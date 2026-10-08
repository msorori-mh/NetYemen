$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# Same CLI version as .github/workflows/supabase-core-ci.yml. An unpinned
# `npx supabase` resolves to whatever is latest that day, which may not match
# the containers the workflow started with the pinned version.
$supabaseCli = 'supabase@2.109.1'

$rawStatus = (npx --yes $supabaseCli status --output json 2>$null) -join "`n"
$jsonStart = $rawStatus.IndexOf('{')
$jsonEnd = $rawStatus.LastIndexOf('}')
if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) {
    throw 'Could not parse Supabase status JSON.'
}
$status = $rawStatus.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
if (-not $status.DB_URL -or $status.DB_URL -notmatch '127\.0\.0\.1|localhost') {
    throw 'LOCAL_ONLY guard failed: refusing to run without loopback Supabase.'
}

# Suites must be numbered uniquely and contiguously from 001. The upper bound
# follows the files that exist (at least the 30 current suites), so adding
# 031, 032, ... does not require editing this script, while a gap, a duplicate
# number or a deleted baseline suite still fails.
$minimumTestCount = 30
$tests = @(Get-ChildItem 'supabase/tests/*.sql' | Sort-Object Name)
$actualTests = @($tests | ForEach-Object { $_.BaseName.Substring(0,3) })
$expectedTestCount = [Math]::Max($tests.Count, $minimumTestCount)
$expectedTests = @(1..$expectedTestCount | ForEach-Object { '{0:D3}' -f $_ })
if (Compare-Object $expectedTests $actualTests) {
    throw "SQL suite numbering must be unique and contiguous 001..$('{0:D3}' -f $expectedTestCount): $($actualTests -join ', ')"
}

npx --yes $supabaseCli db reset --no-seed 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Fresh local migration reset failed.' }

# The reset wiped the vault, so the card key must be created again BEFORE any
# suite runs: the card suites (013-015, 027, ...) encrypt and decrypt with it.

@"
SELECT vault.create_secret(
  'TEST_ONLY_LOCAL_CARD_KEY_DO_NOT_USE',
  'card_master_key',
  'Disposable local-test-only card key'
);
"@ |
    docker exec -i supabase_db_netyemen-local psql -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw 'Disposable card vault test key setup failed.' }

foreach ($test in $tests) {
    Write-Host "RUN $($test.Name)" -ForegroundColor Cyan
    $testSql = Get-Content -Raw $test.FullName

    # supabase test db resolves \ir from supabase/tests, while this verifier
    # streams SQL through docker exec from the repository root. Inline the
    # exact production verifier artifacts so both runners execute the same SQL.
    if ($test.Name -eq '019_hosted_admin_review_verifiers.sql') {
        $preflight = Get-Content -Raw (
            Join-Path $repoRoot 'supabase/verification/017_hosted_admin_review_production_preflight.sql'
        )
        $postverify = Get-Content -Raw (
            Join-Path $repoRoot 'supabase/verification/017_hosted_admin_review_production_postverify.sql'
        )
        $testSql = $testSql.Replace(
            '\ir ../verification/017_hosted_admin_review_production_preflight.sql',
            $preflight
        )
        $testSql = $testSql.Replace(
            '\ir ../verification/017_hosted_admin_review_production_postverify.sql',
            $postverify
        )
    }

    $testSql |
        docker exec -i supabase_db_netyemen-local psql -U postgres -d postgres -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "SQL suite failed: $($test.Name)" }
}

# Real concurrent sessions against the purchase and deposit RPCs. The harness
# generates fresh identifiers, so it can run on the database the suites used.
# `python3` is the name on Linux/macOS (CI); plain `python` on Windows.
$pythonCommand = Get-Command python3 -ErrorAction SilentlyContinue
if (-not $pythonCommand) { $pythonCommand = Get-Command python -ErrorAction SilentlyContinue }
if (-not $pythonCommand) { throw 'Python 3 is required for scripts/test_commerce_concurrency.py.' }
& $pythonCommand.Source scripts/test_commerce_concurrency.py
if ($LASTEXITCODE -ne 0) { throw 'Commerce concurrency test failed.' }

& (Join-Path $PSScriptRoot 'reset_netyemen_local_pilot.ps1')

$seedCheck = docker exec supabase_db_netyemen-local psql -U postgres -d postgres -Atc @'
SELECT CASE WHEN
  (SELECT count(*) FROM auth.users WHERE email LIKE '%@pilot.netyemen.test') = 8 AND
  (SELECT count(*) FROM public.networks WHERE commercial_name LIKE 'TEST_ONLY%') = 2 AND
  (SELECT count(*) FROM public.network_packages WHERE name LIKE 'TEST_ONLY%') = 3 AND
  (SELECT count(*) FROM public.support_cases WHERE subject LIKE 'TEST_ONLY%') >= 1 AND
  (SELECT binding_status FROM public.notification_transport_config WHERE id=1) = 'approved_pending_secrets' AND
  NOT EXISTS (SELECT 1 FROM public.card_fulfillment_records WHERE secret_payload_storage_path IS NOT NULL OR secret_payload_retrieval_token IS NOT NULL)
THEN 'PASS' ELSE 'FAIL' END;
'@
if ($seedCheck.Trim() -ne 'PASS') { throw 'TEST_ONLY pilot seed verification failed.' }

Write-Host 'NETYEMEN V1 INTEGRATED LOCAL PILOT VERIFICATION: PASS' -ForegroundColor Green
exit 0
