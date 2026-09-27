# Tests the RetroLooks PowerShell module and its installer from the build output (dist/powershell), in
# Windows PowerShell 5.1 and PowerShell 7. Everything is redirected to a temporary folder and a throwaway
# registry key, so it's safe to run on a developer machine. Build first (`npm test` or `node tools/build.mjs`).
#   pwsh -File tests/powershell/RetroLooks.tests.ps1
param([switch]$Inner)   # set when the script re-runs itself inside each PowerShell
$ErrorActionPreference = 'Stop'
$package = Join-Path (Split-Path (Split-Path $PSScriptRoot)) 'dist\powershell'
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

$sandbox = Join-Path ([IO.Path]::GetTempPath()) ('retro-looks-test-' + [guid]::NewGuid())
$testKey = "HKCU:\SOFTWARE\RetroLooksTest-$([guid]::NewGuid())"
$paths = @{
    Fonts      = Join-Path $sandbox 'fonts'
    FontKey    = "$testKey\Fonts"
    Fragment   = Join-Path $sandbox 'Fragments\Retro Looks'
    FontUsers  = Join-Path $sandbox 'RetroLooks\font-users'
}
$fragmentFile = Join-Path $paths.Fragment 'retro-looks.json'
New-Item -ItemType Directory -Force $sandbox | Out-Null

try {
    Import-Module (Join-Path $package 'RetroLooks\RetroLooks.psd1') -Force
    $module = Get-Module RetroLooks
    & $module {
        param($p)
        $script:FontDir = $p.Fonts; $script:FontKey = $p.FontKey; $script:FragmentDir = $p.Fragment
        $script:FontUsersDir = $p.FontUsers
    } $paths
    $fonts = & $module { Get-RetroFont }
    $registered = { $k = Get-ItemProperty $paths.FontKey -ErrorAction SilentlyContinue; @($fonts | Where-Object { $k -and $k.($_.registryName) }) }
    $ownMarker = Join-Path $paths.FontUsers 'powershell'
    # The marker the VS Code extension leaves (see vscode/fonts.js).
    $vscodeMarker = Join-Path $paths.FontUsers 'vscode'

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
    foreach ($terminalProfile in $fragment.profiles) {
        Check ($terminalProfile.commandline -match '^(pwsh|powershell)\.exe') "$($terminalProfile.name): shell set"
        Check ($schemes -contains $terminalProfile.colorScheme) "$($terminalProfile.name): color scheme '$($terminalProfile.colorScheme)' exists"
        $grid = ($fonts | Where-Object family -eq $terminalProfile.font.face).pixelsPerEm
        if ($grid) {
            $pixelsPerDot = $terminalProfile.font.size * $dpi / 72 / $grid
            Check ([math]::Abs($pixelsPerDot - [math]::Round($pixelsPerDot)) -lt 0.001) "$($terminalProfile.name): $($terminalProfile.font.size)pt is sharp at $dpi DPI"
        }
    }

    Write-Host '-- Install-RetroLooks -KeepFontSizes'
    Install-RetroLooks -KeepFontSizes 6>$null | Out-Null
    $source = Get-Content (Join-Path $package 'RetroLooks\retro-looks.json') -Raw | ConvertFrom-Json
    $written = Get-Content $fragmentFile -Raw | ConvertFrom-Json
    Check ((@($written.profiles | ForEach-Object { $_.font.size }) -join ',') -eq (@($source.profiles | ForEach-Object { $_.font.size }) -join ',')) 'nominal font sizes kept'

    Write-Host '-- fonts shared with the VS Code extension'
    'Retro Looks for VS Code' | Set-Content $vscodeMarker
    $message = Uninstall-RetroLooks 6>&1 | Out-String
    Check (-not (Test-Path $paths.Fragment)) 'Terminal fragment removed'
    Check (-not (Test-Path $ownMarker)) 'own marker removed'
    Check ((& $registered).Count -eq $fonts.Count) 'fonts kept while the VS Code extension uses them'
    Check ($message -match 'VS Code extension still uses them') 'user is told why'
    Check (Test-Path $vscodeMarker) "the extension's marker is left alone"
    Install-RetroLooks 6>$null | Out-Null
    Uninstall-RetroLooks -RemoveFonts 6>$null | Out-Null
    Check ((& $registered).Count -eq 0) '-RemoveFonts removes them anyway'
    Remove-Item $vscodeMarker
    Install-RetroLooks 6>$null | Out-Null
    Uninstall-RetroLooks 6>$null | Out-Null
    Check ((& $registered).Count -eq 0) 'fonts removed when nothing else uses them'
    Check (@(Get-ChildItem $paths.Fonts -ErrorAction SilentlyContinue).Count -eq 0) 'font files deleted'
    Check (-not (Test-Path (Split-Path $paths.FontUsers))) 'no RetroLooks folder left behind'

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
    $sharp = { param($pt, $dpi) & $module { param($a, $b) Get-SharpPoints $a 16 $b } $pt $dpi }
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
    Check (Test-Path (Join-Path $modules "RetroLooks\$version\fonts.json")) 'module data copied'
    & (Join-Path $package 'install.ps1') -ModulesRoot $modules -NoRun 6>$null | Out-Null
    Check (@(Get-ChildItem (Join-Path $modules 'RetroLooks')).Count -eq 1) 'reinstalling replaces the old copy'
    & (Join-Path $package 'install.ps1') -ModulesRoot $modules -NoRun -Uninstall 6>$null | Out-Null
    Check (-not (Test-Path (Join-Path $modules 'RetroLooks'))) 'uninstall removes the module'
} catch {
    Write-Host "  FAIL $($_.Exception.Message) ($($_.InvocationInfo.PositionMessage))" -ForegroundColor Red
    $script:failures++
} finally {
    Remove-Module RetroLooks -ErrorAction SilentlyContinue
    Remove-Item $testKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}
exit $script:failures
