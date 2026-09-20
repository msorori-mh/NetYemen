# NY-V1-SUPPORT-DISPUTES-001 — Codex Completion Report

Date: 2026-08-08
Branch: `codex/NY-V1-SUPPORT-DISPUTES-001`
Stack base: `origin/kimi/NY-V1-ADMIN-OPS-001`

## Outcome

PASS. The V1 non-financial support path now covers support tickets, complaints, and disputes from customer creation through assignment, conversation, resolution, closure, and bounded reopening. No wallet, payment, refund execution, notification, attachment, or credential-storage capability was added.

## Delivered

- A deliberately compact `support_cases` model for ticket, complaint, and dispute records.
- Lifecycle: `open`, `assigned`, `in_progress`, `waiting_customer`, `resolved`, `closed`.
- Category, priority, deterministic priority-based SLA due time, age/overdue presentation, assignment, resolution, and outcome.
- Optional network, package, and network-addition-request references with reference validation.
- Customer-visible immutable messages and immutable status/event history.
- Separate immutable internal staff notes hidden from customers and network owners.
- A non-financial `refund_recommended` dispute outcome. It records a recommendation only and performs no money movement.
- Reopening only by the customer or support staff, within 14 days of resolution, with a maximum of three reopenings.
- Customer isolation, explicit support-agent scope, narrow platform-admin oversight, and network-owner access only for explicitly related networks they actively own.
- Audited create, claim, status-change, and reopen actions in the existing immutable platform audit trail.
- Arabic RTL customer screens for My Support, New Ticket, Ticket Details, and history/messages.
- Arabic RTL Support Queue, Agent Case View, and Admin Oversight entry point.
- Loading, error, and empty states.
- Riverpod repository boundary with Supabase and demo/fake implementations.

## Authorization

`auth.uid()` and active profile state are authoritative. Client tables expose reads only through RLS. All writes use narrowly authorized `SECURITY DEFINER` RPCs with fixed `search_path`; there is no generic authenticated write policy or bypass.

Customers can create, read, message, inspect history, and reopen only their own cases. Support agents can view the support queue, claim cases, communicate, add internal notes, and operate the supported lifecycle. Platform admins receive the same narrow case oversight authority. Network owners can only read and reply to cases that explicitly reference a network for which they hold an active owner membership. They cannot see internal notes or operate workflow controls.

Messages, notes, and case events reject update and delete operations. Direct table writes were not granted to authenticated clients.

## Tests and Verification

| Check | Result |
|---|---|
| Local migration application | PASS |
| Existing SQL suites `001`–`008` | PASS |
| `009_support_complaints_disputes.sql` | PASS — 6 positive, 11 negative checks |
| `flutter analyze` | PASS — no issues |
| `flutter test` | PASS — 96 tests |
| `flutter build apk --debug` | PASS |
| Core foundation verifier | PASS |
| `git diff --check` | PASS |
| Targeted secret scan | PASS — no matches |

The support SQL suite covers own-case creation/read/reply, priority SLA, related owner visibility/reply, support claim/lifecycle/internal note, refund recommendation constraints, reopening, admin oversight, cross-customer denial, unrelated-owner denial, customer assignment/resolution denial, internal-note isolation, immutable messages/events, invalid direct close, and refund-recommendation restriction to disputes.

## Local Supabase Note

The Docker project ID is shared across local worktrees. A notifications worktree replaced the shared local schema after this branch had successfully run `supabase db reset`. To avoid editing repository configuration or contacting any remote project, the support migration was subsequently applied directly to the same local Postgres container and all nine SQL suites were executed there with `ON_ERROR_STOP=1`. No production or remote Supabase command was used.

## Deferred by Design

- Actual refunds or any other money movement remain owned by Commerce/Finance.
- Attachments were not added because storage is disabled and no established safe storage pattern exists.
- Notifications, wallet behavior, payment integrations, card secrets, and card payloads remain untouched.
