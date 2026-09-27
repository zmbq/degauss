// Synthesizes the degauss sound, so no recording (and no recording's license) is needed. A CRT's degauss
// coil is driven straight from the mains through a thermistor that heats up within a second: a relay
// click, a loud 60 Hz hum that dies away as the current drops, and the shadow mask and chassis ringing.
// Deterministic (seeded noise), so every build produces the same file.

const RATE = 22050;
const SECONDS = 2.2;
const MAINS = 60;

function noise(seed) {
  // mulberry32
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 2 ** 31 - 1;
  };
}

export function degaussSamples() {
  const random = noise(1987);
  const samples = new Float64Array(Math.round(RATE * SECONDS));
  const ring = [ // the shadow mask's "boing": inharmonic partials, frequency, level, decay (s)
    [410, 0.22, 0.5], [655, 0.16, 0.36], [1010, 0.1, 0.24], [1540, 0.06, 0.15],
  ];
  for (let i = 0; i < samples.length; i++) {
    const t = i / RATE;
    const phase = 2 * Math.PI * MAINS * t;
    // The relay closing.
    const click = random() * Math.exp(-t / 0.004) * 0.6;
    // The coil: a saturated (buzzy) mains hum with a strong second harmonic, as transformers hum.
    const hum = (Math.tanh(3 * Math.sin(phase)) * 0.5 + Math.sin(2 * phase + 0.7) * 0.35 + Math.sin(3 * phase) * 0.15)
      * Math.min(1, t / 0.008) * (0.8 * Math.exp(-t / 0.42) + 0.2 * Math.exp(-t / 1.1));
    // The first jolt of the magnetic field.
    const thump = Math.sin(2 * Math.PI * 45 * t) * Math.exp(-t / 0.08) * 0.5;
    let boing = 0;
    for (const [f, level, decay] of ring) {
      const glide = 1 + 0.02 * Math.exp(-t / 0.1);
      boing += Math.sin(2 * Math.PI * f * glide * t) * level * Math.exp(-t / decay);
    }
    samples[i] = click + hum * 0.7 + thump + boing;
  }
  const peak = samples.reduce((m, s) => Math.max(m, Math.abs(s)), 0);
  const fade = Math.round(RATE * 0.05);
  for (let i = 0; i < samples.length; i++) {
    samples[i] = (samples[i] / peak) * 0.85 * Math.min(1, (samples.length - 1 - i) / fade);
  }
  return samples;
}

// A 16-bit mono PCM WAV file.
export function degaussWav() {
  const samples = degaussSamples();
  const data = Buffer.alloc(samples.length * 2);
  samples.forEach((s, i) => data.writeInt16LE(Math.round(s * 32767), i * 2));
  const header = Buffer.alloc(44);
  header.write('RIFF', 0);
  header.writeUInt32LE(36 + data.length, 4);
  header.write('WAVE', 8);
  header.write('fmt ', 12);
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20); // PCM
  header.writeUInt16LE(1, 22); // mono
  header.writeUInt32LE(RATE, 24);
  header.writeUInt32LE(RATE * 2, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write('data', 36);
  header.writeUInt32LE(data.length, 40);
  return Buffer.concat([header, data]);
}
