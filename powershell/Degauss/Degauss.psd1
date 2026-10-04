@{
    RootModule           = 'Degauss.psm1'
    # The module's own version; bump it (and powershell/CHANGELOG.md) when the module changes.
    ModuleVersion        = '0.3.0'
    GUID                 = '7f4fdfc1-13a0-4917-bb50-9f7ea44c6989'
    Author               = 'Itay Zandbank'
    Copyright            = '(c) Itay Zandbank. MIT License; bundled fonts keep their own licenses.'
    # Shown on the PowerShell Gallery, which doesn't show the README.
    Description          = 'Vintage computer looks for Windows Terminal: Apple //e, IBM PS/2 VGA and IBM 3270, with their period fonts and colors. After Install-Module, run Install-Degauss to install the fonts (for your user, no admin) and add the looks to Windows Terminal, then restart Terminal. Switch a tab''s look with "look apple" and recolor it with "color amber" or DOS codes like "color 0A". "degauss" does what the button on a CRT did. Windows only; works in Windows PowerShell 5.1 and PowerShell 7 (install from PowerShell 7 if you have it). Docs: https://github.com/zmbq/degauss'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Install-Degauss', 'Uninstall-Degauss', 'Set-DegaussLook', 'Set-DegaussColor', 'Get-DegaussLook', 'Initialize-DegaussTab', 'Invoke-Degauss')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('look', 'color', 'degauss')
    PrivateData          = @{
        PSData = @{
            Tags         = @('Windows', 'retro', 'vintage', 'degauss', 'crt', 'dos', 'windows-terminal', 'terminal', 'font', 'theme', 'apple', 'ibm', '3270', 'vga')
            LicenseUri   = 'https://github.com/zmbq/degauss/blob/main/LICENSE'
            ProjectUri   = 'https://github.com/zmbq/degauss'
            IconUri      = 'https://raw.githubusercontent.com/zmbq/degauss/main/vscode/icon.png'
            # The build replaces this with the version's entry from powershell/CHANGELOG.md.
            ReleaseNotes = 'https://github.com/zmbq/degauss/blob/main/powershell/CHANGELOG.md'
        }
    }
}
