# Doodle District — Inkstake Arena

A first-person survival shooter drawn in blue ballpoint on lined notebook paper, with an
on-chain staking and reward layer on Creditcoin, and cross-chain entry proven trustlessly
by the Attestcoin Protocol.

Built for BUIDL CTC 2026 Fall — Gaming track.

| Directory | Contents |
| --- | --- |
| `game/doodleshooter/` | The game. Static site, no build step. |
| `contracts/` | Foundry project: Creditcoin and Sepolia contracts. |
| `server/` | `ink-monitor` — run monitor and Attestcoin relayer. |
| `docs/` | Design, plans, and the Attestcoin integration document. |

## Running the game locally

```bash
cd game/doodleshooter && python3 serve.py 8910
```

Then open http://127.0.0.1:8910

## Status

Phase 1 (solo vs bots, staked, monitored) is in progress. Online multiplayer is Phase 2 and
is deliberately gated off — see `CLAUDE.md`.
