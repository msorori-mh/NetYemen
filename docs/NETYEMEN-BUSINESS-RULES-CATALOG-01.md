# NETYEMEN BUSINESS RULES CATALOG (V1.0)

**Task ID:** NY-PRODUCT-001  
**Document Code:** `NETYEMEN-BUSINESS-RULES-CATALOG-01.md`  
**Classification:** `PROPOSED_CONTRACT`  
**Scope:** Core Platform Business Logic, Financial Controls, and Data Rules  

---

## 1. Domain 1: Authentication & User Accounts (`BR-AUTH`)

* **BR-AUTH-001 [Yemen Phone Normalization]:** All user phone numbers must be formatted and stored in normalized E.164 format `+9677XXXXXXXX`. Local inputs without country code must be prepended with `+967` after validating that the number consists of 9 digits starting with `77`, `78`, `73`, `71`, or `70`. (`PROPOSED_CONTRACT`)
* **BR-AUTH-002 [OTP Expiration & Resend Limits]:** SMS OTP tokens expire exactly 300 seconds (5 minutes) after issuance. A user may only request a new OTP after a 60-second cooldown period. Max 5 failed OTP attempts are allowed per phone number per hour before temporary block. (`PROPOSED_CONTRACT`)
* **BR-AUTH-003 [Automatic Profile Provisioning]:** Upon successful OTP verification of a new phone number, the backend database trigger (`on auth.users create`) must automatically create a matching `users` profile record with `wallet_balance = 0` and `role = 'customer'`. Client-side direct table creation is forbidden. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)
* **BR-AUTH-004 [Session Token Expiration]:** JWT user session tokens expire after 30 days. Session refresh must occur automatically in the background if the user account remains active. (`PROPOSED_CONTRACT`)
* **BR-AUTH-005 [Immediate Suspension Session Revocation]:** If a user account status is updated to `suspended`, all active JWT sessions and refresh tokens for that `user_id` must be immediately revoked at the Supabase auth layer. (`PROPOSED_CONTRACT`)
* **BR-AUTH-006 [Multi-Device Session Policy]:** A customer account may maintain up to 3 concurrent active mobile device sessions. Logging in on a 4th device automatically revokes the oldest session. (`PROPOSED_CONTRACT`)
* **BR-AUTH-007 [Account Deletion Grace Period]:** Account deletion requests enter a 30-day `closure_pending` state during which financial reconciliation is completed. Hard deletion of historical wallet ledger entries is strictly forbidden; profile details are anonymized upon closure. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)

---

## 2. Domain 2: Network Owners & Hotspot Infrastructure (`BR-NETWORK`)

* **BR-NETWORK-001 [Owner Identity Verification Requirement]:** Network Owners must submit identity documents (national ID or commercial registration) before creating networks. Network owner profiles remain in `pending_verification` state until approved by Platform Admin. (`PROPOSED_CONTRACT`)
* **BR-NETWORK-002 [Network Approval Gate]:** Newly created networks default to `is_approved = false` and `is_active = false`. Networks cannot be discovered by customers or sell cards until a `PLATFORM_ADMIN` transitions the network state to `approved`. (`PROPOSED_CONTRACT`)
* **BR-NETWORK-003 [Network Ownership Immutability]:** A network belongs to exactly one `NETWORK_OWNER`. Ownership transfer requires multi-signature approval by both current owner and `PLATFORM_ADMIN`. (`PROPOSED_CONTRACT`)
* **BR-NETWORK-004 [Operator Staff Assignment]:** Network Owners may assign up to 5 `NETWORK_OPERATOR` accounts per network to assist with card batch uploads and price management. (`PROPOSED_CONTRACT`)
* **BR-NETWORK-005 [Network Visibility Criteria]:** A network is visible in the customer discovery API if and only if `is_approved = true`, `is_active = true`, and the owner account status is `active`. (`PROPOSED_CONTRACT`)
* **BR-NETWORK-006 [Featured Network Controls]:** Networks may be flagged as `is_featured = true` exclusively by `PLATFORM_ADMIN` for promotional placement. Network owners cannot self-assign featured status. (`PROPOSED_CONTRACT`)
* **BR-NETWORK-007 [Network Suspension Freeze]:** If a network is suspended by Admin (`is_active = false`), ongoing card purchases for that network are immediately blocked. Available card stock is temporarily frozen. (`PROPOSED_CONTRACT`)

