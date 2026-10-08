# Shared SQL source helpers for the NetYemen static verifiers.
# Dot-source this file:   . (Join-Path $PSScriptRoot 'lib/netyemen_sql.ps1')
#
# These helpers read migration TEXT; they do not connect to a database.

# Whole-line SQL comments ("   -- ...") are blanked, keeping the line breaks so
# that line numbers stay valid. A commented-out statement can then neither
# satisfy nor violate a rule. Trailing comments after code are left alone
# because "--" can legitimately occur inside string literals.
function Remove-SqlLineComments {
    param([string]$Sql)
    $lineCommentPattern = '(?m)^[ \t]*--[^\n]*$'
    return [regex]::Replace($Sql, $lineCommentPattern, '')
}

# 1-based line number of a character index.
function Get-SqlLineNumber {
    param([string]$Text, [int]$Index)
    return ([regex]::Matches($Text.Substring(0, $Index), "`n")).Count + 1
}

# Reads every *.sql file of a directory in name order and returns a list of
# @{ Name; Sql } (comments blanked). Empty files are returned with Sql = "".
function Get-SqlMigrations {
    param([string]$Directory)
    $migrations = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $Directory -File -Filter *.sql | Sort-Object Name)) {
        $rawSql = Get-Content -LiteralPath $file.FullName -Raw
        if ([string]::IsNullOrWhiteSpace($rawSql)) {
            $migrations += @{ Name = $file.Name; Sql = "" }
        } else {
            $migrations += @{ Name = $file.Name; Sql = (Remove-SqlLineComments -Sql $rawSql) }
        }
    }
    # The leading comma keeps the array intact when it has 0 or 1 element.
    return ,$migrations
}

# Splits SQL text into its CREATE FUNCTION statements. Both layouts are
# understood:
#   options BEFORE the body (pg_get_functiondef layout)
#       CREATE OR REPLACE FUNCTION f(...) RETURNS x
#        LANGUAGE plpgsql
#        SECURITY DEFINER
#        SET search_path TO 'public', 'pg_temp'
#       AS $function$ ... $function$;
#   options AFTER the body
#       CREATE FUNCTION f(...) RETURNS x AS $$ ... $$
#       LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp;
#
# Each statement is returned as a hashtable:
#   Name     function name as written (may be schema-qualified / quoted)
#   Index    character index of CREATE in $Sql
#   Parsed   $false when the dollar-quoted body is not terminated
#   Header   CREATE .. up to the body: name, parameters, RETURNS, leading options
#   Body     text between the dollar-quote tags ("" when there is none)
#   Options  Header + the text between the closing tag and ';'. This is where
#            LANGUAGE / SECURITY DEFINER / SET search_path live, whichever side
#            of the body they are written on. Words inside the body are never
#            part of Options.
function Get-SqlFunctionStatements {
    param([string]$Sql)
    $statements = @()
    $startPattern = '(?i)\bCREATE\s+(?:OR\s+REPLACE\s+)?FUNCTION\s+([A-Za-z_0-9."]+)\s*\('
    $bodyOpenPattern = '(?i)\bAS\s+(\$[A-Za-z_0-9]*\$)'
    $ordinal = [System.StringComparison]::Ordinal
    foreach ($startMatch in [regex]::Matches($Sql, $startPattern)) {
        $rest = $Sql.Substring($startMatch.Index)
        $bodyOpen = [regex]::Match($rest, $bodyOpenPattern)
        $firstSemicolon = $rest.IndexOf(';', $ordinal)
        $statement = @{
            Name    = $startMatch.Groups[1].Value
            Index   = $startMatch.Index
            Parsed  = $true
            Header  = ""
            Body    = ""
            Options = ""
        }
        if ($bodyOpen.Success -and ($firstSemicolon -lt 0 -or $bodyOpen.Index -lt $firstSemicolon)) {
            $tag = $bodyOpen.Groups[1].Value
            $bodyStart = $bodyOpen.Index + $bodyOpen.Length
            $bodyEnd = $rest.IndexOf($tag, $bodyStart, $ordinal)
            $statement.Header = $rest.Substring(0, $bodyOpen.Index)
            if ($bodyEnd -lt 0) {
                $statement.Parsed = $false
                $statement.Options = $statement.Header
            } else {
                $afterBody = $bodyEnd + $tag.Length
                $statementEnd = $rest.IndexOf(';', $afterBody, $ordinal)
                if ($statementEnd -lt 0) { $statementEnd = $rest.Length }
                $statement.Body = $rest.Substring($bodyStart, $bodyEnd - $bodyStart)
                $statement.Options = $statement.Header + " " + $rest.Substring($afterBody, $statementEnd - $afterBody)
            }
        } else {
            # No dollar-quoted body before the first ';' (SQL-standard body or a
            # single-quoted body): the whole statement counts as header/options.
            $statementEnd = $firstSemicolon
            if ($statementEnd -lt 0) { $statementEnd = $rest.Length }
            $statement.Header = $rest.Substring(0, $statementEnd)
            $statement.Options = $statement.Header
        }
        $statements += $statement
    }
    return ,$statements
}

# The FINAL definition of every function: the last CREATE [OR REPLACE] FUNCTION
# for a name across the given migrations (which must be in apply order). That
# is what a database with every migration applied actually runs.
# Returns: lower-case schema-qualified name -> @{ Header; Body; Options; Migration; Line }.
# Overloads share one entry (the last one written wins).
function Get-FinalSqlFunctions {
    param([array]$Migrations)
    $finalFunctions = @{}
    foreach ($migration in $Migrations) {
        if ([string]::IsNullOrEmpty($migration.Sql)) { continue }
        $functionStatements = Get-SqlFunctionStatements -Sql $migration.Sql
        foreach ($functionStatement in $functionStatements) {
            $functionName = $functionStatement.Name.Replace('"', '').ToLowerInvariant()
            if (-not $functionName.Contains('.')) { $functionName = "public.$functionName" }
            $finalFunctions[$functionName] = @{
                Header    = $functionStatement.Header
                Body      = $functionStatement.Body
                Options   = $functionStatement.Options
                Migration = $migration.Name
                Line      = (Get-SqlLineNumber -Text $migration.Sql -Index $functionStatement.Index)
            }
        }
    }
    return $finalFunctions
}
