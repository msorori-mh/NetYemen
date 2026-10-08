$ErrorActionPreference = 'Continue'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

# Same CLI version as .github/workflows/supabase-core-ci.yml. An unpinned
# `npx supabase` resolves to whatever is latest that day, which may not match
# the containers the workflow started with the pinned version.
$supabaseCli = 'supabase@2.109.1'

# The CLI may print notices around the JSON document; parse only the object.
$rawStatus = (npx --yes $supabaseCli status --output json 2>$null) -join "`n"
$jsonStart = $rawStatus.IndexOf('{')
$jsonEnd = $rawStatus.LastIndexOf('}')
if ($jsonStart -lt 0 -or $jsonEnd -le $jsonStart) {
    throw 'Could not parse Supabase status JSON.'
}
$status = $rawStatus.Substring($jsonStart, $jsonEnd - $jsonStart + 1) | ConvertFrom-Json
if (-not $status.DB_URL -or $status.DB_URL -notmatch '127\.0\.0\.1|localhost') {
    throw 'LOCAL_ONLY guard failed: Supabase DB_URL is not loopback.'
}

npx --yes $supabaseCli db reset --no-seed 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Local database reset failed.' }

# supabase/seed.sql refuses to run unless the session opts in explicitly with
# app.allow_local_seed = 'on' (and the database is local and holds no real
# accounts). psql runs -c and -f in one session, so the SET applies to the seed.
# This script is the ONLY supported way to apply the seed; automatic seeding is
# disabled in supabase/config.toml.
Get-Content -Raw 'supabase/seed.sql' |
    docker exec -i supabase_db_netyemen-local psql -U postgres -d postgres -v ON_ERROR_STOP=1 `
        -c "SET app.allow_local_seed = 'on'" -f -
if ($LASTEXITCODE -ne 0) { throw 'TEST_ONLY pilot seed failed.' }

Write-Host 'TEST_ONLY local pilot reset and seed: PASS' -ForegroundColor Green
