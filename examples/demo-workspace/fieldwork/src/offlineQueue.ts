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
}

/** Minimal persistence contract — swap in SQLite, AsyncStorage, etc. */
export interface QueueStore {
  load(): Promise<QueuedSubmission[]>;
  save(items: QueuedSubmission[]): Promise<void>;
}

/** No-op store used in tests and until a real store is injected. */
const noopStore: QueueStore = {
  async load() {
    return [];
  },
  async save(_items) {
    /* noop */
  },
};

export class OfflineQueue {
  private items: QueuedSubmission[] = [];
  private store: QueueStore;
  private endpoint: string;

  constructor(endpoint: string, store: QueueStore = noopStore) {
    this.endpoint = endpoint;
    this.store = store;
  }

  /** Restore persisted queue from the store (call on app launch). */
  async hydrate(): Promise<void> {
    this.items = await this.store.load();
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

  /**
   * Drain the queue. Posts each queued submission to the server in FIFO order.
   * Removes successfully delivered items and persists the remaining queue.
   *
   * TODO: Add exponential-backoff retry. Currently, if a POST fails (network
   * hiccup, 5xx), the item is silently dropped. It should be retried up to
   * N times with delays of 1s, 2s, 4s, 8s… before being moved to a
   * dead-letter bucket. Without this, transient errors cause permanent data loss.
   */
  async flush(): Promise<{ delivered: number; failed: number }> {
    let delivered = 0;
    let failed = 0;
    const remaining: QueuedSubmission[] = [];

    for (const item of this.items) {
      try {
        const response = await fetch(this.endpoint, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(item.submission),
        });

        if (response.ok) {
          delivered++;
        } else {
          // Non-2xx — treat as failure and drop (no retry yet)
          failed++;
        }
      } catch {
        // Network error — drop the item (no retry yet)
        failed++;
      }
    }

    this.items = remaining;
    await this.store.save(this.items);
    return { delivered, failed };
  }
}
