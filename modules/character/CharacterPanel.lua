-- DragonUI_NewEra/modules/character/CharacterPanel.lua — the Character panel ORCHESTRATOR.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): we do NOT reskin Blizzard's CharacterFrame in place. We build
-- a CUSTOM DragonUI-owned frame (NE.charpanel.frame = "DragonUI_NewEra_Character"), HIDE Blizzard's
-- CharacterFrame, and REPARENT Blizzard's functional widgets (the 19 equipment slot buttons +
-- CharacterModelFrame) into ours so click-to-equip / texture / quality logic keeps working (Blizzard
-- drives those by GLOBAL NAME, so reparenting preserves behaviour).
--
-- GEOMETRY (matches VISUAL_SPEC.md exactly, ported from NewEra/CharacterPanel/*):
--   * Frame  338x424 COLLAPSED  ->  548x424 EXPANDED (sidebar shown).
--   * Inset (left content, FIXED 328x360) at Frame.TOPLEFT(4,-60), BOTTOMRIGHT->frame.BOTTOMLEFT(332,4).
--   * InsetRight (sidebar host, auto-sized) at Inset.TOPRIGHT(1,0); hidden until expanded.
--   * CharacterModelFrame resized to 231x320 at Inset.TOPLEFT(52,-66) (fixed, not box-filled).
--   * 19 slots at the VANILLA PaperDollFrame.xml anchors (Head/Hands columns chain -4; weapons +5),
--     translated relative to our Inset so they tight-flank the model exactly like NewEra.
--
-- HOW (proven 3.3.5a mechanics) is lifted from /root/downport/DragonflightUICharacter/CharacterFrame.lua:
--   * CharacterFrame:HookScript("OnShow", function(s) s:Hide() end)   -- keep stock frame hidden
--   * save the global ToggleCharacter, replace it with our own that drives NE.charpanel.Toggle
--   * tinsert(UISpecialFrames, "DragonUI_NewEra_Character")           -- ESC closes ours
-- WHAT (the DF look/scope) comes from NewEra + our Core toolkit (NE.chrome / NE.tabs / NE.tex).
--
-- GRACEFUL DEGRADATION (CONTRACT §A.5 / §B): every risky step (chrome, reparent, tab build) is
-- pcall-wrapped and logged; onBoot never errors. Reparenting + repositioning happen ONLY OUT OF
-- COMBAT, guarded by InCombatLockdown + NE.FrameUtil.AfterCombat.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE     = "character"
local FRAME_NAME = "DragonUI_NewEra_Character"

-- ----------------------------------------------------------------------------
-- Geometry constants (VISUAL_SPEC.md — replicate NewEra exactly).
-- ----------------------------------------------------------------------------
-- Frame.
-- Match NewEra exactly: PANEL_DEFAULT_WIDTH=338 collapsed, 548 expanded. (We position slots/model
-- relative to the Inset, so they fit 338 fine — the earlier 384 was wider than NewEra.)
local FRAME_W_COLLAPSED = 338
local FRAME_W_EXPANDED  = 548
local FRAME_H           = 424

-- Slot geometry. Vanilla PaperDollItemSlotButtonTemplate is a 37px button; metal frames around them
-- are ~49x44 (left)/50x44 (right)/42x53 (bottom) and are drawn by Wave-2 (SlotFrames.lua). The slot
-- CHAIN pitch is what we replicate here: vanilla chains each slot at the previous slot's BOTTOMLEFT
-- with (0,-4), and the weapon row at the previous slot's TOPRIGHT with (5,0).
local SLOT_VERT_GAP   = -4    -- vanilla inter-slot vertical chain offset
local SLOT_HORIZ_GAP  = 5     -- vanilla inter-weapon horizontal chain offset

-- DOWNPORT/REPORT: removed CP._dollBox box-fill of the model. Faithful NewEra sizes the model to a
-- FIXED 231x320 at Inset.TOPLEFT(52,-66) (NOT box-filled / NOT centered), and the race bg uses native
-- quarter sizes anchored to the model. ModelArea no longer reads CP._dollBox.
local MODEL_W = 231   -- NewEra CharacterModelScene size
local MODEL_H = 320
-- DOWNPORT/REPORT: NewEra's model (52,-66) is relative to PaperDollFrame (≈ the FRAME). Our model is
-- parented to the Inset (which is itself at frame -60,+4), so applying -66 directly dropped it ~60px
-- too low (empty band above it). Subtract the inset offset: frame(52,-66) == Inset(48,-6).
local MODEL_X = 48    -- Inset.TOPLEFT x  (= frame x 52)
local MODEL_Y = -6    -- Inset.TOPLEFT y  (= frame y -66)

-- Per-VISUAL_SPEC slot anchors (relative to the Inset):
--   * Head at Inset.TOPLEFT(4,-2)        — top of left column
--   * Hands at Inset.TOPRIGHT(-4,-2)     — top of right column
--   * MainHand at Frame.BOTTOMLEFT(84,24)— bottom weapon row
local LEFT_COL_X   =  4    -- Inset.TOPLEFT x for Head
local LEFT_COL_Y   = -2    -- Inset.TOPLEFT y for Head
local RIGHT_COL_X  = -4    -- Inset.TOPRIGHT x for Hands
local RIGHT_COL_Y  = -2    -- Inset.TOPRIGHT y for Hands
-- Weapon row: NewEra anchors CharacterMainHandSlot at Frame.BOTTOMLEFT(84,24).
-- DOWNPORT/REPORT: center the weapon row UNDER THE MODEL (model frame-center ≈ 167.5; 3-slot row is
-- ~121 wide → MainHand at 107). NewEra's 84 centers on the frame, leaving the row left of the model.
local WEAPON_X     = 107   -- Frame.BOTTOMLEFT x for MainHand (centered under the model)
local WEAPON_Y     = 24    -- Frame.BOTTOMLEFT y for MainHand

-- The 19 equipment slot buttons split into the vanilla two-column + bottom-weapon layout.
-- LEFT column (top->bottom): Head,Neck,Shoulder,Back,Chest,Shirt,Tabard,Wrist
-- RIGHT column (top->bottom): Hands,Waist,Legs,Feet,Finger0,Finger1,Trinket0,Trinket1
-- BOTTOM weapon row (left->right): MainHand,SecondaryHand,Ranged
local SLOT_LEFT = {
  "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
  "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
}
local SLOT_RIGHT = {
  "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
  "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
}
local SLOT_BOTTOM = {
  "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}
-- All reparented slot widgets, for the single reparent pass (model handled separately).
local REPARENT_WIDGETS = {}
for _, t in ipairs({ SLOT_LEFT, SLOT_RIGHT, SLOT_BOTTOM }) do
  for _, n in ipairs(t) do REPARENT_WIDGETS[#REPARENT_WIDGETS + 1] = n end
end

-- ----------------------------------------------------------------------------
-- Local logger + guard. DOWNPORT: NE.Log may be absent on a standalone load.
-- ----------------------------------------------------------------------------
local function log(msg)
  if NE.Log then NE.Log("CHARPANEL", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [character]: " .. tostring(msg))
  end
end
CP._log = log

local function guard(label, fn)
  local ok, err = pcall(fn)
  if not ok then log(label .. " failed: " .. tostring(err)) end
  return ok
end

-- ----------------------------------------------------------------------------
-- Class-icon portrait. CONTRACT §A0/§A.3: PaperDoll portrait is the CLASS icon
-- (no spec system on 3.3.5a), drawn from the class-icon atlas (FDID 1662186,
-- "classicon-<classfile>") registered by Agent F's Assets.lua.
-- ----------------------------------------------------------------------------
local function applyClassPortrait(frame)
  local p = frame and (frame.portrait or frame.PortraitTexture)
  if not p then return end
  local _, classFile = UnitClass("player")
  classFile = classFile and classFile:lower() or "warrior"
  local atlas = "classicon-" .. classFile
  -- NE.tex.SetAtlas returns false (and logs a miss) if the sheet isn't shipped — fall back to the
  -- native circular player portrait so the corner is never blank (graceful degrade).
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(p, atlas, false)) then
    if SetPortraitTexture then pcall(SetPortraitTexture, p, "player") end
  end
end
CP.ApplyClassPortrait = applyClassPortrait

-- ----------------------------------------------------------------------------
-- Build the custom frame shell (once). DF chrome + class portrait + DF close.
-- Sized to the COLLAPSED width; SetSidebarExpanded() grows it.
-- ----------------------------------------------------------------------------
local function buildFrame()
  if CP.frame then return CP.frame end

  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  f:SetSize(FRAME_W_COLLAPSED, FRAME_H)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:Hide()
  CP.frame = f
  CP._sidebarExpanded = false

  -- ESC closes it (DOWNPORT: by global name; no SetShown anywhere — Show/Hide only).
  if NE.FrameUtil and NE.FrameUtil.EscClose then
    NE.FrameUtil.EscClose(FRAME_NAME)
  else
    tinsert(UISpecialFrames, FRAME_NAME)
  end

  -- Draggable title band so the frame can be repositioned (DFUIC pattern).
  local drag = CreateFrame("Button", nil, f)
  drag:SetPoint("TOPLEFT", 60, -2)
  drag:SetPoint("TOPRIGHT", -30, -2)
  drag:SetHeight(28)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() f:StartMoving() end)
  drag:SetScript("OnDragStop", function() f:StopMovingOrSizing() end)

  -- DF portrait-frame chrome (nineslice + Rock bg + title). noPortrait=true: PanelChrome's default
  -- portrait fill is the PLAYER portrait + a watcher that re-asserts it on UNIT_PORTRAIT_UPDATE,
  -- which would fight our CLASS icon (§A.3). So we suppress its portrait entirely and OWN the
  -- portrait region ourselves below.
  guard("chrome.Apply", function()
    if NE.chrome and NE.chrome.Apply then
      NE.chrome.Apply(f, {
        layout     = "PortraitFrameTemplate",
        -- Title = the character's NAME (matches the example: "Ashgaroth"). UnitName may be nil at
        -- build time → fall back to "Character"; updateTitle() re-asserts the real name on login.
        title      = UnitName("player") or _G.CHARACTER or "Character",
        noPortrait = true,
      })
    end
  end)

  -- Own the portrait region: build the cutout texture + seat it in the metal corner, then fill it
  -- with the CLASS icon (and keep it correct across model/portrait events).
  guard("classPortrait", function()
    if not f.portrait then
      f.portrait = f:CreateTexture(nil, "ARTWORK")
    end
    if NE.portrait and NE.portrait.ApplyCutout then
      -- Default size/anchor (60 @ TOPLEFT -5,8). The grey "square outline" was NOT the cutout gap —
      -- it was opaque grey pixels in the inter-cell GAPS of the icon sheet that bilinear filtering
      -- bled at the texcoord edges. Fixed by clearing the WHOLE sheet's alpha (gaps → transparent),
      -- so size can stay at the correct 60.
      NE.portrait.ApplyCutout(f.portrait, f)
    end
    applyClassPortrait(f)
    f:HookScript("OnShow", function() applyClassPortrait(f) end)
    if not f._neClassPortraitWatcher then
      local w = CreateFrame("Frame", nil, f)
      w:RegisterEvent("UNIT_PORTRAIT_UPDATE")
      w:RegisterEvent("PLAYER_ENTERING_WORLD")
      w:SetScript("OnEvent", function(_, _, unit)
        if (not unit) or unit == "player" then applyClassPortrait(f) end
      end)
      f._neClassPortraitWatcher = w
    end
  end)

  -- DF modern close button. NE.chrome.Apply already built+modernized f.CloseButton; CloseButton.lua
  -- re-asserts it. Belt-and-suspenders here so the X exists even if that file failed to boot.
  guard("closeButton", function()
    if NE.panelchrome and NE.panelchrome.ModernizeCloseButton and f.CloseButton then
      NE.panelchrome.ModernizeCloseButton(f.CloseButton, { frameLevelBump = 20 })
    end
  end)

  -- Panel open/close sounds (igCharacterInfoOpen/Close), via a child watcher (never on the frame).
  guard("sounds", function()
    if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
      NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
    end
  end)

  return f
end
CP.BuildFrame = buildFrame

-- ----------------------------------------------------------------------------
-- Sidebar EXPAND / COLLAPSE. CONTRACT §C surface: the stats-sidebar agent (Wave 2) calls
-- NE.charpanel.SetSidebarExpanded(bool). Collapsed = frame 338, InsetRight hidden. Expanded =
-- frame 548, InsetRight shown. The left Inset is FIXED 328x360, so the model + slots NEVER move.
-- DOWNPORT: width changes on our (non-protected) frame are combat-legal; only the slot/model
-- REPARENT is gated out of combat. No SetShown on 3.3.5 — Show()/Hide() only.
-- ----------------------------------------------------------------------------
-- DOWNPORT/REPORT: per-tab frame/inset WIDTH (the state-machine fix). NewEra's
-- InsetFrames.lua (setInsetForTab/TAB_WIDTHS) gives the three Era-only tabs FULL-WIDTH content with
-- NO sidebar. Values read verbatim from NewEra: HonorFrame/ReputationFrame/SkillFrame = 445; the
-- fixed left-content (PaperDoll) Inset width = 328 (frame.BOTTOMLEFT + 332 with BR_X). Character/Pet
-- keep the fixed-width Inset + sidebar; the wide tabs stretch the Inset to the frame's right edge.
local WIDE_TAB_FRAME_W = 445   -- NewEra TAB_WIDTHS.{Honor,Reputation,Skill}Frame
local INSET_BR_RIGHT_X = -6    -- retail PANEL_INSET_RIGHT_OFFSET (Inset.BR -> frame.BOTTOMRIGHT)
local INSET_BR_BOT_Y   = 4     -- retail PANEL_INSET_BOTTOM_OFFSET
-- Mirror InsetFrames.lua's fixed-width anchor numbers (kept local; we re-assert them when restoring
-- the narrow paperdoll layout after a wide tab).
local INSET_TOP_X      = 4
local INSET_TOP_Y      = -60
local INSET_FIXED_BR_X = 332   -- gives the fixed 328-wide Inset (frame.BOTTOMLEFT + 332)

-- Re-anchor the Inset for the current tab: narrow/fixed (PaperDoll, Pet) vs wide/stretched (the three
-- Era tabs). DOWNPORT: pure SetPoint/ClearAllPoints on our own non-protected Inset — combat-legal.
local function applyInsetWidthForTab(wide)
  local f = CP.frame
  local inset = f and f.Inset
  if not inset then return end
  inset:ClearAllPoints()
  inset:SetPoint("TOPLEFT", f, "TOPLEFT", INSET_TOP_X, INSET_TOP_Y)
  if wide then
    -- Stretch the Inset BOTTOMRIGHT to the frame's right edge so the full-width content pane
    -- (SetAllPoints(Inset)) fills the wider frame.
    inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", INSET_BR_RIGHT_X, INSET_BR_BOT_Y)
  else
    -- Fixed-width left content: BOTTOMRIGHT pinned to frame.BOTTOMLEFT so model/slots never shift
    -- even when the frame expands for the sidebar.
    inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", INSET_FIXED_BR_X, INSET_BR_BOT_Y)
  end
end
CP.ApplyInsetWidthForTab = applyInsetWidthForTab

-- DOWNPORT/REPORT: gather the paperdoll DECORATIONS that are NOT children of the model/slots (so they
-- do NOT follow a slot/model Hide). SlotFrames.lua + InnerBorder.lua register their textures here.
CP._paperdollDecor = CP._paperdollDecor or {}

-- DOWNPORT/REPORT: ShowPaperDoll(show) — Show()/Hide() the WHOLE player-paperdoll group as one unit:
-- CharacterModelFrame (race-bg + model controls are its children, so they follow it), the 19 slot
-- buttons (their metal frames are children of the slots, so they follow), AND the decorations that
-- are NOT children of the slots/model (inner gold border + the slot metal frames, registered into
-- CP._paperdollDecor). Combat-safe — Show/Hide only on non-protected + Blizzard slot buttons; never
-- reparents. Each step pcall-guarded so a single bad widget can't break a tab switch.
local function showPaperDoll(show)
  show = show and true or false
  local model = _G.CharacterModelFrame
  if model then pcall(show and model.Show or model.Hide, model) end
  for _, name in ipairs(REPARENT_WIDGETS) do
    local b = _G[name]
    if b then pcall(show and b.Show or b.Hide, b) end
  end
  -- Decorations not parented to the slots/model (inner border pieces + slot metal frames).
  for _, t in ipairs(CP._paperdollDecor) do
    if t then pcall(show and t.Show or t.Hide, t) end
  end
end
CP.ShowPaperDoll = showPaperDoll

local function setSidebarExpanded(expanded)
  local f = CP.frame or buildFrame()
  if not f then return end
  expanded = expanded and true or false

  -- DOWNPORT/REPORT: the sidebar only exists on the paperdoll/pet tabs. If a wide (Era) tab is
  -- active, force-collapse: the wide tab owns the full frame width and has no sidebar. This makes
  -- SetSidebarExpanded resilient to being called after a secondary tab.
  local wideTab = CP._wideTabActive and true or false
  if wideTab then expanded = false end

  CP._sidebarExpanded = expanded

  if wideTab then
    -- Wide tab: frame = NewEra full-content width; Inset stretches to the frame edge; no sidebar.
    f:SetWidth(WIDE_TAB_FRAME_W)
    applyInsetWidthForTab(true)
  else
    -- Narrow paperdoll/pet: 338 collapsed / 548 expanded; Inset fixed-width (model/slots stay put).
    f:SetWidth(expanded and FRAME_W_EXPANDED or FRAME_W_COLLAPSED)
    applyInsetWidthForTab(false)
  end

  local ir = f.InsetRight
  if ir then
    if expanded then ir:Show() else ir:Hide() end
  end
end
CP.SetSidebarExpanded = setSidebarExpanded
CP.IsSidebarExpanded  = function() return CP._sidebarExpanded and true or false end

-- DOWNPORT/REPORT: TabButtons.selectTab calls this on every tab change to drive the per-tab frame/
-- inset width + paperdoll visibility + sidebar state. key == "Character" shows the player paperdoll;
-- Pet hides it (PetPaperDoll drives its OWN DragonUI_NewEra_PetModel, not CharacterModelFrame); the
-- three Era tabs go full-width with no model/slots/decor and no sidebar.
local WIDE_TAB_KEYS = { Skills = true, Honor = true, Reputation = true, Currency = true }
local function applyTabState(key)
  local f = CP.frame
  if not f then return end
  local wide = WIDE_TAB_KEYS[key] and true or false
  CP._wideTabActive = wide

  -- Player paperdoll only on the Character tab.
  pcall(showPaperDoll, key == "Character")

  if wide then
    -- Force-collapse the sidebar (hide InsetRight) and reset the saved expand flag, then go wide.
    CP._sidebarExpanded = false
    if f.InsetRight then f.InsetRight:Hide() end
    setSidebarExpanded(false)   -- wideTabActive=true path: sets WIDE width + stretched Inset
  else
    -- Narrow tab: restore the correct width. Character rests expanded (sidebar); Pet uses its own
    -- expand path (handled by selectTab). Re-assert the fixed-width Inset either way.
    setSidebarExpanded(CP._sidebarExpanded or false)
  end
end
CP.ApplyTabState = applyTabState

-- ----------------------------------------------------------------------------
-- Hide + intercept Blizzard's CharacterFrame (DFUIC mechanics, CONTRACT §A0).
--   * keep CharacterFrame hidden via an OnShow self-hide hook,
--   * save the global ToggleCharacter and replace it with one that drives ours.
-- Show/hide only — never reparent/teardown here (taint-free). Idempotent.
-- ----------------------------------------------------------------------------
local function interceptBlizzard()
  if CP._intercepted then return end
  CP._intercepted = true

  local cf = _G.CharacterFrame
  if cf and cf.HookScript then
    -- DOWNPORT: do NOT UnregisterAllEvents on CharacterFrame — its events drive the slot/model/stat
    -- updates that our reparented widgets still depend on. Just keep the FRAME hidden.
    cf:HookScript("OnShow", function(self)
      if not InCombatLockdown() then self:Hide() end
      -- Open ours to mirror Blizzard's intent (a path that bypassed ToggleCharacter still works).
      if not CP.frame or not CP.frame:IsShown() then CP.Toggle(true) end
    end)
  end

  -- Replace the global ToggleCharacter (save the old). Our replacement maps Blizzard's tab arg to
  -- ours and drives NE.charpanel.Toggle. DOWNPORT: combat-safe — Toggle no-ops the show in lockdown.
  if type(_G.ToggleCharacter) == "function" and not CP._oldToggleCharacter then
    CP._oldToggleCharacter = _G.ToggleCharacter
    _G.ToggleCharacter = function(which)
      CP.Toggle(nil, which)   -- nil = toggle; `which` selects the tab
    end
  end
end
CP.InterceptBlizzard = interceptBlizzard

-- ----------------------------------------------------------------------------
-- Position the reparented widgets per the VANILLA PaperDollFrame.xml anchors, translated to OUR
-- Inset. Idempotent — safe to re-run on every show (re-assert in case Blizzard re-anchored).
-- ----------------------------------------------------------------------------
local function positionSlots(host, modelFrame)
  local f = CP.frame
  if not host then return end

  -- LEFT column: Head at Inset.TOPLEFT(4,-2), chain each slot at prev BOTTOMLEFT (0,-4).
  local prev
  for i, name in ipairs(SLOT_LEFT) do
    local b = _G[name]
    if b then
      b:ClearAllPoints()
      if i == 1 then
        b:SetPoint("TOPLEFT", host, "TOPLEFT", LEFT_COL_X, LEFT_COL_Y)
      else
        b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, SLOT_VERT_GAP)
      end
      prev = b
    end
  end

  -- RIGHT column: Hands at Inset.TOPRIGHT(-4,-2), chain each slot at prev BOTTOMLEFT (0,-4).
  prev = nil
  for i, name in ipairs(SLOT_RIGHT) do
    local b = _G[name]
    if b then
      b:ClearAllPoints()
      if i == 1 then
        -- Vanilla Hands anchors TOPLEFT to PaperDollFrame; relative to our Inset we want the slot's
        -- TOPRIGHT pinned to the Inset's TOPRIGHT so the column hugs the right edge (VISUAL_SPEC).
        b:SetPoint("TOPRIGHT", host, "TOPRIGHT", RIGHT_COL_X, RIGHT_COL_Y)
      else
        b:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, SLOT_VERT_GAP)
      end
      prev = b
    end
  end

  -- BOTTOM weapon row: MainHand at Frame.BOTTOMLEFT(84,24); SecondaryHand/Ranged chain at prev
  -- TOPRIGHT (5,0) — the vanilla weapon-row spacing.
  prev = nil
  for i, name in ipairs(SLOT_BOTTOM) do
    local b = _G[name]
    if b then
      b:ClearAllPoints()
      if i == 1 then
        b:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", WEAPON_X, WEAPON_Y)
      else
        b:SetPoint("TOPLEFT", prev, "TOPRIGHT", SLOT_HORIZ_GAP, 0)
      end
      prev = b
    end
  end

  -- DOWNPORT/REPORT: faithful NewEra — model is FIXED 231x320 at Inset.TOPLEFT(52,-66), NOT box-filled
  -- and NOT centered. (Reverted the CP._dollBox fill.) Keep RefreshUnit/SetUnit (harmless reframe).
  if modelFrame then
    modelFrame:SetSize(MODEL_W, MODEL_H)
    modelFrame:ClearAllPoints()
    modelFrame:SetPoint("TOPLEFT", host, "TOPLEFT", MODEL_X, MODEL_Y)
    if modelFrame.RefreshUnit then pcall(modelFrame.RefreshUnit, modelFrame)
    elseif modelFrame.SetUnit then pcall(modelFrame.SetUnit, modelFrame, "player") end
  end
end
CP.PositionSlots = positionSlots

-- ----------------------------------------------------------------------------
-- Reparent the functional widgets ONCE, OUT OF COMBAT (CONTRACT §A0 + §B).
-- CharacterModelFrame + the 19 slot buttons -> our Inset, repositioned to the vanilla layout.
-- Texture/quality/click logic is LEFT ALONE (Blizzard drives them by global name).
-- ----------------------------------------------------------------------------
local function doReparent()
  local f = CP.frame
  if not f then return end
  -- Host = our Inset (left content pane). InsetFrames.lua builds it; fall back to the frame itself.
  local host = (f.Inset) or f
  local modelFrame = _G.CharacterModelFrame

  -- Reparent slots.
  for _, name in ipairs(REPARENT_WIDGETS) do
    local b = _G[name]
    if b and b.SetParent then
      b:SetParent(host)
      -- DOWNPORT: a reparented Blizzard child inherits OUR frame level; raise it above the inset
      -- nineslice/bg so the slot art + quality border aren't occluded.
      if b.SetFrameLevel then b:SetFrameLevel((host:GetFrameLevel() or 1) + 5) end
    end
  end
  -- Reparent the 3D model + its rotate buttons.
  if modelFrame and modelFrame.SetParent then
    modelFrame:SetParent(host)
    if modelFrame.SetFrameLevel then modelFrame:SetFrameLevel((host:GetFrameLevel() or 1) + 2) end
    for _, rn in ipairs({ "CharacterModelFrameRotateLeftButton", "CharacterModelFrameRotateRightButton" }) do
      local rb = _G[rn]
      if rb and rb.SetParent then rb:SetParent(modelFrame) end
    end
  end

  positionSlots(host, modelFrame)
  CP._reparented = true
end

-- Run the reparent exactly once, deferring into out-of-combat if needed.
local function reparentOnce()
  if CP._reparented then return end
  if InCombatLockdown() then
    if NE.FrameUtil and NE.FrameUtil.AfterCombat then
      NE.FrameUtil.AfterCombat(function() guard("reparent", doReparent) end)
    end
    return
  end
  guard("reparent", doReparent)
end
CP.ReparentWidgets = reparentOnce

-- ----------------------------------------------------------------------------
-- ReassertLayout — idempotent re-position of slots+model (cheap; safe out of combat). Called on
-- every show + tab switch so a Blizzard re-anchor can't drift our layout. Combat-guarded: SetPoint
-- on our reparented (non-protected-by-us) Blizzard children is legal out of combat only.
-- ----------------------------------------------------------------------------
local function reassertLayout()
  if not CP._reparented then return end
  if InCombatLockdown() then return end   -- DOWNPORT: skip in lockdown; re-asserted on next show
  local f = CP.frame
  if not f then return end
  local host = (f.Inset) or f
  guard("reassertLayout", function() positionSlots(host, _G.CharacterModelFrame) end)
end
CP.ReassertLayout = reassertLayout

-- ----------------------------------------------------------------------------
-- Toggle (show/hide our frame), combat-safe + tab-aware. CONTRACT surface.
--   Toggle(true)             -> show
--   Toggle(false)            -> hide
--   Toggle(nil)              -> flip
--   Toggle(_, "ReputationFrame"/...) -> show + select that tab
-- DOWNPORT: maps Blizzard's tab-name arg ("PaperDollFrame"/"PetPaperDollFrame"/
-- "ReputationFrame"/"SkillFrame"/"HonorFrame") to our SelectTab names.
-- ----------------------------------------------------------------------------
local BLIZ_TAB_TO_NAME = {
  PaperDollFrame    = "Character",
  PetPaperDollFrame = "Pets",
  ReputationFrame   = "Reputation",
  SkillFrame        = "Skills",
  HonorFrame        = "Honor",
  TokenFrame        = "Currency",
  CurrencyFrame     = "Currency",
}

function CP.Toggle(show, whichTab)
  local f = CP.frame or buildFrame()
  if not f then return end

  -- Decide target visibility.
  local target
  if show == true then target = true
  elseif show == false then target = false
  else target = not f:IsShown() end

  if not target then
    f:Hide()
    return
  end

  -- DOWNPORT: showing is the only "risky" path in combat (a protected reparent may still be pending);
  -- the Show itself is legal (our frame is not protected), but we must not reparent in lockdown.
  f:Show()
  reparentOnce()
  reassertLayout()

  local tabName = whichTab and BLIZ_TAB_TO_NAME[whichTab] or nil
  if tabName and CP.SelectTab then guard("selectTab", function() CP.SelectTab(tabName) end) end
end

-- ----------------------------------------------------------------------------
-- NE.charpanel public surface (CONTRACT §C). Implemented here: frame / Toggle / SetSidebarExpanded /
-- ReassertLayout / PositionSlots / ReparentWidgets. The real BuildInset/BuildInsetRight come from
-- InsetFrames.lua (loads after this file); SelectTab comes from TabButtons.lua; SelectSidebar is a
-- Wave-2 (sidebar) stub. Declare no-op placeholders so load order can't nil-deref.
-- ----------------------------------------------------------------------------
CP.BuildInset      = CP.BuildInset      or function() end
CP.BuildInsetRight = CP.BuildInsetRight or function() end
CP.SelectTab       = CP.SelectTab       or function(_) end

if not CP.SelectSidebar  then CP.SelectSidebar  = function(_) end end  -- Wave-2 (sidebar) fills

-- The canonical boot/re-entry: build the frame, intercept Blizzard, build insets/tabs, reparent.
-- Set the title bar to the character's NAME (example shows "Ashgaroth"). Re-asserted on login since
-- UnitName is nil at file/boot parse time.
-- Set the window header text directly. Exposed so the Titles pane can update it OPTIMISTICALLY on
-- click (UnitPVPName lags a frame behind SetCurrentTitle).
local function setWindowTitle(text)
  local f = CP.frame
  if not f or not text then return end
  local fs = f.Title or (f.TitleContainer and f.TitleContainer.TitleText)
  if fs and fs.SetText then fs:SetText(text)
  elseif NE.panelchrome and NE.panelchrome.SetTitle then pcall(NE.panelchrome.SetTitle, f, text) end
end
CP.SetWindowTitle = setWindowTitle

local function updateTitle()
  if not CP.frame then return end
  -- DOWNPORT/REPORT: UnitPVPName returns the player's name WITH their current title applied (e.g.
  -- "Magna the Explorer"); fall back to the plain name when there's no title.
  local name = (UnitPVPName and UnitPVPName("player"))
  if not name or name == "" then name = UnitName("player") end
  if name then setWindowTitle(name) end
end
CP.UpdateTitle = updateTitle

local function boot()
  buildFrame()
  guard("buildInset", function()
    if CP.BuildInset then CP.BuildInset() end
    if CP.BuildInsetRight then CP.BuildInsetRight() end
  end)
  guard("buildTabs", function() if CP.BuildTabs then CP.BuildTabs() end end)
  guard("intercept", interceptBlizzard)
  reparentOnce()
  guard("title", updateTitle)
  -- Resting state: the Character tab expands the stats sidebar (done by SelectTab). Honor the saved
  -- flag otherwise.
  guard("sidebarRest", function() setSidebarExpanded(CP._sidebarExpanded or false) end)
  guard("reassert", reassertLayout)
end
CP.Boot = boot

-- ----------------------------------------------------------------------------
-- Boot via Core/Modules.lua. PLAYER_LOGIN builds + intercepts + reparents (out of combat);
-- PLAYER_ENTERING_WORLD re-runs to catch any late-loaded tab content.
-- ----------------------------------------------------------------------------
if NE.modules and NE.modules.Register then
  NE.modules.Register{
    name    = MODULE,
    default = true,
    label   = "Character Panel",
    desc    = "The modern Dragonflight character window. Disable to keep the stock Blizzard frame.",
    events  = { "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD" },
    onBoot  = function() boot() end,
  }
else
  log("NE.modules.Register absent; character panel not booted")
end

-- ----------------------------------------------------------------------------
-- DragonUI integration (CONTRACT §A.1) — INLINE here per Agent A's brief. Our panel is a CUSTOM
-- frame (not a NE.RegisterPanel, no mover). open/close drive OUR Toggle (CONTRACT §A0 update).
-- Each handshake is independently guarded (NE.dragon.* may be absent on a standalone load).
-- ----------------------------------------------------------------------------
local function registerWithDragon()
  local title = "Character Panel"
  local desc  = "A modern Dragonflight character window (custom frame; the Blizzard frame is hidden)."

  local moduleTable = {
    ne_id   = MODULE,
    Enable  = function() CP.Toggle(true) end,
    Disable = function() CP.Toggle(false) end,
    Refresh = function() reassertLayout() end,
  }
  local dragon = NE.dragon
  if dragon then
    local mr = dragon.ModuleRegistry
    local registered = false
    if mr and type(mr.Register) == "function" then
      local ok = pcall(mr.Register, mr, "ne_" .. MODULE, moduleTable, title, desc, 20)
      registered = ok
      if not ok then log("ModuleRegistry:Register failed") end
    end
    if not registered and type(dragon.RegisterModule) == "function" then
      local ok = pcall(dragon.RegisterModule, dragon, "ne_" .. MODULE, moduleTable, title, desc, 20)
      if not ok then log("RegisterModule failed") end
    end
  end

  -- (b) Options-tab entry.
  NE.optionPanels = NE.optionPanels or {}
  local already = false
  for _, p in ipairs(NE.optionPanels) do if p.id == MODULE then already = true; break end end
  if not already then
    table.insert(NE.optionPanels, {
      id      = MODULE,
      title   = title,
      desc    = desc,
      order   = 20,
      refresh = function() reassertLayout() end,
    })
  end

  -- (c) QA harness entry (/dnetest). open/close drive OUR custom frame (CONTRACT §A0).
  NE.qa = NE.qa or { modules = {} }
  NE.qa.modules = NE.qa.modules or {}
  local inQa = false
  for _, m in ipairs(NE.qa.modules) do if m.name == "Character" then inQa = true; break end end
  if not inQa then
    table.insert(NE.qa.modules, {
      name     = "Character",
      getFrame = function() return CP.frame end,
      open     = function() CP.Toggle(true) end,
      close    = function() CP.Toggle(false) end,
    })
  end
end

guard("registerWithDragon", registerWithDragon)
