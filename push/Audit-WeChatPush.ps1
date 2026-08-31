[CmdletBinding()]
param(
    [string]$Serial,
    [string]$AdbPath = 'adb',
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$wechatPackage = 'com.tencent.mm'
$gmsPackage = 'com.google.android.gms'
$thanoxPackage = 'github.tornaco.android.thanos'
$bridgePackage = 'com.codex.wechatfcmtokenbridge'
$rootReclaimerScript = '/data/adb/service.d/96-wechat-process-reclaimer.sh'
$rootReclaimerState = '/data/adb/wechat-process-reclaimer'

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

function Get-PackageVersion {
    param([Parameter(Mandatory)][string]$Package)
    $dump = Invoke-Device -Arguments @('dumpsys', 'package', $Package)
    $versionCode = -1L
    $versionName = $null
    foreach ($line in $dump) {
        if ($versionCode -lt 0 -and $line -match 'versionCode=(\d+)') { $versionCode = [int64]$Matches[1] }
        if (-not $versionName -and $line -match '^\s*versionName=(.+)$') { $versionName = $Matches[1].Trim() }
    }
    [pscustomobject]@{ VersionCode = $versionCode; VersionName = $versionName; Dump = $dump }
}

function Test-RootExpression {
    param([Parameter(Mandatory)][string]$Expression)
    return ((Invoke-Root -Command "if $Expression; then echo true; else echo false; fi" -AllowFailure | Select-Object -Last 1) -eq 'true')
}

$rootId = (Invoke-Root -Command 'id' | Select-Object -First 1)
if ($rootId -notmatch 'uid=0') { throw 'Root shell is unavailable.' }

$wechat = Get-PackageVersion -Package $wechatPackage
$gms = Get-PackageVersion -Package $gmsPackage
$thanox = Get-PackageVersion -Package $thanoxPackage
$bridge = Get-PackageVersion -Package $bridgePackage
$wechatDumpText = $wechat.Dump -join "`n"
$userLine = $wechat.Dump | Where-Object { $_ -match '^\s*User 0:' } | Select-Object -First 1
$stopped = $null
if ($userLine -match 'stopped=(true|false)') { $stopped = [bool]::Parse($Matches[1]) }
$notificationGranted = $wechatDumpText -match 'android\.permission\.POST_NOTIFICATIONS:\s+granted=true'

$disabledComponents = @()
$inDisabled = $false
foreach ($line in $wechat.Dump) {
    if ($line -match '^\s*disabledComponents:') { $inDisabled = $true; continue }
    if ($inDisabled -and $line -match '^\s*enabledComponents:') { break }
    if ($inDisabled -and $line.Trim()) { $disabledComponents += $line.Trim() }
}

$firebasePrefs = '/data/user/0/com.tencent.mm/shared_prefs/com.google.android.gms.appid.xml'
$firebaseMessagingPrefs = '/data/user/0/com.tencent.mm/shared_prefs/com.google.firebase.messaging.xml'
$registrationFile = Test-RootExpression "[ -s $firebasePrefs ]"
$registrationEntry = Test-RootExpression ("grep -q 'name=`"|T|' $firebasePrefs 2>/dev/null")
$autoInitCommand = @"
if grep -Eq 'name="(auto_init|firebase_messaging_auto_init_enabled)"[^>]*(value="true"|>true<)' $firebaseMessagingPrefs $firebasePrefs 2>/dev/null; then
  echo ExplicitTrue
elif grep -Eq 'name="(auto_init|firebase_messaging_auto_init_enabled)"[^>]*(value="false"|>false<)' $firebaseMessagingPrefs $firebasePrefs 2>/dev/null; then
  echo ExplicitFalse
else
  echo DefaultOrManifest
fi
"@
$autoInit = (Invoke-Root -Command $autoInitCommand -AllowFailure | Select-Object -Last 1)

$thanoxRoot = (Invoke-Root -Command "find /data/system -maxdepth 1 -type d -name 'thanos_*' 2>/dev/null | head -n 1" | Select-Object -First 1)
if (-not $thanoxRoot) { throw 'Thanox data root was not found.' }
$thanoxData = "$thanoxRoot/data/u/0"

function Test-ThanoxListMembership {
    param([Parameter(Mandatory)][string]$FileName)
    return Test-RootExpression "grep -q '<string>com.tencent.mm</string>' $thanoxData/$FileName 2>/dev/null"
}

$thanoxXmlText = (Invoke-Root -Command "cat $thanoxData/thanos.xml" | Out-String)
[xml]$thanoxXml = $thanoxXmlText
function Get-ThanoxSetting {
    param([Parameter(Mandatory)][string]$Name)
    $node = @($thanoxXml.settings.setting) | Where-Object { $_.name -eq $Name } | Select-Object -First 1
    if (-not $node) { return $null }
    return [bool]::Parse([string]$node.value)
}

$delegateEnabled = Get-ThanoxSetting 'plugin.push.message.delegate.server.channel_enabled_com.tencent.mm'
$showContent = Get-ThanoxSetting 'plugin.push.message.delegate.server.channel_show_content_enabled_com.tencent.mm'
$startApp = Get-ThanoxSetting 'plugin.push.message.delegate.server.channel_start_app_on_push_enabled_com.tencent.mm'
$skipIfRunning = Get-ThanoxSetting 'plugin.push.message.delegate.server.channel_skip_if_running_enabled_com.tencent.mm'
$smartStandbyGlobal = Get-ThanoxSetting 'PREF_SMART_STANDBY_V2_ENABLED'
$startBlocked = Test-ThanoxListMembership 'start_blocking_pkgs.xml'
$backgroundRestricted = Test-ThanoxListMembership 'bg_restrict_pkgs.xml'
$smartStandby = Test-ThanoxListMembership 'smart_stand_by_pkgs.xml'

$wechatProcessNames = @(Invoke-Device -Arguments @('ps', '-A', '-o', 'NAME') -AllowFailure |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -match '^com\.tencent\.mm(?::[^\s]+)?$' })
$standby = ((Invoke-Device -Arguments @('am', 'get-standby-bucket', $wechatPackage) -AllowFailure) -join '').Trim()
$idleWhitelist = Test-RootExpression "dumpsys deviceidle whitelist 2>/dev/null | grep -q 'com.google.android.gms'"
$socketCountText = (Invoke-Root -Command "ss -tnp 2>/dev/null | grep ':5228' | grep -c ESTAB" -AllowFailure | Select-Object -Last 1)
$socketCount = if ($socketCountText -match '^\d+$') { [int]$socketCountText } else { 0 }
$gmsPidText = ((Invoke-Device -Arguments @('pidof', 'com.google.android.gms.persistent') -AllowFailure) -join ' ').Trim()
$guardPid = ((Invoke-Root -Command 'cat /data/adb/fcm-connectivity-guard/health.pid 2>/dev/null' -AllowFailure) -join '').Trim()
$guardRunning = $guardPid -match '^\d+$' -and (Test-RootExpression "[ -d /proc/$guardPid ]")
$serviceList = (Invoke-Device -Arguments @('service', 'list') -AllowFailure) -join "`n"
$profileIo = "$thanoxRoot/profile_user_io"
$transportCountText = Invoke-Root -Command (
    "grep -cE '^epoch_ms=[0-9]+ package=com[.]tencent[.]mm$' " +
    "$profileIo/wechat_fcm_transport.log 2>/dev/null || true") -AllowFailure |
    Select-Object -Last 1
$transportCount = if ($transportCountText -match '^\d+$') {
    [int]$transportCountText
} else { 0 }
$lastTransportLine = Invoke-Root -Command (
    "grep -E '^epoch_ms=[0-9]+ package=com[.]tencent[.]mm$' " +
    "$profileIo/wechat_fcm_transport.log 2>/dev/null | tail -n 1") -AllowFailure |
    Select-Object -Last 1
$lastTransportEpoch = if ($lastTransportLine -match '^epoch_ms=(\d+) ') {
    [int64]$Matches[1]
} else { $null }
$reclaimCountText = Invoke-Root -Command (
    "grep -cE '^epoch_ms=[0-9]+ package=com[.]tencent[.]mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$' " +
    "$profileIo/wechat_fcm_reclaim.log 2>/dev/null || true") -AllowFailure |
    Select-Object -Last 1
$reclaimCount = if ($reclaimCountText -match '^\d+$') {
    [int]$reclaimCountText
} else { 0 }
$lastReclaimLine = Invoke-Root -Command (
    "grep -E '^epoch_ms=[0-9]+ package=com[.]tencent[.]mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$' " +
    "$profileIo/wechat_fcm_reclaim.log 2>/dev/null | tail -n 1") -AllowFailure |
    Select-Object -Last 1
$lastReclaimEpoch = $null
$lastReclaimOutcome = $null
if ($lastReclaimLine -match '^epoch_ms=(\d+) package=com\.tencent\.mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$') {
    $lastReclaimEpoch = [int64]$Matches[1]
    $lastReclaimOutcome = $Matches[2]
}
$postUseReclaimCountText = Invoke-Root -Command (
    "grep -cE '^epoch_ms=[0-9]+ package=com[.]tencent[.]mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$' " +
    "$profileIo/wechat_post_use_reclaim.log 2>/dev/null || true") -AllowFailure |
    Select-Object -Last 1
$postUseReclaimCount = if ($postUseReclaimCountText -match '^\d+$') {
    [int]$postUseReclaimCountText
} else { 0 }
$lastPostUseReclaimLine = Invoke-Root -Command (
    "grep -E '^epoch_ms=[0-9]+ package=com[.]tencent[.]mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$' " +
    "$profileIo/wechat_post_use_reclaim.log 2>/dev/null | tail -n 1") -AllowFailure |
    Select-Object -Last 1
$lastPostUseReclaimEpoch = $null
$lastPostUseReclaimOutcome = $null
if ($lastPostUseReclaimLine -match '^epoch_ms=(\d+) package=com\.tencent\.mm outcome=(attempted|am_kill_attempted|am_kill_ok|am_kill_failed|skipped_active)$') {
    $lastPostUseReclaimEpoch = [int64]$Matches[1]
    $lastPostUseReclaimOutcome = $Matches[2]
}
$rootReclaimerLocalPath = Join-Path $PSScriptRoot 'wechat-process-reclaimer.sh'
$rootReclaimerLocalHash = if (Test-Path -LiteralPath $rootReclaimerLocalPath -PathType Leaf) {
    (Get-FileHash -Algorithm SHA256 -LiteralPath $rootReclaimerLocalPath).Hash.ToLowerInvariant()
} else { $null }
$rootReclaimerInstalledHashText = ((Invoke-Root -Command (
    "sha256sum $rootReclaimerScript 2>/dev/null | cut -d ' ' -f 1") -AllowFailure) -join '').Trim()
$rootReclaimerInstalledHash = if ($rootReclaimerInstalledHashText -match '^[0-9a-f]{64}$') {
    $rootReclaimerInstalledHashText
} else { $null }
$rootReclaimerPid = ((Invoke-Root -Command (
    "cat $rootReclaimerState/worker.pid 2>/dev/null") -AllowFailure) -join '').Trim()
$rootReclaimerProcessCountText = Invoke-Root -Command (
    "ps -A -o PID,ARGS 2>/dev/null | grep -cE '^[[:space:]]*[0-9]+[[:space:]]+sh $rootReclaimerScript`$' || true") `
    -AllowFailure | Select-Object -Last 1
$rootReclaimerProcessCount = if ($rootReclaimerProcessCountText -match '^\d+$') {
    [int]$rootReclaimerProcessCountText
} else { 0 }
$rootReclaimerRunning = $rootReclaimerPid -match '^\d+$' -and
    (Test-RootExpression "[ -d /proc/$rootReclaimerPid ]") -and
    $rootReclaimerProcessCount -eq 1
$rootReclaimerEventCountText = Invoke-Root -Command (
    "grep -cE '^epoch_ms=[0-9]{13} source=(fcm|post_use|smoke) request_epoch_ms=[0-9]{13} outcome=(zero|remaining|command_failed|stopped_violation|skipped_race_foreground)`$' " +
    "$rootReclaimerState/reclaim.log 2>/dev/null || true") -AllowFailure |
    Select-Object -Last 1
