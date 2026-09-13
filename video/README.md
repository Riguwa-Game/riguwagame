# video/

The demo video, built with Remotion. `out/riguwa-demo.mp4` is the deliverable: 1920x1080,
1 minute 55 seconds.

```bash
npm install
npm run studio          # preview
npm run render          # out/riguwa-demo.mp4
npm run render:draft    # half scale, fast, for checking composition
```

## What is real in it

All of it. The gameplay is a **real staked run**: 3 tCTC staked from the deployer account, played,
lost at wave 2, and settled on-chain by ink-monitor with no human in the path. The Blockscout
footage is that same run's `settleRun` transaction, and the cross-chain section is the real relay
transaction whose first log is `TransactionVerified` from the block-prover precompile.

The run loses. That is deliberate: below wave 5 the stake joins the pool, which is what the
contract is supposed to do, and a demo where the house always pays proves less than one where it
does not.

## How the footage was captured

`begin()` refuses to start without an active on-chain run, so there is no way to film this without
staking. Headless Chrome has no wallet extension and no gamepad, so two things were injected over
the DevTools Protocol:

- **A wallet bridge.** The page gets an EIP-1193 provider that is a thin proxy: every `request()`
  is forwarded to the Node process, which signs with viem. The private key never enters the page.
- **A synthetic gamepad.** `navigator.getGamepads` is overridden and driven by a choreography that
  runs *inside* the page, so aiming is smooth at 60fps rather than stuttering on CDP round-trips.
  The bot tracks the nearest live enemy, fires in bursts, reloads in the gaps, and backs off when
  hurt. Mouse look was not an option: the game ignores `mousemove` without pointer lock, which
  headless will not reliably grant.

Capture scripts live in the session scratchpad rather than here; `docs/images/README.md` records
the same technique for the stills.

## Assets and licensing

`public/` is gitignored: roughly 140 MB of footage, narration and music, all regenerable.

- **Narration** is macOS `say` with the Samantha voice, one file per scene so retiming one scene
  cannot desync the rest.
- **Music** is "Inspired" by Kevin MacLeod (incompetech.com), licensed **CC BY 4.0**. The
  attribution is on the end card, and it has to stay there.

## Structure

`src/theme.ts` holds the palette and, more importantly, the scene table. Narration length drives
those numbers, not the other way round: regenerate the voice, read the new durations, update the
table. Every scene is one `<Sequence>` with its own audio file.

`src/components/Screen.tsx` frames footage and pushes in slowly. `Cursor.tsx` is the travelling
pointer with a click ring, which is the effect Cursorful sells as a product and is about forty
lines here, with keyframes we control and footage that stays untouched.
