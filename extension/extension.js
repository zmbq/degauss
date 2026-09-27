// Retro Looks: switches theme + fonts together, restores the previous look on "Retro: Off",
// and (on Windows) installs the bundled fonts and the Windows Terminal profiles.
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');

const SAVED_KEY = 'retroLooks.saved';
const REMIND_DISMISSED_KEY = 'retroLooks.installReminderDismissed'; // per machine: fonts are per machine
const FONT_REG_KEY = 'HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts';
const FONT_REG_KEY_MACHINE = 'HKLM\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts';
const isWindows = process.platform === 'win32';

let extensionPath;
const generated = (...parts) => path.join(extensionPath, 'generated', ...parts);
const readJson = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));

function run(command, args) {
  return new Promise((resolve, reject) => {
    execFile(command, args, { windowsHide: true }, (err, stdout) => (err ? reject(err) : resolve(stdout)));
  });
}

// ---------- font size ----------

const pixelPerfect = () => vscode.workspace.getConfiguration('retroLooks').get('pixelPerfectFontSize');

// The Windows display DPI (96 = 100% scaling). Other platforms don't expose it to extensions: 96.
async function windowsDpi() {
  if (!isWindows) return 96;
  try {
    const out = await run('reg', ['query', 'HKCU\\Control Panel\\Desktop\\WindowMetrics', '/v', 'AppliedDPI']);
    const dpi = parseInt(out.match(/REG_DWORD\s+0x([0-9a-f]+)/i)?.[1] ?? '', 16);
    return dpi > 0 ? dpi : 96;
  } catch {
    return 96;
  }
}

// Screen pixels per CSS pixel: display scaling times VS Code's own zoom (each zoom level is 20%).
async function displayScale() {
  const zoomLevel = vscode.workspace.getConfiguration('window').get('zoomLevel') ?? 0;
  return ((await windowsDpi()) / 96) * Math.pow(1.2, zoomLevel);
}

// Windows Terminal sizes fonts in points (screen pixels = points * dpi / 72); pick the sharp size
// closest to the nominal one, like sizesFor() does for VS Code. Keep in sync with install.ps1.
function sharpPoints(points, pixelsPerEm, dpi) {
  const multiple = Math.max(1, Math.round((points * dpi) / 72 / pixelsPerEm));
  return Math.round(((multiple * pixelsPerEm * 72) / dpi) * 1000) / 1000;
}

// Pixel fonts are only sharp when each font pixel covers a whole number of screen pixels, so pick the
// size closest to the look's nominal size for which fontSize * scale is a multiple of the font's grid.
// The editor's line height matters too: VS Code rounds it to whole CSS pixels (1.35 x the font size by
// default), which at fractional scalings can put every line half a screen pixel off the grid. So pick a
// line height close to VS Code's default that is a whole number of screen pixels and leaves an even
// number of spare pixels, so the text is centered on a whole pixel.
// Returns { fontSize, lineHeight }, where lineHeight 0 means VS Code's default.
async function sizesFor(look) {
  const target = look.vscode.fontSize;
  const grid = look.font.pixelsPerEm;
  if (!grid || !pixelPerfect()) {
    return { fontSize: target, lineHeight: 0 };
  }
  const scale = await displayScale();
  const multiple = Math.max(1, Math.round((target * scale) / grid));
  const fontPixels = multiple * grid;
  const fontSize = Math.round((fontPixels / scale) * 1000) / 1000;

  const isWhole = (x) => Math.abs(x - Math.round(x)) < 1e-6;
  const base = Math.round(1.35 * fontSize);
  for (let offset = 0; offset <= 8; offset++) {
    for (const lineHeight of offset ? [base - offset, base + offset] : [base]) {
      const linePixels = lineHeight * scale;
      if (lineHeight >= fontSize && isWhole(linePixels) && Math.round(linePixels - fontPixels) % 2 === 0) {
        return { fontSize, lineHeight };
      }
    }
  }
  return { fontSize, lineHeight: 0 };
}

// ---------- settings ----------

async function lookSettings(look) {
  const { fontSize, lineHeight } = await sizesFor(look);
  return {
    'window.autoDetectColorScheme': false, // otherwise the OS light/dark preference overrides the theme
    'workbench.colorTheme': look.theme,
    'editor.fontFamily': look.fontFamily,
    'editor.fontSize': fontSize,
    'editor.lineHeight': lineHeight,
    'editor.cursorStyle': look.vscode.cursorStyle,
    'terminal.integrated.fontFamily': look.fontFamily,
    'terminal.integrated.fontSize': fontSize,
    'terminal.integrated.cursorStyle': look.vscode.cursorStyle === 'underline' ? 'underline' : 'block',
  };
}

