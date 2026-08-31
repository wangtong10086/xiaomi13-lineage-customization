[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('NativeFcm', 'NativeFcmGuarded', 'ThanoxDelegate', 'ThanoxNotifyOnly')][string]$Mode,
    [string]$Serial,
    [string]$AdbPath = 'adb',
    [string]$ThanoxHelperPath = (Join-Path $PSScriptRoot 'work\thanox-wechat-push-cli.jar'),
    [string]$BackupRoot = 'E:\Xiaomi13Migration',
    [ValidateSet('Phone', 'WindowsDpapi')][string]$BackupTarget = 'Phone',
    [string]$JavaPath,
    [string]$ApkSignerJarPath,
    [switch]$EnableBackgroundRestriction,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$wechatPackage = 'com.tencent.mm'
$thanoxPackage = 'github.tornaco.android.thanos'
$expectedWechatVersionCodes = @(3085L, 3160L)
$expectedThanoxVersionCode = 3354368L
$remoteHelper = '/data/local/tmp/thanox-wechat-push-cli.jar'

function Resolve-Adb {
    $command = Get-Command -Name $AdbPath -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if (Test-Path -LiteralPath $AdbPath -PathType Leaf) { return (Resolve-Path -LiteralPath $AdbPath).Path }
    throw "adb was not found at '$AdbPath'."
}

$script:Adb = Resolve-Adb

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

if (-not $Serial) {
    $devices = @(Invoke-Adb -Arguments @('devices', '-l') | Where-Object { $_ -match '^([^\s]+)\s+device\b' })
    if ($devices.Count -ne 1) { throw "Expected exactly one authorized ADB device; found $($devices.Count)." }
    $Serial = ([regex]::Match($devices[0], '^([^\s]+)')).Groups[1].Value
}

function Invoke-Device {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    return Invoke-Adb -Arguments (@('-s', $Serial, 'shell') + $Arguments) -AllowFailure:$AllowFailure
}

function Invoke-Root {
    param([Parameter(Mandatory)][string]$Command, [switch]$AllowFailure)
    $quoted = "'" + $Command.Replace("'", "'`"'`"'") + "'"
    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'su', '-c', $quoted) -AllowFailure:$AllowFailure
}

function Get-VersionCode {
    param([Parameter(Mandatory)][string]$Package)
    $line = Invoke-Device -Arguments @('dumpsys', 'package', $Package) |
        Where-Object { $_ -match 'versionCode=(\d+)' } | Select-Object -First 1
    if (-not $line -or $line -notmatch 'versionCode=(\d+)') { return [int64]-1 }
    return [int64]$Matches[1]
}

function Get-ProtectedConfigDigest {
    $command = "/data/adb/magisk/busybox find /data/adb/modules/playintegrityfix /data/adb/modules/Yurikey /data/adb/modules/fuxi_prop_spoof /data/adb/migration-disabled-static-extras/service.d -type f -exec sha256sum {} ';' 2>/dev/null | sort | sha256sum | cut -d ' ' -f 1"
    return ((Invoke-Root -Command $command) -join '').Trim()
}

function Convert-HelperState {
    param([Parameter(Mandatory)][string[]]$Lines)
    $state = [ordered]@{}
    foreach ($line in $Lines) {
        if ($line -match '^([A-Za-z]+)=(true|false)$') { $state[$Matches[1]] = [bool]::Parse($Matches[2]) }
    }
    foreach ($key in @('delegateEnabled','showContent','startApp','skipIfRunning',
            'startBlocked','backgroundRestricted','smartStandby','smartStandbyGlobal',
            'smartStandbyStopService','smartStandbyUnbindService',
            'smartStandbySetInactive','smartStandbyBypassNotification',
            'smartStandbyBypassVisible','smartStandbyBlockServiceRestart')) {
        if (-not $state.Contains($key)) { throw "Thanox helper did not return '$key'." }
    }
    return [pscustomobject]$state
}

function Invoke-ThanoxHelper {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $argText = $Arguments -join ' '
    $lines = Invoke-Root -Command "CLASSPATH=$remoteHelper app_process /system/bin com.codex.wechatpush.ThanoxWechatPushCli $argText" -AllowFailure:$AllowFailure
    if ($AllowFailure -and ($lines | Where-Object { $_ -match '^ERROR=' })) { return $null }
    return Convert-HelperState -Lines $lines
}

function Get-PackagePaths {
    param([Parameter(Mandatory)][string]$Package)
    return @(Invoke-Device -Arguments @('pm', 'path', $Package) | ForEach-Object {
        if ($_ -match '^package:(.+)$') { $Matches[1] }
    })
}

