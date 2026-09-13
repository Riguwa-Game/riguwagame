# Module map

Import order roughly follows dependency order: `prng` and `util` are leaves, `main` is the root.

| File | Lines | Responsibility |
| --- | --- | --- |
| `main.js` | ~900 | Bootstrap and game loop. Waves, screens, scoring, **the stake panel and settlement**. |
| `enemies.js` | ~800 | Enemy types, AI states, bosses, the enemy manager. |
| `level.js` | ~470 | Level construction. Merged ink geometry plus axis-aligned box colliders. |
| `player.js` | ~440 | First-person player: movement, grapple, camera feel, health, weapons. |
| `weapons.js` | ~370 | View models and firing logic: rifle, shotgun, sniper, revolver, katana. |
| `audio.js` | ~320 | Procedural WebAudio effects and per-map 8-bit music. No sound files. |
| `effects.js` | ~320 | Particles, decals, rigid gibs, tracers. |
| `render.js` | ~270 | The ink renderer and the pen-on-paper post pass. |
| `net.js` | ~220 | Peer-to-peer WebRTC over PeerJS. **Phase 2 — gated.** |
| `physics.js` | ~170 | Axis-aligned box world, spatial hash, swept movement, raycasts. |
| `players.js` | ~160 | Remote players in a match. **Phase 2 — gated.** |
| `input.js` | ~140 | Unified keyboard/mouse and gamepad input. |
| `hud.js` | ~120 | DOM heads-up display, drawn in pen style over the canvas. |
| `nav.js` | ~115 | Navigation grid generated from the collision world. |
| `util.js` | ~70 | Shared math helpers. Re-exports the PRNG. |
| `prng.js` | ~35 | **Seeded randomness. Zero dependencies on purpose.** |
| `chain/config.js` | ~110 | Addresses, ABIs, chain params, Reown id, monitor URL, deployment overrides. |
| `chain/wallet.js` | ~70 | Reown AppKit + `@wagmi/core`. `createAppKit` runs once at module scope. |
| `chain/arena.js` | ~160 | Contract calls, balance/pool reads, decoded contract errors. |
| `net/monitor.js` | ~65 | WebSocket client for ink-monitor. |

## Randomness

All gameplay randomness goes through `rand`, `randInt`, `choose` and `random`, which live in
**`prng.js`** — dependency-free so it can be unit tested under Node and mirrored by the server.
`util.js` re-exports them, so the 243 existing call sites are untouched. `util.js` itself imports
three.js, which is why the PRNG cannot live there.

`setSeed(hexString)` makes a run reproducible. A staked run takes its seed from the on-chain
`RunStarted` event via `game.pendingSeed`.

**Never call `Math.random()` directly for anything that affects gameplay.** Purely cosmetic jitter —
particle scatter, camera shake, audio detune, the default player name — may, and does.

## Context object

`main.js` builds a single `ctx` threaded through every system:
`{ scene, camera, world, level, nav, input, hud, effects, audio, renderer, game, player, enemies }`.
`window.__game` exposes it for debugging — but `begin()` still refuses without an active stake, so
the console is not a free-play door either.

## Naming

Canonical English names come from the project README: Doodle District, Doodle Mexico, The Doodler,
The Eraser, The Inkblot, Grunt, Rusher, Bomber, Sniper, Flyer, Heavy, Shield bearer, and the
rifle / shotgun / sniper / katana loadout. If code and README disagree, the README wins.
