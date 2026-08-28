[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Serial,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Package,

    [string]$AdbPath = 'adb',

    [ValidateRange(10, 180)]
    [int]$WaitSeconds = 70,

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$allowedPackages = @(
    'com.anjuke.android.app',
    'com.lietou.mishu',
    'com.ss.android.ugc.aweme',
    'com.MobileTicket',
    'cn.gov.tax.its',
    'com.chinamworld.main',
    'com.eg.android.AlipayGphone'
)
$modulePackage = 'io.github.magisk317.mipush'
$xmsfDatabase = '/data/user/0/com.xiaomi.xmsf/databases/db'
$mipushLog = '/data/user/0/com.xiaomi.xmsf/files/log/runtime.MiPush.' + (Get-Date -Format 'yyyy-MM-dd') + '.jsonl'

if ($allowedPackages -notcontains $Package) {
    throw "Package '$Package' is not in the reviewed allowlist. Internal helpers such as com.miui.nextpay and com.xiaomi.payment are deliberately excluded."
}

$adbCommand = Get-Command -Name $AdbPath -ErrorAction SilentlyContinue
if (-not $adbCommand) {
    if (Test-Path -LiteralPath $AdbPath -PathType Leaf) {
        $script:Adb = (Resolve-Path -LiteralPath $AdbPath).Path
    } else {
        throw "adb was not found at '$AdbPath'."
    }
} else {
    $script:Adb = $adbCommand.Source
}

function Invoke-Adb {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    $output = & $script:Adb @Arguments 2>&1
    $exitCode = $LASTEXITCODE
    $lines = @($output | ForEach-Object { $_.ToString() })
    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "adb failed with exit code ${exitCode}: $($lines -join ' ')"
    }
    return $lines
}

function Invoke-Root {
    param(
        [Parameter(Mandatory)]
        [string]$Command,
        [switch]$AllowFailure
    )

    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'su', '-c', $Command) -AllowFailure:$AllowFailure
}

function Get-Scope {
    return Invoke-Root -Command "/data/adb/lspd/cli scope ls $modulePackage"
}

function Test-TargetScope {
    param([string[]]$ScopeLines)
    return [bool]($ScopeLines | Where-Object { $_ -match ('^\s*' + [regex]::Escape($Package) + '\s+0\s*$') })
}

function Get-Denylist {
    return Invoke-Root -Command 'magisk --denylist ls'
}

function Test-MainDenyEntry {
    param([string[]]$DenyLines)
    return $DenyLines -contains "$Package|$Package"
}

function Get-RegistrationRows {
    return Invoke-Root -Command "sqlite3 $xmsfDatabase select/**/pkg,type,registered_type,blocked,island_enabled/**/from/**/REGISTERED_APPLICATION/**/order/**/by/**/pkg"
}

function Get-EventRows {
    return Invoke-Root -Command "sqlite3 $xmsfDatabase select/**/id,pkg,type,date,result/**/from/**/EVENT/**/order/**/by/**/id"
}

function Get-TargetEvents {
    param([string[]]$Rows)

    $parsed = foreach ($row in $Rows) {
        $columns = $row -split '\|'
        if ($columns.Count -ge 5 -and $columns[1] -eq $Package) {
            [pscustomobject]@{
                Id     = [int64]$columns[0]
                Type   = [int]$columns[2]
                Date   = [int64]$columns[3]
                Result = [int]$columns[4]
            }
        }
    }
    return @($parsed)
}

function Test-RegisteredTypeOne {
    param([string[]]$Rows)

    $row = $Rows | Where-Object { $_ -match ('^' + [regex]::Escape($Package) + '\|') } | Select-Object -Last 1
    if (-not $row) {
        return $false
    }
    $columns = $row -split '\|'
    return $columns.Count -ge 3 -and $columns[2] -eq '1'
}

function Test-PrivateRegId {
    $preferencePath = "/data/user/0/$Package/shared_prefs/mipush.xml"
    $xml = (Invoke-Root -Command "cat $preferencePath" -AllowFailure) -join "`n"
    if ([string]::IsNullOrWhiteSpace($xml)) {
        return $false
    }
    $match = [regex]::Match($xml, '<string name="regId">(.*?)</string>', 'Singleline')
    return $match.Success -and $match.Groups[1].Value.Length -gt 0
}

$state = (Invoke-Adb -Arguments @('-s', $Serial, 'get-state') | Select-Object -Last 1).Trim()
if ($state -ne 'device') {
    throw "Device '$Serial' is not in adb device state (reported '$state')."
}

$rootIdentity = (Invoke-Root -Command 'id') -join ' '
if ($rootIdentity -notmatch 'uid=0\(root\)') {
    throw "Root was not granted on device '$Serial'."
}

$packagePath = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'pm', 'path', $Package) -AllowFailure
if (-not ($packagePath | Where-Object { $_ -match '^package:' })) {
    throw "Package '$Package' is not installed for the active Android user."
}

