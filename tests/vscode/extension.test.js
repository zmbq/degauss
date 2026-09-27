// Drives the extension through a fake VS Code: choosing looks and colors, Off, and migration.
// Requires a build (`npm test` runs the build first).
const test = require('node:test');
const assert = require('node:assert');
const { createFakeVscode } = require('./helpers/fake-vscode');

const NIGHT_OWL = 'Night Owl (No Italics)';
const USER_TWEAK = { 'editor.background': '#010101' };

function startWithUserSettings(globalState) {
  const fake = createFakeVscode();
  fake.settings = {
    'workbench.colorTheme': NIGHT_OWL,
    'window.autoDetectColorScheme': true,
    'workbench.colorCustomizations': { [`[${NIGHT_OWL}]`]: USER_TWEAK },
  };
  fake.activate(globalState);
  return fake;
}

test('choosing a monochrome look asks for its color and recolors only that theme', async () => {
  const fake = startWithUserSettings();
  await fake.settle();

  fake.answers.push('Apple //e', 'Amber');
  await fake.commands['degauss.choose']();
  const s = fake.settings;
  assert.strictEqual(s['workbench.colorTheme'], 'Apple //e');
  assert.deepStrictEqual(s['degauss.phosphorColors'], { apple2e: 'amber' });
  assert.deepStrictEqual(s['workbench.colorCustomizations'][`[${NIGHT_OWL}]`], USER_TWEAK, 'user customization kept');
  assert.strictEqual(s['workbench.colorCustomizations']['[Apple //e]']['editor.background'], '#110C05');
  assert(s['editor.tokenColorCustomizations']['[Apple //e]'].textMateRules.every((r) => r.scope), 'only scoped token rules');
});

test('the default color needs no overrides, and custom colors are remembered per look', async () => {
  const fake = startWithUserSettings();
  await fake.settle();

  fake.answers.push('Apple //e', 'Green');
  await fake.commands['degauss.choose']();
  assert.strictEqual(fake.settings['workbench.colorCustomizations']['[Apple //e]'], undefined);
  assert.strictEqual(fake.settings['editor.tokenColorCustomizations'], undefined);
  assert.strictEqual(fake.settings['degauss.phosphorColors'], undefined);

  fake.answers.push('Custom…', '#102030');
  await fake.commands['degauss.setColor']();
  assert.deepStrictEqual(fake.settings['degauss.phosphorColors'], { apple2e: '#102030' });
  assert(fake.settings['workbench.colorCustomizations']['[Apple //e]'], 'custom color applied');

  fake.answers.push('IBM 3270 Monochrome', 'Yellow');
  await fake.commands['degauss.choose']();
  assert.deepStrictEqual(fake.settings['degauss.phosphorColors'], { apple2e: '#102030', 'ibm-3270-mono': 'yellow' });
  assert.strictEqual(fake.settings['workbench.colorTheme'], 'IBM 3270 Monochrome');
});

test('editing degauss.phosphorColors by hand recolors the active look', async () => {
  const fake = startWithUserSettings();
  await fake.settle();
  fake.answers.push('Apple //e', 'Green');
  await fake.commands['degauss.choose']();

  await fake.vscode.workspace.getConfiguration('degauss').update('phosphorColors', { apple2e: 'cyan' });
  await fake.settle();
  assert(fake.settings['workbench.colorCustomizations']['[Apple //e]'], 'recolored to cyan');
});

test('the color IBM 3270 look asks no color question', async () => {
  const fake = startWithUserSettings();
  await fake.settle();
  fake.answers.push('IBM 3270');
  await fake.commands['degauss.choose']();
  assert.strictEqual(fake.settings['workbench.colorTheme'], 'IBM 3270');
  assert.strictEqual(fake.answers.length, 0);
});

test('Off restores the user\'s settings but remembers the chosen colors', async () => {
  const fake = startWithUserSettings();
  await fake.settle();
  fake.answers.push('Apple //e', 'Amber');
  await fake.commands['degauss.choose']();
  await fake.commands['degauss.off']();

  const s = fake.settings;
  assert.strictEqual(s['workbench.colorTheme'], NIGHT_OWL);
  assert.strictEqual(s['window.autoDetectColorScheme'], true);
  assert.deepStrictEqual(s['workbench.colorCustomizations'], { [`[${NIGHT_OWL}]`]: USER_TWEAK });
  assert.strictEqual(s['editor.tokenColorCustomizations'], undefined);
  for (const key of ['editor.fontFamily', 'editor.fontSize', 'editor.lineHeight', 'editor.cursorStyle',
    'terminal.integrated.fontFamily', 'terminal.integrated.fontSize', 'terminal.integrated.cursorStyle']) {
    assert.strictEqual(s[key], undefined, `${key} removed`);
  }
  assert.deepStrictEqual(s['degauss.phosphorColors'], { apple2e: 'amber' });
});

test('an active v0.1 "Apple //e Amber" look is migrated to Apple //e in amber', async () => {
  const globalState = new Map([['degauss.saved', { 'workbench.colorTheme': NIGHT_OWL }]]);
  const fake = createFakeVscode();
  fake.settings = { 'workbench.colorTheme': 'Apple //e Amber' };
  fake.activate(globalState);
  await fake.settle();
  assert.strictEqual(fake.settings['workbench.colorTheme'], 'Apple //e');
  assert.deepStrictEqual(fake.settings['degauss.phosphorColors'], { apple2e: 'amber' });
  assert(fake.settings['workbench.colorCustomizations']['[Apple //e]']);
});
