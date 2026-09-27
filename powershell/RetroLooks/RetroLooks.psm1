# RetroLooks: vintage computer looks for Windows Terminal. Installs the fonts (current user only, no admin
# needed) and a Windows Terminal fragment with one hidden profile per look (only a profile can set a tab's
# font), so the user's settings.json is never touched. The looks are used through two commands:
#   Set-RetroLook (look)    opens a tab with a look, in the current folder, and closes the old one
#   Set-RetroColor (color)  recolors the current tab, like DOS's COLOR command
# Works on Windows PowerShell 5.1 and PowerShell 7.

$script:ModuleRoot = $PSScriptRoot

# Where things get installed. Script variables so the tests can point them at a sandbox.
$script:FontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$script:FontKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
# Never rename this folder: Windows Terminal ties users' profile settings to it.
$script:FragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\Retro Looks'
# Preferences (terminal.json: default look, default colors) and the color handed to a tab `look` opens.
$script:DataDir = Join-Path $env:LOCALAPPDATA 'RetroLooks'
# The Retro Looks VS Code extension installs the same fonts. Each project that uses them leaves a marker
# file here; the fonts are only removed once no marker is left.
$script:FontUsersDir = Join-Path $script:DataDir 'font-users'
$script:Marker = 'powershell'
$script:UserNames = @{ vscode = 'the Retro Looks VS Code extension' }
# Installed font files start with this; matches installedFile in fonts.json (see tools/build.mjs).
$script:FontFilePrefix = 'RetroLooks-'
# The tests replace this with a fake that records its arguments.
$script:WtCommand = 'wt.exe'

$Esc = [char]27
$St = "$Esc\"   # String Terminator, ends an OSC sequence

# ---------- data shipped with the module ----------

# Windows PowerShell 5.1's ConvertFrom-Json emits a JSON array as one object; these emit items one by one.
function Get-RetroFont {
    $fonts = Get-Content (Join-Path $script:ModuleRoot 'fonts.json') -Raw | ConvertFrom-Json
    foreach ($font in $fonts) { $font }
}

function Get-LookData {
    $looks = Get-Content (Join-Path $script:ModuleRoot 'looks.json') -Raw | ConvertFrom-Json
    foreach ($look in $looks) { $look }
}

function Get-PaletteData {
    Get-Content (Join-Path $script:ModuleRoot 'palette.json') -Raw | ConvertFrom-Json
}

# ---------- fonts ----------

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

function Add-FontMarker {
    New-Item -ItemType Directory -Force $script:FontUsersDir | Out-Null
    $version = $ExecutionContext.SessionState.Module.Version
    $line = "Retro Looks for Windows Terminal (RetroLooks module $version), $((Get-Date).ToUniversalTime().ToString('o'))"
    [IO.File]::WriteAllText((Join-Path $script:FontUsersDir $script:Marker), "$line`n")
}

function Remove-FontMarker {
    Remove-Item (Join-Path $script:FontUsersDir $script:Marker) -Force -ErrorAction SilentlyContinue
    # Leave nothing behind once no project uses the fonts.
    foreach ($dir in $script:FontUsersDir, $script:DataDir) {
        if ((Test-Path $dir) -and -not (Get-ChildItem $dir -Force)) { Remove-Item $dir -Force }
    }
}

# The other projects still using the fonts (marker names, e.g. "vscode").
function Get-OtherFontUser {
    if (-not (Test-Path $script:FontUsersDir)) { return }
    Get-ChildItem $script:FontUsersDir -File | Where-Object Name -ne $script:Marker | ForEach-Object Name
}

# ---------- colors (the same math as vscode/palette.js; the tests compare the two) ----------

function ConvertTo-Rgb([string]$Hex) {
    $n = [Convert]::ToInt32($Hex.TrimStart('#'), 16)
    return @((($n -shr 16) -band 255), (($n -shr 8) -band 255), ($n -band 255))
}

function ConvertTo-HexColor([double[]]$Rgb) {
    $parts = foreach ($c in $Rgb) {
        # [double] literals: with integer 0 and 255, PowerShell picks the integer overloads of Min/Max,
        # which round 250.5 to 250 before we get to round it.
        $clamped = [math]::Min([double]255, [math]::Max([double]0, $c))
        ([int][math]::Round($clamped, [MidpointRounding]::AwayFromZero)).ToString('X2')
    }
    return '#' + ($parts -join '')
}

