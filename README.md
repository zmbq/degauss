# Retro Looks

Vintage computer looks for **VS Code** and **Windows Terminal**: period-correct fonts and color schemes
from the machines we grew up on.

| Look | Font | What it looks like |
|---|---|---|
| **Apple //e Green** | PR Number 3 (the //e 80-column font) | Green phosphor monitor, like Apple's own Monitor II |
| **Apple //e Amber** | PR Number 3 | Amber monitor, the popular third-party alternative |
| **IBM PS/2 VGA** *(Windows Terminal only)* | PxPlus IBM VGA 9x16 | The black DOS prompt with the 16 VGA colors |
| **IBM 3270** | IBM 3270 | Mainframe green screen with the default ISPF editor highlighting |

Want a Commodore 64, a classic Mac or a CP/M machine, or a VS Code version of the PS/2 look? [Add it!](CONTRIBUTING.md)

## VS Code

Install **Retro Looks** from the Marketplace (or Open VSX), then open the Command Palette
(`Ctrl+Shift+P`) and run **Retro: Choose Look…**, or one of the **Retro: …** commands directly.

- A look sets the color theme, the editor and terminal fonts, font size and cursor.
- **Retro: Off** puts back exactly what you had before.
- On Windows, the extension offers to install its fonts when VS Code starts (for your user only,
  no admin needed), until you install them or choose **Don't Show Again**. You can also run
  **Retro: Install Fonts and Windows Terminal Profiles**, which installs the fonts plus the
  Windows Terminal profiles.
- On macOS and Linux, run **Retro: Open Bundled Fonts Folder** and install the fonts with your
  system's font installer. Automatic installation there is on the to-do list.
- Works in Remote SSH, WSL and container windows: the extension runs on your local machine.

The themes are also available on their own through the normal theme picker (`Ctrl+K Ctrl+T`), and
you can use any of the fonts with any theme.

## Windows Terminal

Paste this into PowerShell:

```powershell
irm https://github.com/zmbq/vscode-retro/releases/latest/download/install.ps1 | iex
```

Then close all Windows Terminal windows and reopen it. The looks appear as new profiles in the
drop-down next to the **+** tab button. Nothing needs admin rights, and your `settings.json` isn't
touched: the profiles are added as a [Terminal fragment](https://learn.microsoft.com/windows/terminal/json-fragment-extensions).

Prefer to read before you run? [Look at the script](installer/install.ps1), or download
`retro-looks-terminal.zip` from the [latest release](https://github.com/zmbq/vscode-retro/releases/latest),
unzip it and run `install.ps1`.

To uninstall:

```powershell
& ([scriptblock]::Create((irm https://github.com/zmbq/vscode-retro/releases/latest/download/install.ps1))) -Uninstall
```

## Tweaking colors

**Windows Terminal:** Settings → Color schemes → pick a Retro scheme → Duplicate, then edit the copy
and select it in the profile's Appearance settings.

**VS Code:** override any color for just one theme in your `settings.json`:

```jsonc
"workbench.colorCustomizations": {
  "[Apple //e Amber]": { "editor.background": "#1A1000" }
},
"editor.tokenColorCustomizations": {
  "[Apple //e Amber]": { "comments": "#9A6A20" }
}
```

**Want a whole new color,** like a white phosphor monitor? Clone this repo and ask your AI assistant
(Claude Code, GitHub Copilot, …) to "add a white phosphor Apple //e look". The repo includes instructions
for them ([AGENTS.md](AGENTS.md)), and monochrome looks only need one color.

To use a different font size, change `editor.fontSize` / `terminal.integrated.fontSize` after applying
a look. Pixel fonts look sharpest at particular sizes, so try a few.

## Credits and licenses

The code and themes are MIT licensed (see [LICENSE](LICENSE)). The fonts are the work of their authors
and are redistributed under their own licenses, included next to each font in [fonts/](fonts/):

- **PR Number 3**, Kreative Software, [Kreative Relay Fonts Free Use License](fonts/pr-number-3/LICENSE.txt)
- **PxPlus IBM VGA 9x16**, VileR, [The Ultimate Oldschool PC Font Pack](https://int10h.org/oldschool-pc-fonts/), [CC BY-SA 4.0](fonts/pxplus-ibm-vga-9x16/LICENSE.txt)
- **IBM 3270**, Ricardo Bánffy and contributors, [3270font](https://github.com/rbanffy/3270font), [BSD 3-Clause](fonts/ibm-3270/LICENSE.txt)

The ISPF colors follow the defaults documented in IBM's *ISPF Edit and Edit Macros* manual.

Retro Looks is a fan project. It is not affiliated with or endorsed by Apple, IBM or any other
company whose products it pays tribute to; their names are used only to describe the look.
