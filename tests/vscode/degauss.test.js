// Degauss: Degauss!: the sound, the effect's math, and the effect through a fake VS Code.
const test = require('node:test');
const assert = require('node:assert');
const fs = require('node:fs');
const path = require('node:path');
const { createFakeVscode, fakeEditor, EXTENSION_DIR } = require('./helpers/fake-vscode');
const degaussModule = require(path.join(EXTENSION_DIR, 'degauss.js'));
const { degaussFrame, hueRotate, rainbow, options } = degaussModule;

const played = [];
options.play = (file) => played.push(file);
options.frameMs = 0;

test('both products ship the recorded degauss sound', () => {
  const root = path.join(EXTENSION_DIR, '..');
  const wav = fs.readFileSync(path.join(EXTENSION_DIR, 'generated', 'degauss.wav'));
  assert.strictEqual(wav.toString('ascii', 0, 4), 'RIFF');
  assert.strictEqual(wav.toString('ascii', 8, 12), 'WAVE');
  const seconds = wav.readUInt32LE(40) / wav.readUInt32LE(28);
  assert(seconds > 1 && seconds < 3, `about two seconds long (${seconds})`);
  assert(wav.equals(fs.readFileSync(path.join(root, 'sounds', 'degauss', 'degauss.wav'))), 'copied unchanged from sounds/degauss');
  assert(wav.equals(fs.readFileSync(path.join(root, 'dist', 'powershell', 'Degauss', 'degauss.wav'))), 'the module gets the same sound');
  for (const notices of [path.join(EXTENSION_DIR, 'THIRD-PARTY-NOTICES.md'), path.join(root, 'dist', 'powershell', 'Degauss', 'THIRD-PARTY-NOTICES.md')]) {
    assert(fs.readFileSync(notices, 'utf8').includes('by Sanderboah -- https://freesound.org/s/838728/ -- License: Creative Commons 0'), `the recording is credited in ${notices}`);
  }
});

test('the disturbance starts strong and dies away', () => {
  assert.strictEqual(degaussFrame(0).strength, 1);
  const strengths = [0, 0.25, 0.5, 0.75, 0.99].map((t) => degaussFrame(t).strength);
  assert.deepStrictEqual([...strengths].sort((a, b) => b - a), strengths);
  assert(strengths.at(-1) < 0.001);
  assert.strictEqual(hueRotate('#33FF66', 0), '#33FF66');
  assert.notStrictEqual(hueRotate('#33FF66', 120), '#33FF66');
  assert.deepStrictEqual([0, 120, 240].map(rainbow), ['#FF0000', '#00FF00', '#0000FF']);
});

test('Degauss: Degauss! plays the sound, wobbles and tints the visible editors, and cleans up', async () => {
  const fake = createFakeVscode();
  fake.editors = [fakeEditor(10, 29)];
  fake.activate();
  await fake.settle();
  fake.answers.push('Apple //e', 'Amber');
  await fake.commands['degauss.choose']();
  played.length = 0;

  await fake.commands['degauss.degauss']();
  assert.deepStrictEqual(played, [path.join(EXTENSION_DIR, 'generated', 'degauss.wav')]);
  const [editor] = fake.editors;
  const lines = (type) => editor.decorations.filter(([t]) => t === type).flatMap(([, ranges]) => ranges.map((r) => r.line));
  const first = fake.decorationTypes.filter((t) => editor.decorations.some(([d]) => d === t))[0];
  assert(fake.decorationTypes.some((t) => t.options.before?.margin), 'lines are shifted (the wobble)');
  assert(fake.decorationTypes.some((t) => t.options.isWholeLine && t.options.backgroundColor), 'lines are tinted');
  assert(new Set(fake.decorationTypes.map((t) => t.options.color).filter(Boolean)).size > 5, 'the text color swirls');
  assert(lines(first).every((l) => l >= 10 && l <= 29), 'only visible lines are decorated');
  assert(fake.decorationTypes.every((t) => t.disposed), 'every decoration is gone at the end');
  const settings = JSON.stringify(fake.settings);
  await fake.commands['degauss.degauss']();
  assert.strictEqual(JSON.stringify(fake.settings), settings, 'no settings are written');
});

test('outside a Degauss look, the text keeps its colors', async () => {
  const fake = createFakeVscode();
  fake.editors = [fakeEditor(0, 5)];
  fake.activate();
  await fake.settle();
  await fake.commands['degauss.degauss']();
  assert(fake.decorationTypes.length > 0);
  assert(fake.decorationTypes.every((t) => !t.options.color), 'no text color');
  assert(fake.decorationTypes.every((t) => t.disposed));
});
