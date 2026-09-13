# Inkstake Arena — Plan 1: Game Foundation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the existing Chinese-language game into a fully English, deterministically seedable, single-monorepo codebase with AI context files — with no on-chain code yet.

**Architecture:** Three independent slices. First, collapse three separate git repositories into one monorepo and write the `CLAUDE.md` context files that encode the phase gate. Second, replace every Chinese string with English in place — no i18n table, no translation library, because the project's own README already contains every canonical name. Third, route all gameplay randomness through a seeded PRNG in `util.js`, where 243 of the game's random calls already funnel.

**Tech Stack:** Vanilla ES modules, three.js (vendored), no build step, no package manager in the game. Tests use `node --test` (built into Node 24, zero dependencies).

**Spec:** `docs/brainstorms/2026-09-13-inkstake-arena-design.md`

## Global Constraints

- **Zero build step.** The game must remain deployable as a static folder. Never add a bundler, transpiler, or `package.json` to `game/doodleshooter/`.
- **Zero runtime dependencies** beyond what is vendored in `game/doodleshooter/vendor/`. New libraries are vendored as ESM, exactly as `three.js` and `peerjs` already are.
- **All code, comments and identifiers in English.** No exceptions.
- **Phase gate.** Do not modify `src/net.js`, `src/players.js`, or any free-for-all code path beyond mechanical string translation. Online multiplayer is Phase 2.
- **Node 24** is available; use `node --test`, never add a test framework.
- Canonical English names come from `game/doodleshooter/README.md`. Do not invent new ones.

---

### Task 1: Collapse three repositories into one monorepo

Today `riguwagame/` has zero commits, while `contracts/` and `game/doodleshooter/` each carry their own `.git`. The hackathon requires one GitHub repository URL with a README. Nested repositories would appear empty to a reviewer who clones normally.

**Files:**
- Delete: `contracts/.git`, `game/doodleshooter/.git`
- Create: `.gitignore`, `README.md`
- Verify: `contracts/.gitmodules` still resolves after the parent `.git` is gone

- [ ] **Step 1: Record what the child repositories contain, so nothing is lost silently**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git -C contracts log --oneline | head -20 > /tmp/contracts-history.txt 2>/dev/null || echo "(no commits)" > /tmp/contracts-history.txt
git -C game/doodleshooter log --oneline | head -20 > /tmp/game-history.txt 2>/dev/null || echo "(no commits)" > /tmp/game-history.txt
cat /tmp/contracts-history.txt /tmp/game-history.txt
```

Expected: a short list, or "(no commits)". Read it before continuing. If either history is substantial and worth keeping, stop and ask the project owner before deleting.

- [ ] **Step 2: Preserve the submodule pins, then remove the child git directories**

`contracts/lib/*` are git submodules of the `contracts` repository. Once `contracts/.git` is deleted they become plain directories, which is what we want — the dependency source is then committed directly and a reviewer needs no `--recursive` clone.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat contracts/.gitmodules
rm -rf contracts/.git contracts/.gitmodules
find contracts/lib -maxdepth 2 -name '.git' -exec rm -rf {} + 2>/dev/null
rm -rf game/doodleshooter/.git
find . -maxdepth 3 -name '.git' -not -path './.git' -print
```

Expected: the final `find` prints nothing.

- [ ] **Step 3: Write the root `.gitignore`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > .gitignore <<'EOF'
.DS_Store

# Foundry
contracts/out/
contracts/cache/
contracts/broadcast/*/31337/
contracts/broadcast/**/dry-run/

# Secrets — never commit
.env
.env.*
!.env.example

# Node
node_modules/
server/dist/
EOF
```

- [ ] **Step 4: Confirm no secret is about to be committed**

`contracts/.env` holds a real private key. It must stay ignored.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add -A
git status --short | grep -E '\.env$' && echo "STOP: .env is staged" || echo "OK: no .env staged"
git ls-files | grep -c . 
```

Expected: `OK: no .env staged`. If it prints `STOP`, fix `.gitignore` and run `git rm --cached contracts/.env` before continuing.

- [ ] **Step 5: Write a placeholder root README that Task 2 and Plan 3 will expand**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > README.md <<'EOF'
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
EOF
```

- [ ] **Step 6: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add -A
git commit -m "chore: collapse contracts and game into a single monorepo"
git log --oneline
```

Expected: one commit listed.

---

### Task 2: Write the CLAUDE.md context files

These files are how any AI agent — and any new human contributor — gets oriented. The root file carries the phase gate as a hard rule.

**Files:**
- Create: `CLAUDE.md`
- Create: `contracts/CLAUDE.md`
- Create: `game/doodleshooter/CLAUDE.md`
- Create: `game/doodleshooter/src/CLAUDE.md`

`server/CLAUDE.md` is created in Plan 3, when that directory first exists.

- [ ] **Step 1: Write the root `CLAUDE.md`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > CLAUDE.md <<'EOF'
# Doodle District — Inkstake Arena

A browser FPS with an on-chain staking layer on Creditcoin, using the Attestcoin Protocol for
trustless cross-chain entry and prize funding. Hackathon submission: BUIDL CTC 2026 Fall,
Gaming track.

## Layout

| Path | What it is |
| --- | --- |
| `game/doodleshooter/` | The game. Vanilla ES modules, three.js vendored, **no build step**. |
| `contracts/` | Foundry. Four UUPS contracts on Creditcoin, one plain contract on Sepolia. |
| `server/` | `ink-monitor`: watches runs over WebSocket, signs results, relays Attestcoin proofs. |
| `docs/` | `brainstorms/` design docs, `plans/` implementation plans. |

