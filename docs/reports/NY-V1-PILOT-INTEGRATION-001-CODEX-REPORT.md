# NY-V1-PILOT-INTEGRATION-001 — Final V1 Source / Local Pilot Closure

## MISSION

Integrate the non-commerce and commerce V1 baselines into one Arabic RTL product, close all provider-neutral source paths permitted by governance, prove local Supabase E2E/authorization/financial/security behavior, create reproducible TEST_ONLY pilot data, and produce an internal debug APK. No production or remote Supabase activity occurred.

## STARTING_SHA

`307bf11d544a9624364bc266a8d590aef4a0f090` (`origin/codex/NY-V1-NONCOMMERCE-INTEGRATION-001`)

## ENDING_SHA

Tested source baseline: `df714f843369de7b29d32ec81e5cbc0d348ca1ab`.

The documentation commit containing this report is intentionally excluded from the tested source SHA; it changes no runtime source, schema, tests, or build inputs.

## INTEGRATED_BRANCHES

| Branch | Integrated SHA | Result |
|---|---:|---|
| `origin/codex/NY-V1-NONCOMMERCE-INTEGRATION-001` | `307bf11d544a9624364bc266a8d590aef4a0f090` | Baseline |
| `origin/kimi/NY-V1-COMMERCE-CORE-001` | `c235f67e14cb83349e64e4d5014644da2bda8355` | Merged with `182d7e9`; shared Flutter files resolved semantically |

Published history was not rewritten. The duplicate commerce SQL sequence `011` was moved forward to `013`; notification `011` and support `012` were retained.

## MIGRATION_MANIFEST

| Order | Migration | Domain |
|---:|---|---|
| 1 | `20260727090000_netyemen_core_identity_and_networks.sql` | Identity, roles, networks, aliases |
| 2 | `20260727091000_netyemen_core_rls_and_audit.sql` | RLS, authorization helpers, immutable audit |
| 3 | `20260727130000_netyemen_network_addition_requests.sql` | Network requests |
| 4 | `20260728090000_netyemen_network_packages.sql` | Package catalog |
| 5 | `20260728091000_netyemen_package_inventory.sql` | Idempotent inventory |
| 6 | `20260729090000_netyemen_admin_operations.sql` | Admin operations |
| 7 | `20260729095000_netyemen_commerce_core.sql` | Wallet, deposits, purchase, fulfillment/refund/settlement hooks |
| 8 | `20260730090000_netyemen_acl_hardening.sql` | Client ACL/default privilege hardening |
| 9 | `20260730100000_netyemen_notifications_engagement.sql` | Event/outbox/inbox and unbound transport |
| 10 | `20260808090000_netyemen_support_disputes.sql` | Support, complaints, disputes |
| 11 | `20260808100000_netyemen_v1_pilot_integration.sql` | Cross-domain events/audit, purchase disputes, governance holds |

All migration timestamps and SQL suite numbers are unique. Integration corrections are forward-only.

## FEATURE_MATRIX

| Feature | Implemented | Tested | State |
|---|---|---|---|
| Authentication/session | Yes | Flutter + SQL | PASS |
| Public discovery and Wi-Fi privacy | Yes | Flutter + SQL | PASS |
| Network addition request/review | Yes | SQL `005/006/008` | PASS |
| Packages and inventory | Yes | Flutter + SQL | PASS |
| Owner/admin operations | Yes | Flutter + SQL | PASS |
| Notifications event/outbox/inbox | Yes | Flutter + SQL | PASS; external transport unbound |
| Support/complaints/disputes | Yes | Flutter + SQL | PASS |
| Wallet and deposits | Yes | Flutter + SQL | PASS; local manual review only |
| Atomic purchase and fulfillment boundary | Yes | SQL + concurrency | PASS; fulfillment fail-closed |
| Finance summaries/refund hooks | Yes | SQL | PASS |
| Settlement references | Yes | SQL | PASS; commission/net/payout held |
| Reproducible local seed | Yes | Integrated verifier | PASS |
| Android debug APK | Yes | Gradle/JDK 17 | PASS |

Customer navigation provides الرئيسية، الشبكات، المحفظة، المشتريات، الحساب, with الطلبات، الإيداعات، الإشعارات، الدعم والشكاوى reachable from the account hub. Network operations are role-gated; finance/admin/support/audit operations share the existing role-aware operations entry rather than adding a second navigation system.

