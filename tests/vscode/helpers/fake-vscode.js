// A fake `vscode` module for testing extension.js without VS Code: in-memory user settings (with the
// defaults declared in vscode/package.json), scripted answers for pickers, and captured messages.
const Module = require('node:module');
const path = require('node:path');
const assert = require('node:assert');

const EXTENSION_DIR = path.join(__dirname, '..', '..', '..', 'vscode');

function createFakeVscode() {
  const pkg = require(path.join(EXTENSION_DIR, 'package.json'));
  const defaults = Object.fromEntries(
    Object.entries(pkg.contributes?.configuration?.properties ?? {}).map(([key, prop]) => [key, prop.default])
  );

  const fake = {
    settings: {}, // user (global) settings, by full key
    answers: [], // queued answers: quick pick labels or input box strings
    messages: [],
    commands: {},
    context: {}, // context keys set with setContext (they drive `when` clauses in package.json)
    listeners: [],
    editors: [], // visible text editors (see fakeEditor)
    decorationTypes: [], // every decoration type created: { options, disposed }
  };

  const fire = (changed) => fake.listeners.forEach((fn) => fn({
    affectsConfiguration: (section) => changed === section || changed.startsWith(section + '.'),
  }));

  fake.vscode = {
    ConfigurationTarget: { Global: 1 },
    workspace: {
      getConfiguration(section) {
        const full = (key) => (section ? `${section}.${key}` : key);
        return {
          get: (key) => (full(key) in fake.settings ? fake.settings[full(key)] : defaults[full(key)]),
          inspect: (key) => ({ globalValue: fake.settings[full(key)], defaultValue: defaults[full(key)] }),
          update: async (key, value) => {
            if (value === undefined) delete fake.settings[full(key)];
            else fake.settings[full(key)] = structuredClone(value);
            fire(full(key));
          },
        };
      },
      onDidChangeConfiguration: (fn) => {
        fake.listeners.push(fn);
        return { dispose() {} };
      },
    },
    window: {
      get visibleTextEditors() { return fake.editors; },
      createTextEditorDecorationType(options) {
        const type = { options, disposed: false, dispose() { type.disposed = true; } };
        fake.decorationTypes.push(type);
        return type;
      },
      async showQuickPick(items) {
        const label = fake.answers.shift();
        const item = items.find((i) => i.label === label);
        assert(item, `no quick pick item "${label}" among: ${items.map((i) => i.label).join(', ')}`);
        return item;
      },
      async showInputBox(options) {
        const value = fake.answers.shift();
        assert.strictEqual(options.validateInput?.(value) ?? null, null, `input "${value}" was rejected`);
        return value;
      },
      async showInformationMessage(message, ...buttons) {
        fake.messages.push(message);
        // Clicks a button if it's the next queued answer; otherwise the notification is dismissed.
        return buttons.includes(fake.answers[0]) ? fake.answers.shift() : undefined;
      },
      async showWarningMessage(message, ...buttons) {
        fake.messages.push(message);
        // A missing font (on a test machine) shouldn't stop a look from being applied.
        return buttons.includes('Apply Anyway') ? 'Apply Anyway' : undefined;
      },
    },
    commands: {
      registerCommand(id, fn) {
        fake.commands[id] = fn;
        return { dispose() {} };
      },
      async executeCommand(id, ...args) {
        if (id === 'setContext') fake.context[args[0]] = args[1];
      },
    },
    env: { openExternal() {} },
    Uri: { file: (p) => ({ fsPath: p }) },
  };

  // Loads a fresh copy of extension.js wired to this fake and activates it.
  fake.activate = (globalState = new Map()) => {
    const originalLoad = Module._load;
    Module._load = function (request, ...rest) {
      return request === 'vscode' ? fake.vscode : originalLoad.call(this, request, ...rest);
    };
    try {
      const file = require.resolve(path.join(EXTENSION_DIR, 'extension.js'));
      delete require.cache[file];
      const extension = require(file);
      fake.listeners.length = 0;
      fake.globalState = globalState;
      extension.activate({
        extensionPath: EXTENSION_DIR,
        subscriptions: [],
        globalState: {
          get: (key) => globalState.get(key),
          update: async (key, value) => (value === undefined ? globalState.delete(key) : globalState.set(key, value)),
        },
      });
      fake.extension = extension;
      return extension;
    } finally {
      Module._load = originalLoad;
    }
  };

  // Waits for the extension's startup checks (however long the registry takes, e.g. on a slow CI
  // machine), then lets other fire-and-forget work (settings listeners) finish.
  fake.settle = async () => {
    await fake.extension?._internal.startup();
    await new Promise((resolve) => setTimeout(resolve, 200));
  };
  return fake;
}

// A visible editor showing lines first..last; it records what decorations were set on it.
function fakeEditor(first, last) {
  const editor = {
    visibleRanges: [{ start: { line: first }, end: { line: last } }],
    document: { lineAt: (line) => ({ range: { line } }) },
    decorations: [], // [type, ranges] in the order they were set
    setDecorations(type, ranges) { editor.decorations.push([type, ranges]); },
  };
  return editor;
}

module.exports = { createFakeVscode, fakeEditor, EXTENSION_DIR };
