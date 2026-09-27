# Instructions for AI coding assistants

Retro Looks gives VS Code and Windows Terminal the look of vintage computers: a period font plus
matching color schemes. People will often ask you to **add a new look** ("add a Commodore 64") or
**a new color variant** ("I want a white phosphor Apple //e", "make the amber darker"). This file
tells you how. `CONTRIBUTING.md` has the same information for humans; read it too.

## Layout

- `looks/<look-id>/look.json`: one folder per look. Either a `"phosphor"` color (monochrome monitors)
  or `vscode-theme.json` + `terminal-scheme.json` next to it.
- `fonts/<font-id>/`: the font file, its `LICENSE.txt` (verbatim) and `font.json`.
- `tools/build.mjs`: generates everything else. `tools/templates/phosphor-*.json` are the templates
  monochrome looks are generated from; `${slot}` placeholders are filled by `phosphorPalette()`.
- `extension/`: the VS Code extension. `extension.js` is hand-written; `package.json`'s `contributes`
  section and all of `extension/generated/` are produced by the build. Never edit those by hand.
- `installer/install.ps1`: the Windows Terminal installer. Must keep working on Windows PowerShell 5.1
  (no `??`, no ternaries, no `&&` in the script).

## Commands

- Build: `node tools/build.mjs` (no npm install needed). Run it after every change and fix any error it reports.
- Package the extension: `npm run package` → `dist/vscode-retro-<version>.vsix`.
- Try it: F5 in VS Code ("Run Retro Looks"), or `code --install-extension dist/vscode-retro-<version>.vsix`.
- Try the Terminal side: run `dist/terminal/install.ps1`, then restart Windows Terminal.

## Recipe: a new monochrome color (the most common request)

1. Copy the closest existing phosphor look, e.g. `looks/apple2e-green/` → `looks/apple2e-white/`.
2. In the new `look.json`: set `name`, `description`, `order`, and `phosphor` to the monitor's color.
   Reference points: P1 green ≈ `#40F040`, P3 amber ≈ `#F0A848`, P4 white ≈ `#E8E8E0`.
   Softer, less saturated colors are easier on the eyes on large modern screens.
3. Generate a **new** GUID for `terminal.guid` (`[guid]::NewGuid()` or `crypto.randomUUID()`),
   formatted as `{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`. Never reuse or change an existing GUID.
4. Run the build. The VS Code theme and the Terminal scheme are generated from the one color.
5. Add the look to the table in `README.md`.

To make an existing phosphor look brighter or dimmer, change its `phosphor` color. To change how all
phosphor looks map shades to UI elements, edit the templates or `phosphorPalette()`. That affects every
monochrome look, so check them all.

## Recipe: a new machine

1. **Font first.** Find a font that recreates the machine's actual character set, and confirm from its
   license text that redistribution is allowed. Add it under `fonts/<font-id>/` with `font.json`
   (see an existing one) and the license **verbatim** as `LICENSE.txt`. `family` must be the exact
   family name inside the font file. If you can't verify the license, stop and tell the user.
   Never modify, rename or re-encode font files.
2. Create `looks/<look-id>/look.json` like the existing ones, with a new GUID.
3. Colors: a monochrome machine gets `"phosphor"`. A color machine gets `vscode-theme.json` (a VS Code
   color theme without `name`) and `terminal-scheme.json` (a Windows Terminal scheme without `name`, with
   all 16 ANSI colors plus `background`, `foreground`, `cursorColor`, `selectionBackground`). Start from
   `looks/ibm-3270/` or `looks/ibm-ps2-vga/`. Use the machine's real palette and default colors.
4. Build, then update `README.md` (the looks table and the font credit).

## Rules

- **Historical accuracy matters.** Use the machine's real fonts, colors and screen behavior. Don't invent
  details: if you aren't sure how the machine looked (e.g. whether its text mode had color), say so and
  ask. Users of this project remember these machines well.
- Don't add fonts with unclear or non-redistributable licenses, and keep each font's license next to it.
- Keep the Retro naming: look names are the machine's name plus the variant, e.g. "Apple //e Amber".
- Keep `FONT_FILE_PREFIX` (build.mjs), `$FontFilePrefix` (install.ps1) and the `(TrueType)` registry
  name format in sync; the installer and extension use them to find and uninstall fonts.
- Don't commit generated files (`extension/generated/`, `dist/`, the copied files listed in `.gitignore`).
- Bump `extension/package.json` `version` and add a `CHANGELOG.md` entry for anything user-visible.

## If the user just wants a personal tweak

They may not need a new look at all. Without building anything:

- VS Code: override colors for one theme in their user `settings.json` with
  `"workbench.colorCustomizations": { "[Apple //e Amber]": { ... } }` and
  `"editor.tokenColorCustomizations": { "[Apple //e Amber]": { ... } }`.
- Windows Terminal: duplicate the scheme in Settings → Color schemes and edit the copy.

Offer this when they only want to adjust colors on their own machine; build a new look when they want
it in the extension or want to contribute it.