function Get-MixedColor([string]$From, [string]$To, [double]$T) {
    $a = ConvertTo-Rgb $From
    $b = ConvertTo-Rgb $To
    return ConvertTo-HexColor @(($a[0] + ($b[0] - $a[0]) * $T), ($a[1] + ($b[1] - $a[1]) * $T), ($a[2] + ($b[2] - $a[2]) * $T))
}

# A preset name or #RRGGBB (# optional) -> '#RRGGBB', brightened like a glowing phosphor; $null if invalid.
function Resolve-RetroColor([string]$Value) {
    if (-not $Value) { return $null }
    $data = Get-PaletteData
    $name = $Value.Trim().ToLower()
    $preset = $data.presets.PSObject.Properties[$name]
    if ($preset) { return $preset.Value }
    if ($name -notmatch '^#?([0-9a-f]{6})$') { return $null }
    $rgb = ConvertTo-Rgb $Matches[1]
    $peak = [math]::Max($rgb[0], [math]::Max($rgb[1], $rgb[2]))
    if ($peak -eq 0) { return $null }
    if ($peak -lt $data.minPeak) {
        return ConvertTo-HexColor @(($rgb[0] * $data.minPeak / $peak), ($rgb[1] * $data.minPeak / $peak), ($rgb[2] * $data.minPeak / $peak))
    }
    return ConvertTo-HexColor $rgb
}

function Get-PhosphorPalette([string]$Color) {
    $dark = { param($t) Get-MixedColor '#000000' $Color $t }
    $light = { param($t) Get-MixedColor $Color '#FFFFFF' $t }
    $palette = @{
        deep = & $dark 0.055; bg = & $dark 0.07; raised = & $dark 0.118; faint = & $dark 0.165; border = & $dark 0.227
        selection = & $dark 0.36; dim = & $dark 0.42; comment = & $dark 0.54; muted = & $dark 0.7; soft = & $dark 0.815
        text = & $dark 0.9; full = $Color
        light1 = & $light 0.2; light2 = & $light 0.38; light3 = & $light 0.54; light4 = & $light 0.7
        normal = & $dark 0.72; bright = & $light 0.12
    }
    foreach ($entry in (Get-PaletteData).vga.PSObject.Properties) {
        $rgb = ConvertTo-Rgb $entry.Value
        $level = (0.3 * $rgb[0] + 0.59 * $rgb[1] + 0.11 * $rgb[2]) / 255
        $palette["vga_$($entry.Name)"] = if ($level -eq 0) { '#000000' } else { & $dark (0.25 + 0.75 * $level) }
    }
    return $palette
}

# The Terminal color scheme (background, foreground, the 16 ANSI colors, ...) of a style in a color.
function Get-RetroScheme([string]$Style, [string]$Color) {
    $palette = Get-PhosphorPalette $Color
    $template = Get-Content (Join-Path $script:ModuleRoot "templates\$Style-terminal-scheme.json") -Raw
    $filled = [regex]::Replace($template, '\$\{(\w+)\}', {
            param($m)
            $slot = $m.Groups[1].Value
            if (-not $palette.ContainsKey($slot)) { throw "Unknown palette slot $slot in $Style template." }
            $palette[$slot]
        })
    $scheme = @{}
    foreach ($entry in ($filled | ConvertFrom-Json).PSObject.Properties) { $scheme[$entry.Name] = $entry.Value }
    return $scheme
}

# DOS's 16 colors, by COLOR command digit.
$script:DosColors = @('#000000', '#0000AA', '#00AA00', '#00AAAA', '#AA0000', '#AA00AA', '#AA5500', '#AAAAAA',
    '#555555', '#5555FF', '#55FF55', '#55FFFF', '#FF5555', '#FF55FF', '#FFFF55', '#FFFFFF')
# On a black background, a DOS color that matches a phosphor preset means that preset.
$script:DosPresets = @{ 0xA = 'green'; 0xE = 'yellow'; 0xF = 'white'; 0xB = 'cyan'; 0x6 = 'amber' }

