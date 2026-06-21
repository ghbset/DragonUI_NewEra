# DragonUI_NewEra — Textures / Art Pipeline (Sprint 0)

Owner: Asset Pipeline Engineer (CONTRACTS.md §3).
Source art: `/root/downport/DOWNPORT THIS/NewEra/Art/` (Classic 1.15 / retail-extracted BLPs).
Dest: `/root/downport/DragonUI_NewEra/Textures/` — **the only path this agent writes to.**

---

## 1. Pipeline / architecture decision

- Art lives under `Textures/<Subfolder>/...` mirroring NewEra's `Art/<Subfolder>` layout
  (Sprint-0 set is all in `Art/Common`, so it lands in `Textures/Common/`).
- `Textures/Assets.lua` is a **pure fdid → file-path index** of `NE.tex.RegisterLocal(fdid, path)`
  calls. Paths point at `Interface\AddOns\DragonUI_NewEra\Textures\...`.
- **ARCHITECT DECISION (atlas mechanism):** atlas *coordinates* come from the Core NineSlice
  coord tables (`core/NineSliceLayouts.lua` + the transcribed atlas-coord data), **not** from
  `C_Texture.RegisterAtlas`. The 3.3.5a client has no native atlas DB and the ClassicAPI
  `C_Texture` shim only answers existence/info queries — it does not feed slice geometry to the
  render path (retail atlas nicknames would stretch as flat strips). So:
  - geometry (atlas-name → fdid + texcoord rect, slice sizes) = **Core** coord tables;
  - art location (fdid → BLP on disk) = **this file**.
  This is recorded verbatim at the top of `Textures/Assets.lua`.
- `NE.tex.RegisterLocal` / `NE.tex.Set` are provided by the Core agent's `core/Texture.lua`;
  this agent only *calls* the API.

---

## 2. Art/ inventory (source, read-only)

Total: **1238 files, ~131 MB**. Formats: **1236 BLP**, 1 PNG, 1 CSV (no TGA).
46 top-level panel folders. Largest are per-panel art for LATER sprints.

| Folder | Files | Size | Covers |
|---|---|---|---|
| Common | 119 | 21M | **shared chrome** (Core-owned): frame-metal, inset border, rock bg, tabs, slots, close btn, scrollbars, class/spec icons, etc. |
| Professions | 37 | 44M | profession UI (later) |
| Talents | 35 | 16M | talent tree art (later) |
| EncounterJournal | 365 | 13M | dungeon journal (later) |
| AchievementIcons | 337 | 1.5M | achievement icons |
| LFG | 9 | 8.5M | LFG |
| PvPMatch | 13 | 5.2M | PvP scoreboard |
| PlayerFrame / UnitFrame / TargetFrame / PartyFrame / RaidFrame / NamePlates | — | — | HUD unit frames (base DragonUI mostly owns these) |
| CharacterPanel | 3 | 590K | paperdoll class bgs (later, Sprint 1+) |
| Spellbook | 6 | 1.1M | spellbook reskin (later) |
| Merchant / Bank / TradeFrame / AuctionHouse / Mail* | — | — | vendor/bag panels (later) |
| RaceBackground | 32 | 625K | dress-up race backdrops (later) |
| ActionBar | 2 | 1.2M | action bar -2x sheets (HUD; base DragonUI) |
| Calendar / Guild / Social / Honor / Achievements / TabardFrame / Tooltip / EditMode / BossMods / Minimap / ComboPoint / BuffFrame / CastingBar / CooldownViewerSettings / Campaign / Durability / FullAlert / DressUp / LootRoll / PetStable / QuestTracker / RaidManager / SpellActivationOverlay | — | — | misc panels/HUD (later or base-owned) |

*(Full per-folder counts available via `find Art/<folder> -type f`.)*

---

## 3. Copied this sprint (fdid → path map)

All 7 Sprint-0 shared/Core sheets copied to `Textures/Common/`, registered in `Textures/Assets.lua`:

| FileDataID | File (`Textures/Common/`) | Dimensions | Encoding | Bytes | Role |
|---|---|---|---|---|---|
| 2406979 | 2406979-uiframe-metal-corners.blp | 512×512 | BGRA (raw3) aDepth8 | 1,049,748 | UI-Frame-Metal corners (incl. PortraitMetal / Double) |
| 2406984 | 2406984-uiframe-metal-edges-vert.blp | 512×32 | BGRA (raw3) aDepth8 | 66,708 | `!`-tile Left/Right metal edges |
| 2406987 | 2406987-uiframe-metal-edges-horiz.blp | 64×256 | BGRA (raw3) aDepth8 | 66,708 | `_`-tile Top/Bottom metal edges |
| 374155 | 374155-uibackground-rock.blp | 1024×1024 | DXT1 aDepth0 | 525,460 | UI-Background-Rock fill (ButtonFrameTemplate) |
| 1723831 | 1723831-uiframe-inner.blp | 128×128 | DXT5 aDepth8 | 17,556 | InsetFrameTemplate inner corners (6×6) |
| 1723832 | 1723832-uiframe-inner.blp | 64×256 | DXT5 aDepth8 | 17,556 | Inset Left/Right inner tiles (3×256) |
| 1723833 | 1723833-uiframe-inner.blp | 256×128 | DXT5 aDepth8 | 33,940 | Inset Top/Bottom inner band |

