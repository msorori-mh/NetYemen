-- WASEL NET production post-verify for exact hosted TEST_ONLY admin review.
-- READ ONLY: verifies terminal states, least privilege, audit evidence, and no
-- automatic network creation after the authorized admin-console decisions.
BEGIN;
SET TRANSACTION READ ONLY;

DO $$
DECLARE
    v_count BIGINT;
    v_rls_enabled BOOLEAN;
    v_rls_forced BOOLEAN;
BEGIN
    IF to_regclass('public.test_onboarding_applications') IS NULL
       OR to_regprocedure(
            'public.admin_review_test_onboarding(uuid,text,text)'
          ) IS NULL THEN
        RAISE EXCEPTION
            'HOLD: hosted onboarding review objects are missing.';
    END IF;

    IF EXISTS (
        WITH expected(
            phone,
            account_status,
            verification_state,
            owner_review_status
        ) AS (
            VALUES
                (
                    '967770000021',
                    'active',
                    'test_admin_approved',
                    'not_requested'
                ),
                (
                    '967770000022',
                    'active',
                    'test_admin_approved',
                    'approved'
                ),
                (
                    '967770000023',
                    'suspended',
                    'rejected',
                    'not_requested'
                )
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
           OR a.id IS NULL
           OR p.id IS NULL
           OR a.invite_label <> 'waselnet-prod-pilot-20260822'
           OR p.account_status <> e.account_status
           OR a.verification_state <> e.verification_state
           OR a.owner_review_status <> e.owner_review_status
    ) THEN
        RAISE EXCEPTION
            'HOLD: an exact TEST_ONLY identity is not in its expected terminal state.';
    END IF;

    SELECT count(*)
    INTO v_count
    FROM public.user_roles ur
    JOIN auth.users u
      ON u.id = ur.user_id
    WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g') IN (
        '967770000021',
        '967770000022',
        '967770000023'
    );

    IF v_count <> 4 THEN
        RAISE EXCEPTION
            'HOLD: exact TEST_ONLY role count is %, expected 4.',
            v_count;
    END IF;

    IF EXISTS (
        WITH expected(phone, expected_owner_role) AS (
            VALUES
                ('967770000021', FALSE),
                ('967770000022', TRUE),
                ('967770000023', FALSE)
        )
        SELECT 1
        FROM expected e
        JOIN auth.users u
          ON regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
             = e.phone
        WHERE NOT EXISTS (
                  SELECT 1
                  FROM public.user_roles ur
                  WHERE ur.user_id = u.id
                    AND ur.role = 'customer'
              )
           OR EXISTS (
                  SELECT 1
                  FROM public.user_roles ur
                  WHERE ur.user_id = u.id
                    AND ur.role = 'network_owner'
              ) IS DISTINCT FROM e.expected_owner_role
           OR EXISTS (
                  SELECT 1
                  FROM public.user_roles ur
                  WHERE ur.user_id = u.id
                    AND ur.role NOT IN ('customer', 'network_owner')
              )
    ) THEN
        RAISE EXCEPTION
            'HOLD: exact TEST_ONLY least-privilege role mapping is incorrect.';
    END IF;

    SELECT count(*)
    INTO v_count
    FROM public.audit_events ae
    JOIN public.test_onboarding_applications a
      ON ae.entity_id = a.id::TEXT
    JOIN auth.users u
      ON u.id = a.user_id
    WHERE ae.action = 'ADMIN_REVIEW_TEST_ONBOARDING'
      AND ae.result = 'success'
      AND regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g') IN (
          '967770000021',
          '967770000022',
          '967770000023'
      )
      AND (
          (
              regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
              IN ('967770000021', '967770000022')
              AND ae.reason_code = 'TEST_ADMIN_APPROVED'
              AND ae.metadata->>'decision' = 'approve'
          )
          OR (
              regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
              = '967770000023'
              AND ae.reason_code = 'TEST_ADMIN_REJECTED'
              AND ae.metadata->>'decision' = 'reject'
          )
      )
      AND ae.actor_user_id IS NOT NULL
      AND EXISTS (
          SELECT 1
          FROM public.user_roles actor_role
          WHERE actor_role.user_id = ae.actor_user_id
            AND actor_role.role = 'platform_admin'
      );

    IF v_count <> 3 THEN
        RAISE EXCEPTION
            'HOLD: exact TEST_ONLY review audit count is %, expected 3.',
            v_count;
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
            'HOLD: owner review created a network or membership automatically.';
    END IF;

    SELECT relrowsecurity, relforcerowsecurity
    INTO v_rls_enabled, v_rls_forced
    FROM pg_class
    WHERE oid = 'public.test_onboarding_applications'::regclass;

    IF NOT COALESCE(v_rls_enabled, FALSE)
       OR NOT COALESCE(v_rls_forced, FALSE) THEN
        RAISE EXCEPTION
            'HOLD: test_onboarding_applications RLS is not enabled and forced.';
    END IF;

    IF has_function_privilege(
        'anon',
        'public.admin_review_test_onboarding(uuid,text,text)',
        'EXECUTE'
    ) OR NOT has_function_privilege(
        'authenticated',
        'public.admin_review_test_onboarding(uuid,text,text)',
        'EXECUTE'
    ) THEN
        RAISE EXCEPTION
            'HOLD: admin review RPC grants are incorrect.';
    END IF;

    RAISE NOTICE
        'HOSTED ADMIN REVIEW POST-VERIFY PASS: exact decisions, terminal states, least privilege, audits, and forced RLS verified.';
END;
$$;

SELECT
    'PASS'::TEXT AS decision,
    regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g')
        AS normalized_phone,
    a.id AS application_id,
    a.requested_account_type,
    p.account_status,
    a.verification_state,
    a.owner_review_status,
    (
        SELECT array_agg(ur.role ORDER BY ur.role)
        FROM public.user_roles ur
        WHERE ur.user_id = u.id
    ) AS roles,
    (
        SELECT count(*)
        FROM public.audit_events ae
        WHERE ae.action = 'ADMIN_REVIEW_TEST_ONBOARDING'
          AND ae.entity_id = a.id::TEXT
    ) AS review_audits
FROM auth.users u
JOIN public.test_onboarding_applications a
  ON a.user_id = u.id
JOIN public.profiles p
  ON p.id = u.id
WHERE regexp_replace(COALESCE(u.phone, ''), '[^0-9]', '', 'g') IN (
    '967770000021',
    '967770000022',
    '967770000023'
)
ORDER BY normalized_phone;

ROLLBACK;
