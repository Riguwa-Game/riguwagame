# Contracts

Foundry project. Four UUPS-upgradeable contracts on Creditcoin Testnet and one plain contract on
Ethereum Sepolia. OpenZeppelin v5.7.0 is vendored in `lib/` (previously git submodules, now
committed directly so a plain clone works).

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