$rootReclaimerEventCount = if ($rootReclaimerEventCountText -match '^\d+$') {
    [int]$rootReclaimerEventCountText
} else { 0 }
$lastRootReclaimerLine = Invoke-Root -Command (
    "grep -E '^epoch_ms=[0-9]{13} source=(fcm|post_use|smoke) request_epoch_ms=[0-9]{13} outcome=(zero|remaining|command_failed|stopped_violation|skipped_race_foreground)`$' " +
    "$rootReclaimerState/reclaim.log 2>/dev/null | tail -n 1") -AllowFailure |
    Select-Object -Last 1
$lastRootReclaimerEpoch = $null
$lastRootReclaimerSource = $null
$lastRootReclaimerRequestEpoch = $null
$lastRootReclaimerOutcome = $null
if ($lastRootReclaimerLine -match '^epoch_ms=(\d{13}) source=(fcm|post_use|smoke) request_epoch_ms=(\d{13}) outcome=(zero|remaining|command_failed|stopped_violation|skipped_race_foreground)$') {
    $lastRootReclaimerEpoch = [int64]$Matches[1]
    $lastRootReclaimerSource = $Matches[2]
    $lastRootReclaimerRequestEpoch = [int64]$Matches[3]
    $lastRootReclaimerOutcome = $Matches[4]
}
$rebindMarkerPresent = Test-RootExpression (
    '[ -f /data/local/tmp/wechat-fcm-token-bridge/rebind.once ]')

