# Sprint 1 — Character Panel: Build Contract

Downport `NewEra/CharacterPanel/*` (Classic 1.15, ~7,600 LOC) → 3.3.5a, reskinning the real
`CharacterFrame` in place. Sits on the Sprint-0 Core toolkit + compat shims. Read with the Sprint-0
`/root/downport/DragonUI_NewEra/CONTRACTS.md` (§0 conventions still apply).

Source: `/root/downport/DOWNPORT THIS/NewEra/CharacterPanel/`. Target: `modules/character/`.

---

## A0. ARCHITECTURE PIVOT (2026-06-20, user-directed — SUPERSEDES the reskin approach below)

The reskin-in-place approach fought Blizzard's chrome/title/tabs/layout and looked broken. **We now
build a CUSTOM DragonUI-owned frame and HIDE Blizzard's `CharacterFrame`, REPARENTING Blizzard's
functional widgets (equipment slots + 3D model) into our frame for behavior.** Decisions:

- **Custom frame.** `NE.charpanel.frame = CreateFrame("Frame","DragonUI_NewEra_Character",UIParent)`,
  added to `UISpecialFrames` (ESC closes), sized to the DF character layout. All chrome/title/
  portrait/close/tabs/insets/sidebar are OURS (built via the Core toolkit), never Blizzard's.
- **Hide + intercept Blizzard.** Keep `CharacterFrame` hidden. Intercept the open path so the `C`
  key / micro button opens OUR frame: `hooksecurefunc("ToggleCharacter", fn)` (hide CharacterFrame,
  toggle ours to the requested tab) AND `CharacterFrame:HookScript("OnShow", hide-self+show-ours)`
  to catch other open paths. Never taint: do show/hide only; reparent ONLY out of combat (at
  PLAYER_LOGIN), guard with `InCombatLockdown()` + `CombatQueue`/`AfterCombat`.
- **Reparent functional widgets (ONCE, out of combat).** `CharacterModelFrame` and the 19 slot
  buttons (`CharacterHeadSlot`,`CharacterNeckSlot`,`CharacterShoulderSlot`,`CharacterShirtSlot`,
  `CharacterChestSlot`,`CharacterWaistSlot`,`CharacterLegsSlot`,`CharacterFeetSlot`,
  `CharacterWristSlot`,`CharacterHandsSlot`,`CharacterFinger0Slot`,`CharacterFinger1Slot`,
  `CharacterTrinket0Slot`,`CharacterTrinket1Slot`,`CharacterBackSlot`,`CharacterMainHandSlot`,
  `CharacterSecondaryHandSlot`,`CharacterRangedSlot`,`CharacterTabardSlot`) → `SetParent(Inset)` +
  reposition to DF layout (two vertical columns + bottom weapon row, retail style). Their texture/
  count/quality/click-to-equip logic is driven by Blizzard by GLOBAL NAME, so reparenting preserves
  behavior. Do NOT reimplement them.
- **What we build custom:** chrome (`NE.chrome.Apply` on our frame), class-icon portrait, DF close,
  DF metal tabs (our own buttons that switch content panes), the stat sidebar, and the secondary-tab
  panes (Reputation/Skills/Honor/Pet — read Blizzard data APIs, render our own rows). Stats are read
  via the unchanged global APIs (`UnitStat`, `GetResistance`, etc.) and rendered in our sidebar.
- **Much NewEra source still applies** — slot-frame decorations, inner border, model-area bg, model
  controls, sidebar stat rendering, class backgrounds, collapsible tab rows — just host them in OUR
  frame/Inset instead of Blizzard's. Reuse the visual logic; drop the chrome-suppression logic.

The §A items below are updated to fit this: "reskin CharacterFrame" → "build/populate our custom
frame". The integration (module toggle + options + QA) and all 3.3.5 gotchas (§B) are unchanged,
except QA `open` shows OUR frame: `open=function() NE.charpanel.Toggle(true) end`.

**REFERENCE — proven 3.3.5 mechanics: `/root/downport/DragonflightUICharacter/`** (the user's earlier
WORKING custom-frame character panel, Interface 30300). MINE it for the hard 3.3.5 plumbing, which is
already solved there: `CharacterFrame.lua` (hide stock CharacterFrame + `HookScript("OnShow",Hide)` +
replace global `ToggleCharacter` with own `Toggle`, save old; `UISpecialFrames`; custom frame build;
slot list + positioning), `StatsPanel.lua` (928 lines of working 3.3.5 stat reading/rendering — the
real `UnitStat`/resistance/melee/ranged/spell getters), `EquipmentManager.lua` (ItemRack-model equip,
3.3.5-safe). **Use DragonflightUICharacter for HOW (3.3.5 mechanics); use NewEra for WHAT (the DF look,
class art, decorations, richer sidebar, secondary tabs).** It is a reference, NOT the base — the
target look/scope is NewEra, built on our Core toolkit.

