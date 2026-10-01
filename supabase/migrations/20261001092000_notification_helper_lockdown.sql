-- Notification helper EXECUTE lockdown (review finding H-2).
--
-- These SECURITY DEFINER helpers perform no caller check and are meant for
-- service_role and other SECURITY DEFINER functions only. Their migration
-- revoked EXECUTE from PUBLIC alone, but Supabase grants EXECUTE on new public
-- functions to anon and authenticated by default, so any visitor could, for
-- example, enqueue a push notification to every customer through
-- /rest/v1/rpc/enqueue_notification_event, or list admin user ids through
-- resolve_notification_audience('role_based', '{"role":"platform_admin"}').
--
-- Every in-database caller is SECURITY DEFINER, so revoking client EXECUTE does
-- not change behaviour.
REVOKE EXECUTE ON FUNCTION public.enqueue_notification_event(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, TEXT, TEXT, TEXT, UUID, UUID, TIMESTAMPTZ, JSONB
) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.resolve_notification_audience(TEXT, JSONB) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.ensure_notification_preferences(UUID) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notification_rate_limit_hit(TEXT, INTEGER, INTEGER) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notification_preference_allows(UUID, TEXT, TEXT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.notification_assert_no_secrets(TEXT, TEXT, TEXT) FROM anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.process_notification_outbox(INTEGER) FROM anon, authenticated;
