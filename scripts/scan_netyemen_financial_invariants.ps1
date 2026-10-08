# NetYemen Financial Invariant Source Scan
# Verifies that SQL migrations enforce ledger immutability, non-negative balance,
# idempotency, and server-side price authority for the V1 commerce core.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Financial Invariant Source Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()

$repoRoot = Split-Path -Parent $PSScriptRoot
$migrationsRoot = Join-Path $repoRoot "supabase/migrations"
# ALL migrations are scanned. The previous `*commerce*.sql` filter ignored every
# later migration, so a follow-up file could add a mutable ledger policy, a
# client write grant or a direct UPDATE on the ledger without being noticed.
$migrationFiles = @(Get-ChildItem -Path $migrationsRoot -File -Filter *.sql | Sort-Object Name)
if ($migrationFiles.Count -eq 0) {
    Write-Host "RESULT: HOLD (no migration files found under $migrationsRoot)" -ForegroundColor Red
    exit 1
}
$allSql = ""
foreach ($migrationFile in $migrationFiles) {
    $migrationSql = Get-Content -LiteralPath $migrationFile.FullName -Raw
    if (-not [string]::IsNullOrWhiteSpace($migrationSql)) {
        $allSql += $migrationSql + "`n"
    }
}
Write-Host "Scanning $($migrationFiles.Count) migration files under $migrationsRoot"

# Tables whose rows may only be written by controlled SECURITY DEFINER RPCs.
$protectedMoneyTables = @("customer_wallet_ledger", "wallet_accounts")

# Required tables
$requiredTables = @(
    "wallet_accounts",
    "customer_wallet_ledger",
    "wallet_deposit_requests",
    "purchase_records",
    "card_fulfillment_records",
    "refund_requests",
    "owner_settlement_items"
)
foreach ($table in $requiredTables) {
    if ($allSql -notmatch "CREATE\s+TABLE\s+IF\s+NOT\s+EXISTS\s+public\.$table\b") {
        $violations += "Missing required commerce table: $table"
    }
}

# Ledger immutability and no direct client balance mutation.
#
# The previous checks were single-line regexes ("table.*FOR UPDATE"): `.` does
# not cross a line break, so they could never see a normal multi-line
# CREATE POLICY, and they could false-positive on a `SELECT ... FOR UPDATE` row
# lock. The checks below parse whole statements ([^;] crosses line breaks).
foreach ($table in $protectedMoneyTables) {
    # (a) Every RLS policy on the table must be explicitly FOR SELECT. A policy
    #     without a FOR clause means FOR ALL and would allow writes.
    $policyPattern = "(?i)CREATE\s+POLICY\s+[^;]*?\bON\s+public\.$table\b[^;]*;"
    foreach ($policyMatch in [regex]::Matches($allSql, $policyPattern)) {
        if ($policyMatch.Value -notmatch "(?i)\bFOR\s+SELECT\b") {
            $violations += "$table has an RLS policy that is not FOR SELECT (mutable policy)."
        }
    }

    # (b) No INSERT/UPDATE/DELETE/TRUNCATE/ALL table privilege for client roles.
    $grantPattern = "(?i)(?<!REVOKE\s)GRANT\s+([^;]*?)\bON\s+(?:TABLE\s+)?[^;]*?public\.$table\b[^;]*?\bTO\s+([^;]+);"
    foreach ($grantMatch in [regex]::Matches($allSql, $grantPattern)) {
        $privileges = $grantMatch.Groups[1].Value
        $grantees = $grantMatch.Groups[2].Value
        if ($privileges -match "(?i)\b(INSERT|UPDATE|DELETE|TRUNCATE|ALL)\b" -and $grantees -match "(?i)\b(authenticated|anon|public)\b") {
            $violations += "$table grants a write privilege to a client role (authenticated/anon/public)."
        }
    }
}

# Non-negative wallet balance
if ($allSql -notmatch "chk_wallet_accounts_balance_non_negative") {
    $violations += "wallet_accounts.cached_balance non-negative CHECK missing."
}
if ($allSql -notmatch "chk_customer_wallet_ledger_balance_non_negative") {
    $violations += "Ledger balance_after non-negative CHECK missing."
}

# Idempotency: unique indexes on (user_id, idempotency_key)
$idempotencyTables = @("customer_wallet_ledger", "wallet_deposit_requests", "purchase_records")
foreach ($table in $idempotencyTables) {
    if ($allSql -notmatch "CREATE\s+UNIQUE\s+INDEX\s+idx_$table`_idempotency\s+ON\s+public\.$table\s*\(\s*user_id\s*,\s*idempotency_key\s*\)") {
        $violations += "Idempotency UNIQUE index missing on $table"
    }
}

# Server-side price authority (purchase_package must not accept trusted client price)
if ($allSql -notmatch "CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.purchase_package") {
    $violations += "purchase_package RPC not found."
}
if ($allSql -match "p_client_price") {
    $violations += "purchase_package accepts a client price parameter (server-side price authority violated)."
}

# Refund creates compensating CREDIT, never mutates historical ledger
if ($allSql -notmatch "CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.review_refund_request") {
    $violations += "review_refund_request RPC not found."
}
if ($allSql -notmatch "'CREDIT'\s*,") {
    $violations += "Refund compensating CREDIT entry not found."
}
if ($allSql -match "UPDATE\s+(?:ONLY\s+)?public\.customer_wallet_ledger") {
    $violations += "Direct UPDATE on customer_wallet_ledger detected (refund should INSERT only)."
}
if ($allSql -match "DELETE\s+FROM\s+(?:ONLY\s+)?public\.customer_wallet_ledger") {
    $violations += "Direct DELETE on customer_wallet_ledger detected."
}

if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (financial invariants present in $($migrationFiles.Count) migrations)" -ForegroundColor Green
    exit 0
}
