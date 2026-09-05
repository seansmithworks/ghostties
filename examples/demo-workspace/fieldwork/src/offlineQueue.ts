/**
 * Fieldwork — Offline Form Submission Queue
 *
 * Buffers form submissions locally when the device has no connectivity
 * and drains them to the server in FIFO order once a connection is restored.
 */

export interface FormSubmission {
  formId: string;
  schemaVersion: number;
  respondentId: string;
  fields: Record<string, unknown>;
  gpsCoordinates?: { lat: number; lng: number; accuracyMeters: number };
  capturedAt: string; // ISO-8601
}

export interface QueuedSubmission {
  id: string;
  submission: FormSubmission;
  enqueuedAt: string; // ISO-8601
  attempts: number;
  lastError?: string;
}

/** A submission that exhausted its retries (or was rejected outright). */
export interface DeadLetteredSubmission extends QueuedSubmission {
  deadLetteredAt: string; // ISO-8601
  reason: string;
}

/** Minimal persistence contract — swap in SQLite, AsyncStorage, etc. */
export interface QueueStore {
  load(): Promise<QueuedSubmission[]>;
  save(items: QueuedSubmission[]): Promise<void>;
  /** Optional: persist the dead-letter bucket. In-memory only if omitted. */
  loadDeadLetters?(): Promise<DeadLetteredSubmission[]>;
  saveDeadLetters?(items: DeadLetteredSubmission[]): Promise<void>;
}

export interface RetryOptions {
  /** Max delivery attempts per item before it is dead-lettered. */
  maxAttempts: number;
  /** First retry delay; doubles on each subsequent retry (1s, 2s, 4s, 8s…). */
  baseDelayMs: number;
  /** Ceiling on any single retry delay. */
  maxDelayMs: number;
}

const defaultRetryOptions: RetryOptions = {
  maxAttempts: 5,
  baseDelayMs: 1_000,
  maxDelayMs: 30_000,
};

/** No-op store used in tests and until a real store is injected. */
const noopStore: QueueStore = {
  async load() {
    return [];
  },
  async save(_items) {
    /* noop */
  },
};

const sleep = (ms: number) =>
  ms > 0
    ? new Promise<void>((resolve) => setTimeout(resolve, ms))
    : Promise.resolve();

/** Outcome of trying to deliver one item, including retries. */
type DeliveryOutcome = "delivered" | "dead" | "offline";

export class OfflineQueue {
  private items: QueuedSubmission[] = [];
  private deadLetters: DeadLetteredSubmission[] = [];
  private store: QueueStore;
  private endpoint: string;
  private retry: RetryOptions;

  constructor(
    endpoint: string,
    store: QueueStore = noopStore,
    retry: Partial<RetryOptions> = {},
  ) {
    this.endpoint = endpoint;
    this.store = store;
    this.retry = { ...defaultRetryOptions, ...retry };
  }

  /** Restore persisted queue from the store (call on app launch). */
  async hydrate(): Promise<void> {
    this.items = await this.store.load();
    this.deadLetters = (await this.store.loadDeadLetters?.()) ?? [];
  }

  /** Add a new submission to the tail of the queue and persist immediately. */
  async enqueue(submission: FormSubmission): Promise<void> {
    const queued: QueuedSubmission = {
      id: `${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
      submission,
      enqueuedAt: new Date().toISOString(),
      attempts: 0,
    };
    this.items.push(queued);
    await this.store.save(this.items);
  }

  /** How many submissions are waiting to be flushed. */
  get size(): number {
    return this.items.length;
  }

  /** Submissions that exhausted retries or were rejected by the server. */
  get deadLettered(): readonly DeadLetteredSubmission[] {
    return this.deadLetters;
  }

  /**
   * Drain the queue. Posts each queued submission to the server in FIFO order.
   *
   * Failed POSTs are retried with exponential backoff (baseDelayMs doubling
   * per attempt, capped at maxDelayMs) up to maxAttempts:
   * - 2xx           → delivered, removed from the queue.
   * - 4xx           → dead-lettered immediately (the payload is bad; retrying
   *                   cannot fix it).
   * - 5xx           → retried; dead-lettered once attempts are exhausted.
   * - network error → retried; if attempts are exhausted the device is
   *                   presumed offline, so the item stays queued and the
   *                   flush stops. Nothing is dead-lettered for lost
   *                   connectivity — the next reconnect flushes it again.
   *
   * The queue is persisted after every item so a crash mid-flush cannot
   * lose state.
   */
  async flush(): Promise<{
    delivered: number;
    failed: number;
    deadLettered: number;
  }> {
    let delivered = 0;
    let deadLettered = 0;

    while (this.items.length > 0) {
      const item = this.items[0];
      const outcome = await this.deliverWithRetry(item);

      if (outcome === "offline") {
        // Connectivity is gone — keep this item and everything behind it.
        await this.store.save(this.items);
        break;
      }

      this.items.shift();
      if (outcome === "delivered") {
        delivered++;
      } else {
        deadLettered++;
        this.deadLetters.push({
          ...item,
          deadLetteredAt: new Date().toISOString(),
          reason: item.lastError ?? "unknown",
        });
        await this.store.saveDeadLetters?.(this.deadLetters);
      }
      await this.store.save(this.items);
    }

    return { delivered, failed: this.items.length, deadLettered };
  }

  /**
   * Attempt to POST one item, retrying with exponential backoff until it
   * succeeds, is deemed undeliverable, or the device appears to be offline.
   */
  private async deliverWithRetry(
    item: QueuedSubmission,
  ): Promise<DeliveryOutcome> {
    while (true) {
      item.attempts++;
      let response: Response;

      try {
        response = await fetch(this.endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(item.submission),
        });
      } catch (err) {
        // Network error — likely offline rather than a bad submission.
        item.lastError = err instanceof Error ? err.message : String(err);
        if (item.attempts >= this.retry.maxAttempts) {
          // Reset so the next reconnect gets a full retry budget.
          item.attempts = 0;
          return "offline";
        }
        await sleep(this.backoffDelay(item.attempts));
        continue;
      }

      if (response.ok) {
        return "delivered";
      }

      item.lastError = `HTTP ${response.status}`;

      if (response.status >= 500) {
        // Server error — transient, worth retrying.
        if (item.attempts >= this.retry.maxAttempts) {
          return "dead";
        }
        await sleep(this.backoffDelay(item.attempts));
        continue;
      }

      // 4xx — the server understood and rejected it; retrying cannot help.
      return "dead";
    }
  }

  /** Delay before retry N (1-based): base × 2^(N−1), capped at maxDelayMs. */
  private backoffDelay(attempt: number): number {
    return Math.min(
      this.retry.baseDelayMs * 2 ** (attempt - 1),
      this.retry.maxDelayMs,
    );
  }
}
