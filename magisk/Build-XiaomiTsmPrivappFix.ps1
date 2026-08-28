[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TsmApk,
    [Parameter(Mandatory)][string]$OutputZip,
    [string]$ExpectedSha256 = 'c48ba0c5686e879c49416f0be3d18ae840e2f255f406345eab26e95bbe785e5c'
)

$ErrorActionPreference = 'Stop'
$sourceApk = (Resolve-Path -LiteralPath $TsmApk).Path
$actualHash = (Get-FileHash -LiteralPath $sourceApk -Algorithm SHA256).Hash.ToLowerInvariant()
if ($actualHash -ne $ExpectedSha256.ToLowerInvariant()) {
    throw "TSM APK SHA-256 mismatch: expected $ExpectedSha256, got $actualHash"
}

$template = Join-Path $PSScriptRoot 'xiaomi-tsm-privapp-fix'
$output = [IO.Path]::GetFullPath($OutputZip)
$stage = Join-Path ([IO.Path]::GetTempPath()) ("xiaomi-tsm-privapp-fix-" + [guid]::NewGuid().ToString('N'))
try {
    New-Item -ItemType Directory -Path $stage | Out-Null
    Copy-Item -LiteralPath (Join-Path $template 'module.prop') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $template 'sepolicy.rule') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $template 'post-fs-data.sh') -Destination $stage
    Copy-Item -LiteralPath (Join-Path $template 'customize.sh') -Destination $stage
    $apkDir = Join-Path $stage 'system\system_ext\priv-app\MiuiTsmClient'
    $permissionDir = Join-Path $stage 'system\system_ext\etc\permissions'
    New-Item -ItemType Directory -Path $apkDir,$permissionDir | Out-Null
    Copy-Item -LiteralPath $sourceApk -Destination (Join-Path $apkDir 'MiuiTsmClient.apk')
    Copy-Item -LiteralPath (Join-Path $template 'privapp-permissions-com.miui.tsmclient.xml') -Destination $permissionDir
    New-Item -ItemType Directory -Path ([IO.Path]::GetDirectoryName($output)) -Force | Out-Null
    if (Test-Path -LiteralPath $output) { Remove-Item -LiteralPath $output -Force }
    Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $output -CompressionLevel Optimal
} finally {
    if ($stage.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stage)) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}

$zipHash = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
[pscustomobject]@{ Output = $output; TsmApkSha256 = $actualHash; ZipSha256 = $zipHash }
