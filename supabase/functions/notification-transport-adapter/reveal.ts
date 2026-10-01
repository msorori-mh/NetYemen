// Parses the result of public.reveal_purchase_card_secret (final definition in
// 20260908120000_card_pgcrypto.sql). The RPC decrypts inside Postgres and
// returns { purchase_id, status: 'revealed', card_pin }; it never returns
// ciphertext. Returns the trimmed PIN, or null when the payload is unusable.
export function extractRevealedCardPin(data: unknown): string | null {
  if (data === null || typeof data !== "object" || Array.isArray(data)) {
    return null;
  }
  const record = data as Record<string, unknown>;
  if (record.status !== "revealed") return null;
  const pin = record.card_pin;
  if (typeof pin !== "string") return null;
  const trimmed = pin.trim();
  return trimmed ? trimmed : null;
}
