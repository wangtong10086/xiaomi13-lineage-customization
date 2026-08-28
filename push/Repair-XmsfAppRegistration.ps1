[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Serial,
    [Parameter(Mandatory)][ValidateSet(
        'com.eg.android.AlipayGphone',
        'com.anjuke.android.app',
        'com.ss.android.ugc.aweme',
        'com.MobileTicket',
        'com.lietou.mishu',
        'cn.gov.tax.its',
        'com.chinamworld.main')][string]$Package,
    [ValidateSet('Audit', 'Register', 'Reregister', 'Verify')][string]$Action = 'Audit',
    [string]$AdbPath = 'adb',
    [string]$BackupRoot = 'E:\Xiaomi13Migration',
    [ValidateRange(30, 180)][int]$WaitSeconds = 100,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profile = @{
    'com.eg.android.AlipayGphone' = [pscustomobject]@{
        VersionCode = 212210L
        Launcher = 'com.eg.android.AlipayGphone/.AlipayLogin'
        Processes = @('com.eg.android.AlipayGphone', 'com.eg.android.AlipayGphone:push')
        Components = @(
            'com.alipay.pushsdk.thirdparty.xiaomi.XiaoMiMsgReceiver',
            'com.xiaomi.mipush.sdk.PushMessageHandler',
            'com.xiaomi.mipush.sdk.MessageHandleService'
        )
        Implemented = $true
        VectorCredential = $false
        RequireAlipayBinding = $true
        RequireNativeInvocation = $true
    }
    'com.anjuke.android.app' = [pscustomobject]@{
        Implemented = $true
        VersionCode = 322403L
        Launcher = 'com.anjuke.android.app/.mainmodule.WelcomeActivity'
        Processes = @('com.anjuke.android.app')
        Components = @()
        VectorCredential = $false
        RequireAlipayBinding = $false
        RequireNativeInvocation = $true
    }
    'com.ss.android.ugc.aweme' = [pscustomobject]@{
        Implemented = $true
        VersionCode = 400201L
        Launcher = 'com.ss.android.ugc.aweme/.splash.SplashActivity'
        Processes = @('com.ss.android.ugc.aweme')
        Components = @()
        VectorCredential = $true
        RequireAlipayBinding = $false
        RequireNativeInvocation = $false
    }
    'com.MobileTicket' = [pscustomobject]@{
        Implemented = $true
        VersionCode = 280L
        Launcher = 'com.MobileTicket/.ui.activity.WelcomeGuideActivity'
        Processes = @('com.MobileTicket')
        Components = @()
        VectorCredential = $false
        RequireAlipayBinding = $false
        RequireNativeInvocation = $false
    }
    'com.lietou.mishu' = [pscustomobject]@{
        Implemented = $true
        VersionCode = 13081L
        Launcher = 'com.lietou.mishu/.HomeActivity'
        Processes = @('com.lietou.mishu')
        Components = @()
        VectorCredential = $false
        RequireAlipayBinding = $false
        RequireNativeInvocation = $false
    }
    'cn.gov.tax.its' = [pscustomobject]@{
        Implemented = $true
        VersionCode = 20303L
        Launcher = 'cn.gov.tax.its/.MainActivity'
        Processes = @('cn.gov.tax.its')
        Components = @()
        VectorCredential = $false
        RequireAlipayBinding = $false
        RequireNativeInvocation = $false
    }
    'com.chinamworld.main' = [pscustomobject]@{
        Implemented = $true
        VersionCode = 2351L
        Launcher = 'com.chinamworld.main/com.ccb.start.MainActivity'
        Processes = @('com.chinamworld.main')
        Components = @()
        VectorCredential = $false
        RequireAlipayBinding = $false
        RequireNativeInvocation = $false
    }
}[$Package]

$modulePackage = 'com.codex.xmsfappregistrationcompat'
$vectorPackage = 'io.github.magisk317.mipush'
$xmsfDatabase = '/data/user/0/com.xiaomi.xmsf/databases/db'
$controlDirectory = '/data/local/tmp/xmsf-app-registration-compat'
$privatePreference = "/data/user/0/$Package/shared_prefs/mipush.xml"

$adbCommand = Get-Command -Name $AdbPath -ErrorAction SilentlyContinue
if ($adbCommand) {
    $script:Adb = $adbCommand.Source
} elseif (Test-Path -LiteralPath $AdbPath -PathType Leaf) {
    $script:Adb = (Resolve-Path -LiteralPath $AdbPath).Path
} else {
    throw "adb was not found at '$AdbPath'."
}

function Invoke-Adb {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $output = & $script:Adb @Arguments 2>&1
    $code = $LASTEXITCODE
    $lines = @($output | ForEach-Object { $_.ToString() })
    if ($code -ne 0 -and -not $AllowFailure) {
        throw "adb failed with exit code ${code}: $($lines -join ' ')"
    }
    return $lines
}

function Invoke-Root {
    param([Parameter(Mandatory)][string]$Command, [switch]$AllowFailure)
    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'su', '-c', $Command) -AllowFailure:$AllowFailure
}

