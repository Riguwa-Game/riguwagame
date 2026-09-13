import { maxEnemiesInWave, minSecondsForWave } from './waves.ts';
import type { RunResult } from '../signer.ts';
import type { Hex } from 'viem';

export class SessionError extends Error {}

export type ClientEvent =
  | { t: 'wave'; n: number }
  | { t: 'kill'; wave: number; enemy: string }
  | { t: 'damage'; wave: number; amount: number }
  | { t: 'died'; wave: number; score: number }
  | { t: 'ping' };

type Options = {
  runId: Hex;
  player: Hex;
  seed: Hex;
  startedAt: number;
};

/// One run. Tracks progress and refuses anything the game's own wave formula says is impossible.
export class RunSession {
  readonly runId: Hex;
  readonly player: Hex;
  readonly seed: Hex;

  private wave = 0;
  private score = 0;
  private dead = false;
  private waveStartedAt: number;
  private kills = new Map<number, number>();
  private clockValue: number;

  constructor(opts: Options) {
    this.runId = opts.runId;
    this.player = opts.player;
    this.seed = opts.seed;
    this.clockValue = opts.startedAt;
    this.waveStartedAt = opts.startedAt;
  }

  clock(): number {
    return this.clockValue;
  }

  setClock(t: number): void {
    this.clockValue = t;
  }

  waveReached(): number {
    return this.wave;
  }

  killsInWave(n: number): number {
    return this.kills.get(n) ?? 0;
  }

  isFinished(): boolean {
    return this.dead;
  }

  handle(ev: ClientEvent): void {
    if (this.dead && ev.t !== 'ping') throw new SessionError('the run already ended');

    switch (ev.t) {
      case 'ping':
        return;

      case 'wave': {
        if (!Number.isInteger(ev.n)) throw new SessionError('wave must be an integer');
        if (ev.n !== this.wave + 1) {
          throw new SessionError(`wave ${ev.n} does not follow wave ${this.wave}`);
        }
        if (this.wave > 0) {
          const elapsed = this.clockValue - this.waveStartedAt;
          const floor = minSecondsForWave(this.wave);
          if (elapsed < floor) {
            throw new SessionError(
              `wave ${this.wave} cleared in ${elapsed.toFixed(1)}s, floor is ${floor.toFixed(1)}s`,
            );
          }
        }
        this.wave = ev.n;
        this.waveStartedAt = this.clockValue;
        return;
      }

      case 'kill': {
        if (ev.wave !== this.wave) {
          throw new SessionError(`kill reported for wave ${ev.wave}, current wave is ${this.wave}`);
        }
        const next = this.killsInWave(ev.wave) + 1;
        const cap = maxEnemiesInWave(ev.wave);
        if (next > cap) {
          throw new SessionError(`wave ${ev.wave} can spawn at most ${cap} enemies, saw ${next}`);
        }
        this.kills.set(ev.wave, next);
        return;
      }

      case 'damage':
        return;

      case 'died': {
        if (ev.wave > this.wave) {
          throw new SessionError(`died on wave ${ev.wave} but only reached wave ${this.wave}`);
        }
        if (!Number.isFinite(ev.score) || ev.score < 0) {
          throw new SessionError('score must be a non-negative number');
        }
        this.score = Math.floor(ev.score);
        this.dead = true;
        return;
      }

      default:
        throw new SessionError('unknown event');
    }
  }

  finish(): RunResult {
    return {
      runId: this.runId,
      player: this.player,
      waveReached: this.wave,
      score: BigInt(this.score),
      endedAt: BigInt(Math.floor(this.clockValue)),
    };
  }

  /// The client vanished. Credit what was actually confirmed, nothing more.
  finishOnDisconnect(): RunResult {
    this.dead = true;
    return this.finish();
  }
}
