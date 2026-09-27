# Instructions for AI coding assistants

Retro Looks gives VS Code and Windows Terminal the look of vintage computers: a period font plus
matching color schemes. People will often ask you to **add a new look** ("add a Commodore 64") or
**change colors** ("I want a cyan Apple //e", "make the amber darker"). This file tells you how. `CONTRIBUTING.md` has the same information for humans; read it too.

## Layout

- `looks/<look-id>/look.json`: one folder per look. Monochrome looks have a `"monochrome"` section
  (`style` and `defaultColor`); color looks have `vscode-theme.json` + `terminal-scheme.json` next to it.
- `fonts/<font-id>/`: the font file, its `LICENSE.txt` (verbatim) and `font.json`.
- `tools/build.mjs`: generates everything else. `tools/templates/<style>-*.json` are the templates
  monochrome looks are generated from (`phosphor`: smooth shades, like the Apple //e; `intensity`: two
  brightness levels, like the IBM 3278); `${slot}` placeholders are filled by `phosphorPalette()`.
- `vscode/palette.js`: the color presets and the palette math, shared by the build and the extension
  (which recolors monochrome looks at runtime with the user's chosen color).
- Degauss (**Retro: Degauss**, `degauss`): `tools/degauss-sound.mjs` synthesizes the sound at build time
  (no recording, so no license to track); the effect is `vscode/degauss.js` in VS Code (temporary editor
  decorations, never settings) and `Invoke-RetroDegauss` in the module (color escape sequences).
- `vscode/`: **project 1**, the VS Code extension. `extension.js` is hand-written; `package.json`'s
  `contributes` and all of `vscode/generated/` are produced by the build. Never edit those by hand.
  It installs fonts only; Windows Terminal is not its job.
- `powershell/`: **project 2**, the RetroLooks PowerShell module for Windows Terminal
  (`RetroLooks/RetroLooks.psm1`, `.psd1`) and `install.ps1`, which installs the module and runs it.
  Both must keep working on Windows PowerShell 5.1 (no `??`, no ternaries, no `&&`; and 5.1's
  `ConvertFrom-Json` returns a JSON array as one object, so enumerate it explicitly).
- The two projects share only the fonts: same folder, file names and registry names (from the build's
  `fonts.json`). Each project that uses the fonts leaves a marker file in `%LOCALAPPDATA%\RetroLooks\font-users`
  (`vscode/fonts.js`, `RetroLooks.psm1`); uninstalling removes its own marker and removes the fonts only if
  no marker is left. Keep it that way, and give any new installer its own marker. The extension's
  `vscode/uninstall.js` (VS Code's `vscode:uninstall` hook) does the same when it's removed from the Extensions view.
- **Versions:** each product has its own. The extension's is `version` in `vscode/package.json`, the
  module's is `ModuleVersion` in `powershell/RetroLooks/RetroLooks.psd1`, each with its own changelog
  (`vscode/CHANGELOG.md`, `powershell/CHANGELOG.md`), and each is released on its own Git tag:
  `vscode-v1.2.3` or `powershell-v1.2.3` (`.github/workflows/release-<product>.yml` checks the tag matches the
  version and uses the changelog entry as the release notes). Module releases are GitHub's "latest"
  release, because `install.ps1` downloads from it. When a product changes, bump its version and add a
  changelog entry.
- The PowerShell module repeats `vscode/palette.js`'s color math (`Get-PhosphorPalette` and friends in
  `RetroLooks.psm1`) to recolor tabs at runtime. Change both together; the PowerShell tests compare them
  color by color. Watch PowerShell's overload resolution: `[math]::Max(0, $x)` picks the integer overload.

## Commands

- Build: `node tools/build.mjs` (no npm install needed). Run it after every change and fix any error it reports.
- Test: `npm test` (builds, then runs `tests/**/*.test.js` with Node's test runner) and, on Windows,
  `pwsh -File tests/powershell/RetroLooks.tests.ps1` (the module and its installer, against a sandbox, in
  both PowerShells). Both run in CI and must pass. Add tests for new behavior;
  `tests/vscode/helpers/fake-vscode.js` drives the extension without VS Code.
- Package the extension: `npm run package` → `dist/vscode-retro-<version>.vsix`.
- Try it: F5 in VS Code ("Run Retro Looks"), or `code --install-extension dist/vscode-retro-<version>.vsix`.
- Try the Terminal side: run `dist/powershell/install.ps1`, then restart Windows Terminal.

## Recipe: a different color for a monochrome look (the most common request)

Usually **no code change is needed**: users pick any color themselves (VS Code: **Retro: Set Phosphor
Color…** or the `retroLooks.phosphorColors` setting, e.g. `{ "apple2e": "#40E0FF" }`; Windows Terminal:
the preset color schemes). Tell them that first.

To add a new **preset** for everyone, add it to `PRESETS` in `vscode/palette.js` (a name and a
`#RRGGBB`) and to the preset lists in `README.md` and `vscode/README.md`. Every monochrome look then gets it in VS Code and a
Terminal scheme for it. Softer, less saturated colors are easier on the eyes on large modern screens.

To change how monochrome looks map shades to UI elements, edit the templates or `phosphorPalette()`.
That affects every monochrome look and every color, so check several.

## Recipe: a new machine

1. **Font first.** Find a font that recreates the machine's actual character set, and confirm from its
   license text that redistribution is allowed. Add it under `fonts/<font-id>/` with `font.json`
   (see an existing one) and the license **verbatim** as `LICENSE.txt`. For a pixel font, set
   `pixelsPerEm` (units-per-em ÷ one pixel's size in font units) so the extension can size it sharply;
   read the numbers from the font's `head`/`hmtx` tables rather than guessing. `family` must be the exact
   family name inside the font file. If you can't verify the license, stop and tell the user.
   Never modify, rename or re-encode font files.
2. Create `looks/<look-id>/look.json` like the existing ones, with a **new** GUID for `terminal.guid`
   (`[guid]::NewGuid()` or `crypto.randomUUID()`, formatted `{xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx}`).
   Never reuse or change an existing GUID; Windows Terminal ties users' settings to it. Give it `aliases`
   (the short names the Terminal `look` command accepts, e.g. `["c64"]`; they must be unique across looks).
3. Colors: a monochrome machine gets `"monochrome": { "style": "phosphor", "defaultColor": "green" }`
   (or `"intensity"` for terminals with only normal and bright text). A color machine gets `vscode-theme.json` (a VS Code
   color theme without `name`) and `terminal-scheme.json` (a Windows Terminal scheme without `name`, with
   all 16 ANSI colors plus `background`, `foreground`, `cursorColor`, `selectionBackground`). Start from
   `looks/ibm-3270/`. Use the machine's real palette and default colors.
   A look can be **Windows Terminal only**: leave out the `vscode` section and `vscode-theme.json`
   (see `looks/ibm-ps2-vga/`). Do that when a VS Code theme wouldn't look good yet, rather than shipping an ugly one.
4. Build, then update `README.md` and, for VS Code looks, `vscode/README.md` (the extension's Marketplace
   page): the looks table and the font credit.

## Rules

- **Historical accuracy matters.** Use the machine's real fonts, colors and screen behavior. Don't invent
  details: if you aren't sure how the machine looked (e.g. whether its text mode had color), say so and
  ask. Users of this project remember these machines well.
- Don't add fonts with unclear or non-redistributable licenses, and keep each font's license next to it.
- Keep the Retro naming: look names are the machine's name plus the variant, e.g. "IBM 3270 Monochrome".
  Monochrome looks aren't named after a color; the color is the user's choice.
- Keep `FONT_FILE_PREFIX` (build.mjs) and `$script:FontFilePrefix` (RetroLooks.psm1) in sync; the module
  uses the prefix to find and uninstall fonts, including ones from older versions.
- Don't commit generated files (`vscode/generated/`, `dist/`, the copied files listed in `.gitignore`).
- For anything user-visible, bump the changed product's version and add an entry to its changelog.

## If the user just wants a personal tweak

They may not need a new look at all. Without building anything:

- Monochrome looks: any color via **Retro: Set Phosphor Color…** (VS Code) or a preset scheme (Terminal).
- VS Code, color looks: override colors for one theme in their user `settings.json` with
  `"workbench.colorCustomizations": { "[IBM 3270]": { ... } }` and
  `"editor.tokenColorCustomizations": { "[IBM 3270]": { ... } }`. Not for monochrome themes: the extension
  manages their entries in those settings.
- Windows Terminal: duplicate the scheme in Settings → Color schemes and edit the copy.

Offer this when they only want to adjust colors on their own machine; build a new look when they want
it in the extension or want to contribute it.
