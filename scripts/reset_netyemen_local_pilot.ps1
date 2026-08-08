$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$status = npx supabase status --output json 2>$null | ConvertFrom-Json
if (-not $status.DB_URL -or $status.DB_URL -notmatch '127\.0\.0\.1|localhost') {
    throw 'LOCAL_ONLY guard failed: Supabase DB_URL is not loopback.'
}

npx supabase db reset --no-seed
if ($LASTEXITCODE -ne 0) { throw 'Local database reset failed.' }

Get-Content -Raw 'supabase/seed.sql' |
    docker exec -i supabase_db_netyemen-local psql -U postgres -d postgres -v ON_ERROR_STOP=1
if ($LASTEXITCODE -ne 0) { throw 'TEST_ONLY pilot seed failed.' }

Write-Host 'TEST_ONLY local pilot reset and seed: PASS' -ForegroundColor Green
