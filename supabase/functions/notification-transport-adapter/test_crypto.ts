/**
 * Local crypto tests for the card secret AES-256-GCM implementation.
 *
 * - Roundtrip encrypt → decrypt
 * - Unique nonce per encryption
 * - Tamper detection (wrong nonce)
 * - Wrong-key failure
 * - The TEST_ONLY key fallback is refused unless explicitly local/test
 *
 * The plaintext secret is compared but never printed.
 */

import {
  aes256GcmDecrypt,
  aes256GcmEncrypt,
  getCardMasterKey,
  isHostedSupabaseUrl,
  isTestKeyAllowed,
} from "./crypto.ts";

// The deterministic TEST_ONLY key needs BOTH the allow flag and an explicit
// non-production marker, and is refused on a hosted Supabase project.
Deno.env.delete("CARD_MASTER_KEY_v1");
Deno.env.delete("SUPABASE_URL");
Deno.env.delete("CARD_CRYPTO_ENVIRONMENT");
Deno.env.set("CARD_CRYPTO_ALLOW_TEST_KEY", "true");

async function expectKeyRefused(label: string): Promise<void> {
  let refused = false;
  try {
    await getCardMasterKey("v1");
  } catch (error) {
    refused = error instanceof Error && error.message.startsWith("CARD_KEY_NOT_CONFIGURED");
  }
  if (!refused) throw new Error(`test key must be refused: ${label}`);
}

// 0a. Allow flag alone is not enough.
if (isTestKeyAllowed()) throw new Error("allow flag alone must not enable the test key");
await expectKeyRefused("allow flag without CARD_CRYPTO_ENVIRONMENT");

// 0b. A production-looking marker is refused.
Deno.env.set("CARD_CRYPTO_ENVIRONMENT", "production");
await expectKeyRefused("CARD_CRYPTO_ENVIRONMENT=production");

// 0c. Hosted Supabase project is refused even with both flags.
Deno.env.set("CARD_CRYPTO_ENVIRONMENT", "test");
for (
  const hostedUrl of [
    "https://abcdefghijklmnop.supabase.co",
    "https://abcdefghijklmnop.supabase.co/",
    "https://ABCDEFGHIJKLMNOP.SUPABASE.CO",
    "https://abcdefghijklmnop.supabase.in",
    "not a url",
  ]
) {
  if (!isHostedSupabaseUrl(hostedUrl)) throw new Error(`must be treated as hosted: ${hostedUrl}`);
  Deno.env.set("SUPABASE_URL", hostedUrl);
  await expectKeyRefused(`SUPABASE_URL=${hostedUrl}`);
}
for (const localUrl of ["http://127.0.0.1:54321", "http://kong:8000", "http://localhost:54321"]) {
  if (isHostedSupabaseUrl(localUrl)) throw new Error(`must be treated as local: ${localUrl}`);
}
if (isHostedSupabaseUrl(undefined)) throw new Error("unset SUPABASE_URL is not hosted");

// 0d. Allow flag must be exactly "true".
Deno.env.set("SUPABASE_URL", "http://127.0.0.1:54321");
Deno.env.set("CARD_CRYPTO_ALLOW_TEST_KEY", "1");
await expectKeyRefused("CARD_CRYPTO_ALLOW_TEST_KEY=1");
console.log("PASS: TEST_ONLY key is refused outside an explicit local/test environment");

Deno.env.set("CARD_CRYPTO_ALLOW_TEST_KEY", "true");
Deno.env.set("CARD_CRYPTO_ENVIRONMENT", "test");

function assertEqual<T>(actual: T, expected: T, message: string): void {
  if (actual !== expected) {
    throw new Error(`${message}: expected ${expected}, got ${actual}`);
  }
}

const key = await getCardMasterKey("v1");
const plaintext = "NY_V1_TEST_SECRET_123456789";

// 1. Roundtrip
const encrypted = await aes256GcmEncrypt(key, plaintext);
const decrypted = await aes256GcmDecrypt(
  key,
  encrypted.ciphertextB64,
  encrypted.nonce,
  encrypted.authTagB64,
);
assertEqual(decrypted, plaintext, "roundtrip decrypt mismatch");
console.log("PASS: encrypt/decrypt roundtrip");

// 2. Unique nonce
const encrypted2 = await aes256GcmEncrypt(key, plaintext);
if (encrypted.nonce === encrypted2.nonce) {
  throw new Error("nonce reuse detected");
}
console.log("PASS: unique nonce per encryption");

// 3. Tamper detection: ciphertext cannot be decrypted with a different nonce
let tamperCaught = false;
try {
  await aes256GcmDecrypt(key, encrypted.ciphertextB64, encrypted2.nonce, encrypted.authTagB64);
} catch {
  tamperCaught = true;
}
if (!tamperCaught) {
  throw new Error("tamper detection failed");
}
console.log("PASS: tamper detection");

// 4. Wrong-key failure
const wrongKey = await crypto.subtle.generateKey(
  { name: "AES-GCM", length: 256 },
  false,
  ["encrypt", "decrypt"],
);
let wrongKeyCaught = false;
try {
  await aes256GcmDecrypt(wrongKey, encrypted.ciphertextB64, encrypted.nonce, encrypted.authTagB64);
} catch {
  wrongKeyCaught = true;
}
if (!wrongKeyCaught) {
  throw new Error("wrong-key failure expected");
}
console.log("PASS: wrong-key failure");

console.log("\nAll card crypto tests passed.");