## Phase gate — read this before touching multiplayer

**Online / peer-to-peer multiplayer is deferred.** Do not modify `src/net.js`, `src/players.js`,
or any free-for-all code path in `src/main.js` beyond mechanical string translation.

The gate lifts only when offline bot mode works end to end: translated to English, seeded from
an on-chain seed, staked, monitored by `ink-monitor`, settled on-chain, and paid out. When that
is verified working, **edit this section explicitly** to record that the gate is lifted, then
begin Phase 2.

The online code is left intact and gated off, not deleted. It is Phase 2 material.

## Hard rules

- **All code, comments, identifiers and documentation in English.** The game originally shipped
  with Chinese UI strings; these have been translated. Do not reintroduce any.
- **Never add a build step or package manager to `game/doodleshooter/`.** It must stay a static
  folder. New libraries are vendored as ESM into `vendor/`, exactly as three.js and peerjs are.
- **Never commit `.env`.** `contracts/.env` holds a live private key and is gitignored.
- **Contracts are UUPS-upgradeable and must be verified on Blockscout.** Non-negotiable.
- **Tests before implementation.** Contracts use Foundry; the game and server use `node --test`.

## Key facts

| Thing | Value |
| --- | --- |
| Creditcoin Testnet chain id | `102031` |
| Creditcoin RPC | `https://rpc.cc3-testnet.creditcoin.network` |
| Blockscout | `https://creditcoin-testnet.blockscout.com` |
| BlockProver precompile | `0x0000000000000000000000000000000000000FD2` |
| ChainInfo precompile | `0x0000000000000000000000000000000000000FD3` |
| Proof Builder API | `https://prover.cc3-testnet.creditcoin.network` |
| Ethereum Sepolia source chainKey | `1` (**not** `11155111`) |
| Native token | tCTC |

## Documents

Read `docs/brainstorms/2026-09-13-inkstake-arena-design.md` before making architectural changes.
It records why the trust model, the phase split and the pool-solvency design are what they are.
EOF
```

- [ ] **Step 2: Write `game/doodleshooter/CLAUDE.md`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > game/doodleshooter/CLAUDE.md <<'EOF'
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

## Constraints that must not be broken

- **No build step. No package.json. No bundler.** This is the defining property of the project.
- **No runtime dependencies** beyond `vendor/`. Import maps in `index.html` wire them up.
- **English only** in all strings, comments and identifiers.
- Online multiplayer is gated — see the root `CLAUDE.md`.

## How the look works

The scene renders into a buffer holding shade, an ink id and view-space normals plus float depth.
A post pass draws outlines from an inverse-depth Laplacian, adds surface-following hatching, paper
grain, ruled lines and the red margin. Wobble is static so nothing flickers.

## Modes

- **Solo** — survive waves. A boss every fifth wave. Checkpoints unlock at waves 5, 10, 15, …
  This is the only mode in Phase 1.
- **Free for all** — up to ten players, first to 20 kills, ten-minute cap. Peer-to-peer over
  WebRTC (PeerJS); the host's browser keeps score. **Phase 2 — gated off.**

## Files

See `src/CLAUDE.md` for the module map.
EOF
```

- [ ] **Step 3: Write `game/doodleshooter/src/CLAUDE.md`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > game/doodleshooter/src/CLAUDE.md <<'EOF'
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
| `util.js` | ~70 | Shared math helpers **and the seeded PRNG**. |

## Randomness

All gameplay randomness goes through `rand`, `randInt` and `choose` in `util.js`, which are
backed by a seeded PRNG. Call `setSeed(hexString)` at run start to make a run reproducible;
the seed comes from the on-chain `RunStarted` event.

**Never call `Math.random()` directly for anything that affects gameplay.** Purely cosmetic
jitter — particle scatter, audio detune — may use it, and is marked with a comment where it does.

## Context object

`main.js` builds a single `ctx` object threaded through every system:
`{ scene, camera, world, level, nav, input, hud, effects, audio, renderer, game, player, enemies }`.
`window.__game` exposes it for debugging in the browser console.
EOF
```

- [ ] **Step 4: Write `contracts/CLAUDE.md`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > contracts/CLAUDE.md <<'EOF'
# Contracts

Foundry project. Four UUPS-upgradeable contracts on Creditcoin Testnet and one plain contract on
Ethereum Sepolia. OpenZeppelin v5.7.0 is vendored in `lib/`.

Contracts are implemented in Plan 2 — see `docs/plans/2026-09-13-plan-2-contracts.md`.

## Planned contracts

| Contract | Chain | Purpose |
| --- | --- | --- |
| `ArenaEscrow` | Creditcoin | Stakes, reward pool, solvency accounting, settlement. The core. |
| `USDT` | Creditcoin | Mock test stablecoin, 6 decimals. Testnet only, no real value. |
| `SeasonRegistry` | Creditcoin | Per-season leaderboard: best wave, best score, runs, wins. |
| `DoodleGateASC` | Creditcoin | Attestcoin Smart Contract. Verifies Sepolia proofs, mints credits. |
| `DoodleGate` | Sepolia | Minimal. Emits `ArenaEntryPaid` and `PrizePoolFunded`. |

## Rules

- **UUPS on every Creditcoin contract**, ERC-7201 namespaced storage, verified on Blockscout.
- **Test first.** Write the failing test, watch it fail, then implement.
- **Never commit `.env`.** It holds a live deployer key.
- `evm_version = "shanghai"` and `via_ir = true` — Creditcoin's EVM, and several contracts hit
  stack-too-deep without IR.

## The two checks that carry the whole bridge

Inside `DoodleGateASC`, after the block-prover precompile returns:

1. `require(receipt.receiptStatus == 1)` — the precompile proves a transaction was **included**,
   not that it **succeeded**. Skipping this lets a reverted payment mint credits.
2. `require(log.address_ == sourceGate[chainKey])` — without this, anyone can deploy a contract
   on Sepolia emitting a byte-identical event and mint themselves unlimited credits.

Both have dedicated negative tests. Do not weaken either.

## Commands

```bash
forge build
forge test -vvv
forge coverage
forge fmt --check
forge test --fork-url https://rpc.cc3-testnet.creditcoin.network --match-path 'test/fork/*'
```
EOF
```

