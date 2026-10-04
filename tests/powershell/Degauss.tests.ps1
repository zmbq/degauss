# Tests the Degauss PowerShell module and its installer from the build output (dist/powershell), in
# Windows PowerShell 5.1 and PowerShell 7. Everything is redirected to a temporary folder and a throwaway
# registry key, wt.exe is replaced by a fake, and color sequences are captured instead of written, so it's
# safe to run on a developer machine. Build first (`npm test` or `node tools/build.mjs`).
#   pwsh -File tests/powershell/Degauss.tests.ps1
param([switch]$Inner)   # set when the script re-runs itself inside each PowerShell
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$package = Join-Path $root 'dist\powershell'
if (-not (Test-Path (Join-Path $package 'Degauss\Degauss.psd1'))) { throw "Build first: $package is missing." }

if (-not $Inner) {
    $failed = @()
    foreach ($shell in @('powershell', 'pwsh') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue }) {
        Write-Host "== $shell"
        & $shell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Inner
        if ($LASTEXITCODE -ne 0) { $failed += $shell }
    }
    if ($failed) { throw "Degauss tests failed in: $($failed -join ', ')" }
    Write-Host 'All Degauss tests passed.'
    return
}

# ---------- inside one PowerShell ----------
$script:failures = 0
function Check([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "  ok   $Message" } else { Write-Host "  FAIL $Message" -ForegroundColor Red; $script:failures++ }
}
function Throws([scriptblock]$Block, [string]$Pattern, [string]$Message) {
    try { & $Block; Check $false "$Message (no error)" } catch { Check ($_.Exception.Message -match $Pattern) "$Message ($($_.Exception.Message))" }
}

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('degauss-test-' + [guid]::NewGuid())
$testKey = "HKCU:\SOFTWARE\DegaussTest-$([guid]::NewGuid())"
$paths = @{
    Fonts    = Join-Path $sandbox 'fonts'
    FontKey  = "$testKey\Fonts"
    Fragment = Join-Path $sandbox 'Fragments\Degauss'
    Data     = Join-Path $sandbox 'Degauss'
}
$fragmentFile = Join-Path $paths.Fragment 'degauss.json'
$prefsFile = Join-Path $paths.Data 'terminal.json'
New-Item -ItemType Directory -Force $sandbox | Out-Null
$savedEnv = @{ WT_SESSION = $env:WT_SESSION; WT_PROFILE_ID = $env:WT_PROFILE_ID; TERM_PROGRAM = $env:TERM_PROGRAM; DEGAUSS_LOOK = $env:DEGAUSS_LOOK }
$env:DEGAUSS_LOOK = $null

