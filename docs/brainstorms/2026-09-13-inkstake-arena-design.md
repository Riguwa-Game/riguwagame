# Inkstake Arena — Design

**Project:** Doodle District — Inkstake Arena
**Event:** BUIDL CTC 2026 Fall (Creditcoin / Credit Labs), Gaming track
**Date:** 2026-09-13
**Status:** Approved design. No implementation started.

---

## 1. What we are building

`game/doodleshooter` is a finished browser FPS — a survival shooter drawn in blue ballpoint on
lined notebook paper, rendered entirely procedurally with three.js. No models, no textures, no
sound files, no build step. It ships as a static site.

We are adding an on-chain layer on Creditcoin so that a player can **stake** value on a run,
**play against bots**, and **be paid a reward if they win** — and so that the entry fee and the
prize pool can arrive **from Ethereum Sepolia**, proven trustlessly by the **Attestcoin Protocol**.

### 1.1 Phase gate

Work is staged. The existing online free-for-all mode is **deferred**.

| | Phase 1 — now | Phase 2 — after Phase 1 ships |
| --- | --- | --- |
| Game mode | Solo vs bots (waves) | + Online free-for-all |
| Stake | tCTC or USDT, max 100 | same |
| Attestcoin integration | Cross-chain entry + sponsorship | unchanged |
| Who attests the result | VPS monitor, threshold 1 | Match participants, threshold `ceil(2n/3)` |

The online code (`net.js`, `players.js`, FFA paths in `main.js`) is **left in place and gated
off**, not deleted. Phase 2 lifts the gate.

---

## 2. The central problem, and how we answer it

The game's online mode is peer-to-peer with the host's browser keeping score. The moment real
value is staked, "the host says I won" is free money. In solo-vs-bots there are no peers at all,
so there is not even a witness.

Three honest ways to answer "how does the chain know you won?": a server, a replay verifier, or a
quorum of peers. **Phase 1 uses a server** — a lightweight monitor on a VPS that watches the run
live and signs the outcome. **Phase 2 uses peer quorum.**

Critically, the contract does not know or care which of these it is talking to. It knows only an
**attestor set and a threshold**:

```solidity
settleRun(RunResult calldata r, bytes[] calldata sigs)
    require(validAttestations(r, sigs) >= threshold);
```

| | `attestors` | `threshold` |
| --- | --- | --- |
| Phase 1 | `[monitorKey]` | `1` |
| Phase 2 | match participants | `ceil(2n/3)` |

The struct and the function are **identical across both phases**. Moving to Phase 2 is a
configuration change made by the owner, not a rewrite. Phase 1 work is not thrown away.

### 2.1 Stated limitation

In Phase 1 the score is trusted to our monitor key. We state this plainly rather than hide it.

This does **not** conflict with the hackathon theme. "Without relying on centralized oracle
operators" refers to **cross-chain data** — and every piece of cross-chain data in this system
(entry payments, prize sponsorship) is proven by the Attestcoin block-prover precompile with no
oracle at all. The PvE score attestation is a separate, ordinary game-industry concern, it is
key-rotatable by the owner, and Phase 2 replaces it with a decentralised quorum.

---

## 3. Attestcoin Protocol integration

This is the graded centrepiece and it is unaffected by the phase gate.

### 3.1 What the protocol actually gives us

Attestcoin **Readability** lets a contract on Creditcoin prove that a transaction really happened
on a source chain, then read its event logs and act on them — synchronously, in one transaction,
with no oracle.

| Fact | Value |
| --- | --- |
| Creditcoin Testnet EVM chain id | `102031` |
| Creditcoin RPC | `https://rpc.cc3-testnet.creditcoin.network` |
| Explorer (verification target) | `https://creditcoin-testnet.blockscout.com` |
| BlockProver precompile | `0x0000000000000000000000000000000000000FD2` |
| ChainInfo precompile | `0x0000000000000000000000000000000000000FD3` |
| Proof Builder API | `https://prover.cc3-testnet.creditcoin.network` |
| Solidity package | `@gluwa/asc-contracts@0.2.1` |
| TypeScript SDK | `@gluwa/usc-sdk@0.18.0` |
| Source chain: Ethereum Sepolia | **chainKey `1`** (not `11155111`) |
| Cost per verification | approx. `2.6e-5` CTC when proved promptly |

