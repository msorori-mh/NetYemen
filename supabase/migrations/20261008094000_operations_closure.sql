-- Operations closure: deposit splitting, notification isolation, account
-- deletion completion and wallet reconciliation.

-- 1. Dual approval cannot be dodged by splitting a deposit -------------------
CREATE OR REPLACE FUNCTION public.review_wallet_deposit_request(p_deposit_id uuid, p_action text, p_rejection_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user_id UUID;
    v_deposit public.wallet_deposit_requests%ROWTYPE;
    v_existing_ledger UUID;
    v_ledger_id UUID;
    v_balance_after INTEGER;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.is_finance_officer() AND NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance_officer or platform_admin can review deposits.'
            USING ERRCODE = '42501';
    END IF;

    IF p_action NOT IN ('approve', 'reject') THEN
        RAISE EXCEPTION 'INVALID_ACTION: Action must be approve or reject.'
            USING ERRCODE = '22000';
    END IF;

    IF p_action = 'reject' AND (p_rejection_reason IS NULL OR length(trim(p_rejection_reason)) = 0) THEN
        RAISE EXCEPTION 'REJECTION_REASON_REQUIRED: Rejection requires a reason.'
            USING ERRCODE = '22000';
    END IF;

    -- Lock deposit row for review
    SELECT * INTO v_deposit
    FROM public.wallet_deposit_requests
    WHERE id = p_deposit_id
    FOR UPDATE;

    IF v_deposit.id IS NULL THEN
        RAISE EXCEPTION 'NOT_FOUND: Deposit request not found.'
            USING ERRCODE = '42501';
    END IF;

    -- Idempotency: already approved/rejected returns existing state without double credit
    IF v_deposit.status = 'approved' THEN
        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'approved', 'replayed', TRUE);
    END IF;

    IF v_deposit.status = 'rejected' THEN
        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'rejected', 'replayed', TRUE);
    END IF;

    IF v_deposit.status NOT IN ('pending', 'under_review') THEN
        RAISE EXCEPTION 'INVALID_STATE: Deposit is not reviewable (status=%).', v_deposit.status
            USING ERRCODE = '22000';
    END IF;

    -- Separation of duties: staff cannot review their own deposits.
    IF v_deposit.user_id = v_user_id THEN
        RAISE EXCEPTION 'SELF_REVIEW_FORBIDDEN: A deposit cannot be reviewed by its requester.'
            USING ERRCODE = '42501';
    END IF;

    IF p_action = 'reject' THEN
        UPDATE public.wallet_deposit_requests
        SET status = 'rejected',
            reviewed_by = v_user_id,
            reviewed_at = NOW(),
            rejection_reason = trim(p_rejection_reason)
        WHERE id = p_deposit_id;

        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'rejected');
    END IF;

    -- Approve: exactly one credit ledger entry. Check for pre-existing ledger to prevent double credit.
    IF v_deposit.ledger_entry_id IS NOT NULL THEN
        RETURN jsonb_build_object('id', p_deposit_id, 'status', 'approved', 'replayed', TRUE);
    END IF;

    -- The same bank transfer reference may only be credited once per
    -- destination (THR-09). The unique index below backs this up under
    -- concurrent approvals.
    IF EXISTS (
        SELECT 1
        FROM public.wallet_deposit_requests d
        WHERE d.id <> p_deposit_id
          AND d.status = 'approved'
          AND d.bank_directory_id IS NOT DISTINCT FROM v_deposit.bank_directory_id
          AND lower(trim(d.reference_number)) = lower(trim(v_deposit.reference_number))
    ) THEN
        RAISE EXCEPTION 'DUPLICATE_REFERENCE: This transfer reference was already credited.'
            USING ERRCODE = '23505';
    END IF;

    -- Four-eyes rule for large deposits (THR-23): the first approval only
    -- records the approver and moves the request to under_review; a second,
    -- different reviewer credits the wallet.
    -- The threshold also applies to what the same customer was credited in
    -- the last 24 hours, so a large transfer cannot be split into requests that
    -- each stay just under it.
    IF v_deposit.amount >= public.deposit_dual_approval_threshold()
       OR v_deposit.amount::BIGINT + COALESCE((
            SELECT SUM(d.amount)::BIGINT
            FROM public.wallet_deposit_requests d
            WHERE d.user_id = v_deposit.user_id
              AND d.id <> p_deposit_id
              AND d.status = 'approved'
              AND d.reviewed_at > NOW() - INTERVAL '24 hours'
          ), 0) >= public.deposit_dual_approval_threshold() THEN
        IF v_deposit.first_approved_by IS NULL THEN
            UPDATE public.wallet_deposit_requests
            SET status = 'under_review',
                first_approved_by = v_user_id,
                first_approved_at = NOW()
            WHERE id = p_deposit_id;

            RETURN jsonb_build_object(
                'id', p_deposit_id,
                'status', 'under_review',
                'requires_second_approval', TRUE
            );
        ELSIF v_deposit.first_approved_by = v_user_id THEN
            -- Same reviewer again (e.g. a retried request): nothing changes.
            RETURN jsonb_build_object(
                'id', p_deposit_id,
                'status', 'under_review',
                'requires_second_approval', TRUE,
                'replayed', TRUE
            );
        END IF;
    END IF;

    -- Lock wallet account to serialize balance changes for this user
    SELECT cached_balance INTO v_balance_after
    FROM public.wallet_accounts
    WHERE user_id = v_deposit.user_id
    FOR UPDATE;

    IF v_balance_after IS NULL THEN
        RAISE EXCEPTION 'WALLET_ACCOUNT_MISSING: Customer wallet account not found.'
            USING ERRCODE = '42501';
    END IF;

    v_balance_after := v_balance_after + v_deposit.amount;

    INSERT INTO public.customer_wallet_ledger (
        user_id,
        entry_type,
        amount,
        balance_after,
        reference_type,
        reference_id,
        idempotency_key,
        actor_user_id,
        reason_code,
        metadata
    ) VALUES (
        v_deposit.user_id,
        'CREDIT',
        v_deposit.amount,
        v_balance_after,
        'DEPOSIT',
        p_deposit_id,
        gen_random_uuid(),
        v_user_id,
        'DEPOSIT_APPROVED',
        jsonb_build_object(
            'reference_number', v_deposit.reference_number,
            'first_approved_by', v_deposit.first_approved_by
        )
    ) RETURNING id INTO v_ledger_id;

    UPDATE public.wallet_deposit_requests
    SET status = 'approved',
        reviewed_by = v_user_id,
        reviewed_at = NOW(),
        ledger_entry_id = v_ledger_id
    WHERE id = p_deposit_id;

    RETURN jsonb_build_object('id', p_deposit_id, 'status', 'approved', 'ledger_entry_id', v_ledger_id);
