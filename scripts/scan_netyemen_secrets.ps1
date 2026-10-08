# NetYemen Secret/Key Prohibition Scan
# Scans every git-tracked text file for likely leaked credentials.
#
# How to suppress a finding (in order of preference):
#   1. Use an obviously fake value containing TEST_ONLY, TEST-ONLY, E2E_ONLY,
#      CI_ONLY / ci-only or REPLACE_WITH (generic password / api-key rules only).
#   2. Put an inline marker on the SAME line or the line directly ABOVE it:
#         secret-scan: allow-<reason>      e.g.  -- secret-scan: allow-numeric-limit
#   3. Add a precise entry (exact path + rule + value) to $allowList below.
# Never widen a pattern or add a directory-wide exclusion to make a finding go away.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Secret & Key Prohibition Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$repoRoot = Split-Path -Parent $PSScriptRoot
Set-Location $repoRoot

$violations = @()

# ---------------------------------------------------------------------------
# 1. Files: everything git tracks, minus binaries, lockfiles and build outputs.
# ---------------------------------------------------------------------------
$tracked = @(git -c core.quotepath=off ls-files)
if ($LASTEXITCODE -ne 0) {
    Write-Host "RESULT: HOLD (git ls-files failed; the scan must run inside the git checkout)" -ForegroundColor Red
    exit 1
}

$skipExtensions = @(
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".bmp",
    ".ttf", ".otf", ".woff", ".woff2",
    ".jar", ".jks", ".keystore", ".pdf", ".zip", ".gz", ".apk", ".aab",
    ".mp3", ".mp4",
    ".lock"
)
$skipPathPattern = '^(build|dist|\.dart_tool|owner_app/build|owner_app/\.dart_tool)/'
$maxBytes = 2MB

# ---------------------------------------------------------------------------
# 2. Rules. Patterns are .NET regular expressions and are case-sensitive
#    unless they start with (?i). PlaceholderOk = $true means a value that is
#    visibly a fake placeholder is accepted for that rule.
# ---------------------------------------------------------------------------
$rules = @(
    @{ Name = "jwt-like-key";            PlaceholderOk = $false; Pattern = 'eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.' },
    @{ Name = "supabase-secret-key";     PlaceholderOk = $false; Pattern = 'sb_secret_[A-Za-z0-9_-]{20,}' },
    @{ Name = "supabase-access-token";   PlaceholderOk = $false; Pattern = 'sbp_[a-f0-9]{40}' },
    @{ Name = "pem-private-key";         PlaceholderOk = $false; Pattern = '-----BEGIN (?:RSA |EC |DSA |OPENSSH |ENCRYPTED )?PRIVATE KEY-----' },
    @{ Name = "service-role-assignment"; PlaceholderOk = $false; Pattern = '(?i)service[_-]?role(?:[_-]?key)?\s*[:=]\s*[''"][A-Za-z0-9._\-+/=]{20,}[''"]' },
    @{ Name = "google-service-account";  PlaceholderOk = $false; Pattern = '"private_key"\s*:\s*"' },
    @{ Name = "aws-access-key-id";       PlaceholderOk = $false; Pattern = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' },
    @{ Name = "aws-secret-access-key";   PlaceholderOk = $false; Pattern = '(?i)aws_secret_access_key\s*[:=]\s*[''"]?[A-Za-z0-9/+=]{40}' },
    @{ Name = "sk-style-api-key";        PlaceholderOk = $false; Pattern = '\bsk-[A-Za-z0-9]{48}\b' },
    @{ Name = "sixteen-digit-number";    PlaceholderOk = $false; Pattern = '\b[0-9]{16}\b' },
    @{ Name = "hardcoded-password";      PlaceholderOk = $true;  Pattern = '(?i)password\s*[:=]\s*[''"][^''"]{8,}[''"]' },
    @{ Name = "hardcoded-api-key";       PlaceholderOk = $true;  Pattern = '(?i)api[_-]?key\s*[:=]\s*[''"][^''"]{10,}[''"]' }
)

# Inline allow marker (existing repository convention, e.g. allow-numeric-limit).
$allowMarkerPattern = 'secret-scan:\s*allow-[a-z0-9-]+'

# Values that are visibly fake. Applies only to rules with PlaceholderOk.
$placeholderPattern = '(?i)TEST[_-]ONLY|E2E[_-]ONLY|CI[_-]ONLY|REPLACE_WITH'

# A PEM header immediately followed by "..." is documentation, not a key.
$pemPlaceholderPattern = '-----BEGIN (?:RSA )?PRIVATE KEY-----(?:\\n|\s)*\.\.\.'

# Precise, reviewed exceptions: exact tracked path + rule name + the exact
# value fragment. Keep this list short; prefer placeholders or inline markers.
$allowList = @(
    # Widget-test fixture password typed into a fake auth repository.
    @{ Path = "test/features/auth/customer_auth_test.dart"; Rule = "hardcoded-password"; Value = "'Pilot1234'" }
)

# ---------------------------------------------------------------------------
# 3. Scan.
# ---------------------------------------------------------------------------
$scannedFiles = 0
$skippedFiles = 0

foreach ($relativePath in $tracked) {
    if ([string]::IsNullOrWhiteSpace($relativePath)) { continue }

    $extension = [System.IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    if ($skipExtensions -contains $extension) { $skippedFiles++; continue }
    if ($relativePath -match $skipPathPattern) { $skippedFiles++; continue }

    $fullPath = Join-Path $repoRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { $skippedFiles++; continue }
    if ((Get-Item -LiteralPath $fullPath).Length -gt $maxBytes) { $skippedFiles++; continue }

    $text = [System.IO.File]::ReadAllText($fullPath)
    # A NUL character means the file is binary.
    if ($text.IndexOf([char]0) -ge 0) { $skippedFiles++; continue }

    $scannedFiles++
    $lines = @($text -split "`r?`n")

    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ([string]::IsNullOrEmpty($line)) { continue }

        foreach ($rule in $rules) {
            $match = [regex]::Match($line, $rule.Pattern)
            if (-not $match.Success) { continue }

            # Inline marker on this line or on the line directly above.
            if ($line -cmatch $allowMarkerPattern) { continue }
            if ($index -gt 0 -and $lines[$index - 1] -cmatch $allowMarkerPattern) { continue }

            if ($rule.PlaceholderOk -and $match.Value -match $placeholderPattern) { continue }
            if ($rule.Name -eq "pem-private-key" -and $line -cmatch $pemPlaceholderPattern) { continue }

            $allowed = $false
            foreach ($entry in $allowList) {
                if ($entry.Path -ceq $relativePath -and $entry.Rule -eq $rule.Name -and $match.Value.Contains($entry.Value)) {
                    $allowed = $true
                }
            }
            if ($allowed) { continue }

            # The matched value is deliberately not printed.
            $lineNumber = $index + 1
            $violations += "Possible secret in ${relativePath}:${lineNumber} (rule: $($rule.Name))"
        }
    }
}

Write-Host "Scanned $scannedFiles tracked text files ($skippedFiles skipped as binary, lockfile or build output)."

# A scan that looked at nothing must never report PASS.
if ($scannedFiles -eq 0) {
    Write-Host "RESULT: HOLD (zero files scanned)" -ForegroundColor Red
    exit 1
}

if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (no secrets detected in $scannedFiles files)" -ForegroundColor Green
    exit 0
}
