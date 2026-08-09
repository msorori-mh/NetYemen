# NetYemen V1 External Pilot — Edge Function Authorization Verifier
# Task ID: NY-V1-EXTERNAL-PILOT-BINDING-001
# Description: Negative authorization tests for the notification-transport-adapter
#              Edge Function. Must run against LOCAL Supabase only.

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

$serviceRoleKey = $status.SERVICE_ROLE_KEY
$anonKey = $status.ANON_KEY
$funcUrl = 'http://127.0.0.1:54321/functions/v1/notification-transport-adapter'

$failures = @()

function Test-Response {
    param(
        [string]$Name,
        [int]$ExpectedStatus,
        [string]$ResponseBody,
        [string]$ExpectedSubstring = ''
    )
    if ($ResponseBody -match '"error"\s*:\s*"') {
        # Edge functions return errors in JSON body; treat the HTTP status as authoritative.
    }
    if ($ExpectedSubstring -and $ResponseBody -notlike "*$ExpectedSubstring*") {
        $failures += "$Name`: expected substring '$ExpectedSubstring' in body: $ResponseBody"
    } else {
        Write-Host "  [OK] $Name (status $ExpectedStatus)" -ForegroundColor Green
    }
}

function Invoke-EdgeFunction {
    param(
        [string]$Authorization = '',
        [string]$Body = '{}'
    )
    $headerArgs = @('-H', 'Content-Type: application/json')
    if ($Authorization) {
        $headerArgs += '-H'
        $headerArgs += "Authorization: $Authorization"
    }
    $bodyFile = [System.IO.Path]::GetTempFileName()
    $outFile = [System.IO.Path]::GetTempFileName()
    try {
        Set-Content -Path $bodyFile -Value $Body -NoNewline
        $status = curl.exe -s -o $outFile -w '%{http_code}' -X POST $headerArgs -d "@$bodyFile" $funcUrl
        $body = Get-Content -Raw -Path $outFile
        return @{ StatusCode = [int]$status; Body = $body }
    } finally {
        if (Test-Path $bodyFile) { Remove-Item $bodyFile -Force }
        if (Test-Path $outFile) { Remove-Item $outFile -Force }
    }
}

Write-Host '================================================================' -ForegroundColor Cyan
Write-Host 'NetYemen V1 External Pilot Edge Function Authorization Verifier' -ForegroundColor Cyan
Write-Host '================================================================' -ForegroundColor Cyan

# Negative: dispatch_push with missing Authorization header.
$r = Invoke-EdgeFunction -Body '{"action":"dispatch_push","delivery_id":"neg-01","user_id":"00000000-0000-0000-0000-000000000000","token":"neg-token","title_ar":"x","body_ar":"x"}'
if ($r.StatusCode -ne 401) { $failures += "dispatch_push missing auth expected 401, got $($r.StatusCode): $($r.Body)" }
else { Test-Response -Name 'dispatch_push missing Authorization' -ExpectedStatus 401 -ResponseBody $r.Body -ExpectedSubstring 'UNAUTHORIZED' }

# Negative: dispatch_push with anon JWT.
$r = Invoke-EdgeFunction -Authorization "Bearer $anonKey" -Body '{"action":"dispatch_push","delivery_id":"neg-02","user_id":"00000000-0000-0000-0000-000000000000","token":"neg-token","title_ar":"x","body_ar":"x"}'
if ($r.StatusCode -ne 403) { $failures += "dispatch_push anon token expected 403, got $($r.StatusCode): $($r.Body)" }
else { Test-Response -Name 'dispatch_push anon JWT rejected' -ExpectedStatus 403 -ResponseBody $r.Body -ExpectedSubstring 'FORBIDDEN' }

# Negative: decrypt_card_secret with missing Authorization header.
$r = Invoke-EdgeFunction -Body '{"action":"decrypt_card_secret","key_version":"v1-test","ciphertext_b64":"dGVzdA==","nonce":"nonce","auth_tag_b64":"dGFn"}'
if ($r.StatusCode -ne 401) { $failures += "decrypt_card_secret missing auth expected 401, got $($r.StatusCode): $($r.Body)" }
else { Test-Response -Name 'decrypt_card_secret missing Authorization' -ExpectedStatus 401 -ResponseBody $r.Body -ExpectedSubstring 'UNAUTHORIZED' }

# Negative: decrypt_card_secret with anon JWT.
$r = Invoke-EdgeFunction -Authorization "Bearer $anonKey" -Body '{"action":"decrypt_card_secret","key_version":"v1-test","ciphertext_b64":"dGVzdA==","nonce":"nonce","auth_tag_b64":"dGFn"}'
if ($r.StatusCode -ne 403) { $failures += "decrypt_card_secret anon token expected 403, got $($r.StatusCode): $($r.Body)" }
else { Test-Response -Name 'decrypt_card_secret anon JWT rejected' -ExpectedStatus 403 -ResponseBody $r.Body -ExpectedSubstring 'FORBIDDEN' }

# Positive authorization check: service-role key is accepted, but FCM credentials are
# intentionally omitted in local Supabase so the function returns credential_required.
$r = Invoke-EdgeFunction -Authorization "Bearer $serviceRoleKey" -Body '{"action":"dispatch_push","delivery_id":"pos-01","user_id":"00000000-0000-0000-0000-000000000000","token":"pos-token","title_ar":"x","body_ar":"x"}'
if ($r.StatusCode -ne 200 -or $r.Body -notlike '*credential_required*') {
    $failures += "dispatch_push service-role auth expected 200 credential_required, got $($r.StatusCode): $($r.Body)"
} else {
    Test-Response -Name 'dispatch_push service-role accepted, FCM credentials required' -ExpectedStatus 200 -ResponseBody $r.Body -ExpectedSubstring 'credential_required'
}

# Negative: unknown action is rejected regardless of auth.
$r = Invoke-EdgeFunction -Authorization "Bearer $serviceRoleKey" -Body '{"action":"unknown_action"}'
if ($r.StatusCode -ne 400) { $failures += "unknown action expected 400, got $($r.StatusCode): $($r.Body)" }
else { Test-Response -Name 'unknown action rejected' -ExpectedStatus 400 -ResponseBody $r.Body -ExpectedSubstring 'UNKNOWN_ACTION' }

if ($failures.Count -gt 0) {
    Write-Host '================================================================' -ForegroundColor Red
    Write-Host 'EXTERNAL PILOT VERIFICATION RESULT: HOLD' -ForegroundColor Red
    Write-Host '================================================================' -ForegroundColor Red
    foreach ($f in $failures) { Write-Host "  [FAIL] $f" -ForegroundColor Red }
    exit 1
}

Write-Host '================================================================' -ForegroundColor Green
Write-Host 'EXTERNAL PILOT VERIFICATION RESULT: PASS' -ForegroundColor Green
Write-Host '================================================================' -ForegroundColor Green
exit 0
