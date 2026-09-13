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
- `evm_version = "cancun"` and `via_ir = true`. IR avoids stack-too-deep in several contracts.

### Why cancun, and what Creditcoin actually supports

Gluwa's own example repos pin `shanghai`, but they also pin OpenZeppelin 5.1. OZ 5.7's
`Math.sol` pulls in `Bytes.sol`, which emits `MCOPY` — a Cancun opcode — so Shanghai will not
compile at all.

Creditcoin Testnet was probed directly with `eth_call` plus a state override, injecting raw
bytecode for each opcode:

| Opcode | Result |
| --- | --- |
| `PUSH0` (Shanghai, `0x5f`) | supported |
| `MCOPY` (Cancun, `0x5e`) | **supported** |
| `TSTORE` / `TLOAD` (Cancun, `0x5c`/`0x5d`) | **supported** |
| `BLOBBASEFEE` (Cancun, `0x4a`) | **rejected** — `InvalidCode(Opcode(74))` |

A deliberately invalid opcode returned the same rejection shape, which is what makes the probe
trustworthy rather than a false positive.

So Creditcoin is Cancun **minus the blob opcodes** — typical for a Frontier EVM, which has no
blobs to price. That is safe for us: solc only emits `BLOBBASEFEE` if the source reads
`block.blobbasefee`, and nothing here does. **Never use `block.blobbasefee`.**

To re-run the probe:

```bash
curl -s -X POST https://rpc.cc3-testnet.creditcoin.network -H 'Content-Type: application/json' \
  -d '{"jsonrpc":"2.0","id":1,"method":"eth_call","params":[
        {"to":"0x00000000000000000000000000000000DeaDBeef","data":"0x"},"latest",
        {"0x00000000000000000000000000000000DeaDBeef":{"code":"0x6020600060005e600160005260206000f3"}}]}'
```

A result of `0x…01` means `MCOPY` executed.

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
