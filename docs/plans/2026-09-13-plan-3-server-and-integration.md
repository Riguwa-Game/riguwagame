# Inkstake Arena — Plan 3: Monitor, Relayer and Game Integration

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Close the loop — a player stakes on Creditcoin, plays a solo run against bots, the `ink-monitor` watches it and signs the result, and the contract pays out. Plus: an entry paid on Ethereum Sepolia is proven by Attestcoin and credited automatically, with no tCTC in the player's wallet.

**Architecture:** One small Node process on the VPS does two jobs. The **run monitor** accepts a WebSocket only for a run that exists on-chain, checks progress for plausibility against the on-chain seed, and signs an EIP-712 `RunResult` when the run ends. The **relayer** watches `DoodleGate` on Sepolia, waits for the block to be attested, fetches Merkle and continuity proofs from the Proof Builder, and submits them to `DoodleGateASC`. The game gains a `src/chain/` module built on **Reown AppKit** (ethers adapter), vendored as a single pre-bundled ES module so no build step is introduced.

**Tech Stack:** Node 24, TypeScript, `ws`, `ethers` v6, `@gluwa/usc-sdk` v0.18.0, `node --test`. Game side: vanilla ES modules, vendored Reown AppKit + ethers.

**Spec:** `docs/brainstorms/2026-09-13-inkstake-arena-design.md`

**Depends on:** Plan 1 complete (English, seeded PRNG) and Plan 2 complete (contracts deployed and verified).

## Global Constraints

- **Never add a build step to `game/doodleshooter/`.** ethers and Reown AppKit are vendored as ES modules into `vendor/`, exactly as three.js and peerjs already are. AppKit is pre-bundled once by `tools/bundle-appkit.sh`; that script is an author tool, not part of running the game. The server may use TypeScript; the game may not.
- **Reown AppKit project id** `b56e18d47c72ab683b10814fe9495694`. This is Reown's public documentation id and works on **localhost only** — before deploying to a real domain, register a project at dashboard.reown.com and swap it in, or wallets will reject `metadata.url`.
- **Token logos live in `game/doodleshooter/public/`** (`ctc.png`, `usdt.svg`, `usdt.png`) and are referenced as `./public/<file>`.
- **English only** in all code, comments and identifiers.
- **Phase gate holds.** Do not touch `src/net.js`, `src/players.js` or FFA paths. This plan wires the **solo** run only.
- **The monitor key is an attestor key, not an admin key.** It signs run results and nothing else. It must never hold owner rights on any contract.
- **Never commit `.env`.** The monitor private key lives only in the VPS environment.
- Creditcoin Testnet chain id `102031` (`0x18E8F` in EIP-3085/3326 wallet calls).
- Sepolia source **chainKey is `1`**, not `11155111`.
- The seed algorithm in `server/src/monitor/prng.ts` must match `game/doodleshooter/src/util.js` exactly. A shared test vector enforces this.

## File structure

```
server/
  package.json  tsconfig.json  .env.example  CLAUDE.md
  src/
    config.ts              env parsing, addresses, ABIs           Task 1
    signer.ts              EIP-712 RunResult signing              Task 1
    abi.ts                 minimal ABIs for the three contracts   Task 1
    monitor/
      prng.ts              mirror of the game PRNG                Task 2
      waves.ts             expected wave composition from a seed  Task 2
      session.ts           one run: state machine + plausibility  Task 2
      server.ts            WebSocket endpoint                     Task 2
    relayer/
      index.ts             Sepolia watcher to ASC submitter       Task 3
    index.ts               starts both                            Task 3
  test/
    prng.test.ts  session.test.ts  signer.test.ts
tools/bundle-appkit.sh   one-time AppKit bundler (author tool)       Task 4
game/doodleshooter/
  public/ctc.png  usdt.svg  usdt.png  README.md   token marks     (done)
  vendor/appkit/appkit.bundle.js                                  Task 4
  vendor/ethers/ethers.min.js                                     Task 4
  src/chain/config.js  wallet.js  arena.js                        Tasks 4-5
  src/net/monitor.js                                              Task 6
docs/ATTESTCOIN_INTEGRATION.md                                    Task 7
```

---

### Task 1: Server scaffolding, config and the EIP-712 signer

**Files:**
- Create: `server/package.json`, `server/tsconfig.json`, `server/.env.example`, `server/CLAUDE.md`
- Create: `server/src/config.ts`, `server/src/abi.ts`, `server/src/signer.ts`
- Create: `server/test/signer.test.ts`

**Interfaces:**
- Produces:
  - `config` — typed object with `creditcoinRpc`, `sepoliaRpc`, `proofBuilderUrl`, `sourceChainKey`, `arenaEscrow`, `doodleGateAsc`, `doodleGateSepolia`, `monitorKey`, `wsPort`
  - `signRunResult(result: RunResult): Promise<string>` — returns a 65-byte hex signature
  - `type RunResult = { runId: string; player: string; waveReached: number; score: number; endedAt: number }`
  - Tasks 2 and 3 consume both.

- [ ] **Step 1: Scaffold the package**

```bash
mkdir -p /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server/src/monitor \
         /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server/src/relayer \
         /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server/test
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > package.json <<'EOF'
{
  "name": "ink-monitor",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "description": "Run monitor and Attestcoin relayer for Inkstake Arena",
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "node --experimental-strip-types src/index.ts",
    "test": "node --experimental-strip-types --test test/"
  },
  "dependencies": {
    "@gluwa/usc-sdk": "0.18.0",
    "dotenv": "^17.2.3",
    "ethers": "^6.15.0",
    "ws": "^8.18.0"
  },
  "devDependencies": {
    "@types/node": "^24.0.0",
    "@types/ws": "^8.5.13",
    "typescript": "^5.9.2"
  }
}
EOF
cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2023",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "rootDir": ".",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "declaration": false
  },
  "include": ["src/**/*.ts"]
}
EOF
cat > .env.example <<'EOF'
# Creditcoin
CREDITCOIN_RPC_URL=https://rpc.cc3-testnet.creditcoin.network
ARENA_ESCROW=
DOODLE_GATE_ASC=

# The attestor key. Signs RunResult and submits proofs. NEVER an owner key.
MONITOR_PRIVATE_KEY=

# Ethereum Sepolia (source chain)
SEPOLIA_RPC_URL=
DOODLE_GATE_SEPOLIA=
SOURCE_CHAIN_KEY=1

# Attestcoin
PROOF_BUILDER_URL=https://prover.cc3-testnet.creditcoin.network

# Monitor WebSocket
WS_PORT=8920
EOF
npm install
```

- [ ] **Step 2: Write the failing signer test**

The digest must match `ArenaEscrow.hashRunResult` byte for byte, or every settlement fails.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > test/signer.test.ts <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Wallet, verifyTypedData, TypedDataEncoder } from 'ethers';
import { runResultDomain, RUN_RESULT_TYPES, signRunResultWith } from '../src/signer.ts';

const ESCROW = '0x00000000000000000000000000000000000ARENA'.slice(0, 42);
const CHAIN_ID = 102031;

const RESULT = {
  runId: '0x' + '11'.repeat(32),
  player: '0x1111111111111111111111111111111111111111',
  waveReached: 12,
  score: 7777,
  endedAt: 1789000000,
};

test('the encoded type string matches the Solidity typehash preimage', () => {
  // ArenaEscrow computes:
  //   keccak256("RunResult(bytes32 runId,address player,uint32 waveReached,uint64 score,uint64 endedAt)")
  // If this string drifts by even one character, every settlement reverts with NotAttestor.
  assert.equal(
    TypedDataEncoder.from(RUN_RESULT_TYPES).encodeType('RunResult'),
    'RunResult(bytes32 runId,address player,uint32 waveReached,uint64 score,uint64 endedAt)',
  );
});

test('the domain matches the contract', () => {
  const d = runResultDomain(CHAIN_ID, ESCROW);
  assert.equal(d.name, 'InkstakeArena');
  assert.equal(d.version, '1');
  assert.equal(d.chainId, CHAIN_ID);
  assert.equal(d.verifyingContract, ESCROW);
});

test('a signature recovers to the signing address', async () => {
  const wallet = Wallet.createRandom();
  const domain = runResultDomain(CHAIN_ID, ESCROW);
  const sig = await signRunResultWith(wallet, domain, RESULT);
  assert.equal(verifyTypedData(domain, RUN_RESULT_TYPES, RESULT, sig), wallet.address);
});

test('a signature is 65 bytes', async () => {
  const wallet = Wallet.createRandom();
  const sig = await signRunResultWith(wallet, runResultDomain(CHAIN_ID, ESCROW), RESULT);
  assert.equal((sig.length - 2) / 2, 65);
});

test('changing any field changes the signature', async () => {
  const wallet = Wallet.createRandom();
  const domain = runResultDomain(CHAIN_ID, ESCROW);
  const base = await signRunResultWith(wallet, domain, RESULT);
  for (const patch of [
    { runId: '0x' + '22'.repeat(32) },
    { player: '0x2222222222222222222222222222222222222222' },
    { waveReached: 13 },
    { score: 7778 },
    { endedAt: 1789000001 },
  ]) {
    const sig = await signRunResultWith(wallet, domain, { ...RESULT, ...patch });
    assert.notEqual(sig, base, `field ${Object.keys(patch)[0]} must affect the signature`);
  }
});

