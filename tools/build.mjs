// Builds both projects from looks/ and fonts/:
//   vscode/generated/...                  themes, templates, looks.json, fonts (packaged into the VSIX)
//   vscode/package.json                   "contributes" section (themes + commands) is rewritten
//   dist/powershell/ + dist/retro-looks-powershell.zip (+ .sha256)
//                                         the RetroLooks PowerShell module (Windows Terminal) and its installer
// Each product has its own version (vscode/package.json, powershell/RetroLooks/RetroLooks.psd1) and is
// released on its own tag (vscode-v1.2.3, powershell-v1.2.3). Usage: node tools/build.mjs
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { createRequire } from 'node:module';

// The color math is shared with the extension, which recolors monochrome looks at runtime.
const { PRESETS, VGA, MIN_PEAK, resolveColor, phosphorPalette, fillTemplate } = createRequire(import.meta.url)('../vscode/palette.js');

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const p = (...parts) => path.join(root, ...parts);
const readJson = (file) => JSON.parse(fs.readFileSync(file, 'utf8'));
const writeJson = (file, data) => {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(data, null, 2) + '\n');
};

// Both projects install the fonts under these names, so either one can find and remove them.
// The PowerShell module and the extension read them from the generated fonts.json.
const FONT_FILE_PREFIX = 'RetroLooks-';
const registryName = (family) => `${family} (TrueType)`;

// ---------- monochrome looks ----------

// A monochrome look has one phosphor color, chosen by the user. Its VS Code theme and Terminal scheme are
// generated from tools/templates/<style>-vscode-theme.json and <style>-terminal-scheme.json.
const templateFile = (style, kind) => p('tools', 'templates', `${style}-${kind}.json`);
const presetName = (preset) => preset[0].toUpperCase() + preset.slice(1);

// ---------- load looks and fonts ----------

function loadFonts() {
  const fonts = {};
  for (const id of fs.readdirSync(p('fonts'))) {
    const dir = p('fonts', id);
    const meta = readJson(path.join(dir, 'font.json'));
    for (const f of [meta.file, meta.license]) {
      if (!fs.existsSync(path.join(dir, f))) throw new Error(`fonts/${id}: missing ${f}`);
    }
    fonts[id] = { id, dir, ...meta };
  }
  return fonts;
}

function loadLooks(fonts) {
  const looks = fs.readdirSync(p('looks')).map((id) => {
    const dir = p('looks', id);
    const look = readJson(path.join(dir, 'look.json'));
    if (!fonts[look.font]) throw new Error(`looks/${id}: unknown font "${look.font}"`);
    // A look without a "vscode" section is Windows Terminal only.
    let theme = null, schemes, defaultScheme;
    const mono = look.monochrome;
    if (mono) {
      if (!resolveColor(mono.defaultColor)) throw new Error(`looks/${id}: invalid defaultColor "${mono.defaultColor}"`);
      const read = (kind) => fs.readFileSync(templateFile(mono.style, kind), 'utf8');
      if (look.vscode) theme = fillTemplate(read('vscode-theme'), phosphorPalette(resolveColor(mono.defaultColor)));
      // One Terminal scheme per preset, so users can pick any of them in Terminal's settings.
      schemes = Object.entries(PRESETS).map(([preset, color]) => ({
        name: `${look.name} ${presetName(preset)}`,
        ...fillTemplate(read('terminal-scheme'), phosphorPalette(color)),
      }));
      defaultScheme = `${look.name} ${presetName(mono.defaultColor)}`;
    } else {
      if (look.vscode) theme = readJson(path.join(dir, 'vscode-theme.json'));
      schemes = [{ name: look.name, ...readJson(path.join(dir, 'terminal-scheme.json')) }];
      defaultScheme = look.name;
    }
    return { id, ...look, theme: theme && { name: look.name, ...theme }, schemes, defaultScheme };
  });
  return looks.sort((a, b) => (a.order ?? 999) - (b.order ?? 999) || a.id.localeCompare(b.id));
}

// ---------- shared outputs ----------

// The font list both projects install from, with the names they install under.
function fontList(fonts) {
  return Object.values(fonts).map((f) => ({
    id: f.id, family: f.family, file: f.file, installedFile: FONT_FILE_PREFIX + f.file,
    registryName: registryName(f.family), pixelsPerEm: f.pixelsPerEm ?? null,
  }));
}

function copyFonts(fonts, destRoot) {
  for (const f of Object.values(fonts)) {
    const dest = path.join(destRoot, f.id);
    fs.mkdirSync(dest, { recursive: true });
    for (const file of ['font.json', f.file, f.license]) fs.copyFileSync(path.join(f.dir, file), path.join(dest, file));
  }
}

