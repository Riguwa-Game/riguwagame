# Doodle District — the game

A first-person survival shooter rendered entirely in code. No models, textures or sound files: the
paper, the ink outlines, the hatching, the enemies and the 8-bit music are all procedural. Roughly
4,100 lines of JavaScript plus vendored three.js and Reown AppKit.

## Running it

```bash
python3 serve.py 8910     # then open http://127.0.0.1:8910
```

`serve.py` sends `Cache-Control: no-store` so edits show up on reload. Any static host works; there
is nothing to build. The monitor must be running too — see the phase note below.

## Tests

```bash
node --test
```

Node's built-in runner; there is no test framework dependency and there must not be one. Test files
are `.mjs` because without a `package.json` Node reads a `.js` test as CommonJS. Use bare
`node --test`; `node --test test/` fails on Node 24.

## Constraints that must not be broken

- **No build step. No package.json. No bundler.** This is the defining property of the project.
  `tools/bundle-appkit.sh` pre-bundles AppKit *once, by hand*, into `vendor/` — that is an author
  tool, not a build the game requires.
- **No runtime dependencies** beyond `vendor/`. The import map in `index.html` wires them up.
- **English only** in strings, comments and identifiers. `test/english-only.test.mjs` enforces it.
- **Every run is staked.** `begin()` refuses without an active on-chain run. Do not add a free-play
  path, including for testing — use the console or a throwaway stake.
- Online multiplayer is gated — see the root `CLAUDE.md`.

## How the look works

The scene renders into a buffer holding shade, an ink id and view-space normals plus float depth. A
post pass draws outlines from an inverse-depth Laplacian, adds surface-following hatching, paper
grain, ruled lines and the red margin. Wobble is static so nothing flickers.

UI type is `Patrick Hand` / `Caveat` falling back to `Comic Sans MS` / `Marker Felt`, and every size
in the menu panel is `clamp()`ed against viewport height so the panel scales instead of spilling.
If you add a row to the menu, re-check that it still fits at ~900px of viewport height.

## Chain integration

`src/chain/` holds it: `config.js` (addresses, ABIs, Reown project id, monitor URL), `wallet.js`
(AppKit + `@wagmi/core`), `arena.js` (contract calls). `src/net/monitor.js` is the WebSocket client.

`config.js` reads `window.INKSTAKE_CONFIG` for deployment overrides, so the Reown project id and the
monitor URL can change without touching code. Off localhost the monitor URL defaults to
`wss://monitor.<domain>`, because a page served over https cannot open a `ws://` socket.

## Modes

- **Solo** — survive waves, boss every fifth. **Staked, and the only mode in Phase 1.**
- **Free for all** — up to ten players, peer-to-peer over WebRTC. **Phase 2, gated off.**

## Files

See `src/CLAUDE.md` for the module map, and `public/README.md` for asset provenance.
