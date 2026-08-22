# WASEL NET Admin Web Console Runbook

## Entry point

The administration console has an independent Flutter entry point:

```text
lib/admin_main.dart
```

It does not initialize Firebase Messaging. Customer mobile and administration web
share the audited domain/data modules and the Supabase authorization boundary, but
they have separate bootstrap paths.

## Local run

Use publishable client configuration only. Never place a service-role key in a
Dart define, browser build, repository file, or CI artifact.

For the WASEL NET production pilot, use the fail-closed launcher. It verifies the
exact branch is synchronized with its remote head, pins project
`pgiidgoafajfpcnlmzde`, and pins the local recovery origin to port `7357`
without printing or storing the publishable key.

```powershell
$env:WASELNET_SUPABASE_PUBLISHABLE_KEY = '<publishable-key>'
.\scripts\run_waselnet_admin_local.ps1
```

Set the environment value only in the local PowerShell session. Clear it when the
test is complete. Do not send it in chat or place it in command history on a
shared workstation.

```powershell
flutter run -d chrome --target lib/admin_main.dart `
  --dart-define=SUPABASE_URL=<project-url> `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key> `
  --dart-define=ADMIN_PASSWORD_RECOVERY_REDIRECT_URL=<admin-origin>
```

## Production build

```powershell
flutter build web --release --target lib/admin_main.dart `
  --dart-define=SUPABASE_URL=<project-url> `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key> `
  --dart-define=ADMIN_PASSWORD_RECOVERY_REDIRECT_URL=<admin-origin>
```

The output is written to `build/web`. GitHub Actions also compiles the console
without production credentials as a structural build gate and uploads the
`admin-web-console` artifact.

## Access model

- `platform_admin`: full administration.
- `finance_officer`: finance and settlements.
- `support_agent`: support operations.
- `system_auditor`: overview and audit read models.

The Flutter capability gate controls navigation only. PostgreSQL RLS and guarded
RPC functions remain authoritative.

## Manual release preflight

The `.github/workflows/admin-release-gate.yml` workflow is the only approved CI
entry point for producing an administration release candidate. It is manual and
fail-closed: missing secrets stop the job before any database or build action.

Configure these secrets in the protected `admin-production` GitHub environment:

1. Open `Repository > Settings > Environments` and create
   `admin-production`.
2. Add required reviewers and disable self-approval when the repository plan
   supports deployment protection rules.
3. Add the following environment secrets. Never add their values to workflow
   YAML, repository variables, issues, PR comments, or build artifacts.

| Secret | Authoritative source |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | Supabase account settings > Access Tokens |
| `SUPABASE_PROJECT_REF` | Project dashboard URL; expected WASEL NET ref: `pgiidgoafajfpcnlmzde` |
| `SUPABASE_DB_PASSWORD` | Supabase project > Database settings |
| `SUPABASE_URL` | Supabase project > API settings |
| `SUPABASE_PUBLISHABLE_KEY` | Supabase project > API keys; publishable key only |

Create the public protected-environment variable
`ADMIN_PASSWORD_RECOVERY_REDIRECT_URL` with the exact HTTPS origin of the
hosted administration console. For local testing only, `http://localhost` or
`http://127.0.0.1` is accepted. The release build fails closed when the value is
missing. The console adds `mode=recovery` to the callback query automatically.

## Administration authentication and password recovery

The administration entry point uses email and password authentication. The
customer Android entry point remains phone OTP only; the two user experiences
must not share a login screen.

Before testing password recovery:

1. Add the exact generated callback URL, for example
   `https://admin.example.com?mode=recovery`, to
   `Authentication > URL Configuration` in the Supabase dashboard.
2. Set the same origin in the protected environment variable
   `ADMIN_PASSWORD_RECOVERY_REDIRECT_URL`.
3. Request password recovery from the administration console itself. The
   dashboard-level `Send password recovery` button uses the project Site URL and
   must not be used as evidence for this console unless that Site URL is the
   administration origin.
4. Open the email link in the same browser, set a new password, and sign in
   again. The console signs the recovery session out after the password update.

The Supabase built-in SMTP service is a development fallback: it only delivers
to addresses belonging to members of the Supabase organization and is limited
to two project-wide auth emails per hour. A production administration console
must use a custom SMTP provider. If the console reports the email-send limit,
stop retrying until one hour has passed; repeated requests extend the incident
and do not prove that the callback is valid.

Never place a password, service-role key, recovery token, or email-link URL in
the repository, CI logs, issues, or PR comments.

The workflow file must exist on the repository default branch before GitHub
enables its manual `Run workflow` control. While PR #15 remains a draft, the
source and ordinary CI gates can be reviewed, but the protected remote preflight
remains `HOLD`. Do not merge merely to expose the button; merge only after the
PR release decision is independently approved.

The workflow links the project, compares migration history, runs linked database
lint, and performs `db push --dry-run`. It never applies migrations. It then
builds the release web console and uploads both the release candidate and the
preflight evidence. It does not build an Android APK.

## Release gate

Before hosting the console:

1. Apply and verify all pending migrations against the linked Supabase project.
2. Run `supabase db lint --linked --level error`.
3. Confirm local and remote migration histories match.
4. Test sign-in and each role on the hosted origin.
5. Configure the hosted origin in Supabase Auth redirect URL allowlists.
6. Keep the console deployment on HOLD if any privileged RPC, RLS policy, or audit
   event is missing.