function Get-InstalledVersionCode {
    $line = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'dumpsys', 'package', $Package) |
        Where-Object { $_ -match 'versionCode=(\d+)' } | Select-Object -First 1
    if (-not $line -or $line -notmatch 'versionCode=(\d+)') { return [int64]-1 }
    return [int64]$Matches[1]
}

function Get-ModuleScope {
    return Invoke-Root -Command "/data/adb/lspd/cli scope ls $modulePackage" -AllowFailure
}

function Test-ModuleScope {
    param([string[]]$Lines)
    return [bool]($Lines | Where-Object {
        $_ -match ('^\s*' + [regex]::Escape($Package) + '\s+0\s*$')
    })
}

function Get-Denylist {
    return Invoke-Root -Command 'magisk --denylist ls'
}

function Test-DenyEntry {
    param([string[]]$Lines, [string]$Process)
    return $Lines -contains "$Package|$Process"
}

function Get-ComponentDisabled {
    param([string]$Component)
    $dump = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'dumpsys', 'package', $Package)
    $inDisabled = $false
    foreach ($line in $dump) {
        if ($line -match '^\s*disabledComponents:') { $inDisabled = $true; continue }
        if ($inDisabled -and $line -match '^\s*enabledComponents:') { break }
        if ($inDisabled -and $line.Trim() -eq $Component) { return $true }
    }
    return $false
}

function Get-RegistrationRow {
    $rows = Invoke-Root -Command "sqlite3 $xmsfDatabase select/**/pkg,type,registered_type,blocked,island_enabled/**/from/**/REGISTERED_APPLICATION/**/order/**/by/**/pkg" -AllowFailure
    return $rows | Where-Object { $_ -match ('^' + [regex]::Escape($Package) + '\|') } | Select-Object -Last 1
}

function Test-RegisteredTypeOne {
    $row = Get-RegistrationRow
    if (-not $row) { return $false }
    $columns = $row -split '\|'
    return $columns.Count -ge 3 -and $columns[2] -eq '1'
}

function Get-LatestEventId {
    $ids = foreach ($row in (Invoke-Root -Command "sqlite3 $xmsfDatabase select/**/id,pkg,type,result/**/from/**/EVENT/**/order/**/by/**/id" -AllowFailure)) {
        $columns = $row -split '\|'
        if ($columns.Count -ge 4 -and $columns[1] -eq $Package -and $columns[0] -match '^\d+$') {
            [int64]$columns[0]
        }
    }
    if ($ids) { return [int64](($ids | Measure-Object -Maximum).Maximum) }
    return [int64]0
}

function Test-FreshSuccessEvent {
    param([int64]$AfterId)
    $rows = Invoke-Root -Command "sqlite3 $xmsfDatabase select/**/id,pkg,type,result/**/from/**/EVENT/**/order/**/by/**/id" -AllowFailure
    return [bool]($rows | Where-Object {
        $columns = $_ -split '\|'
        $columns.Count -ge 4 -and [int64]$columns[0] -gt $AfterId -and
            $columns[1] -eq $Package -and $columns[2] -eq '21' -and $columns[3] -eq '0'
    })
}

function Test-PrivateRegId {
    $xml = (Invoke-Root -Command "cat $privatePreference" -AllowFailure) -join "`n"
    if ([string]::IsNullOrWhiteSpace($xml)) { return $false }
    $match = [regex]::Match($xml, '<string name="regId">(.*?)</string>', 'Singleline')
    return $match.Success -and $match.Groups[1].Value.Length -gt 0
}

function Get-CompatLogLines {
    return @(Invoke-Root -Command '/data/adb/lspd/cli log cat' -AllowFailure |
        Where-Object { $_ -match 'XmsfAppCompat:' })
}

