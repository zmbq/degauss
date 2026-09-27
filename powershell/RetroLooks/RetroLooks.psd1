@{
    RootModule           = 'RetroLooks.psm1'
    # Filled in by tools/build.mjs from the root package.json.
    ModuleVersion        = '0.0.0'
    GUID                 = '7f4fdfc1-13a0-4917-bb50-9f7ea44c6989'
    Author               = 'Itay Zandbank'
    Copyright            = '(c) Itay Zandbank. MIT License; bundled fonts keep their own licenses.'
    Description          = 'Vintage computer looks for Windows Terminal: Apple //e, IBM PS/2 VGA and IBM 3270, with their period fonts.'
    PowerShellVersion    = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport    = @('Install-RetroLooks', 'Uninstall-RetroLooks')
    CmdletsToExport      = @()
    VariablesToExport    = @()
    AliasesToExport      = @()
    PrivateData          = @{
        PSData = @{
            Tags       = @('retro', 'vintage', 'windows-terminal', 'terminal', 'font', 'theme', 'apple', 'ibm', '3270', 'vga')
            LicenseUri = 'https://github.com/zmbq/vscode-retro/blob/main/LICENSE'
            ProjectUri = 'https://github.com/zmbq/vscode-retro'
        }
    }
}
