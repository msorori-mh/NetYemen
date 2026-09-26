-- Read-only post-verification for one completed TEST_ONLY pilot session.
-- Usage: psql ... -v pilot_session_id='<uuid>' -f this-file.sql
\set ON_ERROR_STOP on

\if :{?pilot_session_id}
\else
  \echo 'pilot_session_id is required'
  \quit 3
\endif

SELECT set_config('wasel.pilot_session_id', :'pilot_session_id', FALSE);

DO $$
DECLARE
    v_session_id UUID := current_setting('wasel.pilot_session_id')::UUID;
    v_session public.access_sessions%ROWTYPE;
    v_event_count INTEGER;
    v_event_types INTEGER;
    v_ledger_count INTEGER;
BEGIN
    SELECT * INTO v_session FROM public.access_sessions WHERE id = v_session_id;
    IF v_session.id IS NULL THEN
        RAISE EXCEPTION 'WASEL_RADIUS_POSTVERIFY_SESSION_NOT_FOUND';
    END IF;
    IF v_session.status <> 'closed' OR v_session.ended_at IS NULL
       OR v_session.last_accounting_at IS NULL THEN
        RAISE EXCEPTION 'WASEL_RADIUS_POSTVERIFY_SESSION_NOT_CLOSED';
    END IF;
    IF v_session.input_bytes < 0 OR v_session.output_bytes < 0
       OR v_session.session_seconds < 0 THEN
        RAISE EXCEPTION 'WASEL_RADIUS_POSTVERIFY_COUNTERS_INVALID';
    END IF;

    SELECT COUNT(*), COUNT(DISTINCT event_type)
    INTO v_event_count, v_event_types
    FROM public.radius_accounting_events
    WHERE session_id = v_session_id;
    IF v_event_count < 2 OR v_event_types < 2 OR NOT EXISTS (
        SELECT 1 FROM public.radius_accounting_events
        WHERE session_id = v_session_id AND event_type = 'start'
    ) OR NOT EXISTS (
        SELECT 1 FROM public.radius_accounting_events
        WHERE session_id = v_session_id AND event_type = 'stop'
    ) THEN
        RAISE EXCEPTION 'WASEL_RADIUS_POSTVERIFY_EVENT_CHAIN_INVALID';
    END IF;

    SELECT COUNT(*) INTO v_ledger_count FROM public.partner_usage_ledger
    WHERE session_id = v_session_id AND entry_type = 'accrual';
    IF v_ledger_count <> 1 THEN
        RAISE EXCEPTION 'WASEL_RADIUS_POSTVERIFY_LEDGER_COUNT: expected 1, got %', v_ledger_count;
    END IF;
END;
$$;

SELECT jsonb_build_object(
    'result', 'PASS',
    'session_id', id,
    'status', status,
    'input_bytes', input_bytes,
    'output_bytes', output_bytes,
    'session_seconds', session_seconds,
    'accounting_events', (
        SELECT COUNT(*) FROM public.radius_accounting_events e WHERE e.session_id = s.id
    ),
    'partner_accruals', (
        SELECT COUNT(*) FROM public.partner_usage_ledger l
        WHERE l.session_id = s.id AND l.entry_type = 'accrual'
    )
) AS wasel_radius_postverify
FROM public.access_sessions s
WHERE id = current_setting('wasel.pilot_session_id')::UUID;
