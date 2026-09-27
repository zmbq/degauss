# Changelog

## 0.2.0 (in progress)

- **Pick your phosphor color.** Apple //e is now one look in the color of your choice: green, amber,
  white, cyan, yellow, or any `#RRGGBB` (**Retro: Set Phosphor Color…**). Each look remembers its color.
  An active Apple //e Green or Amber look from 0.1 carries over automatically.
- New **IBM 3270 Monochrome** look: a 3278-style terminal where ISPF's colors become normal and
  intensified text, in any phosphor color.
- **Windows Terminal: `look` and `color`.** `Set-RetroLook` (alias `look`) turns the current tab into a
  retro look (a new tab in the same folder), `Set-RetroColor` (alias `color`) recolors just this tab, with
  presets, `#RRGGBB` or DOS codes like `0A`. `-SetAsDefault` remembers either. Terminal's menu gets a
  single **Retro Looks** profile that opens your default look, so you can make it Terminal's default
  profile; the per-look profiles are hidden (`Install-RetroLooks -ShowProfiles` shows them). There's also a
  color scheme for every preset color of every monochrome look.
- New **IBM PS/2 Monochrome** look (Windows Terminal): the 8503 display, where the VGA colors become
  brightness levels of the phosphor color.
- **Two independent parts.** Windows Terminal support is now the **RetroLooks PowerShell module**
  (`Install-RetroLooks`, `Uninstall-RetroLooks`), installed by the same one-line command. The VS Code
  extension installs fonts only (**Retro: Install Fonts**, shown only while they're missing). Both share
  the fonts: each leaves a marker in `%LOCALAPPDATA%\RetroLooks\font-users`, and the fonts are only
  removed when neither uses them. Uninstalling the extension removes its fonts, so the separate
  uninstall command is gone; run **Retro: Off** first to restore your theme and fonts.
- Tests (`npm test`, `tests/powershell/RetroLooks.tests.ps1`), run in CI on Linux and Windows before
  every build and release.

## 0.1.1

- Fix the Windows Terminal installer (`irm … | iex`) failing with "Checksum mismatch" in PowerShell 7.
- The installer now removes its downloaded files when it's done.

## 0.1.0

First public release.

- Looks: Apple //e Green, Apple //e Amber, IBM 3270 (ISPF), and IBM PS/2 VGA (Windows Terminal only).
- VS Code: themes, look switcher that also sets fonts, and "Retro: Off" to restore your previous setup.
- Windows: one-command font and Windows Terminal profile installer, from VS Code or PowerShell.
- VS Code reminds you at startup if the fonts aren't installed yet (with "Don't Show Again").
- Pixel fonts are sized for your display scaling so they stay sharp, in VS Code (`retroLooks.pixelPerfectFontSize`)
  and in the Windows Terminal profiles (`install.ps1 -KeepFontSizes` to opt out).
