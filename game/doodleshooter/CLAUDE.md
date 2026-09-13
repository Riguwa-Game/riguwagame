# Doodle District — the game

A first-person survival shooter rendered entirely in code. There are no models, textures or
sound files: the paper, the ink outlines, the hatching, the enemies and the 8-bit music are all
procedural. Roughly 4,100 lines of JavaScript plus vendored three.js.

## Running it

```bash
python3 serve.py 8910     # then open http://127.0.0.1:8910
```

`serve.py` sends `Cache-Control: no-store` so edits show up on reload. Any static host works;
there is nothing to build.

## Tests

```bash
node --test
```

Node's built-in runner — there is no test framework dependency and there must not be one.
Test files are `.mjs`, because without a `package.json` Node would read a `.js` test as CommonJS.
Use bare `node --test`; `node --test test/` fails on Node 24.

## Constraints that must not be broken

- **No build step. No package.json. No bundler.** This is the defining property of the project.
- **No runtime dependencies** beyond `vendor/`. The import map in `index.html` wires them up.
- **English only** in all strings, comments and identifiers. `test/english-only.test.mjs` enforces it.
- Online multiplayer is gated — see the root `CLAUDE.md`.

## How the look works

The scene renders into a buffer holding shade, an ink id and view-space normals plus float depth.
A post pass draws outlines from an inverse-depth Laplacian, adds surface-following hatching, paper
grain, ruled lines and the red margin. Wobble is static so nothing flickers.

The UI font stack starts with the handwriting faces `Patrick Hand` and `Caveat` and falls back to
`Comic Sans MS` / `Marker Felt`. The look degrades gracefully when the webfonts are absent.

## Modes

- **Solo** — survive waves. A boss every fifth wave. Checkpoints unlock at waves 5, 10, 15, …
  This is the only mode in Phase 1.
- **Free for all** — up to ten players, first to 20 kills, ten-minute cap. Peer-to-peer over
  WebRTC (PeerJS); the host's browser keeps score. **Phase 2 — gated off.**

## Files

See `src/CLAUDE.md` for the module map, and `public/README.md` for asset provenance.