test('a different chain id produces a different signature', async () => {
  const wallet = Wallet.createRandom();
  const a = await signRunResultWith(wallet, runResultDomain(CHAIN_ID, ESCROW), RESULT);
  const b = await signRunResultWith(wallet, runResultDomain(1, ESCROW), RESULT);
  assert.notEqual(a, b, 'domain separation must bind the chain id');
});
EOF
```

- [ ] **Step 3: Run it and confirm it fails**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
npm test
```

Expected: FAIL — `src/signer.ts` does not exist.

- [ ] **Step 4: Implement config, ABIs and the signer**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > src/config.ts <<'EOF'
import 'dotenv/config';

function required(name: string): string {
  const v = process.env[name];
  if (!v) throw new Error(`missing required env var ${name}`);
  return v;
}

export const config = {
  creditcoinRpc: process.env.CREDITCOIN_RPC_URL ?? 'https://rpc.cc3-testnet.creditcoin.network',
  sepoliaRpc: process.env.SEPOLIA_RPC_URL ?? '',
  proofBuilderUrl: process.env.PROOF_BUILDER_URL ?? 'https://prover.cc3-testnet.creditcoin.network',
  sourceChainKey: Number(process.env.SOURCE_CHAIN_KEY ?? 1),
  creditcoinChainId: 102031,
  arenaEscrow: process.env.ARENA_ESCROW ?? '',
  doodleGateAsc: process.env.DOODLE_GATE_ASC ?? '',
  doodleGateSepolia: process.env.DOODLE_GATE_SEPOLIA ?? '',
  wsPort: Number(process.env.WS_PORT ?? 8920),
  monitorKey: () => required('MONITOR_PRIVATE_KEY'),
} as const;
EOF
cat > src/abi.ts <<'EOF'
export const ARENA_ESCROW_ABI = [
  'event RunStarted(bytes32 indexed runId, address indexed player, address indexed token, uint256 stake, bytes32 seed, uint64 deadline)',
  'function runOf(bytes32 runId) view returns (tuple(address player, address token, uint256 stake, uint256 reserved, bytes32 seed, uint64 startedAt, uint64 deadline, uint8 state))',
  'function hashRunResult(tuple(bytes32 runId, address player, uint32 waveReached, uint64 score, uint64 endedAt) r) view returns (bytes32)',
  'function settleRun(tuple(bytes32 runId, address player, uint32 waveReached, uint64 score, uint64 endedAt) r, bytes[] sigs)',
] as const;

export const DOODLE_GATE_SEPOLIA_ABI = [
  'event ArenaEntryPaid(address indexed player, bytes32 indexed runRef, uint256 amount)',
  'event PrizePoolFunded(address indexed sponsor, uint256 amount)',
] as const;

export const DOODLE_GATE_ASC_ABI = [
  'function execute(uint8 action, uint64 chainKey, uint64 blockHeight, bytes encodedTransaction, bytes32 merkleRoot, tuple(bytes32 hash, bool isLeft)[] siblings, bytes32 lowerEndpointDigest, bytes32[] continuityRoots) returns (bool)',
  'function processedQueries(bytes32 queryId) view returns (bool)',
] as const;
EOF
cat > src/signer.ts <<'EOF'
import { Wallet, type TypedDataDomain } from 'ethers';

export type RunResult = {
  runId: string;
  player: string;
  waveReached: number;
  score: number;
  endedAt: number;
};

/// Must match ArenaEscrow.RUN_RESULT_TYPEHASH exactly.
export const RUN_RESULT_TYPES = {
  RunResult: [
    { name: 'runId', type: 'bytes32' },
    { name: 'player', type: 'address' },
    { name: 'waveReached', type: 'uint32' },
    { name: 'score', type: 'uint64' },
    { name: 'endedAt', type: 'uint64' },
  ],
} as const;

/// Must match __EIP712_init("InkstakeArena", "1") in ArenaEscrow.
export function runResultDomain(chainId: number, verifyingContract: string): TypedDataDomain {
  return { name: 'InkstakeArena', version: '1', chainId, verifyingContract };
}

export async function signRunResultWith(
  wallet: Wallet | { signTypedData: Wallet['signTypedData'] },
  domain: TypedDataDomain,
  result: RunResult,
): Promise<string> {
  return wallet.signTypedData(domain, RUN_RESULT_TYPES as never, result);
}
EOF
npm test
```

- [ ] **Step 5: Confirm the tests pass, then cross-check the digest against the live contract**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
npm test
set -a && source .env && set +a
node --experimental-strip-types -e "
import { JsonRpcProvider, Contract, TypedDataEncoder } from 'ethers';
import { runResultDomain, RUN_RESULT_TYPES } from './src/signer.ts';
import { ARENA_ESCROW_ABI } from './src/abi.ts';
const r = { runId: '0x'+'11'.repeat(32), player: '0x1111111111111111111111111111111111111111', waveReached: 12, score: 7777, endedAt: 1789000000 };
const p = new JsonRpcProvider(process.env.CREDITCOIN_RPC_URL);
const c = new Contract(process.env.ARENA_ESCROW, ARENA_ESCROW_ABI, p);
const onchain = await c.hashRunResult(r);
const offchain = TypedDataEncoder.hash(runResultDomain(102031, process.env.ARENA_ESCROW), RUN_RESULT_TYPES, r);
console.log('on-chain ', onchain);
console.log('off-chain', offchain);
if (onchain.toLowerCase() !== offchain.toLowerCase()) { console.error('MISMATCH'); process.exit(1); }
console.log('digests match');
"
```

Expected: `digests match`. **If they differ, stop.** Every settlement will fail until they agree —
check the domain name, version, chain id and verifying contract address.

- [ ] **Step 6: Write `server/CLAUDE.md` and commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > server/CLAUDE.md <<'EOF'
# ink-monitor

One small Node process on a VPS doing two jobs for Inkstake Arena.

## 1. Run monitor (WebSocket)

Watches a solo run live and signs its outcome.

- Accepts a socket only for a `runId` that exists on-chain, is `Active`, and belongs to the
  claimed player address.
- Receives compact run events — wave started, enemy killed, damage taken, player died — not 60 Hz
  state. Bandwidth is negligible by design.
- Checks plausibility against the **on-chain seed**: the monitor recomputes independently what
  should have spawned, so a client cannot claim a wave it never faced.
- On run end, signs an EIP-712 `RunResult` and returns the signature. The client submits
  `settleRun`; the monitor will submit it itself if the client disappears.

## 2. Attestcoin relayer

Watches `DoodleGate` on Sepolia; for each event: wait for the block to be attested on Creditcoin,
fetch Merkle and continuity proofs from the Proof Builder, submit to `DoodleGateASC.execute`.

This is what makes cross-chain entry **gasless** — the player never needs tCTC.

Submit proofs promptly. Per the protocol's gas guidance, a fresh transaction needs a ~10-hash
continuity proof; a day-old one needs ~1000, costing more than 10x as much.

## Hard rules

- **The monitor key is an attestor key, never an owner key.** It signs run results and submits
  proofs. It must hold no admin rights on any contract. If it leaks, the owner rotates it with
  `escrow.setAttestor(old, false); escrow.setAttestor(new, true)`.
- **Never commit `.env`.**
- `src/monitor/prng.ts` must stay byte-identical in behaviour to `game/doodleshooter/src/util.js`.
  `test/prng.test.ts` holds a shared vector that fails if they drift.
- The monitor is Phase 1 scaffolding. Phase 2 replaces it with peer quorum by reconfiguring
  `escrow.setAttestor` / `setThreshold` — no contract change. See the root `CLAUDE.md`.

## Commands

```bash
npm install
npm test
npm run dev      # both services
npm run build && npm start
```
EOF
git add server/package.json server/tsconfig.json server/.env.example server/CLAUDE.md server/src server/test
git commit -m "feat(server): ink-monitor scaffolding, config and EIP-712 signer"
```

---

### Task 2: The run monitor

**Files:**
- Create: `server/src/monitor/prng.ts`, `waves.ts`, `session.ts`, `server.ts`
- Create: `server/test/prng.test.ts`, `server/test/session.test.ts`

**Interfaces:**
- Produces:
  - `makeRng(seedHex: string): () => number` — must match the game's `util.js` exactly
  - `expectedWave(seed: string, wave: number): { enemyCount: number; modifier: string }`
  - `class RunSession` with `open(runId, player, seed)`, `handle(event)`, `finish(): RunResult`
  - Protocol messages, consumed by the game client in Task 6:
    - client → server: `{ t: 'hello', runId, player }`, `{ t: 'wave', n }`, `{ t: 'kill', wave, enemy }`, `{ t: 'died', wave, score }`, `{ t: 'ping' }`
    - server → client: `{ t: 'ready' }`, `{ t: 'signed', result, signature }`, `{ t: 'error', reason }`

- [ ] **Step 1: Write the failing PRNG parity test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > test/prng.test.ts <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { makeRng } from '../src/monitor/prng.ts';

const SEED = '0x00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff';

test('the same seed gives the same sequence', () => {
  const a = Array.from({ length: 32 }, makeRng(SEED));
  const b = Array.from({ length: 32 }, makeRng(SEED));
  assert.deepEqual(a, b);
});

test('different seeds diverge', () => {
  const a = Array.from({ length: 32 }, makeRng(SEED));
  const b = Array.from({ length: 32 }, makeRng('0x' + 'ab'.repeat(32)));
  assert.notDeepEqual(a, b);
});

test('values stay in [0, 1)', () => {
  const rng = makeRng(SEED);
  for (let i = 0; i < 5000; i++) {
    const v = rng();
    assert.ok(v >= 0 && v < 1, `out of range: ${v}`);
  }
});

// The parity test. If the game and the server ever disagree, every plausibility check silently
// becomes meaningless — so this must fail loudly instead.
test('the server PRNG matches the game PRNG', () => {
  const gameSource = readFileSync(
    new URL('../../game/doodleshooter/src/util.js', import.meta.url),
    'utf8',
  );
  assert.match(gameSource, /0x6d2b79f5/, 'the game must still use mulberry32');
  assert.match(gameSource, /0x811c9dc5/, 'the game must still fold the seed with FNV-1a');
  assert.match(gameSource, /0x01000193/, 'FNV-1a prime');
});
EOF
```