function thirdPartyNotices(fonts) {
  const lines = ['# Third-party notices', '', 'The fonts bundled with Retro Looks are the work of their authors and keep their own licenses.', ''];
  for (const f of Object.values(fonts)) {
    lines.push(`## ${f.family}`, '', `- Author: ${f.author}`, `- Source: ${f.url}`, `- License: ${f.licenseName}`, `- Full license text: fonts/${f.id}/${f.license}`, '');
  }
  return lines.join('\n');
}

// ---------- VS Code extension ----------

function buildVscode(allLooks, fonts) {
  // Every font is bundled (the extension installs all of them), but only looks with a "vscode" section
  // get a theme and a command.
  const looks = allLooks.filter((l) => l.vscode);
  const ext = p('vscode');
  const gen = path.join(ext, 'generated');
  fs.rmSync(gen, { recursive: true, force: true });

  for (const l of looks) writeJson(path.join(gen, 'themes', `${l.id}.json`), l.theme);
  // The extension recolors monochrome looks at runtime from the same templates.
  for (const style of new Set(looks.filter((l) => l.monochrome).map((l) => l.monochrome.style))) {
    fs.mkdirSync(path.join(gen, 'templates'), { recursive: true });
    fs.copyFileSync(templateFile(style, 'vscode-theme'), path.join(gen, 'templates', `${style}-vscode-theme.json`));
  }
  copyFonts(fonts, path.join(gen, 'fonts'));
  writeJson(path.join(gen, 'fonts.json'), fontList(fonts));
  writeJson(path.join(gen, 'looks.json'), looks.map((l) => {
    const f = fonts[l.font];
    return {
      id: l.id,
      name: l.name,
      description: l.description,
      theme: l.name,
      font: fontList({ [f.id]: f })[0],
      fontFamily: `'${f.family}', Consolas, monospace`,
      vscode: l.vscode,
      monochrome: l.monochrome
        ? { style: l.monochrome.style, defaultColor: l.monochrome.defaultColor, template: `templates/${l.monochrome.style}-vscode-theme.json` }
        : null,
    };
  }));

  // vsce needs these next to package.json. vscode/README.md and vscode/CHANGELOG.md are the extension's own;
  // the license lives at the repo root.
  fs.copyFileSync(p('LICENSE'), path.join(ext, 'LICENSE'));
  fs.writeFileSync(path.join(ext, 'THIRD-PARTY-NOTICES.md'), thirdPartyNotices(fonts));

  const pkgFile = path.join(ext, 'package.json');
  const pkg = readJson(pkgFile);
  pkg.contributes = {
    themes: looks.map((l) => ({ label: l.name, uiTheme: 'vs-dark', path: `./generated/themes/${l.id}.json` })),
    commands: [
      { command: 'retroLooks.choose', title: 'Retro: Choose Look…' },
      ...looks.map((l) => ({ command: `retroLooks.apply.${l.id}`, title: `Retro: ${l.name}` })),
      { command: 'retroLooks.setColor', title: 'Retro: Set Phosphor Color…' },
      { command: 'retroLooks.off', title: 'Retro: Off (restore previous look)' },
      { command: 'retroLooks.install', title: 'Retro: Install Fonts' },
      { command: 'retroLooks.openFonts', title: 'Retro: Open Bundled Fonts Folder' },
    ],
    menus: {
      // The extension sets retroLooks.fontsInstalled (Windows only; elsewhere the command stays visible).
      commandPalette: [{ command: 'retroLooks.install', when: '!retroLooks.fontsInstalled' }],
    },
    configuration: {
      title: 'Retro Looks',
      properties: {
        'retroLooks.pixelPerfectFontSize': {
          type: 'boolean',
          default: true,
          markdownDescription: 'Adjust the font size of pixel fonts to your display scaling so every font pixel covers a whole number of screen pixels. This keeps them sharp; turn it off to use each look\'s nominal size.',
        },
        'retroLooks.phosphorColors': {
          type: 'object',
          default: {},
          additionalProperties: { type: 'string' },
          markdownDescription: 'The phosphor color of each monochrome look in VS Code, by look ID ('
            + looks.filter((l) => l.monochrome).map((l) => `\`${l.id}\``).join(', ')
            + '): a preset (' + Object.keys(PRESETS).map((c) => `\`${c}\``).join(', ')
            + ') or `#RRGGBB`. Easiest to set with **Retro: Set Phosphor Color…**. Windows Terminal is not affected.',
        },
      },
    },
  };
  writeJson(pkgFile, pkg);
  return pkg.version;
}

// ---------- PowerShell module (Windows Terminal) ----------

function terminalFragment(looks, fonts) {
  return {
    $help: 'Retro Looks for Windows Terminal — https://github.com/zmbq/vscode-retro',
    schemes: looks.flatMap((l) => l.schemes),
    profiles: looks.map((l) => ({
      guid: l.terminal.guid,
      name: l.name,
      // commandline is filled in at install time (pwsh.exe if present, otherwise powershell.exe),
      // and pixel fonts' sizes are adjusted to the display scaling.
      startingDirectory: '%USERPROFILE%',
      colorScheme: l.defaultScheme,
      font: { face: fonts[l.font].family, size: l.terminal.fontSize },
      cursorShape: l.terminal.cursorShape,
      padding: l.terminal.padding,
      // The looks are opened with the `look` command; Install-RetroLooks -ShowProfiles shows them in the menu.
      hidden: true,
    })),
  };
}