$result = [ordered]@{
    CollectedAt = (Get-Date).ToString('o')
    Serial = $Serial
    Device = [ordered]@{
        Product = ((Invoke-Device -Arguments @('getprop', 'ro.product.device')) -join '').Trim()
        Model = ((Invoke-Device -Arguments @('getprop', 'ro.product.model')) -join '').Trim()
        BuildFingerprint = ((Invoke-Device -Arguments @('getprop', 'ro.build.fingerprint')) -join '').Trim()
        Root = $true
    }
    WeChat = [ordered]@{
        Package = $wechatPackage
        VersionCode = $wechat.VersionCode
        VersionName = $wechat.VersionName
        Stopped = $stopped
        Running = ($wechatProcessNames.Count -gt 0)
        ProcessCount = $wechatProcessNames.Count
        StandbyBucket = $standby
        NotificationPermissionGranted = $notificationGranted
        FirebaseReceiverPresent = ($wechatDumpText -match 'com\.google\.firebase\.iid\.FirebaseInstanceIdReceiver')
        FirebaseServicePresent = ($wechatDumpText -match 'WCFirebaseMessagingService')
        FirebaseComponentsDisabled = [bool]($disabledComponents | Where-Object { $_ -match 'Firebase|WCFirebase' })
        FcmRegistrationFilePresent = $registrationFile
        FcmRegistrationEntryPresent = $registrationEntry
        FcmAutoInit = $autoInit
    }
    GmsTransport = [ordered]@{
        VersionCode = $gms.VersionCode
        VersionName = $gms.VersionName
        PersistentPidPresent = [bool]($gmsPidText -match '\d')
        EstablishedMtalkSocketCount = $socketCount
        IdleWhitelisted = $idleWhitelist
        ConnectivityGuardRunning = $guardRunning
    }
    Thanox = [ordered]@{
        VersionCode = $thanox.VersionCode
        VersionName = $thanox.VersionName
        BinderServicePresent = ($serviceList -match 'github\.tornaco\.android\.thanos\.core\.IThanos')
        DelegateEnabled = $delegateEnabled
        ShowContent = $showContent
        StartAppOnPush = $startApp
        SkipIfRunningPersisted = $skipIfRunning
        StartBlocked = $startBlocked
        BackgroundRestricted = $backgroundRestricted
        SmartStandby = $smartStandby
        SmartStandbyGlobal = $smartStandbyGlobal
        ActiveHandlingLayer = if ($delegateEnabled) {
            'ThanoxDelegate'
        } elseif ($startBlocked) { 'NativeFcmGuarded' } else { 'NativeFcm' }
    }
    FcmRepair = [ordered]@{
        BridgeInstalled = ($bridge.VersionCode -gt 0)
        BridgeVersionCode = $bridge.VersionCode
        RebindControlMarkerPresent = $rebindMarkerPresent
        TransportTelemetryEventCount = $transportCount
        LastTransportEpochMs = $lastTransportEpoch
        ReclamationEventCount = $reclaimCount
        LastReclamationEpochMs = $lastReclaimEpoch
        LastReclamationOutcome = $lastReclaimOutcome
        PostUseReclamationEventCount = $postUseReclaimCount
        LastPostUseReclamationEpochMs = $lastPostUseReclaimEpoch
        LastPostUseReclamationOutcome = $lastPostUseReclaimOutcome
    }
    RootReclaimer = [ordered]@{
        Target = $rootReclaimerScript
        Installed = [bool]$rootReclaimerInstalledHash
        InstalledSha256 = $rootReclaimerInstalledHash
        LocalSha256 = $rootReclaimerLocalHash
        HashMatchesLocal = [bool]($rootReclaimerInstalledHash -and
            $rootReclaimerInstalledHash -eq $rootReclaimerLocalHash)
        WorkerPid = if ($rootReclaimerPid -match '^\d+$') { [int]$rootReclaimerPid } else { $null }
        WorkerRunning = $rootReclaimerRunning
        ProcessCount = $rootReclaimerProcessCount
        EventCount = $rootReclaimerEventCount
        LastEventEpochMs = $lastRootReclaimerEpoch
        LastRequestEpochMs = $lastRootReclaimerRequestEpoch
        LastSource = $lastRootReclaimerSource
        LastOutcome = $lastRootReclaimerOutcome
        Action = 'am kill com.tencent.mm'
        ForceStopUsed = $false
    }
    Privacy = [ordered]@{
        TokenPrinted = $false
        ContactOrMessageDataRead = $false
        NotificationContentsRead = $false
    }
}

$json = $result | ConvertTo-Json -Depth 8
if ($OutputPath) {
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutputPath))
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Set-Content -LiteralPath $OutputPath -Value $json -Encoding utf8NoBOM
}
$json
