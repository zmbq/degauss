# Copilot instructions

Follow the project instructions in [AGENTS.md](../AGENTS.md) at the repository root. They explain how to
add a new look or color variant (for example "add a white phosphor Apple //e" or "add a Commodore 64"),
how to build (`node tools/build.mjs`) and the rules for fonts, licenses and historical accuracy.

Key points, in case AGENTS.md isn't loaded:

- Looks live in `looks/<id>/look.json`. Monochrome monitors only need a `"phosphor": "#RRGGBB"` color;
  the build generates the VS Code theme and Windows Terminal scheme from it.
- Every new look needs a new, never-changing GUID in `terminal.guid`.
- Fonts live in `fonts/<id>/` with their license verbatim. Never modify font files or add fonts whose
  license doesn't allow redistribution.
- Never edit `extension/generated/` or the `contributes` section of `extension/package.json`; run the build.
- Be historically accurate, and ask rather than guess about how a machine really looked.
