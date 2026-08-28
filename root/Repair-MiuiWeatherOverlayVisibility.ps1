[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$Serial,

    [string]$AdbPath = 'adb',

    [string]$BackupRoot = (Join-Path $PSScriptRoot '..\work\weather-overlay'),

    [switch]$Apply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$package = 'com.miui.weather2'
$expectedVersionCode = '13500601'
$miuiCoreModule = '/data/adb/modules/MiuiCore'
$requiredOverlayFiles = @(
    '/system/app/miuisystem/miuisystem.apk',
    '/system/framework/miui-framework.jar'
)

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

    $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Command))
    return Invoke-Adb -Arguments @('-s', $Serial, 'shell', "echo $encodedCommand | base64 -d | su -c sh") -AllowFailure:$AllowFailure
}

function Get-Denylist {
    return @(Invoke-Root -Command 'magisk --denylist ls')
}

function Get-WeatherDenyEntries {
    param([string[]]$Denylist)
    return @($Denylist | Where-Object { $_ -like "$package|*" })
}

function Get-PackageVersionCode {
    $packageDump = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'dumpsys', 'package', $package)
    $versionLine = $packageDump | Where-Object { $_ -match 'versionCode=(\d+)' } | Select-Object -First 1
    if (-not $versionLine) {
        throw "$package is not installed for the active Android user."
    }
    return [regex]::Match($versionLine, 'versionCode=(\d+)').Groups[1].Value
}

function Assert-Prerequisites {
    $state = (Invoke-Adb -Arguments @('-s', $Serial, 'get-state') | Select-Object -First 1).Trim()
    if ($state -ne 'device') {
        throw "Device '$Serial' is not available through ADB."
    }

    $uid = (Invoke-Root -Command 'id -u' | Select-Object -First 1).Trim()
    if ($uid -ne '0') {
        throw 'Root shell is unavailable.'
    }

    $versionCode = Get-PackageVersionCode
    if ($versionCode -ne $expectedVersionCode) {
        throw "Weather versionCode is $versionCode; reviewed versionCode is $expectedVersionCode. Re-audit before applying."
    }

    $moduleState = (Invoke-Root -Command "if [ -d $miuiCoreModule ] && [ ! -e $miuiCoreModule/disable ]; then echo enabled; else echo unavailable; fi" | Select-Object -First 1).Trim()
    if ($moduleState -ne 'enabled') {
        throw 'The MiuiCore Magisk module is absent or disabled.'
    }

    foreach ($path in $requiredOverlayFiles) {
        $visibility = (Invoke-Root -Command "if [ -r $path ]; then echo readable; else echo missing; fi" | Select-Object -First 1).Trim()
        if ($visibility -ne 'readable') {
            throw "Required MiuiCore overlay is unavailable in the root mount namespace: $path"
        }
    }

    return $versionCode
}

function Restore-DenyEntries {
    param([string[]]$Entries)

    foreach ($entry in $Entries) {
        $parts = $entry -split '\|', 2
        if ($parts.Count -ne 2 -or $parts[0] -ne $package -or $parts[1] -notmatch '^[A-Za-z0-9._:]+$') {
            throw "Refusing to restore malformed denylist entry: $entry"
        }
        Invoke-Root -Command "magisk --denylist add $($parts[0]) $($parts[1])" | Out-Null
    }
}

$versionCode = Assert-Prerequisites
$denyBefore = Get-Denylist
$weatherDenyBefore = @(Get-WeatherDenyEntries -Denylist $denyBefore)

$audit = [ordered]@{
    Serial                   = $Serial
    Package                  = $package
    VersionCode              = $versionCode
    MiuiCoreEnabled          = $true
    RootOverlayFilesReadable = $true
    WeatherDenyEntries       = @($weatherDenyBefore)
    Compatible               = ($weatherDenyBefore.Count -eq 0)
    Applied                  = $false
}

if (-not $Apply) {
    [pscustomobject]$audit | ConvertTo-Json -Depth 4
    return
}

$backupDirectory = New-Item -ItemType Directory -Path $BackupRoot -Force
$backupPath = Join-Path $backupDirectory.FullName ("denylist-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))
[pscustomobject]@{
    CreatedAtUtc       = (Get-Date).ToUniversalTime().ToString('o')
    Serial             = $Serial
    Package            = $package
    VersionCode        = $versionCode
    WeatherDenyEntries = @($weatherDenyBefore)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $backupPath -Encoding UTF8

try {
    foreach ($entry in $weatherDenyBefore) {
        $parts = $entry -split '\|', 2
        if ($parts.Count -ne 2 -or $parts[0] -ne $package -or $parts[1] -notmatch '^[A-Za-z0-9._:]+$') {
            throw "Refusing to remove malformed denylist entry: $entry"
        }
        Invoke-Root -Command "magisk --denylist rm $($parts[0]) $($parts[1])" | Out-Null
    }

    $weatherDenyAfter = @(Get-WeatherDenyEntries -Denylist (Get-Denylist))
    if ($weatherDenyAfter.Count -ne 0) {
        throw "Weather still has denylist entries: $($weatherDenyAfter -join ', ')"
    }

    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $package) | Out-Null
    $startOutput = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'start', '-W', '-n', "$package/.ActivityWeatherMain")
    Start-Sleep -Seconds 8

    $processIdLine = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'pidof', $package) -AllowFailure | Select-Object -First 1
    $weatherProcessId = if ($processIdLine) { $processIdLine.Trim() } else { '' }
    if (-not $weatherProcessId -or $weatherProcessId -notmatch '^\d+$') {
        throw 'Weather process did not remain alive after launch.'
    }

    $processLog = Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'logcat', '--pid', $weatherProcessId, '-d', '-t', '600') -AllowFailure
    $fatalLines = @($processLog | Where-Object {
        $_ -match 'FATAL EXCEPTION|NoClassDefFoundError.*miui\.os\.Build|ClassNotFoundException.*miui\.os\.Build'
    })
    if ($fatalLines.Count -ne 0) {
        throw 'Weather still reports a fatal MIUI framework class-loading error.'
    }

    $audit.Compatible = $true
    $audit.Applied = $true
    $audit.BackupPath = $backupPath
    $audit.ProcessId = [int]$weatherProcessId
    $audit.ColdStartStatus = @($startOutput | Where-Object { $_ -match '^Status:|^TotalTime:|^WaitTime:' })
    [pscustomobject]$audit | ConvertTo-Json -Depth 4
} catch {
    $repairError = $_
    $restoreSummary = 'No original Weather denylist entries required restoration.'
    $currentWeatherEntries = @(Get-WeatherDenyEntries -Denylist (Get-Denylist))
    $missingOriginalEntries = @($weatherDenyBefore | Where-Object { $currentWeatherEntries -notcontains $_ })
    if ($missingOriginalEntries.Count -ne 0) {
        Restore-DenyEntries -Entries $missingOriginalEntries
        $restoreSummary = 'Original Weather denylist entries were restored.'
    }
    Invoke-Adb -Arguments @('-s', $Serial, 'shell', 'am', 'force-stop', $package) -AllowFailure | Out-Null
    throw "Repair validation failed. $restoreSummary $($repairError.Exception.Message)"
}
