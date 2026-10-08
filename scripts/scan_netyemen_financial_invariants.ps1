# NetYemen Financial Invariant Source Scan
# Verifies, by reading the SQL migrations, that the commerce core still enforces
# its money invariants: append-only ledger, non-negative balances, idempotency,
# server-side price authority, serialized purchases, four-eyes deposit review
# and refund-aware settlement.
#
# ALL migrations are read. Function assertions are made against the FINAL
# definition of each function: the last CREATE [OR REPLACE] FUNCTION for that
# name across the migration files in name order, which is what a database with
# every migration applied actually runs. (A check against "any migration"
# would still pass after a later migration replaced the function with a weaker
# body.)

$ErrorActionPreference = "Stop"

Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "NetYemen Financial Invariant Source Scan" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan

$violations = @()
$checksPassed = 0

$repoRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $PSScriptRoot 'lib/netyemen_sql.ps1')

$migrationsRoot = Join-Path $repoRoot "supabase/migrations"
# Comments are blanked by Get-SqlMigrations, so commented-out SQL can neither
# satisfy nor violate a rule.
$migrations = Get-SqlMigrations -Directory $migrationsRoot
if ($migrations.Count -eq 0) {
    Write-Host "RESULT: HOLD (no migration files found under $migrationsRoot)" -ForegroundColor Red
    exit 1
}
$allSql = ""
foreach ($migration in $migrations) {
    $allSql += $migration.Sql + "`n"
}
Write-Host "Scanning $($migrations.Count) migration files under $migrationsRoot"

# name (lower case, schema-qualified) -> @{ Header; Body; Options; Migration; Line }
# of the LAST definition in migration order.
$finalFunctions = Get-FinalSqlFunctions -Migrations $migrations
Write-Host "Resolved the final definition of $($finalFunctions.Count) functions"

# Records one named assertion. $Passed must be a boolean.
function Add-Check {
    param([bool]$Passed, [string]$Description)
    if ($Passed) {
        $script:checksPassed++
        Write-Host "  [OK] $Description" -ForegroundColor Green
    } else {
        $script:violations += $Description
    }
}