function Get-SmartStandbyScope {
    $command = @'
root=$(find /data/system -maxdepth 1 -type d -name 'thanos_*' 2>/dev/null | head -n 1)
file="$root/data/u/0/smart_stand_by_pkgs.xml"
count=$(grep -oE '[A-Za-z][A-Za-z0-9_]*(\.[A-Za-z0-9_]+){2,}' "$file" 2>/dev/null | sort -u | wc -l)
if grep -q 'com.tencent.mm' "$file" 2>/dev/null; then listed=true; else listed=false; fi
echo "count=$count"
echo "wechatListed=$listed"
'@
    $lines = Invoke-Root -Command $command
    $countLine = $lines | Where-Object { $_ -match '^count=(\d+)$' } | Select-Object -First 1
    $listedLine = $lines | Where-Object { $_ -match '^wechatListed=(true|false)$' } | Select-Object -First 1
    if (-not $countLine -or -not $listedLine) { throw 'Unable to verify Thanox smart-standby scope.' }
    return [pscustomobject]@{
        Count = [int]([regex]::Match($countLine, '\d+').Value)
        WeChatListed = $listedLine -match '=true$'
    }
}

function Save-ApkSet {
    param([Parameter(Mandatory)][string]$Package, [Parameter(Mandatory)][string]$Prefix, [Parameter(Mandatory)][string]$Directory)
    $index = 0
    foreach ($devicePath in (Get-PackagePaths -Package $Package)) {
        $leaf = [IO.Path]::GetFileName($devicePath)
        $destination = Join-Path $Directory ("$Prefix-$index-$leaf")
        Invoke-Adb -Arguments @('-s', $Serial, 'pull', $devicePath, $destination) | Out-Null
        $index++
    }
    if ($index -eq 0) { throw "No APK paths found for $Package." }
}

function Save-SignatureSummary {
    param([Parameter(Mandatory)][string]$ApkDirectory, [Parameter(Mandatory)][string]$ReportPath)
    $lines = [System.Collections.Generic.List[string]]::new()
    foreach ($apk in (Get-ChildItem -LiteralPath $ApkDirectory -Filter '*.apk' | Sort-Object Name)) {
        $hash = Get-FileHash -Algorithm SHA256 -LiteralPath $apk.FullName
        $lines.Add("$($apk.Name) sha256=$($hash.Hash)")
        if ($JavaPath -and $ApkSignerJarPath) {
            $signer = & $JavaPath -jar $ApkSignerJarPath verify --print-certs $apk.FullName 2>&1
            if ($LASTEXITCODE -ne 0) { throw "apksigner failed for $($apk.Name)." }
            foreach ($line in $signer) {
                if ($line -match 'Signer #\d+ certificate (SHA-256 digest|DN):') { $lines.Add($line.ToString()) }
            }
        }
    }
    Set-Content -LiteralPath $ReportPath -Value $lines -Encoding utf8NoBOM
}

