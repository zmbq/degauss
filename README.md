# Retro Looks

Vintage computer looks for **VS Code** and **Windows Terminal**: period-correct fonts and color schemes
from the machines we grew up on. There are two independent parts: a VS Code extension and a PowerShell
module for Windows Terminal. Use either or both; they share the same fonts.

| Look | Font | What it looks like |
|---|---|---|
| **Apple //e** | PR Number 3 (the //e 80-column font) | A monochrome monitor in the phosphor color of your choice: green, amber, white, cyan, yellow or any RGB color |
| **IBM PS/2 VGA** *(Windows Terminal only)* | PxPlus IBM VGA 9x16 | The black DOS prompt with the 16 VGA colors |
| **IBM 3270** | IBM 3270 | Mainframe color terminal with the default ISPF editor highlighting |
| **IBM 3270 Monochrome** | IBM 3270 | A 3278-style monochrome terminal: ISPF's colors become normal and intensified text, in the phosphor color of your choice |

Want a Commodore 64, a classic Mac or a CP/M machine, or a VS Code version of the PS/2 look? [Add it!](CONTRIBUTING.md)

## VS Code

Install **Retro Looks** from the Marketplace (or Open VSX), then open the Command Palette
(`Ctrl+Shift+P`) and run **Retro: Choose Look…**, or one of the **Retro: …** commands directly.

- A look sets the color theme, the editor and terminal fonts, font size and cursor.
- **Monochrome looks** (Apple //e, IBM 3270 Monochrome) ask for their phosphor color: green, amber,
  white, cyan, yellow, or **Custom…** for any `#RRGGBB`. Change it later with
  **Retro: Set Phosphor Color…**. Each look remembers its own color (in the
  `retroLooks.phosphorColors` setting), and changing it is instant.
- **Retro: Off** puts back exactly what you had before. Your chosen colors are remembered for next time.
- On Windows, the extension offers to install its fonts when VS Code starts (for your user only,
  no admin needed), until you install them or choose **Don't Show Again**. You can also run
  **Retro: Install Fonts**. **Retro: Uninstall Fonts** removes them, unless Retro Looks for Windows
  Terminal still uses them. Uninstalling the extension from the Extensions view cleans up the fonts too.
- On macOS and Linux, run **Retro: Open Bundled Fonts Folder** and install the fonts with your
  system's font installer. Automatic installation there is on the [roadmap](CONTRIBUTING.md#roadmap-and-where-help-is-wanted).
- Works in Remote SSH, WSL and container windows: the extension runs on your local machine.
- **Before uninstalling, run Retro: Off.** Once the extension is gone it can't restore your theme and
  fonts: VS Code would fall back to its default theme and keep the retro font size and cursor.
  (Reinstalling and running **Retro: Off** fixes it; the extension remembers your original settings.)

The themes are also available on their own through the normal theme picker (`Ctrl+K Ctrl+T`), and
you can use any of the fonts with any theme. The extension's full page is [vscode/README.md](vscode/README.md).

## Windows Terminal

Windows Terminal support is the **RetroLooks PowerShell module**. Paste this into PowerShell:

```powershell
irm https://github.com/zmbq/vscode-retro/releases/latest/download/install.ps1 | iex
```

It installs the module for both PowerShell 7 and Windows PowerShell, then runs `Install-RetroLooks`,
which installs the fonts and adds the looks as Windows Terminal profiles. Pixel fonts are sized for your
display scaling so they stay sharp (`Install-RetroLooks -KeepFontSizes` skips that). Then close all
Windows Terminal windows and reopen it: the looks are in the drop-down next to the **+** tab button.
Nothing needs admin rights, and your `settings.json` isn't touched: the profiles are added as a
[Terminal fragment](https://learn.microsoft.com/windows/terminal/json-fragment-extensions).

Prefer to read before you run? [Look at the installer](powershell/install.ps1) and
[the module](powershell/RetroLooks/RetroLooks.psm1), or download `retro-looks-powershell.zip` from the
[latest release](https://github.com/zmbq/vscode-retro/releases/latest), unzip it and run `install.ps1`.

To uninstall (fonts are kept if the VS Code extension still uses them; add `-RemoveFonts` to remove them anyway):

```powershell
& ([scriptblock]::Create((irm https://github.com/zmbq/vscode-retro/releases/latest/download/install.ps1))) -Uninstall
```

or, to keep the module and just remove the profiles and fonts, `Uninstall-RetroLooks`.

On macOS and Linux, install the fonts (see above) and pick them in your terminal's settings. Retro
color schemes for iTerm2, Ghostty, WezTerm, kitty, Alacritty and others are on the
[roadmap](CONTRIBUTING.md#roadmap-and-where-help-is-wanted), and contributions are welcome.

## Tweaking colors

**Windows Terminal:** the monochrome looks come with a color scheme for every preset color, e.g.
*Apple //e Amber* or *IBM 3270 Monochrome Cyan*. To keep, say, a green and an amber Apple //e side by
side: Settings → the Apple //e profile → Duplicate, then pick the other scheme under Appearance. To
fine-tune a scheme, duplicate it under Color schemes and edit the copy.

**VS Code:** for monochrome looks, just pick another color (any `#RRGGBB` works). To override
individual colors of the **IBM 3270** theme, use your `settings.json`:

```jsonc
"workbench.colorCustomizations": {
  "[IBM 3270]": { "editor.background": "#050505" }
},
"editor.tokenColorCustomizations": {
  "[IBM 3270]": { "comments": "#30C0E0" }
}
```

Don't do this for the monochrome themes: while one is active, the extension manages their entries in
these two settings to apply your phosphor color.

**Want a whole new machine?** Clone this repo and ask your AI assistant (Claude Code, GitHub Copilot, …)
to add it. The repo includes instructions for them ([AGENTS.md](AGENTS.md)), and monochrome looks only
need a font and a default color.

**Font size:** pixel fonts are only sharp when every font pixel covers a whole number of screen pixels.
On Windows, the extension reads your display scaling (and VS Code's zoom level) and picks the sharp
size closest to the look's size, e.g. 21.333 at 150% scaling, with a line height that keeps every line on
whole pixels too. Turn this off with the
`retroLooks.pixelPerfectFontSize` setting, or change `editor.fontSize` / `terminal.integrated.fontSize`
after applying a look.

## Credits and licenses

The code and themes are MIT licensed (see [LICENSE](LICENSE)). The fonts are the work of their authors
and are redistributed under their own licenses, included next to each font in [fonts/](fonts/):

- **PR Number 3**, Kreative Software, [Kreative Relay Fonts Free Use License](fonts/pr-number-3/LICENSE.txt)
- **PxPlus IBM VGA 9x16**, VileR, [The Ultimate Oldschool PC Font Pack](https://int10h.org/oldschool-pc-fonts/), [CC BY-SA 4.0](fonts/pxplus-ibm-vga-9x16/LICENSE.txt)
- **IBM 3270**, Ricardo Bánffy and contributors, [3270font](https://github.com/rbanffy/3270font), [BSD 3-Clause](fonts/ibm-3270/LICENSE.txt)

The ISPF colors follow the defaults documented in IBM's *ISPF Edit and Edit Macros* manual.

Retro Looks is a fan project. It is not affiliated with or endorsed by Apple, IBM or any other
company whose products it pays tribute to; their names are used only to describe the look.
