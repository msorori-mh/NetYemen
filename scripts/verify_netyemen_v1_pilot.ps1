$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$rawStatus = (npx supabase status --output json 2>$null) -join "`n"
$jsonStart = $rawStatus.IndexOf('{')
$jsonEnd = $rawStatus.LastIndexOf('}')
if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) {
    throw 'Could not parse Supabase status JSON.'
}
$status = $rawStatus.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
if (-not $status.DB_URL -or $status.DB_URL -notmatch '127\.0\.0\.1|localhost') {
    throw 'LOCAL_ONLY guard failed: refusing to run without loopback Supabase.'
}

$expectedTests = 1..15 | ForEach-Object { '{0:D3}' -f $_ }
$tests = Get-ChildItem 'supabase/tests/*.sql' | Sort-Object Name
$actualTests = $tests | ForEach-Object { $_.BaseName.Substring(0,3) }
if (Compare-Object $expectedTests $actualTests) {
    throw "SQL suite numbering must be unique and contiguous 001..015: $($actualTests -join ', ')"
}

npx supabase db reset --no-seed 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Fresh local migration reset failed.' }

foreach ($test in $tests) {
    Write-Host "RUN $($test.Name)" -ForegroundColor Cyan
    Get-Content -Raw $test.FullName |
        docker exec -i supabase_db_netyemen-local psql -U postgres -d postgres -v ON_ERROR_STOP=1
    if ($LASTEXITCODE -ne 0) { throw "SQL suite failed: $($test.Name)" }
}

python scripts/test_commerce_concurrency.py
if ($LASTEXITCODE -ne 0) { throw 'Concurrent last-unit test failed.' }

& scripts/reset_netyemen_local_pilot.ps1

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
