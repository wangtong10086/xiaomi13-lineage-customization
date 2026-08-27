[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidatePattern('^[A-Za-z0-9._:-]+$')][string]$Serial,
    [Parameter(Mandatory)][string]$SettingsTsv,
    [string]$RollbackTsv = (Join-Path (Get-Location) ('settings-rollback-{0}.local.tsv' -f (Get-Date -Format 'yyyyMMdd-HHmmss')))
)

$ErrorActionPreference = 'Stop'
$rows = @(Import-Csv -LiteralPath $SettingsTsv -Delimiter "`t")
if (-not $rows.Count) { throw 'Settings TSV is empty.' }
foreach ($column in @('namespace','key','value')) {
    if ($rows[0].PSObject.Properties.Name -notcontains $column) { throw "Settings TSV lacks '$column'." }
}

$deviceRow = & adb devices | Where-Object { $_ -eq "$Serial`tdevice" }
if (-not $deviceRow) { throw "Expected authorized adb device '$Serial' was not found." }

$rollback = foreach ($row in $rows) {
    if ($row.namespace -notin @('system','secure','global')) { throw "Invalid namespace: $($row.namespace)" }
    if ($row.key -notmatch '^[A-Za-z0-9._:-]+$') { throw "Invalid settings key: $($row.key)" }
    if ([string]$row.value -match "[`t`r`n]") { throw "Multiline/tabbed values are not supported: $($row.namespace)/$($row.key)" }
    $current = (& adb -s $Serial shell settings get $row.namespace $row.key 2>&1) -join "`n"
    if ($LASTEXITCODE -ne 0) { throw "Unable to read $($row.namespace)/$($row.key): $current" }
    if ($current.Trim() -match "[`t`r`n]") { throw "Current value cannot be represented safely in rollback TSV: $($row.namespace)/$($row.key)" }
    [pscustomobject]@{
        namespace = $row.namespace
        key = $row.key
        value = if ($current.Trim() -eq 'null') { '__DELETE__' } else { $current.Trim() }
    }
}

$rollbackPath = [IO.Path]::GetFullPath($RollbackTsv)
$parent = [IO.Path]::GetDirectoryName($rollbackPath)
if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$rollback | Export-Csv -LiteralPath $rollbackPath -Delimiter "`t" -NoTypeInformation -UseQuotes Never -Encoding utf8NoBOM

foreach ($row in $rows) {
    if ($row.value -eq '__DELETE__') {
        $result = & adb -s $Serial shell settings delete $row.namespace $row.key 2>&1
    } else {
        $result = & adb -s $Serial shell settings put $row.namespace $row.key $row.value 2>&1
    }
    if ($LASTEXITCODE -ne 0) { throw "Unable to apply $($row.namespace)/$($row.key): $($result -join ' ')" }
}

[pscustomobject]@{ Serial = $Serial; Applied = $rows.Count; Rollback = $rollbackPath }
