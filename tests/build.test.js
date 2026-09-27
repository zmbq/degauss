// Checks what the build produced (`npm test` runs the build first).
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { PRESETS } = require('../extension/palette');

const root = path.join(__dirname, '..');
const read = (...parts) => JSON.parse(fs.readFileSync(path.join(root, ...parts), 'utf8'));

const looks = fs.readdirSync(path.join(root, 'looks')).map((id) => ({ id, ...read('looks', id, 'look.json') }));
const fragment = read('extension', 'generated', 'terminal', 'retro-looks.json');
const pkg = read('extension', 'package.json');
const generatedLooks = read('extension', 'generated', 'looks.json');

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
    assert(commands.has(`retroLooks.apply.${look.id}`), `${look.id}: command`);
    const themePath = themes.get(look.theme);
    assert(themePath, `${look.id}: theme "${look.theme}" contributed`);
    const theme = read('extension', themePath);
    assert.strictEqual(theme.name, look.theme);
    assert(!JSON.stringify(theme).includes('${'), `${look.id}: no unfilled template slots`);
    if (look.monochrome) assert(fs.existsSync(path.join(root, 'extension', 'generated', look.monochrome.template)), `${look.id}: template shipped`);
  }
});

test('every command in package.json is registered by the extension', () => {
  const source = fs.readFileSync(path.join(root, 'extension', 'extension.js'), 'utf8');
  for (const { command } of pkg.contributes.commands) {
    if (command.startsWith('retroLooks.apply.')) continue; // registered in a loop over looks.json
    assert(source.includes(`'${command}'`), `${command} is registered`);
  }
});

test('fonts are bundled with their licenses', () => {
  for (const font of read('extension', 'generated', 'fonts.json')) {
    for (const file of [font.file, 'LICENSE.txt', 'font.json']) {
      assert(fs.existsSync(path.join(root, 'extension', 'generated', 'fonts', font.id, file)), `${font.id}/${file}`);
    }
  }
});
