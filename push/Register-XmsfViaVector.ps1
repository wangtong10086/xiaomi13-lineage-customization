[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$Serial,
    [Parameter(Mandatory)][ValidateSet(
        'com.ss.android.ugc.aweme',
        'com.MobileTicket',
        'com.lietou.mishu',
        'cn.gov.tax.its',
        'com.chinamworld.main')][string]$Package,
    [Parameter(Mandatory)][string]$AdbPath,
    [string]$BackupRoot = 'E:\Xiaomi13Migration',
    [ValidateRange(30, 180)][int]$WaitSeconds = 90,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$profile = @{
    'com.ss.android.ugc.aweme' = [pscustomobject]@{
        VersionCode = 400201L
        Launcher = 'com.ss.android.ugc.aweme/.splash.SplashActivity'
        Strategy = 'built-in-profile'
    }
    'com.MobileTicket' = [pscustomobject]@{
        VersionCode = 280L
        Launcher = 'com.MobileTicket/.ui.activity.WelcomeGuideActivity'
        Strategy = 'auto-detect'
    }
    'com.lietou.mishu' = [pscustomobject]@{
        VersionCode = 13081L
        Launcher = 'com.lietou.mishu/.HomeActivity'
        Strategy = 'auto-detect'
    }
    'cn.gov.tax.its' = [pscustomobject]@{
        VersionCode = 20303L
        Launcher = 'cn.gov.tax.its/.MainActivity'
        Strategy = 'built-in-profile'
    }
    'com.chinamworld.main' = [pscustomobject]@{
        VersionCode = 2351L
        Launcher = 'com.chinamworld.main/com.ccb.start.MainActivity'
        Strategy = 'auto-detect'
    }
}[$Package]

$modulePackage = 'io.github.magisk317.mipush'
$xmsfDatabase = '/data/user/0/com.xiaomi.xmsf/databases/db'

if (-not (Test-Path -LiteralPath $AdbPath -PathType Leaf)) {
    throw "adb was not found at '$AdbPath'."
}
$script:Adb = (Resolve-Path -LiteralPath $AdbPath).Path

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

function Get-VersionCode {
    $line = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'dumpsys', 'package', $Package) |
        Where-Object { $_ -match 'versionCode=(\d+)' } | Select-Object -First 1
    if (-not $line -or $line -notmatch 'versionCode=(\d+)') { return [int64]-1 }
    return [int64]$Matches[1]
}

function Get-Scope {
    return @(Invoke-Root -Command "/data/adb/lspd/cli scope ls $modulePackage" -AllowFailure)
}

function Test-Scope {
    param([string[]]$Lines)
    return [bool]($Lines | Where-Object {
        $_ -match ('^\s*' + [regex]::Escape($Package) + '\s+0\s*$')
    })
}

function Get-Denylist {
    return @(Invoke-Root -Command 'magisk --denylist ls')
}

function Get-Events {
    return @(Invoke-Root -Command `
        "sqlite3 $xmsfDatabase select/**/id,pkg,type,result/**/from/**/EVENT/**/order/**/by/**/id" `
        -AllowFailure)
}

function Get-LatestPackageEventId {
    $ids = foreach ($row in (Get-Events)) {
        $columns = $row -split '\|'
        if ($columns.Count -ge 4 -and $columns[1] -eq $Package -and $columns[0] -match '^\d+$') {
            [int64]$columns[0]
        }
    }
    if ($ids) { return [int64](($ids | Measure-Object -Maximum).Maximum) }
    return [int64]0
}

function Test-FreshRegistrationResult {
    param([int64]$AfterId)
    foreach ($row in (Get-Events)) {
        $columns = $row -split '\|'
        if ($columns.Count -ge 4 -and $columns[0] -match '^\d+$' -and
                [int64]$columns[0] -gt $AfterId -and $columns[1] -eq $Package -and
                $columns[2] -eq '21' -and $columns[3] -eq '0') {
            return $true
        }
    }
    return $false
}

function Test-RegisteredTypeOne {
    $rows = Invoke-Root -Command `
        "sqlite3 $xmsfDatabase select/**/pkg,type,registered_type,blocked/**/from/**/REGISTERED_APPLICATION/**/order/**/by/**/pkg" `
        -AllowFailure
    $row = $rows | Where-Object { $_ -match ('^' + [regex]::Escape($Package) + '\|') } |
        Select-Object -Last 1
    if (-not $row) { return $false }
    $columns = $row -split '\|'
    return $columns.Count -ge 3 -and $columns[2] -eq '1'
}

function Test-PrivateRegId {
    $xml = (Invoke-Root -Command "cat /data/user/0/$Package/shared_prefs/mipush.xml" -AllowFailure) -join "`n"
    if ([string]::IsNullOrWhiteSpace($xml)) { return $false }
    $match = [regex]::Match($xml, '<string name="regId">(.*?)</string>', 'Singleline')
    return $match.Success -and $match.Groups[1].Value.Length -gt 0
}