// Remembers the user's own value of each setting a look is about to change. Keys already saved keep
// their true originals; keys not saved yet (e.g. added in a newer version while a look was active)
// still hold the user's own value, since no look has changed them.
async function saveOriginals(context, keys) {
  const config = vscode.workspace.getConfiguration();
  const saved = { ...(context.globalState.get(SAVED_KEY) ?? {}) };
  for (const key of keys) {
    if (key in saved) continue;
    const value = config.inspect(key)?.globalValue;
    saved[key] = value === undefined ? null : value;
  }
  await context.globalState.update(SAVED_KEY, saved);
}

async function applyLook(context, look) {
  let installFonts = false;
  if (isWindows && !(await isFontInstalled(look.font))) {
    const choice = await vscode.window.showWarningMessage(
      `The "${look.font.family}" font isn't installed yet.`,
      'Install Fonts', 'Apply Anyway'
    );
    if (!choice) return;
    installFonts = choice === 'Install Fonts';
  }
  const settings = await lookSettings(look);
  await saveOriginals(context, Object.keys(settings));
  const config = vscode.workspace.getConfiguration();
  for (const [key, value] of Object.entries(settings)) {
    await config.update(key, value, vscode.ConfigurationTarget.Global);
  }
  // Install last: its message offers to quit VS Code, and the look must be saved before that.
  if (installFonts) await install();
}

async function restore(context, quiet = false) {
  const saved = context.globalState.get(SAVED_KEY);
  if (!saved) {
    if (!quiet) vscode.window.showInformationMessage('Retro Looks: no retro look is active.');
    return;
  }
  const config = vscode.workspace.getConfiguration();
  for (const [key, value] of Object.entries(saved)) {
    await config.update(key, value === null ? undefined : value, vscode.ConfigurationTarget.Global);
  }
  await context.globalState.update(SAVED_KEY, undefined);
}

async function choose(context, looks) {
  const picked = await vscode.window.showQuickPick(
    [
      ...looks.map((look) => ({ label: look.name, detail: look.description, look })),
      { label: 'Off', detail: 'Restore the theme and fonts you had before' },
    ],
    { placeHolder: 'Choose a retro look' }
  );
  if (!picked) return;
  if (picked.look) await applyLook(context, picked.look);
  else await restore(context);
}

// ---------- Windows install ----------

function windowsPaths() {
  const local = process.env.LOCALAPPDATA;
  return {
    fontDir: path.join(local, 'Microsoft', 'Windows', 'Fonts'),
    fragmentDir: path.join(local, 'Microsoft', 'Windows Terminal', 'Fragments', 'Retro Looks'),
  };
}

async function registryHasValue(key, name) {
  try {
    await run('reg', ['query', key, '/v', name]);
    return true;
  } catch {
    return false;
  }
}

async function isFontInstalled(font) {
  return (await registryHasValue(FONT_REG_KEY, font.registryName))
    || (await registryHasValue(FONT_REG_KEY_MACHINE, font.registryName));
}

async function shellCommandline() {
  try {
    await run('where', ['pwsh.exe']);
    return 'pwsh.exe -NoLogo';
  } catch {
    return 'powershell.exe -NoLogo';
  }
}

