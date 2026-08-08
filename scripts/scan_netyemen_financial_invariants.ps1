# NetYemen Financial Invariant Source Scan
# Verifies that SQL migrations enforce ledger immutability, non-negative balance,
# idempotency, and server-side price authority for the V1 commerce core.

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Financial Invariant Source Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()

$searchRoot = "C:/projects/NetYemen-kimi-commerce"
$commerceMigrations = Get-ChildItem -Path "$searchRoot/supabase/migrations" -Filter *commerce*.sql -ErrorAction SilentlyContinue
$allSql = ($commerceMigrations | ForEach-Object { Get-Content $_.FullName -Raw }) -join "`n"

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

# Ledger immutability: no UPDATE/DELETE policies on customer_wallet_ledger
if ($allSql -match "customer_wallet_ledger.*FOR\s+(UPDATE|DELETE)") {
    $violations += "customer_wallet_ledger has a mutable UPDATE/DELETE policy."
}
if ($allSql -notmatch "--\s*No\s+direct\s+INSERT/UPDATE/DELETE\.\s*Entries\s+created\s+exclusively\s+by\s+controlled\s+RPCs") {
    # Comment-based sentinel is optional; the policy check above is the real guard.
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

# No direct client balance mutation
if ($allSql -match "wallet_accounts.*FOR\s+UPDATE") {
    $violations += "wallet_accounts has a direct UPDATE policy."
}

# Refund creates compensating CREDIT, never mutates historical ledger
if ($allSql -notmatch "CREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+public\.review_refund_request") {
    $violations += "review_refund_request RPC not found."
}
if ($allSql -notmatch "'CREDIT'\s*,") {
    $violations += "Refund compensating CREDIT entry not found."
}
if ($allSql -match "UPDATE\s+public\.customer_wallet_ledger") {
    $violations += "Direct UPDATE on customer_wallet_ledger detected (refund should INSERT only)."
}
if ($allSql -match "DELETE\s+FROM\s+public\.customer_wallet_ledger") {
    $violations += "Direct DELETE on customer_wallet_ledger detected."
}

if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "RESULT: PASS (financial invariants present in source)" -ForegroundColor Green
    exit 0
}