- [ ] **Step 5: Verify every file exists and is non-empty**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
for f in CLAUDE.md contracts/CLAUDE.md game/doodleshooter/CLAUDE.md game/doodleshooter/src/CLAUDE.md; do
  printf '%6s  %s\n' "$(wc -l < "$f")" "$f"
done
```

Expected: four files, each well over 20 lines.

- [ ] **Step 6: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add CLAUDE.md contracts/CLAUDE.md game/doodleshooter/CLAUDE.md game/doodleshooter/src/CLAUDE.md
git commit -m "docs: add CLAUDE.md context files with the phase gate"
```

---

### Task 3: Add an English-only guard test

Translation needs a mechanical check, or Chinese text creeps back in. This test runs before the translation exists, fails loudly, and then guards the codebase forever.

**Files:**
- Create: `game/doodleshooter/test/english-only.test.js`
- Create: `game/doodleshooter/test/README.md`

**Interfaces:**
- Produces: `test/english-only.test.js`, runnable via `node --test game/doodleshooter/test/`. Tasks 4–6 rely on it to prove the translation is complete.

- [ ] **Step 1: Write the failing test**

```bash
mkdir -p /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter/test
cat > /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter/test/english-only.test.js <<'EOF'
// Guards the "English only" rule. Scans every source file for CJK characters.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = join(dirname(fileURLToPath(import.meta.url)), '..');
// CJK ideographs, plus the full-width punctuation the original UI text used.
const CJK = /[　-〿㐀-䶿一-鿿！-｠]/u;

function sourceFiles(dir, out = []) {
  for (const name of readdirSync(dir)) {
    if (name === 'vendor' || name === 'node_modules' || name === 'test') continue;
    const p = join(dir, name);
    if (statSync(p).isDirectory()) sourceFiles(p, out);
    else if (/\.(js|html|css|md)$/.test(name)) out.push(p);
  }
  return out;
}

test('no CJK characters remain in game source', () => {
  const offenders = [];
  for (const file of sourceFiles(ROOT)) {
    const lines = readFileSync(file, 'utf8').split('\n');
    lines.forEach((line, i) => {
      if (CJK.test(line)) offenders.push(`${file.slice(ROOT.length + 1)}:${i + 1}`);
    });
  }
  assert.deepEqual(offenders, [], `CJK text found at:\n  ${offenders.join('\n  ')}`);
});

test('index.html declares English', () => {
  const html = readFileSync(join(ROOT, 'index.html'), 'utf8');
  assert.match(html, /<html lang="en">/, 'index.html must declare lang="en"');
  assert.match(html, /<title>Doodle District<\/title>/, 'title must be "Doodle District"');
});
EOF
cat > /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter/test/README.md <<'EOF'
# Game tests

Run with Node's built-in test runner — there is no test framework dependency:

```bash
node --test test/
```

`vendor/` and this directory are excluded from source scans.
EOF
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
node --test test/
```

Expected: FAIL. The first test lists roughly 150 offending locations across `main.js`, `hud.js`,
`weapons.js`, `player.js`, `enemies.js`, `level.js`, `net.js`. The second fails on `lang="zh-CN"`.
Save that offender list — it is the translation worklist for Tasks 4–6.

- [ ] **Step 3: Commit the guard**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add game/doodleshooter/test
git commit -m "test: add English-only guard for game source"
```

---

### Task 4: Translate `index.html`, `hud.js` and `weapons.js`

Start with the smallest, highest-visibility surfaces. Canonical names come from
`game/doodleshooter/README.md` — do not invent alternatives.

**Files:**
- Modify: `game/doodleshooter/index.html:2`, `:5`
- Modify: `game/doodleshooter/src/hud.js` (240 CJK characters)
- Modify: `game/doodleshooter/src/weapons.js:66-69`, `:254`

**Interfaces:**
- Consumes: `test/english-only.test.js` from Task 3.
- Produces: English `KB_KEYS`, `PAD_KEYS` and `CONTROLS_HTML` exports from `hud.js`, and English
  `name` / `hint` fields on every weapon spec. `main.js` reads all of these in Task 5.

- [ ] **Step 1: Translate `index.html`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
sed -i '' 's|<html lang="zh-CN">|<html lang="en">|' index.html
sed -i '' 's|<title>涂鸦街区</title>|<title>Doodle District</title>|' index.html
grep -nE 'lang=|<title>' index.html
```

Expected: `<html lang="en">` and `<title>Doodle District</title>`.

- [ ] **Step 2: Translate the HUD template strings in `hud.js`**

Apply these replacements. The left column is the exact existing text.

