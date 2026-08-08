/**
 * Shared AES-256-GCM helpers for card secret decryption.
 *
 * - Production keys are read from environment variables only.
 * - LOCAL tests fall back to a deterministic TEST_ONLY key derived from a
 *   fixed seed. This fallback is logged loudly and must never be used in
 *   the physical pilot.
 */

const LOCAL_TEST_SEED = "TEST_ONLY_NY_V1_LOCAL_SEED";
const LOCAL_TEST_SALT = "TEST_ONLY_NY_V1_LOCAL_SALT";

export type CardKeyVersion = "v1";

export interface EncryptedCardSecret {
  ciphertextB64: string;
  nonce: string;
  authTagB64: string;
}

export async function getCardMasterKey(keyVersion: CardKeyVersion): Promise<CryptoKey> {
  if (keyVersion !== "v1") {
    throw new Error(`UNSUPPORTED_KEY_VERSION: ${keyVersion}`);
  }

  const envKey = Deno.env.get("CARD_MASTER_KEY_v1");
  if (envKey) {
    return importAes256GcmKeyFromBase64(envKey);
  }

  console.warn(
    "WARN: CARD_MASTER_KEY_v1 is not set. Using a deterministic TEST_ONLY key for local development. " +
      "NEVER deploy this fallback to production or the physical pilot.",
  );
  return deriveTestMasterKey();
}

async function importAes256GcmKeyFromBase64(b64: string): Promise<CryptoKey> {
  const raw = base64ToUint8Array(b64);
  if (raw.length !== 32) {
    throw new Error("INVALID_KEY_LENGTH: CARD_MASTER_KEY_v1 must decode to 32 bytes for AES-256.");
  }
  return crypto.subtle.importKey("raw", raw, "AES-GCM", false, ["encrypt", "decrypt"]);
}

async function deriveTestMasterKey(): Promise<CryptoKey> {
  const encoder = new TextEncoder();
  const baseKey = await crypto.subtle.importKey(
    "raw",
    encoder.encode(LOCAL_TEST_SEED),
    "PBKDF2",
    false,
    ["deriveKey"],
  );
  return crypto.subtle.deriveKey(
    {
      name: "PBKDF2",
      salt: encoder.encode(LOCAL_TEST_SALT),
      iterations: 100_000,
      hash: "SHA-256",
    },
    baseKey,
    { name: "AES-GCM", length: 256 },
    false,
    ["encrypt", "decrypt"],
  );
}

export async function aes256GcmDecrypt(
  key: CryptoKey,
  ciphertextB64: string,
  nonce: string,
  authTagB64: string,
): Promise<string> {
  const ciphertext = base64ToUint8Array(ciphertextB64);
  const authTag = base64ToUint8Array(authTagB64);
  const iv = base64ToUint8Array(nonce);

  if (iv.length !== 12) {
    throw new Error("INVALID_NONCE_LENGTH: AES-GCM nonce must be 12 bytes.");
  }
  if (authTag.length !== 16) {
    throw new Error("INVALID_AUTH_TAG_LENGTH: AES-GCM auth tag must be 16 bytes.");
  }

  // Web Crypto AES-GCM expects ciphertext and auth tag concatenated.
  const combined = new Uint8Array(ciphertext.length + authTag.length);
  combined.set(ciphertext, 0);
  combined.set(authTag, ciphertext.length);

  const decrypted = await crypto.subtle.decrypt({ name: "AES-GCM", iv }, key, combined);
  return new TextDecoder().decode(decrypted);
}

export async function aes256GcmEncrypt(
  key: CryptoKey,
  plaintext: string,
): Promise<EncryptedCardSecret> {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const encoded = new TextEncoder().encode(plaintext);
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, key, encoded);

  const combined = new Uint8Array(encrypted);
  const tagStart = combined.length - 16;
  const ciphertext = combined.slice(0, tagStart);
  const tag = combined.slice(tagStart);

  return {
    ciphertextB64: uint8ArrayToBase64(ciphertext),
    nonce: uint8ArrayToBase64(iv),
    authTagB64: uint8ArrayToBase64(tag),
  };
}

function base64ToUint8Array(b64: string): Uint8Array {
  const binary = atob(b64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

function uint8ArrayToBase64(bytes: Uint8Array): string {
  const binary = String.fromCharCode(...bytes);
  return btoa(binary);
}