## ROLE_AUTHORIZATION_MATRIX

| Role | Intended effective access | Proved denied |
|---|---|---|
| `anon` | Public active network/package discovery | Wallet, requests, mutations, audit |
| `customer` | Own profile, requests, wallet/deposits, purchases, inbox, own support | Admin, finance review, inventory mutation, cross-user data |
| `network_owner` | Own networks, packages, inventory, related support, commercial references | Other-owner networks, customer wallet, admin/finance mutation |
| `network_operator` | Assigned network package/inventory operations | Wallet, admin, owner payout data |
| `finance_officer` | Deposit review and finance summaries | Support administration and generic admin bypass |
| `support_agent` | Support queue/disputes and refund review hook | Deposit approval, wallet mutation, network administration |
| `platform_admin` | Explicit admin RPCs and oversight | No generic RLS bypass; still uses explicit contracts |
| `system_auditor` | Read-only audit/oversight | Ledger, inventory, support, admin mutations |
| `service_role` | Trusted audit/notification processing boundaries | Not exposed as a client role |

Evidence: SQL suites `002`, `003`, `007`–`014`, including direct role/RPC/table negative checks. Results include 14 core positive, 30 core negative, 12 core invariant, inventory/admin/notification/support/commerce negatives, and client `TRUNCATE` denial.

## E2E_RESULTS

| ID | Result | Evidence |
|---|---|---|
| E2E-01 | PASS | Fresh auth user creates profile/customer role |
| E2E-02 | PASS | Anonymous active-network discovery |
| E2E-03 | PASS | Request submission/idempotency/admin resolution in `005/006/008` |
| E2E-04 | PASS | Owner package creation contracts |
| E2E-05 | PASS | Idempotent authorized inventory adjustment |
| E2E-06 | PASS | Active public package visibility |
| E2E-07 | PASS | Local deposit request, finance approval, exactly-one wallet credit |
| E2E-08 | PASS | Server-priced atomic purchase |
| E2E-09 | PASS | Two simultaneous last-unit buyers: exactly one success |
| E2E-10 | PASS | Same idempotency key returns same purchase; one debit/stock use |
| E2E-11 | PASS | Reveal raises `FULFILLMENT_VAULT_NOT_CONFIGURED`; no secret payload |
| E2E-12 | PASS | Support dispute stores direct `purchase_id` relationship |
| E2E-13 | PASS | `refund_recommended` support outcome and compensating credit hook |
| E2E-14 | PASS | Deposit/purchase/refund canonical events and outbox; transport unbound |
| E2E-15 | PASS | Integrated audit events visible to authorized admin/auditor roles |

All database E2E activity used `127.0.0.1:54322` / container `supabase_db_netyemen-local`. Test transactions roll back; seed values are explicitly TEST_ONLY.

## FLUTTER

| Command | Result |
|---|---|
| `flutter pub get` | PASS |
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 109 tests |
| `flutter build apk --debug` | PASS under OpenJDK 17.0.20 |

## SQL

`npx supabase db reset --no-seed` passed on the complete 11-migration chain. SQL suites `001` through `014` ran in lexical order through `psql -v ON_ERROR_STOP=1` and all passed.

## VERIFIERS

| Verifier | Result |
|---|---|
| `scripts/verify_netyemen_core_foundation.ps1` | PASS |
| `scripts/verify_netyemen_commerce_v1.ps1` | PASS |
| `scripts/verify_netyemen_v1_pilot.ps1` | PASS |
| Secret scan | PASS |
| Card-secret prohibition scan | PASS |
| Financial invariant scan | PASS |
| `git diff --check` | PASS |

## FINANCIAL_INVARIANTS

- Wallet balance has a database non-negative constraint and is mutated only through append-only ledger-triggered paths.
- Ledger client update/delete/truncate is denied; refunds add compensating CREDIT entries and preserve original DEBIT entries.
- Deposit review locks the request and produces exactly one referenced credit; replay is no-op.
- Purchase price comes only from the locked server package row; the RPC accepts no client price.
- Wallet and inventory rows are locked; inventory constraints and movements prevent negative stock.
- Last-unit concurrency produced one success and one `OUT_OF_STOCK` failure.
- Purchase idempotency produced one purchase, one debit, and one inventory decrement.
- No commission percentage is selected. Gross owner accounting reference is preserved while commission/net/status remain `NULL`/`awaiting_policy` until OD-FIN-02 and OD-SETTLE-01 approval.

