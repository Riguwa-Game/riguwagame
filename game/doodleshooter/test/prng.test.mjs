import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setSeed, getSeed, rand, randInt, choose, random } from '../src/prng.js';

const SEED = '0x00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

function sequence(seed, n = 64) {
  setSeed(seed);
  return Array.from({ length: n }, () => rand());
}

test('the same seed produces the same sequence', () => {
  assert.deepEqual(sequence(SEED), sequence(SEED));
});

test('different seeds produce different sequences', () => {
  assert.notDeepEqual(sequence(SEED), sequence('0x' + 'ab'.repeat(32)));
});

test('rand stays inside its bounds', () => {
  setSeed(SEED);
  for (let i = 0; i < 1000; i++) {
    const v = rand(5, 9);
    assert.ok(v >= 5 && v < 9, `rand(5,9) returned ${v}`);
  }
});

test('randInt is inclusive at both ends and never leaves the range', () => {
  setSeed(SEED);
  const seen = new Set();
  for (let i = 0; i < 2000; i++) seen.add(randInt(1, 3));
  assert.deepEqual([...seen].sort(), [1, 2, 3]);
});

test('choose never returns undefined for a non-empty array', () => {
  setSeed(SEED);
  const arr = ['a', 'b', 'c'];
  for (let i = 0; i < 500; i++) assert.ok(arr.includes(choose(arr)));
});

test('getSeed reports the seed that was set', () => {
  setSeed(SEED);
  assert.equal(getSeed(), SEED);
});

test('the generator is usable before any seed is set', () => {
  const v = random();
  assert.ok(v >= 0 && v < 1);
});

test('a seed with no 0x prefix behaves the same as one with it', () => {
  const a = sequence(SEED);
  const b = sequence(SEED.slice(2));
  assert.deepEqual(a, b, 'the 0x prefix must be stripped before folding');
});

test('the distribution is not obviously degenerate', () => {
  setSeed(SEED);
  const buckets = new Array(10).fill(0);
  for (let i = 0; i < 100000; i++) buckets[Math.floor(rand() * 10)]++;
  for (const [i, n] of buckets.entries()) {
    assert.ok(n > 8000 && n < 12000, `bucket ${i} had ${n} of 100000, expected roughly 10000`);
  }
});