try {
    Import-Module (Join-Path $package 'Degauss\Degauss.psd1') -Force
    $module = Get-Module Degauss
    & $module {
        param($p)
        $script:FontDir = $p.Fonts; $script:FontKey = $p.FontKey; $script:FragmentDir = $p.Fragment
        $script:DataDir = $p.Data; $script:FontUsersDir = Join-Path $p.Data 'font-users'
        # Capture color sequences and wt.exe calls instead of performing them.
        $script:Written = @()
        function script:Write-TerminalSequence([string]$Sequence) { $script:Written += $Sequence }
        $script:WtCalls = @()
        $script:WtCommand = { $script:WtCalls += , @($args) }
        # Scripted answers to yes/no questions (none queued means no).
        $script:Answers = New-Object System.Collections.Queue
        $script:Questions = @()
        $script:AskUser = { param($q) $script:Questions += $q; if ($script:Answers.Count) { $script:Answers.Dequeue() } else { $false } }
        $script:IsTerminalInstalled = { $true }
        # Degauss tabs run PowerShell 7 unless a test says it lacks the module.
        $script:RealPwshHasModule = $script:PwshHasModule
        $script:PwshHasModule = { $true }
        # No sound and no waiting for degauss.
        $script:Played = @()
        $script:PlaySound = { param($f) $script:Played += $f }
        $script:DegaussFrameMs = 0
        # The tests' host has no screen to read: degauss only swirls the colors, unless a test fakes one.
        $script:GetScreenCells = { throw 'No screen in the tests.' }
    } $paths
    $inModule = { param($block, $arg1, $arg2) & $module $block $arg1 $arg2 }
    $fonts = & $module { Get-DegaussFont }
    $looks = @(& $module { Get-LookData })
    $lookById = @{}; foreach ($l in $looks) { $lookById[$l.id] = $l }
    $registered = { $k = Get-ItemProperty $paths.FontKey -ErrorAction SilentlyContinue; @($fonts | Where-Object { $k -and $k.($_.registryName) }) }
    $ownMarker = Join-Path $paths.Data 'font-users\powershell'
    $vscodeMarker = Join-Path $paths.Data 'font-users\vscode'   # what the VS Code extension leaves (vscode/fonts.js)
    $written = { & $module { $script:Written -join '' } }
    $clearWritten = { & $module { $script:Written = @() } }
    $wtCalls = { & $module { $script:WtCalls } }
    $clearWt = { & $module { $script:WtCalls = @() } }
    $degaussGuid = & $module { $script:DegaussProfileGuid }
    $originalPrompt = (Get-Command prompt).ScriptBlock.ToString()
    $profileScheme = { param($id) ((Get-Content $fragmentFile -Raw | ConvertFrom-Json).profiles | Where-Object guid -eq $lookById[$id].guid).colorScheme }
    $fragmentScheme = { param($name) (Get-Content $fragmentFile -Raw | ConvertFrom-Json).schemes | Where-Object name -eq $name }
    $lookProfiles = { param($f) @($f.profiles | Where-Object { $_.guid -ne $degaussGuid }) }
    $degaussProfile = { param($f) $f.profiles | Where-Object { $_.guid -eq $degaussGuid } }

    Write-Host '-- first use'
    $answer = { param($yes) & $module { param($a) $script:Answers.Enqueue($a) } $yes }
    $questions = { & $module { $script:Questions } }
    $env:WT_SESSION = 'test'; $env:TERM_PROGRAM = $null
    Push-Location $sandbox
    & $clearWritten
    color amber
    Check ((& $written) -match '\]4;0;rgb:') 'color works before any setup'
    & $answer $false
    look apple -KeepTab 6>$null
    Check ((@(& $questions) -join ' ') -match "isn't set up yet") 'the first look offers to set up'
    Check (-not (Test-Path $fragmentFile) -and (& $registered).Count -eq 0 -and @(& $wtCalls).Count -eq 0) 'declining leaves everything untouched'
    & $answer $true
    $message = look apple -KeepTab 6>&1 | Out-String -Width 4096
    Check ((Test-Path $fragmentFile) -and (& $registered).Count -eq $fonts.Count) 'accepting installs the fonts and Terminal profiles'
    Check (@(& $wtCalls).Count -eq 0 -and $message -match 'Restart Windows Terminal') '... and asks for a Terminal restart instead of opening a tab Terminal cannot know yet'
    $asked = @(& $questions).Count
    look apple -KeepTab
    Check (@(& $wtCalls).Count -eq 1 -and @(& $questions).Count -eq $asked) 'once set up, look just works'
    & $module { $p = Get-DegaussPreference; $p.installedVersion = '0.0.1'; Save-DegaussPreference $p }
    & $answer $true
    & $clearWt
    $message = look apple -KeepTab 6>&1 | Out-String -Width 4096
    Check ((@(& $questions)[-1]) -match 'updated \(0\.0\.1 to ') 'after an update, look offers to refresh the setup'
    Check ((Get-Content $prefsFile -Raw | ConvertFrom-Json).installedVersion -eq (& $module { Get-ModuleVersion }) -and @(& $wtCalls).Count -eq 1) '... refreshes it and carries on'
    & $clearWt
    look -Off -KeepTab
    Check (@(& $wtCalls).Count -eq 1) 'look -Off never needs setup'
    Pop-Location
    Uninstall-Degauss 6>$null | Out-Null
    $env:WT_SESSION = $null

    Write-Host '-- Install-Degauss'
    Install-Degauss 6>$null | Out-Null
    foreach ($font in $fonts) {
        $value = (Get-ItemProperty $paths.FontKey).($font.registryName)
        Check ($value -eq (Join-Path $paths.Fonts $font.installedFile) -and (Test-Path $value)) "font registered and copied: $($font.family)"
    }
    Check (Test-Path $fragmentFile) 'Terminal fragment written'
    Check ((Test-Path $ownMarker) -and ((Get-Content $ownMarker -Raw) -match 'Degauss module \d')) 'font-user marker written'
    $fragment = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    $schemes = @($fragment.schemes | ForEach-Object { $_.name })
    $dpi = & $module { Get-DisplayDpi }
    $visible = & $degaussProfile $fragment
    Check ($visible -and $visible.name -eq 'Degauss' -and $visible.hidden -eq $false) 'one visible Degauss profile'
    Check ($visible.commandline -match 'Initialize-DegaussTab -Look apple2e$' -and $visible.font.face -eq 'PR Number 3') 'it opens the default look (Apple //e)'
    Check ((& $lookProfiles $fragment).Count -eq $looks.Count) 'plus a profile per look'
    Check (@($fragment.profiles | Where-Object { $_.commandline -notmatch '^pwsh\.exe ' }).Count -eq 0) 'tabs run PowerShell 7 when it has the module'
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Check (& $module { & $script:RealPwshHasModule }) '... which it always has when PowerShell 7 runs the setup'
    }
    & $module { $script:PwshHasModule = { $false } }
    Install-Degauss 6>$null | Out-Null
    $fallback = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    Check (@($fallback.profiles | Where-Object { $_.commandline -notmatch '^powershell\.exe ' }).Count -eq 0) "tabs run Windows PowerShell when PowerShell 7 doesn't have the module (e.g. Install-Module from Windows PowerShell)"
    & $module { $script:PwshHasModule = { $true } }
    Install-Degauss 6>$null | Out-Null
    foreach ($terminalProfile in & $lookProfiles $fragment) {
        Check ($terminalProfile.commandline -match '^(pwsh|powershell)\.exe -NoLogo -NoExit -Command Initialize-DegaussTab$') "$($terminalProfile.name): runs Initialize-DegaussTab"
        Check ($terminalProfile.hidden -eq $true) "$($terminalProfile.name): hidden"
        Check ($schemes -contains $terminalProfile.colorScheme) "$($terminalProfile.name): color scheme '$($terminalProfile.colorScheme)' exists"
        $grid = ($fonts | Where-Object family -eq $terminalProfile.font.face).pixelsPerEm
        if ($grid) {
            $pixelsPerDot = $terminalProfile.font.size * $dpi / 72 / $grid
            Check ([math]::Abs($pixelsPerDot - [math]::Round($pixelsPerDot)) -lt 0.001) "$($terminalProfile.name): $($terminalProfile.font.size)pt is sharp at $dpi DPI"
        }
    }
    Install-Degauss -ShowProfiles -KeepFontSizes 6>$null | Out-Null
    $fragment = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    Check (@($fragment.profiles | Where-Object hidden).Count -eq 0) '-ShowProfiles shows the profiles'
    $source = Get-Content (Join-Path $package 'Degauss\degauss.json') -Raw | ConvertFrom-Json
    Check ((@(& $lookProfiles $fragment | ForEach-Object { $_.font.size }) -join ',') -eq (@($source.profiles | ForEach-Object { $_.font.size }) -join ',')) '-KeepFontSizes keeps nominal sizes'

    Write-Host '-- colors match the VS Code extension (vscode/palette.js)'
    $diffs = 0; $count = 0
    foreach ($look in $looks | Where-Object monochrome) {
        foreach ($preset in (& $module { Get-PaletteData }).presets.PSObject.Properties) {
            $name = "$($look.name) " + $preset.Name.Substring(0, 1).ToUpper() + $preset.Name.Substring(1)
            $expected = $source.schemes | Where-Object name -eq $name
            $actual = & $inModule { param($s, $c) Get-DegaussScheme $s $c } $look.colorStyle $preset.Value
            foreach ($key in $actual.Keys) { $count++; if ($actual[$key] -ne $expected.$key) { $diffs++ } }
        }
    }
    Check ($count -gt 0 -and $diffs -eq 0) "preset schemes identical to the build's ($count colors)"
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $palette = (Join-Path $root 'vscode\palette.js').Replace('\', '/')
        foreach ($custom in '#40E0FF', '#102030', '#FF00FF') {
            $js = node -e "const p=require('$palette'); console.log(JSON.stringify(p.phosphorPalette(p.resolveColor('$custom'))))" | ConvertFrom-Json
            $ps = & $inModule { param($c) Get-PhosphorPalette (Resolve-DegaussColor $c) } $custom
            $bad = @($ps.Keys | Where-Object { $ps[$_] -ne $js.$_ })
            Check ($bad.Count -eq 0) "custom $custom palette identical to palette.js$(if ($bad) { ': ' + ($bad -join ', ') })"
        }
    }

    Write-Host '-- color specs'
    $spec = { param($s) & $module { param($x) ConvertFrom-ColorSpec $x } $s }
    Check ((& $spec 'AMBER').Stored -eq 'amber') 'preset names in any case'
    Check ((& $spec '40e0ff').Stored -eq '#40E0FF') 'RGB with or without #'
    Check ((& $spec '#102030').Phosphor -eq (& $inModule { param($c) Resolve-DegaussColor $c } '#102030')) 'dark colors brightened'
    $dosGreen = & $spec '0A'
    Check ($dosGreen.Phosphor -eq (& $inModule { param($c) Resolve-DegaussColor $c } 'green') -and $dosGreen.Stored -eq '0A') 'DOS 0A is the green phosphor'
    Check ((& $spec 'e').Stored -eq '0E') 'one DOS digit means a black background'
    $dosBlue = & $spec '1f'
    Check ($dosBlue.Foreground -eq '#FFFFFF' -and $dosBlue.Background -eq '#0000AA' -and -not $dosBlue.Phosphor) 'DOS 1F is white on blue'
    Throws { & $spec '11' } 'same' 'DOS rejects the same text and background color'
    Throws { & $spec 'purple' } 'Unknown color' 'unknown names are rejected'
    Throws { & $spec '#000000' } 'black' 'black is rejected'

    Write-Host '-- Set-DegaussColor'
    $env:WT_SESSION = 'test'; $env:TERM_PROGRAM = $null
    $env:WT_PROFILE_ID = $lookById['apple2e'].guid
    & $clearWritten
    color amber
    $amber = & $inModule { param($c) Get-ColorSequence (Get-DegaussScheme 'phosphor' (Resolve-DegaussColor $c)) } 'amber'
    Check ((& $written) -eq $amber) 'color amber recolors an Apple //e tab with the amber phosphor palette'
    Check (([regex]::Matches((& $written), "\]4;\d+;rgb:")).Count -eq 16) 'all 16 ANSI colors are set'
    $env:WT_PROFILE_ID = $lookById['ibm-3270'].guid
    & $clearWritten
    color amber
    $intensity = & $inModule { param($c) Get-ColorSequence (Get-DegaussScheme 'intensity' (Resolve-DegaussColor $c)) } 'amber'
    Check ((& $written) -eq $intensity) 'in a 3270 tab, amber keeps the two brightness levels'
    & $clearWritten
    color 1F
    Check ((& $written) -match '\]10;rgb:ff/ff/ff' -and (& $written) -match '\]11;rgb:00/00/aa' -and (& $written) -notmatch '\]4;') 'DOS 1F sets only text and background'
    & $clearWritten
    color
    Check ((& $written) -eq (& $module { $script:ResetSequence })) 'color alone resets the tab'
    Throws { color nonsense } 'Unknown color' 'bad colors are reported'

    Write-Host '-- defaults and new tabs'
    $env:WT_PROFILE_ID = $lookById['apple2e'].guid
    $message = color cyan -SetAsDefault 6>&1 | Out-String -Width 4096
    Check ((Get-Content $prefsFile -Raw | ConvertFrom-Json).colors.apple2e -eq 'cyan') '-SetAsDefault saves the color for the look'
    Check ((& $profileScheme 'apple2e') -eq 'Apple //e Cyan') "... and the look's Terminal profile uses it, so Terminal's color resets land on it"
    Check ((& $degaussProfile (Get-Content $fragmentFile -Raw | ConvertFrom-Json)).colorScheme -eq 'Apple //e Cyan') '... and so does the Degauss profile'
    Check ($message -match 'Restart Windows Terminal') '... after a Terminal restart, which it mentions'
    & $clearWritten
    Initialize-DegaussTab
    $cyan = & $inModule { param($c) Get-ColorSequence (Get-DegaussScheme 'phosphor' (Resolve-DegaussColor $c)) } 'cyan'
    Check ((& $written) -eq $cyan) 'a new tab of the look opens in the saved color'
    & $clearWritten
    color
    Check ((& $written) -eq ((& $module { $script:ResetSequence }) + $cyan)) 'color alone goes back to the saved default'
    color '#40E0FF' -SetAsDefault 6>$null
    $customScheme = & $fragmentScheme 'Apple //e Custom'
    $expected = & $inModule { param($c) Get-DegaussScheme 'phosphor' (Resolve-DegaussColor $c) } '#40E0FF'
    Check ((& $profileScheme 'apple2e') -eq 'Apple //e Custom' -and $customScheme.background -eq $expected.background -and $customScheme.brightWhite -eq $expected.brightWhite) 'a custom default gets its own Terminal scheme'
    $env:DEGAUSS_LOOK = 'ibm-3270'
    color 1F -SetAsDefault 6>$null
    $dosScheme = & $fragmentScheme 'IBM 3270 Custom'
    Check ((& $profileScheme 'ibm-3270') -eq 'IBM 3270 Custom' -and $dosScheme.background -eq '#0000AA' -and $dosScheme.foreground -eq '#FFFFFF' -and $dosScheme.red -eq '#FF3030') 'a DOS default keeps the look''s colors with DOS''s text and background'
    color -SetAsDefault 6>$null
    Check ((& $profileScheme 'ibm-3270') -eq 'IBM 3270') '... and forgetting it restores the look''s own scheme'
    $env:DEGAUSS_LOOK = 'apple2e'
    color -SetAsDefault 6>$null
    Check (-not (Get-Content $prefsFile -Raw | ConvertFrom-Json).colors.apple2e) 'color -SetAsDefault alone forgets the saved color'
    Check ((& $profileScheme 'apple2e') -eq 'Apple //e Green') '... and the profile goes back to the built-in scheme'

    Write-Host '-- colors survive Windows Terminal resets (input language switches)'
    color cyan
    & $clearWritten
    $shown = prompt
    Check ((& $written) -eq $cyan -and $shown -eq (& ([scriptblock]::Create($originalPrompt)))) "the prompt re-sends the tab's color, and still shows the user's own prompt"
    color amber
    color amber
    & $clearWritten
    prompt | Out-Null
    Check ((& $written) -eq $amber) 'the latest color is re-sent (and the prompt is wrapped only once)'
    color
    & $clearWritten
    prompt | Out-Null
    Check (-not (& $written)) 'after color alone (no default), nothing is re-sent'
    Check ($env:DEGAUSS_LOOK -eq 'apple2e') 'the tab remembers its look'
    $env:WT_PROFILE_ID = $null; $env:DEGAUSS_LOOK = $null
    Throws { color amber -SetAsDefault } 'Degauss tab' '-SetAsDefault outside a Degauss tab is refused'
    & $clearWritten
    color amber
    Check ((& $written) -eq $amber) 'outside Degauss tabs, color still works as a phosphor monitor'

    Write-Host '-- Invoke-Degauss'
    $reset = & $module { $script:ResetSequence }
    $frames = & $module { $script:DegaussFrames }
    & $clearWritten
    degauss
    $out = & $written
    $played = @(& $module { $script:Played })
    Check ($played.Count -eq 1 -and (Test-Path $played[0]) -and $played[0] -like '*degauss.wav') 'degauss plays the sound that ships with the module'
    Check ($out.EndsWith($reset + $amber)) '... and ends with the tab back in its own color'
    Check (([regex]::Matches($out, '\]10;')).Count -eq $frames + 1) "... after $frames frames"
    Check (([regex]::Matches($out, '\]4;\d+;')).Count -eq 16 * ($frames + 1)) '... that swirl all 16 colors of a recolored tab'
    $backgrounds = @([regex]::Matches($out, '\]11;(rgb:[^\x1b]+)') | ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique)
    Check ($backgrounds.Count -gt 10) "... and tint the background ($($backgrounds.Count) shades)"
    & $module { $script:Played = @() }
    degauss -Quiet
    Check (@(& $module { $script:Played }).Count -eq 0) 'degauss -Quiet makes no sound'
    color
    $env:WT_PROFILE_ID = $lookById['ibm-3270'].guid
    & $clearWritten
    degauss -Quiet
    $out = & $written
    Check ($out.EndsWith($reset)) 'in a tab with its default colors, degauss goes back to the profile colors'
    $scheme = & $inModule { param($l) Get-LookScheme $l } $lookById['ibm-3270']
    $first = & $inModule { param($c) Get-DegaussSequence $c 0 } (& $module { Get-TabColors })
    Check ($scheme -and $first -eq (& $inModule { param($s) Get-ColorSequence $s } $scheme).Replace(
        "]11;$(& $inModule { param($c) Format-OscColor $c } $scheme.background)", "]11;$(& $inModule { param($c) Format-OscColor (Get-MixedColor $c '#FF0000' 0.3) } $scheme.background)")) '... and swirls from the look''s own colors'
    $env:WT_PROFILE_ID = $null; $env:DEGAUSS_LOOK = $null
    & $clearWritten
    degauss -Quiet
    $out = & $written
    Check ($out -notmatch '\]4;' -and $out.EndsWith($reset)) 'in other tabs, degauss changes only the text and background, then resets them'
    Check ($out -notmatch '\[\?1049h') '... and, without a screen to read, never leaves it'

    Write-Host '-- degauss wobbles the picture'
    & $module {
        $cell = { param($c, $fg, $bg) New-Object System.Management.Automation.Host.BufferCell $c, $fg, $bg, 'Complete' }
        $cells = New-Object 'System.Management.Automation.Host.BufferCell[,]' 3, 8
        for ($y = 0; $y -lt 3; $y++) { for ($x = 0; $x -lt 8; $x++) { $cells[$y, $x] = & $cell ' ' 'Gray' 'Black' } }
        for ($x = 0; $x -lt 5; $x++) { $cells[0, $x] = & $cell 'PS C:'[$x] 'Gray' 'Black' }
        $cells[1, 0] = & $cell 'E' 'Red' 'Black'
        $cells[1, 1] = & $cell 'R' 'Yellow' 'DarkBlue'
        $script:TestCells = $cells
        $script:GetScreenCells = { , $script:TestCells }
    }
    $e = [char]27
    $screen = & $module { ConvertFrom-ScreenCells $script:TestCells }
    Check ($screen.Width -eq 8 -and $screen.Height -eq 3) 'the screen is read at its size'
    Check ($screen.Lines[0] -eq "$e[39;49mPS C:$e[0m") '... default colors stay default, trailing blanks are dropped'
    Check ($screen.Lines[1] -eq "$e[91;49mE$e[93;44mR$e[0m") '... console colors become ANSI colors'
    Check ($screen.Lines[2] -eq '') '... and blank lines are empty'
    & $clearWritten
    degauss -Quiet
    $out = & $written
    $enter = & $module { $script:EnterWobble }
    $leave = & $module { $script:LeaveWobble }
    Check ($out.StartsWith($enter)) 'degauss redraws the screen on the alternate screen'
    Check ($out.EndsWith($leave + $reset)) '... and goes back to the real one, and to the tab''s own colors'
    Check (([regex]::Matches($out, '\]10;')).Count -eq $frames) "... still swirling the colors, $frames frames"
    Check ($out -match "\[2;1H$e\[0m$e\[2K *$e\[39;49mPS C:") '... the picture jolts down a line when the coil fires'
    Check ($out -match "\[1;1H$e\[0m$e\[2K +$e\[39;49mPS C:") '... then the lines wobble'
    $last = $out.Substring($out.LastIndexOf("$e]10;"))
    Check ($last -match "\[1;1H$e\[0m$e\[2K$e\[39;49mPS C:") '... and settle'
    & $module { $script:GetScreenCells = { throw 'No screen in the tests.' } }
    color amber

    Write-Host '-- Set-DegaussLook'
    Push-Location $sandbox
    & $clearWt
    look apple -KeepTab
    $call = @(& $wtCalls)[0]
    Check (($call -join ' ') -eq "-w 0 nt -p $($lookById['apple2e'].guid) -d $sandbox") 'look apple opens an Apple //e tab in the current folder'
    & $clearWt
    look 3270mono -Color amber -KeepTab
    $pendingFile = Join-Path $paths.Data 'pending-color'
    Check ((@(& $wtCalls)[0] -join ' ') -match [regex]::Escape($lookById['ibm-3270-mono'].guid)) 'look 3270mono opens the 3270 Monochrome profile'
    Check ((Get-Content $pendingFile -Raw) -match '^ibm-3270-mono\|amber\|\d+$') '-Color is handed to the new tab'
    $env:WT_PROFILE_ID = $lookById['ibm-3270-mono'].guid
    & $clearWritten
    Initialize-DegaussTab
    $monoAmber = & $inModule { param($c) Get-ColorSequence (Get-DegaussScheme 'intensity' (Resolve-DegaussColor $c)) } 'amber'
    Check ((& $written) -eq $monoAmber -and -not (Test-Path $pendingFile)) 'the new tab applies it and clears the hand-over'
    $env:WT_PROFILE_ID = $null; $env:DEGAUSS_LOOK = $null
    & $clearWt
    look -Off -KeepTab
    Check ((@(& $wtCalls)[0] -join ' ') -eq "-w 0 nt -d $sandbox") 'look -Off opens a normal tab'
    & $clearWt
    $message = look ps2 -SetAsDefault -KeepTab 6>&1 | Out-String -Width 4096
    Check ((@(& $wtCalls)[0] -join ' ') -match [regex]::Escape($lookById['ibm-ps2-vga'].guid)) 'look -SetAsDefault also switches to the look'
    Check ($message -match 'Default look: IBM PS/2 VGA' -and $message -match 'restart Windows Terminal') 'and says the Degauss profile needs a Terminal restart'
    $fragment = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    $visible = & $degaussProfile $fragment
    Check ($visible.commandline -match '-Look ibm-ps2-vga$' -and $visible.font.face -eq 'PxPlus IBM VGA 9x16' -and $visible.guid -eq $degaussGuid) 'the Degauss profile now copies the new default, same GUID'
    Check (@($fragment.profiles | Where-Object hidden).Count -eq 0) 'Install-Degauss -ShowProfiles is remembered when the fragment is rewritten'
    $message = look ps2 -Color amber -SetAsDefault -KeepTab 6>&1 | Out-String -Width 4096
    Check ($message -match 'Default look: IBM PS/2 VGA \(amber\)' -and $message -notmatch 'restart') 'a new default color needs no restart'
    look -KeepTab
    Check ((@(& $wtCalls)[2] -join ' ') -match [regex]::Escape($lookById['ibm-ps2-vga'].guid)) 'look alone opens the default look'

    Write-Host '-- the Degauss profile'
    & $clearWritten
    $message = Initialize-DegaussTab -Look apple2e 6>&1 | Out-String -Width 4096
    Check ($message -match 'default look is now IBM PS/2 VGA' -and $message -match 'Apple //e') 'a tab from an outdated Degauss profile says a Terminal restart is pending'
    Check ($env:DEGAUSS_LOOK -eq 'apple2e') '... and still knows it shows Apple //e'
    $message = Initialize-DegaussTab -Look ibm-ps2-vga 6>&1 | Out-String -Width 4096
    Check (-not $message.Trim()) 'an up-to-date Degauss tab says nothing'
    $vgaAmber = & $inModule { param($c) Get-ColorSequence (Get-DegaussScheme 'luminance' (Resolve-DegaussColor $c)) } 'amber'
    Check ((& $written) -like "*$vgaAmber") '... and opens in the default color'
    $env:DEGAUSS_LOOK = $null
    Check (@(Get-DegaussLook | Where-Object Default).Name -eq 'IBM PS/2 VGA') 'Get-DegaussLook shows the default'
    Check (@(Get-DegaussLook).Count -eq $looks.Count) 'Get-DegaussLook lists every look'
    Throws { look nosuchlook -KeepTab } 'apple.*3270' 'unknown looks list the valid names'
    $env:TERM_PROGRAM = 'vscode'
    & $clearWt
    look apple -KeepTab 6>$null
    Check (@(& $wtCalls).Count -eq 0) "in VS Code's terminal, look only prints a hint"
    $env:TERM_PROGRAM = $null; $env:WT_SESSION = $null
    & $clearWt
    $asked = @(& $questions).Count
    $message = look apple -KeepTab 6>&1 | Out-String -Width 4096
    Check ($message -match "isn't Windows Terminal" -and $message -match 'color works here') 'outside Windows Terminal, look explains (and mentions color)'
    Check (@(& $wtCalls).Count -eq 0 -and @(& $questions).Count -eq $asked) '... without opening anything or offering setup'
    & $module { $script:IsTerminalInstalled = { $false } }
    $message = look apple -KeepTab 6>&1 | Out-String -Width 4096
    Check ($message -match "isn't installed" -and $message -match 'winget install Microsoft.WindowsTerminal') 'without Windows Terminal installed, look says how to get it'
    $message = look 3270 -SetAsDefault 6>&1 | Out-String -Width 4096
    Check ((Get-Content $prefsFile -Raw | ConvertFrom-Json).defaultLook -eq 'ibm-3270' -and $message -match 'Default look: IBM 3270') '-SetAsDefault still works outside Windows Terminal'
    & $module { $script:IsTerminalInstalled = { $true } }
    Pop-Location

    Write-Host '-- without Windows Terminal'
    & $module { $script:IsTerminalInstalled = { $false } }
    $warnings = Install-Degauss 6>$null 3>&1 | Out-String -Width 4096
    Check ($warnings -match 'Windows Terminal is not installed' -and (& $registered).Count -eq $fonts.Count) 'Install-Degauss warns, and installs the fonts anyway'
    & $module { $script:IsTerminalInstalled = { $true } }

    Write-Host '-- fonts shared with the VS Code extension'
    'Degauss for VS Code' | Set-Content $vscodeMarker
    $message = Uninstall-Degauss 6>&1 | Out-String -Width 4096
    Check (-not (Test-Path $paths.Fragment)) 'Terminal fragment removed'
    Check (-not (Test-Path $prefsFile)) 'preferences removed'
    Check (-not (Test-Path $ownMarker)) 'own marker removed'
    Check ((& $registered).Count -eq $fonts.Count) 'fonts kept while the VS Code extension uses them'
    Check ($message -match 'VS Code extension still uses them') 'user is told why'
    Check (Test-Path $vscodeMarker) "the extension's marker is left alone"
    Install-Degauss 6>$null | Out-Null
    Uninstall-Degauss -RemoveFonts 6>$null | Out-Null
    Check ((& $registered).Count -eq 0) '-RemoveFonts removes them anyway'
    Remove-Item $vscodeMarker
    Install-Degauss 6>$null | Out-Null
    $env:WT_SESSION = 'test'
    Push-Location $sandbox
    look apple -Color amber -SetAsDefault -KeepTab 6>$null
    Pop-Location
    Uninstall-Degauss 6>$null | Out-Null
    Check ((& $registered).Count -eq 0) 'fonts removed when nothing else uses them'
    Check (@(Get-ChildItem $paths.Fonts -ErrorAction SilentlyContinue).Count -eq 0) 'font files deleted'
    Check (-not (Test-Path $paths.Data)) 'no Degauss folder left behind'
    Check ((Get-Command prompt).ScriptBlock.ToString() -eq $originalPrompt) "the user's prompt function is back as it was"

    Write-Host '-- cleans up leftovers of older versions'
    New-Item -ItemType Directory -Force $paths.Fragment, $paths.Fonts | Out-Null
    '{}' | Set-Content $fragmentFile
    foreach ($name in 'Degauss-PRNumber3.ttf', 'Degauss-OldFont.ttf') {
        $file = Join-Path $paths.Fonts $name
        'x' | Set-Content $file
        Set-ItemProperty -Path $paths.FontKey -Name "$name (TrueType)" -Value $file
    }
    Uninstall-Degauss 6>$null | Out-Null
    Check (-not (Test-Path $paths.Fragment)) 'old fragment removed'
    $left = @((Get-ItemProperty $paths.FontKey).PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
    Check ($left.Count -eq 0) 'old fonts unregistered, including ones no longer shipped'

    Write-Host '-- sharp point sizes'
    $sharp = { param($pt, $d) & $module { param($a, $b) Get-SharpPoints $a 16 $b } $pt $d }
    Check ((& $sharp 16 144) -eq 16) '16pt at 144 DPI stays 16pt'
    Check ((& $sharp 12 144) -eq 16) '12pt at 144 DPI becomes 16pt'
    Check ((& $sharp 16 96) -eq 12) '16pt at 96 DPI becomes 12pt'
    foreach ($d in 96, 120, 144, 168, 192) {
        foreach ($pt in 12, 14, 16) {
            $s = & $sharp $pt $d
            $dots = $s * $d / 72 / 16
            Check ([math]::Abs($dots - [math]::Round($dots)) -lt 0.001) "$pt pt at $d DPI -> $s pt is sharp"
        }
    }

    Write-Host '-- install.ps1 (module copy only)'
    $modules = Join-Path $sandbox 'modules'
    & (Join-Path $package 'install.ps1') -ModulesRoot $modules -NoRun 6>$null | Out-Null
    $version = (Import-PowerShellDataFile (Join-Path $package 'Degauss\Degauss.psd1')).ModuleVersion
    Check (Test-Path (Join-Path $modules "Degauss\$version\Degauss.psd1")) "module installed as Degauss\$version"
    Check (Test-Path (Join-Path $modules "Degauss\$version\looks.json")) 'module data copied'
    & (Join-Path $package 'install.ps1') -ModulesRoot $modules -NoRun 6>$null | Out-Null
    Check (@(Get-ChildItem (Join-Path $modules 'Degauss')).Count -eq 1) 'reinstalling replaces the old copy'
    & (Join-Path $package 'install.ps1') -ModulesRoot $modules -NoRun -Uninstall 6>$null | Out-Null
    Check (-not (Test-Path (Join-Path $modules 'Degauss'))) 'uninstall removes the module'
} catch {
    Write-Host "  FAIL $($_.Exception.Message) ($($_.InvocationInfo.PositionMessage))" -ForegroundColor Red
    $script:failures++
} finally {
    foreach ($name in $savedEnv.Keys) { Set-Item "env:$name" $savedEnv[$name] -ErrorAction SilentlyContinue }
    Remove-Module Degauss -ErrorAction SilentlyContinue
    Remove-Item $testKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
exit $script:failures