`EvmV1Decoder` is entirely `internal pure`, so **no library linking is required**.

**Writability** (Creditcoin to other chains) is still under third-party audit and is **not
released on testnet**. It is therefore out of scope, and documented as roadmap. The code marks the
exact seam where it plugs in.

### 3.2 Our two flows

Following the protocol's own stated best practice — one source contract, unambiguous
purpose-built event names — a single Sepolia contract emits both events, and a single ASC on
Creditcoin handles both via `ASCBase`'s `action` discriminator.

| action | Sepolia event | Effect on Creditcoin |
| --- | --- | --- |
| `0` `EntryPaid` | `ArenaEntryPaid(address player, bytes32 runRef, uint256 amount)` | Mints USDT entry credit to the player, so they can play **holding neither tCTC nor USDT** |
| `1` `PrizeFunded` | `PrizePoolFunded(address sponsor, uint256 amount)` | Tops up the house reward pool |

### 3.3 Verification sequence inside the ASC

```
execute(action, chainKey, blockHeight, encodedTx, merkleRoot, siblings,
        lowerEndpointDigest, continuityRoots)

  1. queryId = keccak(chainKey, blockHeight, txIndex)
     require(!processedQueries[queryId])                 <- replay protection
  2. VERIFIER.verifyAndEmit(...)                         <- precompile 0x0FD2
  3. require(receipt.receiptStatus == 1)                 <- MANDATORY, see below
  4. logs = EvmV1Decoder.getLogsByEventSignature(receipt, SIG)
  5. require(logs[0].address_ == sourceGate[chainKey])   <- MANDATORY, see below
  6. dispatch on `action`, run business logic
```

Two checks carry the whole security of the bridge and both are called out explicitly in the
protocol docs:

- **`receiptStatus == 1`.** The precompile proves a transaction was *included in a real block*.
  It does **not** prove the transaction *succeeded*. Skipping this check would let a reverted
  entry payment mint credits.
- **Emitter binding.** Without `sourceGate[chainKey]`, anyone could deploy their own contract on
  Sepolia that emits a byte-identical `ArenaEntryPaid` event and mint themselves unlimited
  credits. This is the single most important line in the repository.

---

## 4. Contracts

Four UUPS-upgradeable contracts on Creditcoin, one plain contract on Sepolia. Every Creditcoin
contract is **verified on Blockscout**.

OpenZeppelin **v5.7.0** is already vendored in `contracts/lib/`, so all upgradeable contracts use
**ERC-7201 namespaced storage**, which makes storage-layout collisions across upgrades
structurally impossible.

### 4.1 `DoodleGate` — Ethereum Sepolia, plain, ~40 lines

Deliberately minimal, per protocol guidance: source-chain logic should do as little as possible
and exist mainly to emit events.

```solidity
event ArenaEntryPaid(address indexed player, bytes32 indexed runRef, uint256 amount);
event PrizePoolFunded(address indexed sponsor, uint256 amount);

function payEntry(bytes32 runRef) external payable;   // requires msg.value > 0
function fundPrize() external payable;                // requires msg.value > 0
function withdraw(address to) external onlyOwner;
```

### 4.2 `USDT` — test stablecoin, UUPS, 6 decimals

A **mock test stablecoin deployed by this project for hackathon purposes only**. It is not
affiliated with Tether and holds no real value. Name and symbol are `USDT` at the project owner's
explicit request; the NatSpec and README state the mock status prominently.

- ERC-20, 6 decimals
- `mint(address,uint256)` restricted to owner and the ASC
- `faucet()` — capped, rate-limited self-service for testers
- UUPS, owner-authorised upgrades

### 4.3 `ArenaEscrow` — UUPS, the core

Holds stakes, holds the reward pool, and enforces solvency.

