[CmdletBinding()]
param(
    [string]$Serial,
    [string]$AdbPath = 'adb',
    [string]$HelperPath = (Join-Path $PSScriptRoot 'work\thanox-wechat-fcm-telemetry-cli.jar'),
    [string]$DeviceBackupRoot = '/data/adb/wechat-backups',
    [switch]$EnableReclamation,
    [switch]$EnablePostUseReclamation,
    [switch]$UpgradeReclaimers,
    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedThanoxVersionCode = 3354368L
$remoteHelper = '/data/local/tmp/thanox-wechat-fcm-telemetry-cli.jar'
$mainClass = 'com.codex.wechatpush.ThanoxWechatFcmTelemetryCli'

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

function Invoke-Device {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    return Invoke-Adb -Arguments (@('-s', $Serial, 'shell') + $Arguments) `
        -AllowFailure:$AllowFailure
}

function Invoke-Root {
    param([Parameter(Mandatory)][string]$Command, [switch]$AllowFailure)
    $quoted = "'" + $Command.Replace("'", "'`"'`"'") + "'"
    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'su', '-c', $quoted) `
        -AllowFailure:$AllowFailure
}

function Get-VersionCode {
    $line = Invoke-Device -Arguments @('dumpsys', 'package', 'github.tornaco.android.thanos') |
        Where-Object { $_ -match 'versionCode=(\d+)' } | Select-Object -First 1
    if (-not $line -or $line -notmatch 'versionCode=(\d+)') { return -1L }
    return [int64]$Matches[1]
}

function Convert-State {
    param([Parameter(Mandatory)][string[]]$Lines)
    $state = [ordered]@{}
    foreach ($line in $Lines) {
        if ($line -match '^([A-Za-z]+)=(true|false|-?\d+)$') {
            $key = $Matches[1]
            $value = $Matches[2]
            if ($value -match '^(true|false)$') {
                $state[$key] = [bool]::Parse($value)
            } else {
                $state[$key] = [int]$value
            }
        }
    }
    foreach ($key in @('profileEnabled','pushEnabled','ruleExists','ruleEnabled',
            'reclaimRuleExists','reclaimRuleEnabled',
            'reclaimUsesAmKill','reclaimUsesUnprivilegedSh','reclaimDelayMs',
            'postUseReclaimRuleExists','postUseReclaimRuleEnabled',
            'postUseReclaimUsesAmKill','postUseReclaimUsesUnprivilegedSh',
            'postUseReclaimDelayMs',
            'shellSuSupportInstalled','enabledRuleCount')) {
        if (-not $state.Contains($key)) { throw "Telemetry helper did not return '$key'." }
    }
    return [pscustomobject]$state
}

function Invoke-Helper {
    param([Parameter(Mandatory)][string[]]$Arguments, [switch]$AllowFailure)
    $command = "CLASSPATH=$remoteHelper app_process /system/bin $mainClass $($Arguments -join ' ')"
    $lines = Invoke-Root -Command $command -AllowFailure:$AllowFailure
    if ($lines | Where-Object { $_ -match '^ERROR=' }) {
        if ($AllowFailure) { return $null }
        throw "Telemetry helper failed: $($lines -join ' ')"
    }
    return Convert-State -Lines $lines
}

function New-PhoneBackup {
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $archive = "$DeviceBackupRoot/thanox-wechat-fcm-telemetry-$stamp.tar.gz"
    $command = @"
set -eu
root=`$(find /data/system -maxdepth 1 -type d -name 'thanos_*' | head -n 1)
test -n "`$root"
mkdir -p $DeviceBackupRoot
chmod 0700 $DeviceBackupRoot
/data/adb/magisk/busybox tar -czf $archive \
  "`$root/data/u/0/rules/db/rule.db" \
  "`$root/data/u/0/rules/db/rule.db-wal" \
  "`$root/data/u/0/rules/db/rule.db-shm" \
  "`$root/data/u/0/thanos.xml" 2>/dev/null
chmod 0600 $archive
sha256sum $archive
"@
    $line = Invoke-Root -Command $command | Where-Object {
        $_ -match '^([0-9a-f]{64})\s+(.+)$'
    } | Select-Object -Last 1
    if (-not $line -or $line -notmatch '^([0-9a-f]{64})\s+(.+)$') {
        throw 'Thanox phone-local backup did not produce a SHA-256 digest.'
    }
    return [pscustomobject]@{ Path = $Matches[2]; Sha256 = $Matches[1] }
}

