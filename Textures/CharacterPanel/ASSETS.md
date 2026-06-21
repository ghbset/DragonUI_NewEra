# CharacterPanel Assets (Sprint 1, Agent F)

Art shipped + registered for the CharacterPanel reskin. Registration lives in
`modules/character/Assets.lua` (`NE.tex.RegisterLocal` + `NE.tex.RegisterAtlases`).
Atlas COORDS transcribed from `NewEra/Generated/AtlasData.lua` (retail build 12.0.5.67451).
Architect decision: coords live in `NE.tex.atlases`, **not** `C_Texture.RegisterAtlas`.

## fdid -> path map (44 BLPs)

All paths are `Interface\AddOns\DragonUI_NewEra\Textures\CharacterPanel\<file>`.

| FDID | File | Dims | Enc | Purpose |
|------|------|------|-----|---------|
| 1400895 | 1400895-character-info-classes-a.blp | 1024x1024 | DXT5 | Class BGs: Mage/Monk/Paladin/Priest/Rogue/Shaman/Warlock/Warrior |
| 1400896 | 1400896-character-info-classes-b.blp | 1024x512 | DXT5 | Class BGs: DeathKnight/DemonHunter/Druid/Hunter |
| 5882640 | 5882640-character-panel-background.blp | 1024x512 | DXT5 | Overall pane background |
| 1662186 | 1662186-classicon.blp | 2048x1024 | DXT5 | 12 class icons (portrait swap) |
| 410247 | 410247-charpaperdoll.blp | 32x16 | DXT5 | Char-Paperdoll-Horizontal inner-border h-tile |
| 410248 | 410248-charpaperdoll.blp | 256x128 | DXT5 | Char-Paperdoll-Parts (corners, slot frames) |
| 410249 | 410249-charpaperdoll.blp | 16x32 | DXT5 | Char-Paperdoll-Vertical inner-border v-tile |
| 3534438 | 3534438-common-buttons-icons.blp | 1024x1024 | DXT5 | common-button-square-gray-{up,down} |
| 3487944 | 3487944-common-buttons-icons.blp | 2048x1024 | **ARGB8888** | common-icon-* (zoom/rotate/undo) |
| 4571485 | 4571485-options-listexpand.blp | 128x128 | **ARGB8888** | options_listexpand_* (collapsible headers) |
| 136567 | 136567-ui-character-reputationbar.blp | 256x64 | DXT5 | Reputation bar end caps |
| 4499236 | 4499236-campaign-headericon.blp | 2048x1024 | **ARGB8888** | campaign_headericon_* (Skills collapse) |
| 131089-131112 | RaceBackground/*-DressUpBackground-<Race><1-4>.blp | 256x256 / 64x256 / 256x128 / 64x128 | DXT5 | Race model BGs: Dwarf/Human/NightElf/Orc/Scourge/Tauren (24 files) |
| 455998-456001 | RaceBackground/*-DressUpBackground-Gnome<1-4>.blp | (same quarters) | DXT5 | Gnome model BG (4 files) |
| 456006-456009 | RaceBackground/*-DressUpBackground-Troll<1-4>.blp | (same quarters) | DXT5 | Troll model BG (4 files) |

Total: **22,860,208 bytes (21.80 MB)**, 44 files (12 top-level + 32 RaceBackground).

## Atlas-coord families registered (via NE.tex.RegisterAtlases)

All rects transcribed verbatim from `NewEra/Generated/AtlasData.lua`:

| Family | Count | Sheet FDID | AtlasData.lua lines |
|--------|-------|-----------|---------------------|
| `ui-character-info-<class>-bg` | 12 | 1400895 / 1400896 | 13756-13770 |
| `classicon-<class>` | 13 (incl. evoker, never selected on 3.3.5a) | 1662186 | 2402-2414 |
| `options_listexpand_{left,right,right_expanded}` + `_options_listexpand_middle` | 4 | 4571485 | 519, 8672-8674 |
| `common-icon-{zoomin,zoomout,rotateleft,rotateright,undo}` | 5 | 3487944 | 2762-2779 |
| `common-button-square-gray-{up,down}` | 2 | 3534438 | 2570-2571 |

## Validation results (python BLP2 header read)

- **All 44 BLPs are valid BLP2** (magic `BLP2`), **all power-of-two**, all `type/version=1`.
- 41 sheets use DXT (encoding 2, DXT5/BC3 alpha) — the well-supported 3.3.5a path.
- **3 sheets are uncompressed ARGB8888 (BLP2 encoding 3, alphaDepth 8):**
  `3487944`, `4499236`, `4571485`. These are 3.3.5a-loadable (the client supports
  uncompressed BGRA addon BLPs) but heavyweight (8.4 MB each for the two 2048x1024 ones).
  Flagged for Wave 2: if texture memory / load time is a concern, the consuming modules
  (ModelControls, Skills collapse) can degrade gracefully — `NE.tex.SetAtlas` already
  returns false + `NE.Log`s a MISS if a sheet ever fails to load.
- `mips=0` on all the large sheets (matches Sprint-0 sheets like 2406979) — accepted by
  the 3.3.5a addon loader; not a problem.

## Missing / uncertain art (for Wave 2 to degrade)

- **136570** (rep/skill bar — contract listed "if present"): **NOT in source**, not shipped.
  Only 136567 (reputation bar) exists. Wave 2: do not reference 136570.
- **evoker** class icon is registered for parity but there is no Evoker class on 3.3.5a —
  it will never be selected by `classicon-<classfile>` lookup.
- The 3 ARGB8888 sheets above are the only load-risk items; everything else is standard DXT5.
- All other CharacterPanel sheets named in the source `Assets.lua` were located and shipped.
- Shared chrome (UI-Frame-Metal nineslice, rock bg 374155, InsetFrame inner-border
  1723831/2/3, tab sheet 4707839, RedButton 4698972, minimal-scrollbar family,
  spec-icons) is NOT in this module — it is owned by Core `Textures/Assets.lua` and consumed
  from there (per contract: disabling CharacterPanel must not drop shared art).
