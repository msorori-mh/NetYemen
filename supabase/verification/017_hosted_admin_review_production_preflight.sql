-- WASEL NET production preflight for exact hosted TEST_ONLY admin review.
-- READ ONLY: maps normalized stored phones to immutable application references.
BEGIN;
SET TRANSACTION READ ONLY;

DO $$
DECLARE
    v_count BIGINT;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM supabase_migrations.schema_migrations
        WHERE version = '20260821090000'
    ) OR NOT EXISTS (
        SELECT 1
        FROM supabase_migrations.schema_migrations
        WHERE version = '20260821120000'
    ) THEN
        RAISE EXCEPTION
            'HOLD: controlled onboarding or admin review migration is missing.';
    END IF;

    IF to_regclass('public.test_onboarding_applications') IS NULL
       OR to_regprocedure(
            'public.admin_review_test_onboarding(uuid,text,text)'
          ) IS NULL THEN
        RAISE EXCEPTION
            'HOLD: hosted onboarding review objects are missing.';
    END IF;

    SELECT count(*)
    INTO v_count
    FROM auth.users u
    WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g') IN (
        '967770000021',
        '967770000022',
        '967770000023'
    );

    IF v_count <> 3 THEN
        RAISE EXCEPTION
            'HOLD: expected exactly 3 exact TEST_ONLY Auth identities; found %.',
            v_count;
    END IF;

    IF EXISTS (
        WITH expected(
            phone,
            requested_account_type,
            owner_review_status
        ) AS (
            VALUES
                ('967770000021', 'customer', 'not_requested'),
                ('967770000022', 'network_owner', 'pending'),
                ('967770000023', 'customer', 'not_requested')
        )
        SELECT 1
        FROM expected e
        LEFT JOIN auth.users u
          ON regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
             = e.phone
        LEFT JOIN public.test_onboarding_applications a
          ON a.user_id = u.id
        LEFT JOIN public.profiles p
          ON p.id = u.id
        WHERE u.id IS NULL
           OR COALESCE(u.raw_app_meta_data->>'onboarding_channel', '')
              <> 'test_invite'
           OR a.id IS NULL
           OR a.invite_label <> 'waselnet-prod-pilot-20260822'
           OR a.requested_account_type <> e.requested_account_type
           OR a.verification_state <> 'test_only_pending'
           OR a.owner_review_status <> e.owner_review_status
           OR p.account_status <> 'pending_verification'
    ) THEN
        RAISE EXCEPTION
            'HOLD: an exact TEST_ONLY identity or application is not in the expected pending state.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM auth.users u
        WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g') IN (
            '967770000021',
            '967770000022',
            '967770000023'
        )
          AND (
              NOT EXISTS (
                  SELECT 1
                  FROM public.user_roles ur
                  WHERE ur.user_id = u.id
                    AND ur.role = 'customer'
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.user_roles ur
                  WHERE ur.user_id = u.id
                    AND ur.role <> 'customer'
              )
          )
    ) THEN
        RAISE EXCEPTION
            'HOLD: a pending TEST_ONLY identity does not have the exact customer-only baseline role.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.audit_events ae
        JOIN public.test_onboarding_applications a
          ON ae.entity_id = a.id::TEXT
        JOIN auth.users u
          ON u.id = a.user_id
        WHERE ae.action = 'ADMIN_REVIEW_TEST_ONBOARDING'
          AND regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g') IN (
              '967770000021',
              '967770000022',
              '967770000023'
          )
    ) THEN
        RAISE EXCEPTION
            'HOLD: at least one exact TEST_ONLY application already has an admin review audit event.';
    END IF;

    IF EXISTS (
        SELECT 1
        FROM auth.users u
        WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
              = '967770000022'
          AND (
              EXISTS (
                  SELECT 1
                  FROM public.networks n
                  WHERE n.created_by = u.id
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.network_memberships nm
                  WHERE nm.user_id = u.id
              )
          )
    ) THEN
        RAISE EXCEPTION
            'HOLD: owner applicant already has a network or membership before review.';
    END IF;

    RAISE NOTICE
        'HOSTED ADMIN REVIEW PREFLIGHT PASS: exact TEST_ONLY identities are pending, customer-only, unaudited, and mapped by normalized phone.';
END;
$$;

WITH review_plan(
    normalized_phone,
    expected_decision,
    expected_account_type
) AS (
    VALUES
        ('967770000021', 'approve', 'customer'),
        ('967770000022', 'approve', 'network_owner'),
        ('967770000023', 'reject', 'customer')
)
SELECT
    'PASS'::TEXT AS decision,
    rp.normalized_phone,
    a.id AS application_id,
    a.user_id,
    rp.expected_decision,
    rp.expected_account_type,
    a.verification_state,
    a.owner_review_status,
    p.account_status
FROM review_plan rp
JOIN auth.users u
  ON regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
     = rp.normalized_phone
JOIN public.test_onboarding_applications a
  ON a.user_id = u.id
JOIN public.profiles p
  ON p.id = u.id
ORDER BY rp.normalized_phone;

ROLLBACK;
