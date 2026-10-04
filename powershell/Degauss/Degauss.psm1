# Degauss: vintage computer looks for Windows Terminal. Installs the fonts (current user only, no admin
# needed) and a Windows Terminal fragment with one hidden profile per look (only a profile can set a tab's
# font), so the user's settings.json is never touched. The looks are used through two commands:
#   Set-DegaussLook (look)    opens a tab with a look, in the current folder, and closes the old one
#   Set-DegaussColor (color)  recolors the current tab, like DOS's COLOR command
# and, for fun, Invoke-Degauss (degauss), which does what a CRT's degauss button did.
# Works on Windows PowerShell 5.1 and PowerShell 7.

$script:ModuleRoot = $PSScriptRoot

# Where things get installed. Script variables so the tests can point them at a sandbox.
$script:FontDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$script:FontKey = 'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
# Never rename this folder: Windows Terminal ties users' profile settings to it.
$script:FragmentDir = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows Terminal\Fragments\Degauss'
# Preferences (terminal.json: default look, default colors) and the color handed to a tab `look` opens.
$script:DataDir = Join-Path $env:LOCALAPPDATA 'Degauss'
# The Degauss VS Code extension installs the same fonts. Each project that uses them leaves a marker
# file here; the fonts are only removed once no marker is left.
$script:FontUsersDir = Join-Path $script:DataDir 'font-users'
$script:Marker = 'powershell'
$script:UserNames = @{ vscode = 'the Degauss VS Code extension' }
# Installed font files start with this; matches installedFile in fonts.json (see tools/build.mjs).
$script:FontFilePrefix = 'Degauss-'
# The tests replace this with a fake that records its arguments.
$script:WtCommand = 'wt.exe'
# The one visible profile, "Degauss": a copy of the user's default look. Its GUID never changes, so it
# can be Windows Terminal's default profile and stay that way when the default look changes.
$script:DegaussProfileGuid = '{79eea499-748d-4441-821d-451f0c283c2e}'
$script:DegaussProfileName = 'Degauss'
# The look `look` opens when nothing else was chosen.
$script:FallbackLook = 'apple2e'
# Asks the user a yes/no question (default yes). The tests replace it with a scripted answer.
$script:AskUser = {
    param([string]$Question)
    $choices = [System.Management.Automation.Host.ChoiceDescription[]]@('&Yes', '&No')
    return $Host.UI.PromptForChoice('Degauss', $Question, $choices, 0) -eq 0
}

$Esc = [char]27
$St = "$Esc\"   # String Terminator, ends an OSC sequence

# ---------- data shipped with the module ----------