# Parses what Set-RetroColor accepts. Returns @{ Stored = <normalized text>; Phosphor = '#RRGGBB' } for a
# phosphor color, or @{ Stored; Foreground; Background } for a DOS code with a background.
function ConvertFrom-ColorSpec([string]$Spec) {
    $value = $Spec.Trim()
    $presets = (Get-PaletteData).presets.PSObject.Properties.Name
    if ($presets -contains $value.ToLower()) { return @{ Stored = $value.ToLower(); Phosphor = (Resolve-RetroColor $value) } }
    if ($value -match '^#?[0-9a-fA-F]{6}$') {
        $color = Resolve-RetroColor $value
        if (-not $color) { throw "'$Spec' is black; pick a color that glows." }
        return @{ Stored = '#' + $value.TrimStart('#').ToUpper(); Phosphor = $color }
    }
    if ($value -match '^[0-9a-fA-F]{1,2}$') {
        $code = $value.ToUpper().PadLeft(2, '0')
        $background = [Convert]::ToInt32($code.Substring(0, 1), 16)
        $foreground = [Convert]::ToInt32($code.Substring(1, 1), 16)
        if ($background -eq $foreground) { throw "COLOR ${code}: the text and background colors can't be the same (DOS agreed)." }
        if ($background -eq 0) {
            $phosphor = if ($script:DosPresets.ContainsKey($foreground)) { Resolve-RetroColor $script:DosPresets[$foreground] } else { Resolve-RetroColor $script:DosColors[$foreground] }
            return @{ Stored = $code; Phosphor = $phosphor }
        }
        return @{ Stored = $code; Foreground = $script:DosColors[$foreground]; Background = $script:DosColors[$background] }
    }
    throw "Unknown color '$Spec'. Use $($presets -join ', '), #RRGGBB, or a DOS code like 0A or 1F."
}

# ---------- terminal escape sequences ----------

$script:AnsiOrder = @('black', 'red', 'green', 'yellow', 'blue', 'purple', 'cyan', 'white',
    'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite')

function Format-OscColor([string]$Hex) {
    $h = $Hex.TrimStart('#').ToLower()
    return "rgb:$($h.Substring(0, 2))/$($h.Substring(2, 2))/$($h.Substring(4, 2))"
}

# The escape sequences that recolor a terminal: the 16 ANSI colors (OSC 4), text (OSC 10), background
# (OSC 11) and cursor (OSC 12). Windows Terminal and VS Code's terminal both understand them.
function Get-ColorSequence([hashtable]$Scheme) {
    $sequence = ''
    for ($i = 0; $i -lt 16; $i++) {
        $sequence += "$Esc]4;$i;$(Format-OscColor $Scheme[$script:AnsiOrder[$i]])$St"
    }
    $sequence += "$Esc]10;$(Format-OscColor $Scheme.foreground)$St"
    $sequence += "$Esc]11;$(Format-OscColor $Scheme.background)$St"
    $sequence += "$Esc]12;$(Format-OscColor $Scheme.cursorColor)$St"
    return $sequence
}

# Puts the tab back to its profile's own colors.
$script:ResetSequence = "$Esc]104$St$Esc]110$St$Esc]111$St$Esc]112$St"

# The sequence for a parsed color in a look (or, outside Retro Looks tabs, as a plain phosphor monitor).
function Get-SpecSequence($Parsed, $Look) {
    if ($Parsed.Phosphor) {
        $style = if ($Look) { $Look.colorStyle } else { 'phosphor' }
        return Get-ColorSequence (Get-RetroScheme $style $Parsed.Phosphor)
    }
    # A DOS code with a background: like DOS, only the text and background change.
    return "$Esc]10;$(Format-OscColor $Parsed.Foreground)$St$Esc]11;$(Format-OscColor $Parsed.Background)$St$Esc]12;$(Format-OscColor $Parsed.Foreground)$St"
}

function Write-TerminalSequence([string]$Sequence) {
    [Console]::Write($Sequence)
}

# ---------- preferences ----------

function Get-RetroPreference {
    $prefs = @{ defaultLook = $null; colors = @{} }
    $file = Join-Path $script:DataDir 'terminal.json'
    if (Test-Path $file) {
        $saved = Get-Content $file -Raw | ConvertFrom-Json
        if ($saved.defaultLook) { $prefs.defaultLook = $saved.defaultLook }
        if ($saved.colors) { foreach ($entry in $saved.colors.PSObject.Properties) { $prefs.colors[$entry.Name] = $entry.Value } }
    }
    return $prefs
}

function Save-RetroPreference([hashtable]$Prefs) {
    New-Item -ItemType Directory -Force $script:DataDir | Out-Null
    $json = [pscustomobject]@{ defaultLook = $Prefs.defaultLook; colors = [pscustomobject]$Prefs.colors } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $script:DataDir 'terminal.json'), $json, (New-Object Text.UTF8Encoding $false))
}

