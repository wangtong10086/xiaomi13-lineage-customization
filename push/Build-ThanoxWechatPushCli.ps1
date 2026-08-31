[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$JavaPath,
    [Parameter(Mandatory)][string]$JavacPath,
    [Parameter(Mandatory)][string]$JarPath,
    [Parameter(Mandatory)][string]$D8JarPath,
    [Parameter(Mandatory)][string]$AndroidJarPath,
    [string]$OutputPath = (Join-Path $PSScriptRoot 'work\thanox-wechat-push-cli.jar')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($path in @($JavaPath, $JavacPath, $JarPath, $D8JarPath, $AndroidJarPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required build input does not exist: $path"
    }
}

$source = Join-Path $PSScriptRoot 'thanox-helper\ThanoxWechatPushCli.java'
$outputFull = [IO.Path]::GetFullPath($OutputPath)
$outputDir = Split-Path -Parent $outputFull
$stage = Join-Path ([IO.Path]::GetTempPath()) ("thanox-wechat-cli-" + [guid]::NewGuid().ToString('N'))
$classes = Join-Path $stage 'classes'
$dex = Join-Path $stage 'dex'
$classJar = Join-Path $stage 'classes.jar'

try {
    New-Item -ItemType Directory -Path $classes, $dex, $outputDir -Force | Out-Null
    & $JavacPath -encoding UTF-8 -source 8 -target 8 -classpath $AndroidJarPath -d $classes $source
    if ($LASTEXITCODE -ne 0) { throw "javac failed with exit code $LASTEXITCODE." }

    Push-Location $classes
    try {
        & $JarPath --create --file $classJar .
        if ($LASTEXITCODE -ne 0) { throw "class jar failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }

    & $JavaPath -cp $D8JarPath com.android.tools.r8.D8 --min-api 24 --output $dex $classJar
    if ($LASTEXITCODE -ne 0) { throw "D8 failed with exit code $LASTEXITCODE." }

    Push-Location $dex
    try {
        & $JarPath --create --file $outputFull classes.dex
        if ($LASTEXITCODE -ne 0) { throw "jar failed with exit code $LASTEXITCODE." }
    } finally {
        Pop-Location
    }

    Get-FileHash -Algorithm SHA256 -LiteralPath $outputFull | Select-Object Path, Hash
} finally {
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}
