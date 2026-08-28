[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$OutputZip
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'New-DeterministicZip.ps1')
$template = Join-Path $PSScriptRoot 'fcm-connectivity-guard'
$output = [IO.Path]::GetFullPath($OutputZip)
$stage = Join-Path ([IO.Path]::GetTempPath()) ("fcm-connectivity-guard-" + [guid]::NewGuid().ToString('N'))
try {
    Copy-Item -LiteralPath $template -Destination $stage -Recurse
    New-DeterministicZip -SourceDirectory $stage -OutputZip $output
} finally {
    if ($stage.StartsWith([IO.Path]::GetTempPath(), [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $stage)) {
        Remove-Item -LiteralPath $stage -Recurse -Force
    }
}

[pscustomobject]@{
    Output = $output
    ZipSha256 = (Get-FileHash -LiteralPath $output -Algorithm SHA256).Hash.ToLowerInvariant()
}
