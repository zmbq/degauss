// Checks what the build produced for both projects (`npm test` runs the build first).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { PRESETS } = require('../../vscode/palette');

const root = path.join(__dirname, '..', '..');
const read = (...parts) => JSON.parse(fs.readFileSync(path.join(root, ...parts), 'utf8'));
const exists = (...parts) => fs.existsSync(path.join(root, ...parts));

const looks = fs.readdirSync(path.join(root, 'looks')).map((id) => ({ id, ...read('looks', id, 'look.json') }));
const pkg = read('vscode', 'package.json');
const generatedLooks = read('vscode', 'generated', 'looks.json');
const moduleDir = ['dist', 'powershell', 'Degauss'];
const fragment = read(...moduleDir, 'degauss.json');

test('each product has its own version, with a changelog entry for it', async () => {
  const semver = /^\d+\.\d+\.\d+$/;
  assert.match(pkg.version, semver, 'the extension version (vscode/package.json)');
  const manifest = fs.readFileSync(path.join(root, 'powershell', 'Degauss', 'Degauss.psd1'), 'utf8');
  const moduleVersion = manifest.match(/ModuleVersion\s*=\s*'([^']+)'/)?.[1];
  assert.match(moduleVersion ?? '', semver, 'the module version (Degauss.psd1)');
  assert.strictEqual(fs.readFileSync(path.join(root, ...moduleDir, 'Degauss.psd1'), 'utf8'), manifest, 'the manifest ships as written');

  // The release workflows use these entries as the release notes.
  const { releaseNotes } = await import('../../tools/release-notes.mjs');
  const changelog = (file) => fs.readFileSync(path.join(root, file), 'utf8');
  assert.doesNotThrow(() => releaseNotes(changelog('vscode/CHANGELOG.md'), pkg.version), `vscode/CHANGELOG.md has a ## ${pkg.version} entry`);
  assert.doesNotThrow(() => releaseNotes(changelog('powershell/CHANGELOG.md'), moduleVersion), `powershell/CHANGELOG.md has a ## ${moduleVersion} entry`);
  assert(exists(...moduleDir, 'CHANGELOG.md'), 'the module ships its changelog');
});

test('both projects install the same fonts under the same names', () => {
  const vscodeFonts = read('vscode', 'generated', 'fonts.json');
  assert.deepStrictEqual(read(...moduleDir, 'fonts.json'), vscodeFonts);
  for (const font of vscodeFonts) {
    assert.strictEqual(font.installedFile, `Degauss-${font.file}`);
    assert.strictEqual(font.registryName, `${font.family} (TrueType)`);
    for (const file of [font.file, 'LICENSE.txt', 'font.json']) {
      assert(exists('vscode', 'generated', 'fonts', font.id, file), `VS Code: ${font.id}/${file}`);
      assert(exists(...moduleDir, 'fonts', font.id, file), `PowerShell: ${font.id}/${file}`);
    }
  }
});

test('the VS Code extension leaves Windows Terminal to the PowerShell module', () => {
  assert(!exists('vscode', 'generated', 'terminal'));
  assert(!pkg.contributes.commands.some((c) => /Terminal/.test(c.title)), 'no Terminal commands');
});

test('the PowerShell package has the module, its installer and the licenses', () => {
  for (const file of ['Degauss.psd1', 'Degauss.psm1', 'fonts.json', 'degauss.json', 'LICENSE', 'THIRD-PARTY-NOTICES.md']) {
    assert(exists(...moduleDir, file), file);
  }
  for (const file of ['install.ps1', 'LICENSE', 'THIRD-PARTY-NOTICES.md']) assert(exists('dist', 'powershell', file), file);
  assert(exists('dist', 'degauss-powershell.zip') && exists('dist', 'degauss-powershell.zip.sha256'));
});