---

## 3. Domain 3: Internet Cards & Inventory (`BR-CARD`)

* **BR-CARD-001 [Card Definition]:** An internet card represents a unique access voucher defined by a card number (PIN/Serial). A card belongs to exactly one network and exactly one imported batch. (`VERIFIED_CURRENT_STATE`)
* **BR-CARD-002 [Uniqueness & Duplicate Prevention]:** Card numbers must be unique within a network. Re-importing an existing card number within the same network must be rejected during pre-import validation. (`PROPOSED_CONTRACT`)
* **BR-CARD-003 [Card Lifecycle States]:** A card transitions through strictly defined states: `available` -> `reserved` -> `sold` -> `quarantined` -> `invalid` -> `cancelled`. Direct backwards state transitions are forbidden. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)
* **BR-CARD-004 [Plaintext Card Confidentiality]:** Unsold card numbers (`status = 'available'`) must NEVER be accessible in plaintext to client applications, network owners via API, or third parties. Card numbers are encrypted at rest. (`PROPOSED_CONTRACT`)
* **BR-CARD-005 [Purchaser Reveal Contract]:** Full plaintext card numbers are disclosed exclusively to the verified customer who executed the successful purchase transaction for that specific `card_id`. (`PROPOSED_CONTRACT`)
* **BR-CARD-006 [Card Complaint Quarantine]:** When a customer submits a valid complaint within 24 hours of purchase, the associated card status transitions to `quarantined` pending support investigation. (`PROPOSED_CONTRACT`)
* **BR-CARD-007 [Batch Import Atomicity]:** Importing a card batch CSV/text file operates inside a single transaction. If > 5% of lines contain format or duplicate errors, the entire batch import is aborted. (`PROPOSED_CONTRACT`)

---

## 4. Domain 4: Customer Wallet & Ledger (`BR-WALLET`)

* **BR-WALLET-001 [Non-Negative Balance Invariant]:** Customer wallet balance must never be negative (`wallet_balance >= 0`). Any transaction attempting to reduce balance below 0 must fail database check constraints and abort. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)
* **BR-WALLET-002 [Append-Only Financial Ledger]:** Wallet balances are derived from immutable append-only ledger entries (`wallet_ledger_entries`). Direct SQL `UPDATE` or `DELETE` on ledger rows is strictly forbidden. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)
* **BR-WALLET-003 [Deposit Approval Workflow]:** Wallet deposit requests require manual receipt image verification by a `FINANCE_OFFICER`. Approval creates a ledger `CREDIT` entry and updates closing balance. (`PROPOSED_CONTRACT`)
* **BR-WALLET-004 [Deposit Rejection Rationale]:** Rejected deposit requests require a documented reason code (e.g., "Invalid reference number", "Unreadable receipt"). Customer receives instant notification. (`PROPOSED_CONTRACT`)
* **BR-WALLET-005 [Compensating Reversal Entries]:** Financial corrections or deposit reversals MUST be recorded as new compensating ledger entries (`REVERSAL`). Deleting historical records is forbidden. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)
* **BR-WALLET-006 [Currency Standard]:** All wallet accounts, prices, deposits, and payouts are denominated in Yemeni Rial (YER). Fractional currency units are rounded to nearest whole YER. (`PROPOSED_CONTRACT`)

---

## 5. Domain 5: Card Purchase Transactions (`BR-PURCHASE`)

