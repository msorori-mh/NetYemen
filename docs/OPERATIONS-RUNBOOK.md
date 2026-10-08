# WASEL NET / NetYemen — Operations Runbook

Scope: the recurring and one-off operator tasks of the Supabase backend after
the migrations up to `20261008094000_operations_closure.sql`. Function and
column names are the ones in `supabase/migrations`; when this document and a
migration disagree, the migration is right and this document must be fixed.

All amounts are whole Yemeni rials (YER) stored as integers. Nothing is ever
multiplied or divided by 100.

Conventions used below:

- "SQL editor" means a session as the database owner (`postgres`) — the
  Supabase dashboard SQL editor or `psql` with the database password.
- "service role" means a server-side caller holding the service-role key. That
  key must never be placed in an app, a browser, a repository or a CI artifact.
- Staff RPCs (`finance_*`, `admin_*`) are called by a signed-in staff account
  from one of the admin consoles; they check the caller's role themselves.

---

## 1. Applying migrations

1. Take the release from a reviewed commit on `main` whose CI is green.
2. Dry run first and read the plan:

   ```sh
   npx supabase@2.115.0 link --project-ref <project-ref>
   npx supabase@2.115.0 migration list --linked
   npx supabase@2.115.0 db push --linked --dry-run
   ```

   The `WASEL NET Admin Release Gate` workflow runs the same read-only commands
   and stores their output as evidence.
3. Run the matching `supabase/verification/*_preflight.sql` scripts (read-only)
   where one exists for the release.
4. Apply with `db push --linked` (no `--include-seed`; `supabase/seed.sql`
   refuses to run on anything but a local database and automatic seeding is
   disabled in `supabase/config.toml`).
5. Read the migration output. Lines to look for:
   - `card_vault fingerprint backfill: ...` (section 7),
   - `pg_cron is not enabled: schedule ... externally.` (section 2),
   - any `WARNING`.
6. Run the matching `*_postverify.sql` scripts.

Never run `supabase config push` with `supabase/config.toml`. That file is the
local/CI configuration: it contains fixed test OTP codes and disabled email
confirmation (section 9).

### Settlement batches created before `20261008090000`

Before `20261008090000_settlement_refund_integrity.sql` the refund deductions
of a settlement batch could be wrong in four ways:

- a sale refunded before it was ever settled was still deducted in full, so
  the owner paid back money that had never been credited;
- a refund of a settled sale deducted the gross amount although the owner had
  only received gross minus commission;
- refunds were picked up only for networks that also had new sales in the
  period, otherwise they were not deducted at all;
- refund lines were matched by network, not by the owner who had been paid.

After applying the migrations, finance must review every batch created before
the time the migration was applied:

```sql
SELECT b.id, b.status, b.created_at, b.period_start, b.period_end,
       b.network_id, b.owner_user_id,
       b.gross_sales, b.total_commission, b.total_refunds, b.net_settlement
FROM public.settlement_batches b
WHERE b.created_at < '<timestamp the migration was applied>'
ORDER BY b.created_at;

-- refund lines of one batch
SELECT l.reference_id AS refund_request_id, l.gross_amount, l.commission_amount, l.net_amount
FROM public.settlement_batch_lines l
WHERE l.settlement_batch_id = '<batch-id>' AND l.line_type = 'refund';
```

Batches with `total_refunds <> 0` are the ones that can be wrong; batches of
owners who had refunds in the period but show `total_refunds = 0` may be
missing a deduction. A wrong batch that is still `draft` or `ready_for_review`
is cancelled (section 5) and recreated with the corrected function. A wrong
batch that was already `approved` or `paid` cannot be cancelled: finance
records the difference per owner and settles it with the owner outside the
system. There is no adjustment RPC yet, so keep that record with the batch id.

---

## 2. Scheduled jobs

Two maintenance functions must run periodically. Both are executable by
`service_role` (and the database owner) only.

| Function | Suggested schedule | Returns |
|---|---|---|
| `process_due_account_deletions(p_limit int default 50)` | daily | `{"completed": n, "auth_removal_pending": m}` |
| `radius_close_stale_sessions(p_idle interval default '30 minutes')` | every 10 minutes | `{"closed_stale": n, "expired_authorizations": m}` |

### With pg_cron

If the `pg_cron` extension was already enabled when
`20261008094000_operations_closure.sql` was applied, the migration registered