# ---------- looks ----------

function Find-RetroLook([string]$Name) {
    $wanted = $Name.Trim().ToLower()
    foreach ($look in Get-LookData) {
        $names = @($look.id, $look.name) + @($look.aliases) | ForEach-Object { "$_".ToLower() }
        if ($names -contains $wanted) { return $look }
    }
    return $null
}

# The look of the current Windows Terminal tab, from the profile Terminal says it was opened with.
function Get-CurrentLook {
    if (-not $env:WT_PROFILE_ID) { return $null }
    $id = $env:WT_PROFILE_ID.Trim('{', '}').ToLower()
    foreach ($look in Get-LookData) {
        if ($look.guid.Trim('{', '}').ToLower() -eq $id) { return $look }
    }
    return $null
}

function Get-LookNames {
    foreach ($look in Get-LookData) { @($look.aliases)[0] }
}

# ---------- commands ----------

function Set-RetroColor {
    <#
    .SYNOPSIS
    Recolors the current terminal tab, like DOS's COLOR command. Alias: color.
    .DESCRIPTION
    Takes a phosphor color (green, amber, white, cyan, yellow or #RRGGBB) or a DOS COLOR code (0A, 1F, ...;
    the first digit is the background, the second the text). Only this tab changes. In a Retro Looks tab the
    color is applied the way that machine would show it; for example an IBM 3270 tab keeps its two
    brightness levels. Without a color, the tab goes back to its default colors.
    .PARAMETER Color
    A preset (green, amber, white, cyan, yellow), #RRGGBB, or a DOS code.
    .PARAMETER SetAsDefault
    Also make this the color new tabs of this look open with. Without -Color, go back to the look's own default.
    .EXAMPLE
    color amber
    .EXAMPLE
    color 0A
    .EXAMPLE
    color '#40E0FF' -SetAsDefault
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Color,
        [switch]$SetAsDefault
    )
    $look = Get-CurrentLook
    if ($SetAsDefault -and -not $look) {
        throw "-SetAsDefault works in a Retro Looks tab (open one with Set-RetroLook, alias look)."
    }

    if (-not $Color) {
        $prefs = Get-RetroPreference
        if ($SetAsDefault) {
            $prefs.colors.Remove($look.id)
            Save-RetroPreference $prefs
        }
        Write-TerminalSequence $script:ResetSequence
        if ($look -and $prefs.colors[$look.id]) {
            Write-TerminalSequence (Get-SpecSequence (ConvertFrom-ColorSpec $prefs.colors[$look.id]) $look)
        }
        return
    }

    $parsed = ConvertFrom-ColorSpec $Color
    if (-not $parsed.Phosphor) { Write-TerminalSequence $script:ResetSequence }
    Write-TerminalSequence (Get-SpecSequence $parsed $look)
    if ($SetAsDefault) {
        $prefs = Get-RetroPreference
        $prefs.colors[$look.id] = $parsed.Stored
        Save-RetroPreference $prefs
        Write-Host "New $($look.name) tabs will open in $($parsed.Stored)."
    }
}

function Initialize-RetroTab {
    <#
    .SYNOPSIS
    Applies a Retro Looks tab's color when it opens. The Retro Looks profiles run it; you don't need to.
    #>
    [CmdletBinding()]
    param()
    $look = Get-CurrentLook
    if (-not $look) { return }
    $spec = $null
    # A color handed over by `look -Color`, if it's for this look and fresh.
    $pending = Join-Path $script:DataDir 'pending-color'
    if (Test-Path $pending) {
        $parts = (Get-Content $pending -Raw).Trim() -split '\|'
        if ($parts[0] -eq $look.id -and ((Get-Date).ToUniversalTime().Ticks - [long]$parts[2]) -lt [TimeSpan]::FromMinutes(1).Ticks) {
            $spec = $parts[1]
        }
        Remove-Item $pending -Force -ErrorAction SilentlyContinue
    }
    if (-not $spec) { $spec = (Get-RetroPreference).colors[$look.id] }
    if ($spec) { Write-TerminalSequence (Get-SpecSequence (ConvertFrom-ColorSpec $spec) $look) }
}

