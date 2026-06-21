# DragonUI_NewEra — Build Contracts (Sprint 0)

**Read this first.** Every agent codes against these fixed interfaces, not against each other's
in-progress output. The architect owns this file and the TOC; agents own their directories.

Paths: addon = `/root/downport/DragonUI_NewEra/`. Downport SOURCE = `/root/downport/DOWNPORT THIS/NewEra/`
(Classic 1.15). Base HUD = `/root/downport/DragonUI/DragonUI/` (3.3.5a). Shim lib =
`/root/downport/classicapi/!!!ClassicAPI/`.

---

## 0. Global conventions (all agents)

- **Namespace:** the addon table is `_G.DragonUI_NewEra`, aliased `NE`. Every Lua file starts with
  `local NE = DragonUI_NewEra`. Never create a global `NE`. (Porting a NewEra file = replace its
  top `NE = NE or {}` with `local NE = DragonUI_NewEra`; everything else `NE.*` stays.)
- **Base addon handle:** `NE.dragon == _G.DragonUI`. Use it for: `NE.dragon.ModuleRegistry`,
  `NE.dragon.MoversSystem`, `NE.dragon.OptionsPanel`, `NE.dragon.PanelControls`, `NE.dragon.Fonts`,
  `NE.dragon.SafeCall`, `NE.dragon.CombatQueue`, and `SetAtlasTexture` (global from DragonUI Atlas.lua).
