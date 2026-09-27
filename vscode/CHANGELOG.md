# Changelog: Retro Looks for VS Code

## 0.2.1

- No changes to the extension (released together with the PowerShell module's color-reset fix).

## 0.2.0

- **Pick your phosphor color.** Apple //e is now one look in the color of your choice: green, amber,
  white, cyan, yellow, or any `#RRGGBB` (**Retro: Set Phosphor Color…**). Each look remembers its color.
  An active Apple //e Green or Amber look from 0.1 carries over automatically.
- New **IBM 3270 Monochrome** look: a 3278-style terminal where ISPF's colors become normal and
  intensified text, in any phosphor color.
- The extension installs fonts only (**Retro: Install Fonts**, shown only while they're missing); Windows
  Terminal is now the job of the RetroLooks PowerShell module. The two share the fonts, and the fonts are
  only removed when neither uses them.
- Uninstalling the extension removes its fonts, so the separate uninstall command is gone. Run
  **Retro: Off** first to restore your theme and fonts.

## 0.1.1

- No changes to the extension (released together with a Windows Terminal installer fix).

## 0.1.0

First public release.

- Looks: Apple //e Green, Apple //e Amber and IBM 3270 (ISPF).
- Themes, a look switcher that also sets fonts, and **Retro: Off** to restore your previous setup.
- Installs the fonts and the Windows Terminal profiles on Windows, and reminds you at startup if the fonts
  aren't installed yet (with "Don't Show Again").
- Pixel fonts are sized for your display scaling so they stay sharp (`retroLooks.pixelPerfectFontSize`).
