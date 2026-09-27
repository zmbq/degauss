@{
    RootModule           = 'RetroLooks.psm1'
    # The module's own version; bump it (and powershell/CHANGELOG.md) when the module changes.
    ModuleVersion        = '0.3.0'
    GUID                 = '7f4fdfc1-13a0-4917-bb50-9f7ea44c6989'
    Author               = 'Itay Zandbank'
    Copyright            = '(c) Itay Zandbank. MIT License; bundled fonts keep their own licenses.'
    Description          = 'Vintage computer looks for Windows Terminal: Apple //e, IBM PS/2 and IBM 3270, with their period fonts. Switch looks with `look` and recolor a tab with `color`, like DOS.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Install-RetroLooks', 'Uninstall-RetroLooks', 'Set-RetroLook', 'Set-RetroColor', 'Get-RetroLook', 'Initialize-RetroTab', 'Invoke-RetroDegauss')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @('look', 'color', 'degauss')
    PrivateData          = @{
        PSData = @{
            Tags       = @('retro', 'vintage', 'windows-terminal', 'terminal', 'font', 'theme', 'apple', 'ibm', '3270', 'vga')
            LicenseUri = 'https://github.com/zmbq/vscode-retro/blob/main/LICENSE'
            ProjectUri = 'https://github.com/zmbq/vscode-retro'
            ReleaseNotes = 'https://github.com/zmbq/vscode-retro/blob/main/powershell/CHANGELOG.md'
        }
    }
}
