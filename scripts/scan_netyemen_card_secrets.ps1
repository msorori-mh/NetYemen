# NetYemen Card Secret Prohibition Scan (OD-CARD-01)
# Ensures no plaintext card/voucher secret is stored by the schema or committed
# in source: SQL (migrations, tests, verification, seed), the Flutter apps,
# the static admin console and the Edge Functions.
#
# Synthetic test values must contain TEST_ONLY; a reviewed exception can be
# marked on the same line with:   card-secret-scan: allow-<reason>

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Card Secret Prohibition Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()

# Repository root derived from this script's location (scripts/ -> repo root).
# The previous hard-coded Windows path did not exist on CI, so the scan matched
# zero files and still printed PASS.
$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib/netyemen_sql.ps1')

# ---------------------------------------------------------------------------
# 1. Files. Every root is mandatory and must contribute at least one file.
# ---------------------------------------------------------------------------
$scanRoots = @(
    @{ Label = "SQL (supabase/**/*.sql)";       Path = "supabase";           Extensions = @(".sql") },
    @{ Label = "customer/admin app (lib)";      Path = "lib";                Extensions = @(".dart") },
    @{ Label = "owner app (owner_app/lib)";     Path = "owner_app/lib";      Extensions = @(".dart") },
    @{ Label = "static admin console (admin)";  Path = "admin";              Extensions = @(".js", ".mjs", ".html", ".json") },
    @{ Label = "edge functions";                Path = "supabase/functions"; Extensions = @(".ts", ".js", ".mjs", ".json") }
)

$filesByPath = @{}
foreach ($scanRoot in $scanRoots) {
    $rootPath = Join-Path $repoRoot $scanRoot.Path
    $rootFiles = @()
    if (Test-Path -LiteralPath $rootPath -PathType Container) {
        $rootFiles = @(Get-ChildItem -LiteralPath $rootPath -Recurse -File | Where-Object {
            $scanRoot.Extensions -contains $_.Extension.ToLowerInvariant() -and
            $_.FullName -notmatch '[\\/](node_modules|build|\.dart_tool|\.temp|\.branches)[\\/]'
        })
    }
    Write-Host "  $($scanRoot.Label): $($rootFiles.Count) files"
    # A scan that looked at nothing must never report PASS.
    if ($rootFiles.Count -eq 0) {
        $violations += "No files found to scan for $($scanRoot.Label) under $rootPath"
    }
    foreach ($file in $rootFiles) {
        $filesByPath[$file.FullName] = $file
    }
}
$allFiles = @($filesByPath.Values | Sort-Object FullName)

# ---------------------------------------------------------------------------
# 2. Literal rules (every file). PowerShell -match is case-insensitive.
#    "pin" is matched as a whole word, so pin_fingerprint, card_pin_fingerprint,
#    v_pin and p_pin are not hits; an assignment needs a QUOTED DIGIT literal.
# ---------------------------------------------------------------------------
$literalRules = @(
    @{ Name = "card number literal";       Pattern = '\bcard_number\b["'']?\s*[=:]\s*["''][0-9]{8,}["'']' },
    @{ Name = "voucher code literal";      Pattern = '\bvoucher_code\b["'']?\s*[=:]\s*["''][A-Za-z0-9]{8,}["'']' },
    @{ Name = "wifi password literal";     Pattern = '\bwifi_password\b["'']?\s*[=:]\s*["''][^"'']{4,}["'']' },
    @{ Name = "numeric card PIN literal";  Pattern = '\b(?:card_)?pin(?:_code)?\b["'']?\s*[=:]\s*["''][0-9]{6,}["'']' },
    @{ Name = "secret reference literal";  Pattern = '\bsecret_reference\b["'']?\s*[=:]\s*["''][A-Za-z0-9]{8,}["'']' },
    @{ Name = "pgcrypto call with a hard-coded key literal"; Pattern = '\bpgp_sym_(?:en|de)crypt\s*\((?:[^();]|\([^();]*\))*,\s*''[^'']*''\s*\)' },
    @{ Name = "card_master_key created with a committed value"; Pattern = '\bcreate_secret\s*\(\s*''[^'']*''\s*,\s*''card_master_key''' }
)
$testOnlyPattern = 'TEST[_-]ONLY'
$allowMarkerPattern = 'card-secret-scan:\s*allow-[a-z0-9-]+'

