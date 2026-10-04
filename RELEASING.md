# Releasing

The two products are released separately, each from its own Git tag. Both start the same way:

1. Bump the version: `version` in `vscode/package.json`, or `ModuleVersion` in
   `powershell/Degauss/Degauss.psd1`.
2. Turn the changelog's "(in progress)" heading into the version (`vscode/CHANGELOG.md` or
   `powershell/CHANGELOG.md`). The GitHub release uses that entry as its notes.
3. Run `npm test` and `pwsh -File tests/powershell/Degauss.tests.ps1`, commit and push.
4. Tag and push: `vscode-v1.2.3` or `powershell-v1.2.3`, matching the version. The release workflow
   checks the match, runs the tests and creates the GitHub release.

A tag with a suffix, like `vscode-v1.2.3-alpha.1`, makes a **test release**: a GitHub pre-release only.
The suffix is only in the tag; the version stays `1.2.3`. Tag the plain version once it's good.

## VS Code extension: Visual Studio Marketplace

The extension is uploaded by hand (the workflow only publishes when a `VSCE_PAT` secret exists, and
there isn't one).

1. Download `degauss-<version>.vsix` from the GitHub release.
2. On the [publisher management page](https://marketplace.visualstudio.com/manage), open **Degauss** →
   **…** → **Update**, and upload the `.vsix`.
3. The Marketplace verifies it, usually within minutes, before the new version shows up.

The Marketplace page (description, README, preview badge) comes from the `.vsix`, so it only changes with
a new upload.

**Trying a test release:** download its `.vsix` and `code --install-extension degauss-<version>.vsix`
(or Extensions view → **…** → **Install from VSIX…**). It replaces the Marketplace version. Turn off
**Auto Update** for the extension while testing. Since the test build has the same version as the final
release, go back to the Marketplace build with `code --install-extension zmbq.degauss --force`.

## PowerShell module: PowerShell Gallery

`install.ps1` downloads the module from the latest GitHub release, so that part is done by the tag. The
[PowerShell Gallery](https://www.powershellgallery.com/packages/Degauss) is published by hand, from
PowerShell 7 (it has PSResourceGet).

**Once:** store the Gallery API key (scope "Push new packages and package versions", glob `Degauss`):

```powershell
Install-PSResource Microsoft.PowerShell.SecretManagement, Microsoft.PowerShell.SecretStore
Register-SecretVault -Name Local -ModuleName Microsoft.PowerShell.SecretStore -DefaultVault
Set-Secret -Name PSGalleryApiKey      # prompts for the key, so it stays out of your history
```

**Each release:** publish the module exactly as the GitHub release has it. Download
`degauss-powershell.zip` from the release, unzip it, and publish its `Degauss` folder (the folder name
must match the module name):

```powershell
Publish-PSResource -Path .\degauss-powershell\Degauss -Repository PSGallery `
    -ApiKey (Get-Secret PSGalleryApiKey -AsPlainText)
```

Or build the same folder yourself: `git checkout powershell-v1.2.3`, `node tools/build.mjs`, and publish
`dist\powershell\Degauss`. Don't publish from a working copy that isn't the tag.

A published version can't be replaced, only unlisted, so try it locally first if anything packaging-related
changed:

```powershell
Register-PSResourceRepository -Name LocalTest -Uri C:\temp\psrepo -Trusted
Publish-PSResource -Path .\dist\powershell\Degauss -Repository LocalTest
Install-PSResource Degauss -Repository LocalTest -Scope CurrentUser
```

Don't publish test releases to the Gallery. Try them with
`install.ps1 -Version powershell-v1.2.3-alpha.1` instead.
