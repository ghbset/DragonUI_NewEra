-- DragonUI_NewEra/modules/character/InnerBorder.lua — gold inner border wrapping the model/slot
-- viewport (4 corners + 4 tiled edges) + the full-width gold divider line above the weapon row.
-- Ported from NewEra/CharacterPanel/InnerBorder.lua.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): parented to OUR Inset (NE.charpanel.Inset), not Blizzard's
-- CharacterFrame.Inset. The Inset is FIXED 338x364, so the retail-faithful corner offsets translate
-- directly. Borders are OVERLAY textures on the Inset; they only make sense on the Character tab, so
-- we Show/Hide them from CP.SelectTab (our foundation's tab switch hook) — no taint risk since these
-- are OUR widgets, not Blizzard's protected fields.
--
-- ART (FDIDs 410247/410248/410249, registered in Assets.lua), with canonical-path fallback:
--   Corners (7x7):       Char-Paperdoll-Parts      (410248)
--   Horiz edges (h-tile): Char-Paperdoll-Horizontal (410247)
--   Vert edges  (v-tile): Char-Paperdoll-Vertical   (410249)
-- Texcoords transcribed verbatim from retail/NewEra CharacterFrame.xml.
--
-- GRACEFUL DEGRADATION (§B): build is pcall-guarded; missing art renders blank, never errors.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE = "character"

local function log(msg) if CP._log then CP._log(msg) elseif NE.Log then NE.Log("CHARPANEL", msg) end end

-- Art sources: prefer the shipped local BLP (Assets.lua), else the canonical 3.3.5a client path.
local function src(fdid, path)
  return (NE.tex and NE.tex.localFiles and NE.tex.localFiles[fdid]) or path
end
local BLP_PARTS      = src(410248, "Interface\\CharacterFrame\\Char-Paperdoll-Parts")
local BLP_HORIZONTAL = src(410247, "Interface\\CharacterFrame\\Char-Paperdoll-Horizontal")
local BLP_VERTICAL   = src(410249, "Interface\\CharacterFrame\\Char-Paperdoll-Vertical")

local CORNERS = {
  UpperLeft  = { 0.40625, 0.43359375, 0.80468750, 0.85937500 },
  UpperRight = { 0.40625, 0.43359375, 0.73437500, 0.78906250 },
  LowerLeft  = { 0.40625, 0.43359375, 0.66406250, 0.71875000 },
  LowerRight = { 0.40625, 0.43359375, 0.59375000, 0.64843750 },
}
local EDGE_TOP    = { 0.00000, 1.00000, 0.50000, 0.81250 }
local EDGE_BOTTOM = { 0.00000, 1.00000, 0.06250, 0.37500 }
local EDGE_LEFT   = { 0.06250, 0.37500, 0.00000, 1.00000 }
local EDGE_RIGHT  = { 0.50000, 0.81250, 0.00000, 1.00000 }

-- The created textures, kept on CP so the tab-visibility toggle can reach them.
CP._innerBorderPieces = CP._innerBorderPieces or {}
-- DOWNPORT/REPORT: shared paperdoll-decor list (also populated by SlotFrames.lua). The inner-border
-- pieces are children of the INSET, not the model/slots, so they do NOT follow a model/slot Hide —
-- they MUST be registered here so CP.ShowPaperDoll can hide them on non-Character tabs.
CP._paperdollDecor = CP._paperdollDecor or {}

-- Register a freshly-built border texture into the decor list (once).
local function registerDecor(t)
  if t then table.insert(CP._paperdollDecor, t) end
end

local function buildBorder()
  local f = CP.frame
  local inset = f and f.Inset
  if not inset then log("InnerBorder: Inset not built yet"); return end
  if inset._neInnerBorderBuilt then return end
  inset._neInnerBorderBuilt = true

  local pieces = CP._innerBorderPieces

  -- Corner: 7x7 from Char-Paperdoll-Parts, anchored relative to the Inset.
  local function corner(name, texcoord, point, relPoint, x, y)
    local t = inset:CreateTexture(nil, "OVERLAY")
    t:SetTexture(BLP_PARTS)
    t:SetSize(7, 7)
    t:SetTexCoord(texcoord[1], texcoord[2], texcoord[3], texcoord[4])
    t:SetPoint(point, inset, relPoint, x, y)
    pieces[name] = t
    return t
  end

  -- Retail-faithful corner offsets (NewEra CharacterFrame.xml). Inset is FIXED 338x364.
  local tl = corner("TopLeft",     CORNERS.UpperLeft,  "TOPLEFT",     "TOPLEFT",      46,  -4)
  local tr = corner("TopRight",    CORNERS.UpperRight, "TOPRIGHT",    "TOPRIGHT",    -47,  -4)
  local bl = corner("BottomLeft",  CORNERS.LowerLeft,  "BOTTOMLEFT",  "BOTTOMLEFT",   46,  31)
  local br = corner("BottomRight", CORNERS.LowerRight, "BOTTOMRIGHT", "BOTTOMRIGHT", -47,  31)

  -- Vertical edges (5px wide, v-tiled) connecting the corners.
  local left = inset:CreateTexture(nil, "OVERLAY")
  left:SetTexture(BLP_VERTICAL); left:SetVertTile(true)
  left:SetTexCoord(EDGE_LEFT[1], EDGE_LEFT[2], EDGE_LEFT[3], EDGE_LEFT[4])
  left:SetWidth(5)
  left:SetPoint("TOPLEFT",    tl, "BOTTOMLEFT", -1, 0)
  left:SetPoint("BOTTOMLEFT", bl, "TOPLEFT",    -1, 0)
  pieces.Left = left

  local right = inset:CreateTexture(nil, "OVERLAY")
  right:SetTexture(BLP_VERTICAL); right:SetVertTile(true)
  right:SetTexCoord(EDGE_RIGHT[1], EDGE_RIGHT[2], EDGE_RIGHT[3], EDGE_RIGHT[4])
  right:SetWidth(5)
  right:SetPoint("TOPRIGHT",    tr, "BOTTOMRIGHT", 1, 0)
  right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT",    1, 0)
  pieces.Right = right

  -- Horizontal edges (5px tall, h-tiled).
  local top = inset:CreateTexture(nil, "OVERLAY")
  top:SetTexture(BLP_HORIZONTAL); top:SetHorizTile(true)
  top:SetTexCoord(EDGE_TOP[1], EDGE_TOP[2], EDGE_TOP[3], EDGE_TOP[4])
  top:SetHeight(5)
  top:SetPoint("TOPLEFT",  tl, "TOPRIGHT", 0, 1)
  top:SetPoint("TOPRIGHT", tr, "TOPLEFT",  0, 1)
  pieces.Top = top

  local bottom = inset:CreateTexture(nil, "OVERLAY")
  bottom:SetTexture(BLP_HORIZONTAL); bottom:SetHorizTile(true)
  bottom:SetTexCoord(EDGE_BOTTOM[1], EDGE_BOTTOM[2], EDGE_BOTTOM[3], EDGE_BOTTOM[4])
  bottom:SetHeight(5)
  bottom:SetPoint("BOTTOMLEFT",  bl, "BOTTOMRIGHT", 0, -1)
  bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT",  0, -1)
  pieces.Bottom = bottom

  -- The full-width gold divider: the SECOND horizontal line that runs across the whole Inset width at
  -- y=+27 above the bottom — the separator above the weapon row crossing under the slot columns.
  local bottom2 = inset:CreateTexture(nil, "OVERLAY")
  bottom2:SetTexture(BLP_HORIZONTAL); bottom2:SetHorizTile(true)
  bottom2:SetTexCoord(EDGE_BOTTOM[1], EDGE_BOTTOM[2], EDGE_BOTTOM[3], EDGE_BOTTOM[4])
  bottom2:SetHeight(5)
  bottom2:SetPoint("BOTTOMLEFT",  inset, "BOTTOMLEFT",  0, 27)
  bottom2:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 27)
  pieces.Bottom2 = bottom2

  -- DOWNPORT/REPORT: register every border piece into the shared paperdoll-decor list so
  -- CP.ShowPaperDoll hides them on non-Character tabs (they are Inset children, not model/slot
  -- children, so they would otherwise stay visible).
  for _, t in pairs(pieces) do registerDecor(t) end
