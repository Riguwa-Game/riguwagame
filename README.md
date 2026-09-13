# Doodle District — Inkstake Arena

A first-person survival shooter drawn in blue ballpoint on lined notebook paper, with a staking
and reward layer on Creditcoin and **cross-chain entry proven trustlessly by the Attestcoin
Protocol**.

Built for **BUIDL CTC 2026 Fall** — Gaming track.

Stake tCTC or USDT, survive the waves, and get paid by the wave you reached: 1.5x at wave 5, 2x at
wave 10, 3x at wave 15. Or pay your entry on **Ethereum Sepolia** and play on Creditcoin without
ever holding tCTC — the Attestcoin block-prover precompile verifies your Sepolia payment on-chain,
inside the same Creditcoin transaction that credits you.

## The proof

A real Sepolia payment, relayed and credited on Creditcoin:

| | |
| --- | --- |
| Sepolia `payEntry` | [`0x9ff6a146…bb88cb`](https://eth-sepolia.blockscout.com/tx/0x9ff6a14677c820b1ea73156cb7a36e1959792fdfdfbdf0f3feac42099bbb88cb) |
| Creditcoin relay | [`0x021ea75f…ed21b5`](https://creditcoin-testnet.blockscout.com/tx/0x021ea75fdc161883a2cefd82530a6e12e973e74b63d4e9702380805151ed21b5) |
| Staked run settled | [`0x322cf5dc…361f33`](https://creditcoin-testnet.blockscout.com/tx/0x322cf5dc365f5b460713a582831b236ca9ad884905f4254e3a477e8954361f33) |

The relay transaction's first log is `TransactionVerified`, emitted by the **BlockProver
precompile itself**. No oracle sat in between. See [`docs/ATTESTCOIN_INTEGRATION.md`](docs/ATTESTCOIN_INTEGRATION.md).

## Deployed contracts

All source-verified.

### Creditcoin Testnet (`102031`)

| Contract | Address |
| --- | --- |
| `ArenaEscrow` | [`0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7`](https://creditcoin-testnet.blockscout.com/address/0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7) |
| `DoodleGateASC` | [`0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF`](https://creditcoin-testnet.blockscout.com/address/0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF) |
| `USDT` (mock) | [`0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1`](https://creditcoin-testnet.blockscout.com/address/0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1) |
| `SeasonRegistry` | [`0xc588f37d165dd2B80AD95532aC5a8a975C732050`](https://creditcoin-testnet.blockscout.com/address/0xc588f37d165dd2B80AD95532aC5a8a975C732050) |

### Ethereum Sepolia

| Contract | Address |
| --- | --- |
| `DoodleGate` | [`0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484`](https://eth-sepolia.blockscout.com/address/0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484) |

## Layout

| Directory | Contents |
| --- | --- |
| `game/doodleshooter/` | The game. Static site, **no build step**, three.js and Reown AppKit vendored. |
| `contracts/` | Foundry. Four UUPS contracts on Creditcoin, one plain contract on Sepolia. |
| `server/` | `ink-monitor` — run monitor and Attestcoin relayer. |
| `docs/` | Design, plans, and the Attestcoin integration document. |

## Running it

```bash
# the game
cd game/doodleshooter && python3 serve.py 8910    # http://127.0.0.1:8910

# the monitor + relayer
cd server && cp .env.example .env && npm install && npm run dev

# the contracts
cd contracts && forge test
```

## How it holds together

**Staking can never promise more than it holds.** `startRun` reserves the payout ceiling from the
pool before it accepts the stake and refuses the run if the pool cannot cover it. The identity
`balance == free + reserved + activeStake` is asserted as a fuzz invariant and held across 4,096
randomised calls.

**Settlement is a threshold over attestations.** `settleRun` verifies N-of-M EIP-712 signatures
over a `RunResult`. Phase 1 runs with one attestor — the monitor key, which holds no owner rights.
Phase 2 reconfigures the same function for peer quorum with **no contract change**; a test proves
the switch is configuration only.

**A monitor outage cannot trap a stake.** `abandonRun` is callable by anyone once the settlement
window closes.

## Honest limitations

- **Phase 1 trusts the monitor for the score.** That is stated plainly rather than hidden. It does
  not touch the cross-chain claim: every piece of cross-chain data is proven by the precompile with
  no oracle. The attestor key is rotatable, and Phase 2 replaces it with peer quorum.
- **Attestcoin Writability is not released on testnet**, so ETH paid on Sepolia stays in
  `DoodleGate` and rewards pay in tCTC or USDT. `DoodleGate.withdraw` marks where two-way
  settlement lands when Writability ships.
- **Online multiplayer is deliberately gated off.** The code is intact but Phase 2 — see
  `CLAUDE.md`.
- The `USDT` contract is a **testnet-only mock** deployed by this project. It is not issued by,
  affiliated with, or endorsed by Tether, and holds no value.

## Tests

```
contracts   139 passing, 95.19% lines, 98.04% functions
server       35 passing
game         12 passing
```
