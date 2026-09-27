const test = require('node:test');
const assert = require('node:assert');
const { createFakeVscode } = require('./helpers/fake-vscode');

const { computeSizes, sharpPoints } = createFakeVscode().activate()._internal;
// Sizes are rounded to 3 decimals (21.333, not 21.3333...), so allow for that.
const isWhole = (x) => Math.abs(x - Math.round(x)) < 1e-3;
const SCALES = [1, 1.25, 1.5, 1.75, 2, 2.25, 2.5, 3];

test('VS Code font sizes put every font pixel on whole screen pixels', () => {
  for (const scale of SCALES) {
    const { fontSize } = computeSizes(20, 16, scale);
    const pixelsPerDot = (fontSize * scale) / 16;
    assert(isWhole(pixelsPerDot) && pixelsPerDot >= 1, `${scale * 100}%: ${fontSize}px gives ${pixelsPerDot} pixels per dot`);
    assert(Math.abs(fontSize - 20) <= 8 / scale + 1e-9, `${scale * 100}%: ${fontSize}px is the nearest sharp size`);
  }
});

test('line heights are whole screen pixels with the text centered on a whole pixel', () => {
  for (const scale of SCALES) {
    const { fontSize, lineHeight } = computeSizes(20, 16, scale);
    assert(lineHeight >= fontSize, `${scale * 100}%: line height ${lineHeight} fits the font`);
    const linePixels = lineHeight * scale;
    assert(isWhole(linePixels), `${scale * 100}%: ${lineHeight}px line is ${linePixels} screen pixels`);
    assert.strictEqual(Math.round(linePixels - fontSize * scale) % 2, 0, `${scale * 100}%: even spare pixels`);
  }
});

test('known values', () => {
  assert.deepStrictEqual(computeSizes(20, 16, 1.5), { fontSize: 21.333, lineHeight: 28 });
  assert.deepStrictEqual(computeSizes(20, 16, 1), { fontSize: 16, lineHeight: 22 });
});

test('Windows Terminal point sizes are sharp', () => {
  for (const dpi of [96, 120, 144, 168, 192]) {
    for (const points of [12, 14, 16]) {
      const sharp = sharpPoints(points, 16, dpi);
      assert(isWhole((sharp * dpi) / 72 / 16), `${dpi} DPI: ${points}pt -> ${sharp}pt`);
    }
  }
  assert.strictEqual(sharpPoints(16, 16, 144), 16);
  assert.strictEqual(sharpPoints(12, 16, 144), 16);
  assert.strictEqual(sharpPoints(16, 16, 96), 12);
});