function New-WindowsEncryptedBackup {
    param([Parameter(Mandatory)][pscustomobject]$PreState, [Parameter(Mandatory)][string]$ProtectedDigest)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backup = Join-Path $BackupRoot "$stamp-wechat-push"
    $apkDir = Join-Path $backup 'apk'
    $reportDir = Join-Path $backup 'reports'
    New-Item -ItemType Directory -Path $apkDir, $reportDir -Force | Out-Null

    Save-ApkSet -Package $wechatPackage -Prefix 'wechat' -Directory $apkDir
    Save-ApkSet -Package $thanoxPackage -Prefix 'thanox' -Directory $apkDir
    Save-SignatureSummary -ApkDirectory $apkDir -ReportPath (Join-Path $reportDir 'apk-signatures.txt')

    $thanoxRoot = (Invoke-Root -Command "find /data/system -maxdepth 1 -type d -name 'thanos_*' 2>/dev/null | head -n 1" | Select-Object -First 1)
    if (-not $thanoxRoot) { throw 'Thanox data root was not found.' }
    $thanoxData = "$thanoxRoot/data/u/0"
    $remoteArchive = "/data/local/tmp/wechat-push-config-$stamp.tar.gz"
    $plainArchive = Join-Path ([IO.Path]::GetTempPath()) "wechat-push-config-$stamp.tar.gz"
    $encryptedArchive = Join-Path $backup 'private-config-backup.tar.gz.dpapi'
    $paths = @(
        "$thanoxData/thanos.xml",
        "$thanoxData/push_channels.xml",
        "$thanoxData/bg_restrict_pkgs.xml",
        "$thanoxData/smart_stand_by_pkgs.xml",
        "$thanoxData/start_blocking_pkgs.xml",
        '/data/system/procstartstore/procstartinfo',
        '/data/user/0/github.tornaco.android.thanos/databases/rules_database',
        '/data/user/0/com.tencent.mm/shared_prefs/com.google.android.gms.appid.xml',
        '/data/user/0/com.tencent.mm/shared_prefs/com.google.firebase.messaging.xml',
        '/data/user/0/com.tencent.mm/shared_prefs/com.google.android.gms.measurement.prefs.xml',
        '/data/user/0/com.tencent.mm/databases/google_app_measurement.db'
    )

    try {
        Invoke-Root -Command "/data/adb/magisk/busybox tar -czf $remoteArchive $($paths -join ' ')" | Out-Null
        Invoke-Adb -Arguments @('-s', $Serial, 'pull', $remoteArchive, $plainArchive) | Out-Null
        Add-Type -AssemblyName System.Security.Cryptography.ProtectedData
        $plain = [IO.File]::ReadAllBytes($plainArchive)
        $encrypted = [Security.Cryptography.ProtectedData]::Protect(
            $plain, $null, [Security.Cryptography.DataProtectionScope]::CurrentUser)
        [IO.File]::WriteAllBytes($encryptedArchive, $encrypted)
        $archiveHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $plainArchive).Hash

        $metadata = [ordered]@{
            CreatedAt = (Get-Date).ToString('o')
            Serial = $Serial
            ModeRequested = $Mode
            Encryption = 'Windows DPAPI CurrentUser'
            PlaintextArchiveSha256 = $archiveHash
            ProtectedConfigDigestBefore = $ProtectedDigest
            ThanoxStateBefore = $PreState
            MayContainFcmRegistrationMaterial = $true
            ContactsOrMessageContentIncluded = $false
            PrivateFilesRemainEncryptedAtRest = $true
        }
        $metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $reportDir 'backup-metadata.json') -Encoding utf8NoBOM
        @(
            'The private archive is protected with Windows DPAPI for the current user.',
            'Do not commit this backup or its APKs to Git.',
            'Decrypt only for a deliberate restore; no token or message content is printed by the repair scripts.'
        ) | Set-Content -LiteralPath (Join-Path $backup 'README.txt') -Encoding utf8NoBOM
        return [pscustomobject]@{
            Path = $backup
            Sha256 = $archiveHash
            Target = 'WindowsDpapi'
        }
    } finally {
        Invoke-Root -Command "rm -f $remoteArchive" -AllowFailure | Out-Null
        if (Test-Path -LiteralPath $plainArchive) { Remove-Item -LiteralPath $plainArchive -Force }
    }
}

function New-PhoneConfigBackup {
    param([Parameter(Mandatory)][pscustomobject]$PreState,
        [Parameter(Mandatory)][string]$ProtectedDigest)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archive = "/data/adb/wechat-backups/wechat-push-config-$stamp.tar.gz"
    $metadata = "/data/local/tmp/wechat-push-config-$stamp.txt"
    $thanoxRoot = (Invoke-Root -Command (
        "find /data/system -maxdepth 1 -type d -name 'thanos_*' 2>/dev/null | head -n 1") |
        Select-Object -First 1)
    if (-not $thanoxRoot) { throw 'Thanox data root was not found.' }
    $thanoxData = "$thanoxRoot/data/u/0"
    $stateLines = @(
        "created_at=$([DateTimeOffset]::Now.ToString('o'))",
        "serial=$Serial",
        "mode_requested=$Mode",
        "wechat_version_code=$wechatVersion",
        "thanox_version_code=$thanoxVersion",
        "protected_config_digest=$ProtectedDigest"
    ) + @($PreState.psobject.Properties | ForEach-Object {
        "thanox_state_$($_.Name)=$($_.Value.ToString().ToLowerInvariant())"
    })
    $encodedMetadata = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes(($stateLines -join "`n") + "`n"))
    $paths = @(
        "$thanoxData/thanos.xml",
        "$thanoxData/push_channels.xml",
        "$thanoxData/bg_restrict_pkgs.xml",
        "$thanoxData/smart_stand_by_pkgs.xml",
        "$thanoxData/start_blocking_pkgs.xml",
        '/data/system/procstartstore/procstartinfo',
        '/data/user/0/github.tornaco.android.thanos/databases/rules_database',
        '/data/user/0/com.tencent.mm/shared_prefs/com.google.android.gms.appid.xml',
        '/data/user/0/com.tencent.mm/shared_prefs/com.google.firebase.messaging.xml',
        '/data/user/0/com.tencent.mm/shared_prefs/com.google.android.gms.measurement.prefs.xml',
        '/data/user/0/com.tencent.mm/databases/google_app_measurement.db'
    )
    try {
        $command = @"
set -eu
mkdir -p /data/adb/wechat-backups
chmod 0700 /data/adb/wechat-backups
echo $encodedMetadata | /data/adb/magisk/busybox base64 -d > $metadata
chmod 0600 $metadata
/data/adb/magisk/busybox tar -czf $archive $metadata $($paths -join ' ') 2>/dev/null
/data/adb/magisk/busybox tar -tzf $archive >/dev/null
chmod 0600 $archive
sha256sum $archive
"@
        $line = Invoke-Root -Command $command | Where-Object {
            $_ -match '^([0-9a-f]{64})\s+(.+)$'
        } | Select-Object -Last 1
        if (-not $line -or $line -notmatch '^([0-9a-f]{64})\s+(.+)$') {
            throw 'Phone-local configuration backup did not produce a SHA-256 digest.'
        }
        return [pscustomobject]@{
            Path = $Matches[2]
            Sha256 = $Matches[1]
            Target = 'Phone'
        }
    } finally {
        Invoke-Root -Command "rm -f $metadata" -AllowFailure | Out-Null
    }
}

