# Tests the RetroLooks PowerShell module and its installer from the build output (dist/powershell), in
# Windows PowerShell 5.1 and PowerShell 7. Everything is redirected to a temporary folder and a throwaway
# registry key, wt.exe is replaced by a fake, and color sequences are captured instead of written, so it's
# safe to run on a developer machine. Build first (`npm test` or `node tools/build.mjs`).
#   pwsh -File tests/powershell/RetroLooks.tests.ps1
param([switch]$Inner)   # set when the script re-runs itself inside each PowerShell
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot)
$package = Join-Path $root 'dist\powershell'
if (-not (Test-Path (Join-Path $package 'RetroLooks\RetroLooks.psd1'))) { throw "Build first: $package is missing." }

if (-not $Inner) {
    $failed = @()
    foreach ($shell in @('powershell', 'pwsh') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue }) {
        Write-Host "== $shell"
        & $shell -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath -Inner
        if ($LASTEXITCODE -ne 0) { $failed += $shell }
    }
    if ($failed) { throw "RetroLooks tests failed in: $($failed -join ', ')" }
    Write-Host 'All RetroLooks tests passed.'
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

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('retro-looks-test-' + [guid]::NewGuid())
$testKey = "HKCU:\SOFTWARE\RetroLooksTest-$([guid]::NewGuid())"
$paths = @{
    Fonts    = Join-Path $sandbox 'fonts'
    FontKey  = "$testKey\Fonts"
    Fragment = Join-Path $sandbox 'Fragments\Retro Looks'
    Data     = Join-Path $sandbox 'RetroLooks'
}
$fragmentFile = Join-Path $paths.Fragment 'retro-looks.json'
$prefsFile = Join-Path $paths.Data 'terminal.json'
New-Item -ItemType Directory -Force $sandbox | Out-Null
$savedEnv = @{ WT_SESSION = $env:WT_SESSION; WT_PROFILE_ID = $env:WT_PROFILE_ID; TERM_PROGRAM = $env:TERM_PROGRAM; RETRO_LOOK = $env:RETRO_LOOK }
$env:RETRO_LOOK = $null