- `netyemen-account-deletions` — `17 2 * * *` — `SELECT public.process_due_account_deletions(200)`
- `netyemen-radius-stale-sessions` — `*/10 * * * *` — `SELECT public.radius_close_stale_sessions()`

Check with `SELECT jobname, schedule, command, active FROM cron.job;`.

If `pg_cron` is enabled **after** the migration was applied, nothing was
registered. Register the jobs once in the SQL editor:

```sql
SELECT cron.schedule('netyemen-account-deletions', '17 2 * * *',
                     'SELECT public.process_due_account_deletions(200)');
SELECT cron.schedule('netyemen-radius-stale-sessions', '*/10 * * * *',
                     'SELECT public.radius_close_stale_sessions()');
```

Review `cron.job_run_details` weekly for failed runs.

### Without pg_cron

Any scheduler that can keep the service-role key secret (a server cron job, a
scheduled cloud function) calls the RPCs through PostgREST:

```sh
curl -sS -X POST "$SUPABASE_URL/rest/v1/rpc/process_due_account_deletions" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{"p_limit": 200}'

curl -sS -X POST "$SUPABASE_URL/rest/v1/rpc/radius_close_stale_sessions" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d '{}'
```

Do not use GitHub Actions for this unless the key is stored as an environment
secret with required reviewers; a scheduled workflow with the service-role key
is a standing production credential.

Until one of the two is in place, account deletions promised by the privacy
policy are **not carried out**, and RADIUS sessions whose router never sent a
Stop stay `active` indefinitely.

### Account deletion result

`process_due_account_deletions` completes requests whose `scheduled_for` has
passed (30 days after the request): the profile is anonymized, push tokens,
inbox and PIN are deleted, RADIUS credentials are revoked and the wallet is
closed. Purchase, ledger and audit rows are kept for legal retention.

`auth_removal_pending` is the number of requests completed in that run for
which the function could **not** remove the sign-in identity (the `auth`
schema is owned by the platform and the function owner may not be allowed to
write to it). Those accounts are anonymized in `public` but the person could
still sign in. When the value is not `0`:

1. Find them:

   ```sql
   SELECT entity_id AS user_id, occurred_at
   FROM public.audit_events
   WHERE action = 'ACCOUNT_DELETION_COMPLETED'
     AND metadata ->> 'auth_identity_removed' = 'false'
   ORDER BY occurred_at DESC;
   ```

2. For each user, remove the sign-in identity. The auth user row itself cannot
   be hard-deleted while financial records reference it (foreign keys are
   `ON DELETE RESTRICT` on purpose), so scrub it instead, in the SQL editor:

   ```sql
   DELETE FROM auth.sessions   WHERE user_id = '<user-id>';
   DELETE FROM auth.identities WHERE user_id = '<user-id>';
   UPDATE auth.users
   SET email = NULL, phone = NULL, encrypted_password = NULL,
       raw_user_meta_data = '{}'::jsonb, banned_until = 'infinity'
   WHERE id = '<user-id>';
   ```

   If the SQL editor role is also refused, ban the user through the Auth admin
   API (dashboard: Authentication → Users) and open a ticket; do not leave it.
3. Note the user id and date in the privacy log.

If the value is non-zero on every run, the function owner lacks rights on the
`auth` schema in this project; record it as a standing manual step until it is
fixed.

---

## 3. Daily wallet reconciliation

`finance_reconcile_wallets()` compares every wallet's `cached_balance` with the
signed sum of its `customer_wallet_ledger` entries. It returns **only** the
wallets that do not reconcile:

`(user_id, cached_balance, ledger_balance, last_balance_after, ledger_entries)`

An empty result is the healthy state. It is **not scheduled automatically** and
it does not alert anyone: a finance officer, platform admin or auditor must run
it every day (admin console or `SELECT * FROM public.finance_reconcile_wallets();`
in the SQL editor) and record that it was empty.

When it returns rows:

1. Freeze each listed wallet (section 6) so the difference cannot grow.
2. Do not edit `wallet_accounts.cached_balance` and do not touch ledger rows:
   the ledger is append-only by trigger and the cached balance is maintained by
   the ledger trigger.
3. Collect the evidence: the returned row, the wallet's ledger
   (`SELECT * FROM public.customer_wallet_ledger WHERE user_id = '<id>' ORDER BY created_at, id;`)
   and the audit events for that user.