end

-- Show/hide the border by active tab. Borders frame the PaperDoll model+slots, so they only show on
-- the Character tab. DOWNPORT: no taint risk (our own textures); no SetShown — Show()/Hide() only.
local function setBorderVisibility(visible)
  for _, t in pairs(CP._innerBorderPieces) do
    if t then if visible then t:Show() else t:Hide() end end
  end
end
CP.SetInnerBorderVisible = setBorderVisibility

-- Hook the foundation's tab switch so the border tracks the active tab. Wrapped once.
local function hookTabVisibility()
  if CP._innerBorderTabHooked then return end
  if type(CP.SelectTab) ~= "function" then return end
  CP._innerBorderTabHooked = true
  hooksecurefunc(CP, "SelectTab", function(name)
    setBorderVisibility(name == nil or name == "Character")
  end)
  -- Initial state: visible if the resting tab is Character (the foundation default).
  setBorderVisibility((CP._activeTab or "Character") == "Character")
end

CP.BuildInnerBorder = buildBorder

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled(MODULE) then return end
  local ok, err = pcall(function()
    -- Ensure the Inset exists (the foundation builds it at PLAYER_LOGIN; build defensively).
    if CP.frame and not CP.frame.Inset and CP.BuildInset then CP.BuildInset() end
    buildBorder()
    hookTabVisibility()
  end)
  if not ok then log("InnerBorder boot failed: " .. tostring(err)) end
end)