| Chinese | English |
| --- | --- |
| `太刀` | `Katana` |
| `拔刀就绪` | `Blade ready` |
| `分数` | `Score` |
| `波次` | `Wave` |
| `个敌人待消灭` | `enemies left` |
| `生命` | `Health` |
| `手雷` | `Grenades` |
| `步枪` | `Rifle` |
| `换弹中…` | `Reloading…` |
| `连击 x` | `Combo x` |

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 - <<'EOF'
import io
p = 'src/hud.js'
s = io.open(p, encoding='utf-8').read()
for a, b in [
    ('太刀', 'Katana'), ('拔刀就绪', 'Blade ready'), ('分数', 'Score'),
    ('波次', 'Wave'), ('个敌人待消灭', 'enemies left'), ('生命', 'Health'),
    ('手雷', 'Grenades'), ('步枪', 'Rifle'), ('换弹中…', 'Reloading…'),
    ('连击 x', 'Combo x'),
]:
    s = s.replace(a, b)
io.open(p, 'w', encoding='utf-8').write(s)
EOF
grep -n '[一-鿿]' src/hud.js | head -20
```

Expected: only `KB_KEYS.focus`, `KB_KEYS.next` and the `CONTROLS_HTML` block still show Chinese.
Those are handled in the next step.

- [ ] **Step 3: Translate the key labels and the controls table in `hud.js`**

Replace the `KB_KEYS` entries and the whole `CONTROLS_HTML` block. The English wording is taken
from the controls table already present in `README.md`.

```javascript
export const KB_KEYS = { fire: 'LMB', aim: 'RMB', block: 'RMB', jump: 'Space', sprint: 'Shift', slide: 'C', dash: 'C', grapple: 'Q', melee: 'F', reload: 'R', grenade: 'G', focus: 'both mouse buttons (or X)', next: 'wheel', pause: 'Esc', confirm: 'Space', score: 'Tab' };
export const PAD_KEYS = { fire: 'R2', aim: 'L2', block: 'L2', jump: '✕', sprint: 'L3', slide: '○', dash: '○', grapple: 'L1', melee: 'R1', reload: '□', grenade: 'R3', focus: 'L2 + R2', next: '△', pause: 'Options', confirm: '✕', score: 'Create' };
export const CONTROLS_HTML = `
<div class="cols">
  <div><div class="colhead">Mouse + keyboard</div>
    <div><b>WASD</b> move &nbsp; <b>Mouse</b> look &nbsp; <b>Shift</b> sprint</div>
    <div><b>LMB</b> fire / slash &nbsp; <b>RMB</b> aim / block</div>
    <div><b>Space</b> jump (again on a wall = wall jump)</div>
    <div><b>Space</b> again in the air = double jump</div>
    <div><b>C / Ctrl</b> slide on the ground · air dash</div>
    <div><b>Q / E</b> grapple: tap to swing, hold to reel, jump to launch</div>
    <div><b>F</b> quick katana slash &nbsp; <b>R</b> reload &nbsp; <b>M</b> music</div>
    <div><b>G</b> grenade · hold to throw further</div>
    <div><b>Tab</b> scoreboard (online) &nbsp; <b>Esc</b> pause</div>
    <div><b>Both mouse buttons</b> katana dash once the gauge is lit</div>
    <div><b>1-4 / wheel</b> rifle · shotgun · sniper · katana</div>
  </div>
  <div><div class="colhead">PS5 controller</div>
    <div><b>L stick</b> move &nbsp; <b>R stick</b> look &nbsp; <b>L3</b> sprint</div>
    <div><b>R2</b> fire / slash &nbsp; <b>L2</b> aim / block</div>
    <div><b>✕</b> jump &nbsp; <b>○</b> slide · air dash</div>
    <div><b>L1</b> grapple (hold to reel, ✕ to launch)</div>
    <div><b>L2 + R2</b> katana dash once the gauge is lit</div>
    <div><b>R1</b> quick katana slash, then back to your gun</div>
    <div><b>□</b> reload &nbsp; <b>△</b> next weapon</div>
    <div><b>R3 / d-pad up</b> grenade · hold to throw further</div>
    <div><b>Create</b> scoreboard (online) &nbsp; <b>Options</b> pause</div>
  </div>
</div>`;
```

- [ ] **Step 4: Translate the weapon names and hints in `weapons.js`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 - <<'EOF'
import io
p = 'src/weapons.js'
s = io.open(p, encoding='utf-8').read()
for a, b in [
    ("name: '步枪', hint: '全自动 · 让红点对准他们'",
     "name: 'Rifle', hint: 'Full auto · keep the dot on them'"),
    ("name: '霰弹枪', hint: '泵动 · 近距离威力惊人'",
     "name: 'Shotgun', hint: 'Pump action · devastating up close'"),
    ("name: '狙击枪', hint: '栓动狙击 · 一枪一个擦除'",
     "name: 'Sniper', hint: 'Bolt action · one shot, one erasure'"),
    ("name: '左轮手枪', hint: '手炮 · 爆头即擦除'",
     "name: 'Revolver', hint: 'Hand cannon · a headshot erases'"),
    ("this.name = '太刀'; this.hint = '挥砍 · 按住瞄准格挡并反弹子弹';",
     "this.name = 'Katana'; this.hint = 'Slash · hold aim to block and deflect bullets';"),
]:
    assert a in s, a
    s = s.replace(a, b)
io.open(p, 'w', encoding='utf-8').write(s)
print('ok')
EOF
grep -c '[一-鿿]' src/weapons.js
```

Expected: `0`.

- [ ] **Step 5: Run the guard test — it should still fail, but with a shorter list**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
node --test test/ 2>&1 | tail -30
```

Expected: the `index.html` test now PASSES. The CJK test still FAILS, but only with locations in
`main.js`, `player.js`, `enemies.js`, `level.js` and `net.js`.

- [ ] **Step 6: Load the game and confirm nothing broke visually**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 serve.py 8910 &
sleep 2 && curl -sf http://127.0.0.1:8910/src/hud.js > /dev/null && echo "serves OK"
```