# Windows PowerShell 5.1's ConvertFrom-Json emits a JSON array as one object; these emit items one by one.
function Get-DegaussFont {
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

function Install-DegaussFont {
    New-Item -ItemType Directory -Force $script:FontDir | Out-Null
    if (-not (Test-Path $script:FontKey)) { New-Item $script:FontKey -Force | Out-Null }
    foreach ($font in Get-DegaussFont) {
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

# Removes every Degauss font, including ones from older versions, by their file name prefix.
function Uninstall-DegaussFont {
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
    $line = "Degauss for Windows Terminal (Degauss module $version), $((Get-Date).ToUniversalTime().ToString('o'))"
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
function Resolve-DegaussColor([string]$Value) {
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
function Get-DegaussScheme([string]$Style, [string]$Color) {
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

# Parses what Set-DegaussColor accepts. Returns @{ Stored = <normalized text>; Phosphor = '#RRGGBB' } for a
# phosphor color, or @{ Stored; Foreground; Background } for a DOS code with a background.
function ConvertFrom-ColorSpec([string]$Spec) {
    $value = $Spec.Trim()
    $presets = (Get-PaletteData).presets.PSObject.Properties.Name
    if ($presets -contains $value.ToLower()) { return @{ Stored = $value.ToLower(); Phosphor = (Resolve-DegaussColor $value) } }
    if ($value -match '^#?[0-9a-fA-F]{6}$') {
        $color = Resolve-DegaussColor $value
        if (-not $color) { throw "'$Spec' is black; pick a color that glows." }
        return @{ Stored = '#' + $value.TrimStart('#').ToUpper(); Phosphor = $color }
    }
    if ($value -match '^[0-9a-fA-F]{1,2}$') {
        $code = $value.ToUpper().PadLeft(2, '0')
        $background = [Convert]::ToInt32($code.Substring(0, 1), 16)
        $foreground = [Convert]::ToInt32($code.Substring(1, 1), 16)
        if ($background -eq $foreground) { throw "COLOR ${code}: the text and background colors can't be the same (DOS agreed)." }
        if ($background -eq 0) {
            $phosphor = if ($script:DosPresets.ContainsKey($foreground)) { Resolve-DegaussColor $script:DosPresets[$foreground] } else { Resolve-DegaussColor $script:DosColors[$foreground] }
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

# The sequence for a parsed color in a look (or, outside Degauss tabs, as a plain phosphor monitor).
function Get-SpecSequence($Parsed, $Look) {
    if ($Parsed.Phosphor) {
        $style = if ($Look) { $Look.colorStyle } else { 'phosphor' }
        return Get-ColorSequence (Get-DegaussScheme $style $Parsed.Phosphor)
    }
    # A DOS code with a background: like DOS, only the text and background change.
    return "$Esc]10;$(Format-OscColor $Parsed.Foreground)$St$Esc]11;$(Format-OscColor $Parsed.Background)$St$Esc]12;$(Format-OscColor $Parsed.Foreground)$St"
}

function Write-TerminalSequence([string]$Sequence) {
    [Console]::Write($Sequence)
}

# Windows Terminal throws away colors set by programs when the input language changes (and in a few other
# cases; microsoft/terminal#11522). So a tab remembers its color and re-sends it with every prompt: after
# such a reset, the color is back as soon as a command runs or Enter is pressed. The user's own prompt
# function is wrapped, not replaced, and Uninstall-Degauss puts it back.
$script:TabSequence = $null
$script:OriginalPrompt = $null
$script:PromptWrapper = {
    if ($script:TabSequence) { try { Write-TerminalSequence $script:TabSequence } catch { } }
    & $script:OriginalPrompt
}

function Set-TabColorState([string]$Sequence) {
    $script:TabSequence = $Sequence
    if ($Sequence -and -not $script:OriginalPrompt) {
        $current = Get-Command prompt -CommandType Function -ErrorAction SilentlyContinue
        $script:OriginalPrompt = if ($current) { $current.ScriptBlock } else { { "PS $($executionContext.SessionState.Path.CurrentLocation)$('>' * ($nestedPromptLevel + 1)) " } }
        Set-Item function:global:prompt -Value $script:PromptWrapper
    }
}

function Remove-PromptHook {
    if ($script:OriginalPrompt) {
        Set-Item function:global:prompt -Value $script:OriginalPrompt
        $script:OriginalPrompt = $null
    }
    $script:TabSequence = $null
}

# ---------- preferences ----------

# defaultLook: what `look` and the Degauss profile open; colors: each look's default color;
# showProfiles, keepFontSizes: Install-Degauss's choices, kept for when the fragment is rewritten.
function Get-DegaussPreference {
    $prefs = @{ defaultLook = $null; colors = @{}; showProfiles = $false; keepFontSizes = $false; installedVersion = $null }
    $file = Join-Path $script:DataDir 'terminal.json'
    if (Test-Path $file) {
        $saved = Get-Content $file -Raw | ConvertFrom-Json
        if ($saved.defaultLook) { $prefs.defaultLook = $saved.defaultLook }
        if ($saved.colors) { foreach ($entry in $saved.colors.PSObject.Properties) { $prefs.colors[$entry.Name] = $entry.Value } }
        $prefs.showProfiles = [bool]$saved.showProfiles
        $prefs.keepFontSizes = [bool]$saved.keepFontSizes
        if ($saved.installedVersion) { $prefs.installedVersion = $saved.installedVersion }
    }
    return $prefs
}

function Save-DegaussPreference([hashtable]$Prefs) {
    New-Item -ItemType Directory -Force $script:DataDir | Out-Null
    $json = [pscustomobject]@{
        defaultLook = $Prefs.defaultLook; colors = [pscustomobject]$Prefs.colors
        showProfiles = [bool]$Prefs.showProfiles; keepFontSizes = [bool]$Prefs.keepFontSizes
        installedVersion = $Prefs.installedVersion
    } | ConvertTo-Json -Depth 5
    [IO.File]::WriteAllText((Join-Path $script:DataDir 'terminal.json'), $json, (New-Object Text.UTF8Encoding $false))
}

function Get-ModuleVersion { "$($ExecutionContext.SessionState.Module.Version)" }

# Is Windows Terminal installed? A script variable so the tests can pretend either way.
$script:IsTerminalInstalled = { [bool](Get-Command wt.exe -ErrorAction SilentlyContinue) }

# Can PowerShell 7 load this version of the module? Install-Module installs for the PowerShell that runs it
# only, so a module installed from Windows PowerShell is usually missing from PowerShell 7. A script variable
# so the tests can pretend either way.
$script:PwshHasModule = {
    if ($PSVersionTable.PSEdition -eq 'Core') { return $true }
    if (-not (Get-Command pwsh.exe -ErrorAction SilentlyContinue)) { return $false }
    $check = "if (Get-Module -ListAvailable Degauss | Where-Object { `"`$(`$_.Version)`" -eq '$(Get-ModuleVersion)' }) { exit 0 } else { exit 1 }"
    & pwsh.exe -NoProfile -NonInteractive -Command $check 2>$null | Out-Null
    return $LASTEXITCODE -eq 0
}

# The PowerShell Degauss tabs run: PowerShell 7 if it has this module, otherwise Windows PowerShell.
function Get-TabShell {
    if (& $script:PwshHasModule) { 'pwsh.exe' } else { 'powershell.exe' }
}

function Write-NotInTerminal {
    if (& $script:IsTerminalInstalled) {
        Write-Host "look switches Windows Terminal tabs to a retro look, and this terminal isn't Windows Terminal. Open Windows Terminal and run look there. (color works here too, if this terminal supports it.)"
    } else {
        Write-Host "look needs Windows Terminal, which isn't installed. Get it from the Microsoft Store, or with: winget install Microsoft.WindowsTerminal"
    }
}

# `look` needs the fonts and the Terminal profiles. Installing a module never runs its code, so on first use
# this offers to set them up, and after an update it offers to refresh them. Returns $true when `look` can
# go ahead right away.
function Confirm-DegaussSetup {
    if (-not (Test-Path (Join-Path $script:FragmentDir 'degauss.json'))) {
        $question = "Degauss isn't set up yet: it needs to install its fonts (for your user only) and add its profiles to Windows Terminal. Set it up now?"
        if (-not (& $script:AskUser $question)) {
            Write-Host 'Not set up. Run Install-Degauss whenever you are ready.'
            return $false
        }
        Install-Degauss
        Write-Host 'Restart Windows Terminal (close all its windows), then run look again.' -ForegroundColor Yellow
        return $false
    }
    $prefs = Get-DegaussPreference
    $current = Get-ModuleVersion
    if ($prefs.installedVersion -ne $current) {
        $from = if ($prefs.installedVersion) { $prefs.installedVersion } else { 'an earlier version' }
        if (& $script:AskUser "Degauss was updated ($from to $current). Refresh its fonts and Windows Terminal profiles?") {
            Install-Degauss -ShowProfiles:$prefs.showProfiles -KeepFontSizes:$prefs.keepFontSizes
            Write-Host 'Looks added in this update appear after you restart Windows Terminal.' -ForegroundColor Yellow
        }
    }
    return $true
}

function Get-DefaultLookId([hashtable]$Prefs) {
    if ($Prefs.defaultLook -and (Find-DegaussLook $Prefs.defaultLook)) { return $Prefs.defaultLook }
    return $script:FallbackLook
}

# Writes the Windows Terminal fragment: a hidden profile per look (what `look` opens) and the visible
# Degauss profile, a copy of the default look. Terminal reads it when it starts.
# The Terminal color scheme for a look's default color: one of the shipped preset schemes if it matches,
# or else a new "<look> Custom" scheme. Returns @{ name; new } (new: the scheme to add, if any).
function Get-DefaultColorScheme($Entry, [string]$Spec, [string]$CurrentScheme, $Schemes) {
    $parsed = ConvertFrom-ColorSpec $Spec
    if ($parsed.Phosphor -and $Entry.monochrome) {
        foreach ($preset in (Get-PaletteData).presets.PSObject.Properties) {
            $name = "$($Entry.name) " + $preset.Name.Substring(0, 1).ToUpper() + $preset.Name.Substring(1)
            if ($preset.Value -eq $parsed.Phosphor -and ($Schemes | Where-Object { $_.name -eq $name })) {
                return @{ name = $name; new = $null }
            }
        }
    }
    $custom = [ordered]@{ name = "$($Entry.name) Custom" }
    if ($parsed.Phosphor) {
        $colors = Get-DegaussScheme $Entry.colorStyle $parsed.Phosphor
        foreach ($key in $colors.Keys | Sort-Object) { $custom[$key] = $colors[$key] }
    } else {
        # A DOS code with a background: the look's own colors, with DOS's text and background.
        $base = $Schemes | Where-Object { $_.name -eq $CurrentScheme }
        foreach ($p in $base.PSObject.Properties) { if ($p.Name -ne 'name') { $custom[$p.Name] = $p.Value } }
        $custom.foreground = $parsed.Foreground
        $custom.cursorColor = $parsed.Foreground
        $custom.background = $parsed.Background
    }
    return @{ name = $custom.name; new = [pscustomobject]$custom }
}

function Write-DegaussFragment([hashtable]$Prefs) {
    $shell = Get-TabShell
    $pixelsPerEm = @{}
    foreach ($font in Get-DegaussFont) { if ($font.pixelsPerEm) { $pixelsPerEm[$font.family] = [int]$font.pixelsPerEm } }
    $fragment = Get-Content (Join-Path $script:ModuleRoot 'degauss.json') -Raw | ConvertFrom-Json
    $dpi = Get-DisplayDpi
    $schemes = @($fragment.schemes)
    $looksByGuid = @{}
    foreach ($entry in Get-LookData) { $looksByGuid[$entry.guid] = $entry }
    foreach ($terminalProfile in $fragment.profiles) {
        # Each tab applies its saved color (and a color handed over by `look -Color`) when it opens.
        $terminalProfile | Add-Member -NotePropertyName commandline -NotePropertyValue "$shell -NoLogo -NoExit -Command Initialize-DegaussTab" -Force
        $terminalProfile.hidden = -not $Prefs.showProfiles
        $grid = $pixelsPerEm[$terminalProfile.font.face]
        if ($grid -and -not $Prefs.keepFontSizes) {
            $terminalProfile.font.size = Get-SharpPoints $terminalProfile.font.size $grid $dpi
        }
        # Windows Terminal resets colors set by programs to the profile's scheme, e.g. when the input
        # language changes (microsoft/terminal#11522). So the profile uses the scheme of the look's default
        # color, and a reset lands on the user's color rather than the built-in one.
        $entry = $looksByGuid[$terminalProfile.guid]
        if ($entry -and $Prefs.colors[$entry.id]) {
            $scheme = Get-DefaultColorScheme $entry $Prefs.colors[$entry.id] $terminalProfile.colorScheme $schemes
            if ($scheme.new) { $schemes += $scheme.new }
            $terminalProfile.colorScheme = $scheme.name
        }
    }
    $fragment.schemes = $schemes

    $defaultLook = Find-DegaussLook (Get-DefaultLookId $Prefs)
    $source = $fragment.profiles | Where-Object { $_.guid -eq $defaultLook.guid }
    $visible = $source | ConvertTo-Json -Depth 5 | ConvertFrom-Json   # a copy
    $visible.guid = $script:DegaussProfileGuid
    $visible.name = $script:DegaussProfileName
    $visible.hidden = $false
    # -Look tells the tab which look this copy was made from, so it can notice a newer default.
    $visible.commandline = "$shell -NoLogo -NoExit -Command Initialize-DegaussTab -Look $($defaultLook.id)"
    $fragment.profiles = @($visible) + @($fragment.profiles)

    New-Item -ItemType Directory -Force $script:FragmentDir | Out-Null
    $json = $fragment | ConvertTo-Json -Depth 10
    [IO.File]::WriteAllText((Join-Path $script:FragmentDir 'degauss.json'), $json, (New-Object Text.UTF8Encoding $false))
}

# ---------- looks ----------

function Find-DegaussLook([string]$Name) {
    $wanted = $Name.Trim().ToLower()
    foreach ($look in Get-LookData) {
        $names = @($look.id, $look.name) + @($look.aliases) | ForEach-Object { "$_".ToLower() }
        if ($names -contains $wanted) { return $look }
    }
    return $null
}

# The look of the current Windows Terminal tab: the one Initialize-DegaussTab recorded when the tab opened,
# or else the one of the profile Terminal says the tab was opened with.
function Get-CurrentLook {
    if ($env:TERM_PROGRAM -eq 'vscode') { return $null }   # VS Code's terminal follows the VS Code look
    if ($env:DEGAUSS_LOOK) {
        $look = Find-DegaussLook $env:DEGAUSS_LOOK
        if ($look) { return $look }
    }
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

function Set-DegaussColor {
    <#
    .SYNOPSIS
    Recolors the current terminal tab, like DOS's COLOR command. Alias: color.
    .DESCRIPTION
    Takes a phosphor color (green, amber, white, cyan, yellow or #RRGGBB) or a DOS COLOR code (0A, 1F, ...;
    the first digit is the background, the second the text). Only this tab changes. In a Degauss tab the
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
        throw "-SetAsDefault works in a Degauss tab (open one with Set-DegaussLook, alias look)."
    }

    $prefs = Get-DegaussPreference
    if (-not $Color) {
        if ($SetAsDefault) {
            $prefs.colors.Remove($look.id)
            Save-DefaultColor $prefs $look
        }
        Write-TerminalSequence $script:ResetSequence
        $sequence = $null
        if ($look -and $prefs.colors[$look.id]) {
            $sequence = Get-SpecSequence (ConvertFrom-ColorSpec $prefs.colors[$look.id]) $look
            Write-TerminalSequence $sequence
        }
        Set-TabColorState $sequence
        return
    }

    $parsed = ConvertFrom-ColorSpec $Color
    $sequence = Get-SpecSequence $parsed $look
    if (-not $parsed.Phosphor) { $sequence = $script:ResetSequence + $sequence }
    Write-TerminalSequence $sequence
    Set-TabColorState $sequence
    if ($SetAsDefault) {
        $prefs.colors[$look.id] = $parsed.Stored
        Save-DefaultColor $prefs $look
        Write-Host "New $($look.name) tabs will open in $($parsed.Stored)."
    }
}

# Saves a look's default color, and puts it in the look's Windows Terminal profile too, so that Terminal's
# own color resets land on it (after Terminal restarts and reads the profile again).
function Save-DefaultColor([hashtable]$Prefs, $Look) {
    Save-DegaussPreference $Prefs
    if (Test-Path (Join-Path $script:FragmentDir 'degauss.json')) {
        Write-DegaussFragment $Prefs
        Write-Host "Restart Windows Terminal for $($Look.name)'s profile to use it too (so Terminal's own color resets, e.g. when you switch input languages, return to it)."
    }
}

# ---------- degauss ----------

# Replaceable by the tests.
$script:PlaySound = {
    param($File)
    $script:Player = New-Object System.Media.SoundPlayer $File
    $script:Player.Play()   # plays in the background while the colors swirl
}
$script:DegaussFrames = 32
$script:DegaussFrameMs = 40
# The widest wobble, in columns, is twice this (vscode/degauss.js wobbles by pixels, a terminal by cells).
$script:DegaussWobbleColumns = 2
# The characters and colors on screen, as a BufferCell[,]. Throws where the host can't read the screen
# (then degauss only swirls the colors). Replaceable by the tests.
$script:GetScreenCells = {
    $raw = $Host.UI.RawUI
    $position = $raw.WindowPosition
    $size = $raw.WindowSize
    if ($size.Width -le 0 -or $size.Height -le 0) { throw 'No screen to read.' }
    $rectangle = New-Object System.Management.Automation.Host.Rectangle $position.X, $position.Y, ($position.X + $size.Width - 1), ($position.Y + $size.Height - 1)
    , $raw.GetBufferContents($rectangle)
}

# The scheme a Degauss tab opened with: its profile's, in the module's copy of the fragment.
function Get-LookScheme($Look) {
    $fragment = Get-Content (Join-Path $script:ModuleRoot 'degauss.json') -Raw | ConvertFrom-Json
    $name = $null
    foreach ($p in $fragment.profiles) { if ($p.guid -eq $Look.guid) { $name = $p.colorScheme } }
    foreach ($entry in $fragment.schemes) {
        if ($entry.name -ne $name) { continue }
        $scheme = @{}
        foreach ($property in $entry.PSObject.Properties) { $scheme[$property.Name] = $property.Value }
        return $scheme
    }
    return $null
}

# The tab's current colors, as far as the module knows them: what `color` set, else the look's own, else
# Windows Terminal's default (Campbell). @{ Ansi = 16 colors or $null; Foreground; Background; Cursor }
function Get-TabColors {
    $sequence = $script:TabSequence
    if (-not $sequence) {
        $look = Get-CurrentLook
        $scheme = if ($look) { Get-LookScheme $look } else { $null }
        if ($scheme) { $sequence = Get-ColorSequence $scheme }
    }
    $colors = @{ Ansi = $null; Foreground = '#CCCCCC'; Background = '#0C0C0C'; Cursor = '#FFFFFF' }
    if (-not $sequence) { return $colors }
    $ansi = New-Object 'string[]' 16
    foreach ($m in [regex]::Matches($sequence, '\](4;(\d+)|10|11|12);rgb:(\w\w)/(\w\w)/(\w\w)')) {
        $hex = '#' + ($m.Groups[3].Value + $m.Groups[4].Value + $m.Groups[5].Value).ToUpper()
        switch ($m.Groups[1].Value) {
            '10' { $colors.Foreground = $hex }
            '11' { $colors.Background = $hex }
            '12' { $colors.Cursor = $hex }
            default { $ansi[[int]$m.Groups[2].Value] = $hex; $colors.Ansi = $ansi }
        }
    }
    return $colors
}

# Rotates a color's hue (the matrix of CSS's hue-rotate filter, as in vscode/degauss.js).
function Get-RotatedColor([string]$Hex, [double]$Degrees) {
    $rgb = ConvertTo-Rgb $Hex
    $c = [math]::Cos($Degrees * [math]::PI / 180)
    $s = [math]::Sin($Degrees * [math]::PI / 180)
    return ConvertTo-HexColor @(
        ($rgb[0] * (0.213 + 0.787 * $c - 0.213 * $s) + $rgb[1] * (0.715 - 0.715 * $c - 0.715 * $s) + $rgb[2] * (0.072 - 0.072 * $c + 0.928 * $s)),
        ($rgb[0] * (0.213 - 0.213 * $c + 0.143 * $s) + $rgb[1] * (0.715 + 0.285 * $c + 0.14 * $s) + $rgb[2] * (0.072 - 0.072 * $c - 0.283 * $s)),
        ($rgb[0] * (0.213 - 0.213 * $c - 0.787 * $s) + $rgb[1] * (0.715 - 0.715 * $c + 0.715 * $s) + $rgb[2] * (0.072 + 0.928 * $c + 0.072 * $s)))
}

# A fully saturated color of the given hue.
function Get-RainbowColor([double]$Hue) {
    $h = ((($Hue % 360) + 360) % 360) / 60
    $x = 1 - [math]::Abs(($h % 2) - 1)
    $rgb = @(@(1, $x, 0), @($x, 1, 0), @(0, 1, $x), @(0, $x, 1), @($x, 0, 1), @(1, 0, $x))[[int][math]::Floor($h)]
    return ConvertTo-HexColor @(($rgb[0] * 255), ($rgb[1] * 255), ($rgb[2] * 255))
}

# One frame of the effect at time $T (0 to 1): the colors swing around the color wheel and the background
# is washed with a sweeping rainbow tint, both dying away like the coil's current (vscode/degauss.js).
function Get-DegaussSequence($Colors, [double]$T) {
    $strength = (1 - $T) * (1 - $T)
    $hue = 240 * $strength * [math]::Sin(2 * [math]::PI * 4 * $T)
    $tint = Get-RainbowColor (720 * $T)
    $sequence = ''
    if ($Colors.Ansi) {
        for ($i = 0; $i -lt 16; $i++) {
            if ($Colors.Ansi[$i]) { $sequence += "$Esc]4;$i;$(Format-OscColor (Get-RotatedColor $Colors.Ansi[$i] $hue))$St" }
        }
    }
    $sequence += "$Esc]10;$(Format-OscColor (Get-RotatedColor $Colors.Foreground $hue))$St"
    $sequence += "$Esc]11;$(Format-OscColor (Get-MixedColor $Colors.Background $tint (0.3 * $strength)))$St"
    $sequence += "$Esc]12;$(Format-OscColor (Get-RotatedColor $Colors.Cursor $hue))$St"
    return $sequence
}

# Console colors (the order of [ConsoleColor]) as ANSI color numbers (the order of SGR 30-37 and 90-97).
$script:ConsoleToAnsi = @(0, 4, 2, 6, 1, 5, 3, 7, 8, 12, 10, 14, 9, 13, 11, 15)

function Get-SgrColor([int]$Color, [bool]$Background) {
    # Gray text on black is how the console reports the terminal's default colors.
    if ($Background -and $Color -eq 0) { return 49 }
    if (-not $Background -and $Color -eq 7) { return 39 }
    $ansi = $script:ConsoleToAnsi[$Color]
    $base = if ($ansi -lt 8) { 30 } else { 90 }   # 30-37, or 90-97 for the bright ones
    if ($Background) { $base += 10 }
    return $base + ($ansi % 8)
}

# The screen as lines of text with SGR color sequences, for redrawing it. Trailing blanks are dropped.
function ConvertFrom-ScreenCells($Cells) {
    $height = $Cells.GetLength(0)
    $width = $Cells.GetLength(1)
    $lines = New-Object 'string[]' $height
    for ($y = 0; $y -lt $height; $y++) {
        # The last cell that isn't a blank on the default background.
        $last = -1
        for ($x = $width - 1; $x -ge 0; $x--) {
            $cell = $Cells[$y, $x]
            if (($cell.Character -ne ' ' -and $cell.Character -ne [char]0) -or [int]$cell.BackgroundColor -ne 0) { $last = $x; break }
        }
        $line = New-Object System.Text.StringBuilder
        $colors = -1   # the current foreground and background, as one number
        for ($x = 0; $x -le $last; $x++) {
            $cell = $Cells[$y, $x]
            if ($cell.BufferCellType -eq 'Trailing') { continue }   # the right half of a wide character
            $next = 16 * [int]$cell.ForegroundColor + [int]$cell.BackgroundColor
            if ($next -ne $colors) {
                [void]$line.Append("$Esc[$(Get-SgrColor ([int]$cell.ForegroundColor) $false);$(Get-SgrColor ([int]$cell.BackgroundColor) $true)m")
                $colors = $next
            }
            $character = if ($cell.Character -eq [char]0) { ' ' } else { $cell.Character }
            [void]$line.Append($character)
        }
        if ($colors -ge 0) { [void]$line.Append("$Esc[0m") }
        $lines[$y] = $line.ToString()
    }
    return @{ Lines = $lines; Width = $width; Height = $height }
}

# One frame of the picture at time $T (0 to 1), redrawn on the alternate screen: each line shifted right by a
# wave that dies away, like vscode/degauss.js's wobble. The first frames jolt down a line, like the picture
# jumping when the coil fires.
function Get-WobbleFrame($Screen, [double]$T, [int]$Frame) {
    $strength = (1 - $T) * (1 - $T)
    $jolt = if ($Frame -lt 2) { 1 } else { 0 }
    $out = New-Object System.Text.StringBuilder
    if ($jolt) { [void]$out.Append("$Esc[1;1H$Esc[0m$Esc[2K") }
    for ($y = 0; $y + $jolt -lt $Screen.Height; $y++) {
        $wave = $script:DegaussWobbleColumns * $strength * (1 + [math]::Sin(2 * [math]::PI * ($y / 10 + 5 * $T)))
        $offset = [int][math]::Floor($wave + 0.5)
        [void]$out.Append("$Esc[$($y + $jolt + 1);1H$Esc[0m$Esc[2K")
        if ($offset) { [void]$out.Append(' ' * $offset) }
        [void]$out.Append($Screen.Lines[$y])
    }
    return $out.ToString()
}

# Onto the alternate screen (the real one, scrollback and all, is left untouched), cursor hidden, and no
# wrapping, so lines shifted past the right edge are cut off. And back again.
$script:EnterWobble = "$Esc[?1049h$Esc[?25l$Esc[?7l"
$script:LeaveWobble = "$Esc[0m$Esc[?7h$Esc[?1049l$Esc[?25h"

function Invoke-Degauss {
    <#
    .SYNOPSIS
    Degausses the terminal, like the button on a CRT monitor: a thunk, a hum, and a second of wobbling, swirling colors. Alias: degauss.
    .DESCRIPTION
    Works in any terminal tab. Where the screen can be read (Windows Terminal, the Windows console), the
    picture wobbles too; it's redrawn on the alternate screen, so nothing on the real one changes. Like the
    real thing, it also fixes the colors: afterwards the tab is back to its own colors, including ones
    Windows Terminal threw away (for example when you switch input languages).
    .PARAMETER Quiet
    Without the sound.
    .EXAMPLE
    degauss
    #>
    [CmdletBinding()]
    param([switch]$Quiet)
    $colors = Get-TabColors
    # The picture wobbles where the screen can be read; elsewhere only the colors swirl.
    $screen = $null
    try { $screen = ConvertFrom-ScreenCells (& $script:GetScreenCells) } catch { Write-Verbose "Colors only: $_" }
    # Worked out before the sound starts, so the frames keep up with it.
    $frames = for ($i = 0; $i -lt $script:DegaussFrames; $i++) {
        $t = $i / $script:DegaussFrames
        $frame = Get-DegaussSequence $colors $t
        if ($screen) { $frame += Get-WobbleFrame $screen $t $i }
        $frame
    }
    if (-not $Quiet) {
        try { & $script:PlaySound (Join-Path $script:ModuleRoot 'degauss.wav') } catch { Write-Verbose "No sound: $_" }
    }
    try {
        if ($screen) { Write-TerminalSequence $script:EnterWobble }
        foreach ($frame in $frames) {
            Write-TerminalSequence $frame
            if ($script:DegaussFrameMs) { Start-Sleep -Milliseconds $script:DegaussFrameMs }
        }
    } finally {
        if ($screen) { Write-TerminalSequence $script:LeaveWobble }
        Write-TerminalSequence $script:ResetSequence
        if ($script:TabSequence) { Write-TerminalSequence $script:TabSequence }
    }
}

function Initialize-DegaussTab {
    <#
    .SYNOPSIS
    Sets up a Degauss tab when it opens. The Degauss profiles run it; you don't need to.
    .PARAMETER Look
    The look the Degauss profile was made from (the other profiles are found by their GUID).
    #>
    [CmdletBinding()]
    param([string]$Look)
    $target = if ($Look) { Find-DegaussLook $Look } else { Get-CurrentLook }
    if (-not $target) { return }
    # Remember the look for `color`, which otherwise goes by the profile's GUID.
    $env:DEGAUSS_LOOK = $target.id

    # Windows Terminal reads the Degauss profile when it starts, so after a new default look it keeps
    # opening the old one until it's restarted.
    $prefs = Get-DegaussPreference
    if ($Look) {
        $default = Find-DegaussLook (Get-DefaultLookId $prefs)
        if ($default.id -ne $target.id) {
            Write-Host "Your default look is now $($default.name), but Windows Terminal still has $($target.name) loaded for the Degauss profile. Close all Windows Terminal windows and reopen it to switch." -ForegroundColor Yellow
        }
    }

    $spec = $null
    # A color handed over by `look -Color`, if it's for this look and fresh.
    $pending = Join-Path $script:DataDir 'pending-color'
    if (Test-Path $pending) {
        $parts = (Get-Content $pending -Raw).Trim() -split '\|'
        if ($parts[0] -eq $target.id -and ((Get-Date).ToUniversalTime().Ticks - [long]$parts[2]) -lt [TimeSpan]::FromMinutes(1).Ticks) {
            $spec = $parts[1]
        }
        Remove-Item $pending -Force -ErrorAction SilentlyContinue
    }
    if (-not $spec) { $spec = $prefs.colors[$target.id] }
    if ($spec) {
        $sequence = Get-SpecSequence (ConvertFrom-ColorSpec $spec) $target
        Write-TerminalSequence $sequence
        Set-TabColorState $sequence
    }
}

function Set-DegaussLook {
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
    Open the tab in this color: a preset, #RRGGBB or a DOS code (see Set-DegaussColor).
    .PARAMETER SetAsDefault
    Also make this look (and -Color, if given) your default: what `look` opens without arguments, and what
    the Degauss profile in Windows Terminal's menu opens (after a Windows Terminal restart).
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
        Write-Host "This terminal follows the VS Code look. Use 'Degauss: Choose Look...' in VS Code's Command Palette."
        return
    }
    # Only Windows Terminal can open a tab with a look. Elsewhere, explain (and still allow -SetAsDefault).
    $inTerminal = [bool]$env:WT_SESSION
    if (-not $inTerminal -and -not $SetAsDefault) {
        Write-NotInTerminal
        return
    }
    if ($inTerminal -and -not $Off -and -not (Confirm-DegaussSetup)) { return }

    $target = $null
    if (-not $Off) {
        $prefs = Get-DegaussPreference
        $name = $Look
        if (-not $name) { $name = Get-DefaultLookId $prefs }
        $target = Find-DegaussLook $name
        if (-not $target) { throw "Unknown look '$name'. Looks: $((Get-LookNames) -join ', ')." }
        $parsed = $null
        if ($Color) { $parsed = ConvertFrom-ColorSpec $Color }
        if ($SetAsDefault) {
            $previous = Get-DefaultLookId $prefs
            $prefs.defaultLook = $target.id
            if ($parsed) { $prefs.colors[$target.id] = $parsed.Stored }
            Save-DegaussPreference $prefs
            $installed = Test-Path (Join-Path $script:FragmentDir 'degauss.json')
            if ($installed) { Write-DegaussFragment $prefs }
            $color = $prefs.colors[$target.id]
            if (-not $color) { $color = $target.defaultColor }
            Write-Host "Default look: $($target.name)$(if ($color) { " ($color)" })."
            if ($installed -and $previous -ne $target.id) {
                Write-Host 'The Degauss profile in Windows Terminal switches to it after you restart Windows Terminal (close all its windows).'
            }
        }
    }

    if (-not $inTerminal) { return }   # -SetAsDefault outside Windows Terminal: saved, nothing to open
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

function Get-DegaussLook {
    <#
    .SYNOPSIS
    Lists the looks, with the names Set-DegaussLook accepts and your default colors.
    #>
    [CmdletBinding()]
    param()
    $prefs = Get-DegaussPreference
    $current = Get-CurrentLook
    foreach ($look in Get-LookData) {
        $color = $prefs.colors[$look.id]
        if (-not $color) { $color = $look.defaultColor }
        [pscustomobject]@{
            Name    = $look.name
            Look    = @($look.aliases)[0]
            Aliases = @($look.aliases) -join ', '
            Color   = $color
            Default = (Get-DefaultLookId $prefs) -eq $look.id
            Current = $current -and $current.id -eq $look.id
        }
    }
}

function Install-Degauss {
    <#
    .SYNOPSIS
    Installs the Degauss fonts and adds the looks to Windows Terminal.
    .DESCRIPTION
    Installs the fonts for the current user (no admin needed) and writes a Windows Terminal fragment: one
    visible profile, Degauss, which opens your default look (make it Windows Terminal's default profile
    if you like), and a hidden profile per look, which Set-DegaussLook (alias look) opens. Pixel fonts are
    sized for the display's scaling so they stay sharp. Restart Windows Terminal afterwards. Running it
    again updates an existing installation.
    .PARAMETER KeepFontSizes
    Use the profiles' nominal font sizes instead of the sharpest sizes for this display's scaling.
    .PARAMETER ShowProfiles
    Also show every look in Windows Terminal's profile menu.
    #>
    [CmdletBinding()]
    param([switch]$KeepFontSizes, [switch]$ShowProfiles)

    Install-DegaussFont
    Add-FontMarker

    $prefs = Get-DegaussPreference
    $prefs.showProfiles = [bool]$ShowProfiles
    $prefs.keepFontSizes = [bool]$KeepFontSizes
    $prefs.installedVersion = Get-ModuleVersion
    Save-DegaussPreference $prefs
    Write-DegaussFragment $prefs

    if (-not (& $script:IsTerminalInstalled)) {
        Write-Warning 'Windows Terminal is not installed, and the looks need it. The fonts are installed anyway. Get Windows Terminal from the Microsoft Store, or with: winget install Microsoft.WindowsTerminal'
        return
    }
    Write-Host ''
    Write-Host 'Degauss installed. Close all Windows Terminal windows and reopen it. Then open the'
    Write-Host "Degauss profile from Terminal's menu, or type, in any PowerShell tab:"
    Write-Host "  look apple         (or: $((Get-LookNames) -join ', '))"
    Write-Host '  color amber        (or #RRGGBB, or a DOS code like 0A)'
    Write-Host 'Get-DegaussLook lists the looks.'
}

function Uninstall-Degauss {
    <#
    .SYNOPSIS
    Removes the looks from Windows Terminal, and the fonts unless something else still uses them.
    .PARAMETER RemoveFonts
    Remove the fonts even if the Degauss VS Code extension still uses them.
    #>
    [CmdletBinding()]
    param([switch]$RemoveFonts)

    if (Test-Path $script:FragmentDir) { Remove-Item $script:FragmentDir -Recurse -Force }
    foreach ($file in 'terminal.json', 'pending-color') {
        Remove-Item (Join-Path $script:DataDir $file) -Force -ErrorAction SilentlyContinue
    }
    Remove-PromptHook
    Write-Host 'Removed the looks from Windows Terminal.'

    Remove-FontMarker
    $others = @(Get-OtherFontUser)
    if ($others.Count -and -not $RemoveFonts) {
        $names = ($others | ForEach-Object { if ($script:UserNames[$_]) { $script:UserNames[$_] } else { $_ } }) -join ', '
        Write-Host "Kept the fonts: $names still uses them (-RemoveFonts removes them anyway)."
    } else {
        Uninstall-DegaussFont
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
Register-ArgumentCompleter -CommandName Set-DegaussLook -ParameterName Look -ScriptBlock $lookCompleter
Register-ArgumentCompleter -CommandName Set-DegaussLook -ParameterName Color -ScriptBlock $colorCompleter
Register-ArgumentCompleter -CommandName Set-DegaussColor -ParameterName Color -ScriptBlock $colorCompleter

Set-Alias -Name look -Value Set-DegaussLook
Set-Alias -Name color -Value Set-DegaussColor
Set-Alias -Name degauss -Value Invoke-Degauss

Export-ModuleMember -Function Install-Degauss, Uninstall-Degauss, Set-DegaussLook, Set-DegaussColor, Get-DegaussLook, Initialize-DegaussTab, Invoke-Degauss -Alias look, color, degauss
