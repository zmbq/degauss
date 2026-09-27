# Copilot instructions

Follow the project instructions in [AGENTS.md](../AGENTS.md) at the repository root. They explain how to
add a new look or change colors (for example "make my Apple //e cyan" or "add a Commodore 64"), how to
build and test (`npm test`) and the rules for fonts, licenses and historical accuracy.

Key points, in case AGENTS.md isn't loaded:

- Users choose monochrome looks' colors themselves (VS Code: **Retro: Set Phosphor Color…** or the
  `retroLooks.phosphorColors` setting), so a new color rarely needs code. New presets go in
  `extension/palette.js`.
- Looks live in `looks/<id>/look.json`. Monochrome monitors need a `"monochrome"` section with a `style`
  and `defaultColor`; the build generates the VS Code theme and Windows Terminal schemes from templates.
- Every new look needs a new, never-changing GUID in `terminal.guid`.
- Fonts live in `fonts/<id>/` with their license verbatim. Never modify font files or add fonts whose
  license doesn't allow redistribution.
- Never edit `extension/generated/` or the `contributes` section of `extension/package.json`; run the build.
- Run `npm test` (and `tests/installer.tests.ps1` on Windows) before finishing; add tests for new behavior.
- Be historically accurate, and ask rather than guess about how a machine really looked.
