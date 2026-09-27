// Installs and removes the Degauss fonts on Windows (current user only). Plain Node, no VS Code API,
// so the extension's uninstall hook (uninstall.js) can use it too.
//
// The Degauss PowerShell module installs the same fonts, in the same place, under the same names.
// Each project that uses the fonts leaves a marker file in %LOCALAPPDATA%\Degauss\font-users; the
// fonts are only removed once no marker is left, so uninstalling one project never breaks the other.
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const MARKER = 'vscode';
// The tests point this at a throwaway key (and LOCALAPPDATA at a temporary folder).
const fontKey = () => process.env.DEGAUSS_TEST_FONT_KEY || 'HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts';
const FONT_KEY_MACHINE = 'HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts';
const fontDir = () => path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Windows', 'Fonts');
const fontUsersDir = () => path.join(process.env.LOCALAPPDATA, 'Degauss', 'font-users');

function run(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { windowsHide: true }, (err, stdout) => (err ? reject(err) : resolve(stdout)));
  });
}

async function registryHasValue(key, name) {
  try {
    await run('reg', ['query', key, '/v', name]);
    return true;
  } catch {
    return false;
  }
}

// Installed for this user by Degauss, or by the user themselves for the whole machine.
async function isFontInstalled(font) {
  return (await registryHasValue(fontKey(), font.registryName)) || (await registryHasValue(FONT_KEY_MACHINE, font.registryName));
}

// ---------- markers ----------

function addMarker(description) {
  fs.mkdirSync(fontUsersDir(), { recursive: true });
  fs.writeFileSync(path.join(fontUsersDir(), MARKER), `${description}, ${new Date().toISOString()}\n`);
}

function hasMarker() {
  return fs.existsSync(path.join(fontUsersDir(), MARKER));
}

function removeMarker() {
  fs.rmSync(path.join(fontUsersDir(), MARKER), { force: true });
  // Leave nothing behind once no project uses the fonts.
  for (const dir of [fontUsersDir(), path.dirname(fontUsersDir())]) {
    try { fs.rmdirSync(dir); } catch { /* not empty, or not there */ }
  }
}

// The other projects still using the fonts (marker names, e.g. "powershell").
function otherFontUsers() {
  try {
    return fs.readdirSync(fontUsersDir()).filter((name) => name !== MARKER);
  } catch {
    return [];
  }
}

// ---------- fonts ----------

// fonts: the build's fonts.json; sourceDir: the folder holding <id>/<file> for each font.
async function installFonts(fonts, sourceDir, description) {
  fs.mkdirSync(fontDir(), { recursive: true });
  for (const font of fonts) {
    const source = path.join(sourceDir, font.id, font.file);
    const dest = path.join(fontDir(), font.installedFile);
    // Installed fonts may be locked by running apps; identical files don't need copying.
    if (!fs.existsSync(dest) || fs.statSync(dest).size !== fs.statSync(source).size) fs.copyFileSync(source, dest);
    await run('reg', ['add', fontKey(), '/v', font.registryName, '/t', 'REG_SZ', '/d', dest, '/f']);
  }
  addMarker(description);
}

// Removes the fonts (whoever else uses them; check otherFontUsers() first). Returns the file names that
// couldn't be deleted because they're in use; they're unregistered either way.
async function removeFonts(fonts) {
  const locked = [];
  for (const font of fonts) {
    // Only remove registrations that point at our own file, not a copy the user installed themselves.
    try {
      const out = await run('reg', ['query', fontKey(), '/v', font.registryName]);
      if (out.includes(font.installedFile)) await run('reg', ['delete', fontKey(), '/v', font.registryName, '/f']);
    } catch { /* not registered */ }
    try {
      fs.rmSync(path.join(fontDir(), font.installedFile), { force: true });
    } catch {
      locked.push(font.installedFile);
    }
  }
  return locked;
}

module.exports = {
  isFontInstalled, installFonts, removeFonts, addMarker, hasMarker, removeMarker, otherFontUsers, fontDir,
};