function Set-RetroLook {
    <#
    .SYNOPSIS
    Opens a Windows Terminal tab with a retro look, in the current folder, and closes this one. Alias: look.
    .DESCRIPTION
    Windows Terminal only lets a profile set a tab's font, so a new tab opens with the look's (hidden)
    profile. Scrollback and anything running in the old tab are not carried over; use -KeepTab to keep it.
    Without a look, opens your default look (Apple //e unless you set another with -SetAsDefault).
    .PARAMETER Look
    The look: apple, ps2, ps2mono, 3270, 3270mono (or its full name). Tab completes.
    .PARAMETER Color
    Open the tab in this color: a preset, #RRGGBB or a DOS code (see Set-RetroColor).
    .PARAMETER SetAsDefault
    Make this look (and -Color, if given) what `look` opens without arguments.
    .PARAMETER Off
    Open a normal tab (your default Windows Terminal profile) instead.
    .PARAMETER KeepTab
    Don't close the current tab.
    .EXAMPLE
    look apple -Color amber
    .EXAMPLE
    look 3270 -SetAsDefault
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)][string]$Look,
        [string]$Color,
        [switch]$SetAsDefault,
        [switch]$Off,
        [switch]$KeepTab
    )
    if ($env:TERM_PROGRAM -eq 'vscode') {
        Write-Host "This terminal follows the VS Code look. Use 'Retro: Choose Look...' in VS Code's Command Palette."
        return
    }

    $target = $null
    if (-not $Off) {
        $prefs = Get-RetroPreference
        $name = $Look
        if (-not $name) { $name = $prefs.defaultLook }
        if (-not $name) { $name = 'apple2e' }
        $target = Find-RetroLook $name
        if (-not $target) { throw "Unknown look '$name'. Looks: $((Get-LookNames) -join ', ')." }
        $parsed = $null
        if ($Color) { $parsed = ConvertFrom-ColorSpec $Color }
        if ($SetAsDefault) {
            $prefs.defaultLook = $target.id
            if ($parsed) { $prefs.colors[$target.id] = $parsed.Stored }
            Save-RetroPreference $prefs
            Write-Host "'look' now opens $($target.name)$(if ($parsed) { " in $($parsed.Stored)" })."
        }
    }

    if (-not $env:WT_SESSION) {
        if ($SetAsDefault) { return }
        throw 'Set-RetroLook opens a Windows Terminal tab; run it inside Windows Terminal.'
    }
    if ($target -and $parsed) {
        New-Item -ItemType Directory -Force $script:DataDir | Out-Null
        [IO.File]::WriteAllText((Join-Path $script:DataDir 'pending-color'), "$($target.id)|$($parsed.Stored)|$((Get-Date).ToUniversalTime().Ticks)")
    }

    $location = Get-Location
    $folder = if ($location.Provider.Name -eq 'FileSystem') { $location.ProviderPath } else { $HOME }
    $folder = $folder.Replace(';', '\;')   # wt treats ; as a command separator
    $arguments = @('-w', '0', 'nt')
    if ($target) { $arguments += @('-p', $target.guid) }
    $arguments += @('-d', $folder)
    & $script:WtCommand @arguments

    if (-not $KeepTab) { exit }
}

function Get-RetroLook {
    <#
    .SYNOPSIS
    Lists the Retro Looks, with the names Set-RetroLook accepts and your default colors.
    #>
    [CmdletBinding()]
    param()
    $prefs = Get-RetroPreference
    $current = Get-CurrentLook
    foreach ($look in Get-LookData) {
        $color = $prefs.colors[$look.id]
        if (-not $color) { $color = $look.defaultColor }
        [pscustomobject]@{
            Name    = $look.name
            Look    = @($look.aliases)[0]
            Aliases = @($look.aliases) -join ', '
            Color   = $color
            Default = ($prefs.defaultLook -eq $look.id) -or (-not $prefs.defaultLook -and $look.id -eq 'apple2e')
            Current = $current -and $current.id -eq $look.id
        }
    }
}