test('every look has a Terminal profile with a unique GUID and an existing scheme', () => {
  const guids = fragment.profiles.map((p) => p.guid);
  assert.strictEqual(new Set(guids).size, guids.length, 'GUIDs are unique');
  assert.strictEqual(fragment.profiles.length, looks.length);
  const schemes = new Set(fragment.schemes.map((s) => s.name));
  for (const profile of fragment.profiles) {
    assert(/^\{[0-9a-f-]{36}\}$/.test(profile.guid), `${profile.name}: GUID format`);
    assert(schemes.has(profile.colorScheme), `${profile.name}: scheme "${profile.colorScheme}" exists`);
  }
});

test('Terminal schemes are complete and fully resolved', () => {
  const keys = ['background', 'foreground', 'cursorColor', 'selectionBackground', 'black', 'red', 'green', 'yellow', 'blue',
    'purple', 'cyan', 'white', 'brightBlack', 'brightRed', 'brightGreen', 'brightYellow', 'brightBlue', 'brightPurple', 'brightCyan', 'brightWhite'];
  for (const scheme of fragment.schemes) {
    for (const key of keys) assert(/^#[0-9A-F]{6}$/i.test(scheme[key]), `${scheme.name}.${key} = ${scheme[key]}`);
  }
});

test('monochrome looks get a Terminal scheme per preset', () => {
  for (const look of looks.filter((l) => l.monochrome)) {
    for (const preset of Object.keys(PRESETS)) {
      const name = `${look.name} ${preset[0].toUpperCase()}${preset.slice(1)}`;
      assert(fragment.schemes.some((s) => s.name === name), `scheme "${name}"`);
    }
  }
});

test('VS Code looks have a theme, a command and a template when monochrome', () => {
  const vscodeLooks = looks.filter((l) => l.vscode);
  assert.deepStrictEqual(generatedLooks.map((l) => l.id).sort(), vscodeLooks.map((l) => l.id).sort());
  const commands = new Set(pkg.contributes.commands.map((c) => c.command));
  const themes = new Map(pkg.contributes.themes.map((t) => [t.label, t.path]));
  for (const look of generatedLooks) {
    assert(commands.has(`degauss.apply.${look.id}`), `${look.id}: command`);
    const themePath = themes.get(look.theme);
    assert(themePath, `${look.id}: theme "${look.theme}" contributed`);
    const theme = read('vscode', themePath);
    assert.strictEqual(theme.name, look.theme);
    assert(!JSON.stringify(theme).includes('${'), `${look.id}: no unfilled template slots`);
    if (look.monochrome) assert(exists('vscode', 'generated', look.monochrome.template), `${look.id}: template shipped`);
  }
});

test('every command in package.json is registered by the extension', () => {
  const source = fs.readFileSync(path.join(root, 'vscode', 'extension.js'), 'utf8');
  for (const { command } of pkg.contributes.commands) {
    if (command.startsWith('degauss.apply.')) continue; // registered in a loop over looks.json
    assert(source.includes(`'${command}'`), `${command} is registered`);
  }
});

test('Degauss: Install Fonts is only in the Command Palette while the fonts are missing', () => {
  const entry = pkg.contributes.menus.commandPalette.find((m) => m.command === 'degauss.install');
  assert.strictEqual(entry?.when, '!degauss.fontsInstalled');
  const source = fs.readFileSync(path.join(root, 'vscode', 'extension.js'), 'utf8');
  assert(source.includes("'setContext', 'degauss.fontsInstalled'"), 'the extension sets the context key');
});

test('release notes are the changelog entry for the version', async () => {
  const { releaseNotes } = await import('../../tools/release-notes.mjs');
  const changelog = '# Changelog\n\n## 1.2.10\n\n- Newer.\n\n## 1.2.1\n\n- The fix.\n- Another.\n\n## 1.2.0\n\nFirst.\n';
  assert.strictEqual(releaseNotes(changelog, '1.2.1'), '- The fix.\n- Another.\n');
  assert.strictEqual(releaseNotes(changelog, '1.2.0'), 'First.\n');
  assert.throws(() => releaseNotes(changelog, '1.3.0'), /No "## 1.3.0" entry/);
  assert.throws(() => releaseNotes('## 2.0.0\n\n## 1.0.0\n\nOld.\n', '2.0.0'), /empty/);
});
