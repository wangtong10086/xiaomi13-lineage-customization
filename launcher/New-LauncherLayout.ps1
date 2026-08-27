[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$InventoryTsv,
    [Parameter(Mandatory)][string]$CategoriesTsv,
    [Parameter(Mandatory)][string]$OutputTsv,
    [ValidateRange(1, 12)][int]$Columns = 4,
    [ValidateRange(1, 12)][int]$Rows = 6,
    [ValidateRange(0, 5)][int]$FirstPageStartRow = 0
)

$ErrorActionPreference = 'Stop'
$inventory = @(Import-Csv -LiteralPath $InventoryTsv -Delimiter "`t")
$categories = @(Import-Csv -LiteralPath $CategoriesTsv -Delimiter "`t")
if (-not $inventory.Count) { throw 'Inventory is empty.' }
if (-not $categories.Count) { throw 'Category mapping is empty.' }

$requiredInventory = @('id','title','package','usage_seconds','launches')
$requiredCategories = @('package','group','page')
foreach ($name in $requiredInventory) {
    if ($inventory[0].PSObject.Properties.Name -notcontains $name) { throw "Inventory lacks '$name'." }
}
foreach ($name in $requiredCategories) {
    if ($categories[0].PSObject.Properties.Name -notcontains $name) { throw "Categories lack '$name'." }
}

$map = @{}
$groupOrder = @{}
$groupIndex = 0
foreach ($row in $categories) {
    if ($row.package -notmatch '^[A-Za-z0-9._]+$') { throw "Invalid package: $($row.package)" }
    if ($map.ContainsKey($row.package)) { throw "Package mapped twice: $($row.package)" }
    $page = 0
    if (-not [int]::TryParse($row.page, [ref]$page) -or $page -lt 1) { throw "Invalid page for $($row.package)" }
    if (-not $groupOrder.ContainsKey($row.group)) { $groupOrder[$row.group] = $groupIndex++ }
    $map[$row.package] = [pscustomobject]@{ Group = $row.group; Page = $page; Order = $groupOrder[$row.group] }
}

$ranked = foreach ($item in $inventory) {
    if (-not $map.ContainsKey($item.package)) { throw "Unassigned package: $($item.package)" }
    $id = 0; $usage = 0L; $launches = 0L
    if (-not [int]::TryParse($item.id, [ref]$id) -or $id -lt 0) { throw "Invalid id for $($item.package)" }
    if (-not [long]::TryParse($item.usage_seconds, [ref]$usage) -or $usage -lt 0) { throw "Invalid usage for $($item.package)" }
    if (-not [long]::TryParse($item.launches, [ref]$launches) -or $launches -lt 0) { throw "Invalid launches for $($item.package)" }
    $category = $map[$item.package]
    [pscustomobject]@{
        id = $id; title = $item.title; package = $item.package
        usage_seconds = $usage; launches = $launches
        group = $category.Group; page = $category.Page; group_order = $category.Order
    }
}

$ranked = @($ranked | Sort-Object page, group_order, @{Expression='usage_seconds';Descending=$true}, @{Expression='launches';Descending=$true}, package)
$pageCounts = @{}
$layout = foreach ($item in $ranked) {
    if (-not $pageCounts.ContainsKey($item.page)) { $pageCounts[$item.page] = 0 }
    $index = $pageCounts[$item.page]++
    $start = if ($item.page -eq 1) { $FirstPageStartRow * $Columns } else { 0 }
    $position = $start + $index
    if ($position -ge ($Columns * $Rows)) { throw "Page $($item.page) exceeds ${Columns}x${Rows} capacity." }
    [pscustomobject]@{
        id = $item.id; package = $item.package; title = ([string]$item.title -replace "[`t`r`n]", ' ')
        screen = $item.page; x = $position % $Columns; y = [math]::Floor($position / $Columns)
        group = $item.group; usage_seconds = $item.usage_seconds; launches = $item.launches
    }
}

$fullOutput = [IO.Path]::GetFullPath($OutputTsv)
$parent = [IO.Path]::GetDirectoryName($fullOutput)
if ($parent) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
$layout | Export-Csv -LiteralPath $fullOutput -Delimiter "`t" -NoTypeInformation -UseQuotes Never -Encoding utf8NoBOM
[pscustomobject]@{ Output = $fullOutput; Icons = $layout.Count; Pages = $pageCounts.Count; Validated = $true }