foreach ($file in $allFiles) {
    $content = Get-Content -LiteralPath $file.FullName -Raw
    if ([string]::IsNullOrWhiteSpace($content)) { continue }
    $relativePath = [System.IO.Path]::GetRelativePath($repoRoot, $file.FullName).Replace('\', '/')
    if ($file.Extension -eq ".sql") {
        # Commented-out examples (e.g. the documented key-provisioning step) are not code.
        $content = Remove-SqlLineComments -Sql $content
    }

    foreach ($rule in $literalRules) {
        foreach ($match in [regex]::Matches($content, $rule.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            if ($match.Value -cmatch $testOnlyPattern) { continue }
            $lineNumber = Get-SqlLineNumber -Text $content -Index $match.Index
            $lineText = ($content -split "`n")[$lineNumber - 1]
            if ($lineText -cmatch $allowMarkerPattern) { continue }
            # The matched value is deliberately not printed.
            $violations += "${relativePath}:${lineNumber}: $($rule.Name)"
        }
    }
}

# ---------------------------------------------------------------------------
# 3. Schema rules (all migrations).
# ---------------------------------------------------------------------------
$migrations = Get-SqlMigrations -Directory (Join-Path $repoRoot "supabase/migrations")
if ($migrations.Count -eq 0) {
    $violations += "No migration files found under supabase/migrations"
}

# (a) No table may declare a plaintext card-secret column.
$forbiddenColumnPattern = '(?i)(?<![A-Za-z_0-9.])"?(card_number|card_pin|card_code|card_secret|pin|pin_code|plaintext_pin|pin_plaintext|voucher_code|wifi_password|secret_payload|plaintext_secret)"?\s+(?:text|varchar|character\s+varying|char|citext|bytea|jsonb?)\b'
$tableDdlPattern = '(?i)\bCREATE\s+(?:UNLOGGED\s+)?TABLE\b[^;]*;|\bALTER\s+TABLE\b[^;]*\bADD\s+(?:COLUMN\s+)?[^;]*;'
$allSql = ""
foreach ($migration in $migrations) {
    $allSql += $migration.Sql + "`n"
    foreach ($ddlMatch in [regex]::Matches($migration.Sql, $tableDdlPattern)) {
        foreach ($columnMatch in [regex]::Matches($ddlMatch.Value, $forbiddenColumnPattern)) {
            $lineNumber = Get-SqlLineNumber -Text $migration.Sql -Index ($ddlMatch.Index + $columnMatch.Index)
            $violations += "$($migration.Name):${lineNumber}: table DDL declares a plaintext card-secret column '$($columnMatch.Groups[1].Value)'"
        }
    }
}

# (b) The vault stores ciphertext only.
if ($allSql -notmatch '(?i)\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.card_vault\s*\([^;]*\bciphertext\s+BYTEA\s+NOT\s+NULL\b') {
    $violations += "public.card_vault must be created with 'ciphertext BYTEA NOT NULL'"
}

# (c) The FINAL card ingest function encrypts the PIN and keeps only a keyed
#     fingerprint for duplicate detection; it never logs the PIN.
$finalFunctions = Get-FinalSqlFunctions -Migrations $migrations
$ingestName = "public.admin_ingest_card_vault_batch"
if (-not $finalFunctions.ContainsKey($ingestName)) {
    $violations += "$ingestName is not defined by any migration"
} else {
    $ingest = $finalFunctions[$ingestName]
    $ingestWhere = "$ingestName (final definition at $($ingest.Migration):$($ingest.Line))"
    if ($ingest.Body -notmatch '(?i)\bpgp_sym_encrypt\s*\(\s*v_pin\s*,\s*v_master_key\s*\)') {
        $violations += "$ingestWhere does not encrypt the PIN with pgp_sym_encrypt(v_pin, v_master_key)"
    }
    if ($ingest.Body -notmatch '(?i)\bcard_pin_fingerprint\s*\(') {
        $violations += "$ingestWhere does not compute card_pin_fingerprint() for duplicate detection"
    }
    if ($ingest.Body -match '(?i)\bRAISE\s+(?:DEBUG|LOG|INFO|NOTICE|WARNING)\b[^;]*\bv_pin\b') {
        $violations += "$ingestWhere writes the PIN to the server log (RAISE ... v_pin)"
    }
    if ($ingest.Body -match '(?i)\b(?:record_audit_event|jsonb_build_object)\s*\([^;]*\bv_pin\b') {
        $violations += "$ingestWhere puts the PIN into an audit/JSON payload"
    }
}

# (d) Fulfillment records must not carry the secret itself.
if ($allSql -match '(?i)\bCREATE\s+TABLE[^;]*\bfulfillment_records\b[^;]*\b(secret_payload|plaintext_secret|card_pin|voucher_code)\b') {
    $violations += "fulfillment_records contains a forbidden secret payload column"
}

# ---------------------------------------------------------------------------
# Result.
# ---------------------------------------------------------------------------
if ($allFiles.Count -eq 0) {
    Write-Host "RESULT: HOLD (zero files scanned)" -ForegroundColor Red
    exit 1
}
if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD (OD-CARD-01 violation)" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (no plaintext card/voucher secrets detected in $($allFiles.Count) files, $($migrations.Count) migrations)" -ForegroundColor Green
    exit 0
}