## A. Architect decisions (locked — do not deviate without flagging)

1. **Integration model.** The panel is our custom `NE.charpanel.frame` (Blizzard `CharacterFrame`
   hidden). Wire it as:
   - `NE.modules.Register{ name="character", default=true, onBoot=… }` (Core/Modules) — drives the reskin.
   - Options + QA via a dedicated helper `NE.RegisterReskin(spec)` (Agent A adds it to `integration/`):
     registers a DragonUI `ModuleRegistry` toggle + an options-tab entry + a QA entry whose
     `open=function() ToggleCharacter("PaperDollFrame") end`, `close=function() HideUIPanel(CharacterFrame) end`.
     **No mover** (CharacterFrame is a UIPanel).
2. **WowScrollBox → named FauxScrollFrame.** 3.3.5a has NO `WowScrollBox`/`ScrollUtil`/`MinimalScrollBar`.
   Everywhere the source uses them (Sidebar, Reputation, Skills, Honor lists), replace with a
   **named** `FauxScrollFrameTemplate` (name REQUIRED — unnamed errors) + manual row pool + an
   `OnVerticalScroll`/`FauxScrollFrame_Update` refresh. Row counts are bounded (~30-50), so
   non-virtualized is fine. Reuse `NE.scrollbar.Reskin` (Slider path) for the bar skin.
3. **Portrait = CLASS icon, not spec.** 3.3.5a has no retail specialization system. DO NOT port the
   `C_SpecializationInfo` spec-icon mapping. Use the player's **class icon** from the class-icon
   atlas (FDID 1662186, `classicon-<classfile>`) via `CLASS_ICON_TCOORDS`/the registered atlas.
4. **C_EquipmentSet → 3.3.5 global equip-manager.** 3.3.5a has a NATIVE equipment manager as GLOBAL
   funcs (`GetNumEquipmentSets`, `GetEquipmentSetInfo`, `GetEquipmentSetInfoByName`,
   `UseEquipmentSet`, `SaveEquipmentSet`, `DeleteEquipmentSet`, `GetEquipmentSetLocations`,
   `EquipmentSetContainsCulledSlots`, `GetEquipmentSetItemIDs`) — NOT under `C_EquipmentSet`. Agent E
   adds a `compat/C_EquipmentSet.lua` mapping the namespace to these globals (return-shape adapted),
   and sets `NE.cap.equipmentSets` by probing `GetNumEquipmentSets`. Keep NewEra's custom-Lua backend
   as the fallback if the globals are absent/flaky (private-server caveat — see project memory).
5. **Graceful degradation is mandatory.** No sub-feature may break the panel. If a secondary tab
   (Reputation/Skills/Honor/Pet) or the equip manager hits an unportable API, it must **leave that
   tab's native Blizzard look intact** and `NE.Log` a warning — never error out of `Apply`/boot.
   (Sprint 0 lesson: one nil deref aborted the whole panel.)
6. **Phasing / DoD priority.** MUST-HAVE (the Sprint-1 DoD): the **PaperDoll tab** fully DF-styled —
   chrome + restyled main tabs + model area + slot frames + slot-quality borders + class-icon
   portrait + class-colored level text + the stat **sidebar**. SHOULD-HAVE (same sprint, but may
   degrade): Reputation, Skills, Honor, PetPaperDoll tabs + Equipment Manager + per-slot flyout.

## B. 3.3.5a gotcha checklist (apply proactively — these cost Sprint-0 round-trips)

- `CreateMaskTexture` EXISTS but RETURNS NIL on this client → guard the return, not the method (`local ok,m=pcall(f.CreateMaskTexture,f); if ok and m and m.SetTexture then …`). Masks aren't needed (`SetPortraitTexture` is natively circular).
- `Button:SetNormalTexture`/`SetPushedTexture`/etc. take a PATH STRING, not a texture object. Use `SetX(path)` then `GetX():SetTexCoord(...)`.
- A child Button/Texture inherits the PARENT frame level → gets occluded by nineslice/title-band at higher levels. Raise it (`SetFrameLevel(base+N)`).
- No `SetShown` (Show/Hide). `FauxScrollFrame` MUST be named. No `:SetMask`/`ScrollBox`/native `Texture:SetAtlas` (use `NE.tex.SetAtlas`).
- 3.3.5 return-arg shifts: `GetCurrencyListInfo` icon=pos8, `GetFactionInfo` isHeader=pos9. `pcall` every stat/data getter in render loops.
- LoD/data not ready at boot → defer with `C_Timer.After` / event hooks; build lazily, never assume a frame/texture exists.
- Use `NE.tex.SetAtlas`/`NE.tex.Set` for all atlas art; `NE.dragon.Fonts` for fonts; `-- DOWNPORT:` comment every deviation.

