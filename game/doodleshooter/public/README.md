# public/

Static assets served alongside the game. Referenced from the UI as `./public/<file>`.

| File | What | Source |
| --- | --- | --- |
| `logo.png` | **Riguwa mark**, 512x512, transparent | This project's own logo. Source art in `game/logos/`. |
| `favicon.png` · `favicon-32.png` | The same mark, 64x64 and 32x32 | Derived from `logo.png` |
| `apple-touch-icon.png` | The same mark, 180x180 | Derived from `logo.png` |
| `ctc.png` | Creditcoin (CTC) mark, 256x256 | Creditcoin official branding, via the Trust Wallet assets registry |
| `usdt.png` | Tether (USDT) mark, 300x300 | Trust Wallet assets registry |
| `usdt.svg` | Tether (USDT) mark, vector | cryptologos.cc |

`ctc.png`, `usdt.png` and `usdt.svg` are third-party trademarks, used only to label token choices
in the staking UI. `logo.png` is ours, and is what `wallet.js` hands to AppKit as `metadata.icons`
— the mark a wallet shows next to a connection request must identify *us*, not a chain we run on.

The transparent background was flood-filled from the image edges only, so the white inside the
letterform survives and the mark stays legible on a dark background as well as on the game's paper.

Note: the `USDT` contract in `contracts/src/USDT.sol` is a **testnet-only mock deployed by this
project**. It is not issued by, affiliated with, or endorsed by Tether, and holds no value.