4. Escalate to engineering as a financial incident. `last_balance_after`
   different from `ledger_balance` points at a wrong `balance_after` written by
   an RPC; `cached_balance` different from both points at a write that bypassed
   the ledger.
5. The correction is a new compensating ledger entry made by a reviewed
   migration or script, approved by a second person. There is no adjustment
   RPC.

---

## 4. Deposits

- A deposit request needs a non-empty bank reference and a payment destination.
- `review_wallet_deposit_request(deposit_id, 'approve' | 'reject', reason)`:
  a reviewer can never review their own deposit (`SELF_REVIEW_FORBIDDEN`), and
  the same reference for the same destination is credited once
  (`DUPLICATE_REFERENCE`).
- Dual approval: when the amount is at least
  `deposit_dual_approval_threshold()` (currently 50000 YER), **or** the amount
  plus what the same customer was credited in the previous 24 hours reaches
  it, the first approval only moves the request to `under_review`; a second,
  different reviewer credits the wallet. At least two finance/admin accounts
  must therefore exist and be reachable.

---

## 5. Owner settlement

Statuses: `draft`, `ready_for_review`, `approved`, `paid`, `cancelled`,
`corrected`.

1. **Create** — `finance_create_settlement_batch(period_start, period_end, network_id default null)`.
   One draft batch per owner and network with unsettled completed sales in the
   period, plus refund lines (below). Only one creation run executes at a time.
2. **Approve** — `finance_approve_settlement_batch(batch_id)` by a **different**
   person than the creator (`FORBIDDEN_SELF_APPROVAL`).
3. **Pay** — transfer the money outside the system, then
   `finance_mark_settlement_paid(batch_id, p_notes)` where `p_notes` is the
   payment reference of that transfer. It is required
   (`PAYMENT_REFERENCE_REQUIRED`) and is stored on the batch and in the audit
   event. "Paid" is a status plus this reference; there is no payout ledger and
   the system does not verify that the transfer happened.
4. **Cancel a wrong draft** — `finance_cancel_settlement_batch(batch_id, reason)`
   works for `draft` and `ready_for_review` only and needs a reason. The sales
   go back to the unsettled pool (a sale refunded in the meantime becomes
   `voided`). An `approved` or `paid` batch cannot be cancelled.

### Refund accounting rule

- A sale refunded **before** it was included in any batch never reaches the
  owner: its settlement item becomes `voided`.
- A sale refunded **after** it was included in a batch (or paid) produces a
  `refund` line in the next batch created for that owner:
  `gross_amount` and `commission_amount` are those of the reversed sale and
  `net_amount = -(owner net of that sale)`. The platform commission of the
  reversed sale is therefore given up, not charged to the owner.
- `total_refunds` of a batch is the owner net clawed back, and
  `net_settlement = gross_sales - total_commission - total_refunds`.