## SECURITY

- RLS is enabled and forced where applicable; role behavior is exercised as `anon`, `authenticated`, and `service_role`, not UI-only.
- `SECURITY DEFINER` functions use fixed `public, pg_temp` search paths and explicit execute grants/revokes.
- `auth.uid()` is authoritative; RPCs do not accept actor/user IDs for customer financial actions.
- No client `TRUNCATE`, generic admin bypass, client ledger write, card secret, provider credential, or Flutter-embedded provider secret was found.
- Fulfillment stores no plaintext/encrypted card payload; vault fields remain null and reveal fails closed.
- Notification transport is explicitly `unbound`; outbox processing cannot claim external delivery.
- Wi-Fi discovery continues to exclude BSSID, hardware identifiers, coordinates, and credentials.
- Audit rows and support messages/notes/events are immutable.

## PILOT_SEED

`supabase/seed.sql` creates eight synthetic identities: two customers, owner, operator, finance officer, support agent, platform admin, and system auditor. It adds two TEST_ONLY networks, two aliases, three packages, inventory `25/10/1`, one pending deposit, one support case, and synthetic wallet balances totaling 12,000 TEST_ONLY YER.

No bank/card credentials or real account/provider data exist. `scripts/reset_netyemen_local_pilot.ps1` enforces a loopback DB URL, resets with `--no-seed`, applies the seed, and is repeatable.

## PILOT_APK

- Artifact: `build/app/outputs/flutter-apk/app-debug.apk`
- Size: `152424078` bytes
- SHA-256: `02089080B8B6832C40A038B2FC929EA1FDAD1763B61D7A83D6BB7EFD5F11B9A2`
- Type: debug/internal pilot only
- Device install check: NOT RUN — `adb` is not installed/available on this workstation
- Play Store publication: NOT PERFORMED

## OWNER_DECISION_PACKAGE_V1

The owner can close all remaining scoped decisions in one response using the response template after the table.

### OD-NOTIF-01

- **QUESTION:** Which external push transport should bind to the existing event/outbox/inbox architecture?
- **OPTION A:** FCM through a server-side adapter/Edge Function.
- **OPTION B:** OneSignal server-side adapter and SDK.
- **OPTION C:** In-app inbox/polling only.
- **RECOMMENDED OPTION:** A, subject to owner approval and server-side secret provisioning.
- **WHY:** Native Android fit, mature delivery path, and no need to replace the provider-neutral domain architecture.
- **COST / COMPLEXITY:** Medium setup; low-to-medium recurring cost at pilot scale.
- **SECURITY IMPACT:** Service credentials must remain server-side; token lifecycle and least-privilege adapter access required.
- **USER EXPERIENCE IMPACT:** Timely background deposit/support/purchase status alerts; C has delayed alerts.
- **CLASSIFICATION:** `BLOCKS_SOURCE=NO`; `BLOCKS_LOCAL_PILOT=NO`; `BLOCKS_EXTERNAL_PILOT=YES` if background push is acceptance-critical; `BLOCKS_PRODUCTION=YES`.

### OD-FIN-01

- **QUESTION:** How are customer deposit proofs verified and what SLA applies?
- **OPTION A:** Manual receipt/reference review by finance officer.
- **OPTION B:** OCR-assisted extraction with manual approval.
- **OPTION C:** Direct approved financial-institution API.
- **RECOMMENDED OPTION:** A for V1 external pilot, with a documented staffing/SLA limit; evaluate B after real workload data.
- **WHY:** It matches the implemented controlled queue and avoids pretending a bank API exists.
- **COST / COMPLEXITY:** Low engineering, medium recurring operations; B/C increase engineering/compliance cost.
- **SECURITY IMPACT:** Requires dual-control procedures, proof retention policy, fraud checks, and finance-only approval.
- **USER EXPERIENCE IMPACT:** Slower than API credit; clear pending/rejected/approved states are already supported.
- **CLASSIFICATION:** `BLOCKS_SOURCE=NO`; `BLOCKS_LOCAL_PILOT=NO`; `BLOCKS_EXTERNAL_PILOT=YES`; `BLOCKS_PRODUCTION=YES`.

