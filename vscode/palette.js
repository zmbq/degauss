// Phosphor colors and the palettes monochrome looks are generated from.
// Shared by tools/build.mjs (to build the default themes) and extension.js (to recolor them at runtime).

const PRESETS = {
  green: '#40F040',
  amber: '#F0A848',
  white: '#E8ECF0',
  cyan: '#48E0E8',
  yellow: '#F0F060',
};

// The 16 VGA text-mode colors, in Windows Terminal's ANSI order. A monochrome VGA display like the IBM 8503
// showed each one as a brightness level: VGA sums 30% red, 59% green and 11% blue into one gray.
const VGA = {
  black: '#000000', red: '#AA0000', green: '#00AA00', yellow: '#AA5500',
  blue: '#0000AA', purple: '#AA00AA', cyan: '#00AAAA', white: '#AAAAAA',
  brightBlack: '#555555', brightRed: '#FF5555', brightGreen: '#55FF55', brightYellow: '#FFFF55',
  brightBlue: '#5555FF', brightPurple: '#FF55FF', brightCyan: '#55FFFF', brightWhite: '#FFFFFF',
};

function hexToRgb(hex) {
  const n = parseInt(hex.replace('#', ''), 16);
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255];
}

function rgbToHex(rgb) {
  return '#' + rgb.map((c) => Math.round(Math.min(255, Math.max(0, c))).toString(16).padStart(2, '0')).join('').toUpperCase();
}

const mix = (a, b, t) => rgbToHex(hexToRgb(a).map((c, i) => c + (hexToRgb(b)[i] - c) * t));

// A phosphor glows brightly whatever its color, so dark custom colors are brightened until their
// strongest channel reaches 200; otherwise every shade derived from them would be too dim to read.
const MIN_PEAK = 200;

// Accepts a preset name or #RRGGBB (# optional, any case). Returns '#RRGGBB', or null if invalid.
function resolveColor(input) {
  if (typeof input !== 'string') return null;
  const value = input.trim().toLowerCase();
  if (PRESETS[value]) return PRESETS[value];
  const match = value.match(/^#?([0-9a-f]{6})$/);
  if (!match) return null;
  const rgb = hexToRgb(match[1]);
  const peak = Math.max(...rgb);
  if (peak === 0) return null;
  return rgbToHex(peak < MIN_PEAK ? rgb.map((c) => (c * MIN_PEAK) / peak) : rgb);
}

// Every shade is the phosphor color dimmed toward black or lit toward white.
// powershell/Degauss/Degauss.psm1 (Get-PhosphorPalette) must compute exactly the same.
function phosphorPalette(color) {
  const dark = (t) => mix('#000000', color, t);
  const light = (t) => mix(color, '#FFFFFF', t);
  const palette = {
    deep: dark(0.055), bg: dark(0.07), raised: dark(0.118), faint: dark(0.165), border: dark(0.227),
    selection: dark(0.36), dim: dark(0.42), comment: dark(0.54), muted: dark(0.7), soft: dark(0.815),
    text: dark(0.9), full: color,
    light1: light(0.2), light2: light(0.38), light3: light(0.54), light4: light(0.7),
    // The two brightness levels of a monochrome terminal like the IBM 3278.
    normal: dark(0.72), bright: light(0.12),
  };
  // The VGA colors as brightness levels (vga_red, vga_brightWhite, ...). Black stays black; every other
  // color gets at least a quarter of the brightness, so dark blue text doesn't vanish on a modern screen.
  for (const [name, hex] of Object.entries(VGA)) {
    const [r, g, b] = hexToRgb(hex);
    const level = (0.3 * r + 0.59 * g + 0.11 * b) / 255;
    palette[`vga_${name}`] = level === 0 ? '#000000' : dark(0.25 + 0.75 * level);
  }
  return palette;
}

// Fills ${slot} placeholders in a template's text and parses it.
function fillTemplate(templateText, palette) {
  return JSON.parse(templateText.replace(/\$\{(\w+)\}/g, (_, key) => {
    if (!(key in palette)) throw new Error(`unknown palette slot ${key}`);
    return palette[key];
  }));
}

module.exports = { PRESETS, VGA, MIN_PEAK, resolveColor, phosphorPalette, fillTemplate, mix };