$wechatVersion = Get-VersionCode -Package $wechatPackage
$thanoxVersion = Get-VersionCode -Package $thanoxPackage
$product = ((Invoke-Device -Arguments @('getprop', 'ro.product.device')) -join '').Trim()
$rootId = (Invoke-Root -Command 'id' | Select-Object -First 1)
if ($rootId -notmatch 'uid=0') { throw 'Root shell is unavailable.' }
if ($product -ne 'fuxi') { throw "Unsupported device '$product'; expected fuxi." }
if ($expectedWechatVersionCodes -notcontains $wechatVersion) {
    throw "WeChat versionCode $wechatVersion does not match verified locks $($expectedWechatVersionCodes -join ', ')."
}
if ($thanoxVersion -ne $expectedThanoxVersionCode) {
    throw "Thanox versionCode $thanoxVersion does not match lock $expectedThanoxVersionCode."
}
if ($Mode -ne 'ThanoxDelegate' -and $EnableBackgroundRestriction) {
    throw '-EnableBackgroundRestriction is valid only with -Mode ThanoxDelegate.'
}

$proposal = [ordered]@{
    Mode = $Mode
    Apply = [bool]$Apply
    WeChatVersionCode = $wechatVersion
    ThanoxVersionCode = $thanoxVersion
    BackupTarget = $BackupTarget
    Changes = if ($Mode -eq 'NativeFcm') {
        @('Disable Thanox WeChat delegate', 'Remove WeChat from Thanox start blocking', 'Remove extra background restriction', 'Enable smart standby')
    } elseif ($Mode -eq 'NativeFcmGuarded') {
        @('Disable Thanox WeChat delegate',
          'Enable Thanox package start blocking; reviewed live behavior still permits system FCM and user activity starts',
          'Remove the extra background restriction',
          'Enable WeChat-only smart-standby stop-service and restart-block lifecycle controls')
    } elseif ($Mode -eq 'ThanoxNotifyOnly') {
        @('Enable Thanox delegate/content/skip-if-running',
          'Disable start-app-on-push so FCM arrival does not launch WeChat',
          'Enable Thanox background start blocking while preserving user activity launches',
          'Remove the extra background restriction',
          'Enable WeChat-only smart-standby stop-service and restart-block lifecycle controls')
    } elseif ($EnableBackgroundRestriction) {
        @('Enable Thanox delegate/content/skip-if-running/start-app', 'Remove Thanox start blocking', 'Enable staged background restriction', 'Enable smart standby')
    } else {
        @('Enable Thanox delegate/content/skip-if-running/start-app', 'Remove Thanox start blocking', 'Remove extra background restriction', 'Enable smart standby')
    }
    ForbiddenOperations = @('pm clear', 'force-stop', 'freeze/disable Firebase components', 'direct WeChat database writes')
}
$proposal | ConvertTo-Json -Depth 5

if (-not $Apply) {
    & (Join-Path $PSScriptRoot 'Audit-WeChatPush.ps1') -Serial $Serial -AdbPath $script:Adb
    return
}

if (-not (Test-Path -LiteralPath $ThanoxHelperPath -PathType Leaf)) {
    throw "Thanox helper was not found at '$ThanoxHelperPath'. Build it with Build-ThanoxWechatPushCli.ps1."
}

