# RetroLooks: vintage computer looks for Windows Terminal. Installs the fonts (current user only, no admin
# needed) and adds the Retro Looks profiles and color schemes as a Windows Terminal fragment, so the user's
# settings.json is never touched. Works on Windows PowerShell 5.1 and PowerShell 7.

$script:ModuleRoot = $PSScriptRoot

# Where things get installed. Script variables so the tests can point them at a sandbox.
$script:FontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$script:FontKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
# Never rename this folder: Windows Terminal ties users' profile settings to it.
$script:FragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\Retro Looks'
# The Retro Looks VS Code extension uses the same fonts; uninstalling here leaves them alone if it's installed.
$script:EditorExtensionDirs = @('.vscode', '.vscode-insiders', '.vscode-oss', '.cursor', '.windsurf') |
    ForEach-Object { Join-Path $HOME "$_\extensions" }
$script:ExtensionId = 'zmbq.vscode-retro'
# Installed font files start with this; matches installedFile in fonts.json (see tools/build.mjs).
$script:FontFilePrefix = 'RetroLooks-'

function Get-RetroFont {
    # Windows PowerShell 5.1's ConvertFrom-Json emits a JSON array as one object; emit its items one by one.
    $fonts = Get-Content (Join-Path $script:ModuleRoot 'fonts.json') -Raw | ConvertFrom-Json
    foreach ($font in $fonts) { $font }
}

# Pixel fonts are only sharp when each font pixel covers a whole number of screen pixels
# (screen pixels = points * dpi / 72). Pick the sharp size closest to the nominal one.
function Get-SharpPoints([double]$Points, [int]$PixelsPerEm, [int]$Dpi) {
    $multiple = [math]::Max(1, [math]::Round($Points * $Dpi / 72 / $PixelsPerEm, [MidpointRounding]::AwayFromZero))
    return [math]::Round($multiple * $PixelsPerEm * 72 / $Dpi, 3)
}

function Get-DisplayDpi {
    $metrics = Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -Name AppliedDPI -ErrorAction SilentlyContinue
    if ($metrics -and $metrics.AppliedDPI -gt 0) { return [int]$metrics.AppliedDPI }
    return 96
}

function Install-RetroFont {
    New-Item -ItemType Directory -Force $script:FontDir | Out-Null
    if (-not (Test-Path $script:FontKey)) { New-Item $script:FontKey -Force | Out-Null }
    foreach ($font in Get-RetroFont) {
        $source = Join-Path $script:ModuleRoot "fonts\$($font.id)\$($font.file)"
        $dest = Join-Path $script:FontDir $font.installedFile
        # Installed fonts may be locked by running apps; identical files don't need copying.
        if (-not ((Test-Path $dest) -and (Get-Item $dest).Length -eq (Get-Item $source).Length)) {
            Copy-Item $source $dest -Force
        }
        Set-ItemProperty -Path $script:FontKey -Name $font.registryName -Value $dest
        Write-Host "Installed font: $($font.family)"
    }
}

# Removes every Retro Looks font, including ones from older versions, by their file name prefix.
function Uninstall-RetroFont {
    if (-not (Test-Path $script:FontKey)) { return }
    $entries = (Get-ItemProperty $script:FontKey).PSObject.Properties |
        Where-Object { $_.Value -is [string] -and (Split-Path $_.Value -Leaf) -like "$script:FontFilePrefix*" }
    foreach ($entry in $entries) {
        Remove-ItemProperty -Path $script:FontKey -Name $entry.Name
        try {
            Remove-Item $entry.Value -Force -ErrorAction Stop
            Write-Host "Removed font: $($entry.Name)"
        } catch {
            Write-Warning "Font file is in use, so it stays until you delete it later (it's no longer registered): $($entry.Value)"
        }
    }
}

function Test-RetroVSCodeExtension {
    foreach ($dir in $script:EditorExtensionDirs) {
        if ((Test-Path $dir) -and (Get-ChildItem $dir -Directory -Filter "$script:ExtensionId-*" -ErrorAction SilentlyContinue)) {
            return $true
        }
    }
    return $false
}

function Install-RetroLooks {
    <#
    .SYNOPSIS
    Installs the Retro Looks fonts and adds the Retro Looks profiles to Windows Terminal.
    .DESCRIPTION
    Installs the fonts for the current user (no admin needed) and writes a Windows Terminal fragment with
    the retro profiles and color schemes. Pixel fonts are sized for the display's scaling so they stay sharp.
    Restart Windows Terminal afterwards. Running it again updates an existing installation.
    .PARAMETER KeepFontSizes
    Use the profiles' nominal font sizes instead of the sharpest sizes for this display's scaling.
    #>
    [CmdletBinding()]
    param([switch]$KeepFontSizes)

    Install-RetroFont

    $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe -NoLogo' } else { 'powershell.exe -NoLogo' }
    $pixelsPerEm = @{}
    foreach ($font in Get-RetroFont) { if ($font.pixelsPerEm) { $pixelsPerEm[$font.family] = [int]$font.pixelsPerEm } }
    $fragment = Get-Content (Join-Path $script:ModuleRoot 'retro-looks.json') -Raw | ConvertFrom-Json
    $dpi = Get-DisplayDpi
    foreach ($terminalProfile in $fragment.profiles) {
        $terminalProfile | Add-Member -NotePropertyName commandline -NotePropertyValue $shell -Force
        $grid = $pixelsPerEm[$terminalProfile.font.face]
        if ($grid -and -not $KeepFontSizes) {
            $terminalProfile.font.size = Get-SharpPoints $terminalProfile.font.size $grid $dpi
        }
    }
    New-Item -ItemType Directory -Force $script:FragmentDir | Out-Null
    $json = $fragment | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $script:FragmentDir 'retro-looks.json'), $json, (New-Object Text.UTF8Encoding $false))

    Write-Host ''
    Write-Host 'Retro Looks installed. Close all Windows Terminal windows and reopen it;'
    Write-Host 'the new profiles are in the drop-down next to the + tab button.'
}

function Uninstall-RetroLooks {
    <#
    .SYNOPSIS
    Removes the Retro Looks profiles from Windows Terminal, and the fonts unless VS Code still uses them.
    .PARAMETER RemoveFonts
    Remove the fonts even if the Retro Looks VS Code extension is installed.
    #>
    [CmdletBinding()]
    param([switch]$RemoveFonts)

    if (Test-Path $script:FragmentDir) { Remove-Item $script:FragmentDir -Recurse -Force }
    Write-Host 'Removed the Retro Looks profiles from Windows Terminal.'

    if (-not $RemoveFonts -and (Test-RetroVSCodeExtension)) {
        Write-Host 'Kept the fonts: the Retro Looks VS Code extension still uses them (-RemoveFonts removes them anyway).'
    } else {
        Uninstall-RetroFont
    }
    Write-Host 'Restart Windows Terminal to finish.'
}

Export-ModuleMember -Function Install-RetroLooks, Uninstall-RetroLooks
