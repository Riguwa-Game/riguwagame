# Contracts

Foundry project. Four UUPS-upgradeable contracts on Creditcoin Testnet and one plain contract on
Ethereum Sepolia. OpenZeppelin v5.7.0 is vendored in `lib/` (previously git submodules, now
committed directly so a plain clone works).

**Deployed and verified 2026-09-13.** Full table with Blockscout links in `DEPLOYMENT.md`.

| Contract | Chain | Proxy |
| --- | --- | --- |
| `ArenaEscrow` | Creditcoin | `0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7` |
| `DoodleGateASC` | Creditcoin | `0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF` |
| `USDT` | Creditcoin | `0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1` |
| `SeasonRegistry` | Creditcoin | `0xc588f37d165dd2B80AD95532aC5a8a975C732050` |
| `DoodleGate` | Sepolia | `0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484` |

Attestor (`ink-monitor`): `0xFd2ade73561E4700654C9c21932Dda8495e58665` — signs `RunResult` only, never an owner.

## Planned contracts

| Contract | Chain | Purpose |
| --- | --- | --- |
| `ArenaEscrow` | Creditcoin | Stakes, reward pool, solvency accounting, settlement. The core. |
| `USDT` | Creditcoin | Mock test stablecoin, 6 decimals. Testnet only, no real value. |
| `SeasonRegistry` | Creditcoin | Per-season leaderboard: best wave, best score, runs, wins. |
| `DoodleGateASC` | Creditcoin | Attestcoin Smart Contract. Verifies Sepolia proofs, mints credits. |
| `DoodleGate` | Sepolia | Minimal. Emits `ArenaEntryPaid` and `PrizePoolFunded`. |

## Live parameters

| Setting | Value | How to change it |
| --- | --- | --- |
| Max stake | 10 tCTC · 100 USDT | `setMaxStake` — **owner setter, no upgrade** |
| Reward pool | 2,000 tCTC · 100,000 USDT | `fundPool` |
| Payout tiers | wave 5 → 1.5x · 10 → 2x · 15+ → 3x | `setMultiplierTiers`, validated monotonic |
| Attestor threshold | 1 | `setThreshold` — this is the Phase 1 → 2 switch |

**Keep the pool ahead of the cap.** `startRun` reserves `stake x 3` before accepting a stake, so the
pool must hold at least `maxStake x 3` free or the advertised cap is a lie and the run reverts with
`PoolTooSmall` — which wallets report as an opaque "internal error". At 10 and 2,000 the pool backs
66 concurrent max-size runs.

## Rules

- **UUPS on every Creditcoin contract**, ERC-7201 namespaced storage, verified on Blockscout.
- **Most parameters are owner setters, not constants.** Reach for `setMaxStake` / `fundPool` /
  `setMultiplierTiers` / `setAttestor` before reaching for an upgrade.
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
forge coverage --ir-minimum --report summary   # plain `forge coverage` hits stack-too-deep
forge fmt --check
./script/check-live.sh                         # verify the live protocol over JSON-RPC
```

### Forking Creditcoin does not work

`forge test --fork-url https://rpc.cc3-testnet.creditcoin.network` fails with:

```
header validation error: `prevrandao` not set
```

Creditcoin blocks carry no `mixHash` and report `difficulty: 0x0`, and Foundry's fork backend
expects one of them on a post-Merge chain. This is a Foundry/Frontier mismatch, not a problem
with these contracts. `test/fork/AttestcoinFork.t.sol` is kept for when it is fixed, and skips
cleanly without a fork URL.

**Use `./script/check-live.sh` instead.** It makes the same assertions over plain JSON-RPC and
works today: chain id, supported source chains, live attestation height, and the opcode probe.

### Live facts, as observed

```
supported chains: [(3, 1, "Ethereum", 1), (1, 11155111, "Sepolia ethereum", 1)]
```

Note the second field is the source chain's **EVM chainId**, not a genesis height. So
`chainKey 1` is Sepolia (`11155111`) and `chainKey 3` is Ethereum mainnet (`1`) — which is
exactly the inversion that makes `SOURCE_CHAIN_KEY=1` easy to get wrong.
