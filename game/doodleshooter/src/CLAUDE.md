# Module map

Import order roughly follows dependency order: `util` and `render` are leaves, `main` is the root.

| File | Lines | Responsibility |
| --- | --- | --- |
| `main.js` | ~830 | Bootstrap and game loop. Solo waves, lobbies, checkpoints, scoring, screens. |
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
| `util.js` | ~90 | Shared math helpers **and the seeded PRNG**. |

## Randomness

All gameplay randomness goes through `rand`, `randInt` and `choose` in `util.js`, which are
backed by a seeded PRNG (mulberry32, seeded by folding a hex seed with FNV-1a). Call
`setSeed(hexString)` at run start to make a run reproducible; the seed comes from the on-chain
`RunStarted` event once staking lands.

**Never call `Math.random()` directly for anything that affects gameplay.** Purely cosmetic
jitter — particle scatter, audio detune — may use it, and is marked with a comment where it does.

## Context object

`main.js` builds a single `ctx` object threaded through every system:
`{ scene, camera, world, level, nav, input, hud, effects, audio, renderer, game, player, enemies }`.
`window.__game` exposes it for debugging in the browser console — handy for `__game.begin()`,
`__game.jumpToWave(10)` and inspecting `__game.game.pendingSeed`.

## Naming

Canonical English names come from the project README: Doodle District, Doodle Mexico, The Doodler,
The Eraser, The Inkblot, Grunt, Rusher, Bomber, Sniper, Flyer, Heavy, Shield bearer, and the
rifle / shotgun / sniper / katana loadout. If code and README disagree, the README wins.