### OD-FIN-02

- **QUESTION:** What platform commission model and value apply to a purchase?
- **OPTION A:** Configurable percentage commission.
- **OPTION B:** Configurable fixed fee by denomination/package.
- **OPTION C:** Owner subscription plus lower transaction commission.
- **RECOMMENDED OPTION:** A for operational simplicity, but the percentage must be explicitly approved; source does not assume 5%.
- **WHY:** Simple reconciliation and transparent owner statements while remaining configurable and effective-dated.
- **COST / COMPLEXITY:** Low-to-medium for A; medium for B; high billing complexity for C.
- **SECURITY IMPACT:** Rates require versioning, maker/checker approval, immutable snapshots, and audit.
- **USER EXPERIENCE IMPACT:** Indirect customer impact; major owner margin/transparency impact.
- **CLASSIFICATION:** `BLOCKS_SOURCE=NO`; `BLOCKS_LOCAL_PILOT=NO`; `BLOCKS_EXTERNAL_PILOT=YES` for real-money settlement; `BLOCKS_PRODUCTION=YES`.

### OD-FIN-03

- **QUESTION:** Which official receiving accounts/channels may appear in the deposit directory?
- **OPTION A:** Finance-managed configuration directory; approve each provider/account separately.
- **OPTION B:** Hardcode accounts in the client.
- **OPTION C:** Launch external pilot without deposits.
- **RECOMMENDED OPTION:** A. Return the approved channel names, account labels/numbers, limits, and active dates separately through a secure operational process.
- **WHY:** Accounts can be disabled without an APK release and the client never becomes the source of truth.
- **COST / COMPLEXITY:** Low engineering; ongoing finance governance.
- **SECURITY IMPACT:** Prevents stale/fraudulent destinations; sensitive operational changes need audit and dual control.
- **USER EXPERIENCE IMPACT:** Accurate available channels and fewer failed deposits.
- **CLASSIFICATION:** `BLOCKS_SOURCE=NO`; `BLOCKS_LOCAL_PILOT=NO`; `BLOCKS_EXTERNAL_PILOT=YES`; `BLOCKS_PRODUCTION=YES`.

### OD-CARD-01

- **QUESTION:** Where and how are card/voucher secrets stored and released?
- **OPTION A:** `pgcrypto` column encryption with server-held key.
- **OPTION B:** External vault/KMS boundary with one-time server-side retrieval.
- **OPTION C:** Application-level encryption before database insertion.
- **RECOMMENDED OPTION:** B where an approved vault is operationally available; A only with a reviewed database-key rotation/runbook. Do not use C in mobile clients.
- **WHY:** B gives the strongest separation from the marketplace database and matches the implemented fail-closed boundary.
- **COST / COMPLEXITY:** High for B; medium for A; high and unsafe key-distribution complexity for C.
- **SECURITY IMPACT:** Critical. Requires key rotation, access audit, one-time reveal controls, masking, and incident response.
- **USER EXPERIENCE IMPACT:** Enables real fulfillment; until bound, purchases remain visibly awaiting fulfillment.
- **CLASSIFICATION:** `BLOCKS_SOURCE=NO`; `BLOCKS_LOCAL_PILOT=NO`; `BLOCKS_EXTERNAL_PILOT=YES`; `BLOCKS_PRODUCTION=YES`.

### OD-CARD-02

- **QUESTION:** What dispute/quarantine window applies after fulfillment?
- **OPTION A:** 12 hours.
- **OPTION B:** 24 hours.
- **OPTION C:** 48 hours.
- **RECOMMENDED OPTION:** B, with required failure reason and fraud/rate controls.
- **WHY:** Balanced customer testing time and owner settlement exposure.
- **COST / COMPLEXITY:** Low engineering; support workload grows with longer windows.
- **SECURITY IMPACT:** Longer windows increase abuse exposure; shorter windows increase unfair rejection risk.
- **USER EXPERIENCE IMPACT:** B provides a clear, reasonable complaint period.
- **CLASSIFICATION:** `BLOCKS_SOURCE=NO`; `BLOCKS_LOCAL_PILOT=NO`; `BLOCKS_EXTERNAL_PILOT=YES` for real fulfillment disputes; `BLOCKS_PRODUCTION=YES`.

