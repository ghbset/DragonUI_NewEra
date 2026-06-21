-- DragonUI_NewEra/modules/character/InsetFrames.lua — the Inset + InsetRight content/sidebar hosts.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): these are children of OUR custom frame
-- (NE.charpanel.frame = "DragonUI_NewEra_Character"), NOT Blizzard's CharacterFrame.
--
-- GEOMETRY (DOWNPORT/REPORT — faithful NewEra/CharacterPanel/InsetFrames.lua):
--   frame.Inset       — left content pane, FIXED 328x360 via TWO anchors: TOPLEFT(4,-60) +
--                       BOTTOMRIGHT to frame.BOTTOMLEFT + (332,4). Holds the reparented 3D model +
--                       equipment slots + per-tab content panes. Fixed WIDTH (BOTTOMRIGHT anchored to
--                       frame.BOTTOMLEFT) so it does NOT resize when the sidebar expands — model/slots
--                       stay put. Mirrors retail UpdateSize pinning Inset to PANEL_DEFAULT_WIDTH.
--   frame.InsetRight  — sidebar host, auto-sizing via TWO anchors: TOPLEFT = Inset.TOPRIGHT+(1,0),
--                       BOTTOMRIGHT = frame.BOTTOMRIGHT+(-4,4). ~1px collapsed, ~211px when expanded.
--                       HIDDEN until the panel expands for the sidebar (SetSidebarExpanded shows it).
--
-- Each gets an InsetFrameTemplate nineslice (thin gold inner border) + a marble inner bg, matching
-- retail's InsetFrameTemplate. All ops are CreateFrame / CreateTexture / SetPoint — combat-legal.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

-- VISUAL_SPEC / NewEra geometry constants.
-- DOWNPORT/REPORT: faithful NewEra port — Inset is FIXED-width via TWO anchors
-- (TOPLEFT(4,-60) + BOTTOMRIGHT to frame.BOTTOMLEFT + (332,4)) = 328 wide x 360 tall,
-- not a SetSize. This keeps the Inset width fixed even when the frame expands.
local INSET_LEFT_X   =  4    -- Frame.TOPLEFT x for the Inset
local INSET_TOP_Y    = -60   -- DOWNPORT/REPORT: revert to NewEra PANEL_INSET_ATTIC_OFFSET (-60); was -50
local INSET_BR_X     = 332   -- DOWNPORT/REPORT: BOTTOMRIGHT-to-frame.BOTTOMLEFT x (gives 328 fixed width)
local INSET_BR_Y     =  4    -- DOWNPORT/REPORT: BOTTOMRIGHT-to-frame.BOTTOMLEFT y
local INSETRIGHT_X   =  1    -- Inset.TOPRIGHT x for InsetRight (retail (1,0))
local INSETRIGHT_Y   =  0    -- Inset.TOPRIGHT y for InsetRight

local function log(msg) if CP._log then CP._log(msg) end end

-- Decorate an inset: marble Bg (BACKGROUND -5) + InsetFrameTemplate inner nineslice (thin gold trim).
-- DOWNPORT: marble path is the stock 3.3.5a UI-Background-Marble. Idempotent.
local function decorateInset(inset)
  if not inset or inset._neDecorated then return end

  local bg = inset:CreateTexture(nil, "BACKGROUND", nil, -5)
  bg:SetTexture("Interface\\FrameGeneral\\UI-Background-Marble", "REPEAT", "REPEAT")
  bg:SetHorizTile(true)
  bg:SetVertTile(true)
  bg:SetAllPoints(inset)
  inset.Bg = bg

  if NE.nineslice and NE.nineslice.ApplyLayout then
    NE.nineslice.ApplyLayout(inset, "InsetFrameTemplate")
  end

  inset._neDecorated = true
end
CP.DecorateInset = decorateInset

-- Build frame.Inset (left content pane). FIXED 338x364 at Frame.TOPLEFT(4,-60).
-- DOWNPORT: anchor ONLY the TOPLEFT + SetSize (not a BOTTOMRIGHT anchor) so the Inset width is fixed
-- and never tracks the frame's width when the sidebar expands.
local function buildInset()
  local f = CP.frame or (CP.BuildFrame and CP.BuildFrame())
  if not f then log("buildInset: frame not built yet"); return nil end
  if f.Inset then decorateInset(f.Inset); return f.Inset end

  local inset = CreateFrame("Frame", "DragonUI_NewEra_CharacterInset", f)
  -- DOWNPORT/REPORT: faithful NewEra — two anchors (TOPLEFT + BOTTOMRIGHT-to-frame.BOTTOMLEFT),
  -- NOT SetSize. Fixed 328 wide x 360 tall; does not grow when the frame expands.
  inset:SetPoint("TOPLEFT", f, "TOPLEFT", INSET_LEFT_X, INSET_TOP_Y)
  inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMLEFT", INSET_BR_X, INSET_BR_Y)
  f.Inset = inset

  decorateInset(inset)
  return inset
end

-- Build frame.InsetRight (sidebar host). 209x364 at Inset.TOPRIGHT(1,0). Hidden by default; shown by
-- NE.charpanel.SetSidebarExpanded (Wave 2 fills the body).
local function buildInsetRight()
  local f = CP.frame
  if not f then log("buildInsetRight: frame not built yet"); return nil end
  if f.InsetRight then decorateInset(f.InsetRight); return f.InsetRight end
  local inset = f.Inset
  if not inset then log("buildInsetRight: Inset not built yet"); return nil end

  local insetRight = CreateFrame("Frame", "DragonUI_NewEra_CharacterInsetRight", f)
  -- DOWNPORT/REPORT: faithful NewEra — two anchors (auto-sizing): TOPLEFT = Inset.TOPRIGHT+(1,0),
  -- BOTTOMRIGHT = frame.BOTTOMRIGHT+(-4,4). ~1px collapsed, ~211px when frame=548. NOT SetSize.
  insetRight:SetPoint("TOPLEFT", inset, "TOPRIGHT", INSETRIGHT_X, INSETRIGHT_Y)
  insetRight:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4)
  insetRight:Hide()   -- DOWNPORT: no SetShown on 3.3.5a; Hide()/Show() only. Shown on expand.
  f.InsetRight = insetRight

  decorateInset(insetRight)
  return insetRight
end

-- Publish the surface (overwrites the CharacterPanel.lua no-op placeholders).
CP.BuildInset      = buildInset
CP.BuildInsetRight = buildInsetRight

-- Boot: build at PLAYER_LOGIN so SlotFrames/Sidebar (Wave 2) + the reparent pass can depend on the
-- Insets existing. Gated on the module being enabled. DOWNPORT: build defensively — CharacterPanel
-- .boot also calls BuildInset, but an enabled module always wants its anchors regardless of ordering.
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  local ok, err = pcall(function() buildInset(); buildInsetRight() end)
  if not ok then log("inset build failed: " .. tostring(err)) end
end)
