// Seeded randomness. Deliberately dependency-free so it can be unit tested under Node and
// mirrored exactly by the run monitor on the server.
//
// All gameplay randomness goes through here. A run's seed comes from the chain, which makes the
// run reproducible and lets the monitor derive independently what should have spawned.
// mulberry32: small, fast, and good enough for a game.

let _seed = '';
let _state = (Math.random() * 0x100000000) >>> 0; // unseeded default: behaves as it always did

function _mulberry32() {
  _state = (_state + 0x6d2b79f5) >>> 0;
  let t = _state;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// Folds a hex seed of any length down to the generator's 32-bit state, with FNV-1a.
export function setSeed(seedHex) {
  _seed = String(seedHex);
  const hex = _seed.replace(/^0x/i, '');
  let h = 0x811c9dc5 >>> 0; // FNV-1a offset basis
  for (let i = 0; i < hex.length; i++) {
    h ^= hex.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0; // FNV-1a prime
  }
  _state = h >>> 0;
}

export function getSeed() { return _seed; }

export const random = () => _mulberry32();
export const rand = (a = 0, b = 1) => a + _mulberry32() * (b - a);
export const randInt = (a, b) => Math.floor(rand(a, b + 1));
export const choose = (arr) => arr[Math.floor(_mulberry32() * arr.length)];