function Get-Audit {
    $deny = Get-Denylist
    $componentsReady = $true
    foreach ($component in $profile.Components) {
        if (Get-ComponentDisabled -Component $component) { $componentsReady = $false }
    }
    [pscustomobject]@{
        Serial = $Serial
        Package = $Package
        VersionCode = Get-InstalledVersionCode
        ProfileImplemented = [bool]$profile.Implemented
        ModuleInstalled = [bool](Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'pm', 'path', $modulePackage) -AllowFailure |
            Where-Object { $_ -match '^package:' })
        ModuleScopePresent = Test-ModuleScope -Lines (Get-ModuleScope)
        MainDenyEntryPresent = Test-DenyEntry -Lines $deny -Process $Package
        PushDenyEntryPresent = Test-DenyEntry -Lines $deny -Process "$Package`:push"
        ComponentsReady = $componentsReady
        RegisteredType1 = Test-RegisteredTypeOne
        PrivateRegIdPresent = Test-PrivateRegId
        LatestEventId = Get-LatestEventId
    }
}

function Backup-State {
    param([hashtable]$ComponentState, [string[]]$Denylist, [bool]$ScopePresent)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path ([IO.Path]::GetFullPath($BackupRoot)) "xmsf-app-registration-$stamp-$($Package.Replace('.', '_'))"
    [IO.Directory]::CreateDirectory($backup) | Out-Null

    [pscustomobject]@{
        Serial = $Serial
        Package = $Package
        VersionCode = Get-InstalledVersionCode
        ComponentDisabled = $ComponentState
        DenyEntries = @($Denylist | Where-Object {
            $_ -match ('^' + [regex]::Escape($Package) + '\|')
        } | ForEach-Object {
            [pscustomobject]@{ Process = ($_ -split '\|', 2)[1]; Present = $true }
        })
        ModuleScopePresent = $ScopePresent
        RegistrationRowPresent = [bool](Get-RegistrationRow)
        RegisteredType1 = Test-RegisteredTypeOne
        PrivateRegIdPresent = Test-PrivateRegId
        LatestEventId = Get-LatestEventId
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backup 'state.json') -Encoding UTF8

    $deviceBackup = "$controlDirectory/backup"
    Invoke-Root -Command "mkdir -p $deviceBackup" | Out-Null
    Invoke-Root -Command "cp -p $xmsfDatabase $deviceBackup/xmsf.db" | Out-Null
    Invoke-Root -Command "cp -p $xmsfDatabase-wal $deviceBackup/xmsf.db-wal" -AllowFailure | Out-Null
    Invoke-Root -Command "cp -p $xmsfDatabase-shm $deviceBackup/xmsf.db-shm" -AllowFailure | Out-Null
    Invoke-Root -Command "cp -p $privatePreference $deviceBackup/mipush.xml" -AllowFailure | Out-Null
    foreach ($deviceFile in @('xmsf.db', 'xmsf.db-wal', 'xmsf.db-shm', 'mipush.xml')) {
        Invoke-Root -Command "chmod 0644 $deviceBackup/$deviceFile" -AllowFailure | Out-Null
    }
    Invoke-Adb -Arguments @('-s', $Serial, 'pull', "$deviceBackup/xmsf.db", (Join-Path $backup 'xmsf.db')) | Out-Null
    Invoke-Adb -Arguments @('-s', $Serial, 'pull', "$deviceBackup/xmsf.db-wal", (Join-Path $backup 'xmsf.db-wal')) -AllowFailure | Out-Null
    Invoke-Adb -Arguments @('-s', $Serial, 'pull', "$deviceBackup/xmsf.db-shm", (Join-Path $backup 'xmsf.db-shm')) -AllowFailure | Out-Null
    Invoke-Adb -Arguments @('-s', $Serial, 'pull', "$deviceBackup/mipush.xml", (Join-Path $backup 'mipush.xml')) -AllowFailure | Out-Null
    return $backup
}

