// The extension's font install/uninstall on Windows, against a temporary folder and a throwaway registry
// key: the fonts are shared with the Degauss PowerShell module through marker files.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const windowsOnly = { skip: process.platform !== 'win32' && 'installs fonts on Windows only' };

// Points LOCALAPPDATA and the fonts registry key at a sandbox for one test.
function useSandbox(t) {
  const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'degauss-test-'));
  const key = `HKCU\\Software\\DegaussTest-${crypto.randomUUID()}\\Fonts`;
  const saved = { LOCALAPPDATA: process.env.LOCALAPPDATA, key: process.env.DEGAUSS_TEST_FONT_KEY };
  process.env.LOCALAPPDATA = sandbox;
  process.env.DEGAUSS_TEST_FONT_KEY = key;
  t.after(() => {
    process.env.LOCALAPPDATA = saved.LOCALAPPDATA;
    if (saved.key === undefined) delete process.env.DEGAUSS_TEST_FONT_KEY;
    else process.env.DEGAUSS_TEST_FONT_KEY = saved.key;
    try { execFileSync('reg', ['delete', key.replace(/\\Fonts$/, ''), '/f'], { stdio: 'ignore' }); } catch { /* already gone */ }
    fs.rmSync(sandbox, { recursive: true, force: true });
  });

  const { EXTENSION_DIR } = require('./helpers/fake-vscode');
  const fonts = JSON.parse(fs.readFileSync(path.join(EXTENSION_DIR, 'generated', 'fonts.json'), 'utf8'));
  const usersDir = path.join(sandbox, 'Degauss', 'font-users');
  return {
    fonts,
    fontDir: path.join(sandbox, 'Microsoft', 'Windows', 'Fonts'),
    usersDir,
    marker: (name) => path.join(usersDir, name),
    registered: () => fonts.filter((f) => {
      try {
        return execFileSync('reg', ['query', key, '/v', f.registryName], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).includes(f.installedFile);
      } catch { return false; }
    }).length,
    runUninstallHook: () => execFileSync(process.execPath, [path.join(EXTENSION_DIR, 'uninstall.js')], { env: process.env }),
  };
}

test('installing registers and copies the fonts and adds a marker', windowsOnly, async (t) => {
  const box = useSandbox(t);
  const { createFakeVscode } = require('./helpers/fake-vscode');
  const fake = createFakeVscode();
  fake.activate();
  await fake.settle();

  assert.strictEqual(fake.context['degauss.fontsInstalled'], false, 'Install Fonts is offered while fonts are missing');
  await fake.commands['degauss.install']();
  assert.strictEqual(fake.context['degauss.fontsInstalled'], true, 'and hidden once they are installed');
  assert.strictEqual(box.registered(), box.fonts.length, 'all fonts registered');
  for (const f of box.fonts) assert(fs.existsSync(path.join(box.fontDir, f.installedFile)), `${f.installedFile} copied`);
  assert.match(fs.readFileSync(box.marker('vscode'), 'utf8'), /Degauss for VS Code \d/);
  assert(!('degauss.uninstall' in fake.commands), 'no separate uninstall command: uninstalling the extension does it');
});

test('the uninstall hook removes the fonts unless the PowerShell module still uses them', windowsOnly, async (t) => {
  const box = useSandbox(t);
  const { createFakeVscode } = require('./helpers/fake-vscode');
  const fake = createFakeVscode();
  fake.activate();
  await fake.settle();
  await fake.commands['degauss.install']();

  fs.writeFileSync(box.marker('powershell'), 'Degauss for Windows Terminal');
  box.runUninstallHook();
  assert(!fs.existsSync(box.marker('vscode')), 'own marker removed');
  assert(fs.existsSync(box.marker('powershell')), "the module's marker is left alone");
  assert.strictEqual(box.registered(), box.fonts.length, 'fonts kept for the module');

  fs.rmSync(box.marker('powershell'));
  fs.writeFileSync(box.marker('vscode'), 'Degauss for VS Code');
  box.runUninstallHook();
  assert.strictEqual(box.registered(), 0, 'fonts removed');
  for (const f of box.fonts) assert(!fs.existsSync(path.join(box.fontDir, f.installedFile)), `${f.installedFile} deleted`);
  assert(!fs.existsSync(path.dirname(box.usersDir)), 'no Degauss folder left behind');
});

test('fonts that are already installed are adopted when the extension starts', windowsOnly, async (t) => {
  const box = useSandbox(t);
  const { createFakeVscode } = require('./helpers/fake-vscode');
  const fake = createFakeVscode();
  fake.activate();
  await fake.settle();
  await fake.commands['degauss.install']();
  fs.rmSync(box.marker('vscode'));

  const restarted = createFakeVscode();
  restarted.activate();
  await restarted.settle();
  assert(fs.existsSync(box.marker('vscode')), 'marker added for already installed fonts');
});

test('"Don\'t Show Again" lasts for this installation; a reinstall reminds again', windowsOnly, async (t) => {
  useSandbox(t); // no fonts installed in the sandbox, so the reminder has a reason to appear
  const { createFakeVscode } = require('./helpers/fake-vscode');
  const reminder = /install the retro fonts\?/;
  const start = async (globalState, answer) => {
    const fake = createFakeVscode();
    if (answer) fake.answers.push(answer);
    fake.activate(globalState);
    await fake.settle();
    return fake.messages.some((m) => reminder.test(m));
  };

  // Dismissed by an earlier installation (what VS Code keeps after an uninstall): remind again.
  const state = new Map([['degauss.installReminderDismissed', true]]);
  assert(await start(state, "Don't Show Again"), 'reminds after a reinstall');
  assert(!(await start(state)), "Don't Show Again is honored for this installation");

  state.set('degauss.installReminderDismissed', 'some other installation');
  assert(await start(state), 'a different installation is reminded');
});