$launcherLines = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'cmd', 'package', 'resolve-activity', '--brief', '-c', 'android.intent.category.LAUNCHER', $Package)
$launcher = $launcherLines | Where-Object { $_ -match ('^' + [regex]::Escape($Package) + '/') } | Select-Object -Last 1
if (-not $launcher) {
    throw "No launcher activity was resolved for '$Package'."
}
$launcher = $launcher.Trim()

$scopeBefore = Get-Scope
$denyBefore = Get-Denylist
$eventsBefore = Get-TargetEvents -Rows (Get-EventRows)
$baselineEventId = if ($eventsBefore.Count) { ($eventsBefore | Measure-Object -Property Id -Maximum).Maximum } else { [int64]0 }
$scopeWasPresent = Test-TargetScope -ScopeLines $scopeBefore
$mainWasDenied = Test-MainDenyEntry -DenyLines $denyBefore
$registeredBefore = Test-RegisteredTypeOne -Rows (Get-RegistrationRows)

$plan = [pscustomobject]@{
    Serial                  = $Serial
    Package                 = $Package
    Mode                    = if ($Apply) { 'apply' } else { 'read-only' }
    Launcher                = $launcher
    VectorScopePresent      = $scopeWasPresent
    MainDenyEntryPresent    = $mainWasDenied
    RegisteredType1Before   = $registeredBefore
    LatestTargetEventBefore = $baselineEventId
    WaitSeconds             = $WaitSeconds
}

if (-not $Apply) {
    $plan
    return
}

$scopeAdded = $false
$denyRemoved = $false
$regIdObserved = $false
$event21Result0 = $false
$registeredType1 = $false
$restoreErrors = [System.Collections.Generic.List[string]]::new()
$moduleLogLineCountBefore = (Invoke-Root -Command "grep -F $Package $mipushLog" -AllowFailure).Count

try {
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $Package) | Out-Null

    if (-not $scopeWasPresent) {
        Invoke-Root -Command "/data/adb/lspd/cli scope add $modulePackage $Package/0" | Out-Null
        $scopeAdded = $true
    }

    if ($mainWasDenied) {
        Invoke-Root -Command "magisk --denylist rm $Package $Package" | Out-Null
        $denyRemoved = $true
    }

    if (-not (Test-TargetScope -ScopeLines (Get-Scope))) {
        throw 'The temporary Vector scope was not applied.'
    }
    if ($mainWasDenied -and (Test-MainDenyEntry -DenyLines (Get-Denylist))) {
        throw 'The exact main-process denylist entry was not removed.'
    }

    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'start', '-W', '-n', $launcher) | Out-Null
    Start-Sleep -Seconds $WaitSeconds

    $eventsAfter = Get-TargetEvents -Rows (Get-EventRows)
    $event21Result0 = [bool]($eventsAfter | Where-Object {
        $_.Id -gt $baselineEventId -and $_.Type -eq 21 -and $_.Result -eq 0
    })
    $registeredType1 = Test-RegisteredTypeOne -Rows (Get-RegistrationRows)

    $moduleLog = Invoke-Root -Command "grep -F $Package $mipushLog" -AllowFailure
    $newModuleLog = @($moduleLog | Select-Object -Skip $moduleLogLineCountBefore)
    $regIdInModuleLog = [bool]($newModuleLog | Where-Object { $_ -match 'regId available' })
    $regIdObserved = $regIdInModuleLog -or (Test-PrivateRegId)
}
finally {
    try { Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $Package) | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    if ($scopeAdded) {
        try { Invoke-Root -Command "/data/adb/lspd/cli scope rm $modulePackage $Package/0" | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    }
    if ($denyRemoved) {
        try { Invoke-Root -Command "magisk --denylist add $Package $Package" | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    }
    try { Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'start', '-W', '-n', $launcher) | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    Start-Sleep -Seconds 8
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'input', 'keyevent', '3') -AllowFailure | Out-Null
}

$scopeRestored = (Test-TargetScope -ScopeLines (Get-Scope)) -eq $scopeWasPresent
$denyRestored = (Test-MainDenyEntry -DenyLines (Get-Denylist)) -eq $mainWasDenied
$registeredAfterRestore = Test-RegisteredTypeOne -Rows (Get-RegistrationRows)
$regIdAfterRestore = Test-PrivateRegId
$restored = $scopeRestored -and $denyRestored -and $restoreErrors.Count -eq 0
$passed = $regIdObserved -and $event21Result0 -and $registeredType1 -and $registeredAfterRestore -and $restored

[pscustomobject]@{
    Serial                       = $Serial
    Package                      = $Package
    RegistrationPassed          = $passed
    RegIdObservedNonEmpty        = $regIdObserved
    Event21Result0               = $event21Result0
    RegisteredType1             = $registeredType1
    RegisteredAfterHideRestore  = $registeredAfterRestore
    PrivateRegIdAfterRestore    = $regIdAfterRestore
    VectorScopeRestored          = $scopeRestored
    MainDenyEntryRestored        = $denyRestored
    RestoreErrorCount            = $restoreErrors.Count
}
