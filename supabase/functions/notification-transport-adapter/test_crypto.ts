/**
 * Local crypto tests for the card secret AES-256-GCM implementation.
 *
 * - Roundtrip encrypt → decrypt
 * - Unique nonce per encryption
 * - Tamper detection (wrong nonce)
 * - Wrong-key failure
 *
 * The plaintext secret is compared but never printed.
 */

import { aes256GcmDecrypt, aes256GcmEncrypt, getCardMasterKey } from "./crypto.ts";

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