Open http://127.0.0.1:8910 in a browser. The main menu still shows Chinese (that is `main.js`,
translated next), but the HUD labels and the controls table must be English, and the browser
console must show **no errors**. Stop the server with `kill %1` when done.

- [ ] **Step 7: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add game/doodleshooter/index.html game/doodleshooter/src/hud.js game/doodleshooter/src/weapons.js
git commit -m "i18n: translate index.html, HUD and weapon strings to English"
```

---

### Task 5: Translate `main.js`

The largest surface — 1,063 Chinese characters covering menus, lobby screens, wave messages, kill
feed labels and error text.

**Files:**
- Modify: `game/doodleshooter/src/main.js`

**Interfaces:**
- Consumes: English `hud.key()` labels and `CONTROLS_HTML` from Task 4.
- Produces: English `MODIFIERS[].name`, `enemyName()`, `HOW{}` and all screen HTML. Task 6 depends
  on none of it; Plan 3 attaches the staking UI to `mainHTML()` and `showDead()`.

- [ ] **Step 1: Translate the gameplay label groups**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 - <<'EOF'
import io
p = 'src/main.js'
s = io.open(p, encoding='utf-8').read()
pairs = [
    # default player name prefix
    ("'涂鸦' + Math.floor", "'doodle' + Math.floor"),
    # wave modifiers
    ("'咖啡因 · 移动更快'", "'Caffeine · they move faster'"),
    ("'重墨 · 打人更疼'", "'Heavy ink · they hit harder'"),
    ("'蜂群 · 数量更多、个体更脆'", "'Swarm · more of them, each frailer'"),
    ("mod.name.startsWith('蜂群')", "mod.name.startsWith('Swarm')"),
    # boss names
    ("{ boss: '涂鸦魔王', eraser: '橡皮魔王', inkblot: '墨渍魔王' }",
     "{ boss: 'The Doodler', eraser: 'The Eraser', inkblot: 'The Inkblot' }"),
    # kill feed labels
    ("label = '爆头'", "label = 'Headshot'"),
    ("label = over ? '一刀两断' : '斩落'", "label = over ? 'Cut in two' : 'Cut down'"),
    ("label = '处决'", "label = 'Execution'"),
    ("label = '原路奉还'", "label = 'Returned to sender'"),
    ("label = '坠出纸面'", "label = 'Fell off the page'"),
    ("label += ' · 空中击杀'", "label += ' · airborne kill'"),
    ("game.addScore(25, '皮纳塔')", "game.addScore(25, 'Pinata')"),
    # weapon names in the death feed
    ("{ rifle: '步枪', shotgun: '霰弹枪', sniper: '狙击枪', katana: '太刀', grenade: '手雷', deflect: '自己的子弹' }",
     "{ rifle: 'rifle', shotgun: 'shotgun', sniper: 'sniper', katana: 'katana', grenade: 'grenade', deflect: 'their own bullet' }"),
]
for a, b in pairs:
    assert a in s, 'not found: ' + a
    s = s.replace(a, b)
io.open(p, 'w', encoding='utf-8').write(s)
print('ok')
EOF
```

- [ ] **Step 2: Translate the wave, tip and message strings**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 - <<'EOF'
import io
p = 'src/main.js'
s = io.open(p, encoding='utf-8').read()
pairs = [
    ("`按住 <b>${hud.key('grapple')}</b> 收绳 · 摆动途中再按一次即可松手`",
     "`Hold <b>${hud.key('grapple')}</b> to reel in · press again mid-swing to let go`"),
    ("`用 <b>${hud.key('block')}</b> 格挡，部分子弹会反弹回去`",
     "`Block with <b>${hud.key('block')}</b> and some bullets go straight back`"),
    ("'空中击杀得分更高 · 尽量别落地'", "'Airborne kills score higher · try not to land'"),
    ("`<b>${hud.key('grenade')}</b> 掷出手雷 · 拾取物可补充手雷`",
     "`<b>${hud.key('grenade')}</b> throws a grenade · pickups restock them`"),
    ("`在空中再按一次 <b>${hud.key('jump')}</b> 可二段跳`",
     "`Press <b>${hud.key('jump')}</b> again in the air to double jump`"),
    ("hud.message('第 ' + n + ' 波', enemyName(bossFor(n)) + ' 正在逼近', 3)",
     "hud.message('Wave ' + n, enemyName(bossFor(n)) + ' is closing in', 3)"),
    ("hud.message('第 ' + n + ' 波', n === 1 ? '它们正从纸面外爬进来' : mod.name || choose(['画得更用力些', '继续涂涂画画', '别待在地面上', '挥刀上吧', '把子弹弹回去']), 2.6)",
     "hud.message('Wave ' + n, n === 1 ? 'They are crawling in from off the page' : mod.name || choose(['Press harder', 'Keep scribbling', 'Stay off the ground', 'Go in with the blade', 'Send the bullets back']), 2.6)"),
    ("hud.kill('检查点 · 第 ' + n + ' 波', 0)", "hud.kill('Checkpoint · wave ' + n, 0)"),
    ("hud.setTimer('下一波还有 ' + Math.ceil(game.intermission) + ' 秒')",
     "hud.setTimer('Next wave in ' + Math.ceil(game.intermission) + 's')"),
    ("hud.message('第 ' + game.wave + ' 波已清除', '喘口气 · +' + 200 * game.wave, 2.5)",
     "hud.message('Wave ' + game.wave + ' cleared', 'Catch your breath · +' + 200 * game.wave, 2.5)"),
    ("hud.tip('被弹回', 0.9)", "hud.tip('Deflected back', 0.9)"),
    ("hud.tip('被弹开', 0.7)", "hud.tip('Turned aside', 0.7)"),
    ("hud.tip('被格挡', 0.9)", "hud.tip('Parried', 0.9)"),
    ("hud.tip('绳索切断', 0.9)", "hud.tip('Rope cut', 0.9)"),
    ("hud.kill('+弹药 · +手雷', 0)", "hud.kill('+Ammo · +grenade', 0)"),
    ("level.key === 'mexico' ? '塔可 · +35 生命' : '+35 生命'",
     "level.key === 'mexico' ? 'Taco · +35 health' : '+35 health'"),
    ("hud.tip(`<b>斩击就绪</b> · 按住 ${hud.key('focus')} 冲刺`, 2.2)",
     "hud.tip(`<b>Slash ready</b> · hold ${hud.key('focus')} to dash`, 2.2)"),
    ("hud.tip('被挡下 · 冲刺没能命中', 1.2)", "hud.tip('Blocked · the dash missed', 1.2)"),
    ("hud.tip(musicWanted ? '音乐已开启' : '音乐已关闭', 1.5)",
     "hud.tip(musicWanted ? 'Music on' : 'Music off', 1.5)"),
    ("hud.tip('点击画面以锁定鼠标', 2)", "hud.tip('Click the view to lock the mouse', 2)"),
]
for a, b in pairs:
    assert a in s, 'not found: ' + a
    s = s.replace(a, b)