```solidity
struct Run {
    address player;
    address token;        // address(0) == native tCTC
    uint256 stake;
    uint256 reserved;     // payout ceiling locked at start
    bytes32 seed;
    uint64  startedAt;
    uint64  deadline;
    RunState state;       // Active | Settled | Abandoned
}

struct RunResult {        // EIP-712 signed payload
    bytes32 runId;
    address player;
    uint32  waveReached;
    uint64  score;
    uint64  endedAt;
}

struct Tier {             // payout schedule, owner-configurable
    uint32 minWave;       // inclusive lower bound
    uint32 multiplierBps; // 15_000 == 1.5x
}
```

EIP-712 domain: `name = "InkstakeArena"`, `version = "1"`, `chainId = 102031`,
`verifyingContract = ArenaEscrow proxy`.

#### Entry points

| function | notes |
| --- | --- |
| `startRun(address token, uint256 amount)` | payable for native; caps, reserves, seeds |
| `settleRun(RunResult r, bytes[] sigs)` | threshold attestations; pays or absorbs |
| `abandonRun(bytes32 runId)` | after `deadline`; returns stake, releases reserve |
| `fundPool(address token, uint256 amount)` | owner or ASC |
| `setAttestor(address, bool)` / `setThreshold(uint256)` | owner; this is the phase switch |
| `setMaxStake(address token, uint256)` | owner |
| `setMultiplierTiers(Tier[])` | owner, validated monotonic |

#### `startRun` — the solvency gate

`nonce` is a per-player counter (`runNonce[msg.sender]++`), which makes every `runId` unique
per player without any global state. A player may hold **only one Active run at a time**; starting
a second reverts.

```
require(activeRun[msg.sender] == bytes32(0));        // one run at a time
require(amount > 0 && amount <= maxStake[token]);
maxPayout = amount * maxMultiplierBps / 10_000;      // 3x
require(pool[token].free >= maxPayout);              // <-- refuse if we cannot pay
pool[token].free     -= maxPayout;
pool[token].reserved += maxPayout;
seed     = keccak256(abi.encodePacked(blockhash(block.number - 1), msg.sender, nonce));
runId    = keccak256(abi.encodePacked(address(this), block.chainid, msg.sender, nonce));
deadline = block.timestamp + RUN_TTL;                // 2 hours
```

The reward pool can therefore **never be promised more than it holds**, no matter how many players
arrive. This is asserted as a fuzz invariant:

```
balance(token) >= pool[token].reserved + sum(stake of Active runs)
```

On `blockhash`: a validator could in principle influence the seed. For a game seed committed
*before* play this is acceptable, and it is documented rather than papered over.

#### Payout

Basis points throughout; no floating point. Tiers are configurable but validated monotonic. They
were chosen to line up with the game's existing checkpoint rhythm, which already unlocks every
5 waves.

| Wave reached | Multiplier | bps |
| --- | --- | --- |
| `< 5` | loss — stake is absorbed into the pool | `0` |
| `5 – 9` | 1.5x | `15000` |
| `10 – 14` | 2.0x | `20000` |
| `>= 15` | 3.0x | `30000` (`maxMultiplierBps`) |

`settleRun` releases the reservation exactly once, pays the player on a win or folds the stake
into `pool.free` on a loss, and calls `SeasonRegistry.recordRun`.

`abandonRun` is the safety valve: if the monitor dies or never signs, the player is made whole
after `RUN_TTL`. Without it, a monitor outage would lock funds permanently.

Native and ERC-20 payout paths both use checks-effects-interactions and a reentrancy guard.

### 4.4 `SeasonRegistry` — UUPS

Per-season, per-player: `bestWave`, `bestScore`, `runs`, `wins`, `totalStaked`, `totalWon`.
`recordRun` is callable only by `ArenaEscrow`.

Elo is **not** in Phase 1 — Elo is a pairwise PvP rating and is meaningless against bots. Phase 2
adds it when there are real opponents.

### 4.5 `DoodleGateASC` — UUPS

