[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$XmsfApk,
    [Parameter(Mandatory)][string]$OutputZip,
    [string]$ExpectedSha256 = '089b8c70b6e9d60a5eb0aef282bf943e570f1cd877834fd6babfdd6ac9787733'
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'New-DeterministicZip.ps1')
$sourceApk = (Resolve-Path -LiteralPath $XmsfApk).Path
$actualHash = (Get-FileHash -LiteralPath $sourceApk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "XMSF APK SHA-256 mismatch: expected $ExpectedSha256, got $actualHash"
}

$template = Join-Path $PSScriptRoot 'xmsf-systemizer'
$output = [IO.Path]::GetFullPath($OutputZip)
$stage = Join-Path ([IO.Path]::GetTempPath()) ("xmsf-systemizer-" + [guid]::NewGuid().ToString('N'))
try {
    Copy-Item -LiteralPath $template -Destination $stage -Recurse
    $apkDir = Join-Path $stage 'system\priv-app\Xmsf'
    New-Item -ItemType Directory -Path $apkDir -Force | Out-Null
    Copy-Item -LiteralPath $sourceApk -Destination (Join-Path $apkDir 'Xmsf.apk')
    New-DeterministicZip -SourceDirectory $stage -OutputZip $output
} finally {
    if ($stage.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stage)) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}

$zipHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{ Output = $output; XmsfApkSha256 = $actualHash; ZipSha256 = $zipHash }
