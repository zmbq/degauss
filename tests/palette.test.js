const test = require('node:test');
const assert = require('node:assert');
const { PRESETS, resolveColor, phosphorPalette, fillTemplate } = require('../extension/palette');

test('presets resolve by name, in any case', () => {
  for (const [name, hex] of Object.entries(PRESETS)) {
    assert.strictEqual(resolveColor(name), hex);
    assert.strictEqual(resolveColor(name.toUpperCase()), hex);
  }
});

test('hex colors resolve with or without #', () => {
  assert.strictEqual(resolveColor('#40e0ff'), '#40E0FF');
  assert.strictEqual(resolveColor('40E0FF'), '#40E0FF');
  assert.strictEqual(resolveColor('  #40E0FF  '), '#40E0FF');
});

test('dark colors are brightened so their strongest channel reaches 200', () => {
  const [r, g, b] = [1, 3, 5].map((i) => parseInt(resolveColor('#102030').slice(i, i + 2), 16));
  assert.strictEqual(Math.max(r, g, b), 200);
  assert(r < g && g < b, 'hue is kept');
  assert.strictEqual(resolveColor('#F0A848'), '#F0A848', 'bright colors are unchanged');
});

test('invalid colors are rejected', () => {
  for (const bad of ['', 'purple', '#12345', '#1234567', '#GGGGGG', '#000000', null, undefined, 42]) {
    assert.strictEqual(resolveColor(bad), null, String(bad));
  }
});

test('palettes run from dark to light', () => {
  const p = phosphorPalette(PRESETS.amber);
  const luma = (hex) => [1, 3, 5].reduce((sum, i) => sum + parseInt(hex.slice(i, i + 2), 16), 0);
  const order = ['deep', 'bg', 'raised', 'faint', 'border', 'selection', 'dim', 'comment', 'muted', 'soft', 'text', 'full', 'light1', 'light2', 'light3', 'light4'];
  for (let i = 1; i < order.length; i++) assert(luma(p[order[i]]) >= luma(p[order[i - 1]]), `${order[i - 1]} <= ${order[i]}`);
  assert(luma(p.bright) > luma(p.normal), 'intensified is brighter than normal');
});

test('fillTemplate fills slots and rejects unknown ones', () => {
  assert.deepStrictEqual(fillTemplate('{"a": "${full}"}', { full: '#123456' }), { a: '#123456' });
  assert.throws(() => fillTemplate('{"a": "${nope}"}', {}), /unknown palette slot nope/);
});