* **BR-PURCHASE-001 [Atomic Purchase Transaction]:** Card purchase must be executed as a single atomic database RPC (`purchase_card`). The transaction must validate balance, lock one available card (`FOR UPDATE`), deduct wallet balance, mark card sold, and write purchase log. (`PROPOSED_CONTRACT`)
* **BR-PURCHASE-002 [Idempotency Key Enforcement]:** Every purchase RPC call requires a client-generated UUID `idempotency_key`. Resubmitting an identical key returns the original purchase result without re-executing debit. (`PROPOSED_CONTRACT`)
* **BR-PURCHASE-003 [Server-Enforced Price]:** Card purchase price is fetched directly from the database `network_prices` table. Client-supplied price arguments are ignored to prevent price tampering. (`PROPOSED_CONTRACT`)
* **BR-PURCHASE-004 [Implicit Auth Identity]:** The buyer identity is extracted from `auth.uid()`. Passing arbitrary `user_id` client parameters to purchase RPC is forbidden and rejected. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)
* **BR-PURCHASE-005 [Post-Commit Notification]:** Purchase confirmation push notifications and events are triggered ONLY AFTER the database transaction successfully commits. (`PROPOSED_CONTRACT`)

---

## 6. Domain 6: Refunds & Dispute Management (`BR-REFUND`)

* **BR-REFUND-001 [Dispute Eligibility Window]:** Customers may request a card refund within 24 hours of purchase if the card PIN is invalid or already consumed on the local hotspot. (`PROPOSED_CONTRACT`)
* **BR-REFUND-002 [Refund Execution]:** Approved refunds generate a compensating `CREDIT` ledger entry to the customer wallet and update card status to `quarantined` or `invalid`. (`PROPOSED_CONTRACT`)
* **BR-REFUND-003 [Owner Chargeback]:** Refunds for invalid cards uploaded by an owner are debited from the owner's pending settlement balance during reconciliation. (`PROPOSED_CONTRACT`)

---

## 7. Domain 7: Owner Settlements & Payouts (`BR-SETTLEMENT`)

* **BR-SETTLEMENT-001 [Net Payable Formula]:** Owner settlement equals total eligible sold cards minus platform commission (e.g., 5%) minus approved customer refunds minus prior adjustments. (`PROPOSED_CONTRACT`)
* **BR-SETTLEMENT-002 [Minimum Payout Threshold]:** Owner payouts are processed when net payable reaches a minimum threshold of 10,000 YER or on a semi-monthly schedule. (`PROPOSED_CONTRACT`)
* **BR-SETTLEMENT-003 [Four-Eyes Payout Approval]:** Settlement payout vouchers above 100,000 YER require creation by a `FINANCE_OFFICER` and final payout approval by `PLATFORM_ADMIN`. (`PROPOSED_CONTRACT`)

---

## 8. Domain 8: Platform Support & Case Operations (`BR-SUPPORT`)

* **BR-SUPPORT-001 [Ticket Assignment & Lifecycle]:** Customer support tickets are assigned to `SUPPORT_AGENT` personnel. Agents can communicate with customers and request card verification. (`PROPOSED_CONTRACT`)
* **BR-SUPPORT-002 [Restricted Card Reveal in Support]:** A support agent may view a full card PIN ONLY within an active, assigned support ticket context. Uncontextual card lookup by support agents is logged as a security alert. (`PROPOSED_CONTRACT`)

---

## 9. Domain 9: Administration & Role Governance (`BR-ADMIN`)

* **BR-ADMIN-001 [Role Assignment Authority]:** Platform roles (`FINANCE_OFFICER`, `SUPPORT_AGENT`, `SYSTEM_AUDITOR`) can only be assigned or revoked by a `PLATFORM_ADMIN`. (`PROPOSED_CONTRACT`)
* **BR-ADMIN-002 [Commercial RPC Admin Non-Bypass]:** System administrators CANNOT bypass commercial purchase RPC checks (e.g., cannot buy cards without wallet balance or force-reveal cards without purchase). (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)

---

## 10. Domain 10: Audit Logging & System Compliance (`BR-AUDIT`)

* **BR-AUDIT-001 [Immutable Audit Trail]:** All administrative actions, role updates, wallet approvals, card quarantine events, and security exceptions are recorded in an append-only `audit_logs` table. (`PROPOSED_CONTRACT`)
* **BR-AUDIT-002 [Audit Log Modification Ban]:** No user, including `PLATFORM_ADMIN` or database superuser, may modify or delete records in `audit_logs`. (`PROPOSED_CONTRACT` / `FORBIDDEN_BEHAVIOR`)
