# NetYemen Secret/Key Prohibition Scan
# Scans every text file in the repository for likely leaked credentials.
#
# Files: the whole working tree is enumerated recursively (Get-ChildItem
# -Recurse -File -Force), minus tool/build directories, binary files and
# lockfiles. When the tree is a git checkout, files that git ignores
# (android/key.properties, .env, admin/config.js, ...) are skipped because
# they cannot be committed by accident; everything else is scanned whether or
# not it is tracked yet.
#
# How to suppress a finding (in order of preference):
#   1. Use an obviously fake value containing TEST_ONLY, CI_ONLY / ci-only,
#      E2E_ONLY, REPLACE_WITH / replace-locally, example, placeholder or
#      changeme (generic assignment rules only; never for real key formats).
#   2. Put an inline marker on the SAME line or the line directly ABOVE it:
#         secret-scan: allow-<reason>      e.g.  -- secret-scan: allow-numeric-limit
#   3. Add a precise entry (exact path + rule + value) to $allowList below.
# Never widen a pattern or add a directory-wide exclusion to make a finding go away.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Secret & Key Prohibition Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$repoRoot = Split-Path -Parent $PSScriptRoot

$violations = @()

# ---------------------------------------------------------------------------
# 1. Files.
# ---------------------------------------------------------------------------
# Directory names that are never scanned, at any depth (tool caches and build
# outputs). Case-sensitive, whole path segment.
$excludedSegmentPattern = '(^|/)(\.git|build|\.dart_tool|node_modules|\.gradle|\.idea|\.pub-cache|\.temp|\.branches)(/|$)'

$skipExtensions = @(
    ".png", ".jpg", ".jpeg", ".gif", ".ico", ".webp", ".bmp",
    ".ttf", ".otf", ".woff", ".woff2",
    ".jar", ".jks", ".keystore", ".pdf", ".zip", ".gz", ".apk", ".aab",
    ".mp3", ".mp4",
    ".lock"
)
$skipFileNames = @("package-lock.json", "pnpm-lock.yaml", "yarn.lock", "deno.lock")
$maxBytes = 2MB

$candidates = New-Object System.Collections.Generic.List[string]
foreach ($entry in @(Get-ChildItem -LiteralPath $repoRoot -Force)) {
    if ($entry.Name -cmatch $excludedSegmentPattern) { continue }
    if ($entry.PSIsContainer) {
        # -Force: on Linux and macOS names starting with a dot (.github) are
        # hidden and would otherwise be skipped.
        foreach ($file in @(Get-ChildItem -LiteralPath $entry.FullName -Recurse -File -Force)) {
            $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName).Replace('\', '/')
            if ($relativePath -cmatch $excludedSegmentPattern) { continue }
            $candidates.Add($relativePath)
        }
    } else {
        $candidates.Add($entry.Name)
    }
}