function Install-RetroLooks {
    <#
    .SYNOPSIS
    Installs the Retro Looks fonts and adds the looks to Windows Terminal.
    .DESCRIPTION
    Installs the fonts for the current user (no admin needed) and writes a Windows Terminal fragment with a
    profile and color schemes for each look. The profiles are hidden: open the looks with Set-RetroLook
    (alias look). Pixel fonts are sized for the display's scaling so they stay sharp. Restart Windows
    Terminal afterwards. Running it again updates an existing installation.
    .PARAMETER KeepFontSizes
    Use the profiles' nominal font sizes instead of the sharpest sizes for this display's scaling.
    .PARAMETER ShowProfiles
    Also show the looks in Windows Terminal's profile menu.
    #>
    [CmdletBinding()]
    param([switch]$KeepFontSizes, [switch]$ShowProfiles)

    Install-RetroFont
    Add-FontMarker

    $shell = if (Get-Command pwsh.exe -ErrorAction SilentlyContinue) { 'pwsh.exe' } else { 'powershell.exe' }
    $pixelsPerEm = @{}
    foreach ($font in Get-RetroFont) { if ($font.pixelsPerEm) { $pixelsPerEm[$font.family] = [int]$font.pixelsPerEm } }
    $fragment = Get-Content (Join-Path $script:ModuleRoot 'retro-looks.json') -Raw | ConvertFrom-Json
    $dpi = Get-DisplayDpi
    foreach ($terminalProfile in $fragment.profiles) {
        # Each tab applies its saved color (and a color handed over by `look -Color`) when it opens.
        $terminalProfile | Add-Member -NotePropertyName commandline -NotePropertyValue "$shell -NoLogo -NoExit -Command Initialize-RetroTab" -Force
        $terminalProfile.hidden = -not $ShowProfiles
        $grid = $pixelsPerEm[$terminalProfile.font.face]
        if ($grid -and -not $KeepFontSizes) {
            $terminalProfile.font.size = Get-SharpPoints $terminalProfile.font.size $grid $dpi
        }
    }
    New-Item -ItemType Directory -Force $script:FragmentDir | Out-Null
    $json = $fragment | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $script:FragmentDir 'retro-looks.json'), $json, (New-Object Text.UTF8Encoding $false))

    Write-Host ''
    Write-Host 'Retro Looks installed. Close all Windows Terminal windows and reopen it, then type'
    Write-Host "  look apple         (or: $((Get-LookNames) -join ', '))"
    Write-Host '  color amber        (or #RRGGBB, or a DOS code like 0A)'
    Write-Host 'Get-RetroLook lists the looks.'
}

function Uninstall-RetroLooks {
    <#
    .SYNOPSIS
    Removes the Retro Looks from Windows Terminal, and the fonts unless something else still uses them.
    .PARAMETER RemoveFonts
    Remove the fonts even if the Retro Looks VS Code extension still uses them.
    #>
    [CmdletBinding()]
    param([switch]$RemoveFonts)

    if (Test-Path $script:FragmentDir) { Remove-Item $script:FragmentDir -Recurse -Force }
    foreach ($file in 'terminal.json', 'pending-color') {
        Remove-Item (Join-Path $script:DataDir $file) -Force -ErrorAction SilentlyContinue
    }
    Write-Host 'Removed the Retro Looks from Windows Terminal.'

    Remove-FontMarker
    $others = @(Get-OtherFontUser)
    if ($others.Count -and -not $RemoveFonts) {
        $names = ($others | ForEach-Object { if ($script:UserNames[$_]) { $script:UserNames[$_] } else { $_ } }) -join ', '
        Write-Host "Kept the fonts: $names still uses them (-RemoveFonts removes them anyway)."
    } else {
        Uninstall-RetroFont
    }
    Write-Host 'Restart Windows Terminal to finish.'
}

# ---------- tab completion and aliases ----------

$lookCompleter = {
    param($commandName, $parameterName, $wordToComplete)
    Get-LookData | ForEach-Object { @($_.aliases)[0] } | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
$colorCompleter = {
    param($commandName, $parameterName, $wordToComplete)
    (Get-PaletteData).presets.PSObject.Properties.Name | Where-Object { $_ -like "$wordToComplete*" } |
        ForEach-Object { [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_) }
}
Register-ArgumentCompleter -CommandName Set-RetroLook -ParameterName Look -ScriptBlock $lookCompleter
Register-ArgumentCompleter -CommandName Set-RetroLook -ParameterName Color -ScriptBlock $colorCompleter
Register-ArgumentCompleter -CommandName Set-RetroColor -ParameterName Color -ScriptBlock $colorCompleter

Set-Alias -Name look -Value Set-RetroLook
Set-Alias -Name color -Value Set-RetroColor

Export-ModuleMember -Function Install-RetroLooks, Uninstall-RetroLooks, Set-RetroLook, Set-RetroColor, Get-RetroLook, Initialize-RetroTab -Alias look, color
