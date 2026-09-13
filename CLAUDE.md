# Doodle District — Inkstake Arena

A browser FPS with a staking layer on Creditcoin, using the Attestcoin Protocol for trustless
cross-chain entry and prize funding. Hackathon submission: BUIDL CTC 2026 Fall, Gaming track.

## Layout

| Path | What it is | CLAUDE.md |
| --- | --- | --- |
| `game/doodleshooter/` | The game. Vanilla ES modules, three.js and AppKit vendored, **no build step**. | [yes](game/doodleshooter/CLAUDE.md) · [module map](game/doodleshooter/src/CLAUDE.md) |
| `contracts/` | Foundry. Four UUPS contracts on Creditcoin, one plain contract on Sepolia. | [yes](contracts/CLAUDE.md) |
| `server/` | `ink-monitor`: run monitor over WebSocket + Attestcoin relayer. | [yes](server/CLAUDE.md) |
| `docs/` | Design docs and implementation plans. | [yes](docs/CLAUDE.md) |
| `tools/` | `bundle-appkit.sh` — one-time author tool, not a game build step. | — |

## Phase gate — read this before touching multiplayer

**Online / peer-to-peer multiplayer is deferred.** Do not modify `src/net.js`, `src/players.js`, or
any free-for-all code path in `src/main.js`.

The gate lifts only when offline bot mode works end to end: translated, seeded from the chain,
staked, monitored, settled and paid out. When that is verified, **edit this section explicitly** to
record it, then begin Phase 2.

Phase 2 needs **no contract change**: `settleRun` verifies N-of-M attestations, so moving from the
monitor key to peer quorum is `setAttestor` plus `setThreshold(ceil(2n/3))`. A test proves it.

## Hard rules

- **All code, comments, identifiers and documentation in English.**
  `game/doodleshooter/test/english-only.test.mjs` enforces it.
- **Never add a build step or package manager to `game/doodleshooter/`.** It must stay a static
  folder. Libraries are vendored as ES modules into `vendor/`. Pre-bundling one by hand into
  `vendor/` is fine; requiring a build to *run* the game is not.
- **Never commit `.env`.** `contracts/.env` and `server/.env` hold live private keys.
- **Contracts are UUPS-upgradeable and verified on Blockscout.** Non-negotiable.
- **Tests before implementation.** Foundry for contracts, `node --test` elsewhere.
- **Every run is staked.** `begin()` refuses without an active on-chain run. Do not add a free-play
  path — including "just for testing".

## Deployed and live

| Contract | Chain | Address |
| --- | --- | --- |
| `ArenaEscrow` | Creditcoin | `0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7` |
| `DoodleGateASC` | Creditcoin | `0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF` |
| `USDT` (mock) | Creditcoin | `0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1` |
| `SeasonRegistry` | Creditcoin | `0xc588f37d165dd2B80AD95532aC5a8a975C732050` |
| `DoodleGate` | Sepolia | `0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484` |

Owner / deployer `0x56A2950ddE6B1040d1DCC4b4C4Fc314Bd56eFB0E` ·
attestor `0xFd2ade73561E4700654C9c21932Dda8495e58665` (signs `RunResult` only, never an owner).

Full table with explorer links in `contracts/DEPLOYMENT.md`.

| Service | Where | Host |
| --- | --- | --- |
| The game | `https://riguwa.xyz` | Vercel, project `inkstake-arena` |
| `ink-monitor` | `wss://monitor.riguwa.xyz` | VPS `43.159.63.76`, loopback `:8920` behind nginx |

The Vercel hostname is a deployment address, not an entry point: it is not registered with Reown
and the monitor's origin allowlist rejects it. One canonical origin. Deployment steps, and the
rules for sharing that VPS with unrelated projects, are in `docs/DEPLOYMENT.md`.

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
| EVM target | `cancun` minus blob opcodes — see `contracts/CLAUDE.md` |
| Reown AppKit project | `4553a4639c46b13a8f3da08c527a28e5` (riguwa.xyz) |
| Production domain | `riguwa.xyz` (no `www`) · monitor at `wss://monitor.riguwa.xyz` |

## Things that bit us, so they do not bite you again

- **The monitor wallet needs tCTC.** It submits relay and settlement transactions. A fresh attestor
  key fails everything with `gas required exceeds allowance 0`.
- **Attestation lag is 20–40 minutes.** The SDK's default `waitUntilHeightAttested` timeout is far
  shorter and silently drops a paid entry. Ours is an hour; `npm run relay -- <txHash>` recovers one.
- **Keep the pool ahead of the cap.** `startRun` reserves `stake x 3`, so the pool must hold at
  least `maxStake x 3` free or the advertised cap reverts with `PoolTooSmall` — which wallets
  report as an opaque "internal error".
- **`forge test --fork-url` cannot fork Creditcoin** (`prevrandao not set`). Use
  `contracts/script/check-live.sh`.
- **Proxy verification needs `--skip-is-verified-check`.** All four `ERC1967Proxy` deployments share
  identical runtime bytecode, so forge wrongly reports three of them as already verified.

## Documents

`docs/brainstorms/2026-09-13-inkstake-arena-design.md` records why the trust model, the phase split
and the pool-solvency design are what they are. Read it before changing anything architectural.
`docs/ATTESTCOIN_INTEGRATION.md` is the submission's technical integration document.
