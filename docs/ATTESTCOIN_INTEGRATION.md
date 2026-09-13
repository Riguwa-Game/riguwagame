# Attestcoin Protocol Integration

How Inkstake Arena uses the Attestcoin Protocol, and the on-chain evidence that it works.

## What we use it for

A player on Ethereum Sepolia pays for a run, or sponsors a prize pool. Neither is bridged by a
trusted party. A contract on Creditcoin **proves the source-chain transaction itself**, reads its
event logs, and acts on them in the same transaction.

| action | Sepolia event | Effect on Creditcoin |
| --- | --- | --- |
| `0` | `ArenaEntryPaid(address player, bytes32 runRef, uint256 amount)` | Mints USDT entry credit, so the player can stake **holding no tCTC at all** |
| `1` | `PrizePoolFunded(address sponsor, uint256 amount)` | Tops up the reward pool |

## Proof that it works

A real payment on Sepolia, relayed and credited on Creditcoin:

| | |
| --- | --- |
| Sepolia `payEntry` | [`0x9ff6a146…bb88cb`](https://eth-sepolia.blockscout.com/tx/0x9ff6a14677c820b1ea73156cb7a36e1959792fdfdfbdf0f3feac42099bbb88cb) — 0.0005 ETH, block 11,695,759 |
| Creditcoin relay | [`0x021ea75f…ed21b5`](https://creditcoin-testnet.blockscout.com/tx/0x021ea75fdc161883a2cefd82530a6e12e973e74b63d4e9702380805151ed21b5) — status 1, 275,996 gas |
| Credit minted | 0.05 USDT (rate: 100 USDT per 1e18 of source value) |

The relay transaction carries three logs, and the first one is the point:

| Emitter | Event |
| --- | --- |
| `0x…0fd2` — **the BlockProver precompile** | `TransactionVerified` (`0x8a8df984…`) |
| `0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1` — USDT | `Transfer` (mint) |
| `0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF` — our ASC | `EntryCredited` |

The protocol's own precompile attested the Sepolia transaction **inside the same Creditcoin
transaction** that minted the credit. No oracle sat in between.

## Components

| Piece | Where | What it does |
| --- | --- | --- |
| `DoodleGate` | Sepolia | Minimal source contract. Emits the two events, nothing else. |
| `DoodleGateASC` | Creditcoin | The Attestcoin Smart Contract. Verifies proofs, decodes logs, executes. |
| `ASCReadableUpgradeable` | Creditcoin | Our proxy-safe port of `@gluwa/asc-contracts` `ASCBase`. |
| `ink-monitor` relayer | server | Waits for attestation, fetches proofs, submits. A courier, not an oracle. |

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

Read live with `server/`'s `npm run check:attestcoin`:

```
supported chains: [(3, 1, "Ethereum", 1), (1, 11155111, "Sepolia ethereum", 1)]
```

Note the second field is the source chain's **EVM chainId**, not a genesis height — which is
exactly the inversion that makes `SOURCE_CHAIN_KEY=1` easy to get wrong.

## The flow

```
Sepolia                    ink-monitor relayer              Creditcoin
───────                    ───────────────────              ──────────
payEntry()
  emits ArenaEntryPaid
        │
        └─ picked up ─────►
                           waitUntilHeightAttested(1, h)
                           ProofBuilder.getProof(txHash)
                                      │
                                      └─ execute(action, …) ─►  DoodleGateASC
                                                                1. dedupe by queryId
                                                                2. VERIFIER.verifyAndEmit (0x…0FD2)
                                                                3. require receiptStatus == 1
                                                                4. getLogsByEventSignature
                                                                5. require emitter == sourceGate
                                                                6. mint credit / fund pool
```

Steps 1–6 all happen synchronously in one Creditcoin transaction.

## The two checks that carry the security

Both are called out in the protocol documentation, and both have dedicated negative tests.

### 1. `receiptStatus == 1`

The block prover proves a transaction was **included in a real block on the real chain**. It does
**not** prove the transaction **succeeded**. Without this check a reverted entry payment would
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

Gluwa's `ASCBase` hands the subclass `(action, queryId, encodedTransaction)`. We pass **`chainKey`**
as well — without it a subclass cannot bind the emitter per source chain, which is check 2 above.
Our `ASCReadableUpgradeable` also makes `VERIFIER` a `constant` rather than a constructor-set
`immutable`, so the contract carries no constructor logic under a UUPS proxy.

## How it is tested

Two layers, because a mock only ever proves we are consistent with ourselves.

1. **Unit tests** etch a `MockBlockProver` at `0x…0FD2` with `vm.etch` and drive every branch,
   including both mandatory checks and every malformed-event shape. Transaction fixtures are built
   in Solidity in the decoder's own `abi.encode(uint8 txType, bytes[] chunks)` layout.
2. **Live checks** against the real chain. `forge test --fork-url` does **not** work: Creditcoin
   blocks carry no `mixHash` and report `difficulty: 0x0`, so Foundry's fork backend rejects them
   with `header validation error: \`prevrandao\` not set`. `contracts/script/check-live.sh` makes
   the same assertions over plain JSON-RPC and works today.

## Operational notes worth knowing

- **Attestation lag is 20–40 minutes** on CC3 testnet. The SDK's default
  `waitUntilHeightAttested` timeout is far shorter; ours is an hour. A timeout silently drops a
  paid entry, so `npm run relay -- <txHash>` exists to recover one.
- **The relayer wallet needs tCTC.** It submits the proof transaction. A fresh attestor key fails
  every submission with `gas required exceeds allowance 0`.
- Submit proofs **promptly**: per the protocol's gas guidance a fresh block needs a ~10-hash
  continuity proof while a day-old one needs ~1000, costing more than 10x as much.

## What we did not use, and why

**Attestcoin Writability** (Creditcoin to other chains) is still under third-party audit and is not
released on testnet. So ETH paid on Sepolia stays in `DoodleGate`, and rewards are paid in tCTC or
USDT on Creditcoin. Two-way settlement is the obvious next step the moment Writability ships;
`DoodleGate.withdraw` marks the seam.
