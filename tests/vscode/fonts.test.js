// The extension's font install/uninstall on Windows, against a temporary folder and a throwaway registry
// key: the fonts are shared with the RetroLooks PowerShell module through marker files.
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
  const sandbox = fs.mkdtempSync(path.join(os.tmpdir(), 'retro-looks-test-'));
  const key = `HKCU\\Software\\RetroLooksTest-${crypto.randomUUID()}\\Fonts`;
  const saved = { LOCALAPPDATA: process.env.LOCALAPPDATA, key: process.env.RETRO_LOOKS_TEST_FONT_KEY };
  process.env.LOCALAPPDATA = sandbox;
  process.env.RETRO_LOOKS_TEST_FONT_KEY = key;
  t.after(() => {
    process.env.LOCALAPPDATA = saved.LOCALAPPDATA;
    if (saved.key === undefined) delete process.env.RETRO_LOOKS_TEST_FONT_KEY;
    else process.env.RETRO_LOOKS_TEST_FONT_KEY = saved.key;
    try { execFileSync('reg', ['delete', key.replace(/\\Fonts$/, ''), '/f'], { stdio: 'ignore' }); } catch { /* already gone */ }
    fs.rmSync(sandbox, { recursive: true, force: true });
  });

  const { EXTENSION_DIR } = require('./helpers/fake-vscode');
  const fonts = JSON.parse(fs.readFileSync(path.join(EXTENSION_DIR, 'generated', 'fonts.json'), 'utf8'));
  const usersDir = path.join(sandbox, 'RetroLooks', 'font-users');
  return {
    fonts,
    fontDir: path.join(sandbox, 'Microsoft', 'Windows', 'Fonts'),
    usersDir,
    marker: (name) => path.join(usersDir, name),
    registered: () => fonts.filter((f) => {
      try { return execFileSync('reg', ['query', key, '/v', f.registryName], { encoding: 'utf8' }).includes(f.installedFile); } catch { return false; }
    }).length,
    runUninstallHook: () => execFileSync(process.execPath, [path.join(EXTENSION_DIR, 'uninstall.js')], { env: process.env }),
  };
}

test('installing adds a marker; uninstalling keeps fonts the PowerShell module still uses', windowsOnly, async (t) => {
  const box = useSandbox(t);
  const { createFakeVscode } = require('./helpers/fake-vscode');
  const fake = createFakeVscode();
  fake.activate();
  await fake.settle();

  await fake.commands['retroLooks.install']();
  assert.strictEqual(box.registered(), box.fonts.length, 'all fonts registered');
  for (const f of box.fonts) assert(fs.existsSync(path.join(box.fontDir, f.installedFile)), `${f.installedFile} copied`);
  assert.match(fs.readFileSync(box.marker('vscode'), 'utf8'), /Retro Looks for VS Code \d/);

  // The RetroLooks module also uses the fonts: uninstalling from VS Code keeps them.
  fs.writeFileSync(box.marker('powershell'), 'Retro Looks for Windows Terminal');
  await fake.commands['retroLooks.uninstall']();
  assert(!fs.existsSync(box.marker('vscode')), 'own marker removed');
  assert(fs.existsSync(box.marker('powershell')), "the module's marker is left alone");
  assert.strictEqual(box.registered(), box.fonts.length, 'fonts kept');
  assert(fake.messages.some((m) => /still used by Retro Looks for Windows Terminal/.test(m)), 'user is told why');

  // Once nothing else uses them, uninstalling removes the fonts and the marker folder.
  fs.rmSync(box.marker('powershell'));
  await fake.commands['retroLooks.install']();
  await fake.commands['retroLooks.uninstall']();
  assert.strictEqual(box.registered(), 0, 'fonts unregistered');
  for (const f of box.fonts) assert(!fs.existsSync(path.join(box.fontDir, f.installedFile)), `${f.installedFile} deleted`);
  assert(!fs.existsSync(path.dirname(box.usersDir)), 'no RetroLooks folder left behind');
});

test('the uninstall hook removes the fonts unless the PowerShell module still uses them', windowsOnly, async (t) => {
  const box = useSandbox(t);
  const { createFakeVscode } = require('./helpers/fake-vscode');
  const fake = createFakeVscode();
  fake.activate();
  await fake.settle();
  await fake.commands['retroLooks.install']();

  fs.writeFileSync(box.marker('powershell'), 'Retro Looks for Windows Terminal');
  box.runUninstallHook();
  assert(!fs.existsSync(box.marker('vscode')), 'marker removed');
  assert.strictEqual(box.registered(), box.fonts.length, 'fonts kept for the module');

  fs.rmSync(box.marker('powershell'));
  fs.writeFileSync(box.marker('vscode'), 'Retro Looks for VS Code');
  box.runUninstallHook();
  assert.strictEqual(box.registered(), 0, 'fonts removed');
  assert(!fs.existsSync(path.dirname(box.usersDir)), 'no RetroLooks folder left behind');
});

test('fonts installed before markers existed are adopted when the extension starts', windowsOnly, async (t) => {
  const box = useSandbox(t);
  const { createFakeVscode } = require('./helpers/fake-vscode');
  const fake = createFakeVscode();
  fake.activate();
  await fake.settle();
  await fake.commands['retroLooks.install']();
  fs.rmSync(box.marker('vscode'));

  createFakeVscode().activate();
  await fake.settle();
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
  const state = new Map([['retroLooks.installReminderDismissed', true]]);
  assert(await start(state, "Don't Show Again"), 'reminds after a reinstall');
  assert(!(await start(state)), "Don't Show Again is honored for this installation");

  state.set('retroLooks.installReminderDismissed', 'some other installation');
  assert(await start(state), 'a different installation is reminded');
});