if ((Get-VersionCode) -ne $expectedThanoxVersionCode) {
    throw "Thanox version does not match reviewed lock $expectedThanoxVersionCode."
}
$selectedReclaimerOperations = @(@(
        [bool]$EnableReclamation
        [bool]$EnablePostUseReclamation
        [bool]$UpgradeReclaimers
    ) | Where-Object { $_ })
if ($selectedReclaimerOperations.Count -gt 1) {
    throw 'Select only one reclaimer operation per invocation.'
}
if (-not (Test-Path -LiteralPath $HelperPath -PathType Leaf)) {
    throw "Telemetry helper is missing: $HelperPath"
}

try {
    Invoke-Adb -Arguments @('-s', $Serial, 'push', $HelperPath, $remoteHelper) | Out-Null
    Invoke-Root -Command "chmod 0600 $remoteHelper" | Out-Null
    $before = Invoke-Helper -Arguments @('audit')
    [ordered]@{
        Mode = if ($UpgradeReclaimers) {
            'ThanoxWechatAmKillReclaimerUpgrade'
        } elseif ($EnablePostUseReclamation) {
            'ThanoxWechatPostUseReclamation'
        } elseif ($EnableReclamation) {
            'ThanoxWechatFcmTelemetryAndReclamation'
        } else { 'ThanoxWechatFcmTelemetry' }
        Apply = [bool]$Apply
        StateBefore = $before
        ProposedRule = 'Codex WeChat FCM Transport Telemetry'
        OutputFields = @('epoch_ms', 'package=com.tencent.mm')
        ProposedReclamationRule = if ($EnableReclamation) {
            'Codex WeChat FCM Nonstop Reclaimer'
        } else { $null }
        ReclamationDelayMs = if ($EnableReclamation) { 30000 } else { $null }
        ReclamationGuard = if ($EnableReclamation) {
            'WeChat not foreground and no WeChat audio focus'
        } else { $null }
        ProposedPostUseReclamationRule = if ($EnablePostUseReclamation) {
            'Codex WeChat Post-Use Nonstop Reclaimer'
        } else { $null }
        PostUseReclamationDelayMs = if ($EnablePostUseReclamation) { 30000 } else { $null }
        PostUseReclamationTrigger = if ($EnablePostUseReclamation) {
            'WeChat leaves the foreground; action rechecks foreground and audio focus'
        } else { $null }
        UpgradeReclaimersToAmKill = [bool]$UpgradeReclaimers
        TargetReclamationDelayMs = if ($UpgradeReclaimers) { 30000 } else { $null }
        UpgradedAction = if ($UpgradeReclaimers) {
            '30-second guarded su.exe("am kill com.tencent.mm") request with exit-code-only logging'
        } else { $null }
        ForceStopUsed = $false
        MessageOrTokenDataRecorded = $false
    } | ConvertTo-Json -Depth 6
    if (-not $Apply) { return }

    if (-not $before.profileEnabled -and $before.enabledRuleCount -ne 0) {
        throw 'Refusing to enable Thanox Profile Mode because other enabled rules exist.'
    }
    $backup = New-PhoneBackup
    try {
        $after = Invoke-Helper -Arguments @(
            $(if ($UpgradeReclaimers) {
                'upgrade-reclaimers'
            } elseif ($EnablePostUseReclamation) {
                'apply-post-use-reclaim'
            } elseif ($EnableReclamation) { 'apply-reclaim' } else { 'apply' }))
        [ordered]@{
            Applied = $true
            Backup = $backup
            StateAfter = $after
            DirectDatabaseWriteUsed = $false
            BinderApiUsed = $true
            PrivacySafe = $true
        } | ConvertTo-Json -Depth 6
    } catch {
        if (-not $UpgradeReclaimers) {
            Invoke-Helper -Arguments @(
                $(if ($EnablePostUseReclamation) {
                    'remove-post-use-reclaim'
                } elseif ($EnableReclamation) { 'remove-reclaim' } else { 'remove' }),
                $before.profileEnabled.ToString().ToLowerInvariant(),
                $before.pushEnabled.ToString().ToLowerInvariant()) -AllowFailure | Out-Null
        }
        throw
    }
} finally {
    Invoke-Root -Command "rm -f $remoteHelper" -AllowFailure | Out-Null
}
