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

## Release gate

Before hosting the console:

1. Apply and verify all pending migrations against the linked Supabase project.
2. Run `supabase db lint --linked --level error`.
3. Confirm local and remote migration histories match.
4. Test sign-in and each role on the hosted origin.
5. Configure the hosted origin in Supabase Auth redirect URL allowlists.
6. Keep the console deployment on HOLD if any privileged RPC, RLS policy, or audit
   event is missing.
