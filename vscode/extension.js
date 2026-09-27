// Retro Looks: switches theme + fonts together, restores the previous look on "Retro: Off",
// and (on Windows) installs the bundled fonts. Windows Terminal is the RetroLooks PowerShell module's job.
const vscode = require('vscode');
const fs = require('fs');
const path = require('path');
const { execFile } = require('child_process');
const { PRESETS, resolveColor, phosphorPalette, fillTemplate } = require('./palette');

const SAVED_KEY = 'retroLooks.saved';
const ACTIVE_KEY = 'retroLooks.activeLook'; // id of the look applied by the extension, if any
const REMIND_DISMISSED_KEY = 'retroLooks.installReminderDismissed'; // per machine: fonts are per machine
// The tests point this at a throwaway key (and LOCALAPPDATA at a temporary folder).
const FONT_REG_KEY = process.env.RETRO_LOOKS_TEST_FONT_KEY || 'HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts';
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
  return computeSizes(target, grid, await displayScale());
}

function computeSizes(target, grid, scale) {
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

// ---------- phosphor colors ----------

// Monochrome looks ship with a theme in their default color. Any other color is applied by overriding
// that theme's colors in the user's settings, scoped to the theme ("[Apple //e]": {...}), which takes
// effect instantly and touches nothing else.
const COLOR_SETTINGS = ['workbench.colorCustomizations', 'editor.tokenColorCustomizations'];
const themeKey = (look) => `[${look.theme}]`;
const presetLabel = (preset) => preset[0].toUpperCase() + preset.slice(1);

function savedColors() {
  return vscode.workspace.getConfiguration('retroLooks').get('phosphorColors') ?? {};
}

// The look's chosen color as stored (a preset name or #RRGGBB), falling back to its default.
function chosenColor(look) {
  const value = savedColors()[look.id];
  return resolveColor(value) ? value : look.monochrome.defaultColor;
}

async function saveColorChoice(look, value) {
  const colors = { ...savedColors() };
  if (resolveColor(value) === resolveColor(look.monochrome.defaultColor)) delete colors[look.id];
  else colors[look.id] = value;
  await vscode.workspace.getConfiguration('retroLooks').update(
    'phosphorColors', Object.keys(colors).length ? colors : undefined, vscode.ConfigurationTarget.Global
  );
}

// Sets (or, with overrides = null, removes) this theme's entry in both customization settings.
async function setThemeOverrides(look, overrides) {
  const config = vscode.workspace.getConfiguration();
  for (const key of COLOR_SETTINGS) {
    const current = config.inspect(key)?.globalValue ?? {};
    const updated = { ...current };
    if (overrides) updated[themeKey(look)] = overrides[key];
    else delete updated[themeKey(look)];
    if (JSON.stringify(updated) === JSON.stringify(current)) continue;
    await config.update(key, Object.keys(updated).length ? updated : undefined, vscode.ConfigurationTarget.Global);
  }
}

async function applyColor(look) {
  if (!look.monochrome) return;
  const color = resolveColor(chosenColor(look));
  if (color === resolveColor(look.monochrome.defaultColor)) {
    await setThemeOverrides(look, null); // the theme itself is already in the default color
    return;
  }
  const theme = fillTemplate(fs.readFileSync(generated(look.monochrome.template), 'utf8'), phosphorPalette(color));
  await setThemeOverrides(look, {
    'workbench.colorCustomizations': theme.colors,
    'editor.tokenColorCustomizations': {
      textMateRules: theme.tokenColors.filter((rule) => rule.scope).map(({ scope, settings }) => ({ scope, settings })),
    },
  });
}

// Asks for a color: the presets, or a custom #RRGGBB. Returns the stored form, or undefined if cancelled.
async function pickColor(look) {
  const current = chosenColor(look);
  const items = [
    ...Object.entries(PRESETS).map(([preset, hex]) => ({
      label: presetLabel(preset), description: preset === current ? `${hex} (current)` : hex, value: preset,
    })),
    { label: 'Custom…', description: PRESETS[current] ? '' : `${current} (current)`, value: null },
  ];
  const picked = await vscode.window.showQuickPick(items, { placeHolder: `Phosphor color for ${look.name}` });
  if (!picked) return undefined;
  if (picked.value) return picked.value;
  const input = await vscode.window.showInputBox({
    prompt: `Phosphor color for ${look.name}, as #RRGGBB`,
    value: resolveColor(current),
    validateInput: (value) => (resolveColor(value) ? null : 'Enter a color like #40E0FF'),
  });
  if (input === undefined) return undefined;
  const value = input.trim().toLowerCase();
  return PRESETS[value] ? value : '#' + value.replace(/^#/, '').toUpperCase();
}

async function setColor(context, looks) {
  const active = looks.find((l) => l.id === context.globalState.get(ACTIVE_KEY));
  if (!active?.monochrome) {
    vscode.window.showInformationMessage('Retro Looks: choose a monochrome look first (Retro: Choose Look…).');
    return;
  }
  const value = await pickColor(active);
  if (value === undefined) return;
  await saveColorChoice(active, value);
  await applyColor(active);
}

// ---------- applying looks ----------

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
  await context.globalState.update(ACTIVE_KEY, look.id);
  await applyColor(look);
  // Install last: its message offers to quit VS Code, and the look must be saved before that.
  if (installFonts) await install();
}

async function restore(context, looks, quiet = false) {
  const saved = context.globalState.get(SAVED_KEY);
  if (!saved) {
    if (!quiet) vscode.window.showInformationMessage('Retro Looks: no retro look is active.');
    return;
  }
  const config = vscode.workspace.getConfiguration();
  for (const [key, value] of Object.entries(saved)) {
    await config.update(key, value === null ? undefined : value, vscode.ConfigurationTarget.Global);
  }
  // The color overrides only matter while a look is active; the chosen colors themselves are kept.
  for (const look of looks) if (look.monochrome) await setThemeOverrides(look, null);
  await context.globalState.update(SAVED_KEY, undefined);
  await context.globalState.update(ACTIVE_KEY, undefined);
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
  if (!picked.look) {
    await restore(context, looks);
    return;
  }
  if (picked.look.monochrome) {
    const value = await pickColor(picked.look);
    if (value === undefined) return;
    await saveColorChoice(picked.look, value);
  }
  await applyLook(context, picked.look);
}

// Version 0.1 had separate Apple //e Green and Amber looks; carry an active one over to Apple //e.
async function migrateOldLooks(context, looks) {
  const apple = looks.find((l) => l.id === 'apple2e');
  const oldColor = { 'Apple //e Green': 'green', 'Apple //e Amber': 'amber' }[
    vscode.workspace.getConfiguration('workbench').get('colorTheme')
  ];
  if (!apple || !oldColor || !context.globalState.get(SAVED_KEY)) return;
  await saveColorChoice(apple, oldColor);
  await applyLook(context, apple);
}

// ---------- Windows font install ----------

// The same place, file names and registry names as the RetroLooks PowerShell module (both come from the
// build's fonts.json), so either one can install fonts the other finds.
const fontDir = () => path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Windows', 'Fonts');
// Present while Retro Looks for Windows Terminal (the PowerShell module) is installed.
const terminalFragmentDir = () => path.join(process.env.LOCALAPPDATA, 'Microsoft', 'Windows Terminal', 'Fragments', 'Retro Looks');

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

async function install() {
  if (!isWindows) {
    const choice = await vscode.window.showInformationMessage(
      'Automatic font installation is Windows-only for now. Install the fonts from the bundled fonts folder with your system\'s font installer.',
      'Open Fonts Folder'
    );
    if (choice) openFonts();
    return;
  }
  fs.mkdirSync(fontDir(), { recursive: true });
  for (const font of readJson(generated('fonts.json'))) {
    const source = generated('fonts', font.id, font.file);
    const dest = path.join(fontDir(), font.installedFile);
    // Installed fonts may be locked by running apps; identical files don't need copying.
    if (!fs.existsSync(dest) || fs.statSync(dest).size !== fs.statSync(source).size) fs.copyFileSync(source, dest);
    await run('reg', ['add', FONT_REG_KEY, '/v', font.registryName, '/t', 'REG_SZ', '/d', dest, '/f']);
  }

  // A running VS Code keeps the font list it loaded at startup; reloading the window doesn't refresh it,
  // and extensions can't relaunch VS Code, so the best we can offer is quitting.
  const choice = await vscode.window.showInformationMessage(
    'Retro Looks: fonts installed. Quit VS Code and start it again to see them (reloading the window isn\'t enough).',
    'Quit VS Code', 'Later'
  );
  if (choice === 'Quit VS Code') await vscode.commands.executeCommand('workbench.action.quit');
}

async function uninstall(context, looks) {
  if (!isWindows) {
    vscode.window.showInformationMessage('Retro Looks only installs fonts automatically on Windows.');
    return;
  }
  await restore(context, looks, true);
  // Someone who just removed the fonts doesn't want to be asked to install them at the next startup.
  await context.globalState.update(REMIND_DISMISSED_KEY, true);

  if (fs.existsSync(terminalFragmentDir())) {
    const choice = await vscode.window.showInformationMessage(
      'Retro Looks for Windows Terminal is installed and uses the same fonts, so they were kept. '
        + 'Run Uninstall-RetroLooks in PowerShell to remove it, fonts included.',
      'Remove Fonts Anyway'
    );
    if (choice !== 'Remove Fonts Anyway') return;
  }

  const locked = [];
  for (const font of readJson(generated('fonts.json'))) {
    // Only remove registrations that point at our own file, not a copy the user installed themselves.
    try {
      const out = await run('reg', ['query', FONT_REG_KEY, '/v', font.registryName]);
      if (out.includes(font.installedFile)) await run('reg', ['delete', FONT_REG_KEY, '/v', font.registryName, '/f']);
    } catch { /* not registered */ }
    try {
      fs.rmSync(path.join(fontDir(), font.installedFile), { force: true });
    } catch {
      locked.push(font.installedFile);
    }
  }
  const suffix = locked.length
    ? ` These font files are in use and couldn't be deleted; they're no longer registered and can be deleted from ${fontDir()} later: ${locked.join(', ')}.`
    : '';
  vscode.window.showInformationMessage(`Retro Looks: fonts removed.${suffix}`);
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
    'Retro Looks: install the retro fonts? The looks need them.',
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
  register('retroLooks.setColor', () => setColor(context, looks));
  register('retroLooks.off', () => restore(context, looks));
  register('retroLooks.install', () => install());
  register('retroLooks.uninstall', () => uninstall(context, looks));
  register('retroLooks.openFonts', () => openFonts());

  // Editing retroLooks.phosphorColors by hand recolors the active look right away.
  context.subscriptions.push(vscode.workspace.onDidChangeConfiguration((event) => {
    if (!event.affectsConfiguration('retroLooks.phosphorColors')) return;
    const active = looks.find((l) => l.id === context.globalState.get(ACTIVE_KEY));
    if (active) applyColor(active).catch((err) => console.error('Retro Looks: recoloring failed', err));
  }));

  migrateOldLooks(context, looks).catch((err) => console.error('Retro Looks: migration failed', err));
  remindToInstall(context).catch((err) => console.error('Retro Looks: install reminder failed', err));
}

// `_internal` is for the tests only.
module.exports = { activate, deactivate() {}, _internal: { computeSizes } };
