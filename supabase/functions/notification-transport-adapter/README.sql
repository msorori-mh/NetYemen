-- Provider-neutral transport adapter contract (OD-NOTIF-01 unbound).
-- This module documents the server-side boundary. No provider SDK, API key,
-- service-account JSON, or FCM/OneSignal secret belongs in Flutter or this repo.
--
-- Binding blocker: docs/NETYEMEN-DECISION-REGISTER-01.md → OD-NOTIF-01 OPEN_DECISION.
-- Until explicit provider approval + secret injection into server-only vault,
-- process_notification_outbox materializes in-app deliveries and marks push as
-- dispatch_blocked_unbound_provider.

-- Interface (conceptual):
--   NotificationTransportAdapter.send(delivery_id, token, title, body, deep_link)
--     → { provider_message_id, status }
--
-- Approved binding steps (governance, not implemented here):
--   1. Close OD-NOTIF-01 with chosen provider
--   2. Store credentials in server-only secret store (never client)
--   3. UPDATE notification_transport_config SET provider_key=..., binding_status='bound'
--   4. Deploy edge worker implementing the adapter
--   5. Flip push deliveries from dispatch_blocked_unbound_provider → queued/sent

SELECT jsonb_build_object(
  'adapter_interface', 'NotificationTransportAdapter',
  'binding_status', binding_status,
  'provider_key', provider_key,
  'external_push_dispatch_enabled', binding_status = 'bound'
)
FROM public.notification_transport_config
WHERE id = 1;
