# Changelog

## 0.2.0 (in progress)

- **Pick your phosphor color.** Apple //e is now one look in the color of your choice: green, amber,
  white, cyan, yellow, or any `#RRGGBB` (**Retro: Set Phosphor Color…**). Each look remembers its color.
  An active Apple //e Green or Amber look from 0.1 carries over automatically.
- New **IBM 3270 Monochrome** look: a 3278-style terminal where ISPF's colors become normal and
  intensified text, in any phosphor color.
- Windows Terminal: a color scheme for every preset color of every monochrome look.
- Tests (`npm test`, `tests/installer.tests.ps1`), run in CI before every build and release.

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