function Set-ControlMarker {
    param([ValidateSet('register', 'unregister')][string]$RequestedAction)
    Invoke-Root -Command "mkdir -p $controlDirectory" | Out-Null
    Invoke-Root -Command "chmod 0711 $controlDirectory" | Out-Null
    Remove-ControlMarkers
    Invoke-Root -Command "touch $controlDirectory/$Package.$RequestedAction.once" | Out-Null
    Invoke-Root -Command "chmod 0644 $controlDirectory/$Package.$RequestedAction.once" | Out-Null
    if ($profile.VectorCredential -and $RequestedAction -eq 'register') {
        $pathLine = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'pm', 'path', $vectorPackage) |
            Where-Object { $_ -match '^package:' } | Select-Object -First 1
        $vectorApkPath = $pathLine -replace '^package:', ''
        if ($vectorApkPath -notmatch '^/data/app/[A-Za-z0-9_./+=~-]+/base\.apk$') {
            throw 'Installed Vector APK path did not pass validation.'
        }
        Invoke-Root -Command "ln -sf $vectorApkPath $controlDirectory/$Package.vector-apk.path" | Out-Null
    }
}

function Remove-ControlMarkers {
    Invoke-Root -Command "rm -f $controlDirectory/$Package.register.once $controlDirectory/$Package.unregister.once $controlDirectory/$Package.vector-apk.path" -AllowFailure | Out-Null
}

function Start-Target {
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'start', '-W', '-n', $profile.Launcher) | Out-Null
}

function Invoke-NativeAction {
    param([ValidateSet('register', 'unregister')][string]$RequestedAction)
    $logsBefore = @(Get-CompatLogLines).Count
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $Package) | Out-Null
    Set-ControlMarker -RequestedAction $RequestedAction
    Start-Target
    $nativeWaitSeconds = if ($profile.VectorCredential) { 75 } else { 35 }
    $deadline = (Get-Date).AddSeconds($nativeWaitSeconds)
    $invoked = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 3
        $newLogs = @(Get-CompatLogLines | Select-Object -Skip $logsBefore)
        if ($newLogs | Where-Object { $_ -match "native $RequestedAction invoked" }) {
            $invoked = $true
            break
        }
        if ($newLogs | Where-Object { $_ -match 'version guard rejected|Throwable|Exception' }) { break }
    }
    return $invoked
}

$state = (Invoke-Adb -Arguments @('-s', $Serial, 'get-state') | Select-Object -Last 1).Trim()
if ($state -ne 'device') { throw "Device '$Serial' is not in adb device state." }
if ((Invoke-Root -Command 'id' | Select-Object -Last 1) -notmatch 'uid=0\(root\)') {
    throw "Root was not granted on '$Serial'."
}

if ($Action -in @('Audit', 'Verify') -and -not $Apply) {
    Get-Audit
    return
}
if (-not $Apply) { throw "Action '$Action' changes device state and requires -Apply." }
if (-not $profile.Implemented) {
    throw "Package '$Package' is reviewed but does not yet have an implemented compatibility profile."
}
if ((Get-InstalledVersionCode) -ne $profile.VersionCode) {
    throw "Installed version does not match the reviewed profile version $($profile.VersionCode)."
}
if (-not (Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'pm', 'path', $modulePackage) -AllowFailure |
        Where-Object { $_ -match '^package:' })) {
    throw "Compatibility module '$modulePackage' is not installed."
}

$scopeBefore = Test-ModuleScope -Lines (Get-ModuleScope)
$denyBefore = Get-Denylist
$denyEntries = @($denyBefore | Where-Object {
    $_ -match ('^' + [regex]::Escape($Package) + '\|')
})
$componentBefore = @{}
foreach ($component in $profile.Components) {
    $componentBefore[$component] = Get-ComponentDisabled -Component $component
}
$backupPath = Backup-State -ComponentState $componentBefore -Denylist $denyBefore -ScopePresent $scopeBefore
$baselineEventId = Get-LatestEventId
$compatLogBaseline = @(Get-CompatLogLines).Count
$success = $false
$nativeActionObserved = $false
$restoreErrors = [Collections.Generic.List[string]]::new()

