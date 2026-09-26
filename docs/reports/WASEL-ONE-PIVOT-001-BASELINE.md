# WASEL-ONE-PIVOT-001 — Baseline and execution gate

## Decision

The authoritative implementation baseline is
`origin/integrate/wasel-net-v2` at commit
`772881b02e64041e43d63d17d8f8efa403bfe690`.

The repository `main` branch is a legacy prototype. At baseline time, the
integration branch was 312 commits ahead of `main` and contained the current
Flutter customer app, owner app, admin application, legal site, Supabase schema,
tests, functions, and CI workflows.

Implementation work is isolated on branch `codex/WASEL-ONE-PIVOT-001`.

## Reuse inventory

| Domain | Baseline state | Pivot action |
| --- | --- | --- |
| Customer identity and PIN | Implemented | Reuse |
| Wallet and immutable ledger | Implemented | Reuse for plan purchase |
| Network and SSID catalog | Implemented | Reuse for eligible hotspot discovery |
| Partner memberships | Implemented | Reuse for network-scoped access |
| Package/card commerce | Implemented | Keep as fallback; do not extend as federation core |
| Settlement batches | Implemented for purchases | Extend later for usage accruals |
| Notifications and support | Implemented | Reuse |
| Router/NAS registry | Missing | Add |
| Universal plans and entitlements | Missing | Add |
| RADIUS sessions/accounting | Missing | Add |
| Usage-based partner accrual | Missing | Add |

## Fixed scope for this slice

This slice creates the database contract and authorization boundary for the
federation. It does not claim production RADIUS connectivity, automatic Wi-Fi
association, charging, or partner payouts.

Included:

- architecture decision and operational boundaries;
- federated plan and participating-network model;
- MikroTik/RADIUS access-node registry without secrets;
- customer entitlement and access-session state;
- append-only accounting event and partner usage ledger foundations;
- row-level read isolation and denial of client-side writes;
- SQL contract tests for ownership, partner scoping, and immutability.

Excluded:

- modification of existing card purchase RPCs;
- storage of router shared secrets;
- production router configuration;
- deployment or mutation of hosted Supabase;
- customer interface changes;
- settlement payment automation.

## Verification availability

Flutter, Dart, Docker, Supabase CLI, and `psql` were not present in the execution
environment at baseline time. Therefore, repository/static checks can run here,
while the complete migration and SQL test chain must run through the existing
Supabase CI gate before this slice can be marked production-ready.
