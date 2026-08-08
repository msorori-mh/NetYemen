> **NetYemen V1 Push Notifications & Engagement — Task Completion Report**
> Classification: `TECHNICAL_REPORT`  
> Task ID: `NY-V1-NOTIFICATIONS-ENGAGEMENT-001`  
> Repository: `C:\projects\NetYemen-cursor-notifications`  
> Branch: `cursor/NY-V1-NOTIFICATIONS-ENGAGEMENT-001`

---

## Executive Summary

Closed the complete **source-side** mobile notification and user-engagement path as one coherent vertical slice: device tokens, preferences, transactional + engagement events, outbox, delivery tracking, deep links, domain hooks (network/package/stock/request), admin composer, audience targeting, dedupe/idempotency, rate limits, Android permission UX, Arabic RTL settings/center, SQL + Flutter verification.

**External push provider remains unbound** per `OD-NOTIF-01` (`OPEN_DECISION`). No provider was silently approved. Transport is isolated behind `NotificationTransportAdapter` / `notification_transport_config`.

**FINAL_DECISION: HOLD** — genuine governance/provider-binding blocker only (`OD-NOTIF-01`). All other source-path work is complete and verified locally.

---

## Source Control

| Item | Value |
|---|---|
| Starting SHA | `2b8a6e25bee675e24803b42cec7703c33c144797` |
| Ending SHA | `f3aef7fc5a36ea2088d71461d389d0b8078d1300` |
| Feature commit | `1c0cad90846132ef57b9419b9c4fdd7af07ade9a` |
| Branch | `cursor/NY-V1-NOTIFICATIONS-ENGAGEMENT-001` |
| Base (stacked) | `kimi/NY-V1-ADMIN-OPS-001` |
| PR | Draft, stacked on admin-ops branch |

---

## Delivered Scope (20/20 source items)

| # | Item | Status |
|---|---|---|
| 1 | Device push-token registration | Done (`register_device_push_token`) |
| 2 | Notification preferences | Done (transactional locked; engagement opt-out) |
| 3 | Transactional notification events | Done (request status + network ops) |
| 4 | Engagement notification events | Done (network/package/stock/platform/offers) |
| 5 | Notification outbox | Done |
| 6 | Delivery tracking | Done (`notification_deliveries`) |
| 7 | Deep links | Done (`network/`, `package/`, `request/`, `notifications`, `profile`) |
| 8 | Network-added notifications | Done (trigger on approve/verify) |
| 9 | Package-added notifications | Done (publish → active+public) |
| 10 | Stock-restored notifications | Done (0 → >0 available) |
| 11 | Network request status notifications | Done |
| 12 | Platform update announcements | Done (admin composer) |
| 13 | Admin notification composer | Done (`platform_admin` only) |
| 14 | Audience targeting | Done (customers/gov/city/network/role/user) |
| 15 | Deduplication / idempotency | Done (`dedupe_key`, `idempotency_key`) |
| 16 | Rate limiting | Done (engagement hourly + admin daily) |
| 17 | Android notification permission UX | Done (`permission_handler`, no FCM SDK) |
| 18 | Arabic RTL notification settings | Done |
| 19 | Tests | Done (`009` + Flutter) |
| 20 | Local report + stacked Draft PR | Done |

---

## OD-NOTIF-01 Provider Binding Blocker

| Field | Value |
|---|---|
| Decision | `OD-NOTIF-01` Push Notification Infrastructure & Gateway |
| Status | `OPEN_DECISION` (unchanged; not silently approved) |
| Provisional recommendation | FCM via Edge Functions (not binding) |
| Exact remaining blocker | Explicit human approval of provider **plus** server-only secret injection into vault; then set `notification_transport_config.binding_status = 'bound'` and deploy adapter worker |
| What ships without binding | Full event/outbox/inbox/preferences/admin path; push deliveries marked `dispatch_blocked_unbound_provider` |
| What must not happen | Flutter must never hold provider service-account / API secrets |

Adapter contract: `supabase/functions/notification-transport-adapter/README.sql`  
Flutter adapter: `UnboundNotificationTransportAdapter`

---

## Database / RPC

Migration: `supabase/migrations/20260730100000_netyemen_notifications_engagement.sql`

### Tables
- `notification_transport_config` (singleton, unbound)
- `device_push_tokens`
- `notification_preferences`
- `notification_events`
- `notification_outbox`
- `notification_deliveries`
- `notification_inbox`
- `notification_rate_limits`

### Key RPCs
- `register_device_push_token` / `deactivate_device_push_token`
- `get_notification_preferences` / `update_notification_preferences`
- `list_my_notifications` / `mark_notification_read` / `get_unread_notification_count`
- `enqueue_notification_event` (internal)
- `process_notification_outbox` (service) / `process_notification_outbox_guarded` (admin)
- `admin_compose_notification` (`platform_admin`)
- `admin_notification_delivery_summary` (admin/auditor)
- `get_notification_transport_status`

### Domain hooks (triggers)
- Request status → transactional
- Network approved → engagement + ops transactional
- Package published → engagement
- Stock restored → engagement

Security: no Wi-Fi passwords / card codes / payment secrets in push text (DB constraints + assert helper). Recipient authorization via RLS + SECURITY DEFINER RPCs. No client-side send privilege.

---

## Flutter

New feature: `lib/features/notifications/`

- Permission UX (Android 13+ `POST_NOTIFICATIONS`)
- Preferences screen (RTL Arabic; transactional locked)
- Notification center + unread badge on home
- Deep-link parser/router
- Admin composer entry from admin dashboard
- Provider-neutral transport adapter (unbound)
- `permission_handler` only — **no** Firebase/OneSignal SDK or secrets

---

## Verification Results

### SQL 001–009 (local Supabase only)

| Suite | Result |
|---|---|
| 001–008 existing | PASS |
| 009_notifications_engagement.sql | PASS |

### Flutter

| Check | Result |
|---|---|
| `flutter analyze` | No issues found |
| `flutter test` | **101 tests passed** |
| `flutter build apk --debug` | Built `build\app\outputs\flutter-apk\app-debug.apk` |

### Environment constraints honored
- Local Supabase only
- No production / remote Supabase
- No deployment
- No merge

---

## FINAL_DECISION

**HOLD**

Reason: `OD-NOTIF-01` remains an open governance decision. Source-side architecture, events, outbox, inbox, preferences, admin composer, targeting, tests, and client UX are closed. External provider dispatch is intentionally blocked until explicit provider approval and server-side secret binding.
