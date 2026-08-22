# WASEL NET Google Play release gate

Google Play receives an Android App Bundle (`.aab`), not the debug APK.

## Mandatory evidence

1. PR CI passes Flutter analysis/tests, the admin web build, Android API 36
   release compilation, and SQL contracts 001–018.
2. Production migrations are aligned and DB lint passes.
3. Administrative onboarding review and role checks pass for the exact
   `TEST_ONLY` identities.
4. The public privacy and account-deletion pages return HTTP 200 over HTTPS.
5. A real upload key is configured only in local `android/key.properties` or
   the protected release environment. It must never be committed.
6. The signed bundle is smoke-tested on a physical 64-bit Android device.

## Production account-deletion migration gate

Migration 20260822200000_netyemen_account_deletion_requests.sql remains a
separate production write. Do not infer apply authority from source or CI PASS.

Run the read-only preflight in the WASEL NET SQL Editor before any apply:

~~~powershell
Get-Content -Raw .\supabase\verification\018_account_deletion_production_preflight.sql | Set-Clipboard
~~~

Paste only the SQL contents into the SQL Editor. The result must report
decision=PASS, pending migration 20260822200000, zero existing deletion
requests, and baseline counts for Auth users, profiles, roles, and push tokens.
Any exception is HOLD.

After separately authorized migration apply, run:

~~~powershell
Get-Content -Raw .\supabase\verification\018_account_deletion_production_postverify.sql | Set-Clipboard
~~~

The post-verify must report the applied migration, forced RLS, correct RPC
grants, no direct authenticated mutations, zero unexpected deletion requests,
and unchanged baseline entity counts. Then run linked migration history, DB
lint, and db push --dry-run. Do not test the RPC with a real account; any later
E2E must use an exact disposable TEST_ONLY identity and preserve audit evidence.

## Public legal endpoints

Deploy `supabase/functions/public-legal` with JWT verification disabled, then
use these function routes as release defines and Play Console URLs:

- `.../functions/v1/public-legal/privacy`
- `.../functions/v1/public-legal/delete-account`

The second page supports authenticated deletion without reinstalling the app.

## Local upload-key setup

Create the Play upload key in the controlled release workstation. Copy
`android/key.properties.example` to `android/key.properties` and replace all
four values. Both the properties file and keystore are ignored by Git.

## Deterministic release build

Set the four environment values without printing them, then run:

```powershell
./scripts/build_waselnet_play_bundle.ps1
```

The script refuses a dirty source tree, missing signing, insecure legal URLs,
or failed analysis/tests. It prints only the bundle path and SHA-256 checksum.

## Play Console order

1. Create or select `com.waselnet.app`.
2. Complete App access with a dedicated least-privilege reviewer account.
3. Complete Data safety, Privacy policy, Account deletion, Content rating,
   Target audience, Ads, and Financial features declarations accurately.
4. Upload to Internal testing first and review the automated pre-launch report.
5. Promote to Closed testing only after the physical-device smoke gate passes.
6. Production promotion remains a separate decision after tester evidence and
   any account-specific Google testing requirement is satisfied.
