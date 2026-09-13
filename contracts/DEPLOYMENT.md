# Deployment

Deployed 2026-09-13. Everything below is live and source-verified.

## Live addresses

### Creditcoin Testnet (chain `102031`)

| Contract | Proxy | Implementation |
| --- | --- | --- |
| `ArenaEscrow` | [`0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7`](https://creditcoin-testnet.blockscout.com/address/0xD63CbB36D1d25f44c653Ac5c6990B6B219f92Ee7) | [`0x0354D2A4bE40f118E4D1301915eE2fF54Eec8a52`](https://creditcoin-testnet.blockscout.com/address/0x0354D2A4bE40f118E4D1301915eE2fF54Eec8a52) |
| `DoodleGateASC` | [`0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF`](https://creditcoin-testnet.blockscout.com/address/0xd6565056853e4627f26B4bB4c1AEF7e9248f09dF) | [`0x5f228Ea014D52A9847CaAB401E94B1D3AD102a52`](https://creditcoin-testnet.blockscout.com/address/0x5f228Ea014D52A9847CaAB401E94B1D3AD102a52) |
| `USDT` | [`0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1`](https://creditcoin-testnet.blockscout.com/address/0x47dcAB80A108d6048059562AFF7d76aB3cbFA5B1) | [`0xF7a0e340455af3C476564d7AF283d9bE4D2CFAbb`](https://creditcoin-testnet.blockscout.com/address/0xF7a0e340455af3C476564d7AF283d9bE4D2CFAbb) |
| `SeasonRegistry` | [`0xc588f37d165dd2B80AD95532aC5a8a975C732050`](https://creditcoin-testnet.blockscout.com/address/0xc588f37d165dd2B80AD95532aC5a8a975C732050) | [`0xeA600fB10Cc533e4948A3d7EC04B7d0A6C96CDc8`](https://creditcoin-testnet.blockscout.com/address/0xeA600fB10Cc533e4948A3d7EC04B7d0A6C96CDc8) |

### Ethereum Sepolia (chain `11155111`)

| Contract | Address |
| --- | --- |
| `DoodleGate` | [`0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484`](https://eth-sepolia.blockscout.com/address/0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484) |

### Roles

| Role | Address |
| --- | --- |
| Owner / deployer | `0x56A2950ddE6B1040d1DCC4b4C4Fc314Bd56eFB0E` |
| `ink-monitor` attestor | `0xFd2ade73561E4700654C9c21932Dda8495e58665` |

The attestor holds **no** owner rights: it can sign a `RunResult` and nothing else. Rotate it with
`escrow.setAttestor(old,false)` then `escrow.setAttestor(new,true)`.

## Order matters

1. **Sepolia first** — `DoodleGate`. Its address is what the ASC binds as the only emitter it will
   honour, so it has to exist before step 2.
2. **Creditcoin** — the four proxies, then wiring, then pool seeding.

## Running it

```bash
forge script script/DeploySepolia.s.sol --rpc-url sepolia --broadcast   # then set DOODLE_GATE_SEPOLIA
./script/deploy-creditcoin.sh                                          # deploys + wires + seeds
./script/verify-creditcoin.sh                                          # verifies all 8 on Blockscout
./script/check-live.sh                                                 # protocol liveness
```

### Why Creditcoin is not deployed with `forge script`

Foundry cannot fork Creditcoin — its blocks carry no `mixHash` and report `difficulty: 0x0`, so
the fork backend fails with `header validation error: \`prevrandao\` not set`. `--broadcast`
simulates through that same backend, so `forge script` cannot reach the chain at all.

`script/Deploy.s.sol` remains the canonical, assertion-checked description of the deployment and is
**rehearsed against anvil** before every real run. `script/deploy-creditcoin.sh` then performs the
identical steps with `forge create` and `cast send`, which talk to the RPC directly.

### Verification gotcha

Pass `--skip-is-verified-check`. All four `ERC1967Proxy` deployments share identical runtime
bytecode, so forge's pre-check sees the first verified and wrongly reports the rest as already
done. Blockscout's API is the authority:

```bash
curl -s https://creditcoin-testnet.blockscout.com/api/v2/addresses/<addr> | jq .is_verified
```

## Configuration as deployed

| Setting | Value |
| --- | --- |
| Max stake, native | 100 tCTC |
| Max stake, USDT | 100 USDT (6 decimals) |
| Payout tiers | wave 5 → 1.5x, 10 → 2x, 15+ → 3x |
| Run TTL | 2 hours |
| Attestor threshold | 1 (Phase 1) |
| Cross-chain rate | 100 USDT per 1e18 of source value |
| Max credit per query | 1,000 USDT |
| Reward pool seeded | 300 tCTC + 100,000 USDT |

## Post-deployment checklist

- [x] `registry.setEscrow(escrow)`
- [x] `escrow.setAsc(asc)` and `usdt.setMinter(asc, true)`
- [x] `escrow.setMaxStake` for tCTC and USDT
- [x] `escrow.setAttestor(monitor)` and `escrow.setThreshold(1)`
- [x] **`asc.setSourceGate(1, 0x56CeD9fD5E49C1Aba1371D7aDe383DD16da76484)`** — the bridge is insecure without this
- [x] Reward pool funded
- [x] All 8 Creditcoin contracts + the Sepolia contract verified

## Smoke test, as run against the live deployment

```
startRun  1 tCTC   -> pool (free 297, reserved 3, activeStake 1)
monitor signs the EIP-712 digest with the attestor key
settleRun wave 12  -> paid 2 tCTC (2x tier), run state Settled
pool      -> (free 299, reserved 0, activeStake 0)
stats     -> bestWave 12, bestScore 7777, runs 1, wins 1, staked 1e18, won 2e18
identity  -> balance == free + reserved + activeStake   MATCH
```
