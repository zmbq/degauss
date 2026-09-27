// VS Code runs this after the extension is uninstalled ("vscode:uninstall" in package.json), including
// from the Extensions view, so the fonts don't stay behind. It runs in plain Node, without the VS Code API.
// The fonts are only removed if no other project (the Degauss PowerShell module) still uses them.
const fs = require('fs');
const path = require('path');
const fonts = require('./fonts');

async function main() {
  if (process.platform !== 'win32' || !process.env.LOCALAPPDATA) return;
  fonts.removeMarker();
  if (fonts.otherFontUsers().length) return;
  const list = JSON.parse(fs.readFileSync(path.join(__dirname, 'generated', 'fonts.json'), 'utf8'));
  await fonts.removeFonts(list);
}

main().catch(() => { /* nothing useful to do without a UI */ });