if ((Invoke-Adb -Arguments @('-s', $Serial, 'get-state') | Select-Object -Last 1).Trim() -ne 'device') {
    throw "Device '$Serial' is not in adb device state."
}
if ((Invoke-Root -Command 'id' | Select-Object -Last 1) -notmatch 'uid=0\(root\)') {
    throw "Root was not granted on '$Serial'."
}
if ((Get-VersionCode) -ne $profile.VersionCode) {
    throw "Installed version does not match the reviewed profile version $($profile.VersionCode)."
}
if (-not $Apply) {
    [pscustomobject]@{
        Package = $Package
        VersionCode = Get-VersionCode
        Strategy = $profile.Strategy
        RegisteredType1 = Test-RegisteredTypeOne
        PrivateRegIdPresent = Test-PrivateRegId
        VectorScopePresent = Test-Scope -Lines (Get-Scope)
        LatestEventId = Get-LatestPackageEventId
    }
    return
}

$scopeBefore = Test-Scope -Lines (Get-Scope)
$denyBefore = Get-Denylist
$denyEntries = @($denyBefore | Where-Object {
    $_ -match ('^' + [regex]::Escape($Package) + '\|')
})
$baselineEventId = Get-LatestPackageEventId
$logBaseline = @(Invoke-Root -Command '/data/adb/lspd/cli log cat' -AllowFailure).Count
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupPath = Join-Path ([IO.Path]::GetFullPath($BackupRoot)) `
    "xmsf-vector-registration-$stamp-$($Package.Replace('.', '_'))"
[IO.Directory]::CreateDirectory($backupPath) | Out-Null

$deviceBackup = '/data/local/tmp/xmsf-vector-registration-backup'
Invoke-Root -Command "mkdir -p $deviceBackup" | Out-Null
Invoke-Root -Command "cp -p $xmsfDatabase $deviceBackup/xmsf.db" | Out-Null
Invoke-Root -Command "chmod 0644 $deviceBackup/xmsf.db" | Out-Null
Invoke-Adb -Arguments @('-s', $Serial, 'pull', "$deviceBackup/xmsf.db", (Join-Path $backupPath 'xmsf.db')) | Out-Null

$freshResult = $false
$registered = $false
$privateRegId = $false
$forcedRegisterObserved = $false
$metaMissing = $false
$retryExhausted = $false
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

    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $Package) | Out-Null
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'start', '-W', '-n', $profile.Launcher) | Out-Null

    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ((Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $freshResult = Test-FreshRegistrationResult -AfterId $baselineEventId
        $registered = Test-RegisteredTypeOne
        $privateRegId = Test-PrivateRegId
        $newLogs = @(Invoke-Root -Command '/data/adb/lspd/cli log cat' -AllowFailure |
            Select-Object -Skip $logBaseline)
        $forcedRegisterObserved = [bool]($newLogs | Where-Object {
            $_ -match ('(forced registerPush|registerPush before).*' + [regex]::Escape($Package))
        })
        $metaMissing = [bool]($newLogs | Where-Object {
            $_ -match ('meta-data appId/appKey not found for ' + [regex]::Escape($Package))
        })
        $retryExhausted = [bool]($newLogs | Where-Object {
            $_ -match ('retry exhausted for ' + [regex]::Escape($Package))
        })
        if (($freshResult -and $registered) -or $metaMissing -or $retryExhausted) { break }
    }
}
finally {
    try { Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $Package) | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    if (-not $scopeBefore) {
        try { Invoke-Root -Command "/data/adb/lspd/cli scope rm $modulePackage $Package/0" | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    }
    foreach ($entry in $denyEntries) {
        $process = ($entry -split '\|', 2)[1]
        try { Invoke-Root -Command "magisk --denylist add $Package $process" | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    }
    try { Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'cmd', 'package', 'unstop', '--user', '0', $Package) | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    try { Invoke-Root -Command "rm -f $deviceBackup/xmsf.db" -AllowFailure | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
    try { Invoke-Root -Command "rmdir $deviceBackup" -AllowFailure | Out-Null } catch { $restoreErrors.Add($_.Exception.Message) }
}

$scopeRestored = (Test-Scope -Lines (Get-Scope)) -eq $scopeBefore
$denyAfter = Get-Denylist
$denyRestored = -not @($denyEntries | Where-Object { $_ -notin $denyAfter }).Count

[pscustomobject]@{
    Package = $Package
    Strategy = $profile.Strategy
    RegistrationPassed = $freshResult -and $registered -and $scopeRestored -and $denyRestored -and $restoreErrors.Count -eq 0
    FreshRegistrationResult = $freshResult
    RegisteredType1 = $registered
    PrivateRegIdPresent = $privateRegId
    VectorRegistrationAttemptObserved = $forcedRegisterObserved
    CredentialMetadataMissing = $metaMissing
    RetryExhausted = $retryExhausted
    ScopeRestored = $scopeRestored
    DenylistRestored = $denyRestored
    RestoreErrorCount = $restoreErrors.Count
    BackupPath = $backupPath
}
