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
or any free-for-all code path in `src/main.js`.

The gate lifts only when offline bot mode works end to end: translated to English, seeded from
an on-chain seed, staked, monitored by `ink-monitor`, settled on-chain, and paid out. When that
is verified working, **edit this section explicitly** to record that the gate is lifted, then
begin Phase 2.

The online code is left intact and gated off, not deleted. It is Phase 2 material.

## Hard rules

- **All code, comments, identifiers and documentation in English.** The game shipped with Chinese
  UI strings for a while; they have been reverted. `game/doodleshooter/test/english-only.test.js`
  guards this — do not reintroduce any CJK text.
- **Never add a build step or package manager to `game/doodleshooter/`.** It must stay a static
  folder. New libraries are vendored as ES modules into `vendor/`, exactly as three.js and peerjs
  are. Pre-bundling a dependency once, by hand, into `vendor/` is fine; requiring a build to run
  the game is not.
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
| Reown AppKit project id | `b56e18d47c72ab683b10814fe9495694` (Reown's public docs id — **localhost only**; register a real project before deploying to a domain) |

## Repository history

This was three separate git repositories until 2026-09-13. The game's original 43-commit history
is preserved as a bundle outside the tree:

```
~/Documents/GitHub/riguwagame-game-history-backup.bundle
git clone riguwagame-game-history-backup.bundle recovered-game
```

That history is where the original English UI strings came from — commit `8d8fad9` had translated
the whole game to Chinese, and its parent is the English original.

## Documents

Read `docs/brainstorms/2026-09-13-inkstake-arena-design.md` before making architectural changes.
It records why the trust model, the phase split and the pool-solvency design are what they are.
Implementation plans live in `docs/plans/`.