try {
    Import-Module (Join-Path $package 'RetroLooks\RetroLooks.psd1') -Force
    $module = Get-Module RetroLooks
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
    } $paths
    $inModule = { param($block, $arg1, $arg2) & $module $block $arg1 $arg2 }
    $fonts = & $module { Get-RetroFont }
    $looks = @(& $module { Get-LookData })
    $lookById = @{}; foreach ($l in $looks) { $lookById[$l.id] = $l }
    $registered = { $k = Get-ItemProperty $paths.FontKey -ErrorAction SilentlyContinue; @($fonts | Where-Object { $k -and $k.($_.registryName) }) }
    $ownMarker = Join-Path $paths.Data 'font-users\powershell'
    $vscodeMarker = Join-Path $paths.Data 'font-users\vscode'   # what the VS Code extension leaves (vscode/fonts.js)
    $written = { & $module { $script:Written -join '' } }
    $clearWritten = { & $module { $script:Written = @() } }
    $wtCalls = { & $module { $script:WtCalls } }
    $clearWt = { & $module { $script:WtCalls = @() } }
    $retroGuid = & $module { $script:RetroProfileGuid }
    $originalPrompt = (Get-Command prompt).ScriptBlock.ToString()
    $profileScheme = { param($id) ((Get-Content $fragmentFile -Raw | ConvertFrom-Json).profiles | Where-Object guid -eq $lookById[$id].guid).colorScheme }
    $fragmentScheme = { param($name) (Get-Content $fragmentFile -Raw | ConvertFrom-Json).schemes | Where-Object name -eq $name }
    $lookProfiles = { param($f) @($f.profiles | Where-Object { $_.guid -ne $retroGuid }) }
    $retroProfile = { param($f) $f.profiles | Where-Object { $_.guid -eq $retroGuid } }

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
    & $module { $p = Get-RetroPreference; $p.installedVersion = '0.0.1'; Save-RetroPreference $p }
    & $answer $true
    & $clearWt
    $message = look apple -KeepTab 6>&1 | Out-String -Width 4096
    Check ((@(& $questions)[-1]) -match 'updated \(0\.0\.1 to ') 'after an update, look offers to refresh the setup'
    Check ((Get-Content $prefsFile -Raw | ConvertFrom-Json).installedVersion -eq (& $module { Get-ModuleVersion }) -and @(& $wtCalls).Count -eq 1) '... refreshes it and carries on'
    & $clearWt
    look -Off -KeepTab
    Check (@(& $wtCalls).Count -eq 1) 'look -Off never needs setup'
    Pop-Location
    Uninstall-RetroLooks 6>$null | Out-Null
    $env:WT_SESSION = $null

    Write-Host '-- Install-RetroLooks'
    Install-RetroLooks 6>$null | Out-Null
    foreach ($font in $fonts) {
        $value = (Get-ItemProperty $paths.FontKey).($font.registryName)
        Check ($value -eq (Join-Path $paths.Fonts $font.installedFile) -and (Test-Path $value)) "font registered and copied: $($font.family)"
    }
    Check (Test-Path $fragmentFile) 'Terminal fragment written'
    Check ((Test-Path $ownMarker) -and ((Get-Content $ownMarker -Raw) -match 'RetroLooks module \d')) 'font-user marker written'
    $fragment = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    $schemes = @($fragment.schemes | ForEach-Object { $_.name })
    $dpi = & $module { Get-DisplayDpi }
    $retro = & $retroProfile $fragment
    Check ($retro -and $retro.name -eq 'Retro Looks' -and $retro.hidden -eq $false) 'one visible Retro Looks profile'
    Check ($retro.commandline -match 'Initialize-RetroTab -Look apple2e$' -and $retro.font.face -eq 'PR Number 3') 'it opens the default look (Apple //e)'
    Check ((& $lookProfiles $fragment).Count -eq $looks.Count) 'plus a profile per look'
    foreach ($terminalProfile in & $lookProfiles $fragment) {
        Check ($terminalProfile.commandline -match '^(pwsh|powershell)\.exe -NoLogo -NoExit -Command Initialize-RetroTab$') "$($terminalProfile.name): runs Initialize-RetroTab"
        Check ($terminalProfile.hidden -eq $true) "$($terminalProfile.name): hidden"
        Check ($schemes -contains $terminalProfile.colorScheme) "$($terminalProfile.name): color scheme '$($terminalProfile.colorScheme)' exists"
        $grid = ($fonts | Where-Object family -eq $terminalProfile.font.face).pixelsPerEm
        if ($grid) {
            $pixelsPerDot = $terminalProfile.font.size * $dpi / 72 / $grid
            Check ([math]::Abs($pixelsPerDot - [math]::Round($pixelsPerDot)) -lt 0.001) "$($terminalProfile.name): $($terminalProfile.font.size)pt is sharp at $dpi DPI"
        }
    }
    Install-RetroLooks -ShowProfiles -KeepFontSizes 6>$null | Out-Null
    $fragment = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    Check (@($fragment.profiles | Where-Object hidden).Count -eq 0) '-ShowProfiles shows the profiles'
    $source = Get-Content (Join-Path $package 'RetroLooks\retro-looks.json') -Raw | ConvertFrom-Json
    Check ((@(& $lookProfiles $fragment | ForEach-Object { $_.font.size }) -join ',') -eq (@($source.profiles | ForEach-Object { $_.font.size }) -join ',')) '-KeepFontSizes keeps nominal sizes'

    Write-Host '-- colors match the VS Code extension (vscode/palette.js)'
    $diffs = 0; $count = 0
    foreach ($look in $looks | Where-Object monochrome) {
        foreach ($preset in (& $module { Get-PaletteData }).presets.PSObject.Properties) {
            $name = "$($look.name) " + $preset.Name.Substring(0, 1).ToUpper() + $preset.Name.Substring(1)
            $expected = $source.schemes | Where-Object name -eq $name
            $actual = & $inModule { param($s, $c) Get-RetroScheme $s $c } $look.colorStyle $preset.Value
            foreach ($key in $actual.Keys) { $count++; if ($actual[$key] -ne $expected.$key) { $diffs++ } }
        }
    }
    Check ($count -gt 0 -and $diffs -eq 0) "preset schemes identical to the build's ($count colors)"
    if (Get-Command node -ErrorAction SilentlyContinue) {
        $palette = (Join-Path $root 'vscode\palette.js').Replace('\', '/')
        foreach ($custom in '#40E0FF', '#102030', '#FF00FF') {
            $js = node -e "const p=require('$palette'); console.log(JSON.stringify(p.phosphorPalette(p.resolveColor('$custom'))))" | ConvertFrom-Json
            $ps = & $inModule { param($c) Get-PhosphorPalette (Resolve-RetroColor $c) } $custom
            $bad = @($ps.Keys | Where-Object { $ps[$_] -ne $js.$_ })
            Check ($bad.Count -eq 0) "custom $custom palette identical to palette.js$(if ($bad) { ': ' + ($bad -join ', ') })"
        }
    }

    Write-Host '-- color specs'
    $spec = { param($s) & $module { param($x) ConvertFrom-ColorSpec $x } $s }
    Check ((& $spec 'AMBER').Stored -eq 'amber') 'preset names in any case'
    Check ((& $spec '40e0ff').Stored -eq '#40E0FF') 'RGB with or without #'
    Check ((& $spec '#102030').Phosphor -eq (& $inModule { param($c) Resolve-RetroColor $c } '#102030')) 'dark colors brightened'
    $dosGreen = & $spec '0A'
    Check ($dosGreen.Phosphor -eq (& $inModule { param($c) Resolve-RetroColor $c } 'green') -and $dosGreen.Stored -eq '0A') 'DOS 0A is the green phosphor'
    Check ((& $spec 'e').Stored -eq '0E') 'one DOS digit means a black background'
    $dosBlue = & $spec '1f'
    Check ($dosBlue.Foreground -eq '#FFFFFF' -and $dosBlue.Background -eq '#0000AA' -and -not $dosBlue.Phosphor) 'DOS 1F is white on blue'
    Throws { & $spec '11' } 'same' 'DOS rejects the same text and background color'
    Throws { & $spec 'purple' } 'Unknown color' 'unknown names are rejected'
    Throws { & $spec '#000000' } 'black' 'black is rejected'

    Write-Host '-- Set-RetroColor'
    $env:WT_SESSION = 'test'; $env:TERM_PROGRAM = $null
    $env:WT_PROFILE_ID = $lookById['apple2e'].guid
    & $clearWritten
    color amber
    $amber = & $inModule { param($c) Get-ColorSequence (Get-RetroScheme 'phosphor' (Resolve-RetroColor $c)) } 'amber'
    Check ((& $written) -eq $amber) 'color amber recolors an Apple //e tab with the amber phosphor palette'
    Check (([regex]::Matches((& $written), "\]4;\d+;rgb:")).Count -eq 16) 'all 16 ANSI colors are set'
    $env:WT_PROFILE_ID = $lookById['ibm-3270'].guid
    & $clearWritten
    color amber
    $intensity = & $inModule { param($c) Get-ColorSequence (Get-RetroScheme 'intensity' (Resolve-RetroColor $c)) } 'amber'
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
    Check ((& $retroProfile (Get-Content $fragmentFile -Raw | ConvertFrom-Json)).colorScheme -eq 'Apple //e Cyan') '... and so does the Retro Looks profile'
    Check ($message -match 'Restart Windows Terminal') '... after a Terminal restart, which it mentions'
    & $clearWritten
    Initialize-RetroTab
    $cyan = & $inModule { param($c) Get-ColorSequence (Get-RetroScheme 'phosphor' (Resolve-RetroColor $c)) } 'cyan'
    Check ((& $written) -eq $cyan) 'a new tab of the look opens in the saved color'
    & $clearWritten
    color
    Check ((& $written) -eq ((& $module { $script:ResetSequence }) + $cyan)) 'color alone goes back to the saved default'
    color '#40E0FF' -SetAsDefault 6>$null
    $customScheme = & $fragmentScheme 'Apple //e Custom'
    $expected = & $inModule { param($c) Get-RetroScheme 'phosphor' (Resolve-RetroColor $c) } '#40E0FF'
    Check ((& $profileScheme 'apple2e') -eq 'Apple //e Custom' -and $customScheme.background -eq $expected.background -and $customScheme.brightWhite -eq $expected.brightWhite) 'a custom default gets its own Terminal scheme'
    $env:RETRO_LOOK = 'ibm-3270'
    color 1F -SetAsDefault 6>$null
    $dosScheme = & $fragmentScheme 'IBM 3270 Custom'
    Check ((& $profileScheme 'ibm-3270') -eq 'IBM 3270 Custom' -and $dosScheme.background -eq '#0000AA' -and $dosScheme.foreground -eq '#FFFFFF' -and $dosScheme.red -eq '#FF3030') 'a DOS default keeps the look''s colors with DOS''s text and background'
    color -SetAsDefault 6>$null
    Check ((& $profileScheme 'ibm-3270') -eq 'IBM 3270') '... and forgetting it restores the look''s own scheme'
    $env:RETRO_LOOK = 'apple2e'
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
    Check ($env:RETRO_LOOK -eq 'apple2e') 'the tab remembers its look'
    $env:WT_PROFILE_ID = $null; $env:RETRO_LOOK = $null
    Throws { color amber -SetAsDefault } 'Retro Looks tab' '-SetAsDefault outside a Retro Looks tab is refused'
    & $clearWritten
    color amber
    Check ((& $written) -eq $amber) 'outside Retro Looks tabs, color still works as a phosphor monitor'

    Write-Host '-- Set-RetroLook'
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
    Initialize-RetroTab
    $monoAmber = & $inModule { param($c) Get-ColorSequence (Get-RetroScheme 'intensity' (Resolve-RetroColor $c)) } 'amber'
    Check ((& $written) -eq $monoAmber -and -not (Test-Path $pendingFile)) 'the new tab applies it and clears the hand-over'
    $env:WT_PROFILE_ID = $null; $env:RETRO_LOOK = $null
    & $clearWt
    look -Off -KeepTab
    Check ((@(& $wtCalls)[0] -join ' ') -eq "-w 0 nt -d $sandbox") 'look -Off opens a normal tab'
    & $clearWt
    $message = look ps2 -SetAsDefault -KeepTab 6>&1 | Out-String -Width 4096
    Check ((@(& $wtCalls)[0] -join ' ') -match [regex]::Escape($lookById['ibm-ps2-vga'].guid)) 'look -SetAsDefault also switches to the look'
    Check ($message -match 'Default look: IBM PS/2 VGA' -and $message -match 'restart Windows Terminal') 'and says the Retro Looks profile needs a Terminal restart'
    $fragment = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    $retro = & $retroProfile $fragment
    Check ($retro.commandline -match '-Look ibm-ps2-vga$' -and $retro.font.face -eq 'PxPlus IBM VGA 9x16' -and $retro.guid -eq $retroGuid) 'the Retro Looks profile now copies the new default, same GUID'
    Check (@($fragment.profiles | Where-Object hidden).Count -eq 0) 'Install-RetroLooks -ShowProfiles is remembered when the fragment is rewritten'
    $message = look ps2 -Color amber -SetAsDefault -KeepTab 6>&1 | Out-String -Width 4096
    Check ($message -match 'Default look: IBM PS/2 VGA \(amber\)' -and $message -notmatch 'restart') 'a new default color needs no restart'
    look -KeepTab
    Check ((@(& $wtCalls)[2] -join ' ') -match [regex]::Escape($lookById['ibm-ps2-vga'].guid)) 'look alone opens the default look'

    Write-Host '-- the Retro Looks profile'
    & $clearWritten
    $message = Initialize-RetroTab -Look apple2e 6>&1 | Out-String -Width 4096
    Check ($message -match 'default look is now IBM PS/2 VGA' -and $message -match 'Apple //e') 'a tab from an outdated Retro Looks profile says a Terminal restart is pending'
    Check ($env:RETRO_LOOK -eq 'apple2e') '... and still knows it shows Apple //e'
    $message = Initialize-RetroTab -Look ibm-ps2-vga 6>&1 | Out-String -Width 4096
    Check (-not $message.Trim()) 'an up-to-date Retro Looks tab says nothing'
    $vgaAmber = & $inModule { param($c) Get-ColorSequence (Get-RetroScheme 'luminance' (Resolve-RetroColor $c)) } 'amber'
    Check ((& $written) -like "*$vgaAmber") '... and opens in the default color'
    $env:RETRO_LOOK = $null
    Check (@(Get-RetroLook | Where-Object Default).Name -eq 'IBM PS/2 VGA') 'Get-RetroLook shows the default'
    Check (@(Get-RetroLook).Count -eq $looks.Count) 'Get-RetroLook lists every look'
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
    $warnings = Install-RetroLooks 6>$null 3>&1 | Out-String -Width 4096
    Check ($warnings -match 'Windows Terminal is not installed' -and (& $registered).Count -eq $fonts.Count) 'Install-RetroLooks warns, and installs the fonts anyway'
    & $module { $script:IsTerminalInstalled = { $true } }

    Write-Host '-- fonts shared with the VS Code extension'
    'Retro Looks for VS Code' | Set-Content $vscodeMarker
    $message = Uninstall-RetroLooks 6>&1 | Out-String -Width 4096
    Check (-not (Test-Path $paths.Fragment)) 'Terminal fragment removed'
    Check (-not (Test-Path $prefsFile)) 'preferences removed'
    Check (-not (Test-Path $ownMarker)) 'own marker removed'
    Check ((& $registered).Count -eq $fonts.Count) 'fonts kept while the VS Code extension uses them'
    Check ($message -match 'VS Code extension still uses them') 'user is told why'
    Check (Test-Path $vscodeMarker) "the extension's marker is left alone"
    Install-RetroLooks 6>$null | Out-Null
    Uninstall-RetroLooks -RemoveFonts 6>$null | Out-Null
    Check ((& $registered).Count -eq 0) '-RemoveFonts removes them anyway'
    Remove-Item $vscodeMarker
    Install-RetroLooks 6>$null | Out-Null
    $env:WT_SESSION = 'test'
    Push-Location $sandbox
    look apple -Color amber -SetAsDefault -KeepTab 6>$null
    Pop-Location
    Uninstall-RetroLooks 6>$null | Out-Null
    Check ((& $registered).Count -eq 0) 'fonts removed when nothing else uses them'
    Check (@(Get-ChildItem $paths.Fonts -ErrorAction SilentlyContinue).Count -eq 0) 'font files deleted'
    Check (-not (Test-Path $paths.Data)) 'no RetroLooks folder left behind'
    Check ((Get-Command prompt).ScriptBlock.ToString() -eq $originalPrompt) "the user's prompt function is back as it was"

    Write-Host '-- cleans up a v0.1 installation'
    New-Item -ItemType Directory -Force $paths.Fragment, $paths.Fonts | Out-Null
    '{}' | Set-Content $fragmentFile
    foreach ($name in 'RetroLooks-PRNumber3.ttf', 'RetroLooks-OldFont.ttf') {
        $file = Join-Path $paths.Fonts $name
        'x' | Set-Content $file
        Set-ItemProperty -Path $paths.FontKey -Name "$name (TrueType)" -Value $file
    }
    Uninstall-RetroLooks 6>$null | Out-Null
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
    $version = (Import-PowerShellDataFile (Join-Path $package 'RetroLooks\RetroLooks.psd1')).ModuleVersion
    Check (Test-Path (Join-Path $modules "RetroLooks\$version\RetroLooks.psd1")) "module installed as RetroLooks\$version"
    Check (Test-Path (Join-Path $modules "RetroLooks\$version\looks.json")) 'module data copied'
    & (Join-Path $package 'install.ps1') -ModulesRoot $modules -NoRun 6>$null | Out-Null
    Check (@(Get-ChildItem (Join-Path $modules 'RetroLooks')).Count -eq 1) 'reinstalling replaces the old copy'
    & (Join-Path $package 'install.ps1') -ModulesRoot $modules -NoRun -Uninstall 6>$null | Out-Null
    Check (-not (Test-Path (Join-Path $modules 'RetroLooks'))) 'uninstall removes the module'
} catch {
    Write-Host "  FAIL $($_.Exception.Message) ($($_.InvocationInfo.PositionMessage))" -ForegroundColor Red
    $script:failures++
} finally {
    foreach ($name in $savedEnv.Keys) { Set-Item "env:$name" $savedEnv[$name] -ErrorAction SilentlyContinue }
    Remove-Module RetroLooks -ErrorAction SilentlyContinue
    Remove-Item $testKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
exit $script:failures
