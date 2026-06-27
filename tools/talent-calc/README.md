# DragonUI Talent Calculator (offline, reads your client's DBCs)

A standalone talent calculator that reads talents **straight from your WoW `Data` folder** — including
your server's *custom* trees — and exports a build string the in-game DragonUI New Era addon imports.

## Use it

1. Open **`talents.html`** in a browser (Chrome/Edge/Firefox). Keep the four `.js` files next to it.
2. Click **"Select your WoW Data folder"** and pick your client's `Data` directory.
3. Pick a class, click talents (left-click = +1, right-click = −1), and copy the **Export** string.
4. In game: Talents → **Loadouts** → **Import**, paste the string. Same server ⇒ clean import.

It reads the talent DBCs out of the MPQ archives using WoW's override order (patch letters `Z→A`, then
numbers high→low, then base; the **locale chain** — `enUS` etc. — takes precedence, which is where
`DBFilesClient` lives). The winning copy is the one with your custom talents.

## How it stays in sync with the addon

- **Fingerprint** (`:DUI=<hash>` in the export) is a base-agnostic, locale-free hash of the live tree
  shape — computed identically here and in `modules/talents/Loadouts.lua`, so the addon's import guard
  recognises a same-layout build and skips the "different server" warning.
- **Codec** is the Talented format, packed in canonical `(tier, column)` order on both sides — so a
  string round-trips byte-for-byte between this tool and the addon (and the WoWhead/wotlkdb/truewow
  calculators on a stock layout).

## Files

| file | role |
|---|---|
| `talents.html` | the UI (directory picker + 3-tree calculator + import/export) |
| `mpq.js` | MPQ archive reader (on-demand, handles 4 GB archives; zlib sectors) |
| `dbc.js` | DBC parser + tree assembly + fingerprint + Talented-format codec |
| `resolve.js` | override-chain resolver (letters → numbers → base, locale-first) |
| `blp.js` | BLP2 icon decoder (DXT1/3/5, palettized, BGRA) → RGBA for the talent icons |
| `_test.js` | Node test harness (`node _test.js`) validating reader + parity + round-trip |

## Notes

- **Icons** decode in-browser from the client's BLP files (DXT1/3/5) and render straight onto the
  talent cells — verified against real icons via Node.
- Everything is tested headlessly via Node against a real 3.3.5a client; open `talents.html` in a
  browser to confirm the visual layout and that picking your `Data` folder loads your custom trees.
