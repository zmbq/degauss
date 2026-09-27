# Tests installer/install.ps1 from the built Terminal package (dist/terminal), in Windows PowerShell 5.1
# and PowerShell 7. The copy under test is redirected to a temporary folder and a throwaway registry key,
# so it's safe to run on a developer machine. Run `npm test` (or `node tools/build.mjs`) first.
#   pwsh -File tests/installer.tests.ps1
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot
$package = Join-Path $root 'dist\terminal'
if (-not (Test-Path (Join-Path $package 'install.ps1'))) { throw "Build first: $package\install.ps1 is missing." }

$failures = 0
function Check([bool]$Condition, [string]$Message) {
    if ($Condition) { Write-Host "  ok  $Message" } else { Write-Host "  FAIL $Message" -ForegroundColor Red; $script:failures++ }
}

$shells = @('powershell', 'pwsh') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue }
foreach ($shell in $shells) {
    Write-Host "== $shell"
    $sandbox = Join-Path ([IO.Path]::GetTempPath()) ("retro-looks-test-" + [guid]::NewGuid())
    $testKey = "HKCU:\SOFTWARE\RetroLooksTest-$([guid]::NewGuid())"
    try {
        Copy-Item $package $sandbox -Recurse
        $script = Join-Path $sandbox 'install.ps1'
        $text = [IO.File]::ReadAllText($script)
        $text = $text.Replace('Join-Path $env:LOCALAPPDATA', "Join-Path '$sandbox\appdata'")
        $text = $text.Replace("'HKCU:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'", "'$testKey\Fonts'")
        [IO.File]::WriteAllText($script, $text)
        $fragmentFile = Join-Path $sandbox 'appdata\Microsoft\Windows Terminal\Fragments\Retro Looks\retro-looks.json'
        $fonts = Get-ChildItem (Join-Path $sandbox 'fonts') -Recurse -Filter font.json | ForEach-Object { Get-Content $_.FullName -Raw | ConvertFrom-Json }

        & $shell -NoProfile -ExecutionPolicy Bypass -File $script | Out-Null
        Check ($LASTEXITCODE -eq 0) 'install exits cleanly'
        $registered = Get-ItemProperty "$testKey\Fonts"
        foreach ($font in $fonts) {
            $value = $registered."$($font.family) (TrueType)"
            Check ($value -and (Test-Path $value)) "font registered and copied: $($font.family)"
        }
        Check (Test-Path $fragmentFile) 'Terminal fragment written'
        $fragment = Get-Content $fragmentFile -Raw | ConvertFrom-Json
        $schemes = @($fragment.schemes | ForEach-Object { $_.name })
        foreach ($terminalProfile in $fragment.profiles) {
            Check ($terminalProfile.commandline -match '^(pwsh|powershell)\.exe') "$($terminalProfile.name): shell set ($($terminalProfile.commandline))"
            Check ($schemes -contains $terminalProfile.colorScheme) "$($terminalProfile.name): color scheme '$($terminalProfile.colorScheme)' exists"
            $grid = ($fonts | Where-Object family -eq $terminalProfile.font.face).pixelsPerEm
            if ($grid) {
                $dpi = (Get-ItemProperty 'HKCU:\Control Panel\Desktop\WindowMetrics' -ErrorAction SilentlyContinue).AppliedDPI
                if (-not $dpi) { $dpi = 96 }
                $pixelsPerDot = $terminalProfile.font.size * $dpi / 72 / $grid
                Check ([math]::Abs($pixelsPerDot - [math]::Round($pixelsPerDot)) -lt 0.001) "$($terminalProfile.name): $($terminalProfile.font.size)pt is sharp at $dpi DPI"
            }
        }

        & $shell -NoProfile -ExecutionPolicy Bypass -File $script -Uninstall | Out-Null
        Check ($LASTEXITCODE -eq 0) 'uninstall exits cleanly'
        $left = @((Get-ItemProperty "$testKey\Fonts").PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })
        Check ($left.Count -eq 0) 'fonts unregistered'
        Check (-not (Test-Path $fragmentFile)) 'Terminal fragment removed'
    } finally {
        Remove-Item $testKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item $sandbox -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($failures) { throw "$failures installer check(s) failed." }
Write-Host 'All installer checks passed.'
