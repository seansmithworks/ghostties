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
 * Verify an inbound webhook request from Switchboard.
 *
 * @param rawBody    - The raw, unparsed request body string.
 * @param header     - The value of the `Switchboard-Signature` header.
 * @param secret     - The endpoint's signing secret (from Switchboard dashboard).
 * @returns VerificationResult — `valid: true` if the signature checks out.
 */
export function verifySignature(
  rawBody: string,
  header: string,
  secret: string,
): VerificationResult {
  const parsed = parseSignatureHeader(header);
  if (!parsed) {
    return { valid: false, reason: "malformed_signature_header" };
  }

  const expected = computeExpectedSignature(rawBody, parsed.timestamp, secret);

  // TODO: Replace string equality with crypto.timingSafeEqual() to prevent
  // timing attacks. An attacker can measure response latency to guess the
  // correct signature byte-by-byte using naive === comparison.
  const matched = parsed.signatures.some((sig) => sig === expected);
  if (!matched) {
    return { valid: false, reason: "signature_mismatch" };
  }

  // TODO: Enforce a replay-window check. Reject payloads where
  // `Date.now() / 1000 - parsed.timestamp` exceeds a tolerance (e.g. 300s).
  // Without this, a captured request can be replayed indefinitely.

  return { valid: true };
}