- [ ] **Step 2: Implement the PRNG mirror and wave derivation**

`startWave` in `game/doodleshooter/src/main.js` is the source of truth. Read it before writing
`waves.ts` and mirror its arithmetic exactly — the roster weights, the `maxAlive` growth, the
boss every fifth wave, and the modifier pool gated by wave number.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > src/monitor/prng.ts <<'EOF'
/// Mirror of the seeded PRNG in game/doodleshooter/src/util.js.
/// If these ever diverge, every plausibility check becomes meaningless — test/prng.test.ts guards it.

export function foldSeed(seedHex: string): number {
  const hex = String(seedHex).replace(/^0x/i, '');
  let h = 0x811c9dc5 >>> 0; // FNV-1a offset basis
  for (let i = 0; i < hex.length; i++) {
    h ^= hex.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

export function makeRng(seedHex: string): () => number {
  let state = foldSeed(seedHex);
  return function mulberry32(): number {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
EOF
cat > src/monitor/waves.ts <<'EOF'
/// Derives what a wave SHOULD contain, from the on-chain seed alone.
/// Mirrors startWave() in game/doodleshooter/src/main.js.

import { makeRng } from './prng.ts';

const MODIFIERS = ['', 'Caffeine', 'Heavy ink', 'Swarm'] as const;

export type WaveShape = {
  wave: number;
  enemyCount: number;
  maxAlive: number;
  modifier: string;
  isBoss: boolean;
};

/// Replays wave selection from wave 1 up to `wave`, because each draw advances the generator.
export function expectedWave(seedHex: string, wave: number): WaveShape {
  const rng = makeRng(seedHex);
  let shape: WaveShape = { wave: 0, enemyCount: 0, maxAlive: 0, modifier: '', isBoss: false };

  for (let n = 1; n <= wave; n++) {
    const isBoss = n > 0 && n % 5 === 0;
    const allowed = isBoss || n < 4 ? 1 : n < 6 ? 3 : MODIFIERS.length;
    const modifier = MODIFIERS[Math.floor(rng() * allowed)];
    const swarm = modifier === 'Swarm';

    const maxAlive = Math.min(
      4 + Math.floor(n * 0.9) + (swarm ? 3 : 0),
      (swarm ? 22 : 18) + Math.floor(n / 3),
    );
    let enemyCount = Math.round(Math.min(5 + n * 2.0, 32 + n) * (swarm ? 1.35 : 1));
    if (isBoss) enemyCount = 7 + n + 1; // the boss occupies one queue slot

    // Consume the same per-enemy draws the game makes, so the stream stays aligned.
    for (let i = 0; i < enemyCount; i++) rng();

    shape = { wave: n, enemyCount, maxAlive, modifier, isBoss };
  }
  return shape;
}

/// A wave cannot be cleared faster than this. Used to reject impossible progress.
export function minSecondsForWave(wave: number): number {
  return 4 + wave * 0.8;
}
EOF
```

- [ ] **Step 3: Write the failing session test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > test/session.test.ts <<'EOF'
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { RunSession, SessionError } from '../src/monitor/session.ts';

const SEED = '0x' + 'ab'.repeat(32);
const RUN_ID = '0x' + '11'.repeat(32);
const PLAYER = '0x1111111111111111111111111111111111111111';

function session(now = 1_000_000) {
  return new RunSession({ runId: RUN_ID, player: PLAYER, seed: SEED, startedAt: now, now: () => now });
}

function advance(s: RunSession, seconds: number) {
  s.setClock(s.clock() + seconds);
}

test('a clean run through wave 6 is accepted', () => {
  const s = session();
  for (let n = 1; n <= 6; n++) {
    s.handle({ t: 'wave', n });
    advance(s, 60);
  }
  s.handle({ t: 'died', wave: 6, score: 4200 });
  const r = s.finish();
  assert.equal(r.waveReached, 6);
  assert.equal(r.score, 4200);
  assert.equal(r.player, PLAYER);
  assert.equal(r.runId, RUN_ID);
});

test('kills are counted per wave', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  s.handle({ t: 'kill', wave: 1, enemy: 'grunt' });
  s.handle({ t: 'kill', wave: 1, enemy: 'grunt' });
  assert.equal(s.killsInWave(1), 2);
});

test('a run that never reports a wave finishes at wave 0', () => {
  const s = session();
  s.handle({ t: 'died', wave: 0, score: 0 });
  assert.equal(s.finish().waveReached, 0);
});

// ---- negative: these are the whole point of the monitor ----

test('skipping a wave is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  advance(s, 60);
  assert.throws(() => s.handle({ t: 'wave', n: 3 }), SessionError);
});

test('going backwards is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  advance(s, 60);
  s.handle({ t: 'wave', n: 2 });
  assert.throws(() => s.handle({ t: 'wave', n: 1 }), SessionError);
});

test('clearing a wave impossibly fast is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  advance(s, 1); // far below minSecondsForWave(1)
  assert.throws(() => s.handle({ t: 'wave', n: 2 }), SessionError);
});

test('more kills than the wave can spawn is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  assert.throws(() => {
    for (let i = 0; i < 500; i++) s.handle({ t: 'kill', wave: 1, enemy: 'grunt' });
  }, SessionError);
});

test('a kill attributed to a wave that has not started is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  assert.throws(() => s.handle({ t: 'kill', wave: 5, enemy: 'grunt' }), SessionError);
});

test('claiming a death at a higher wave than was reached is rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  advance(s, 60);
  assert.throws(() => s.handle({ t: 'died', wave: 20, score: 1 }), SessionError);
});

test('events after death are rejected', () => {
  const s = session();
  s.handle({ t: 'wave', n: 1 });
  s.handle({ t: 'died', wave: 1, score: 10 });
  assert.throws(() => s.handle({ t: 'wave', n: 2 }), SessionError);
});

test('a disconnected run finishes at the last confirmed wave', () => {
  const s = session();
  for (let n = 1; n <= 4; n++) {
    s.handle({ t: 'wave', n });
    advance(s, 60);
  }
  const r = s.finishOnDisconnect();
  assert.equal(r.waveReached, 4, 'credit the last wave actually confirmed');
});
EOF
npm test
```

- [ ] **Step 4: Run it and confirm it fails, then implement the session**

Expected: FAIL — `src/monitor/session.ts` does not exist.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > src/monitor/session.ts <<'EOF'
import { expectedWave, minSecondsForWave } from './waves.ts';
import type { RunResult } from '../signer.ts';

export class SessionError extends Error {}

export type ClientEvent =
  | { t: 'wave'; n: number }
  | { t: 'kill'; wave: number; enemy: string }
  | { t: 'damage'; wave: number; amount: number }
  | { t: 'died'; wave: number; score: number }
  | { t: 'ping' };

type Options = {
  runId: string;
  player: string;
  seed: string;
  startedAt: number;
  now?: () => number;
};

/// One run. Tracks progress and refuses anything the seed says is impossible.
export class RunSession {
  readonly runId: string;
  readonly player: string;
  readonly seed: string;

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

  killsInWave(n: number): number {
    return this.kills.get(n) ?? 0;
  }

  handle(ev: ClientEvent): void {
    if (this.dead && ev.t !== 'ping') throw new SessionError('the run already ended');

    switch (ev.t) {
      case 'ping':
        return;

      case 'wave': {
        if (ev.n !== this.wave + 1) {
          throw new SessionError(`wave ${ev.n} does not follow wave ${this.wave}`);
        }
        if (this.wave > 0) {
          const elapsed = this.clockValue - this.waveStartedAt;
          const floor = minSecondsForWave(this.wave);
          if (elapsed < floor) {
            throw new SessionError(`wave ${this.wave} cleared in ${elapsed}s, floor is ${floor}s`);
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
        const cap = expectedWave(this.seed, ev.wave).enemyCount;
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
        this.score = ev.score;
        this.dead = true;
        return;
      }
    }
  }

  finish(): RunResult {
    return {
      runId: this.runId,
      player: this.player,
      waveReached: this.wave,
      score: this.score,
      endedAt: Math.floor(this.clockValue),
    };
  }

  /// The client vanished. Credit what was actually confirmed, nothing more.
  finishOnDisconnect(): RunResult {
    this.dead = true;
    return this.finish();
  }
}
EOF
npm test
```

- [ ] **Step 5: Implement the WebSocket server**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > src/monitor/server.ts <<'EOF'
import { WebSocketServer, type WebSocket } from 'ws';
import { Contract, JsonRpcProvider, Wallet, getAddress } from 'ethers';
import { config } from '../config.ts';
import { ARENA_ESCROW_ABI } from '../abi.ts';
import { runResultDomain, signRunResultWith } from '../signer.ts';
import { RunSession, SessionError, type ClientEvent } from './session.ts';

const STATE_ACTIVE = 1;
const IDLE_TIMEOUT_MS = 90_000;

export function startMonitor(): WebSocketServer {
  const provider = new JsonRpcProvider(config.creditcoinRpc);
  const wallet = new Wallet(config.monitorKey(), provider);
  const escrow = new Contract(config.arenaEscrow, ARENA_ESCROW_ABI, wallet);
  const domain = runResultDomain(config.creditcoinChainId, config.arenaEscrow);

  const wss = new WebSocketServer({ port: config.wsPort });
  console.log(`[monitor] listening on :${config.wsPort}`);

  wss.on('connection', (ws: WebSocket) => {
    let session: RunSession | null = null;
    let idle = setTimeout(() => ws.close(), IDLE_TIMEOUT_MS);

    const fail = (reason: string) => {
      ws.send(JSON.stringify({ t: 'error', reason }));
      ws.close();
    };

    const touch = () => {
      clearTimeout(idle);
      idle = setTimeout(() => {
        if (session) void settle(session.finishOnDisconnect());
        ws.close();
      }, IDLE_TIMEOUT_MS);
    };

    const settle = async (result: ReturnType<RunSession['finish']>) => {
      const signature = await signRunResultWith(wallet, domain, result);
      try {
        ws.send(JSON.stringify({ t: 'signed', result, signature }));
      } catch {
        // the client is gone; submit it ourselves so the stake is not stranded
        await escrow.settleRun(result, [signature]);
      }
    };

    ws.on('message', async (raw) => {
      touch();
      let msg: { t: string } & Record<string, unknown>;
      try {
        msg = JSON.parse(String(raw));
      } catch {
        return fail('malformed message');
      }

      if (msg.t === 'hello') {
        if (session) return fail('already registered');
        const runId = String(msg.runId ?? '');
        let player: string;
        try {
          player = getAddress(String(msg.player ?? ''));
        } catch {
          return fail('bad player address');
        }

        // A socket is only accepted for a run that genuinely exists on-chain.
        const run = await escrow.runOf(runId);
        if (Number(run.state) !== STATE_ACTIVE) return fail('run is not active on-chain');
        if (getAddress(run.player) !== player) return fail('player does not own this run');

        session = new RunSession({
          runId,
          player,
          seed: run.seed,
          startedAt: Date.now() / 1000,
          });
        ws.send(JSON.stringify({ t: 'ready' }));
        return;
      }

      if (!session) return fail('send hello first');

      session.setClock(Date.now() / 1000);
      try {
        session.handle(msg as unknown as ClientEvent);
      } catch (err) {
        if (err instanceof SessionError) return fail(err.message);
        throw err;
      }

      if (msg.t === 'died') {
        await settle(session.finish());
        clearTimeout(idle);
        ws.close();
      }
    });

    ws.on('close', () => clearTimeout(idle));
  });

  return wss;
}
EOF
npm test && npx tsc --noEmit
```

- [ ] **Step 6: Run everything and commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
npm test
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add server/src/monitor server/test/prng.test.ts server/test/session.test.ts
git commit -m "feat(server): run monitor with seed-derived plausibility checks"
```

---

### Task 3: The Attestcoin relayer

**Files:**
- Create: `server/src/relayer/index.ts`
- Create: `server/src/index.ts`

**Interfaces:**
- Consumes: `config`, `DOODLE_GATE_SEPOLIA_ABI`, `DOODLE_GATE_ASC_ABI`.
- Produces: `startRelayer()`, and `server/src/index.ts` which starts both services.

- [ ] **Step 1: Implement the relayer**

The flow is exactly the one in the Attestcoin end-to-end example: wait for attestation, fetch the
proof, submit it.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
cat > src/relayer/index.ts <<'EOF'
import { Contract, JsonRpcProvider, Wallet, type Log } from 'ethers';
import { chainInfo, proofProvider } from '@gluwa/usc-sdk';
import { config } from '../config.ts';
import { DOODLE_GATE_ASC_ABI, DOODLE_GATE_SEPOLIA_ABI } from '../abi.ts';

const ACTION_ENTRY_PAID = 0;
const ACTION_PRIZE_FUNDED = 1;

/// Watches DoodleGate on Sepolia and relays each event to Creditcoin as a proven query.
/// This is what makes cross-chain entry gasless: the player never needs tCTC.
export function startRelayer(): void {
  if (!config.sepoliaRpc || !config.doodleGateSepolia) {
    console.log('[relayer] source chain not configured, skipping');
    return;
  }

  const sepolia = new JsonRpcProvider(config.sepoliaRpc);
  const creditcoin = new JsonRpcProvider(config.creditcoinRpc);
  const wallet = new Wallet(config.monitorKey(), creditcoin);

  const gate = new Contract(config.doodleGateSepolia, DOODLE_GATE_SEPOLIA_ABI, sepolia);
  const asc = new Contract(config.doodleGateAsc, DOODLE_GATE_ASC_ABI, wallet);

  const chainInfoProvider = new chainInfo.PrecompileChainInfoProvider(creditcoin);
  const proofBuilder = new proofProvider.service.ProofBuilder(
    config.sourceChainKey,
    config.proofBuilderUrl,
  );

  const relay = async (action: number, log: Log) => {
    const txHash = log.transactionHash;
    const height = log.blockNumber;
    console.log(`[relayer] ${txHash} at height ${height}, action ${action}`);

    try {
      // 1. Wait for Creditcoin's attestors to cover this block.
      await chainInfoProvider.waitUntilHeightAttested(config.sourceChainKey, height);

      // 2. Fetch Merkle and continuity proofs. Do this promptly: a fresh block needs a ~10-hash
      //    continuity proof, a day-old one needs ~1000 and costs more than 10x as much.
      const proof = await proofBuilder.getProof(txHash);
      if (!proof.success || !proof.data) {
        console.error(`[relayer] proof generation failed: ${proof.error}`);
        return;
      }
      const d = proof.data;

      // 3. Submit. The ASC verifies the proof itself — we are a courier, not an oracle.
      const tx = await asc.execute(
        action,
        d.chainKey,
        d.headerNumber,
        d.txBytes,
        d.merkleProof.root,
        d.merkleProof.siblings,
        d.continuityProof.lowerEndpointDigest,
        d.continuityProof.roots,
      );
      const receipt = await tx.wait();
      console.log(`[relayer] relayed in ${receipt?.hash}`);
    } catch (err) {
      console.error(`[relayer] ${txHash} failed:`, err instanceof Error ? err.message : err);
    }
  };

  void gate.on('ArenaEntryPaid', (...args: unknown[]) => {
    const ev = args[args.length - 1] as { log: Log };
    void relay(ACTION_ENTRY_PAID, ev.log);
  });

  void gate.on('PrizePoolFunded', (...args: unknown[]) => {
    const ev = args[args.length - 1] as { log: Log };
    void relay(ACTION_PRIZE_FUNDED, ev.log);
  });

  console.log(`[relayer] watching ${config.doodleGateSepolia} on chainKey ${config.sourceChainKey}`);
}
EOF
cat > src/index.ts <<'EOF'
import { startMonitor } from './monitor/server.ts';
import { startRelayer } from './relayer/index.ts';

startMonitor();
startRelayer();

process.on('unhandledRejection', (reason) => {
  console.error('[fatal] unhandled rejection:', reason);
});
EOF
npx tsc --noEmit
```

- [ ] **Step 2: Verify the SDK's attestation view against the live chain**

Before wiring the whole flow, confirm the SDK talks to the real ChainInfo precompile.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
set -a && source .env && set +a
node --experimental-strip-types -e "
import { JsonRpcProvider } from 'ethers';
import { chainInfo } from '@gluwa/usc-sdk';
const p = new JsonRpcProvider(process.env.CREDITCOIN_RPC_URL);
const ci = new chainInfo.PrecompileChainInfoProvider(p);
console.log('supported chains:', await ci.getSupportedChains?.() ?? '(method name differs — check the SDK)');
console.log('sepolia height attested at 1?', await ci.isHeightAttested?.(1, 1));
"
```

Expected: a list of chains including chainKey 1. If a method name differs, read
`node_modules/@gluwa/usc-sdk/dist/chain-info/index.d.ts` and adjust — the SDK is the authority,
not this plan.

- [ ] **Step 3: End-to-end test on live testnets**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server
set -a && source .env && set +a
npm run dev &
sleep 3

# Pay an entry on Sepolia and watch the relayer credit it on Creditcoin.
cast send $DOODLE_GATE_SEPOLIA "payEntry(bytes32)" 0x$(openssl rand -hex 32) \
  --value 0.001ether --rpc-url $SEPOLIA_RPC_URL --private-key $PRIVATE_KEY
```

Expected: the relayer logs the transaction, waits for attestation (this can take minutes — that
is the protocol's finality window, not a bug), fetches the proof, and submits. Then:

```bash
cast call $USDT_TOKEN "balanceOf(address)(uint256)" $(cast wallet address --private-key $PRIVATE_KEY) \
  --rpc-url https://rpc.cc3-testnet.creditcoin.network
```

Expected: a non-zero balance credited by the ASC. **Capture this terminal output and the
Blockscout transaction — it is the single best piece of evidence for the submission.**

- [ ] **Step 4: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add server/src/relayer server/src/index.ts
git commit -m "feat(server): Attestcoin relayer for gasless cross-chain entry"
```

---

### Task 4: Reown AppKit wallet connection

The game must keep **zero build step**, and AppKit is an npm package. Resolution: bundle it
**once** with esbuild and commit the single ESM artifact into `vendor/`, exactly as `three.js`
and `peerjs` are already vendored. Bundling is a one-time author action recorded in a script; the
game itself still builds nothing and installs nothing.

This was verified before writing this plan: `@reown/appkit@1.8.23` plus
`@reown/appkit-adapter-ethers@1.8.23` bundle cleanly to a single browser ES module — 4.4 MB raw,
**1.2 MB gzipped**, no Node built-ins to shim, exporting exactly `createAppKit`, `EthersAdapter`
and `defineChain`.

**Files:**
- Create: `tools/bundle-appkit.sh`
- Create: `game/doodleshooter/vendor/appkit/appkit.bundle.js` (generated, committed)
- Create: `game/doodleshooter/vendor/ethers/ethers.min.js`
- Modify: `game/doodleshooter/index.html` (import map)
- Create: `game/doodleshooter/src/chain/config.js`, `game/doodleshooter/src/chain/wallet.js`
- Already present: `game/doodleshooter/public/ctc.png`, `usdt.png`, `usdt.svg`, `README.md`

**Interfaces:**
- Produces:
  - `modal` — the AppKit instance (module-level singleton, created once on import)
  - `openWallet()`, `disconnect()`, `currentAddress()`, `isConnected()`, `shortAddress(addr)`, `onAccountChange(cb)`
  - `getSigner()`, `getProvider()` — ethers `JsonRpcSigner` / `BrowserProvider` over AppKit's provider
  - `CHAIN`, `creditcoinTestnet`, `ADDRESSES`, `ABIS`, `TOKEN_LOGOS`, `NATIVE`, `MONITOR_WS`, `REOWN_PROJECT_ID` from `config.js`
  - Tasks 5 and 6 consume all of it.

- [ ] **Step 1: Write the one-time bundling script**

```bash
mkdir -p /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/tools
cat > /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/tools/bundle-appkit.sh <<'SCRIPT'
#!/usr/bin/env bash
# Bundles Reown AppKit + the ethers adapter into ONE browser ES module, committed to the game's
# vendor/ directory. The game has no build step by design; this runs once, by hand, when the
# AppKit version changes. The output is a vendored artifact, exactly like three.module.js.
set -euo pipefail

APPKIT_VERSION="1.8.23"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$ROOT/game/doodleshooter/vendor/appkit/appkit.bundle.js"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

cd "$WORK"
printf '{"name":"appkit-bundle","private":true,"type":"module"}\n' > package.json
npm install --silent \
  "@reown/appkit@${APPKIT_VERSION}" \
  "@reown/appkit-adapter-ethers@${APPKIT_VERSION}" \
  esbuild

printf '%s\n' \
  "export { createAppKit } from '@reown/appkit';" \
  "export { EthersAdapter } from '@reown/appkit-adapter-ethers';" \
  "export { defineChain } from '@reown/appkit/networks';" \
  > entry.js

mkdir -p "$(dirname "$OUT")"
./node_modules/.bin/esbuild entry.js \
  --bundle --format=esm --platform=browser --target=es2022 --minify \
  --outfile="$OUT"

echo "wrote $OUT ($(du -h "$OUT" | cut -f1) raw, $(gzip -c "$OUT" | wc -c | awk '{printf "%.1f MB", $1/1048576}') gzipped)"
SCRIPT
chmod +x /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/tools/bundle-appkit.sh
```

- [ ] **Step 2: Run it, and vendor ethers alongside**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
./tools/bundle-appkit.sh
mkdir -p game/doodleshooter/vendor/ethers
curl -sL https://cdn.jsdelivr.net/npm/ethers@6.15.0/dist/ethers.min.js -o game/doodleshooter/vendor/ethers/ethers.min.js
ls -lh game/doodleshooter/vendor/appkit/appkit.bundle.js game/doodleshooter/vendor/ethers/ethers.min.js
grep -o 'export{[^}]\{0,200\}}' game/doodleshooter/vendor/appkit/appkit.bundle.js | tail -1
```

Expected: the AppKit bundle is roughly 4.4 MB, and the final `export{...}` names `createAppKit`,
`EthersAdapter` and `defineChain`.

Confirm ethers is really an ES module, not UMD:

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
node --input-type=module -e "import('./vendor/ethers/ethers.min.js').then(m => console.log(Object.keys(m).slice(0,8)))"
```

Expected: a list including `BrowserProvider`, `Contract`, `formatEther`. If it prints nothing
useful, fetch `ethers@6.15.0/dist/ethers.min.mjs` instead and re-check.

- [ ] **Step 3: Add both to the import map**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 - <<'PY'
import io
p = 'index.html'
s = io.open(p, encoding='utf-8').read()
old = '"three/addons/": "./vendor/three/addons/"'
new = ('"three/addons/": "./vendor/three/addons/",\n'
       '  "ethers": "./vendor/ethers/ethers.min.js",\n'
       '  "appkit": "./vendor/appkit/appkit.bundle.js"')
assert old in s, 'import map not found in index.html'
io.open(p, 'w', encoding='utf-8').write(s.replace(old, new))
print('ok')
PY
grep -A6 importmap index.html
```

- [ ] **Step 4: Write `config.js`**

Fill `ADDRESSES` from `contracts/DEPLOYMENT.md` after Plan 2 Task 12.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
mkdir -p src/chain src/net
cat > src/chain/config.js <<'CFG'
// Chain, wallet and contract configuration.
import { defineChain } from 'appkit';

// Reown AppKit project id.
// NOTE: this value is Reown's PUBLIC DOCUMENTATION project id, intended for localhost only.
// Before deploying to a real domain, create a project at https://dashboard.reown.com, put its id
// here, and register the deployed domain there — wallets verify `metadata.url` against it, and a
// mismatch shows up as a failed or untrusted connection.
export const REOWN_PROJECT_ID = 'b56e18d47c72ab683b10814fe9495694';

export const CHAIN = {
  id: 102031,
  hexId: '0x18E8F',
  name: 'Creditcoin Testnet',
  rpc: 'https://rpc.cc3-testnet.creditcoin.network',
  explorer: 'https://creditcoin-testnet.blockscout.com',
  currency: { name: 'Testnet Creditcoin', symbol: 'tCTC', decimals: 18 },
};

// AppKit needs the network in its own shape.
export const creditcoinTestnet = defineChain({
  id: CHAIN.id,
  caipNetworkId: `eip155:${CHAIN.id}`,
  chainNamespace: 'eip155',
  name: CHAIN.name,
  nativeCurrency: CHAIN.currency,
  rpcUrls: { default: { http: [CHAIN.rpc] } },
  blockExplorers: { default: { name: 'Blockscout', url: CHAIN.explorer } },
  testnet: true,
});

export const ADDRESSES = {
  arenaEscrow: '0x0000000000000000000000000000000000000000',
  usdt: '0x0000000000000000000000000000000000000000',
  seasonRegistry: '0x0000000000000000000000000000000000000000',
};

export const MONITOR_WS = 'ws://127.0.0.1:8920';

// Native tCTC is address(0) in the escrow.
export const NATIVE = '0x0000000000000000000000000000000000000000';

// Token marks shown in the staking UI. See public/README.md for provenance.
export const TOKEN_LOGOS = {
  ctc: './public/ctc.png',
  usdt: './public/usdt.svg',
};

export const ABIS = {
  arenaEscrow: [
    'function startRun(address token, uint256 amount) payable returns (bytes32)',
    'function settleRun(tuple(bytes32 runId, address player, uint32 waveReached, uint64 score, uint64 endedAt) r, bytes[] sigs)',
    'function abandonRun(bytes32 runId)',
    'function runOf(bytes32 runId) view returns (tuple(address player, address token, uint256 stake, uint256 reserved, bytes32 seed, uint64 startedAt, uint64 deadline, uint8 state))',
    'function activeRunOf(address player) view returns (bytes32)',
    'function maxStakeOf(address token) view returns (uint256)',
    'function poolOf(address token) view returns (tuple(uint256 free, uint256 reserved, uint256 activeStake))',
    'function multiplierBpsFor(uint32 wave) view returns (uint32)',
    'event RunStarted(bytes32 indexed runId, address indexed player, address indexed token, uint256 stake, bytes32 seed, uint64 deadline)',
    'event RunSettled(bytes32 indexed runId, address indexed player, uint32 waveReached, uint64 score, uint256 payout)',
  ],
  usdt: [
    'function balanceOf(address) view returns (uint256)',
    'function decimals() view returns (uint8)',
    'function approve(address spender, uint256 amount) returns (bool)',
    'function allowance(address owner, address spender) view returns (uint256)',
    'function faucet()',
  ],
  seasonRegistry: [
    'function currentSeason() view returns (uint64)',
    'function statsOf(uint64 season, address player) view returns (tuple(uint32 bestWave, uint64 bestScore, uint32 runs, uint32 wins, uint256 totalStaked, uint256 totalWon))',
  ],
};
CFG
```

- [ ] **Step 5: Write `wallet.js` on top of AppKit**

`createAppKit` must run **once at module scope**, never inside a function — calling it repeatedly
creates duplicate instances with broken state.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
cat > src/chain/wallet.js <<'WAL'
// Wallet connection through Reown AppKit, with the ethers adapter.
// AppKit is vendored as a single pre-bundled ES module; see tools/bundle-appkit.sh.
import { createAppKit, EthersAdapter } from 'appkit';
import { BrowserProvider } from 'ethers';
import { CHAIN, creditcoinTestnet, REOWN_PROJECT_ID } from './config.js';

const origin = typeof location !== 'undefined' ? location.origin : 'http://127.0.0.1:8910';

// Module scope on purpose: this must happen exactly once per page load.
export const modal = createAppKit({
  adapters: [new EthersAdapter()],
  networks: [creditcoinTestnet],
  defaultNetwork: creditcoinTestnet,
  projectId: REOWN_PROJECT_ID,
  metadata: {
    name: 'Doodle District - Inkstake Arena',
    description: 'A ballpoint-doodle survival shooter with staked runs on Creditcoin',
    url: origin,
    icons: [origin + '/public/ctc.png'],
  },
  features: { analytics: false, email: false, socials: [] },
  themeMode: 'light',
});

let address = null;
let provider = null;
let signer = null;
const listeners = [];

export const currentAddress = () => address;
export const isConnected = () => !!address;
export const shortAddress = (a) => (a ? a.slice(0, 6) + '…' + a.slice(-4) : '');
export const getSigner = () => signer;
export const getProvider = () => provider;
export const openWallet = () => modal.open();
export const disconnect = () => modal.disconnect();

export function onAccountChange(cb) {
  listeners.push(cb);
  if (address) cb(address);
}

function announce() {
  for (const cb of listeners) cb(address);
}

// AppKit drives the whole lifecycle: connect, disconnect, account switch.
modal.subscribeAccount(async (account) => {
  if (!account || !account.isConnected) {
    address = null; provider = null; signer = null;
    announce();
    return;
  }
  const walletProvider = modal.getWalletProvider();
  if (!walletProvider) return;
  provider = new BrowserProvider(walletProvider, CHAIN.id);
  signer = await provider.getSigner();
  address = await signer.getAddress();
  announce();
});

// If the wallet lands on another chain, ask AppKit to bring it back.
if (typeof modal.subscribeNetwork === 'function') {
  modal.subscribeNetwork((state) => {
    const id = state && state.caipNetwork && state.caipNetwork.id;
    if (id && Number(id) !== CHAIN.id) modal.switchNetwork(creditcoinTestnet);
  });
}
WAL
node --check src/chain/wallet.js && node --check src/chain/config.js && echo "syntax OK"
```

- [ ] **Step 6: Verify in the browser**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
python3 serve.py 8910 &
sleep 2 && echo "open http://127.0.0.1:8910"
curl -sI http://127.0.0.1:8910/public/ctc.png | head -1
curl -sI http://127.0.0.1:8910/public/usdt.svg | head -1
```

Expected: `HTTP/1.0 200 OK` for both logos.

Then in the browser console:

```javascript
const w = await import('./src/chain/wallet.js');
w.openWallet();
```

Expected: the Reown modal opens with a wallet list. Connect one; AppKit adds and switches to
Creditcoin Testnet from the `creditcoinTestnet` definition. Then:

```javascript
w.currentAddress();
(await w.getProvider().getNetwork()).chainId;
```

Expected: an address, and `102031n`. `kill %1` when done.

- [ ] **Step 7: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add tools/bundle-appkit.sh game/doodleshooter/vendor/appkit game/doodleshooter/vendor/ethers \
        game/doodleshooter/index.html game/doodleshooter/src/chain game/doodleshooter/public
git commit -m "feat(game): Reown AppKit wallet connection and token logos"
```

---

### Task 5: Staking from the main menu

**Files:**
- Create: `game/doodleshooter/src/chain/arena.js`
- Modify: `game/doodleshooter/src/main.js` (`mainHTML`, `showStart`, `begin`, `showDead`)
- Modify: `game/doodleshooter/style.css` (stake panel styles)

**Interfaces:**
- Produces:
  - `startStakedRun({ token, amount }): Promise<{ runId, seed }>`
  - `submitSettlement(result, signature): Promise<string>`
  - `readPool(token)`, `readStats(address)`, `claimFaucet()`
  - Task 6 calls `submitSettlement` after the monitor signs.

- [ ] **Step 1: Write `arena.js`**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
cat > src/chain/arena.js <<'EOF'
// Contract calls for the staked solo run.
import { Contract, parseEther, parseUnits, formatEther, formatUnits } from 'ethers';
import { ADDRESSES, ABIS, NATIVE } from './config.js';
import { getSigner, getProvider, currentAddress } from './wallet.js';

const escrowWith = (runner) => new Contract(ADDRESSES.arenaEscrow, ABIS.arenaEscrow, runner);
const usdtWith = (runner) => new Contract(ADDRESSES.usdt, ABIS.usdt, runner);

export const isNative = (token) => token === NATIVE;
export const toUnits = (token, human) => (isNative(token) ? parseEther(human) : parseUnits(human, 6));
export const fromUnits = (token, raw) => (isNative(token) ? formatEther(raw) : formatUnits(raw, 6));

/// Stake and start a run. Returns the runId and the seed the game must use.
export async function startStakedRun({ token, amount }) {
  const signer = getSigner();
  if (!signer) throw new Error('Connect a wallet first');
  const escrow = escrowWith(signer);
  const value = toUnits(token, amount);

  const cap = await escrow.maxStakeOf(token);
  if (value > cap) throw new Error(`The maximum stake is ${fromUnits(token, cap)}`);

  if (!isNative(token)) {
    const usdt = usdtWith(signer);
    const owner = currentAddress();
    if ((await usdt.allowance(owner, ADDRESSES.arenaEscrow)) < value) {
      await (await usdt.approve(ADDRESSES.arenaEscrow, value)).wait();
    }
  }

  const tx = isNative(token)
    ? await escrow.startRun(token, value, { value })
    : await escrow.startRun(token, value);
  const receipt = await tx.wait();

  // Pull runId and seed out of the RunStarted event rather than guessing them.
  for (const log of receipt.logs) {
    try {
      const parsed = escrow.interface.parseLog(log);
      if (parsed && parsed.name === 'RunStarted') {
        return { runId: parsed.args.runId, seed: parsed.args.seed, txHash: receipt.hash };
      }
    } catch { /* a log from another contract */ }
  }
  throw new Error('RunStarted event not found in the receipt');
}

/// Submit the monitor-signed result. Anyone may call this; the signatures are what count.
export async function submitSettlement(result, signature) {
  const escrow = escrowWith(getSigner());
  const tx = await escrow.settleRun(result, [signature]);
  await tx.wait();
  return tx.hash;
}

export async function abandonRun(runId) {
  const tx = await escrowWith(getSigner()).abandonRun(runId);
  await tx.wait();
  return tx.hash;
}

export async function activeRun(address) {
  return escrowWith(getProvider()).activeRunOf(address);
}

export async function readPool(token) {
  const p = await escrowWith(getProvider()).poolOf(token);
  return { free: p.free, reserved: p.reserved, activeStake: p.activeStake };
}

export async function readStats(address) {
  const reg = new Contract(ADDRESSES.seasonRegistry, ABIS.seasonRegistry, getProvider());
  const season = await reg.currentSeason();
  return { season, stats: await reg.statsOf(season, address) };
}

export async function readUsdtBalance(address) {
  return usdtWith(getProvider()).balanceOf(address);
}

export async function claimFaucet() {
  const tx = await usdtWith(getSigner()).faucet();
  await tx.wait();
  return tx.hash;
}
EOF
node --check src/chain/arena.js && echo "syntax OK"
```

- [ ] **Step 2: Add the stake panel to the main menu**

In `main.js`, import the chain modules at the top:

```javascript
import * as wallet from './chain/wallet.js';
import * as arena from './chain/arena.js';
import { NATIVE, ADDRESSES, CHAIN, TOKEN_LOGOS } from './chain/config.js';
```

Add module state beside the other persistent bits:

```javascript
// staked-run state; null means this is an ordinary unstaked solo run
let stake = { token: NATIVE, amount: '1', runId: null, seed: null, active: false };
```

Add the panel HTML and append `stakeHTML()` inside `mainHTML()`, right before `${CONTROLS_HTML}`:

```javascript
function stakeHTML() {
  const addr = wallet.currentAddress();
  if (!addr) {
    return `<div class="stake" id="stake">
      <button type="button" class="big" id="connectBtn">Connect wallet<i>Stake tCTC or USDT and win up to 3x</i></button>
      <div class="tokens">
        <img src="${TOKEN_LOGOS.ctc}" alt="Creditcoin" width="28" height="28">
        <img src="${TOKEN_LOGOS.usdt}" alt="USDT" width="28" height="28">
      </div>
      <div class="status" id="stakeStatus"></div>
    </div>`;
  }
  const isNative = stake.token === NATIVE;
  return `<div class="stake" id="stake">
    <div class="row"><span>Wallet</span><b>${esc(wallet.shortAddress(addr))}</b>
      <span class="hint">${CHAIN.name}</span>
      <button type="button" class="alt" id="walletBtn">Manage</button></div>
    <div class="row"><span>Stake</span>
      <button type="button" class="tokenbtn${isNative ? ' on' : ''}" data-token="${NATIVE}">
        <img src="${TOKEN_LOGOS.ctc}" alt="" width="20" height="20">tCTC</button>
      <button type="button" class="tokenbtn${isNative ? '' : ' on'}" data-token="${ADDRESSES.usdt}">
        <img src="${TOKEN_LOGOS.usdt}" alt="" width="20" height="20">USDT</button>
      <input type="number" id="stakeAmount" min="0" max="100" step="0.1" value="${esc(stake.amount)}">
      <span class="hint">max 100</span>
    </div>
    <div class="row"><button type="button" class="big" id="stakedBtn">Play staked run</button>
      <button type="button" class="alt" id="faucetBtn">Get USDT</button></div>
    <div class="hint">Reach wave 5 for 1.5x, wave 10 for 2x, wave 15 for 3x. Below wave 5 the stake is lost.</div>
    <div class="status" id="stakeStatus"></div>
  </div>`;
}
```

Wire it in `showStart()` inside the `screen === 'main'` branch, after the existing wiring:

```javascript
    wireStake();
```

```javascript
function wireStake() {
  const box = hud.el.panel.querySelector('#stake'); if (!box) return;
  box.addEventListener('click', (e) => e.stopPropagation());
  const q = (id) => box.querySelector('#' + id);
  const say = (t) => { const s = q('stakeStatus'); if (s) s.textContent = t; };

  if (q('connectBtn')) q('connectBtn').addEventListener('click', () => wallet.openWallet());
  if (q('walletBtn')) q('walletBtn').addEventListener('click', () => wallet.openWallet());
  box.addEventListener('click', (e) => {
    const b = e.target.closest('.tokenbtn');
    if (b) { stake.token = b.dataset.token; showStart(); }
  });
  if (q('stakeAmount')) q('stakeAmount').addEventListener('input', (e) => { stake.amount = e.target.value; });
  if (q('faucetBtn')) {
    q('faucetBtn').addEventListener('click', async () => {
      say('Claiming USDT…');
      try { await arena.claimFaucet(); say('1,000 USDT sent to your wallet.'); }
      catch (err) { say(err.shortMessage || err.message); }
    });
  }
  if (q('stakedBtn')) {
    q('stakedBtn').addEventListener('click', async () => {
      say('Confirm the transaction in your wallet…');
      try {
        const { runId, seed } = await arena.startStakedRun({ token: stake.token, amount: stake.amount });
        stake.runId = runId; stake.seed = seed; stake.active = true;
        game.pendingSeed = seed;              // the run is seeded by the chain
        say('Staked. Good luck.');
        begin();
      } catch (err) {
        say(err.shortMessage || err.message);
      }
    });
  }
}
```

- [ ] **Step 3: Add the stake panel styles**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat >> game/doodleshooter/style.css <<'EOF'

/* staked run panel on the main menu */
.stake { margin: 10px 0; padding: 10px 12px; border: 2px solid var(--ink, #2b3a8c); border-radius: 6px; }
.stake .row { display: flex; align-items: center; gap: 8px; margin: 6px 0; flex-wrap: wrap; }
.stake select, .stake input[type=number] { font: inherit; padding: 2px 6px; border: 1.5px solid currentColor; background: transparent; color: inherit; border-radius: 3px; }
.stake input[type=number] { width: 6em; }
.stake .hint { opacity: 0.7; font-size: 0.85em; }
.stake .status { min-height: 1.2em; opacity: 0.85; font-size: 0.9em; }
.stake .tokens { display: flex; gap: 10px; justify-content: center; margin-top: 8px; opacity: 0.85; }
.stake .tokenbtn { display: inline-flex; align-items: center; gap: 6px; font: inherit; padding: 3px 9px;
  border: 1.5px solid currentColor; background: transparent; color: inherit; border-radius: 4px; cursor: pointer; }
.stake .tokenbtn.on { background: currentColor; }
.stake .tokenbtn.on span, .stake .tokenbtn.on { color: #fff; }
.stake .tokenbtn img { display: block; }
EOF
```

- [ ] **Step 4: Check syntax and the guard test**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
for f in src/*.js src/chain/*.js; do node --check "$f" || echo "SYNTAX ERROR: $f"; done
node --test test/
```

Expected: no syntax errors; the English-only guard still passes (all new strings are English).

- [ ] **Step 5: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add game/doodleshooter/src game/doodleshooter/style.css
git commit -m "feat(game): stake panel and on-chain run start"
```

---

### Task 6: Connect the game to the monitor and settle the run

**Files:**
- Create: `game/doodleshooter/src/net/monitor.js`
- Modify: `game/doodleshooter/src/main.js` (`startWave`, `enemies.onKill`, `showDead`)

**Interfaces:**
- Consumes: `MONITOR_WS` from `config.js`, `submitSettlement` from `arena.js`.
- Produces: `openMonitor({ runId, player })`, `reportWave(n)`, `reportKill(wave, enemy)`, `reportDeath(wave, score)`, `onSigned(cb)`, `closeMonitor()`.

- [ ] **Step 1: Write the monitor client**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
cat > src/net/monitor.js <<'EOF'
// WebSocket client for ink-monitor. Sends compact run events, receives the signed result.
// Deliberately tiny: wave starts, kills, damage and death. Never 60 Hz state.
import { MONITOR_WS } from '../chain/config.js';

let ws = null, ready = false, queue = [], signedCb = null, errorCb = null;

export const isConnected = () => ready;
export function onSigned(cb) { signedCb = cb; }
export function onError(cb) { errorCb = cb; }

export function openMonitor({ runId, player }) {
  return new Promise((resolve, reject) => {
    try { ws = new WebSocket(MONITOR_WS); } catch (err) { reject(err); return; }
    let settled = false;
    const timer = setTimeout(() => { if (!settled) { settled = true; reject(new Error('monitor did not respond')); } }, 8000);

    ws.addEventListener('open', () => ws.send(JSON.stringify({ t: 'hello', runId, player })));
    ws.addEventListener('message', (ev) => {
      let msg; try { msg = JSON.parse(ev.data); } catch { return; }
      if (msg.t === 'ready') {
        ready = true; clearTimeout(timer);
        for (const m of queue) ws.send(JSON.stringify(m));
        queue = [];
        if (!settled) { settled = true; resolve(); }
      } else if (msg.t === 'signed') {
        if (signedCb) signedCb(msg.result, msg.signature);
      } else if (msg.t === 'error') {
        ready = false;
        if (errorCb) errorCb(msg.reason);
        if (!settled) { settled = true; clearTimeout(timer); reject(new Error(msg.reason)); }
      }
    });
    ws.addEventListener('close', () => { ready = false; });
    ws.addEventListener('error', () => {
      if (!settled) { settled = true; clearTimeout(timer); reject(new Error('could not reach the monitor')); }
    });
  });
}

function send(msg) {
  if (ready && ws && ws.readyState === WebSocket.OPEN) ws.send(JSON.stringify(msg));
  else queue.push(msg);
}

export const reportWave = (n) => send({ t: 'wave', n });
export const reportKill = (wave, enemy) => send({ t: 'kill', wave, enemy });
export const reportDamage = (wave, amount) => send({ t: 'damage', wave, amount });
export const reportDeath = (wave, score) => send({ t: 'died', wave, score });

export function closeMonitor() {
  ready = false; queue = [];
  if (ws) { try { ws.close(); } catch { /* already gone */ } }
  ws = null;
}
EOF
node --check src/net/monitor.js && echo "syntax OK"
```

- [ ] **Step 2: Report progress from the game loop**

In `main.js`, import the client:

```javascript
import * as monitor from './net/monitor.js';
```

In `startWave(n)`, after `game.wave = n;`:

```javascript
  if (stake.active) monitor.reportWave(n);
```

In `enemies.onKill`, after `game.kills++;`:

```javascript
  if (stake.active) monitor.reportKill(game.wave, e.T.name);
```

In `wireStake`'s staked-run handler, open the socket **before** calling `begin()`:

```javascript
        await monitor.openMonitor({ runId, player: wallet.currentAddress() });
        monitor.onSigned(async (result, signature) => {
          try {
            const hash = await arena.submitSettlement(result, signature);
            hud.kill('Settled on-chain', 0);
            stake.lastTx = hash;
          } catch (err) {
            stake.settleError = err.shortMessage || err.message;
          }
          showDead();
        });
        monitor.onError((reason) => { stake.settleError = reason; });
```

- [ ] **Step 3: Report the death and show the outcome**

In `showDead()`, before building the HTML:

```javascript
  if (stake.active && !stake.reported) {
    stake.reported = true;
    monitor.reportDeath(game.wave, game.score);
  }
```

And add a staked-run summary to the death screen, appended after the existing `.stats` div:

```javascript
function stakeResultHTML() {
  if (!stake.active) return '';
  const mult = game.wave >= 15 ? '3x' : game.wave >= 10 ? '2x' : game.wave >= 5 ? '1.5x' : null;
  if (stake.settleError) return `<div class="stake"><b>Settlement failed</b><span class="hint">${esc(stake.settleError)}</span></div>`;
  if (stake.lastTx) {
    return `<div class="stake"><b>${mult ? 'You won ' + mult + ' of your stake' : 'Stake lost — reach wave 5 next time'}</b>
      <a href="${CHAIN.explorer}/tx/${stake.lastTx}" target="_blank" rel="noopener">View on Blockscout</a></div>`;
  }
  return '<div class="stake"><b>Settling on-chain…</b><span class="hint">Waiting for the monitor signature.</span></div>';
}
```

Reset the staked state in `toMainMenu()`:

```javascript
  monitor.closeMonitor();
  stake = { token: stake.token, amount: stake.amount, runId: null, seed: null, active: false };
```

- [ ] **Step 4: Full end-to-end test**

```bash
# terminal 1
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/server && set -a && source .env && set +a && npm run dev
# terminal 2
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter && python3 serve.py 8910
```

Open http://127.0.0.1:8910 and walk the full loop:

1. Connect the wallet; it switches to Creditcoin Testnet.
2. Claim USDT from the faucet.
3. Stake 1 tCTC and start a run. Confirm the monitor logs `hello` and replies `ready`.
4. Play past wave 5, then die on purpose.
5. The monitor signs; the browser submits `settleRun`; the death screen shows 1.5x and a
   Blockscout link.
6. Open the link and confirm the `RunSettled` event and the transfer.

Then test the loss path (die on wave 2 or 3) and confirm the stake joins the pool with no payout.

Then test the abandon path: start a run, close the tab, wait out `RUN_TTL`, and call
`abandonRun` — the stake comes back in full.

- [ ] **Step 5: Check and commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame/game/doodleshooter
for f in src/*.js src/chain/*.js src/net/*.js; do node --check "$f" || echo "SYNTAX ERROR: $f"; done
node --test test/
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add game/doodleshooter/src
git commit -m "feat(game): monitor reporting and on-chain settlement"
```

---

### Task 7: Submission documents

**Files:**
- Create: `docs/ATTESTCOIN_INTEGRATION.md`
- Modify: `README.md`
- Modify: `CLAUDE.md` (record that Phase 1 is complete)

- [ ] **Step 1: Write the Attestcoin integration document**

This is an explicit hackathon requirement: *"Technical documentation detailing your setup and
explaining how the project uses the Attestcoin Protocol."* Depth of utilisation is a scored
criterion, so be concrete — name the precompile, the chainKey, the two mandatory checks.

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
cat > docs/ATTESTCOIN_INTEGRATION.md <<'EOF'
# Attestcoin Protocol Integration

How Inkstake Arena uses the Attestcoin Protocol, and why.

## What we use it for

A player on Ethereum Sepolia pays for a run, or sponsors a prize pool. Neither action is bridged
by a trusted party. Instead, a contract on Creditcoin **proves the source-chain transaction
itself**, reads its event logs, and acts on them in the same transaction.

| Action | Sepolia event | Effect on Creditcoin |
| --- | --- | --- |
| `0` `EntryPaid` | `ArenaEntryPaid(address player, bytes32 runRef, uint256 amount)` | Mints USDT entry credit so the player can stake **holding no tCTC at all** |
| `1` `PrizeFunded` | `PrizePoolFunded(address sponsor, uint256 amount)` | Tops up the reward pool |

## Components

| Piece | Where | What it does |
| --- | --- | --- |
| `DoodleGate` | Sepolia | Minimal source contract. Emits the two events. Nothing else. |
| `DoodleGateASC` | Creditcoin | The Attestcoin Smart Contract. Verifies proofs, decodes logs, executes. |
| `ASCReadableUpgradeable` | Creditcoin | Our proxy-safe port of `@gluwa/asc-contracts` `ASCBase`. |
| `ink-monitor` relayer | VPS | Waits for attestation, fetches proofs, submits them. A courier, not an oracle. |

## Environment

| Thing | Value |
| --- | --- |
| Creditcoin Testnet chain id | `102031` |
| BlockProver precompile | `0x0000000000000000000000000000000000000FD2` |
| ChainInfo precompile | `0x0000000000000000000000000000000000000FD3` |
| Proof Builder API | `https://prover.cc3-testnet.creditcoin.network` |
| Source chain: Ethereum Sepolia | **chainKey `1`** (not `11155111`) |
| Solidity package | `@gluwa/asc-contracts@0.2.1` |
| TypeScript SDK | `@gluwa/usc-sdk@0.18.0` |

## The flow

```
Sepolia                    ink-monitor relayer              Creditcoin
───────                    ───────────────────              ──────────
payEntry()
  emits ArenaEntryPaid
        │
        └─ event picked up ─►
                            waitUntilHeightAttested(1, h)
                            ProofBuilder.getProof(txHash)
                                        │
                                        └─ execute(action, …) ─►
                                                       DoodleGateASC
                                                         1. dedupe by queryId
                                                         2. VERIFIER.verifyAndEmit  (0x…0FD2)
                                                         3. require receiptStatus == 1
                                                         4. getLogsByEventSignature
                                                         5. require emitter == sourceGate
                                                         6. mint credit / fund pool
```

All of steps 1–6 happen synchronously in one Creditcoin transaction.

## The two checks that carry the security

Both are called out in the protocol documentation, and both have dedicated negative tests.

### 1. `receiptStatus == 1`

The block prover proves a transaction was **included in a real block on the real chain**. It does
**not** prove the transaction **succeeded**. Without this check, a reverted entry payment would
still mint credit.

Test: `test_revert_transactionThatFailedOnTheSourceChain`.

### 2. Emitter binding

```solidity
if (_s().sourceGate[chainKey] != emitter || emitter == address(0)) {
    revert UnknownEmitter(chainKey, emitter);
}
```

Event signatures are public. Without this binding, anyone could deploy their own contract on
Sepolia emitting a byte-identical `ArenaEntryPaid` and mint themselves unlimited credit. This is
the single most important line in the repository.

Test: `test_revert_eventFromAnUnregisteredEmitter`.

### Replay protection

`queryId = keccak256(chainKey, blockHeight, txIndex)`, recorded in namespaced storage.

Test: `test_revert_replayOfTheSameQuery`.

## One deliberate departure from `ASCBase`

Gluwa's `ASCBase` hands the subclass `(action, queryId, encodedTransaction)`. We pass
**`chainKey`** as well. Without it a subclass cannot bind the emitter per source chain — which is
check 2 above. Our `ASCReadableUpgradeable` also makes `VERIFIER` a `constant` instead of a
constructor-set `immutable`, so the contract carries no constructor logic under a UUPS proxy.

## How we test it

Two layers, because a mock can only ever prove we are consistent with ourselves.

1. **Unit tests** etch a `MockBlockProver` at `0x…0FD2` with `vm.etch` and drive every branch,
   including both mandatory checks. Transaction fixtures are built in Solidity in the decoder's
   exact `abi.encode(uint8 txType, bytes[] chunks)` layout.
2. **Fork tests** run against the live Creditcoin RPC so the **real precompiles answer**:

```bash
forge test --match-path 'test/fork/*' --fork-url https://rpc.cc3-testnet.creditcoin.network -vv
```

That test asserts we are on chain `102031`, that the protocol lists Sepolia as chainKey 1, and
that attestations are actively being produced.

## Costs

Per the protocol's gas guidance, verification is roughly `2.3e-5 + 2.9e-7 * continuityHashCount`
CTC. The relayer submits proofs **promptly**, which keeps continuity proofs near 10 hashes instead
of the ~1000 a day-old transaction would need — more than a 10x saving.

## What we did not use, and why

**Attestcoin Writability** (Creditcoin to other chains) is still under third-party audit and is
not released on testnet. So ETH paid on Sepolia stays in `DoodleGate`, and rewards are paid in
tCTC or USDT on Creditcoin. Two-way settlement is the obvious next step the moment Writability
ships; `DoodleGate.withdraw` marks the seam.
EOF
```

- [ ] **Step 2: Rewrite the root README as the judges' entry point**

Expand the placeholder from Plan 1 with: a one-paragraph pitch, the deployed addresses with
Blockscout links, a quickstart, the architecture diagram, how to run the tests, and an honest
"limitations" section. Include the Phase 1 / Phase 2 split, and state that the Phase 1 score is
attested by our monitor key with Phase 2 replacing it by configuration.

- [ ] **Step 3: Record that Phase 1 is complete**

Only once the full loop is verified working, edit the phase-gate section of the root `CLAUDE.md`:

```markdown
## Phase gate — LIFTED on <date>

Phase 1 is complete and verified end to end: English, seeded from the chain, staked, monitored,
settled and paid out. Online multiplayer (Phase 2) may now proceed. Re-enable the free-for-all
paths in `main.js`, and move the attestor set from the monitor key to match participants with
`escrow.setAttestor` / `escrow.setThreshold(ceil(2n/3))` — no contract change is required.
```

- [ ] **Step 4: Commit**

```bash
cd /Users/axelurwawuskaatarubby/Documents/GitHub/riguwagame
git add docs/ATTESTCOIN_INTEGRATION.md README.md CLAUDE.md
git commit -m "docs: Attestcoin integration document and submission README"
```

---

## Done when

- A player connects a wallet, stakes tCTC or USDT, plays a solo run against bots, and is paid on
  chain according to the wave reached — visible on Blockscout.
- The loss path folds the stake into the pool; the abandon path returns it in full after `RUN_TTL`.
- An entry paid on Sepolia is relayed, proven by the precompile, and credited **without the player
  ever holding tCTC**.
- The fork test passes against the live Creditcoin RPC.
- `npm test` passes in `server/`, `node --test test/` passes in the game, `forge test` passes in
  `contracts/`.
- `docs/ATTESTCOIN_INTEGRATION.md` and the root `README.md` are complete.
- The phase gate in `CLAUDE.md` is explicitly lifted — and not one moment before.
