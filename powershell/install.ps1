# Degauss for Windows Terminal: installs the Degauss PowerShell module (for PowerShell 7 and
# Windows PowerShell, current user only) and runs it, which installs the fonts and the Terminal profiles.
#
#   Install:    irm https://github.com/zmbq/degauss/releases/latest/download/install.ps1 | iex
#   Uninstall:  & ([scriptblock]::Create((irm https://github.com/zmbq/degauss/releases/latest/download/install.ps1))) -Uninstall
#
# Run from an unzipped release (degauss-powershell.zip) it installs from the files next to it;
# otherwise it downloads the release zip and verifies its SHA-256 checksum first.
# Works on Windows PowerShell 5.1 and PowerShell 7.
param(
    [switch]$Uninstall,
    # The release tag to install, e.g. powershell-v0.3.0.
    [string]$Version = 'latest',
    # Use the profiles' nominal font sizes instead of the sharpest sizes for this display's scaling.
    [switch]$KeepFontSizes,
    # With -Uninstall: remove the fonts even if the Degauss VS Code extension still uses them.
    [switch]$RemoveFonts,
    # For tests: install the module under this folder instead of the user's module folders,
    # and don't run Install-/Uninstall-Degauss.
    [string]$ModulesRoot,
    [switch]$NoRun
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$Repo = 'zmbq/degauss'

function Get-ModuleRoots {
    if ($ModulesRoot) { return @($ModulesRoot) }
    $documents = [Environment]::GetFolderPath('MyDocuments')
    return @((Join-Path $documents 'PowerShell\Modules'), (Join-Path $documents 'WindowsPowerShell\Modules'))
}

# Downloads and verifies the release zip; returns the folder it was expanded to.
function Get-ReleasePackage([string]$Temp) {
    $base = if ($Version -eq 'latest') {
        "https://github.com/$Repo/releases/latest/download"
    } else {
        "https://github.com/$Repo/releases/download/$Version"
    }
    $zip = Join-Path $Temp 'degauss-powershell.zip'
    Write-Host "Downloading Degauss ($Version)..."
    Invoke-WebRequest "$base/degauss-powershell.zip" -OutFile $zip -UseBasicParsing
    # Save the checksum to a file: PowerShell 7 returns downloaded .sha256 content as bytes, not text.
    $shaFile = "$zip.sha256"
    Invoke-WebRequest "$base/degauss-powershell.zip.sha256" -OutFile $shaFile -UseBasicParsing
    $expected = ((Get-Content $shaFile -Raw).Trim() -split '\s+')[0]
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($actual -ne $expected.ToUpper()) { throw "Checksum mismatch for degauss-powershell.zip (expected $expected, got $actual)." }
    $dir = Join-Path $Temp 'package'
    Expand-Archive $zip -DestinationPath $dir
    return $dir
}

$temp = $null
$package = $PSScriptRoot
if (-not ($package -and (Test-Path (Join-Path $package 'Degauss\Degauss.psd1')))) {
    $temp = Join-Path ([IO.Path]::GetTempPath()) ('degauss-' + [guid]::NewGuid())
    New-Item -ItemType Directory $temp | Out-Null
}
try {
    if ($temp) { $package = Get-ReleasePackage $temp }
    $source = Join-Path $package 'Degauss'
    $moduleVersion = (Import-PowerShellDataFile (Join-Path $source 'Degauss.psd1')).ModuleVersion

    if ($Uninstall) {
        if (-not $NoRun) {
            Import-Module (Join-Path $source 'Degauss.psd1') -Force
            Uninstall-Degauss -RemoveFonts:$RemoveFonts
        }
        foreach ($modules in Get-ModuleRoots) {
            $dir = Join-Path $modules 'Degauss'
            if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        }
        Write-Host 'Removed the Degauss PowerShell module.'
        return
    }

    $installed = $null
    foreach ($modules in Get-ModuleRoots) {
        # Replace any older version this installer put there.
        $dir = Join-Path $modules 'Degauss'
        if (Test-Path $dir) { Remove-Item $dir -Recurse -Force }
        $dest = Join-Path $dir $moduleVersion
        New-Item -ItemType Directory -Force $dest | Out-Null
        Copy-Item (Join-Path $source '*') $dest -Recurse -Force
        if (-not $installed) { $installed = $dest }
    }
    Write-Host "Installed the Degauss PowerShell module $moduleVersion."
    if (-not $NoRun) {
        Import-Module (Join-Path $installed 'Degauss.psd1') -Force
        Install-Degauss -KeepFontSizes:$KeepFontSizes
    }
} finally {
    if ($temp) { Remove-Item $temp -Recurse -Force -ErrorAction SilentlyContinue }
}
