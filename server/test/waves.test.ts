import { test } from 'node:test';
import assert from 'node:assert/strict';
import { maxEnemiesInWave, maxAliveInWave, minSecondsForWave, isBossWave } from '../src/monitor/waves.ts';

test('boss waves are every fifth', () => {
  assert.equal(isBossWave(0), false);
  for (const w of [5, 10, 15, 20]) assert.ok(isBossWave(w), `wave ${w} is a boss wave`);
  for (const w of [1, 4, 6, 9, 11]) assert.ok(!isBossWave(w), `wave ${w} is not`);
});

test('the enemy bound grows with the wave and then plateaus', () => {
  assert.equal(maxEnemiesInWave(0), 0);
  assert.ok(maxEnemiesInWave(1) > 0);
  for (let w = 1; w < 40; w++) {
    if (isBossWave(w) || isBossWave(w + 1)) continue; // boss waves use a different formula
    assert.ok(
      maxEnemiesInWave(w + 1) >= maxEnemiesInWave(w),
      `wave ${w + 1} must not allow fewer enemies than wave ${w}`,
    );
  }
});

test('the bound is never below what the game can actually queue', () => {
  // Recompute the game's own formula for both modifier outcomes and assert we bound both.
  for (let w = 1; w <= 40; w++) {
    for (const swarm of [false, true]) {
      const actual = isBossWave(w)
        ? 7 + w + 1
        : Math.round(Math.min(5 + w * 2.0, 32 + w) * (swarm ? 1.35 : 1));
      assert.ok(
        maxEnemiesInWave(w) >= actual,
        `wave ${w} swarm=${swarm}: bound ${maxEnemiesInWave(w)} < actual ${actual}`,
      );
    }
  }
});

test('maxAlive bounds the game\'s own concurrency cap for either modifier outcome', () => {
  // maxAlive is the spawner's concurrency cap, not a count - on boss waves it can legitimately
  // exceed the queue size, so there is no ordering between it and maxEnemiesInWave.
  assert.equal(maxAliveInWave(0), 0);
  for (let w = 1; w <= 60; w++) {
    for (const swarm of [false, true]) {
      let actual = Math.min(
        4 + Math.floor(w * 0.9) + (swarm ? 3 : 0),
        (swarm ? 22 : 18) + Math.floor(w / 3),
      );
      if (isBossWave(w)) actual += 2 + Math.floor(w / 5);
      assert.ok(
        maxAliveInWave(w) >= actual,
        `wave ${w} swarm=${swarm}: bound ${maxAliveInWave(w)} < actual ${actual}`,
      );
    }
  }
});

test('the time floor is never negative and never absurd', () => {
  assert.equal(minSecondsForWave(0), 0);
  for (let w = 1; w <= 40; w++) {
    const s = minSecondsForWave(w);
    assert.ok(s >= 3, `wave ${w} floor ${s} is below the minimum`);
    assert.ok(s < 300, `wave ${w} floor ${s} would reject honest play`);
  }
});