## C. Shared surface & anchors (Agent A owns creation; B–E consume)

`NE.charpanel` table (created by Agent A in `CharacterPanel.lua`). Agent A MUST create and expose:
- `CharacterFrame.Inset` (left content pane) and `CharacterFrame.InsetRight` (sidebar host) — built by
  `NE.charpanel.BuildInset()` / `BuildInsetRight()` (from InsetFrames.lua, Agent A). If 3.3.5's
  `CharacterFrame` already has `.Inset`, reuse it; else create defensively.
- `NE.charpanel.ReassertLayout()` and `NE.charpanel.SelectSidebar(i)` — sidebar state (Agent C may
  implement the body, but Agent A declares/stubs them so load order can't nil-deref).
- The chrome applied via `NE.chrome.Apply(CharacterFrame, {layout="PortraitFrameTemplate", title=…})`
  and main tabs restyled via `NE.tabs.ReskinClassicTab("CharacterFrameTab"..i)`.
B–E anchor their content into `CharacterFrame.Inset` / `.InsetRight` / `NE_CharacterStatsPane` and
attach to `NE.charpanel.*`. Nobody but A creates the Inset frames or the boot/register.

## D. File ownership (two waves)

**WAVE 1 (foundation — dispatched now):**
- **Agent A — Shell/Nav/Integration:** `CharacterPanel.lua`, `InsetFrames.lua`, `TabButtons.lua`,
  `CloseButton.lua`, `EditModeRegister.lua` + the `NE.RegisterReskin` helper in `integration/`.
  Establishes the panel shell, chrome, main-tab reskin, boot/module-register, and the
  `NE.charpanel` surface (incl. stubs for ReassertLayout/SelectSidebar). DoD: CharacterFrame opens
  with DF chrome + restyled tabs + modern close button; no errors; registered in options + `/dnetest`.
- **Agent F — Assets:** `modules/character/Assets.lua` + COPY the CharacterPanel art from
  `NewEra/Art/CharacterPanel/` (+ `RaceBackground/`) into `Textures/CharacterPanel/`, register via
  `NE.tex.RegisterLocal`, and ADD atlas-coord tables for any CharacterPanel-specific atlases not
  already in Core (class-info BGs 1400895/1400896, panel bg 5882640, class icons 1662186, paperdoll
  parts 410247/8/9, list-expand 4571485, rep/skill bars 136567/136570, model-control icons
  3534438/3487944, race BGs). Validate BLP headers. Deliver `Textures/CharacterPanel/ASSETS.md`.

**WAVE 2 (content — dispatched after Wave 1 verified):**
- **Agent B — PaperDoll/Model:** `PaperDoll.lua`, `ModelArea.lua`, `ModelControls.lua`,
  `SlotFrames.lua`, `SlotQuality.lua`, `Portrait.lua` (CLASS icon), `LevelText.lua`, `InnerBorder.lua`.
- **Agent C — Sidebar/Stats:** `Sidebar.lua`, `SidebarTabs.lua` (FauxScrollFrame fallback; the
  PaperDoll stat sidebar — part of the MUST-HAVE DoD).
- **Agent D — Secondary tabs:** `Reputation.lua`, `Skills.lua`, `Honor.lua`, `PetPaperDoll.lua`
  (FauxScrollFrame fallback; graceful degradation per A.5).
- **Agent E — Equipment:** `EquipmentFlyout.lua`, `EquipmentSets.lua`, `EquipmentManagerPane.lua` +
  `compat/C_EquipmentSet.lua`.

## E. Load order (TOC additions, after Sprint-0 files, before `core/_HelloDemo.lua`)

`modules\character\Assets.lua` → `CharacterPanel.lua` → `InsetFrames.lua` → `InnerBorder.lua` →
`ModelArea.lua` → `SlotFrames.lua` → `SlotQuality.lua` → `Portrait.lua` → `LevelText.lua` →
`PaperDoll.lua` → `Sidebar.lua` → `SidebarTabs.lua` → `TabButtons.lua` → `ModelControls.lua` →
`EquipmentFlyout.lua` → `EquipmentSets.lua` → `EquipmentManagerPane.lua` → `Reputation.lua` →
`Skills.lua` → `Honor.lua` → `PetPaperDoll.lua` → `CloseButton.lua` → `EditModeRegister.lua`.
(Architect owns the TOC; agents create files at exactly these paths.)

## F. DoD verification (architect)

Static gate green; `/dnetest` shows a "Character" entry that opens CharacterFrame without error;
visual QA: open Character (`C`) → DF portrait-frame chrome, restyled metal tabs, DF close button,
model + slot frames + quality borders, class-icon portrait, class-colored level text, stat sidebar.
Secondary tabs either DF-styled or cleanly native (no errors). No taint on open/close in combat.