io.open(p, 'w', encoding='utf-8').write(s)
print('ok')
EOF
```

- [ ] **Step 3: Translate the remaining screens, lobby text and error messages**

Work through whatever the guard test still reports in `main.js`. Use this wording:

| Chinese | English |
| --- | --- |
| `涂鸦街区` (heading) | `Doodle District` |
| `一款涂鸦风生存射击游戏` | `A doodle-style survival shooter` |
| `开始游戏` / `单人 · 抵御一波波敌人` | `Play` / `Solo · hold off wave after wave` |
| `在线对战` / `自由混战 · 最多 10 名玩家` | `Play online` / `Free for all · up to 10 players` |
| `最高分：` | `Best score: ` |
| `检查点` / `第 N 波` | `Checkpoints` / `Wave N` |
| `地图` | `Map` |
| `鼠标灵敏度` | `Mouse sensitivity` |
| `反转垂直视角` | `Invert vertical look` |
| `音乐` | `Music` |
| `已暂停` / `菜单` | `Paused` / `Menu` |
| `主菜单` | `Main menu` |
| `被抹除` | `Erased` |
| `你撑过了` / `次击杀` / `得分` / `新纪录` | `You survived` / `kills` / `score` / `new record` |
| `点击（或按 X）再画一次` | `Click (or press X) to draw again` |
| `点击任意位置（或按 X）继续` | `Click anywhere (or press X) to resume` |

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
grep -n '[一-鿿]' src/main.js
```

Translate each remaining line by hand, then re-run the grep until it prints nothing.

- [ ] **Step 4: Verify `main.js` is clean**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
grep -c '[一-鿿]' src/main.js
node --check src/main.js && echo "syntax OK"
```

Expected: `0`, then `syntax OK`. `node --check` catches a quote broken during editing, which is
the most likely failure mode here.

- [ ] **Step 5: Play the game and confirm it still runs**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 serve.py 8910 &
sleep 2 && echo "open http://127.0.0.1:8910"
```

In the browser: start a solo run, survive into wave 2, take damage, get a kill, open the pause
menu, die. Every string must be English and the console must stay clean. `kill %1` when done.

- [ ] **Step 6: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add game/doodleshooter/src/main.js
git commit -m "i18n: translate main.js to English"
```

---

### Task 6: Translate the remaining files and turn the guard green

**Files:**
- Modify: `game/doodleshooter/src/player.js` (6 strings)
- Modify: `game/doodleshooter/src/enemies.js` (10 strings)
- Modify: `game/doodleshooter/src/level.js:11`
- Modify: `game/doodleshooter/src/net.js` (4 status strings)

`net.js` is gated for behavioural changes, but mechanical string translation is explicitly allowed
by the Global Constraints.

- [ ] **Step 1: Translate all four files**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 - <<'EOF'
import io
edits = {
 'src/player.js': [
   ("perfect ? '完美招架' : '格挡成功'", "perfect ? 'Perfect parry' : 'Blocked'"),
   ("this.ctx.game.addScore(40, '格挡成功')", "this.ctx.game.addScore(40, 'Blocked')"),
   ("ctx.hud.message('掉出纸面', '已在起点重新绘制', 1.8)",
    "ctx.hud.message('Off the page', 'Redrawn at the start', 1.8)"),
   ("ctx.hud.tip('喘不过气了 · 落地恢复体力', 1.4)",
    "ctx.hud.tip('Out of breath · land to recover', 1.4)"),
   ("this.ctx.hud.tip('抓钩需要缓口气', 0.9)", "this.ctx.hud.tip('The grapple needs a breath', 0.9)"),
   ("ctx.game.addScore(30, '拽翻')", "ctx.game.addScore(30, 'Yanked down')"),
 ],
 'src/enemies.js': [
   ("name: '小兵'", "name: 'Grunt'"),
   ("name: '冲锋怪'", "name: 'Rusher'"),
   ("name: '重装怪'", "name: 'Heavy'"),
   ("name: '狙击怪'", "name: 'Sniper'"),
   ("name: '盾牌怪'", "name: 'Shield bearer'"),
   ("name: '墨水炸弹'", "name: 'Ink bomb'"),
   ("name: '纸黄蜂'", "name: 'Paper wasp'"),
   ("name: '涂鸦魔王'", "name: 'The Doodler'"),
   ("name: '橡皮擦魔王'", "name: 'The Eraser'"),
   ("name: '墨渍魔王'", "name: 'The Inkblot'"),
   ("this.ctx.game.addScore(40, '护盾击碎')", "this.ctx.game.addScore(40, 'Shield broken')"),
 ],
 'src/level.js': [
   ("{ key: 'district', name: '涂鸦街区', blurb: '街道、屋顶与消防梯' }",
    "{ key: 'district', name: 'Doodle District', blurb: 'Streets, rooftops and fire escapes' }"),
   ("{ key: 'mexico', name: '涂鸦墨西哥', blurb: '阳光烘烤的广场 · 皮纳塔、塔可和马里亚奇乐队' }",
    "{ key: 'mexico', name: 'Doodle Mexico', blurb: 'A sun-baked plaza · pinatas, tacos and mariachis' }"),
 ],
 'src/net.js': [
   ("onStatus('正在寻找开放的大厅…')", "onStatus('Looking for an open lobby…')"),
   ("onStatus(`找到 ${offers.length} 个开放大厅…`)", "onStatus(`Found ${offers.length} open lobbies…`)"),
   ("onStatus(`找到 ${offers.length} 个…`)", "onStatus(`Found ${offers.length}…`)"),
 ],
}
for path, pairs in edits.items():
    s = io.open(path, encoding='utf-8').read()
    for a, b in pairs:
        assert a in s, f'{path}: not found: {a}'
        s = s.replace(a, b)
    io.open(path, 'w', encoding='utf-8').write(s)
    print('ok', path)
EOF
```