try {
    Invoke-Root -Command "/data/adb/lspd/cli modules enable $modulePackage" | Out-Null
    if (-not $scopeBefore) {
        Invoke-Root -Command "/data/adb/lspd/cli scope add $modulePackage $Package/0" | Out-Null
    }
    foreach ($entry in $denyEntries) {
        $process = ($entry -split '\|', 2)[1]
        Invoke-Root -Command "magisk --denylist rm $Package $process" | Out-Null
    }
    foreach ($component in $profile.Components) {
        Invoke-Root -Command "pm enable --user 0 $Package/$component" | Out-Null
    }

    if ($Action -eq 'Reregister') {
        $nativeActionObserved = Invoke-NativeAction -RequestedAction unregister
        Start-Sleep -Seconds 12
        Remove-ControlMarkers
    }
    if ($Action -in @('Register', 'Reregister')) {
        $nativeActionObserved = Invoke-NativeAction -RequestedAction register
    }

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    $freshEvent = $false
    $registered = $false
    $privateRegId = $false
    $nativeCallback = $false
    $tokenBinding = $false
    $bindingRpc = $false
    $bindingCallbackSuccess = $false
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $freshEvent = Test-FreshSuccessEvent -AfterId $baselineEventId
        $registered = Test-RegisteredTypeOne
        $privateRegId = Test-PrivateRegId
        $logs = @(Get-CompatLogLines | Select-Object -Skip $compatLogBaseline)
        $nativeCallback = [bool]($logs | Where-Object { $_ -match 'native register command callback succeeded' })
        $tokenBinding = [bool]($logs | Where-Object { $_ -match 'Alipay onToken(After|Before) completed' })
        $bindingRpc = [bool]($logs | Where-Object {
            $_ -match 'Alipay (manufacturer token-bind RPC|optimized token-bind enqueue) completed'
        })
        $bindingCallbackSuccess = [bool]($logs | Where-Object {
            $_ -match 'Alipay token-bind callback status=100(\D|$)'
        })
        $baseSuccess = $freshEvent -and $registered -and $privateRegId -and
            ($nativeActionObserved -or -not $profile.RequireNativeInvocation)
        $bindingSuccess = -not $profile.RequireAlipayBinding -or
            ($nativeCallback -and $tokenBinding -and $bindingRpc -and $bindingCallbackSuccess)
        if ($baseSuccess -and $bindingSuccess) {
            $success = $true
            break
        }
    }
}
finally {
    try { Remove-ControlMarkers } catch { $restoreErrors.Add($_.Exception.Message) }
    try { Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $Package) | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    if (-not $scopeBefore) {
        try { Invoke-Root -Command "/data/adb/lspd/cli scope rm $modulePackage $Package/0" | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    }
    foreach ($entry in $denyEntries) {
        $process = ($entry -split '\|', 2)[1]
        try { Invoke-Root -Command "magisk --denylist add $Package $process" | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    }
    try { Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'cmd', 'package', 'unstop', '--user', '0', $Package) | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    if (-not $success) {
        foreach ($component in $profile.Components) {
            try {
                if ($componentBefore[$component]) {
                    Invoke-Root -Command "pm disable --user 0 $Package/$component" | Out-Null
                } else {
                    Invoke-Root -Command "pm default-state --user 0 $Package/$component" | Out-Null
                }
            } catch { $restoreErrors.Add($_.Exception.Message) }
        }
    }
    try {
        Invoke-Root -Command "rm -f $controlDirectory/backup/xmsf.db $controlDirectory/backup/xmsf.db-wal $controlDirectory/backup/xmsf.db-shm $controlDirectory/backup/mipush.xml" -AllowFailure | Out-Null
        Invoke-Root -Command "rmdir $controlDirectory/backup" -AllowFailure | Out-Null
    } catch { $restoreErrors.Add($_.Exception.Message) }
}

Start-Target
Start-Sleep -Seconds 8
Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'input', 'keyevent', '3') -AllowFailure | Out-Null
$audit = Get-Audit
$denyAfter = Get-Denylist
$scopeRestored = (Test-ModuleScope -Lines (Get-ModuleScope)) -eq $scopeBefore
$denyRestored = -not @($denyEntries | Where-Object { $_ -notin $denyAfter }).Count

[pscustomobject]@{
    Serial = $Serial
    Package = $Package
    Action = $Action
    RegistrationPassed = $success -and $audit.ComponentsReady -and $scopeRestored -and $denyRestored -and $restoreErrors.Count -eq 0
    FreshEvent21Result0 = Test-FreshSuccessEvent -AfterId $baselineEventId
    RegisteredType1 = $audit.RegisteredType1
    PrivateRegIdPresent = $audit.PrivateRegIdPresent
    NativeRegistrationInvoked = $nativeActionObserved
    NativeTokenBindingObserved = $bindingRpc
    NativeTokenBindingSucceeded = $bindingCallbackSuccess
    ComponentsReady = $audit.ComponentsReady
    ModuleScopeRestored = $scopeRestored
    DenylistRestored = $denyRestored
    RestoreErrorCount = $restoreErrors.Count
    BackupPath = $backupPath
}
