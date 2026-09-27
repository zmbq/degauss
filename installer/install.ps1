# Retro Looks for Windows Terminal: installs the fonts (current user only, no admin needed)
# and adds the retro color schemes and profiles to Windows Terminal.
#
#   Install:    irm https://github.com/zmbq/vscode-retro/releases/latest/download/install.ps1 | iex
#   Uninstall:  & ([scriptblock]::Create((irm https://github.com/zmbq/vscode-retro/releases/latest/download/install.ps1))) -Uninstall
#
# Run from an unzipped release (retro-looks-terminal.zip) it installs from the files next to it;
# otherwise it downloads the release zip and verifies its SHA-256 checksum first.
# Works on Windows PowerShell 5.1 and PowerShell 7.
param(
    [switch]$Uninstall,
    [string]$Version = 'latest'
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$Repo = 'zmbq/vscode-retro'
$FontFilePrefix = 'RetroLooks-'   # shared with tools/build.mjs and the VS Code extension
$FontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$FontKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$FragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\Retro Looks'

function Uninstall-RetroLooks {
    if (Test-Path $FontKey) {
        $props = (Get-ItemProperty $FontKey).PSObject.Properties |
            Where-Object { $_.Value -is [string] -and (Split-Path $_.Value -Leaf) -like "$FontFilePrefix*" }
        foreach ($prop in $props) {
            Remove-ItemProperty -Path $FontKey -Name $prop.Name
            try {
                Remove-Item $prop.Value -Force -ErrorAction Stop
                Write-Host "Removed font: $($prop.Name)"
            } catch {
                Write-Warning "Font file is in use and will stay until you remove it after a restart: $($prop.Value)"
            }
        }
    }
    if (Test-Path $FragmentDir) { Remove-Item $FragmentDir -Recurse -Force }
    Write-Host 'Retro Looks removed. Restart Windows Terminal.'
}

function Get-ReleasePayload {
    $base = if ($Version -eq 'latest') {
        "https://github.com/$Repo/releases/latest/download"
    } else {
        "https://github.com/$Repo/releases/download/$Version"
    }
    $temp = Join-Path ([IO.Path]::GetTempPath()) ("retro-looks-" + [guid]::NewGuid())
    New-Item -ItemType Directory $temp | Out-Null
    $zip = Join-Path $temp 'retro-looks-terminal.zip'

    Write-Host "Downloading Retro Looks ($Version)..."
    Invoke-WebRequest "$base/retro-looks-terminal.zip" -OutFile $zip -UseBasicParsing
    $expected = ((Invoke-WebRequest "$base/retro-looks-terminal.zip.sha256" -UseBasicParsing).Content -split '\s+')[0]
    $actual = (Get-FileHash $zip -Algorithm SHA256).Hash
    if ($actual -ne $expected.ToUpper()) { throw "Checksum mismatch for retro-looks-terminal.zip (expected $expected, got $actual)." }

    $dir = Join-Path $temp 'payload'
    Expand-Archive $zip -DestinationPath $dir
    return $dir
}

function Install-RetroLooks([string]$Source) {
    New-Item -ItemType Directory -Force $FontDir, $FragmentDir | Out-Null
    if (-not (Test-Path $FontKey)) { New-Item $FontKey -Force | Out-Null }

    foreach ($meta in Get-ChildItem (Join-Path $Source 'fonts') -Recurse -Filter 'font.json') {
        $font = Get-Content $meta.FullName -Raw | ConvertFrom-Json
        $src = Join-Path $meta.DirectoryName $font.file
        $dest = Join-Path $FontDir ($FontFilePrefix + $font.file)
        # Installed fonts may be locked by running apps; identical files don't need copying.
        if (-not ((Test-Path $dest) -and (Get-Item $dest).Length -eq (Get-Item $src).Length)) {
            Copy-Item $src $dest -Force
        }
        Set-ItemProperty -Path $FontKey -Name "$($font.family) (TrueType)" -Value $dest
        Write-Host "Installed font: $($font.family)"
    }

    $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe -NoLogo' } else { 'powershell.exe -NoLogo' }
    $fragment = Get-Content (Join-Path $Source 'retro-looks.json') -Raw | ConvertFrom-Json
    foreach ($terminalProfile in $fragment.profiles) {
        $terminalProfile | Add-Member -NotePropertyName commandline -NotePropertyValue $shell -Force
    }
    $json = $fragment | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $FragmentDir 'retro-looks.json'), $json, (New-Object Text.UTF8Encoding $false))

    Write-Host ''
    Write-Host 'Retro Looks installed. Close all Windows Terminal windows and reopen it;'
    Write-Host 'the new profiles are in the drop-down next to the + tab button.'
}

if ($Uninstall) {
    Uninstall-RetroLooks
    return
}

$here = $PSScriptRoot
if ($here -and (Test-Path (Join-Path $here 'retro-looks.json'))) {
    Install-RetroLooks $here
} else {
    Install-RetroLooks (Get-ReleasePayload)
}