async function install() {
  if (!isWindows) {
    const choice = await vscode.window.showInformationMessage(
      'Automatic font installation is Windows-only for now. Install the fonts from the bundled fonts folder with your system\'s font installer.',
      'Open Fonts Folder'
    );
    if (choice) openFonts();
    return;
  }
  const { fontDir, fragmentDir } = windowsPaths();
  fs.mkdirSync(fontDir, { recursive: true });
  const fonts = readJson(generated('fonts.json'));
  for (const font of fonts) {
    const source = generated('fonts', font.id, font.file);
    const dest = path.join(fontDir, font.installedFile);
    // Installed fonts may be locked by running apps; identical files don't need copying.
    if (!fs.existsSync(dest) || fs.statSync(dest).size !== fs.statSync(source).size) fs.copyFileSync(source, dest);
    await run('reg', ['add', FONT_REG_KEY, '/v', font.registryName, '/t', 'REG_SZ', '/d', dest, '/f']);
  }

  const fragment = readJson(generated('terminal', 'retro-looks.json'));
  const commandline = await shellCommandline();
  const dpi = await windowsDpi();
  for (const profile of fragment.profiles) {
    profile.commandline = commandline;
    const grid = fonts.find((f) => f.family === profile.font.face)?.pixelsPerEm;
    if (grid && pixelPerfect()) profile.font.size = sharpPoints(profile.font.size, grid, dpi);
  }
  fs.mkdirSync(fragmentDir, { recursive: true });
  fs.writeFileSync(path.join(fragmentDir, 'retro-looks.json'), JSON.stringify(fragment, null, 2));

  // A running VS Code keeps the font list it loaded at startup; reloading the window doesn't refresh it,
  // and extensions can't relaunch VS Code, so the best we can offer is quitting.
  const choice = await vscode.window.showInformationMessage(
    'Retro Looks: fonts and Windows Terminal profiles installed. Quit VS Code and start it again to see the '
      + 'new fonts (reloading the window isn\'t enough). Close all Windows Terminal windows too.',
    'Quit VS Code', 'Later'
  );
  if (choice === 'Quit VS Code') await vscode.commands.executeCommand('workbench.action.quit');
}

async function uninstall(context) {
  if (!isWindows) {
    vscode.window.showInformationMessage('Retro Looks only installs fonts automatically on Windows.');
    return;
  }
  await restore(context, true);
  const { fontDir, fragmentDir } = windowsPaths();
  const locked = [];
  for (const font of readJson(generated('fonts.json'))) {
    const file = path.join(fontDir, font.installedFile);
    // Only remove registrations that point at our own file, not a copy the user installed themselves.
    try {
      const out = await run('reg', ['query', FONT_REG_KEY, '/v', font.registryName]);
      if (out.includes(font.installedFile)) await run('reg', ['delete', FONT_REG_KEY, '/v', font.registryName, '/f']);
    } catch { /* not registered */ }
    try {
      fs.rmSync(file, { force: true });
    } catch {
      locked.push(font.installedFile);
    }
  }
  fs.rmSync(fragmentDir, { recursive: true, force: true });
  // Someone who just removed the fonts doesn't want to be asked to install them at the next startup.
  await context.globalState.update(REMIND_DISMISSED_KEY, true);
  const suffix = locked.length
    ? ` These font files are in use and couldn't be deleted; they're no longer registered and can be deleted from ${windowsPaths().fontDir} later: ${locked.join(', ')}.`
    : '';
  vscode.window.showInformationMessage(`Retro Looks: fonts and Windows Terminal profiles removed.${suffix}`);
}

function openFonts() {
  vscode.env.openExternal(vscode.Uri.file(generated('fonts')));
}

// ---------- startup reminder ----------

async function remindToInstall(context) {
  if (context.globalState.get(REMIND_DISMISSED_KEY)) return;

  if (!isWindows) {
    // Font installation can't be checked outside Windows yet, so just point at the fonts once.
    await context.globalState.update(REMIND_DISMISSED_KEY, true);
    const choice = await vscode.window.showInformationMessage(
      'Retro Looks needs its fonts installed. Install them with your system\'s font installer.',
      'Open Fonts Folder'
    );
    if (choice) openFonts();
    return;
  }

  const fonts = readJson(generated('fonts.json'));
  const installed = await Promise.all(fonts.map(isFontInstalled));
  if (installed.every(Boolean)) return;

  const choice = await vscode.window.showInformationMessage(
    'Retro Looks: install the retro fonts and Windows Terminal profiles? The looks need them.',
    'Install', 'Later', 'Don\'t Show Again'
  );
  if (choice === 'Install') await install();
  else if (choice === 'Don\'t Show Again') await context.globalState.update(REMIND_DISMISSED_KEY, true);
}

// ---------- activation ----------

function activate(context) {
  extensionPath = context.extensionPath;
  const looks = readJson(generated('looks.json'));
  const register = (id, fn) => context.subscriptions.push(vscode.commands.registerCommand(id, fn));

  for (const look of looks) register(`retroLooks.apply.${look.id}`, () => applyLook(context, look));
  register('retroLooks.choose', () => choose(context, looks));
  register('retroLooks.off', () => restore(context));
  register('retroLooks.install', () => install());
  register('retroLooks.uninstall', () => uninstall(context));
  register('retroLooks.openFonts', () => openFonts());

  remindToInstall(context).catch((err) => console.error('Retro Looks: install reminder failed', err));
}

module.exports = { activate, deactivate() {} };
