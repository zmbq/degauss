# Retro Looks

Code on the machines you grew up on. Retro Looks gives VS Code the look of vintage computers: each
look sets a period-correct **font**, a matching **color theme** and the right **cursor**, in one step,
and puts your own setup back when you're done.

![VS Code with the Apple //e look in amber](https://raw.githubusercontent.com/zmbq/vscode-retro/main/docs/images/hero.png)

## The looks

| Look | Font | What it looks like |
|---|---|---|
| **Apple //e** | PR Number 3, the //e 80-column font | A monochrome monitor in the phosphor color of your choice |
| **IBM 3270** | IBM 3270 | A mainframe color terminal with the default ISPF editor highlighting: green text, turquoise comments, red keywords, white strings, blue directives, yellow operators |
| **IBM 3270 Monochrome** | IBM 3270 | A 3278-style monochrome terminal: ISPF's colors become normal and intensified text, in the phosphor color of your choice |

![Apple //e in green](https://raw.githubusercontent.com/zmbq/vscode-retro/main/docs/images/apple2e-green.png)

![IBM 3270 with the ISPF editor colors](https://raw.githubusercontent.com/zmbq/vscode-retro/main/docs/images/ibm-3270.png)

![IBM 3270 Monochrome in green](https://raw.githubusercontent.com/zmbq/vscode-retro/main/docs/images/ibm-3270-mono.png)

## Getting started

1. Install the extension. On Windows, it offers to install its fonts right away (for your user only,
   no admin needed). Click **Install**, then quit and restart VS Code: VS Code only sees new fonts after a
   full restart, and reloading the window isn't enough.
2. Open the Command Palette (`Ctrl+Shift+P`) and run **Retro: Choose Look…**.
3. For a monochrome look, pick a phosphor color.

![The Retro: Choose Look list](https://raw.githubusercontent.com/zmbq/vscode-retro/main/docs/images/choose-look.png)

**Retro: Off** puts your own theme, fonts and settings back, exactly as they were.

## Phosphor colors

Monochrome monitors came in different colors, and some 80-column cards even let you pick one with DIP
switches. Monochrome looks ask for their color when you choose them: **green**, **amber**, **white**,
**cyan**, **yellow**, or **Custom…** for any `#RRGGBB`. Change it any time with
**Retro: Set Phosphor Color…**. The change is instant.

![Choosing a phosphor color](https://raw.githubusercontent.com/zmbq/vscode-retro/main/docs/images/phosphor-colors.png)

Each look remembers its own color, so your Apple //e can be amber while your 3270 stays green. The
colors are stored in the `retroLooks.phosphorColors` setting, e.g. `{ "apple2e": "#40E0FF" }`, if you'd
rather edit them by hand. Very dark colors are brightened so the text stays readable.

## Sharp pixel fonts

Pixel fonts blur when a font pixel doesn't land on whole screen pixels. On Windows, Retro Looks reads
your display scaling (and VS Code's zoom level) and picks the sharp font size closest to the look's
size, with a line height to match: for example 21.333 with 28-pixel lines at 150% scaling. Turn this
off with `retroLooks.pixelPerfectFontSize`.

## Works everywhere you do

The extension runs on your local machine, so the looks work the same in Remote SSH, WSL and container
windows. VS Code's built-in terminal follows the look too.

## Windows Terminal

Want the same looks in Windows Terminal? That's a separate part of Retro Looks, a PowerShell module,
with `look` and `color` commands (`look apple -Color amber`, `color 0A`) and IBM PS/2 looks too. See
[Retro Looks for Windows Terminal](https://github.com/zmbq/vscode-retro#windows-terminal). It shares the
fonts with the extension, and neither removes fonts the other still uses.

## Uninstalling

**Run Retro: Off before you uninstall.** It restores your theme, fonts and settings. The extension can't
do that once it's uninstalled: VS Code would fall back to its default theme and leave the retro font
size, line height and cursor in your settings.

Uninstalling the extension removes its fonts too (the next time VS Code starts), unless Retro Looks for
Windows Terminal still uses them. Forgot to turn it off? Reinstall the extension
and run **Retro: Off**: it still remembers your original settings.

## Commands

| Command | What it does |
|---|---|
| Retro: Choose Look… | Pick a look (and a color, for monochrome looks) |
| Retro: Apple //e, Retro: IBM 3270, … | Apply a look directly, in its remembered color |
| Retro: Set Phosphor Color… | Change the color of the active monochrome look |
| Retro: Off | Put your own theme, fonts and settings back |
| Retro: Install Fonts | Install the fonts (Windows; only shown while they're missing) |
| Retro: Open Bundled Fonts Folder | Open the fonts, to install them by hand on macOS or Linux |

The themes are also available on their own in the normal theme picker (`Ctrl+K Ctrl+T`), and you can use
the fonts with any theme.

## macOS and Linux

The looks work, but the fonts aren't installed automatically yet: run **Retro: Open Bundled Fonts
Folder** and install them with your system's font installer. Automatic installation is next on the
[roadmap](https://github.com/zmbq/vscode-retro/blob/main/CONTRIBUTING.md#roadmap-and-where-help-is-wanted).

## Credits

The fonts are the work of their authors and keep their own licenses (see THIRD-PARTY-NOTICES.md):
**PR Number 3** by Kreative Software, **PxPlus IBM VGA 9x16** by VileR
([The Ultimate Oldschool PC Font Pack](https://int10h.org/oldschool-pc-fonts/)), and **IBM 3270** by
Ricardo Bánffy and contributors ([3270font](https://github.com/rbanffy/3270font)). The ISPF colors follow
IBM's *ISPF Edit and Edit Macros* manual.

Want another machine, like a Commodore 64 or a classic Mac?
[Contributions are welcome](https://github.com/zmbq/vscode-retro/blob/main/CONTRIBUTING.md).

Retro Looks is a fan project, not affiliated with or endorsed by Apple, IBM or any other company whose
products it pays tribute to; their names are used only to describe the look.
