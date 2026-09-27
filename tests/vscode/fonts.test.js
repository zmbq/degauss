// The extension's font install/uninstall on Windows, against a temporary folder and a throwaway registry key.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { execFileSync } = require('node:child_process');

const windowsOnly = { skip: process.platform !== 'win32' && 'installs fonts on Windows only' };

test('fonts are kept while Retro Looks for Windows Terminal uses them', windowsOnly, async (t) => {
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

  // Loaded after the environment is set, since the extension reads it when it loads.
  const { createFakeVscode, EXTENSION_DIR } = require('./helpers/fake-vscode');
  const fonts = JSON.parse(fs.readFileSync(path.join(EXTENSION_DIR, 'generated', 'fonts.json'), 'utf8'));
  const registered = () => fonts.filter((f) => {
    try { return execFileSync('reg', ['query', key, '/v', f.registryName], { encoding: 'utf8' }).includes(f.installedFile); } catch { return false; }
  }).length;
  const fontDir = path.join(sandbox, 'Microsoft', 'Windows', 'Fonts');
  const fragmentDir = path.join(sandbox, 'Microsoft', 'Windows Terminal', 'Fragments', 'Retro Looks');

  const fake = createFakeVscode();
  fake.activate();
  await fake.settle();

  await fake.commands['retroLooks.install']();
  assert.strictEqual(registered(), fonts.length, 'all fonts registered');
  for (const f of fonts) assert(fs.existsSync(path.join(fontDir, f.installedFile)), `${f.installedFile} copied`);

  // The Terminal profiles are installed: uninstalling from VS Code keeps the fonts.
  fs.mkdirSync(fragmentDir, { recursive: true });
  await fake.commands['retroLooks.uninstall']();
  assert.strictEqual(registered(), fonts.length, 'fonts kept while the Terminal profiles are installed');
  assert(fake.messages.some((m) => /Windows Terminal is installed/.test(m)), 'user is told why');

  // Without them, uninstalling removes the fonts.
  fs.rmSync(fragmentDir, { recursive: true });
  await fake.commands['retroLooks.uninstall']();
  assert.strictEqual(registered(), 0, 'fonts unregistered');
  for (const f of fonts) assert(!fs.existsSync(path.join(fontDir, f.installedFile)), `${f.installedFile} deleted`);
});