END;
$function$;

-- 2. A broken notification never blocks commerce -----------------------------
CREATE OR REPLACE FUNCTION public.process_notification_outbox(p_limit integer DEFAULT 50)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_row public.notification_outbox%ROWTYPE;
    v_event public.notification_events%ROWTYPE;
    v_recipient UUID;
    v_processed INTEGER := 0;
    v_deliveries INTEGER := 0;
    v_skipped INTEGER := 0;
    v_binding TEXT;
    v_delivery_id UUID;
    v_allowed BOOLEAN;
    v_rate_ok BOOLEAN;
BEGIN
    SELECT binding_status INTO v_binding
    FROM public.notification_transport_config
    WHERE id = 1;

    FOR v_row IN
        SELECT *
        FROM public.notification_outbox
        WHERE status = 'pending'
          AND next_attempt_at <= NOW()
        ORDER BY created_at
        LIMIT GREATEST(p_limit, 1)
        FOR UPDATE SKIP LOCKED
    LOOP
      -- Each event is handled in its own sub-transaction. One broken event
      -- (for example a malformed audience) is parked and retried later
      -- instead of aborting the purchase, deposit or refund that happened to
      -- trigger processing.
      BEGIN
        UPDATE public.notification_outbox
        SET status = 'processing',
            attempts = attempts + 1,
            locked_at = NOW(),
            locked_by = 'process_notification_outbox'
        WHERE id = v_row.id;

        SELECT * INTO v_event FROM public.notification_events WHERE id = v_row.event_id;

        IF v_event.scheduled_for > NOW() THEN
            UPDATE public.notification_outbox
            SET status = 'pending',
                next_attempt_at = v_event.scheduled_for,
                locked_at = NULL,
                locked_by = NULL
            WHERE id = v_row.id;
            CONTINUE;
        END IF;

        FOR v_recipient IN
            SELECT ra.user_id FROM public.resolve_notification_audience(
                v_event.audience_type,
                v_event.audience_payload
            ) ra
        LOOP
            v_allowed := public.notification_preference_allows(
                v_recipient,
                v_event.category,
                v_event.channel_class
            );

            IF NOT v_allowed THEN
                INSERT INTO public.notification_deliveries (
                    event_id, recipient_user_id, delivery_channel, status, skip_reason
                ) VALUES (
                    v_event.id, v_recipient, 'push', 'skipped_opt_out', 'user_opted_out'
                )
                ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING;
                v_skipped := v_skipped + 1;
                CONTINUE;
            END IF;

            IF v_event.category = 'engagement' THEN
                v_rate_ok := public.notification_rate_limit_hit(
                    'engagement:' || v_recipient::text,
                    3600,
                    20
                );
                IF NOT v_rate_ok THEN
                    INSERT INTO public.notification_deliveries (
                        event_id, recipient_user_id, delivery_channel, status, skip_reason
                    ) VALUES (
                        v_event.id, v_recipient, 'push', 'skipped_rate_limit', 'hourly_engagement_cap'
                    )
                    ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING;
                    v_skipped := v_skipped + 1;
                    CONTINUE;
                END IF;
            END IF;

            IF COALESCE(v_binding, 'unbound') <> 'bound' THEN
                INSERT INTO public.notification_deliveries (
                    event_id, recipient_user_id, delivery_channel, status, skip_reason, attempt_count, last_attempt_at
                ) VALUES (
                    v_event.id,
                    v_recipient,
                    'push',
                    'dispatch_blocked_unbound_provider',
                    'OD-NOTIF-01_provider_unbound',
                    1,
                    NOW()
                )
                ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING
                RETURNING id INTO v_delivery_id;
            ELSE
                INSERT INTO public.notification_deliveries (
                    event_id, recipient_user_id, delivery_channel, status, attempt_count, last_attempt_at
                ) VALUES (
                    v_event.id, v_recipient, 'push', 'queued', 1, NOW()
                )
                ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING
                RETURNING id INTO v_delivery_id;
            END IF;

            -- Always create in-app inbox row (safe local history regardless of provider)
            INSERT INTO public.notification_deliveries (
                event_id, recipient_user_id, delivery_channel, status, attempt_count, last_attempt_at
            ) VALUES (
                v_event.id, v_recipient, 'in_app', 'sent', 1, NOW()
            )
            ON CONFLICT (event_id, recipient_user_id, delivery_channel) DO NOTHING
            RETURNING id INTO v_delivery_id;

            INSERT INTO public.notification_inbox (
                user_id, event_id, delivery_id, title_ar, body_ar, deep_link, category, channel_class
            ) VALUES (
                v_recipient,
                v_event.id,
                v_delivery_id,
                v_event.title_ar,
                v_event.body_ar,
                v_event.deep_link,
                v_event.category,
                v_event.channel_class
            )
            ON CONFLICT (user_id, event_id) DO NOTHING;

            v_deliveries := v_deliveries + 1;
        END LOOP;

        UPDATE public.notification_outbox
        SET status = CASE
                WHEN COALESCE(v_binding, 'unbound') <> 'bound' THEN 'dispatch_blocked'
                ELSE 'materialized'
            END,
            processed_at = NOW(),
            locked_at = NULL,
            locked_by = NULL,
            last_error = CASE
                WHEN COALESCE(v_binding, 'unbound') <> 'bound'
                    THEN 'Provider transport unbound (OD-NOTIF-01). In-app deliveries materialized.'
                ELSE NULL
            END
        WHERE id = v_row.id;

        v_processed := v_processed + 1;
      EXCEPTION WHEN OTHERS THEN
        UPDATE public.notification_outbox
        SET status = CASE WHEN attempts + 1 >= max_attempts THEN 'failed' ELSE 'pending' END,
            attempts = LEAST(attempts + 1, max_attempts),
            next_attempt_at = NOW() + INTERVAL '15 minutes',
            locked_at = NULL,
            locked_by = NULL,
            last_error = left('Processing failed: ' || SQLERRM, 500)
        WHERE id = v_row.id;
        v_skipped := v_skipped + 1;
      END;
    END LOOP;

    RETURN jsonb_build_object(
        'processed', v_processed,
        'deliveries_created', v_deliveries,
        'skipped', v_skipped,
        'transport_binding', COALESCE(v_binding, 'unbound')
    );
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_compose_notification(p_title_ar text, p_body_ar text, p_audience_type text, p_audience_payload jsonb DEFAULT '{}'::jsonb, p_channel_class text DEFAULT 'announcement'::text, p_deep_link text DEFAULT 'notifications'::text, p_scheduled_for timestamp with time zone DEFAULT now(), p_idempotency_key uuid DEFAULT NULL::uuid, p_process_immediately boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_user_id UUID;
    v_event_id UUID;
    v_process JSONB;
    v_rate_ok BOOLEAN;
BEGIN
    v_user_id := auth.uid();
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.'
            USING ERRCODE = '28000';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = v_user_id AND account_status = 'active'
    ) THEN
        RAISE EXCEPTION 'INACTIVE_PROFILE: Account is not active.'
            USING ERRCODE = '42501';
    END IF;

    IF NOT public.has_platform_role('platform_admin') THEN
        RAISE EXCEPTION 'FORBIDDEN_ROLE: Only platform_admin can compose announcements.'
            USING ERRCODE = '42501';
    END IF;

    IF p_channel_class NOT IN ('platform_update', 'announcement', 'offer') THEN
        RAISE EXCEPTION 'INVALID_CHANNEL: Admin composer supports platform_update, announcement, offer.'
            USING ERRCODE = '22000';
    END IF;

    IF p_audience_type NOT IN (
        'all_active_customers', 'governorate', 'city',
        'network_related', 'network_owner_operator', 'specific_user', 'role_based'
    ) THEN
        RAISE EXCEPTION 'INVALID_AUDIENCE: Unsupported audience for admin composer.'
            USING ERRCODE = '22000';
    END IF;

    -- Reject a malformed audience now instead of storing an event that can
    -- never be delivered.
    IF p_audience_type = 'specific_user'
       AND COALESCE(p_audience_payload->>'user_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'INVALID_AUDIENCE_PAYLOAD: specific_user needs a valid user_id.' USING ERRCODE = '22000';
    END IF;
    IF p_audience_type IN ('network_related', 'network_owner_operator')
       AND COALESCE(p_audience_payload->>'network_id', '') !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' THEN
        RAISE EXCEPTION 'INVALID_AUDIENCE_PAYLOAD: network audiences need a valid network_id.' USING ERRCODE = '22000';
    END IF;
    IF p_audience_type = 'governorate' AND NULLIF(trim(p_audience_payload->>'governorate'), '') IS NULL THEN
        RAISE EXCEPTION 'INVALID_AUDIENCE_PAYLOAD: governorate audience needs a governorate.' USING ERRCODE = '22000';
    END IF;
    IF p_audience_type = 'city' AND NULLIF(trim(p_audience_payload->>'city'), '') IS NULL THEN
        RAISE EXCEPTION 'INVALID_AUDIENCE_PAYLOAD: city audience needs a city.' USING ERRCODE = '22000';
    END IF;
    IF p_audience_type = 'role_based' AND NULLIF(trim(p_audience_payload->>'role'), '') IS NULL THEN
        RAISE EXCEPTION 'INVALID_AUDIENCE_PAYLOAD: role_based audience needs a role.' USING ERRCODE = '22000';
    END IF;

    v_rate_ok := public.notification_rate_limit_hit(
        'admin_compose:' || v_user_id::text,
        86400,
        50
    );
    IF NOT v_rate_ok THEN
        RAISE EXCEPTION 'RATE_LIMITED: Daily admin compose limit reached.'
            USING ERRCODE = '54000';
    END IF;

    v_event_id := public.enqueue_notification_event(
        'admin_announcement',
        'engagement',
        p_channel_class,
        p_title_ar,
        p_body_ar,
        COALESCE(NULLIF(trim(p_deep_link), ''), 'notifications'),
        p_audience_type,
        COALESCE(p_audience_payload, '{}'::jsonb),
        'admin_compose',
        COALESCE(p_idempotency_key::text, gen_random_uuid()::text),
        'admin_compose:' || COALESCE(p_idempotency_key::text, gen_random_uuid()::text),
        p_idempotency_key,
        v_user_id,
        COALESCE(p_scheduled_for, NOW()),
        jsonb_build_object('composer', 'admin', 'preview', TRUE)
    );

    PERFORM public.record_audit_event(
        'ADMIN_COMPOSE_NOTIFICATION',
        'notification_event',
        v_event_id::text,
        'success',
        'ADMIN_COMPOSE',
        jsonb_build_object(
            'audience_type', p_audience_type,
            'channel_class', p_channel_class,
            'scheduled_for', COALESCE(p_scheduled_for, NOW())
        )
    );

    IF p_process_immediately AND COALESCE(p_scheduled_for, NOW()) <= NOW() THEN
        v_process := public.process_notification_outbox(100);
    ELSE
        v_process := jsonb_build_object('processed', 0, 'deferred', TRUE);
    END IF;

    RETURN jsonb_build_object(
        'event_id', v_event_id,
        'title_ar', trim(p_title_ar),
        'body_ar', trim(p_body_ar),
        'audience_type', p_audience_type,
        'process_result', v_process
    );
END;
$function$;

-- 3. Account deletion is actually completed ----------------------------------
-- request_my_account_deletion schedules deletion 30 days ahead and the public
-- privacy policy promises it, but nothing ever carried it out. This function
-- completes the requests that are due. Financial and audit records are kept
-- (legal retention) but are detached from any personal detail: the profile is
-- anonymized, sign-in is removed, tokens and inbox are deleted, access
-- credentials are revoked and the wallet is closed.
CREATE OR REPLACE FUNCTION public.process_due_account_deletions(p_limit INTEGER DEFAULT 50)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
    v_request RECORD;
    v_completed INTEGER := 0;
    v_auth_pending INTEGER := 0;
    v_auth_scrubbed BOOLEAN;
BEGIN
    FOR v_request IN
        SELECT id, user_id
        FROM public.account_deletion_requests
        WHERE status = 'pending'
          AND scheduled_for <= NOW()
        ORDER BY scheduled_for
        LIMIT GREATEST(COALESCE(p_limit, 50), 1)
        FOR UPDATE SKIP LOCKED
    LOOP
        UPDATE public.profiles
        SET full_name = NULL,
            default_governorate = NULL,
            default_city = NULL,
            account_status = 'anonymized'
        WHERE id = v_request.user_id;

        DELETE FROM public.device_push_tokens WHERE user_id = v_request.user_id;
        DELETE FROM public.notification_inbox WHERE user_id = v_request.user_id;
        DELETE FROM public.account_pins WHERE user_id = v_request.user_id;

        UPDATE public.radius_access_credentials
        SET status = 'revoked', updated_at = NOW()
        WHERE user_id = v_request.user_id AND status = 'active';

        UPDATE public.wallet_accounts
        SET account_status = 'closed', updated_at = NOW()
        WHERE user_id = v_request.user_id;

        -- Remove the sign-in identity. The auth schema belongs to the platform;
        -- if this role may not change it, the request is still completed here
        -- and reported so the operator removes the auth user through the Auth
        -- admin API.
        v_auth_scrubbed := TRUE;
        BEGIN
            EXECUTE 'DELETE FROM auth.sessions WHERE user_id = $1' USING v_request.user_id;
            EXECUTE 'DELETE FROM auth.identities WHERE user_id = $1' USING v_request.user_id;
        EXCEPTION WHEN OTHERS THEN
            v_auth_scrubbed := FALSE;
        END;
        BEGIN
            UPDATE auth.users
            SET email = NULL,
                phone = NULL,
                encrypted_password = NULL,
                raw_user_meta_data = '{}'::jsonb,
                banned_until = 'infinity'::timestamptz,
                updated_at = NOW()
            WHERE id = v_request.user_id;
        EXCEPTION WHEN OTHERS THEN
            v_auth_scrubbed := FALSE;
        END;

        UPDATE public.account_deletion_requests
        SET status = 'completed',
            completed_at = NOW(),
            reason = NULL
        WHERE id = v_request.id;

        PERFORM public.record_audit_event(
            'ACCOUNT_DELETION_COMPLETED', 'user', v_request.user_id::TEXT, 'success', 'PRIVACY',
            jsonb_build_object('request_id', v_request.id, 'auth_identity_removed', v_auth_scrubbed)
        );

        v_completed := v_completed + 1;
        IF NOT v_auth_scrubbed THEN
            v_auth_pending := v_auth_pending + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object('completed', v_completed, 'auth_removal_pending', v_auth_pending);
END;
$$;
REVOKE EXECUTE ON FUNCTION public.process_due_account_deletions(INTEGER) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.process_due_account_deletions(INTEGER) TO service_role;

-- 4. Wallet reconciliation ---------------------------------------------------
-- Compares, for every wallet, the cached balance with the ledger. Returns only
-- the wallets that do not reconcile; an empty result is the healthy state.
CREATE OR REPLACE FUNCTION public.finance_reconcile_wallets()
RETURNS TABLE (
    user_id UUID,
    cached_balance INTEGER,
    ledger_balance BIGINT,
    last_balance_after INTEGER,
    ledger_entries BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- Signed-in callers must be staff. Without a user the caller is either the
    -- service role or a direct database session (scheduler); client roles are
    -- additionally kept out by the EXECUTE grants below.
    IF auth.uid() IS NOT NULL THEN
        IF NOT (public.is_finance_or_admin() OR public.has_platform_role('system_auditor')) THEN
            RAISE EXCEPTION 'FORBIDDEN_ROLE: Only finance, administrators and auditors can reconcile wallets.'
                USING ERRCODE = '42501';
        END IF;
    ELSIF COALESCE(auth.role(), 'service_role') <> 'service_role' THEN
        RAISE EXCEPTION 'UNAUTHENTICATED: Authentication required.' USING ERRCODE = '28000';
    END IF;

    RETURN QUERY
        WITH ledger AS (
            SELECT l.user_id,
                   SUM(CASE WHEN l.entry_type = 'DEBIT' THEN -l.amount ELSE l.amount END)::BIGINT AS balance,
                   COUNT(*) AS entries
            FROM public.customer_wallet_ledger l
            GROUP BY l.user_id
        ), last_entry AS (
            SELECT DISTINCT ON (l.user_id) l.user_id, l.balance_after
            FROM public.customer_wallet_ledger l
            ORDER BY l.user_id, l.created_at DESC, l.id DESC
        )
        SELECT w.user_id,
               w.cached_balance,
               COALESCE(g.balance, 0),
               e.balance_after,
               COALESCE(g.entries, 0)
        FROM public.wallet_accounts w
        LEFT JOIN ledger g ON g.user_id = w.user_id
        LEFT JOIN last_entry e ON e.user_id = w.user_id
        WHERE w.cached_balance::BIGINT <> COALESCE(g.balance, 0)
        ORDER BY w.user_id;
END;
$$;
REVOKE EXECUTE ON FUNCTION public.finance_reconcile_wallets() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.finance_reconcile_wallets() TO authenticated, service_role;

-- 5. Scheduling --------------------------------------------------------------
-- When pg_cron is enabled on the project the maintenance jobs are registered
-- here. Without pg_cron nothing happens and the jobs must be scheduled by
-- another service-role caller (documented in docs/OPERATIONS-RUNBOOK.md).
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
        PERFORM cron.schedule('netyemen-account-deletions', '17 2 * * *',
            'SELECT public.process_due_account_deletions(200)');
        PERFORM cron.schedule('netyemen-radius-stale-sessions', '*/10 * * * *',
            'SELECT public.radius_close_stale_sessions()');
    ELSE
        RAISE NOTICE 'pg_cron is not enabled: schedule process_due_account_deletions and radius_close_stale_sessions externally.';
    END IF;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Could not register maintenance jobs: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;
