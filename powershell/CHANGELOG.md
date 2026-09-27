# Changelog: Degauss PowerShell module (Windows Terminal)

## 0.3.0 (in progress)

- **Renamed from RetroLooks to Degauss.** The module is now `Degauss`, and its commands are
  `Set-DegaussLook` (`look`), `Set-DegaussColor` (`color`), `Get-DegaussLook`, `Install-Degauss` and
  `Uninstall-Degauss`. The Windows Terminal profile is called Degauss, and the fonts are installed as
  `Degauss-*.ttf`.
- **`degauss`** (`Invoke-Degauss`), like the button on a CRT monitor: the relay's *thunk* and the coil's
  hum (recorded from a real CRT), and a second of wobbling, swirling colors: in Windows Terminal the
  picture itself wobbles, redrawn on the alternate screen so nothing on screen changes. Like the real
  thing, it also fixes the colors: the tab is back to its own colors afterwards, including ones Windows
  Terminal threw away. `-Quiet` skips the sound.

## 0.2.1

- **Tab colors survive Windows Terminal's own color resets.** Windows Terminal throws away colors set by
  `color` when you switch input languages (a known Terminal bug, microsoft/terminal#11522). A tab now
  re-sends its color with every prompt, so it's back as soon as you press Enter, and each look's Terminal
  profile uses your default color, so a reset lands on it (after a Terminal restart).

## 0.2.0

First release as a PowerShell module, installed by the same one-line command as before.

- **`look` and `color`.** `Set-RetroLook` (alias `look`) turns the current tab into a retro look (a new tab
  in the same folder), `Set-RetroColor` (alias `color`) recolors just this tab, with presets, `#RRGGBB` or
  DOS codes like `0A`. `-SetAsDefault` remembers either.
- Terminal's menu gets a single **Retro Looks** profile that opens your default look, so you can make it
  Terminal's default profile; the per-look profiles are hidden (`Install-RetroLooks -ShowProfiles` shows
  them). There's a color scheme for every preset color of every monochrome look.
- The first `look` offers to set up the fonts and profiles if they aren't yet, and to refresh them after
  the module was updated. `Install-RetroLooks` and `Uninstall-RetroLooks` do it by hand.
- New looks: **IBM PS/2 Monochrome** (the 8503 display, where the VGA colors become brightness levels of
  the phosphor color) and **IBM 3270 Monochrome**; Apple //e is now one look in any phosphor color.
- The fonts are shared with the VS Code extension, and only removed when neither uses them.

## 0.1.1 (install.ps1)

- Fix the one-line installer (`irm … | iex`) failing with "Checksum mismatch" in PowerShell 7.
- The installer now removes its downloaded files when it's done.

## 0.1.0 (install.ps1)

First public release, as an installer script: the fonts and Windows Terminal profiles for Apple //e Green,
Apple //e Amber, IBM PS/2 VGA and IBM 3270, sized for your display scaling so they stay sharp
(`-KeepFontSizes` to opt out).
