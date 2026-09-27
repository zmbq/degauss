// Retro: Degauss. Pressing a CRT's degauss button made the picture wobble and swirl with color for a
// second, with a loud hum. VS Code doesn't let extensions bend the whole window, so this wobbles and tints
// the visible editors with temporary decorations (nothing is written to settings) while the system plays
// the sound (generated/degauss.wav, synthesized by tools/degauss-sound.mjs).
const { execFile } = require('child_process');

// Replaceable by the tests.
const options = { frames: 32, frameMs: 40, play: playSound };
const WOBBLE_PX = 6;

const toRgb = (hex) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16));
const toHex = (rgb) => '#' + rgb.map((c) => Math.round(Math.min(255, Math.max(0, c))).toString(16).padStart(2, '0')).join('').toUpperCase();

// Rotates a color's hue (the matrix of CSS's hue-rotate filter).
function hueRotate(hex, degrees) {
  const [r, g, b] = toRgb(hex);
  const c = Math.cos((degrees * Math.PI) / 180);
  const s = Math.sin((degrees * Math.PI) / 180);
  return toHex([
    r * (0.213 + 0.787 * c - 0.213 * s) + g * (0.715 - 0.715 * c - 0.715 * s) + b * (0.072 - 0.072 * c + 0.928 * s),
    r * (0.213 - 0.213 * c + 0.143 * s) + g * (0.715 + 0.285 * c + 0.14 * s) + b * (0.072 - 0.072 * c - 0.283 * s),
    r * (0.213 - 0.213 * c - 0.787 * s) + g * (0.715 - 0.715 * c + 0.715 * s) + b * (0.072 + 0.928 * c + 0.072 * s),
  ]);
}

// A fully saturated color of the given hue.
function rainbow(hue) {
  const h = (((hue % 360) + 360) % 360) / 60;
  const x = 1 - Math.abs((h % 2) - 1);
  const [r, g, b] = [[1, x, 0], [x, 1, 0], [0, 1, x], [0, x, 1], [x, 0, 1], [1, 0, x]][Math.floor(h)];
  return toHex([r * 255, g * 255, b * 255]);
}

// The disturbance at time t (0 to 1): it's strongest at the start and dies away, like the coil's current.
// hue swings back and forth (the colors swirl); tintHue sweeps around the rainbow (the color blotches).
function degaussFrame(t) {
  const strength = (1 - t) ** 2;
  return { strength, hue: 240 * strength * Math.sin(2 * Math.PI * 4 * t), tintHue: 720 * t };
}

function playSound(file) {
  const ignore = () => {};
  if (process.platform === 'win32') {
    const command = `(New-Object Media.SoundPlayer '${file.replace(/'/g, "''")}').PlaySync()`;
    execFile('powershell.exe', ['-NoProfile', '-NonInteractive', '-Command', command], { windowsHide: true }, ignore);
  } else if (process.platform === 'darwin') {
    execFile('afplay', [file], ignore);
  } else {
    execFile('paplay', [file], (err) => err && execFile('aplay', ['-q', file], ignore));
  }
}

let running = false;

// Wobbles and tints the visible editors. `color` is the look's text color (hue-rotated while it swirls);
// without one (not a Retro look), the text keeps its colors and only wobbles.
async function degauss(vscode, { sound, color }) {
  if (running) return;
  running = true;
  if (sound) options.play(sound);
  let current = [];
  try {
    for (let i = 0; i < options.frames; i++) {
      const { strength, hue, tintHue } = degaussFrame(i / options.frames);
      const types = new Map(); // wobble offset -> decoration type
      const typeFor = (offset) => {
        if (!types.has(offset)) {
          types.set(offset, vscode.window.createTextEditorDecorationType({
            color: color ? hueRotate(color, hue) : undefined,
            before: offset ? { contentText: '​', margin: `0 0 0 ${offset}px` } : undefined,
          }));
        }
        return types.get(offset);
      };
      const alpha = Math.round(strength * 0.3 * 255).toString(16).padStart(2, '0');
      const tint = vscode.window.createTextEditorDecorationType({ backgroundColor: rainbow(tintHue) + alpha, isWholeLine: true });

      for (const editor of vscode.window.visibleTextEditors) {
        const byOffset = new Map();
        const whole = [];
        for (const visible of editor.visibleRanges) {
          for (let line = visible.start.line; line <= visible.end.line; line++) {
            const range = editor.document.lineAt(line).range;
            const offset = Math.round(WOBBLE_PX * strength * (1 + Math.sin(2 * Math.PI * (line / 10 + 5 * i / options.frames))));
            if (!byOffset.has(offset)) byOffset.set(offset, []);
            byOffset.get(offset).push(range);
            whole.push(range);
          }
        }
        for (const [offset, ranges] of byOffset) editor.setDecorations(typeFor(offset), ranges);
        editor.setDecorations(tint, whole);
      }
      // Replace the previous frame only once this one is up, so nothing flickers back in between.
      current.forEach((type) => type.dispose());
      current = [...types.values(), tint];
      await new Promise((resolve) => setTimeout(resolve, options.frameMs));
    }
  } finally {
    current.forEach((type) => type.dispose());
    running = false;
  }
}

module.exports = { degauss, degaussFrame, hueRotate, rainbow, options };