# Asserts regex patterns against the final header/body of one function.
# Header = CREATE .. up to the body (name, parameters, RETURNS); Options = header
# plus whatever follows the body (LANGUAGE, SECURITY DEFINER, SET ...).
# $Assertions: list of @{ Part = "Header"|"Body"|"Options"; Pattern = <regex>; Must = $true|$false; What = <text> }
function Assert-FinalFunction {
    param([string]$FunctionName, [array]$Assertions)
    if (-not $finalFunctions.ContainsKey($FunctionName)) {
        Add-Check -Passed $false -Description "$FunctionName is not defined by any migration."
        return
    }
    $definition = $finalFunctions[$FunctionName]
    foreach ($assertion in $Assertions) {
        $text = $definition[$assertion.Part]
        $found = [regex]::IsMatch($text, $assertion.Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        Add-Check -Passed ($found -eq $assertion.Must) -Description "$FunctionName (final definition in $($definition.Migration)): $($assertion.What)"
    }
}

# ---------------------------------------------------------------------------
# 1. Required tables.
# ---------------------------------------------------------------------------
$requiredTables = @(
    "wallet_accounts",
    "customer_wallet_ledger",
    "wallet_deposit_requests",
    "purchase_records",
    "card_fulfillment_records",
    "refund_requests",
    "owner_settlement_items",
    "settlement_batches",
    "settlement_batch_lines"
)
foreach ($table in $requiredTables) {
    $tablePattern = '(?i)\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?public\.' + $table + '\b'
    Add-Check -Passed ($allSql -match $tablePattern) -Description "required commerce table public.$table is created"
}

# ---------------------------------------------------------------------------
# 2. The ledger and the wallet balance are not writable by clients.
#    Statements are matched whole ([^;] crosses line breaks).
# ---------------------------------------------------------------------------
$protectedMoneyTables = @("customer_wallet_ledger", "wallet_accounts")
foreach ($table in $protectedMoneyTables) {
    # (a) Every RLS policy on the table must be explicitly FOR SELECT. A policy
    #     without a FOR clause means FOR ALL and would allow writes.
    $policyPattern = '(?i)\bCREATE\s+POLICY\s+[^;]*?\bON\s+public\.' + $table + '\b[^;]*;'
    $policies = [regex]::Matches($allSql, $policyPattern)
    $mutablePolicies = 0
    foreach ($policyMatch in $policies) {
        if ($policyMatch.Value -notmatch '(?i)\bFOR\s+SELECT\b') { $mutablePolicies++ }
    }
    Add-Check -Passed ($policies.Count -gt 0 -and $mutablePolicies -eq 0) -Description "$table has RLS policies and every one of them is FOR SELECT ($($policies.Count) found, $mutablePolicies mutable)"

    # (b) No INSERT/UPDATE/DELETE/TRUNCATE/ALL table privilege for client roles.
    $grantPattern = '(?i)(?<!REVOKE\s)\bGRANT\s+([^;]*?)\bON\s+(?:TABLE\s+)?[^;]*?public\.' + $table + '\b[^;]*?\bTO\s+([^;]+);'
    $clientWriteGrants = 0
    foreach ($grantMatch in [regex]::Matches($allSql, $grantPattern)) {
        $privileges = $grantMatch.Groups[1].Value
        $grantees = $grantMatch.Groups[2].Value
        if ($privileges -match '(?i)\b(INSERT|UPDATE|DELETE|TRUNCATE|ALL)\b' -and $grantees -match '(?i)\b(authenticated|anon|public)\b') {
            $clientWriteGrants++
        }
    }
    Add-Check -Passed ($clientWriteGrants -eq 0) -Description "$table grants no write privilege to a client role (authenticated/anon/public)"
}

# (c) No code path rewrites history.
Add-Check -Passed ($allSql -notmatch '(?i)\bUPDATE\s+(?:ONLY\s+)?public\.customer_wallet_ledger\b') -Description "no migration UPDATEs customer_wallet_ledger"
Add-Check -Passed ($allSql -notmatch '(?i)\bDELETE\s+FROM\s+(?:ONLY\s+)?public\.customer_wallet_ledger\b') -Description "no migration DELETEs from customer_wallet_ledger"

# (d) The ledger is append-only by trigger, and the trigger is still in place
#     (not dropped after its last CREATE, never disabled).
$appendOnlyCreatePattern = '(?i)\bCREATE\s+TRIGGER\s+trg_customer_wallet_ledger_append_only\s+BEFORE\s+(?:UPDATE\s+OR\s+DELETE|DELETE\s+OR\s+UPDATE)\s+ON\s+public\.customer_wallet_ledger\b[^;]*\bFOR\s+EACH\s+ROW\b[^;]*;'
$appendOnlyDropPattern = '(?i)\bDROP\s+TRIGGER\s+(?:IF\s+EXISTS\s+)?trg_customer_wallet_ledger_append_only\b'
$appendOnlyCreates = [regex]::Matches($allSql, $appendOnlyCreatePattern)
$appendOnlyDrops = [regex]::Matches($allSql, $appendOnlyDropPattern)
$appendOnlyInPlace = $false
if ($appendOnlyCreates.Count -gt 0) {
    $lastCreateIndex = $appendOnlyCreates[$appendOnlyCreates.Count - 1].Index
    $appendOnlyInPlace = $true
    foreach ($dropMatch in $appendOnlyDrops) {
        if ($dropMatch.Index -gt $lastCreateIndex) { $appendOnlyInPlace = $false }
    }
}
Add-Check -Passed $appendOnlyInPlace -Description "customer_wallet_ledger has the row-level append-only trigger trg_customer_wallet_ledger_append_only (BEFORE UPDATE OR DELETE) and it is not dropped afterwards"
Add-Check -Passed ($allSql -notmatch '(?i)\bALTER\s+TABLE\s+[^;]*customer_wallet_ledger\b[^;]*\bDISABLE\s+TRIGGER\b') -Description "no migration disables a trigger on customer_wallet_ledger"

# ---------------------------------------------------------------------------
# 3. Non-negative balances (constraints exist and are never dropped).
# ---------------------------------------------------------------------------
$balanceConstraints = @(
    @{ Name = "chk_wallet_accounts_balance_non_negative"; Column = "cached_balance" },
    @{ Name = "chk_customer_wallet_ledger_balance_non_negative"; Column = "balance_after" }
)
foreach ($constraint in $balanceConstraints) {
    $constraintPattern = '(?i)\bCONSTRAINT\s+' + $constraint.Name + '\s+CHECK\s*\(\s*' + $constraint.Column + '\s*>=\s*0\s*\)'
    Add-Check -Passed ($allSql -match $constraintPattern) -Description "$($constraint.Name) CHECK ($($constraint.Column) >= 0) exists"
    $dropConstraintPattern = '(?i)\bDROP\s+CONSTRAINT\s+(?:IF\s+EXISTS\s+)?' + $constraint.Name + '\b'
    Add-Check -Passed ($allSql -notmatch $dropConstraintPattern) -Description "$($constraint.Name) is never dropped"
}

# ---------------------------------------------------------------------------
# 4. Idempotency: unique indexes on (user_id, idempotency_key).
# ---------------------------------------------------------------------------
$idempotencyTables = @("customer_wallet_ledger", "wallet_deposit_requests", "purchase_records")
foreach ($table in $idempotencyTables) {
    $indexPattern = '(?i)\bCREATE\s+UNIQUE\s+INDEX\s+(?:IF\s+NOT\s+EXISTS\s+)?idx_' + $table + '_idempotency\s+ON\s+public\.' + $table + '\s*\(\s*user_id\s*,\s*idempotency_key\s*\)'
    Add-Check -Passed ($allSql -match $indexPattern) -Description "unique idempotency index on $table (user_id, idempotency_key)"
    $dropIndexPattern = '(?i)\bDROP\s+INDEX\s+(?:CONCURRENTLY\s+)?(?:IF\s+EXISTS\s+)?(?:public\.)?idx_' + $table + '_idempotency\b'
    Add-Check -Passed ($allSql -notmatch $dropIndexPattern) -Description "idempotency index on $table is never dropped"
}

# ---------------------------------------------------------------------------
# 5. purchase_package: server-side price, serialized wallet, one card per sale.
# ---------------------------------------------------------------------------
Add-Check -Passed ($allSql -notmatch '(?i)\bp_client_price\b') -Description "no function accepts a p_client_price parameter"
Assert-FinalFunction -FunctionName "public.purchase_package" -Assertions @(
    @{ Part = "Header"; Must = $true;  Pattern = '\bp_expected_price\s+integer\b'; What = "has the p_expected_price integer parameter" },
    @{ Part = "Header"; Must = $false; Pattern = '\bp_(?:client_)?(?:price|amount)\b'; What = "has no client-supplied price/amount parameter" },
    @{ Part = "Options"; Must = $true; Pattern = '\bSECURITY\s+DEFINER\b[\s\S]*\bSET\s+search_path\b'; What = "is SECURITY DEFINER with a pinned search_path" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bPRICE_CHANGED\b'; What = "rejects a price that differs from the confirmed one (PRICE_CHANGED)" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bFROM\s+public\.wallet_accounts\b[^;]*?\bFOR\s+UPDATE\b'; What = "locks the wallet row FOR UPDATE" },
    @{ Part = "Body";   Must = $true;  Pattern = '\baccount_status\s*(?:<>|!=)\s*''active''[\s\S]{0,200}?WALLET_FROZEN'; What = "checks the wallet account_status (WALLET_FROZEN)" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bcached_balance\s*<\s*v_package\.price\b[\s\S]{0,200}?INSUFFICIENT_BALANCE'; What = "compares the balance with the server-side package price (INSUFFICIENT_BALANCE)" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bFROM\s+public\.package_inventory_balances\b[^;]*?\bFOR\s+UPDATE\b'; What = "locks the inventory row FOR UPDATE" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bFROM\s+public\.card_vault\b[^;]*?\bFOR\s+UPDATE\s+SKIP\s+LOCKED\b'; What = "takes a card with FOR UPDATE SKIP LOCKED" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bpg_advisory_xact_lock\s*\('; What = "serializes calls that share an idempotency key (advisory lock)" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bIDEMPOTENCY_KEY_REUSED\b'; What = "refuses an idempotency key reused for another package" },
    @{ Part = "Body";   Must = $true;  Pattern = '\bINSERT\s+INTO\s+public\.customer_wallet_ledger\b[^;]*?''DEBIT''[^;]*?\bv_package\.price\b'; What = "debits exactly the server-side package price" }
)

# ---------------------------------------------------------------------------
# 6. Deposit review: no self-review, four-eyes above the threshold, one credit.
# ---------------------------------------------------------------------------
Assert-FinalFunction -FunctionName "public.review_wallet_deposit_request" -Assertions @(
    @{ Part = "Body"; Must = $true; Pattern = '\bFROM\s+public\.wallet_deposit_requests\b[^;]*?\bFOR\s+UPDATE\b'; What = "locks the deposit row FOR UPDATE" },
    @{ Part = "Body"; Must = $true; Pattern = '\bv_deposit\.user_id\s*=\s*v_user_id\b[\s\S]{0,200}?SELF_REVIEW_FORBIDDEN'; What = "has the self-review guard (SELF_REVIEW_FORBIDDEN)" },
    @{ Part = "Body"; Must = $true; Pattern = '>=\s*public\.deposit_dual_approval_threshold\s*\(\s*\)'; What = "calls the dual-approval threshold" },
    @{ Part = "Body"; Must = $true; Pattern = '\bfirst_approved_by\s+IS\s+NULL\b'; What = "records the first approver before a second one can credit" },
    @{ Part = "Body"; Must = $true; Pattern = '\bINTERVAL\s+''24 hours'''; What = "applies the threshold to the 24-hour aggregate" },
    @{ Part = "Body"; Must = $true; Pattern = '\bDUPLICATE_REFERENCE\b'; What = "refuses a transfer reference that was already credited" },
    @{ Part = "Body"; Must = $true; Pattern = '\bFROM\s+public\.wallet_accounts\b[^;]*?\bFOR\s+UPDATE\b'; What = "locks the wallet row FOR UPDATE before crediting" },
    @{ Part = "Body"; Must = $true; Pattern = '\bledger_entry_id\s+IS\s+NOT\s+NULL\b'; What = "never credits a deposit that already has a ledger entry" }
)
Add-Check -Passed ($finalFunctions.ContainsKey("public.deposit_dual_approval_threshold")) -Description "public.deposit_dual_approval_threshold() is defined"

# ---------------------------------------------------------------------------
# 7. Refunds are compensating CREDIT entries.
# ---------------------------------------------------------------------------
Assert-FinalFunction -FunctionName "public.review_refund_request" -Assertions @(
    @{ Part = "Body"; Must = $true; Pattern = '\bINSERT\s+INTO\s+public\.customer_wallet_ledger\b[^;]*?''CREDIT'''; What = "refunds by inserting a compensating CREDIT entry" }
)

# ---------------------------------------------------------------------------
# 8. Settlement batches: one run at a time, refunds claw back the owner net.
# ---------------------------------------------------------------------------
Assert-FinalFunction -FunctionName "public.finance_create_settlement_batch" -Assertions @(
    @{ Part = "Body"; Must = $true; Pattern = '\bpg_advisory_xact_lock\s*\('; What = "takes the advisory lock (one batch run at a time)" },
    @{ Part = "Body"; Must = $true; Pattern = '\bINSERT\s+INTO\s+public\.settlement_batch_lines\b[^;]*?''refund''[^;]*?,\s*-\s*[A-Za-z_]+\.owner_net_amount\b'; What = "writes refund lines with a NEGATIVE net amount" },
    @{ Part = "Body"; Must = $true; Pattern = '\bsb\.status\s*<>\s*''cancelled'''; What = "does not count refund lines of cancelled batches as settled" },
    @{ Part = "Body"; Must = $true; Pattern = '\bnet_settlement\s*=\s*v_gross\s*-\s*v_commission\s*-\s*v_refunds\b'; What = "computes net = gross - commission - refunds" }
)

# ---------------------------------------------------------------------------
# Result.
# ---------------------------------------------------------------------------
if ($violations.Count -gt 0) {
    Write-Host "RESULT: HOLD ($($violations.Count) failed, $checksPassed passed)" -ForegroundColor Red
    foreach ($v in $violations) { Write-Host "  [FAIL] $v" -ForegroundColor Red }
    exit 1
} elseif ($checksPassed -eq 0) {
    Write-Host "RESULT: HOLD (no invariant was evaluated)" -ForegroundColor Red
    exit 1
} else {
    Write-Host "RESULT: PASS ($checksPassed financial invariants hold across $($migrations.Count) migrations)" -ForegroundColor Green
    exit 0
}
