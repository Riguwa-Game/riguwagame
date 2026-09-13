# Documentation

| Path | What |
| --- | --- |
| `brainstorms/` | Design documents. The **why** behind architectural decisions. |
| `plans/` | Step-by-step implementation plans, executed in order. |

## Reading order

1. `brainstorms/2026-09-13-inkstake-arena-design.md` — the whole system, and the reasoning.
   Read this before changing anything architectural.
2. `plans/2026-09-13-plan-1-game-foundation.md` — monorepo, English, seeded PRNG.
3. `plans/2026-09-13-plan-2-contracts.md` — five contracts, TDD, deploy and verify.
4. `plans/2026-09-13-plan-3-server-and-integration.md` — monitor, relayer, wallet, settlement.

Each plan produces working, testable software on its own. Run them in order.

## Still to be written

`ATTESTCOIN_INTEGRATION.md` — the technical integration document the hackathon requires.
Created in Plan 3, Task 7.

## Conventions

Plans use `- [ ]` checkboxes so progress is trackable. Steps are bite-sized: write the failing
test, run it, implement, run it again, commit. Design docs state limitations openly rather than
hiding them — the risks table in the design doc is load-bearing, not decoration.
