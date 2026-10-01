import { assertEquals } from "jsr:@std/assert@1";
import { extractRevealedCardPin } from "./reveal.ts";

Deno.test("returns the PIN from the pgcrypto reveal RPC shape", () => {
  assertEquals(
    extractRevealedCardPin({
      purchase_id: "00000000-0000-4000-8000-000000000001",
      status: "revealed",
      card_pin: " 1234567890 ",
    }),
    "1234567890",
  );
});

Deno.test("rejects the legacy ciphertext-only shape", () => {
  assertEquals(
    extractRevealedCardPin({
      key_version: "v1",
      ciphertext_b64: "AAAA",
      nonce: "BBBB",
      auth_tag_b64: "CCCC",
    }),
    null,
  );
});

Deno.test("rejects empty, non-string or unexpected payloads", () => {
  assertEquals(extractRevealedCardPin(null), null);
  assertEquals(extractRevealedCardPin([]), null);
  assertEquals(extractRevealedCardPin({ status: "revealed", card_pin: "  " }), null);
  assertEquals(extractRevealedCardPin({ status: "revealed", card_pin: 123 }), null);
  assertEquals(extractRevealedCardPin({ status: "denied", card_pin: "1" }), null);
});