$backupInfo = $null
$preState = $null
$stoppedBefore = $null
$protectedDigestBefore = Get-ProtectedConfigDigest
try {
    Invoke-Adb -Arguments @('-s', $Serial, 'push', $ThanoxHelperPath, $remoteHelper) | Out-Null
    Invoke-Root -Command "chmod 0600 $remoteHelper" | Out-Null
    $preState = Invoke-ThanoxHelper -Arguments @('audit')
    if (-not $preState.smartStandbyGlobal -or
            $Mode -eq 'ThanoxNotifyOnly' -or $Mode -eq 'NativeFcmGuarded') {
        $smartStandbyScope = Get-SmartStandbyScope
        if ($smartStandbyScope.Count -ne 1 -or -not $smartStandbyScope.WeChatListed) {
            throw 'Refusing to enable global smart standby: its package scope is not limited to WeChat.'
        }
    }
    $stoppedBeforeLine = Invoke-Device -Arguments @('dumpsys', 'package', $wechatPackage) |
        Where-Object { $_ -match '^\s*User 0:.*installed=' } | Select-Object -First 1
    $stoppedBefore = $stoppedBeforeLine -match 'stopped=true'
    $backupInfo = if ($BackupTarget -eq 'Phone') {
        New-PhoneConfigBackup -PreState $preState -ProtectedDigest $protectedDigestBefore
    } else {
        New-WindowsEncryptedBackup -PreState $preState -ProtectedDigest $protectedDigestBefore
    }

    $command = if ($Mode -eq 'NativeFcm') {
        'apply-native'
    } elseif ($Mode -eq 'NativeFcmGuarded') {
        'apply-native-guarded'
    } elseif ($Mode -eq 'ThanoxNotifyOnly') {
        'apply-thanox-notify-only'
    } elseif ($EnableBackgroundRestriction) {
        'apply-thanox-restricted'
    } else {
        'apply-thanox'
    }
    $postState = Invoke-ThanoxHelper -Arguments @($command)

    $protectedDigestAfter = Get-ProtectedConfigDigest
    if ($protectedDigestAfter -ne $protectedDigestBefore) {
        throw 'Protected Wallet/Integrity/keybox configuration digest changed unexpectedly.'
    }

    $stoppedLine = Invoke-Device -Arguments @('dumpsys', 'package', $wechatPackage) |
        Where-Object { $_ -match '^\s*User 0:.*installed=' } | Select-Object -First 1
    $stoppedAfter = $stoppedLine -match 'stopped=true'
    if (-not $stoppedBefore -and $stoppedAfter) {
        throw 'WeChat transitioned to stopped state while applying the configuration.'
    }

    $result = [ordered]@{
        Applied = $true
        Mode = $Mode
        BackgroundRestrictionRequested = [bool]$EnableBackgroundRestriction
        BackupPath = $backupInfo.Path
        BackupSha256 = $backupInfo.Sha256
        BackupTarget = $backupInfo.Target
        ProtectedConfigDigestUnchanged = $true
        ThanoxStateBefore = $preState
        ThanoxStateAfter = $postState
        WeChatStopped = $stoppedAfter
        RequiresManualLaunch = $stoppedAfter
        ForceStopUsed = $false
        DatabaseWriteUsed = $false
    }
    $result | ConvertTo-Json -Depth 6
} catch {
    if ($preState) {
        $restoreArgs = @(
            'restore',
            $preState.delegateEnabled.ToString().ToLowerInvariant(),
            $preState.showContent.ToString().ToLowerInvariant(),
            $preState.startApp.ToString().ToLowerInvariant(),
            $preState.skipIfRunning.ToString().ToLowerInvariant(),
            $preState.startBlocked.ToString().ToLowerInvariant(),
            $preState.backgroundRestricted.ToString().ToLowerInvariant(),
            $preState.smartStandby.ToString().ToLowerInvariant(),
            $preState.smartStandbyGlobal.ToString().ToLowerInvariant(),
            $preState.smartStandbyStopService.ToString().ToLowerInvariant(),
            $preState.smartStandbyUnbindService.ToString().ToLowerInvariant(),
            $preState.smartStandbySetInactive.ToString().ToLowerInvariant(),
            $preState.smartStandbyBypassNotification.ToString().ToLowerInvariant(),
            $preState.smartStandbyBypassVisible.ToString().ToLowerInvariant(),
            $preState.smartStandbyBlockServiceRestart.ToString().ToLowerInvariant()
        )
        Invoke-ThanoxHelper -Arguments $restoreArgs -AllowFailure | Out-Null
    }
    throw
} finally {
    Invoke-Root -Command "rm -f $remoteHelper" -AllowFailure | Out-Null
}
