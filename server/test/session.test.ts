import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RunSession, SessionError } from '../src/monitor/session.ts';
import { minSecondsForWave } from '../src/monitor/waves.ts';
import type { Hex } from 'viem';

const SEED = ('0x' + 'ab'.repeat(32)) as Hex;
const RUN_ID = ('0x' + '11'.repeat(32)) as Hex;
const PLAYER = '0x1111111111111111111111111111111111111111' as Hex;

const session = (now = 1_000_000) =>
  new RunSession({ runId: RUN_ID, player: PLAYER, seed: SEED, startedAt: now });

/// Advance past the time floor for the wave currently in progress.
function clearWave(s: RunSession, n: number) {
  s.handle({ t: 'wave', n });
  s.setClock(s.clock() + minSecondsForWave(n) + 1);
}

// ---------- positive ----------

test('a clean run through wave 6 is accepted', () => {
  const s = session();
  for (let n = 1; n <= 6; n++) clearWave(s, n);
  s.handle({ t: 'died', wave: 6, score: 4200 });
  const r = s.finish();
  assert.equal(r.waveReached, 6);
  assert.equal(r.score, 4200n);
  assert.equal(r.player, PLAYER);
  assert.equal(r.runId, RUN_ID);
});

test('kills are counted per wave', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  s.handle({ t: 'kill', wave: 1, enemy: 'GRUNT' });
  s.handle({ t: 'kill', wave: 1, enemy: 'GRUNT' });
  assert.equal(s.killsInWave(1), 2);
});

test('damage events are accepted and change nothing', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  s.handle({ t: 'damage', wave: 1, amount: 24 });
  assert.equal(s.waveReached(), 1);
});

test('a run that never reports a wave finishes at wave 0', () => {
  const s = session();
  s.handle({ t: 'died', wave: 0, score: 0 });
  assert.equal(s.finish().waveReached, 0);
});

test('ping is allowed even after death', () => {
  const s = session();
  s.handle({ t: 'died', wave: 0, score: 0 });
  s.handle({ t: 'ping' });
});

// ---------- negative: the whole point of the monitor ----------

test('skipping a wave is rejected', () => {
  const s = session();
  clearWave(s, 1);
  assert.throws(() => s.handle({ t: 'wave', n: 3 }), SessionError);
});

test('going backwards is rejected', () => {
  const s = session();
  clearWave(s, 1);
  clearWave(s, 2);
  assert.throws(() => s.handle({ t: 'wave', n: 1 }), SessionError);
});

test('clearing a wave impossibly fast is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  s.setClock(s.clock() + 1); // far below the floor
  assert.throws(() => s.handle({ t: 'wave', n: 2 }), SessionError);
});

test('more kills than the wave can spawn is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  assert.throws(() => {
    for (let i = 0; i < 500; i++) s.handle({ t: 'kill', wave: 1, enemy: 'GRUNT' });
  }, SessionError);
});

test('a kill attributed to a wave that has not started is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  assert.throws(() => s.handle({ t: 'kill', wave: 5, enemy: 'GRUNT' }), SessionError);
});

test('claiming a death at a higher wave than was reached is rejected', () => {
  const s = session();
  clearWave(s, 1);
  assert.throws(() => s.handle({ t: 'died', wave: 20, score: 1 }), SessionError);
});

test('events after death are rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  s.handle({ t: 'died', wave: 1, score: 10 });
  assert.throws(() => s.handle({ t: 'wave', n: 2 }), SessionError);
});

test('a negative score is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  assert.throws(() => s.handle({ t: 'died', wave: 1, score: -5 }), SessionError);
});

test('a non-integer wave is rejected', () => {
  const s = session();
  assert.throws(() => s.handle({ t: 'wave', n: 1.5 }), SessionError);
});

// ---------- disconnect ----------

test('a disconnected run finishes at the last confirmed wave', () => {
  const s = session();
  for (let n = 1; n <= 4; n++) clearWave(s, n);
  const r = s.finishOnDisconnect();
  assert.equal(r.waveReached, 4, 'credit the last wave actually confirmed');
  assert.ok(s.isFinished());
});

test('the wave-5 payout boundary is reachable through honest play', () => {
  const s = session();
  for (let n = 1; n <= 5; n++) clearWave(s, n);
  s.handle({ t: 'died', wave: 5, score: 100 });
  assert.equal(s.finish().waveReached, 5, 'wave 5 is the first winning tier');
});