- [ ] **Step 2: Sweep for anything the scripted edits missed**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
grep -rn '[一-鿿]' src/ index.html style.css || echo "CLEAN"
```

Expected: `CLEAN`. If anything remains — a kick reason in `main.js`, say — translate it by hand
and re-run.

- [ ] **Step 3: Run the guard test and watch it pass**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
for f in src/*.js; do node --check "$f" || echo "SYNTAX ERROR: $f"; done
node --test test/
```

Expected: both tests PASS.

- [ ] **Step 4: Update the README's map and enemy names to match**

`README.md` already uses the canonical English names. Confirm nothing drifted:

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
grep -nE 'Doodle District|Doodle Mexico|The Doodler|The Eraser|The Inkblot' README.md | head
```

Expected: matches present. If a name in the code differs from the README, change the **code** to
match the README, not the other way around.

- [ ] **Step 5: Full playthrough**

Serve the game and play a solo run past wave 2 on both maps (`MEXICO_READY` is `false`, so only
Doodle District is selectable — that is expected). Check the main menu, map picker, settings,
pause menu, death screen and kill feed. All English, console clean.

- [ ] **Step 6: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add game/doodleshooter/src
git commit -m "i18n: translate remaining game source to English"
```

---

### Task 7: Route gameplay randomness through a seeded PRNG

`util.js` already funnels 243 random calls through `rand`, `randInt` and `choose`, so the
generator drops into one place. The seed will later come from the on-chain `RunStarted` event; for
now `setSeed` is simply available and defaults to a random seed so behaviour is unchanged.

**Files:**
- Modify: `game/doodleshooter/src/util.js:4-16`
- Create: `game/doodleshooter/test/prng.test.js`
- Modify: `game/doodleshooter/src/main.js` (call `setSeed` where a solo run begins)
- Audit: `src/enemies.js`, `src/player.js`, `src/level.js`, `src/nav.js`, `src/weapons.js`

**Interfaces:**
- Produces: `setSeed(seedHex: string): void` and `getSeed(): string` exported from `util.js`.
  Plan 3 calls `setSeed` with the seed from `RunStarted`. `ink-monitor` in Plan 3 reimplements the
  same generator to independently derive expected wave composition.

- [ ] **Step 1: Write the failing test**

```bash
cat > /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter/test/prng.test.js <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setSeed, getSeed, rand, randInt, choose } from '../src/util.js';

const SEED = '0x00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

function sequence(seed, n = 64) {
  setSeed(seed);
  return Array.from({ length: n }, () => rand());
}

test('the same seed produces the same sequence', () => {
  assert.deepEqual(sequence(SEED), sequence(SEED));
});

test('different seeds produce different sequences', () => {
  const other = '0x' + 'ab'.repeat(32);
  assert.notDeepEqual(sequence(SEED), sequence(other));
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
  const v = rand();
  assert.ok(v >= 0 && v < 1);
});
EOF
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
node --test test/prng.test.js
```

Expected: FAIL — `setSeed` and `getSeed` are not exported from `util.js`.

- [ ] **Step 3: Implement the seeded generator in `util.js`**

Replace the four random helpers at the top of `util.js`. `rand`, `randInt` and `choose` keep their
exact existing signatures, so the 243 call sites need no changes at all.

```javascript
// ---------------- seeded randomness ----------------
// All gameplay randomness goes through here. A run's seed comes from the chain, which makes the
// run reproducible and lets the monitor derive independently what should have spawned.
// mulberry32: small, fast, and good enough for a game.
let _seed = '';
let _state = (Math.random() * 0x100000000) >>> 0;   // unseeded default: behaves as before

function _mulberry32() {
  _state = (_state + 0x6d2b79f5) >>> 0;
  let t = _state;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
}

// Folds a 32-byte hex seed down to the generator's 32-bit state.
export function setSeed(seedHex) {
  _seed = String(seedHex);
  const hex = _seed.replace(/^0x/i, '');
  let h = 0x811c9dc5 >>> 0;                          // FNV-1a offset basis
  for (let i = 0; i < hex.length; i++) {
    h ^= hex.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  _state = h >>> 0;
}

export function getSeed() { return _seed; }

export const random = () => _mulberry32();
export const rand = (a = 0, b = 1) => a + _mulberry32() * (b - a);
export const randInt = (a, b) => Math.floor(rand(a, b + 1));
export const choose = (arr) => arr[Math.floor(_mulberry32() * arr.length)];
```

