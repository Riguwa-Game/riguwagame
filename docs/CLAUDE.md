# Documentation

| Path | What |
| --- | --- |
| `DEPLOYMENT.md` | **How to ship to riguwa.xyz**, written against what is actually on the VPS. |
| `ATTESTCOIN_INTEGRATION.md` | **The submission's technical integration document.** How the protocol is used, with the on-chain receipts. |
| `brainstorms/` | Design documents. The **why** behind architectural decisions. |
| `plans/` | Step-by-step implementation plans, executed in order. |

## Reading order

1. `brainstorms/2026-09-13-inkstake-arena-design.md` — the whole system and the reasoning. Read this
   before changing anything architectural.
2. `plans/2026-09-13-plan-1-game-foundation.md` — monorepo, English, seeded PRNG. **Done.**
3. `plans/2026-09-13-plan-2-contracts.md` — five contracts, TDD, deploy and verify. **Done.**
4. `plans/2026-09-13-plan-3-server-and-integration.md` — monitor, relayer, wallet, settlement. **Done.**

Plan 1 carries an execution record of the four places reality diverged from the plan. Plans 2 and 3
were corrected in place as OpenZeppelin 5.7 and Creditcoin's EVM turned out differently than assumed.

## Conventions

Plans use `- [ ]` checkboxes so progress is trackable. Steps are bite-sized: write the failing test,
run it, implement, run it again, commit.

Design docs state limitations openly rather than hiding them — the risks table in the design doc and
the "Security & limitations" section of the README are load-bearing, not decoration. If you find a
new limitation, add it there rather than leaving it for a judge to discover.