Inherits `ASCReadableUpgradeable`, our own port of `@gluwa/asc-contracts`'s `ASCBase` with two
changes required for proxies:

- `VERIFIER` becomes an `address constant` (`0x…0FD2`) instead of an `immutable` set in a
  constructor, so there is no constructor logic at all.
- `processedQueries` moves into ERC-7201 namespaced storage.

State: `sourceGate[chainKey] => address`, `entryRateBps`, `maxMintPerQuery`.
Owner-only: `setSourceGate`, `setEntryRate`, `setMaxMintPerQuery`.

---

## 5. `ink-monitor` — the VPS service

One small Node + TypeScript process doing two jobs. Chosen to stay light, as requested.

### 5.1 Run monitor (WebSocket)

The browser opens a socket and sends **compact run events** — wave started, enemy killed, damage
taken, player died — not 60 Hz state. Bandwidth is negligible.

Admission and plausibility rules:

- A session is accepted only if a matching `RunStarted` event exists on-chain for that `runId`
  and that player's address.
- Wave numbers must increase monotonically with no skips.
- A minimum wall-clock time per wave is enforced; wave 10 cannot be cleared in three seconds.
- Kill counts are checked against the wave composition **derived from the on-chain seed** — the
  monitor computes independently what should have spawned.
- Heartbeats; on disconnect the run ends at the last confirmed wave rather than hanging.

On run end the monitor signs the `RunResult` with EIP-712 and hands the signature to the client,
which submits `settleRun`. The monitor can also submit it directly if the client vanishes.

### 5.2 Attestcoin relayer

The same process watches `DoodleGate` on Sepolia, and for each event:

1. `chainInfoProvider.waitUntilHeightAttested(1, blockHeight)`
2. `new ProofBuilder(1, PROOF_BUILDER_URL).getProof(txHash)`
3. `DoodleGateASC.execute(action, …proof…)` on Creditcoin

This makes cross-chain entry **gasless for the player** — they never need tCTC, which is the whole
point of the "pay on Ethereum, play on Creditcoin" claim. Proofs are submitted promptly, which per
the protocol's own gas guidance keeps continuity proofs short and costs roughly 10x lower than
proving stale transactions.

---

## 6. Game changes

The game's two defining constraints are preserved: **zero build step** and **zero runtime
dependencies beyond what is vendored**.

### 6.1 Translation to English

All Chinese strings are replaced **in place** with English. No i18n table, no translation library —
the project's own README is already in English and already contains every canonical name (Doodle
District, Doodle Mexico, The Doodler, The Eraser, The Inkblot, Grunts, Rushers, Bombers, Snipers,
Flyers, Heavies, Shield bearers, rifle / shotgun / sniper / katana). Machine translation would
produce worse copy than the text that already exists, and would add a dependency to a
zero-dependency codebase.

Scope: roughly 1,460 Chinese characters, concentrated in `main.js` (1,063) and `hud.js` (240),
with the remainder in `weapons.js`, `player.js`, `enemies.js`, `level.js` and `net.js`.
`index.html` also changes: `lang="zh-CN"` to `lang="en"`, and the title to `Doodle District`.

### 6.2 Seeded PRNG

`util.js` already funnels 243 of the game's random calls through `rand` / `randInt` / `choose`, so
the seeded generator drops into **one place**. The remaining direct `Math.random()` call sites are
audited; the ones inside `players.js` and `net.js` are online-only and out of Phase 1 scope, and
purely cosmetic ones (particles, audio jitter) are deliberately left alone.

A fixed-timestep refactor is **not** required. That was only ever needed for replay-based
verification, which we did not choose.

### 6.3 Wallet: Reown AppKit

Connection goes through **Reown AppKit** with its ethers adapter, not a hand-rolled EIP-1193 flow.
AppKit is an npm package, which collides with the zero-build-step rule, so it is **pre-bundled
once** by `tools/bundle-appkit.sh` into a single browser ES module and committed to `vendor/` —
exactly the treatment three.js and peerjs already get. Verified before planning: AppKit 1.8.23 plus
the ethers adapter bundle cleanly at 4.4 MB raw, **1.2 MB gzipped**, with no Node built-ins to shim.
The bundler is an author tool; the game itself builds nothing and installs nothing.

