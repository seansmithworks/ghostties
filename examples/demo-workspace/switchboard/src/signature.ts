/**
 * Switchboard — Webhook HMAC Signature Verification
 *
 * Verifies inbound webhook payloads using HMAC-SHA256.
 * Signing scheme: `t=<timestamp>,v1=<hex-hmac>` (compatible with Stripe-style headers).
 */

import * as crypto from "crypto";

export interface VerificationResult {
  valid: boolean;
  reason?: string;
}

export interface SignatureHeader {
  timestamp: number;
  signatures: string[];
}

/**
 * Parse a Switchboard signature header of the form:
 *   `t=1717200000,v1=abc123...,v1=def456...`
 *
 * Returns the Unix timestamp and all v1 signature values.
 */
export function parseSignatureHeader(header: string): SignatureHeader | null {
  const parts = header.split(",");
  let timestamp: number | null = null;
  const signatures: string[] = [];

  for (const part of parts) {
    const [key, value] = part.trim().split("=");
    if (key === "t") {
      const parsed = parseInt(value, 10);
      if (isNaN(parsed)) return null;
      timestamp = parsed;
    } else if (key === "v1") {
      signatures.push(value);
    }
  }

  if (timestamp === null || signatures.length === 0) return null;
  return { timestamp, signatures };
}

/**
 * Compute the expected HMAC-SHA256 signature for a given payload + timestamp.
 * Signed payload format: `<timestamp>.<raw-body>`
 */
function computeExpectedSignature(
  rawBody: string,
  timestamp: number,
  secret: string,
): string {
  const signedPayload = `${timestamp}.${rawBody}`;
  return crypto
    .createHmac("sha256", secret)
    .update(signedPayload, "utf8")
    .digest("hex");
}

/**
 * Compare a candidate signature against the expected one in constant time.
 *
 * `crypto.timingSafeEqual` throws on length mismatch, so length is checked
 * first. The length of the candidate is attacker-supplied and the expected
 * length (64 hex chars) is public, so the early return leaks nothing useful.
 */
function signaturesMatch(candidate: string, expected: string): boolean {
  const candidateBuf = Buffer.from(candidate, "utf8");
  const expectedBuf = Buffer.from(expected, "utf8");
  if (candidateBuf.length !== expectedBuf.length) return false;
  return crypto.timingSafeEqual(candidateBuf, expectedBuf);
}

/** Default replay tolerance: 5 minutes, matching Stripe's recommendation. */
export const DEFAULT_TOLERANCE_SECONDS = 300;

/**
 * Verify an inbound webhook request from Switchboard.
 *
 * @param rawBody    - The raw, unparsed request body string.
 * @param header     - The value of the `Switchboard-Signature` header.
 * @param secret     - The endpoint's signing secret (from Switchboard dashboard).
 * @param toleranceSeconds - Max allowed age (and future clock skew) of the
 *                     signed timestamp; defaults to 300s.
 * @returns VerificationResult — `valid: true` if the signature checks out.
 */
export function verifySignature(
  rawBody: string,
  header: string,
  secret: string,
  toleranceSeconds: number = DEFAULT_TOLERANCE_SECONDS,
): VerificationResult {
  const parsed = parseSignatureHeader(header);
  if (!parsed) {
    return { valid: false, reason: "malformed_signature_header" };
  }

  const expected = computeExpectedSignature(rawBody, parsed.timestamp, secret);

  const matched = parsed.signatures.some((sig) =>
    signaturesMatch(sig, expected),
  );
  if (!matched) {
    return { valid: false, reason: "signature_mismatch" };
  }

  // Replay-window check: a captured request must not be replayable outside
  // the tolerance window. Also rejects timestamps too far in the future,
  // which only occur with forged headers or severe clock skew.
  const nowSeconds = Math.floor(Date.now() / 1000);
  if (Math.abs(nowSeconds - parsed.timestamp) > toleranceSeconds) {
    return { valid: false, reason: "timestamp_out_of_tolerance" };
  }

  return { valid: true };
}