function buildPowerShell(looks, fonts) {
  const out = p('dist', 'powershell');
  const moduleDir = path.join(out, 'RetroLooks');
  // Only clear what this step produces: dist/ also holds the packaged VSIX.
  fs.rmSync(out, { recursive: true, force: true });
  for (const file of ['retro-looks-powershell.zip', 'retro-looks-powershell.zip.sha256']) fs.rmSync(p('dist', file), { force: true });

  fs.mkdirSync(moduleDir, { recursive: true });
  fs.copyFileSync(p('powershell', 'RetroLooks', 'RetroLooks.psm1'), path.join(moduleDir, 'RetroLooks.psm1'));
  const manifest = fs.readFileSync(p('powershell', 'RetroLooks', 'RetroLooks.psd1'), 'utf8');
  const version = manifest.match(/ModuleVersion\s*=\s*'(\d+\.\d+\.\d+)'/)?.[1];
  if (!version) throw new Error("RetroLooks.psd1 needs a ModuleVersion like '1.2.3'");
  fs.copyFileSync(p('powershell', 'RetroLooks', 'RetroLooks.psd1'), path.join(moduleDir, 'RetroLooks.psd1'));
  fs.copyFileSync(p('powershell', 'CHANGELOG.md'), path.join(moduleDir, 'CHANGELOG.md'));
  copyFonts(fonts, path.join(moduleDir, 'fonts'));
  writeJson(path.join(moduleDir, 'fonts.json'), fontList(fonts));
  writeJson(path.join(moduleDir, 'retro-looks.json'), terminalFragment(looks, fonts));

  // For the `look` and `color` commands: the looks, and what the module needs to recolor a tab. The module
  // repeats palette.js's math in PowerShell (the tests check both give the same colors).
  const aliases = new Map();
  for (const l of looks) {
    for (const alias of new Set([l.id, ...(l.aliases ?? [])])) {
      if (aliases.has(alias)) throw new Error(`looks/${l.id}: alias "${alias}" is also used by ${aliases.get(alias)}`);
      aliases.set(alias, l.id);
    }
  }
  const colorStyle = (l) => l.monochrome?.style ?? l.terminal.colorStyle ?? 'phosphor';
  writeJson(path.join(moduleDir, 'looks.json'), looks.map((l) => ({
    id: l.id,
    name: l.name,
    aliases: l.aliases ?? [],
    description: l.description,
    guid: l.terminal.guid,
    monochrome: Boolean(l.monochrome),
    defaultColor: l.monochrome?.defaultColor ?? null,
    colorStyle: colorStyle(l),
  })));
  writeJson(path.join(moduleDir, 'palette.json'), { presets: PRESETS, vga: VGA, minPeak: MIN_PEAK });
  for (const style of new Set(looks.map(colorStyle))) {
    fs.mkdirSync(path.join(moduleDir, 'templates'), { recursive: true });
    fs.copyFileSync(templateFile(style, 'terminal-scheme'), path.join(moduleDir, 'templates', `${style}-terminal-scheme.json`));
  }
  for (const dir of [out, moduleDir]) {
    fs.copyFileSync(p('LICENSE'), path.join(dir, 'LICENSE'));
    fs.writeFileSync(path.join(dir, 'THIRD-PARTY-NOTICES.md'), thirdPartyNotices(fonts));
  }
  fs.copyFileSync(p('powershell', 'install.ps1'), path.join(out, 'install.ps1'));

  const zip = p('dist', 'retro-looks-powershell.zip');
  if (process.platform === 'win32') {
    execFileSync('powershell', ['-NoProfile', '-Command', `Compress-Archive -Path '${out}\\*' -DestinationPath '${zip}' -Force`], { stdio: 'inherit' });
  } else {
    execFileSync('zip', ['-qr', zip, '.'], { cwd: out, stdio: 'inherit' });
  }
  const hash = crypto.createHash('sha256').update(fs.readFileSync(zip)).digest('hex');
  fs.writeFileSync(zip + '.sha256', `${hash}  retro-looks-powershell.zip\n`);
  return version;
}

const fonts = loadFonts();
const looks = loadLooks(fonts);
const extensionVersion = buildVscode(looks, fonts);
const moduleVersion = buildPowerShell(looks, fonts);
const describe = (l) => (l.vscode ? l.name : `${l.name} [Terminal only]`);
console.log(`Built ${looks.length} looks (${looks.map(describe).join(', ')}), ${Object.keys(fonts).length} fonts.`);
console.log(`VS Code extension ${extensionVersion}, PowerShell module ${moduleVersion}.`);
