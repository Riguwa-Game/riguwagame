# BUIDL submission: Riguwa

Paste the section below into the **Details** field of the DoraHacks BUIDL form. It is written in
Markdown, which that editor accepts. Every image is an absolute `raw.githubusercontent.com` URL, so
it renders on DoraHacks without uploading anything.

Everything here is checked against the live deployment. No em dashes, per house style.

---
---

![Riguwa](https://raw.githubusercontent.com/Riguwa-Game/riguwagame/main/docs/images/gameplay.jpg)

# Riguwa

**A ballpoint-doodle survival shooter where the reward is real, and the chain proves you earned it
before it pays.**

Stake tCTC or USDT on a run. Survive the waves. Get paid by how far you got. Or pay your entry on
Ethereum Sepolia and play without ever holding tCTC, because the Attestcoin Protocol proves your
payment on-chain with no oracle in between.

| | |
|---|---|
| **Play it** | https://riguwa.xyz |
| **Code** | https://github.com/Riguwa-Game/riguwagame |
| **Network** | Creditcoin Testnet, chain id `102031` |
| **Explorer** | https://creditcoin-testnet.blockscout.com |
| **Track** | Gaming |

---

## 1. The problem

Web3 games put value on-chain. They do not put **the reason you earned it** on-chain.

- A leaderboard is a database row.
- A reward is an airdrop from a spreadsheet.
- When a game does settle value on-chain, it almost always trusts a server to say who won, and asks
  you to trust that server too.
- When a game reaches across chains, it reaches through a bridge or an oracle operator who must be
  trusted with the answer.

So the asset is trustless and the claim behind it is not. That gap is the whole problem.

## 2. What Riguwa does

The game is a finished first-person survival shooter, drawn in blue ballpoint on lined notebook
paper and rendered **entirely in code**. No models, no textures, no sound files. Every outline,
every enemy, every 8-bit music track is procedural.

On top of it sits a staking layer where **the chain settles the outcome**, and a cross-chain entry
path where **the protocol itself verifies the payment**.

| | |
|---|---|
| **Stake to play** | Stake tCTC or USDT on a run. Reach wave 5 for 1.5x, wave 10 for 2x, wave 15 for 3x. Below wave 5 the stake joins the pool. **There is no free play**, and no console path around it. |
| **Cross-chain entry, no tCTC needed** | Pay on Sepolia. The Attestcoin block-prover precompile verifies that transaction **inside the same Creditcoin transaction** that credits you. |
| **The chain seeds the run** | `startRun` issues a seed from `blockhash`. The game PRNG takes it, so the waves you faced were committed before you played. |
| **Solvency by construction** | `startRun` reserves the full payout ceiling before accepting a stake. The contract can never owe more than it holds, asserted as a fuzz invariant. |

![The staking panel](https://raw.githubusercontent.com/Riguwa-Game/riguwagame/main/docs/images/stake-panel.jpg)

The panel shows both balances and, more usefully, **what the pool can actually back right now**. The
contract cap is 10 tCTC, but the number that matters is `pool.free / 3`, because `startRun` reserves
the full 3x ceiling before it takes your money.

---

## 3. How the Attestcoin Protocol is used

This is the core of the submission, so it is worth being precise.

A player on Ethereum Sepolia pays for a run, or sponsors a prize pool. **Neither is bridged by a
trusted party.** A contract on Creditcoin proves the source-chain transaction itself, reads its
event logs, and acts on them in the same transaction.

| Action | Sepolia event | Effect on Creditcoin |
|---|---|---|
| `0` | `ArenaEntryPaid(address player, bytes32 runRef, uint256 amount)` | Mints USDT entry credit, so the player can stake **holding no tCTC at all** |
| `1` | `PrizePoolFunded(address sponsor, uint256 amount)` | Tops up the reward pool |

### The flow

```
Sepolia                    ink-monitor relayer              Creditcoin
-------                    -------------------              ----------
payEntry()
  emits ArenaEntryPaid
        |
        +-- picked up ---->
                           waitUntilHeightAttested(1, h)
                           ProofBuilder.getProof(txHash)
                                      |
                                      +-- execute(action, ...) -->  DoodleGateASC
                                                                1. dedupe by queryId
                                                                2. VERIFIER.verifyAndEmit (0x...0FD2)
                                                                3. require receiptStatus == 1
                                                                4. getLogsByEventSignature
                                                                5. require emitter == sourceGate
                                                                6. mint credit / fund pool
```

Steps 1 to 6 all happen **synchronously, in one Creditcoin transaction**. The relayer is a courier,
not an oracle: it can choose *when* to deliver a proof, and nothing else. It cannot forge one, and
it cannot change what the proof says.

### Components

| Piece | Where | What it does |
|---|---|---|
| `DoodleGate` | Sepolia | Minimal source contract. Emits the two events, nothing else. |
| `DoodleGateASC` | Creditcoin | The Attestcoin Smart Contract. Verifies proofs, decodes logs, executes. |
| `ASCReadableUpgradeable` | Creditcoin | Proxy-safe port of `@gluwa/asc-contracts` `ASCBase`. |
| `ink-monitor` relayer | server | Waits for attestation, fetches proofs, submits. |

### Environment

| Thing | Value |
|---|---|
| Creditcoin Testnet chain id | `102031` |
| BlockProver precompile | `0x0000000000000000000000000000000000000FD2` |
| ChainInfo precompile | `0x0000000000000000000000000000000000000FD3` |
| Proof Builder API | `https://prover.cc3-testnet.creditcoin.network` |
| Source chain: Ethereum Sepolia | **chainKey `1`**, not `11155111` |
| Solidity package | `@gluwa/asc-contracts@0.2.1` |
| TypeScript SDK | `@gluwa/usc-sdk@0.18.0` |

That `chainKey` is a trap worth flagging for anyone else integrating. Reading the live registry with
`npm run check:attestcoin` returns:

```
supported chains: [(3, 1, "Ethereum", 1), (1, 11155111, "Sepolia ethereum", 1)]
```

The second field is the source chain's **EVM chainId**, not the key. Sepolia's Attestcoin chainKey
is `1`. Using `11155111` fails in a way that looks like a proof problem and is not.

---

## 4. The two checks that carry the bridge

Both live in the contract, not in our infrastructure, and both have dedicated negative tests.

![TransactionVerified emitted by the BlockProver precompile](https://raw.githubusercontent.com/Riguwa-Game/riguwagame/main/docs/images/attestcoin-proof.png)

That is the relay transaction's **first log**. The emitter is **BlockProver**, the precompile at
`0x...0FD2`, not our contract, carrying `chainKey 1` and the Sepolia height it verified. We attest
nothing. The chain does, and the contract refuses to act until it has.

### Check 1: `receiptStatus == 1`

```solidity
if (receipt.receiptStatus != 1) revert SourceTransactionFailed();
```

The block prover proves a transaction was **included in a real block on the real chain**. It does
**not** prove the transaction **succeeded**. Without this check, a reverted entry payment would
still mint credit.

Test: `test_revert_transactionThatFailedOnTheSourceChain`.

### Check 2: emitter binding

```solidity
if (_s().sourceGate[chainKey] != emitter || emitter == address(0)) {
    revert UnknownEmitter(chainKey, emitter);
}
```

Event signatures are public. Without this binding, anyone could deploy their own contract on Sepolia
emitting a byte-identical `ArenaEntryPaid` and mint themselves unlimited credit.

**This is the single most important line in the repository.**

Test: `test_revert_eventFromAnUnregisteredEmitter`.

### Replay protection

`queryId = keccak256(chainKey, blockHeight, txIndex)`, recorded in ERC-7201 namespaced storage.

Test: `test_revert_replayOfTheSameQuery`.

### One deliberate departure from `ASCBase`

Gluwa's `ASCBase` hands the subclass `(action, queryId, encodedTransaction)`. We pass **`chainKey`**
as well, because without it a subclass cannot bind the emitter per source chain, which is check 2
above. `ASCReadableUpgradeable` also makes `VERIFIER` a `constant` rather than a constructor-set
`immutable`, so the contract carries no constructor logic under a UUPS proxy.

---

## 5. Solvency is structural, not a policy

A staking game that can promise more than it holds is not a staking game, it is a queue.

`startRun` reserves the **entire 3x payout ceiling** before it accepts the stake:

```solidity
uint256 ceiling = (amount * $.maxMultiplierBps) / BPS_DENOMINATOR;
if (p.free < ceiling) revert PoolTooSmall(p.free, ceiling);
p.free -= ceiling;
p.reserved += ceiling;
p.activeStake += amount;
```

The invariant, asserted under fuzzing rather than written in a comment:

```
balance(token) == pool.free + pool.reserved + pool.activeStake
```

A consequence worth knowing operationally: the pool must hold at least `maxStake * 3` free, or the
advertised cap reverts with `PoolTooSmall`, which wallets surface as an opaque "internal error".

---

## 6. Live on Creditcoin Testnet, verify it yourself

Every contract is **source-verified on Blockscout**.

![ArenaEscrow verified on Blockscout](https://raw.githubusercontent.com/Riguwa-Game/riguwagame/main/docs/images/verified-contract.png)

### Core contracts, UUPS with ERC-7201 namespaced storage

| Contract | Address |
|---|---|
| **ArenaEscrow**, stakes, pool, settlement | [`0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7`](https://creditcoin-testnet.blockscout.com/address/0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7) |
| **DoodleGateASC**, the Attestcoin Smart Contract | [`0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF`](https://creditcoin-testnet.blockscout.com/address/0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF) |
| **SeasonRegistry**, per-season leaderboard | [`0xc588f37d165dd2B80AD95532aC5a8a975C732050`](https://creditcoin-testnet.blockscout.com/address/0xc588f37d165dd2B80AD95532aC5a8a975C732050) |
| **USDT**, mock test stablecoin, 6 dp | [`0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1`](https://creditcoin-testnet.blockscout.com/address/0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1) |

### Source chain, Ethereum Sepolia

| Contract | Address |
|---|---|
| **DoodleGate**, emits the two events and nothing else | [`0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484`](https://eth-sepolia.blockscout.com/address/0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484) |

Owner and deployer `0x56A2950ddE6B1040d1DCC4b4C4Fc314Bd56eFB0E`. Attestor
`0xFd2ade73561E4700654C9c21932Dda8495e58665`, which signs `RunResult` only and is **never** an owner
key. If it leaks, two transactions retire it.

### Receipts, not claims

| Claim | Proof |
|---|---|
| **Cross-chain entry works** | [Sepolia `payEntry`](https://eth-sepolia.blockscout.com/tx/0x9ff6a14677c820b1ea73156cb7a36e1959792fdfdfbdf0f3feac42099bbb88cb) then [Creditcoin relay](https://creditcoin-testnet.blockscout.com/tx/0x021ea75fdc161883a2cefd82530a6e12e973e74b63d4e9702380805151ed21b5). 0.0005 ETH in, 0.05 USDT credited. |
| **The precompile did the verifying** | That relay transaction's first log is `TransactionVerified`, emitted by `0x...0FD2` itself. |
| **A staked run paid out** | [`settleRun`](https://creditcoin-testnet.blockscout.com/tx/0x322cf5dc365f5b460713a582831b236ca9ad884905f4254e3a477e8954361f33). 1 tCTC staked, wave 12 reached, 2 tCTC paid. |
| **The loop closes itself** | A run staked in [`0x616a462e`](https://creditcoin-testnet.blockscout.com/tx/0x616a462e4cddbf5f55dfb991fc073c16d1c81343e5da53bd3383c389cf10205f) was observed by ink-monitor, signed, and settled in [`0x1d1d4f88`](https://creditcoin-testnet.blockscout.com/tx/0x1d1d4f88ed346a43c4c143682a02007d237c55a5322c41230bdb65e6b06c86b9) at wave 1 with no human in the path. |
| **The protocol is live right now** | `./contracts/script/check-live.sh` prints chain id, supported source chains, and current attestation height. |

---

## 7. How a run actually works

1. **Connect.** Reown AppKit adds and switches to Creditcoin Testnet for you.
2. **Stake.** `startRun(token, amount)` pulls the stake, reserves the 3x ceiling, and emits
   `RunStarted` carrying a seed derived from `blockhash(block.number - 1)`.
3. **Play.** The game seeds its PRNG from that value, so the wave composition was fixed on-chain
   before the first enemy spawned. `ink-monitor` watches the run live over a WebSocket.
4. **Die.** The monitor checks the reported result against **upper bounds** it computes
   independently, signs an EIP-712 `RunResult`, and **submits `settleRun` itself**.
5. **Get paid.** The payout lands before you leave the death screen. You already signed to stake;
   asking you to sign again to *receive* is a bad trade.

![Connecting a wallet](https://raw.githubusercontent.com/Riguwa-Game/riguwagame/main/docs/images/wallet-connect.jpg)

### Why the monitor computes bounds rather than replaying the RNG

An exact RNG replay would be the strictest possible check and also the most brittle: any divergence
between the server's copy and the game's, down to a float, turns an honest player into a rejected
one. Instead the monitor derives **upper bounds** for what a given wave can produce, and rejects
anything above them. A PRNG parity vector generated by the *game's own* implementation guards the
shared seeded randomness.

### Settlement is threshold-signed, so decentralising it needs no redeploy

`settleRun(RunResult, bytes[] sigs)` verifies **N of M** EIP-712 attestations. Phase 1 runs with
threshold 1, the monitor. Moving to a peer quorum is `setAttestor` plus `setThreshold(ceil(2n/3))`
and **no contract change**. A test proves the multi-signer path today.

---

## 8. Architecture

| Path | What is inside | Verify it |
|---|---|---|
| `contracts/` | Four UUPS contracts on Creditcoin, one plain contract on Sepolia | `forge test`, **139 passing**, 95.19% lines |
| `server/` | `ink-monitor`: run monitor over WebSocket, Attestcoin relayer, EIP-712 signer | `npm test`, **35 passing** |
| `game/doodleshooter/` | The game. Vanilla ES modules, **no build step** | `node --test`, **12 passing** |
| `docs/` | Design, implementation plans, Attestcoin integration document | |

**186 tests pass in total.**

### Tech stack

| Layer | What we use |
|---|---|
| Contracts | Solidity 0.8.30, Foundry, OpenZeppelin 5.7 upgradeable, UUPS with ERC-7201 namespaced storage, EVM target `cancun` |
| Attestcoin | `@gluwa/asc-contracts@0.2.1` on-chain, `@gluwa/usc-sdk@0.18.0` off-chain |
| Server | Node 24, TypeScript, viem, `ws`, EIP-712 signing |
| Rendering | three.js, vendored. Scene renders to a buffer of shade, ink id, view-space normals and depth, then a post pass draws outlines from an inverse-depth Laplacian plus hatching, paper grain, ruled lines and the red margin |
| Audio | Procedural WebAudio. Effects and a per-map 8-bit score, no sound files |
| Web3 in the browser | Reown AppKit 1.8, `@wagmi/core`, viem 2 |
| Build | **None.** AppKit, wagmi and viem are pre-bundled once, by hand, into a single ES module committed to `vendor/`, exactly like three.js. The game installs nothing and builds nothing |
| Hosting | Game static on Vercel at `riguwa.xyz`. `ink-monitor` on a VPS at `wss://monitor.riguwa.xyz`, bound to loopback behind nginx with a WebSocket origin allowlist |

![The title screen](https://raw.githubusercontent.com/Riguwa-Game/riguwagame/main/docs/images/menu.jpg)

---

## 9. Security and limitations

We would rather you read this than discover it.

| | |
|---|---|
| **The monitor is a trusted party today** | Threshold 1. It can sign a wrong `RunResult` within the bounds it checks. The contract already verifies N of M, so this is a configuration, not an architecture. |
| **Attestcoin Writability is not used** | Creditcoin to other chains is still under third-party audit and not on testnet. So ETH paid on Sepolia stays in `DoodleGate`, and rewards pay out in tCTC or USDT on Creditcoin. `DoodleGate.withdraw` marks the seam for two-way settlement. |
| **`blockhash` is a weak seed** | It is fine for wave composition, which commits *before* play and is verified after. It is not a lottery and is not used as one. |
| **USDT here is a mock** | `contracts/src/USDT.sol` is a testnet-only token deployed by this project. Not issued by, affiliated with, or endorsed by Tether, and it holds no value. |
| **Attestation lag is 20 to 40 minutes** | Measured on CC3 testnet. The SDK default timeout is far shorter and silently drops a paid entry, so ours is an hour and `npm run relay -- <txHash>` recovers a stuck one. |
| **Online multiplayer is deliberately gated off** | Offline, staked, settled play had to work end to end first. The peer-to-peer code exists and is disabled. |
| **Caps are small on purpose** | 10 tCTC per run, so a public testnet pool cannot be drained by one player. |

---

## 10. What is next

1. **Peer quorum settlement.** `setAttestor` plus `setThreshold`, no redeploy. The test already passes.
2. **Two-way settlement** the moment Attestcoin Writability ships on testnet, so a Sepolia player is
   paid back on Sepolia.
3. **Seasons.** `SeasonRegistry` is deployed and unused in Phase 1. Per-season leaderboards with
   pool-funded prizes.
4. **Online multiplayer**, ungated once the offline staked loop has run in public for a while.

---
---

# Tab "Submission": jawaban per field

Enam field wajib di tab terakhir. Salin satu per satu.

## Project Sector

```
Gaming / GameFi, with cross-chain infrastructure. A staked first-person survival shooter on Creditcoin Testnet whose entry path is verified by the Attestcoin Protocol rather than by a bridge or an oracle operator.
```

## Project Description

```
Riguwa is a staked arena built on a finished first-person survival shooter drawn in blue ballpoint on lined notebook paper and rendered entirely in code, with no models, textures or sound files.

Players stake tCTC or USDT on a run. Reaching wave 5 pays 1.5x, wave 10 pays 2x, wave 15 pays 3x, and a run that ends below wave 5 sends the stake to the pool. There is no free play: the game refuses to start without an active on-chain run.

Two things make the outcome checkable rather than merely recorded. The run seed comes from blockhash at startRun, so the wave composition was committed on-chain before the first enemy spawned. And solvency is structural: startRun reserves the full 3x payout ceiling before it accepts the stake, so the contract can never owe more than it holds, asserted as a fuzz invariant.

Players can also pay their entry on Ethereum Sepolia and never hold tCTC. That path is the Universal Smart Contract integration described below.

Live at https://riguwa.xyz. All nine contracts are source-verified on Blockscout and 186 tests pass across contracts, server and game.
```

## USC Integration Summary

```
We wrote a Universal Smart Contract, DoodleGateASC at 0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF on Creditcoin Testnet, that reads and acts on Ethereum Sepolia state directly. It extends our proxy-safe port of @gluwa/asc-contracts 0.2.1 ASCBase, and off-chain we use @gluwa/usc-sdk 0.18.0 for waitUntilHeightAttested and ProofBuilder.getProof.

What it does. A minimal contract on Sepolia, DoodleGate at 0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484, emits two events and nothing else: ArenaEntryPaid, which credits a player an entry so they can stake while holding no tCTC at all, and PrizePoolFunded, which tops up the reward pool. Our relayer waits for Creditcoin to attest the Sepolia block, fetches the proof, and submits it.

Everything that matters then happens synchronously inside one Creditcoin transaction: dedupe by queryId, call the BlockProver precompile at 0x...0FD2 to verify the source transaction, require receiptStatus == 1, decode the logs, require the emitter is the registered source gate, and mint the credit.

Why that is not a bridge. The relayer is a courier, not an oracle. It chooses when to deliver a proof and nothing else. It cannot forge one and it cannot change what the proof says. The precompile does the attesting, and the contract refuses to act until it has.

Two checks carry the security, and both are in the contract rather than in our infrastructure. First, receiptStatus == 1: the block prover proves a transaction was included in a real block, not that it succeeded, so without this a reverted payment would still mint credit. Second, emitter binding: event signatures are public, so without requiring sourceGate[chainKey] == emitter anyone could deploy a look-alike contract on Sepolia and mint themselves unlimited credit. That is the single most important line in the repository. Both have dedicated negative tests, alongside replay protection keyed on keccak256(chainKey, blockHeight, txIndex).

Proof it works, not a claim. Sepolia payEntry 0x9ff6a14677c820b1ea73156cb7a36e1959792fdfdfbdf0f3feac42099bbb88cb was relayed to Creditcoin in 0x021ea75fdc161883a2cefd82530a6e12e973e74b63d4e9702380805151ed21b5. That relay transaction carries three logs and the first one is the point: TransactionVerified, emitted by the BlockProver precompile itself, carrying chainKey 1 and Sepolia height 11695759. 0.0005 ETH in, 0.05 USDT credited.

One deliberate departure from ASCBase, offered back as feedback. ASCBase hands the subclass (action, queryId, encodedTransaction). We also pass chainKey, because without it a subclass cannot bind the emitter per source chain, which is check two above. We also made VERIFIER a constant rather than a constructor-set immutable, so the contract carries no constructor logic under a UUPS proxy.

One integration trap worth flagging for other teams: Sepolia's Attestcoin chainKey is 1, not its EVM chain id 11155111. The live registry returns tuples whose second field is the EVM chain id, which makes the two easy to swap, and getting it wrong fails in a way that looks like a proof problem and is not.

We did not use Attestcoin Writability, since it is still under third-party audit and not released on testnet. ETH paid on Sepolia therefore stays in DoodleGate and rewards pay out in tCTC or USDT on Creditcoin. DoodleGate.withdraw marks the seam for two-way settlement the moment Writability ships.
```

## GitHub Repository URL

```
https://github.com/Riguwa-Game/riguwagame
```

## Project Deck or Whitepaper (PDF URL)

```
https://github.com/Riguwa-Game/riguwagame/blob/main/docs/riguwa-deck.pdf
```

## Prototype Demo Video URL

Belum ada. Ini satu-satunya field yang harus kamu isi sendiri, karena perlu merekam layar dan mengunggah ke YouTube.
