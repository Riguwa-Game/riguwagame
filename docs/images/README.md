# Screenshots

| File | What it shows | Source |
| --- | --- | --- |
| `menu.jpg` | The title screen | `https://riguwa.xyz` |
| `wallet-connect.jpg` | Reown AppKit modal | `https://riguwa.xyz`, after clicking `#connectBtn` |
| `verified-contract.png` | ArenaEscrow verified on Blockscout | Blockscout, contract tab |
| `attestcoin-proof.png` | `TransactionVerified` emitted by the BlockProver precompile | Blockscout, relay transaction log tab |

All four are captured from the **live deployment**, unedited beyond a resize to 1440px wide. None is
a mockup and none is composed from pieces.

Captured headless over the Chrome DevTools Protocol, at a 1440x900 viewport with
`deviceScaleFactor: 2`. Two things are worth knowing if you retake them:

- **Headless Chrome needs `--enable-unsafe-swiftshader --use-angle=swiftshader`.** With
  `--disable-gpu` there is no WebGL, `new WebGLRenderer()` throws at the top of `main.js`, and the
  page captures as a blank sheet of paper.
- **`--virtual-time-budget` never settles** — the game runs a continuous render loop. Wait a fixed
  ~10 s after `Page.navigate` instead.

There is no gameplay screenshot here on purpose. `begin()` refuses to start without an active
on-chain run, so a real one costs a real stake — and faking it would defeat the point of a README
whose whole argument is that the chain, not the author, decides what happened.