Reown project id `b56e18d47c72ab683b10814fe9495694` is Reown's **public documentation id, valid on
localhost only**. Before deploying to a real domain, a project must be registered at
dashboard.reown.com and its id swapped in — wallets verify `metadata.url` against the registered
domain, and a mismatch surfaces as a failed or untrusted connection.

### 6.4 New modules

```
tools/bundle-appkit.sh        one-time AppKit bundler (author tool, not a game build step)
public/ctc.png                Creditcoin mark
public/usdt.svg, usdt.png     Tether mark; provenance recorded in public/README.md
vendor/appkit/appkit.bundle.js  Reown AppKit + ethers adapter, pre-bundled ESM
vendor/ethers/ethers.min.js     ethers v6 ESM
src/chain/config.js           addresses, ABIs, chain params, Reown project id, logo paths
src/chain/wallet.js           AppKit modal, account subscription, signer access
src/chain/arena.js            startRun / settleRun / pool reads
src/net/monitor.js            WebSocket client to ink-monitor
```

Touch points in existing code are deliberately small: a stake panel on the main menu, a hook where
a solo run begins, and a hook at `showDead()` where a run ends.

### 6.5 Gated-off code

`net.js`, `players.js` and the FFA branches in `main.js` are left intact behind a feature flag.
They are Phase 2 material and must not be modified until the gate is lifted.

---

## 7. Testing strategy

The contracts hold value and their security rests on signature verification and pool accounting,
so the test suite is treated as a primary deliverable. Implementation is **test-first (TDD)**:
tests are written and observed failing before the contract is written.

### 7.1 Testing a precompile that does not exist locally

`0x…0FD2` is a native Creditcoin precompile with no bytecode on a local EVM. Two layers:

1. **Unit tests** — `vm.etch` a `MockBlockProver` at `0x…0FD2` whose result is controllable. This
   mirrors the harness pattern used by Gluwa's own example repositories.
2. **Fork tests** — `forge test --fork-url https://rpc.cc3-testnet.creditcoin.network`, so the
   **real precompile answers**, driven by a real proof for a real Sepolia transaction. This is what
   proves the integration is genuinely live rather than merely passing against our own mock.

Fixture `encodedTransaction` bytes are generated once from a real Sepolia transaction using the
`@gluwa/usc-sdk` encoding module and committed as JSON, so `EvmV1Decoder` is exercised against
real bytes.

### 7.2 `ArenaEscrow`

**Positive.** start to settle to payout on both currencies; pool grows correctly on a loss;
`SeasonRegistry.recordRun` receives correct arguments; `abandonRun` returns the exact stake.

**Edge.**
- Multiplier boundaries at exactly wave 4/5, 9/10, 14/15.
- Cap of 100 in **both decimal systems** — tCTC at 18 decimals, USDT at 6. A classic source of bugs.
- `startRun` refused when the pool cannot cover the payout ceiling.
- Reservation released **exactly once**: settle-then-abandon, abandon-then-settle, settle twice.
- Payout rounding never leaks wei.
- Settle exactly at `deadline` versus one second after.
- Winner is a contract that attempts reentrancy — native path and ERC-20 path.

**Negative.** Every one of these must revert: stake above cap; stake of zero; `msg.value` mismatch
on the native path; ERC-20 path with no approval; settle with a signature from a non-attestor;
settle with a valid signature over a **different `runId`**; settle with a signature from a
**different chainId domain**; duplicate signatures counted twice; signature bytes malformed or
truncated; malleable signature with `s > n/2` (rejected by OpenZeppelin `ECDSA`); settle twice;
settle after abandon; abandon before deadline; **starting a second run while one is Active**;
`setAttestor` / `setThreshold` / `setMaxStake` by a non-owner; non-monotonic multiplier tiers.

### 7.3 `DoodleGateASC`

