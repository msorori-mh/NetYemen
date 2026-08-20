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

```powershell
flutter run -d chrome --target lib/admin_main.dart `
  --dart-define=SUPABASE_URL=<project-url> `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

## Production build

```powershell
flutter build web --release --target lib/admin_main.dart `
  --dart-define=SUPABASE_URL=<project-url> `
  --dart-define=SUPABASE_PUBLISHABLE_KEY=<publishable-key>
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

- `SUPABASE_ACCESS_TOKEN`
- `SUPABASE_PROJECT_REF`
- `SUPABASE_DB_PASSWORD`
- `SUPABASE_URL`
- `SUPABASE_PUBLISHABLE_KEY`

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
