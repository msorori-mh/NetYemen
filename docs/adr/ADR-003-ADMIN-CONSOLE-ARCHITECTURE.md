# ADR-003 — WASEL NET Admin Console Architecture

- Status: Accepted
- Date: 2026-08-19
- Scope: V1 admin and operations experience
- Applies to: Flutter client, Supabase RPC/RLS contracts, responsive web target

## Decision

WASEL NET will keep one shared Flutter domain and data layer, while presenting two
separate product surfaces:

1. Customer mobile application.
2. Role-gated responsive Admin Console, optimized for web/desktop and usable on
   tablets/mobile for field operations.

The Admin Console remains inside the repository as the bounded
`lib/features/admin` and operations feature set. It must not depend on customer
navigation to enforce access. APK/AAB packaging is deferred until the console,
backend contracts, and end-to-end role tests are closed.

## Security boundary

Client visibility is usability only. Supabase RLS and SECURITY DEFINER RPCs are
the authoritative authorization boundary.

| Role | Console access |
|---|---|
| `platform_admin` | Full operational console |
| `finance_officer` | Deposits, payment destinations, commerce, settlements |
| `support_agent` | Support cases, complaints and eligible dispute workflows |
| `system_auditor` | Read-only KPIs, catalogs and audit evidence |
| `network_owner` / `network_operator` | Owner Operations surface, not Admin Console |
| `customer` | No Admin Console access |

No service-role key, encryption key, card plaintext, Firebase credential or
database password may be embedded in Flutter/web builds.

## Bounded modules

The console is composed of independent modules behind a shared adaptive shell:

- Overview and operational KPIs
- Network addition requests
- Networks and SSID verification
- Packages and inventory
- Users, roles and network memberships
- Wallet deposit review and payment destinations
- Purchases, refunds and commerce monitoring
- Settlement batches and approval separation
- Card-vault metadata ingestion (encrypted payload only)
- Notification composition and delivery status
- Support, complaints and disputes
- Immutable audit events

Each module owns its domain entities, repository contract, Supabase adapter,
Riverpod providers, screens and tests. Cross-module navigation passes stable IDs,
not mutable entity objects.

## UI architecture

- A single `AdminAccessGate` resolves authentication and roles before any
  admin provider performs a request.
- `AdminShell` uses a navigation rail on wide screens and a drawer/list on
  narrow screens.
- Menu visibility is derived from a centralized role-capability matrix.
- Every module implements loading, empty, recoverable error, forbidden and
  retry states in Arabic RTL.
- Raw PostgREST exceptions are logged for diagnostics but never rendered to
  end users.
- Destructive or financial actions require a confirmation step and server-side
  authorization; maker/checker separation remains authoritative on the server.
- Pagination/filter/search contracts are server-side for operational lists.

## Data architecture

- Screens depend on repository interfaces only.
- Supabase adapters may use direct SELECT only where RLS is sufficient and the
  result is non-sensitive.
- State-changing, financial, security, notification and approval operations use
  explicit RPCs.
- Provider caches are invalidated after successful mutations.
- Empty catalogs are valid states, not errors.
- Existing pre-V1 data remains quarantined in `legacy_netyemen`.

## Delivery stages

1. Admin foundation: access gate, capability matrix, adaptive shell, safe error
   presentation and navigation tests.
2. Catalog operations: requests, networks, SSIDs, packages and inventory.
3. Identity operations: users, roles and memberships with least privilege.
4. Finance and commerce: deposits, destinations, purchases, refunds and
   settlements.
5. Engagement and support: notifications, delivery status, support and disputes.
6. Audit and readiness: audit filters, role E2E, responsive web QA, Arabic RTL,
   then final APK/AAB and web deployment artifacts.

## Exit criteria

- Static analysis, formatting and Flutter tests pass.
- Supabase migration/tests/lint pass.
- Each privileged role proves allowed and forbidden paths.
- No raw backend exception is displayed.
- Wide and narrow responsive layouts pass.
- Physical Android validation and final APK/AAB occur only after the Admin
  Console stages are closed.