# Files ignored by git are local-only (never committed). Exit code 0 = some
# paths are ignored, 1 = none are; anything else (not a git checkout) means
# no filtering.
$gitIgnored = @{}
if ($candidates.Count -gt 0) {
    try {
        $ignoredPaths = @($candidates | git -C $repoRoot -c core.quotepath=off check-ignore --stdin)
        if ($LASTEXITCODE -eq 0) {
            foreach ($ignoredPath in $ignoredPaths) { $gitIgnored[$ignoredPath] = $true }
        } elseif ($LASTEXITCODE -ne 1) {
            Write-Host "Note: git check-ignore is unavailable here; scanning every file." -ForegroundColor Yellow
        }
    } catch {
        Write-Host "Note: git is unavailable here; scanning every file." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
# 2. Rules. Patterns are .NET regular expressions and are case-sensitive
#    unless they start with (?i). Placeholder = $true means a value that is
#    visibly a fake placeholder is accepted for that rule. Scope = "line"
#    tests each line; Scope = "file" tests the whole text (multi-line keys).
# ---------------------------------------------------------------------------
$rules = @(
    @{ Name = "jwt-like-token";          Scope = "line"; Placeholder = $false; Pattern = 'eyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]*' },
    @{ Name = "supabase-secret-key";     Scope = "line"; Placeholder = $false; Pattern = 'sb_secret_[A-Za-z0-9_-]{20,}' },
    @{ Name = "supabase-access-token";   Scope = "line"; Placeholder = $false; Pattern = 'sbp_[a-f0-9]{40}' },
    @{ Name = "pem-private-key";         Scope = "file"; Placeholder = $false; Pattern = '-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----(?:\\n|\\r|\s)*[A-Za-z0-9+/=]{40,}' },
    @{ Name = "service-role-assignment"; Scope = "line"; Placeholder = $true;  Pattern = '(?i)service[_-]?role(?:[_-]?key)?\s*[:=]\s*[''"][A-Za-z0-9._\-+/=]{20,}[''"]' },
    @{ Name = "google-service-account";  Scope = "line"; Placeholder = $false; Pattern = '"private_key"\s*:\s*"[^"]{20,}' },
    @{ Name = "github-token";            Scope = "line"; Placeholder = $false; Pattern = '\b(?:gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{22,})' },
    @{ Name = "aws-access-key-id";       Scope = "line"; Placeholder = $false; Pattern = '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b' },
    @{ Name = "aws-secret-access-key";   Scope = "line"; Placeholder = $false; Pattern = '(?i)aws_secret_access_key\s*[:=]\s*[''"]?[A-Za-z0-9/+=]{40}' },
    @{ Name = "google-api-key";          Scope = "line"; Placeholder = $false; Pattern = 'AIza[0-9A-Za-z_-]{35}' },
    @{ Name = "slack-token";             Scope = "line"; Placeholder = $false; Pattern = '\bxox[baprs]-[A-Za-z0-9-]{10,}' },
    @{ Name = "slack-webhook";           Scope = "line"; Placeholder = $false; Pattern = 'hooks\.slack\.com/services/T[A-Za-z0-9_]+/B[A-Za-z0-9_]+/[A-Za-z0-9_]+' },
    @{ Name = "sk-style-api-key";        Scope = "line"; Placeholder = $false; Pattern = '\bsk-(?:proj-|ant-)?[A-Za-z0-9_-]{40,}' },
    @{ Name = "sixteen-digit-number";    Scope = "line"; Placeholder = $false; Pattern = '\b[0-9]{16}\b' },
    @{ Name = "database-url-password";   Scope = "line"; Placeholder = $true;  Pattern = 'postgres(?:ql)?://[A-Za-z0-9_.-]+:(?!postgres@)(?![$<\[{%])[^@\s''"]{6,}@' },
    @{ Name = "hardcoded-password";      Scope = "line"; Placeholder = $true;  Pattern = '(?i)password\s*[:=]\s*[''"](?![$<{])[^''"\s]{8,}[''"]' },
    @{ Name = "hardcoded-api-key";       Scope = "line"; Placeholder = $true;  Pattern = '(?i)api[_-]?key\s*[:=]\s*[''"](?![$<{])[^''"\s]{10,}[''"]' },
    @{ Name = "hardcoded-secret";        Scope = "line"; Placeholder = $true;  Pattern = '(?i)\b(?:auth_token|client_secret|shared_secret|secret_key|internal_key)\s*[:=]\s*[''"](?![$<{])[^''"\s]{16,}[''"]' }
)

# Inline allow marker (existing repository convention, e.g. allow-numeric-limit).
$allowMarkerPattern = 'secret-scan:\s*allow-[a-z0-9-]+'

# Values that are visibly fake. Applies only to rules with Placeholder = $true.
$placeholderPattern = '(?i)TEST[_-]ONLY|E2E[_-]ONLY|CI[_-]ONLY|REPLACE[_-](?:WITH|LOCALLY)|example|placeholder|changeme'

# Precise, reviewed exceptions: exact path + rule name + the exact value
# fragment. Keep this list short; prefer placeholders or inline markers.
$allowList = @(
    # Firebase Android client API key. It is a PUBLIC client identifier that
    # ships inside every APK, not a server credential; it is protected by the
    # API-key restrictions configured in Google Cloud (Android package + SHA-1,
    # see docs/OPERATIONS-RUNBOOK.md), not by secrecy. Only this one file is
    # exempt, and only for the google-api-key rule.
    @{ Path = "android/app/google-services.json"; Rule = "google-api-key"; Value = "AIza" },
    # Widget-test fixture password typed into a fake auth repository.
    @{ Path = "test/features/auth/customer_auth_test.dart"; Rule = "hardcoded-password"; Value = "'Pilot1234'" }
)

function Test-AllowListed {
    param([string]$RelativePath, [string]$RuleName, [string]$MatchValue)
    foreach ($entry in $allowList) {
        if ($entry.Path -ceq $RelativePath -and $entry.Rule -ceq $RuleName -and $MatchValue.Contains($entry.Value)) {
            return $true
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# 3. Scan.
# ---------------------------------------------------------------------------
$scannedFiles = 0
$skippedBinary = 0
$skippedIgnored = 0

foreach ($relativePath in $candidates) {
    if ($gitIgnored.ContainsKey($relativePath)) { $skippedIgnored++; continue }

    $extension = [System.IO.Path]::GetExtension($relativePath).ToLowerInvariant()
    $fileName = [System.IO.Path]::GetFileName($relativePath)
    if ($skipExtensions -contains $extension) { $skippedBinary++; continue }
    if ($skipFileNames -contains $fileName) { $skippedBinary++; continue }

    $fullPath = Join-Path $repoRoot $relativePath
    if ((Get-Item -LiteralPath $fullPath -Force).Length -gt $maxBytes) {
        # Never skip silently: an oversized text file could hide anything.
        $violations += "File is larger than 2 MB and was not scanned: $relativePath (add its extension to the binary list only if it really is binary)"
        continue
    }

    $text = [System.IO.File]::ReadAllText($fullPath)
    # A NUL character means the file is binary.
    if ($text.IndexOf([char]0) -ge 0) { $skippedBinary++; continue }

    $scannedFiles++
    $lines = @($text -split "`r?`n")

    foreach ($rule in $rules) {
        if ($rule.Scope -eq "file") {
            foreach ($match in [regex]::Matches($text, $rule.Pattern)) {
                $lineNumber = ($text.Substring(0, $match.Index) -split "`n").Count
                $lineText = $lines[$lineNumber - 1]
                if ($lineText -cmatch $allowMarkerPattern) { continue }
                if ($lineNumber -gt 1 -and $lines[$lineNumber - 2] -cmatch $allowMarkerPattern) { continue }
                if ($rule.Placeholder -and $match.Value -match $placeholderPattern) { continue }
                if (Test-AllowListed -RelativePath $relativePath -RuleName $rule.Name -MatchValue $match.Value) { continue }
                $violations += "Possible secret in ${relativePath}:${lineNumber} (rule: $($rule.Name))"
            }
            continue
        }

        for ($index = 0; $index -lt $lines.Count; $index++) {
            $line = $lines[$index]
            if ([string]::IsNullOrEmpty($line)) { continue }

            $match = [regex]::Match($line, $rule.Pattern)
            if (-not $match.Success) { continue }

            # Inline marker on this line or on the line directly above.
            if ($line -cmatch $allowMarkerPattern) { continue }
            if ($index -gt 0 -and $lines[$index - 1] -cmatch $allowMarkerPattern) { continue }

            if ($rule.Placeholder -and $match.Value -match $placeholderPattern) { continue }
            if (Test-AllowListed -RelativePath $relativePath -RuleName $rule.Name -MatchValue $match.Value) { continue }

            # The matched value is deliberately not printed.
            $lineNumber = $index + 1
            $violations += "Possible secret in ${relativePath}:${lineNumber} (rule: $($rule.Name))"
        }
    }
}

Write-Host "Scanned $scannedFiles text files under $repoRoot ($skippedBinary binary or lockfile, $skippedIgnored git-ignored local files skipped)."

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