- A batch net can be **negative**: the owner owes the platform. Do not mark
  such a batch paid with a made-up reference; recover the amount (or carry it
  with the owner's agreement) and record the real reference.
- Refund lines of a cancelled batch are picked up again by the next batch.

---

## 6. Freezing a wallet

`admin_set_wallet_status(p_user_id, 'frozen' | 'active', p_reason)` — finance
officer or platform admin, reason required (max 500 characters), not on the
caller's own wallet, audited as `ADMIN_SET_WALLET_STATUS`. A frozen wallet
cannot purchase (`WALLET_FROZEN`). A `closed` wallet (deleted account) cannot
be reopened.

Freeze on: a reconciliation difference, a suspected fraudulent deposit, a
disputed chargeback. Unfreeze with a reason that names the resolution.

---

## 7. Card encryption key (`card_master_key`)

Card PINs are stored only as `pgp_sym_encrypt` ciphertext in
`public.card_vault.ciphertext`, with the passphrase read from the Supabase
Vault secret named `card_master_key` by `get_card_master_key()`.

### Provisioning (once per project, before any card is ingested)

In the SQL editor, with a value generated outside the repository
(`openssl rand -base64 48`) and never pasted into chat, tickets or logs:

```sql
SELECT vault.create_secret('<generated-passphrase>', 'card_master_key',
                           'Passphrase for card_vault ciphertext');
```

Store a copy in the organisation's secret manager. **If this secret is lost,
every unsold and unrevealed card is unrecoverable.** Without the secret, card
ingest and reveal fail with `CARD_MASTER_KEY_NOT_CONFIGURED`.

### What the one-time fingerprint backfill prints

`20261008091000` adds `card_vault.pin_fingerprint` (an HMAC of the PIN keyed
with the master key) so the same PIN cannot be ingested twice in a network.
While applying, it prints one of:

| Output | Meaning | Action |
|---|---|---|
| nothing | no card rows existed | none |
| `NOTICE card_vault fingerprint backfill: N card(s) fingerprinted, 0 duplicate card(s) left without one.` | done | none |
| the same notice with `D > 0` duplicates, plus `WARNING card_vault holds D duplicate card(s) ...` | the oldest copy of each PIN was fingerprinted; later copies have `pin_fingerprint IS NULL` | review `SELECT id, network_id, package_id, state, created_at FROM public.card_vault WHERE pin_fingerprint IS NULL;` and invalidate the unsold duplicates with the owner |
| `WARNING card_vault fingerprint backfill skipped: card master key is not available` | the secret did not exist yet | provision the key; existing rows stay without a fingerprint, so they are not protected against re-ingest until a backfill is run again by engineering |
| `WARNING card_vault fingerprint backfill failed and was skipped: ...` | unexpected error | escalate; do not ingest cards until resolved |

### Rotation

Rotation is **not automated** and there is one live key at a time. It needs a
reviewed migration, run in a maintenance window, that in a single transaction:

1. creates the new secret under a new name;
2. re-encrypts every row: `pgp_sym_encrypt(pgp_sym_decrypt(ciphertext, old), new)`;
3. recomputes `pin_fingerprint` with the new key for every row (the
   fingerprint is keyed with the master key; skipping this silently disables
   duplicate detection against existing cards);
4. changes `get_card_master_key()` to read the new secret name;
5. verifies one known test card decrypts, then removes the old secret.

Rotate when a person who knew the passphrase leaves or after any suspected
exposure of database backups together with the secret.

---

## 8. First platform administrator and staff accounts

Staff roles are granted through `platform_access_grants`: an administrator
pre-authorizes an email with `admin_create_access_grant(email, roles, note)`
and the roles are applied by a trigger when that person signs in.

Since `20261008092000` a grant is applied only to an account whose email is
confirmed and whose **only** sign-in method is Google
(`raw_app_meta_data.providers = ["google"]`). An address that was first
registered with a password, or a Google account later linked to one, does not
receive the grant.

There is no RPC for the very first administrator, because every admin RPC
requires an existing `platform_admin`. Bootstrap, once per project, in the SQL
editor:

1. Before the person has ever signed in, insert the pending grant:

   ```sql
   INSERT INTO public.platform_access_grants (email, roles, note)
   VALUES (lower('<admin-google-address>'), ARRAY['platform_admin'],
           'bootstrap: first platform administrator');
   ```

2. The person signs in **with Google** in the static admin console (`admin/`),
   which uses Google OAuth. Verify:

   ```sql
   SELECT g.email, g.applied_at, r.role
   FROM public.platform_access_grants g
   LEFT JOIN public.user_roles r ON r.user_id = g.applied_user_id
   WHERE lower(g.email) = lower('<admin-google-address>');
   ```

3. If `applied_at` stays `NULL`, the account is not Google-only (an
   email/password identity exists for that address). Do not work around it by
   inserting into `user_roles` for that account; remove the password identity
   or use a different Google address, then sign in again.
4. Record who ran the bootstrap and when. From then on, all role changes go
   through `admin_create_access_grant`, `admin_set_user_platform_role` and
   `admin_replace_user_platform_roles`, which are audited and refuse
   self-lockout and removal of the last administrator. Clients have no direct
   write access to `user_roles`.

Create a second `platform_admin` and at least two `finance_officer` accounts
immediately: settlement approval, large deposits and several safety checks
require a second person.

Note: `lib/admin_main.dart` (Flutter web console) signs in with email and
password. An account created that way is not Google-only and cannot receive a
staff grant; see the README on choosing one console.

---

## 9. Production Auth settings that must hold

Check in the Supabase dashboard (Authentication) after every project change and
before every release:

| Setting | Required | Why |
|---|---|---|
| Email confirmations | **ON** | With confirmations off anyone can register someone else's address with a password. `supabase/config.toml` turns them off for the local stack only. |
| Phone test OTP numbers | **none configured** | `supabase/config.toml` lists `+967771111111` / `+967772222222` with a fixed public code for local use. On a hosted project they would be open accounts. |
| Minimum password length | 8 or more | matches the client and the onboarding function |
| Google provider | enabled, with the production OAuth client | staff and owner sign-in |
| Redirect URL allow-list | only the real admin origin and the app deep links | prevents token redirection |
| `TEST_ONBOARDING_ENABLED` function secret | **unset** (or not `true`) outside a named-tester pilot | the `test-onboarding` function creates phone-confirmed accounts without SMS. While a pilot runs it additionally needs `TEST_ONBOARDING_EXPIRES_AT` (at most 14 days ahead), `TEST_ONBOARDING_INVITE_SHA256` and a non-empty `TEST_ONBOARDING_ALLOWED_PHONES`; see `supabase/functions/test-onboarding/README.md`. |
| Service-role key | only in server-side secret stores | full database access |

Verify the flag is off by calling the function without a body: it must answer
`503 TEST_ONBOARDING_DISABLED`.

Customer self-signup currently exists only through that invite-only tester
path. A public launch needs a real SMS (or other) verification flow first.

---

## 10. Static admin console: Subresource Integrity

`admin/index.html` loads `@supabase/supabase-js` from jsDelivr at a pinned
version but, until this step is done, without an `integrity` attribute (the
`TODO(SRI)` comment). Before publishing the console:

```sh
curl -s https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2.45.4/dist/umd/supabase.min.js \
  | openssl dgst -sha384 -binary | openssl base64 -A
```

Put the output into the script tag as `integrity="sha384-<output>"` (keep
`crossorigin="anonymous"`), load the console once and confirm in the browser
console that the script was not blocked. When the version in the URL changes,
recompute the hash in the same commit. Never copy a hash from elsewhere: a
wrong value blocks the library and the whole console. Details:
`admin/README.md`.

---

## 11. Firebase / Google API key in `android/app/google-services.json`

The `current_key` in that file is a public client identifier that ships inside
every APK. It is committed on purpose and the secret scanner allow-lists it in
that single file. It is safe only while it is restricted in Google Cloud
Console → APIs & Services → Credentials:

- Application restriction: **Android apps**, package `com.waselnet.app` (the
  `package_name` in the file) with the SHA-1 of the Play app-signing
  certificate and of the upload key.
- API restriction: only the Firebase APIs the app uses (Firebase
  Installations, Firebase Cloud Messaging registration).

Re-check after adding a signing key or a second app. No server credential
(service-account JSON, FCM private key) may ever be committed;
`scripts/scan_netyemen_fcm_credentials.ps1` enforces this in CI. Push dispatch
itself is not wired end to end yet (nothing drains `notification_outbox` into
the `dispatch_push` action), so no FCM server credential is required today.

---

## 12. CI supply chain (remaining manual step)

Workflows reference actions by major tag (`actions/checkout@v4`, ...).
Pinning each `uses:` to a full commit SHA (`owner/action@<40-hex-sha> # vX.Y.Z`)
is still to be done by someone with network access to look the SHAs up on the
action's release page; a wrong SHA breaks every workflow. `.github/dependabot.yml`
already opens weekly update pull requests for GitHub Actions and for both pub
packages and will keep pinned SHAs current afterwards.

---

## 13. Quick reference

| Task | Who | Call |
|---|---|---|
| Reconcile wallets | finance / admin / auditor | `finance_reconcile_wallets()` — daily, expect no rows |
| Freeze / unfreeze wallet | finance / admin | `admin_set_wallet_status(user, 'frozen' or 'active', reason)` |
| Create settlement | finance / admin | `finance_create_settlement_batch(start, end, network)` |
| Approve settlement | a second finance / admin | `finance_approve_settlement_batch(batch)` |
| Mark paid | finance / admin | `finance_mark_settlement_paid(batch, payment_reference)` |
| Cancel draft | finance / admin | `finance_cancel_settlement_batch(batch, reason)` |
| Complete due deletions | scheduler (service role) | `process_due_account_deletions(200)` |
| Close stale RADIUS sessions | scheduler (service role) | `radius_close_stale_sessions()` |
| Grant a staff role | platform admin | `admin_create_access_grant(email, roles, note)` |
