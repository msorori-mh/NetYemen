# NetYemen Secret/Key Prohibition Scan
# Scans source files for likely leaked secrets, plaintext card numbers, JWTs, etc.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Secret & Key Prohibition Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()

$scanPaths = @(
    "lib/**/*.dart",
    "supabase/**/*.sql",
    "scripts/**/*.ps1"
)

$forbiddenPatterns = @(
    'eyJ[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*\.[A-Za-z0-9_-]*', # JWT
    'sk-[a-zA-Z0-9]{48}',                                 # Supabase service role key shape
    '\b[0-9]{16}\b',                                      # 16-digit card/account numbers
    'password\s*=\s*[''"][^''"]{8,}[''"]',              # hardcoded passwords
    'api[_-]?key\s*=\s*[''"][^''"]{10,}[''"]'           # hardcoded API keys
)

foreach ($pattern in $forbiddenPatterns) {
    $matches = Select-String -Path $scanPaths -Pattern $pattern -ErrorAction SilentlyContinue
    foreach ($match in $matches) {
        $violations += "Possible secret in $($match.Path):$($match.LineNumber) matching '$pattern'"
    }
}

if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (no obvious secrets detected)" -ForegroundColor Green
    exit 0
}