**Positive.** action 0 mints the entry credit; action 1 funds the pool; `queryId` recorded.

**Edge.** Transaction containing many logs — only the matching signature is selected. Multiple
matching events in one transaction — the "first only" policy is explicit and tested. Separate
`chainKey` registrations coexist.

**Negative.** Replay of the same `queryId`; `receiptStatus == 0`; **emitter not equal to the
registered `sourceGate[chainKey]`** — the single most important test in the repository; unregistered
`chainKey`; unknown `action`; no matching log; mint above `maxMintPerQuery`; `setSourceGate` by a
non-owner.

### 7.4 `SeasonRegistry`, `USDT`, `DoodleGate`

`recordRun` only from `ArenaEscrow`; best-wave and best-score only ever improve; season rollover.
USDT faucet rate limit and cap; mint restricted to owner and ASC. `DoodleGate` emits correct
arguments; zero value reverts; withdraw is owner-only.

### 7.5 Upgrade safety — all four UUPS proxies

`initialize` twice reverts; `_authorizeUpgrade` by a non-owner reverts; owner upgrade succeeds;
**state survives the upgrade** (deploy a V2 with an added variable and assert that existing runs,
pool balances and reservations are intact); the implementation contract cannot be initialised
directly.

### 7.6 Fuzz and invariant

Fuzz stake amounts, token choice and wave reached. The standing invariant across all handler
sequences:

```
balance(token) >= pool[token].reserved + sum(stake of Active runs)
```

and: a settled run can never be settled or abandoned again.

### 7.7 Scenario tests drawn from the real game

Test parameters come from the actual codebase, not invented numbers — waves, `maxAlive` growth,
the boss every fifth wave, and the checkpoint rhythm at waves 5/10/15 are read from
`main.js:startWave`. Scenarios: a player dying on wave 4 (loss); surviving to exactly wave 5
(first winning tier); reaching wave 15+ (cap); disconnecting mid-run so the monitor never signs,
followed by `abandonRun`.

### 7.8 Quality gates

`forge coverage` at 90% lines or better on our own contracts; `forge fmt --check`; the existing
`.github/workflows/test.yml` extended to run unit tests always and fork tests on demand.

---

## 8. Risks and open limitations

Stated plainly, because concealing them is worse than having them.

| Risk | Mitigation |
| --- | --- |
| Phase 1 score is trusted to the monitor key | Documented openly; key is owner-rotatable; Phase 2 replaces it with peer quorum; the contract already supports the swap |
| Monitor outage locks a player's stake | `abandonRun` after `RUN_TTL` returns funds; needs no cooperation from us |
| `blockhash` seed is validator-influenceable | Seed is committed before play; acceptable for a game seed; documented |
| Reward pool drained by the public | Hard cap of 100 per run plus payout-ceiling reservation at `startRun`; insolvency is structurally impossible |
| Attestcoin Writability unavailable on testnet | Out of scope; ETH paid on Sepolia stays in `DoodleGate`; the code marks the seam where two-way settlement lands |
| Verified-deployment friction on Blockscout | Verification is a checklist step in the plan, not an afterthought |
| USDT naming overlaps a real-world asset | Testnet-only mock; status stated prominently in NatSpec, README and the submission; named at the owner's explicit direction |

---

## 9. Deliverables

- `contracts/` — five contracts, full Foundry test suite, deploy and verify scripts
- `server/` — `ink-monitor` (run monitor + Attestcoin relayer)
- `game/doodleshooter/` — fully English, seeded, Reown-wallet-enabled, monitor-connected, with
  token marks in `public/`
- `tools/bundle-appkit.sh` — one-time AppKit bundler, so the vendored artifact is reproducible
- `CLAUDE.md` at the repository root and in `contracts/`, `game/doodleshooter/`,
  `game/doodleshooter/src/` and `server/`
- `docs/ATTESTCOIN_INTEGRATION.md` — the technical integration document the hackathon requires
- Root `README.md` as the judges' entry point
- Repository flattened into a single monorepo with one commit history