- **3.3.5a hard rules (luac won't catch these):** no `SetShown` (use Show/Hide); `FauxScrollFrame`
  must be NAMED; no `SetMask`/`ScrollBox`/native atlas; some Blizzard returns are at shifted arg
  positions — `pcall` data getters. LoadOnDemand frames (Talents/Inspect/AH) hook on `ADDON_LOADED`.
- **Do not edit** anything under `/root/downport/DragonUI/` (base) or the NewEra source. Read-only.
- **Comment style for ported files:** keep NewEra's excellent header comments; add a one-line
  `-- DOWNPORT: <what changed from 1.15 source>` wherever you deviate.

---

## 1. compat/ — modern-API shim layer  (owner: API Bridge Engineer)

Goal: after `compat/` loads, every modern symbol NewEra v1 uses **exists and works on 3.3.5a**,
delegating to `!!!ClassicAPI` when present, else a vendored shim copied/adapted from ClassicAPI
or written fresh. Load order is fixed by the TOC (compat loads before core).

**Files you own (exact names — TOC already lists them):**
`compat/Compat.lua` (loader + ClassicAPI detection + `NE.compat` table of capability bools),
`compat/Mixin.lua`, `compat/C_Timer.lua`, `compat/C_Texture.lua`, `compat/C_Container.lua`,
`compat/C_Item.lua`, `compat/C_Spell.lua`, `compat/C_Map.lua`. Plus **`compat/COVERAGE.md`**.

**Contract each shim guarantees (minimum for v1):**
- `Mixin(obj, ...)`, `CreateFromMixins(...)`, `CreateAndInitFromMixin(...)`.
- `C_Timer.After(sec, fn)`, `C_Timer.NewTimer`, `C_Timer.NewTicker`.
- `C_Texture.GetAtlasInfo(name)`, `C_Texture.GetAtlasExists`. (Atlas DATA is registered by Asset
  agent via `NE.tex`; this shim only needs to answer atlas queries NewEra makes directly.)
- `C_Container.*` (GetContainerNumSlots/ItemInfo/ItemLink/NumFreeSlots/UseContainerItem/
  PickupContainerItem) mapped to 3.3.5 `GetContainer*` globals.
- `C_Item.*` subset used by v1 (GetItemInfo wrappers, GetItemSpell, icon/quality helpers).
- `C_Spell.*` subset (GetSpellSubtext, GetSpellPowerCost, texture/cooldown helpers).
- `C_Map.*` subset (GetBestMapForUnit, GetMapInfo, GetPlayerMapPosition) — best-effort; QuestFrame
  uses some. Stub returning safe nils where 3.3.5 can't answer, and record it in COVERAGE.md.

**Rule:** prefer DragonUI's own helper if it already exists; else ClassicAPI; else vendor a copy
INTO compat/ (don't hard-depend on ClassicAPI). Detection: `if NE.hasClassicAPI and C_Timer then …`.

**Deliverable `compat/COVERAGE.md`:** a matrix of every modern symbol NewEra v1 references →
`{source: ClassicAPI | DragonUI | vendored | stub | not-needed-v1}` + a note on any partial/stub.
Produce the symbol list by grepping the v1 module dirs in the NewEra source (CharacterPanel,
Spellbook, Talents, QuestFrame, MerchantFrame, MailFrame) AND the Core/ files those depend on.

---

## 2. core/ — downported NewEra Core chrome toolkit  (owner: Core/Chrome Engineer)

Downport these NewEra `Core/` files onto 3.3.5a, wired to DragonUI. **Files you own (exact names):**
`core/FrameUtil.lua`, `core/Texture.lua`, `core/NineSlice.lua`, `core/NineSliceLayouts.lua`,
`core/PanelChrome.lua`, `core/Portrait.lua`, `core/Tabs.lua`, `core/ButtonSkin.lua`,
`core/ScrollbarReskin.lua`, `core/ItemButton.lua`, `core/ItemGrid.lua`, `core/Modules.lua`,
and the Sprint-0 proof `core/_HelloDemo.lua`.

**Public interfaces you must expose (panels in later sprints depend on these — keep stable):**
- `NE.tex.RegisterLocal(fdid, path)` and `NE.tex.Set(texture, fdidOrAtlasName[, ...])` — the
  texture indirection NewEra uses (`Core/Texture.lua`). The Asset agent supplies the data; you
  supply the API. Resolve atlas coords via the C_Texture shim / registered atlas table.
- `NE.nineslice.Apply(frame, layoutName[, opts])` — applies a registered nineslice layout
  (`Core/NineSlice.lua` + `NineSliceLayouts.lua`). Must support at least `PortraitFrameTemplate`,
  `InsetFrameTemplate`, `ButtonFrameTemplate` for Sprint 1.
- `NE.chrome.Apply(frame, opts)` — the PanelChrome entry that turns a Blizzard frame into a DF
  portrait-frame (nineslice + portrait + title + close-button reskin). (`Core/PanelChrome.lua`.)
- `NE.modules.Register{ name=, default=, onBoot=fn }` and the reload-gated boot dispatcher
  (`Core/Modules.lua`). This drives per-module boot/enable. (The DragonUI-facing toggle is added
  by the Integration agent and proxies into this.)
- `NE.frameutil.PinPixelPerfect(...)`, `NE.portrait.*`, `NE.tabs.*`, `NE.buttonskin.*`,
  `NE.scrollbar.*`, `NE.itembutton.*`, `NE.itemgrid.*` — keep NewEra's surface; downport bodies.

**Wiring to DragonUI:** use `NE.dragon.Fonts` for fonts; prefer DragonUI `utils/nineslice.lua`
patterns where they already solve a problem; register atlases through DragonUI's `Atlas.lua` /
`SetAtlasTexture` OR the C_Texture shim — coordinate the choice with the Asset agent (see §3).

**`core/_HelloDemo.lua` (Sprint-0 exit proof):** registers slash `/dnehello` that creates a
standalone frame and calls `NE.chrome.Apply` to render a DF portrait-frame on it (no real Blizzard
panel — that's Sprint 1). Also registers itself into `NE.qa.modules` so the harness can open it.

---

## 3. Textures/ — art + atlas registration  (owner: Asset Pipeline Engineer)

Inventory `/root/downport/DOWNPORT THIS/NewEra/Art/`. For Sprint 0, deliver the **shared/Core
sheets** needed by the chrome toolkit + Hello demo (the NineSlice frame-metal sheets and shared
backgrounds). **File you own:** `Textures/Assets.lua` — a list of `NE.tex.RegisterLocal(fdid, path)`
calls (the API comes from Core `core/Texture.lua`). Copy the actual BLP files into
`DragonUI_NewEra/Textures/<Folder>/...` preserving NewEra's per-panel folder structure, and point
the registration paths at `Interface\AddOns\DragonUI_NewEra\Textures\...`.

**Sprint-0 minimum atlas set** (from NewEra `Core/NineSliceLayouts.lua` + `Core/Assets.lua`):
the UI-Frame-Metal corner/edge sheets (FDIDs 2406979/2406984/2406987), UI-Background-Rock (374155),
and the InsetFrameTemplate inner-border sheets (1723831/1723832/1723833). Verify each BLP is valid
3.3.5-loadable (dimensions power-of-two; use `mpyq`/existing tooling to sanity-check if unsure).

**Deliverable:** `Textures/ASSETS.md` — what was copied, the FDID→path map, total size, and any
art that's missing/needs extraction for later panels. Confirm one atlas renders end-to-end with the
Core agent's Hello demo (coords correct, not stretched).

**Coordinate with Core (§2) on the atlas mechanism:** decide together whether atlas coords are
resolved via `C_Texture.RegisterAtlas` (ClassicAPI/shim) or a plain `NE.tex` coord table. Record
the decision at the top of `Textures/Assets.lua`.

---

## 4. integration/ — DragonUI handshake  (owner: Integration Liaison)

**Files you own:** `integration/Register.lua`, `integration/Options.lua`.

- `Register.lua`: define `NE.OnReady` (bootstrap calls it once SavedVariables are loaded). In it,
  ensure `NE.dragon.db.profile.newera` exists (defaults `{ enabled=true }`), and provide
  `NE.RegisterPanel(spec)` — the helper every panel module (later sprints) calls to:
  (1) register a `NE.modules.Register` boot entry, (2) register a `NE.dragon.ModuleRegistry:Register`
  entry so it shows in DragonUI's module list, (3) register a `NE.dragon.MoversSystem:RegisterMover`
  for the panel's frame, and (4) append to `NE.qa.modules`. Spec shape:
  `{ id, title, desc, frame, openFn, closeFn, defaultPoint, order }`.
- `Options.lua`: when `DragonUI_Options` loads (hook `ADDON_LOADED` for `"DragonUI_Options"`, and
  also handle the already-loaded case), call `NE.dragon.OptionsPanel:RegisterTab("newera",
  "New Era", builder, 16)`. The builder lists a toggle per registered panel using
  `NE.dragon.PanelControls` bound to `modules.<id>.enabled`, with a callback that calls the panel's
  `Refresh*System` (or `NE.modules` enable). For Sprint 0 it shows just the Hello demo toggle.

**Contract for later panels:** they only ever call `NE.RegisterPanel(spec)` + `NE.chrome.Apply` —
they never touch DragonUI internals directly. You own that indirection.

---

## 5. qa/ — in-game harness + static gate  (owner: QA/Harness Engineer)

**Files you own:** `qa/Harness.lua` and `qa/staticcheck.sh` (+ `qa/QA.md`).

- `qa/Harness.lua`: slash `/dnetest` that iterates `NE.qa.modules` and prints a per-module report:
  does the frame global exist, does `openFn` run without error (wrap in `pcall`), any Lua errors
  captured this session (install a lightweight error hook), and a taint note. Summarize PASS/FAIL.
- `qa/staticcheck.sh`: run `luac -p` (3.3.5/Lua 5.1) on every `.lua` in the addon (skip if no luac
  → say so), verify every file listed in the TOC exists, and grep for the known runtime traps
  (`SetShown(`, unnamed `CreateFrame("...","FauxScrollFrame"` patterns, `:SetMask(`, `C_` calls not
  covered by `compat/COVERAGE.md`). Emit a clear PASS/FAIL with file:line for each hit.
- `qa/QA.md`: how to run both, and the Sprint-0 expected output.

You may run `staticcheck.sh` yourself at the end and paste results.

---

## 6. Sprint-0 Definition of Done (architect verifies)

1. TOC loads clean (all listed files exist; `staticcheck.sh` PASS).
2. `compat/COVERAGE.md` matrix complete for v1 symbols; shims load without error.
3. Core toolkit exposes the §2 interfaces; `/dnehello` renders a DF portrait-frame using downported
   nineslice + one real registered atlas (Asset art), pixel-correct.
4. `/dnetest` reports the Hello demo PASS.
5. A "New Era" tab appears in DragonUI options (when DragonUI_Options is open) with the demo toggle.
6. No global leaks (`NE` is local everywhere); base DragonUI untouched.
