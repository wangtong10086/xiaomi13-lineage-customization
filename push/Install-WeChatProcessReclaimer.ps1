[CmdletBinding()]
param(
    [string]$Serial,
    [string]$AdbPath = 'adb',
    [string]$ScriptPath = (Join-Path $PSScriptRoot 'wechat-process-reclaimer.sh'),
    [string]$DeviceBackupRoot = '/data/adb/wechat-backups',
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedWechatVersionCode = 3085L
$expectedThanoxVersionCode = 3354368L
$remoteStage = '/data/local/tmp/96-wechat-process-reclaimer.sh'
$remoteScript = '/data/adb/service.d/96-wechat-process-reclaimer.sh'
$stateDir = '/data/adb/wechat-process-reclaimer'

function Resolve-Adb {
    $command = Get-Command -Name $AdbPath -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    if (Test-Path -LiteralPath $AdbPath -PathType Leaf) {
        return (Resolve-Path -LiteralPath $AdbPath).Path
    }
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
    $devices = @(Invoke-Adb -Arguments @('devices', '-l') |
        Where-Object { $_ -match '^([^\s]+)\s+device\b' })
    if ($devices.Count -ne 1) {
        throw "Expected exactly one authorized ADB device; found $($devices.Count)."
    }
    $Serial = ([regex]::Match($devices[0], '^([^\s]+)')).Groups[1].Value
}

function Invoke-Root {
    param([Parameter(Mandatory)][string]$Command, [switch]$AllowFailure)
    $quoted = "'" + $Command.Replace("'", "'`"'`"'") + "'"
    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'su', '-c', $quoted) `
        -AllowFailure:$AllowFailure
}

function Get-VersionCode {
    param([Parameter(Mandatory)][string]$Package)
    $lines = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'dumpsys', 'package', $Package)
    $line = $lines | Where-Object { $_ -match 'versionCode=(\d+)' } | Select-Object -First 1
    if (-not $line -or $line -notmatch 'versionCode=(\d+)') { return -1L }
    return [int64]$Matches[1]
}

function Get-ProtectedConfigDigest {
    $command = "/data/adb/magisk/busybox find /data/adb/modules/playintegrityfix /data/adb/modules/Yurikey /data/adb/modules/fuxi_prop_spoof /data/adb/migration-disabled-static-extras/service.d -type f -exec sha256sum {} ';' 2>/dev/null | sort | sha256sum | cut -d ' ' -f 1"
    return ((Invoke-Root -Command $command) -join '').Trim()
}

function Get-WorkerProcessIds {
    $command = "ps -A -o PID,ARGS 2>/dev/null | grep -F 'sh $remoteScript' | grep -v grep | awk '{print `$1}'"
    return @(Invoke-Root -Command $command -AllowFailure |
        Where-Object { $_ -match '^\d+$' } |
        ForEach-Object { [int]$_ })
}

if (-not (Test-Path -LiteralPath $ScriptPath -PathType Leaf)) {
    throw "Worker script is missing: $ScriptPath"
}
if ((Get-VersionCode -Package 'com.tencent.mm') -ne $expectedWechatVersionCode) {
    throw "WeChat version does not match reviewed lock $expectedWechatVersionCode."
}
if ((Get-VersionCode -Package 'github.tornaco.android.thanos') -ne $expectedThanoxVersionCode) {
    throw "Thanox version does not match reviewed lock $expectedThanoxVersionCode."
}

$localHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $ScriptPath).Hash.ToLowerInvariant()
$installedHash = ((Invoke-Root -Command "sha256sum $remoteScript 2>/dev/null | cut -d ' ' -f 1" `
    -AllowFailure) -join '').Trim()
$previousInstalled = $installedHash -match '^[0-9a-f]{64}$'
$workerProcessIds = @(Get-WorkerProcessIds)
$running = $workerProcessIds.Count -gt 0

[ordered]@{
    Mode = 'RootWeChatProcessReclaimer'
    Apply = [bool]$Apply
    Target = $remoteScript
    LocalSha256 = $localHash
    InstalledSha256 = if ($installedHash -match '^[0-9a-f]{64}$') { $installedHash } else { $null }
    WorkerRunning = $running
    WatchedFields = @('epoch_ms', 'package=com.tencent.mm', 'outcome')
    Action = 'am kill com.tencent.mm'
    ForceStopUsed = $false
    MessageOrTokenDataRead = $false
} | ConvertTo-Json -Depth 5

if (-not $Apply) { return }

$protectedBefore = Get-ProtectedConfigDigest
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = "$DeviceBackupRoot/wechat-process-reclaimer-$stamp.tar.gz"
$backupLine = Invoke-Root -Command @"
set -eu
mkdir -p $DeviceBackupRoot
chmod 0700 $DeviceBackupRoot
/data/adb/magisk/busybox tar -czf $backup /data/adb/service.d 2>/dev/null
/data/adb/magisk/busybox tar -tzf $backup >/dev/null
chmod 0600 $backup
sha256sum $backup
"@ | Where-Object { $_ -match '^([0-9a-f]{64})\s+(.+)$' } | Select-Object -Last 1
if (-not $backupLine -or $backupLine -notmatch '^([0-9a-f]{64})\s+(.+)$') {
    throw 'Phone-local service.d backup failed.'
}
$backupHash = $Matches[1]
$backupPath = $Matches[2]

try {
    Invoke-Adb -Arguments @('-s', $Serial, 'push', $ScriptPath, $remoteStage) | Out-Null
    Invoke-Root -Command "sh -n $remoteStage"
    Invoke-Root -Command "cp $remoteStage $remoteScript; chown 0:0 $remoteScript; chmod 0755 $remoteScript"
    $deviceHash = ((Invoke-Root -Command "sha256sum $remoteScript | cut -d ' ' -f 1") -join '').Trim()
    if ($deviceHash -ne $localHash) { throw 'Installed worker hash mismatch.' }

    foreach ($workerProcessId in @(Get-WorkerProcessIds)) {
        Invoke-Root -Command "kill -TERM $workerProcessId 2>/dev/null || true" -AllowFailure | Out-Null
    }
    $remainingWorkerProcessIds = @(Get-WorkerProcessIds)
    if ($remainingWorkerProcessIds.Count -gt 0) {
        Start-Sleep -Seconds 1
    }
    foreach ($workerProcessId in @(Get-WorkerProcessIds)) {
        Invoke-Root -Command "kill -KILL $workerProcessId 2>/dev/null || true" -AllowFailure | Out-Null
    }
    Invoke-Root -Command "rm -f $stateDir/worker.pid" -AllowFailure | Out-Null
    Invoke-Root -Command "nohup $remoteScript >/dev/null 2>&1 &"
    Start-Sleep -Seconds 3
    $newPid = ((Invoke-Root -Command "cat $stateDir/worker.pid 2>/dev/null") -join '').Trim()
    if ($newPid -notmatch '^\d+$') { throw 'Worker PID was not created.' }
    $alive = (Invoke-Root -Command "kill -0 $newPid 2>/dev/null && echo true || echo false" |
        Select-Object -Last 1) -eq 'true'
    if (-not $alive) { throw 'Worker did not remain running.' }
    if ((Get-ProtectedConfigDigest) -ne $protectedBefore) {
        throw 'Protected Wallet/Integrity/keybox configuration digest changed unexpectedly.'
    }

    [ordered]@{
        Applied = $true
        BackupPath = $backupPath
        BackupSha256 = $backupHash
        InstalledSha256 = $deviceHash
        WorkerPid = [int]$newPid
        WorkerRunning = $true
        ProtectedConfigDigestUnchanged = $true
        ForceStopUsed = $false
    } | ConvertTo-Json -Depth 5
} catch {
    $failure = $_
    foreach ($workerProcessId in @(Get-WorkerProcessIds)) {
        Invoke-Root -Command "kill -KILL $workerProcessId 2>/dev/null || true" -AllowFailure | Out-Null
    }
    Invoke-Root -Command "rm -f $stateDir/worker.pid" -AllowFailure | Out-Null
    if ($previousInstalled) {
        Invoke-Root -Command "/data/adb/magisk/busybox tar -xzf $backup -C / data/adb/service.d/96-wechat-process-reclaimer.sh; chmod 0755 $remoteScript; nohup $remoteScript >/dev/null 2>&1 &" -AllowFailure | Out-Null
    } else {
        Invoke-Root -Command "rm -f $remoteScript" -AllowFailure | Out-Null
    }
    throw $failure
} finally {
    Invoke-Root -Command "rm -f $remoteStage" -AllowFailure | Out-Null
}