Leave `TAU`, `clamp`, `lerp`, `damp`, `smoothstep`, `approach`, `wrapAngle`, `angleLerp`,
`randDir`, `v3`, `Spring`, `Spring3`, `Cooldown`, `quatFromYTo` and `alignYAxis` exactly as they
are. Note that `randDir` already calls `rand`, so it becomes seeded for free.

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
node --test test/prng.test.js
```

Expected: all seven tests PASS.

- [ ] **Step 5: Replace direct `Math.random()` in gameplay paths**

56 direct calls exist. Leave alone those in `players.js` and `net.js` (Phase 2, gated) and those
that are purely cosmetic. Replace the rest with the seeded `random()`.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
grep -n 'Math\.random()' src/main.js src/enemies.js src/player.js src/level.js src/nav.js src/weapons.js src/effects.js
```

For each hit, decide and act:

- **Affects gameplay** — wave composition in `startWave`, spawn selection in `pickSpawn`, enemy AI
  rolls, pickup drop rolls, level prop placement: import `random` from `./util.js` and replace
  `Math.random()` with `random()`.
- **Purely cosmetic** — particle scatter in `effects.js`, audio detune in `audio.js`: leave it, and
  add a trailing comment `// cosmetic: intentionally unseeded`.

Handle the one wall-clock dependency too:

```bash
sed -n '429,433p' src/enemies.js
```

Line 431 reads `const now = performance.now() / 1000`. Replace it with the accumulated game clock
so enemy behaviour does not depend on when the tab was opened:

```javascript
const now = this.ctx.game.time, P = this.ctx.player;
```

- [ ] **Step 6: Seed each solo run in `main.js`**

Import `setSeed` and seed at the start of a run. Until Plan 3 supplies an on-chain seed, derive a
random one so behaviour matches today.

In the import block at the top of `main.js`:

```javascript
import { rand, choose, clamp, setSeed } from './util.js';
```

Then in `beginCommon()`, before the run starts:

```javascript
function beginCommon() {
  // A staked run overrides this with the seed from the chain (see src/chain/arena.js).
  if (!game.pendingSeed) game.pendingSeed = '0x' + Array.from({ length: 32 }, () => Math.floor(Math.random() * 256).toString(16).padStart(2, '0')).join('');
  setSeed(game.pendingSeed);
  audio.init(); audio.resume(); if (!input.usingGamepad) input.requestLock();
  if (musicWanted && !audio.musicPlaying) audio.musicOn(true);
  hud.hideScreen(); hud.setGameplayVisible(true); game.menu = false;
}
```

And clear it when a run ends, in `resetGame()`:

```javascript
game.pendingSeed = null;
```

- [ ] **Step 7: Verify determinism end to end**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
for f in src/*.js; do node --check "$f" || echo "SYNTAX ERROR: $f"; done
node --test test/
```

Expected: every test PASSES.

Then in the browser, open the console and run the same seed twice:

```javascript
__game.game.pendingSeed = '0x' + 'ab'.repeat(32); __game.begin();
// note the wave 1 enemy mix and the modifier shown, then:
__game.game.pendingSeed = '0x' + 'ab'.repeat(32); __game.beginAtWave(1);
```

Expected: the same modifier and the same enemy composition both times.

- [ ] **Step 8: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add game/doodleshooter/src game/doodleshooter/test
git commit -m "feat: route gameplay randomness through a seeded PRNG"
```

---

### Task 8: Wire the game tests into CI

**Files:**
- Create: `.github/workflows/game.yml`

- [ ] **Step 1: Write the workflow**

```bash
mkdir -p /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/.github/workflows
cat > /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/.github/workflows/game.yml <<'EOF'
name: Game

permissions: {}

on:
  push:
  pull_request:
  workflow_dispatch:

jobs:
  test:
    name: Game tests
    runs-on: ubuntu-latest
    permissions:
      contents: read
    steps:
      - uses: actions/checkout@v6
        with:
          persist-credentials: false

      - uses: actions/setup-node@v4
        with:
          node-version: '24'

      - name: Syntax check every module
        working-directory: game/doodleshooter
        run: for f in src/*.js; do node --check "$f"; done

      - name: Run tests
        working-directory: game/doodleshooter
        run: node --test test/
EOF
```

- [ ] **Step 2: Run the same commands locally to confirm CI will pass**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
for f in src/*.js; do node --check "$f"; done && node --test test/
```

Expected: all tests PASS.

- [ ] **Step 3: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add .github/workflows/game.yml
git commit -m "ci: run game syntax checks and tests"
```

---

## Done when

- `node --test test/` passes: no CJK anywhere, `index.html` declares English, PRNG is deterministic.
- A solo run plays start to finish with every string in English and a clean console.
- The same seed reproduces the same wave composition.
- One git repository, one commit history, no nested `.git`, no `.env` tracked.
- `CLAUDE.md` exists at the root and in `contracts/`, `game/doodleshooter/` and
  `game/doodleshooter/src/`, and the root file states the phase gate.

**Next:** `docs/plans/2026-09-13-plan-2-contracts.md`