### OD-SETTLE-01

- **QUESTION:** When do owners become payable and how are payouts authorized/executed?
- **OPTION A:** Weekly batch plus approved minimum threshold.
- **OPTION B:** Threshold-triggered batches.
- **OPTION C:** Owner-requested payouts with finance SLA.
- **RECOMMENDED OPTION:** A, with the weekday, minimum threshold, dispute hold, maker/checker approval, and payout channel explicitly supplied by the owner.
- **WHY:** Predictable reconciliation and liquidity planning; source already holds immutable gross references without executing payouts.
- **COST / COMPLEXITY:** Medium finance operations and reconciliation automation.
- **SECURITY IMPACT:** Requires dual authorization, frozen disputed items, immutable vouchers, and no client payout execution.
- **USER EXPERIENCE IMPACT:** Predictable owner cash flow; small balances may roll forward.
- **CLASSIFICATION:** `BLOCKS_SOURCE=NO`; `BLOCKS_LOCAL_PILOT=NO`; `BLOCKS_EXTERNAL_PILOT=YES` for owner payouts; `BLOCKS_PRODUCTION=YES`.

**ONE-RESPONSE OWNER TEMPLATE:** `OD-NOTIF-01=<A|B|C>; OD-FIN-01=<A|B|C + SLA/proof rules>; OD-FIN-02=<A|B|C + exact effective-dated rate/fees>; OD-FIN-03=<A|B|C + approved channels via secure handoff>; OD-CARD-01=<A|B + key/vault owner>; OD-CARD-02=<A|B|C>; OD-SETTLE-01=<A|B|C + day/threshold/hold/approval rules>`.

## V1_GAP_MATRIX

| REQUIREMENT | IMPLEMENTED | TESTED | BLOCKED_BY_GOVERNANCE | DEFERRED_V1_5 |
|---|---|---|---|---|
| Complete V1 source domains/navigation | Yes | Yes | No | No |
| Local auth/discovery/request flow | Yes | Yes | No | No |
| Local wallet/deposit/purchase flow | Yes | Yes | External verification policy only | No |
| Atomic inventory and retry | Yes | Yes | No | No |
| Real card fulfillment | Provider-neutral boundary only | Fail-closed tested | OD-CARD-01 | No |
| External push delivery | Event/outbox/inbox only | Unbound tested | OD-NOTIF-01 | No |
| Real receiving accounts | Configuration schema only | Empty/unbound | OD-FIN-03 | No |
| Commission/net settlement calculation | Gross reference only | Policy hold tested | OD-FIN-02 | No |
| Real payout execution | No; references only | No-execution boundary tested | OD-SETTLE-01 | No |
| Dispute window enforcement against fulfilled card | Hook/data boundary | Local recommendation/refund tested | OD-CARD-02 | No |
| OCR/direct bank API | No | N/A | Optional OD-FIN-01 choice | Yes if manual V1 chosen |
| Production deployment/store publishing | No | N/A | All production decisions/security operations | No |

## OPEN_GOVERNANCE

`OD-NOTIF-01`, `OD-FIN-01`, `OD-FIN-02`, `OD-FIN-03`, `OD-CARD-01`, `OD-CARD-02`, and `OD-SETTLE-01` remain open. Recommendations above are not approvals and no provider, account, percentage, key architecture, dispute duration, or payout schedule was silently bound.

## PRODUCTION_BLOCKERS

- Owner approval and secure implementation/operations for all seven decisions above.
- Production environment threat review, key/secret provisioning, backup/restore drill, monitoring/alerting, incident response, reconciliation, finance maker/checker controls, privacy/retention/legal approval, and load testing.
- Real provider contracts/accounts and end-to-end sandbox certification.
- Signed release build, device matrix/accessibility testing, store compliance, and release approval.

## FINAL_DECISION

**PASS_WITH_GOVERNANCE_HOLD**

The integrated V1 source and local-pilot baseline pass. It is suitable only for local/internal TEST_ONLY pilot work. External pilot and production remain held at the explicit governance/provider boundaries above. No production read/write, remote Supabase operation, deployment, publication, or merge was performed.