**Total copied: 1,777,685 bytes (~1.7 MB), 7 files.**

> Filename note: source `Art/Common/` also contains a near-duplicate `1723831-uiframe.blp`
> (17,556 bytes, identical size). The registered path used by NewEra's `Core/Assets.lua` is
> `1723831-uiframe-inner.blp`, so that is the variant copied. The `-uiframe.blp` variant is
> unregistered and was NOT copied.

---

## 4. Validation results

Validated by reading BLP2 headers (Python struct, wowdev BLP2 layout). Result: **ALL PASS.**

- **Magic:** all 7 are valid `BLP2`.
- **Power-of-two:** all dimensions POT (512/1024/256/128/64/32). ✅
- **Encoding:** valid — metal sheets = uncompressed BGRA8888 (raw3); rock = DXT1; inset = DXT5.
  All three are 3.3.5a-loadable formats.
- **Lua:** `Textures/Assets.lua` passes `luac5.1 -p` (Lua 5.1, 3.3.5 dialect) clean.

Caveats (non-blocking, documented assumptions):
- **No mipmaps** (`hasMips=0`) on all 7 sheets. UI textures don't require mips on 3.3.5a; they
  render at native size via nineslice texcoords, so this is fine. If any sheet is ever down-scaled
  far below native it may shimmer — not a concern for the fixed-size chrome here.
- The two metal-edge sheets (2406984/2406987) are uncompressed BGRA (no DXT). Heavier on VRAM than
  DXT but byte-faithful to the extracted retail art and within budget for chrome.
- End-to-end render check (one atlas drawn pixel-correct via Core's `/dnehello`) is a **joint
  Sprint-0 exit step with the Core agent** — pending their `_HelloDemo.lua`. Header/format/POT
  validation done here is the static half.

---

## 5. MISSING / TODO for later panels

Nothing is *missing* from the source `Art/` tree — all later-panel art is present and located.
Future sprints grab from `/root/downport/DOWNPORT THIS/NewEra/Art/` and register in either a
per-panel `Textures/<Panel>/Assets.lua` (panel-owned) or extend `Textures/Assets.lua` (shared Core).

### CharacterPanel (Sprint 1+) — `Art/CharacterPanel/` and `Art/Common/`
| FDID | Source path | Role |
|---|---|---|
| 1400895 | `Art/CharacterPanel/1400895-character-info-classes-a.blp` (1.0M) | class-themed paperdoll bg (Mage/Monk/Pal/Priest/Rogue/Sham/Lock/War + title/itemlevel bounce) |
| 1400896 | `Art/CharacterPanel/1400896-character-info-classes-b.blp` (525K) | class paperdoll bg (DK/DH/Druid/Hunter) |
| 5882640 | `Art/CharacterPanel/5882640-character-panel-background.blp` (525K) | overall character-pane bg |
| 1662186 | `Art/Common/1662186-classicon.blp` (2.1M) | UI-Classes-Circles class-icon sheet (portrait swap) |

> Other CharacterPanel sheets referenced by NewEra `CharacterPanel/Assets.lua` and living in
> `Art/Common/`: 3534438/3487944 (model-control buttons+icons), 410247/410248/410249
> (Char-Paperdoll Parts/Horiz/Vert), 136567 (reputation bar), 136565/131074 (rep detail bg +
> divider), 4499236 (campaign header icon), 4571485 (options list-expand), 4331838/4332072/
> 7367534/5142787/5142784 (minimal-scrollbar family), 461112/236179/461113/236264/236270/236286/
> 237542/237581 (8 spec icons). Plus `Art/RaceBackground/` (32 dress-up race bg quarters, FDIDs
> 131089-131112 / 455998-456009 — see NewEra CharacterPanel/Assets.lua loop).

### Spellbook (later) — `Art/Spellbook/` (6 files, 1.1M)
4200162 (skilllinetab), 5506565 (items), 5794906 (sheen-mask), 5834697 (backgrounds),
5899876 (spellicon-mask), 5922242 (petautocast-mask).

### Talents (later) — `Art/Talents/` (35 files, 16M)
Tree backgrounds (4631299…4631395 family, ~18 sheets), 4556093 (talents sheet), masks
(4633068 circle, 4731572/4731579 sheen, 7532041 apex, 4722778 anim-mask), dependency bars
(1126606/1126607/1134738/1134739), apex bar 7532048, warmode art (450901/514317/921230/
`warmode-flame-mask.blp`), anim clouds/particles (4723109/4732064).

### Shared-Core candidates not yet needed in Sprint 0 — `Art/Common/`
Tab sheet 4707839, inner top-streak 1723833 *(done)*, DiamondMetal dialog chrome
(3056750/3056755/3058483), item-slot 4701874, close button 4698972, vendor slots
(130766/130841), action-bar sheets 4613342/4615764 (`Art/ActionBar/`). Register into the
shared `Textures/Assets.lua` when a Core consumer (Dialog layout, item grid, vendor) is downported.

---

## 6. Files delivered this sprint
- `Textures/Assets.lua` — 7 `RegisterLocal` calls + architect-decision comment block.
- `Textures/Common/` — 7 BLP sheets (1,777,685 bytes).
- `Textures/ASSETS.md` — this file.
