-- DragonUI_NewEra/modules/character/ModelArea.lua — race-keyed 4-part background behind the 3D model
-- (desaturated + dark overlay). Ported from NewEra/CharacterPanel/ModelArea.lua.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): the foundation (CharacterPanel.lua) already REPARENTED
-- CharacterModelFrame into our Inset and sized it to 231x320 at Inset.TOPLEFT(52,-66). So unlike
-- NewEra we DO NOT resize/anchor the model here — we ONLY stitch the race background behind it.
-- DOWNPORT: dropped NewEra's resizeModelFrame() (the foundation owns model geometry).
-- DOWNPORT/REPORT: race bg reverted to NATIVE retail quarter sizes anchored to the model's TOPLEFT
-- (231 wide = same as the model), NOT box-filled to the inter-column gap.
--
-- The 4 quarter textures are CHILD textures of the model frame at BACKGROUND layer, so they render
-- behind the 3D model. Keyed by UnitRace("player") -> race-bg FDIDs (registered in Assets.lua),
-- desaturated, with a per-race black overlay for the muted retail look.
--
-- GRACEFUL DEGRADATION (§B): every step pcall-guarded; missing art -> blank bg, never errors.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE = "character"

local function log(msg) if CP._log then CP._log(msg) elseif NE.Log then NE.Log("CHARPANEL", msg) end end

-- Race file name -> 4 quarter BLP FDIDs (registered local in Assets.lua). Matches NewEra's map.
local RACE_BG_FDIDS = {
  Dwarf    = {131089, 131090, 131091, 131092},
  Human    = {131093, 131094, 131095, 131096},
  NightElf = {131097, 131098, 131099, 131100},
  Orc      = {131101, 131102, 131103, 131104},
  Scourge  = {131105, 131106, 131107, 131108},
  Tauren   = {131109, 131110, 131111, 131112},
  Gnome    = {455998, 455999, 456000, 456001},
  Troll    = {456006, 456007, 456008, 456009},
}

-- Per-race overlay alpha (retail PaperDollFrame.lua). Default (Human/Dwarf/Tauren/Gnome) -> 0.7.
local RACE_OVERLAY_ALPHA = {
  BLOODELF = 0.8, NIGHTELF = 0.6, SCOURGE = 0.3,
  TROLL = 0.6, ORC = 0.6, WORGEN = 0.5, GOBLIN = 0.6,
}

local function resolveFdid(fdid)
  return (NE.tex and NE.tex.localFiles and NE.tex.localFiles[fdid]) or fdid
end

-- 4 quarter texture sources for a race file name (falls back to Orc — Era's nil-race default).
local function quarterSourcesFor(raceFileName)
  local fdids = RACE_BG_FDIDS[raceFileName] or RACE_BG_FDIDS.Orc
  return resolveFdid(fdids[1]), resolveFdid(fdids[2]), resolveFdid(fdids[3]), resolveFdid(fdids[4])
end

-- Build the 4 stitched BG textures + the black overlay (once), as children of the (already-sized)
-- model frame. Dimensions/texcoords verbatim from retail XML — the BG grid extends below the model
-- viewport behind the weapon row, as retail does.
-- DOWNPORT/REPORT: faithful NewEra — NATIVE retail quarter sizes anchored to the MODEL's TOPLEFT, so
-- the bg is 231 wide = the same width as the model (which the foundation sized to 231x320). Reverted
-- the prior box-fill math + BOX_INSET constants. Quarters: bgTL 212x245 @ model.TOPLEFT(0,0); bgTR
-- 19x245 @ bgTL.TOPRIGHT(0,0); bgBL 212x128 @ bgTL.BOTTOMLEFT(0,0); bgBR 19x128 @ bgTL.BOTTOMRIGHT
-- (0,0). Overlay TOPLEFT @ bgTL.TOPLEFT(0,0) / BOTTOMRIGHT @ bgBR.BOTTOMRIGHT(0,52).
local function buildBackground()
  local model = _G.CharacterModelFrame
  if not model or model._neRaceBgBuilt then return end

  -- DOWNPORT/REPORT: native quarter dimensions, anchored to the model frame's TOPLEFT (231 wide grid).
  local bgTL = model:CreateTexture(nil, "BACKGROUND")
  bgTL:SetSize(212, 245)
  bgTL:SetPoint("TOPLEFT", model, "TOPLEFT", 0, 0)
  bgTL:SetTexCoord(0.171875, 1, 0.0392156862745098, 1)

  local bgTR = model:CreateTexture(nil, "BACKGROUND")
  bgTR:SetSize(19, 245)
  bgTR:SetPoint("TOPLEFT", bgTL, "TOPRIGHT", 0, 0)
  bgTR:SetTexCoord(0, 0.296875, 0.0392156862745098, 1)

  local bgBL = model:CreateTexture(nil, "BACKGROUND")
  bgBL:SetSize(212, 128)
  bgBL:SetPoint("TOPLEFT", bgTL, "BOTTOMLEFT", 0, 0)
  bgBL:SetTexCoord(0.171875, 1, 0, 1)

  local bgBR = model:CreateTexture(nil, "BACKGROUND")
  bgBR:SetSize(19, 128)
  bgBR:SetPoint("TOPLEFT", bgTL, "BOTTOMRIGHT", 0, 0)
  bgBR:SetTexCoord(0, 0.296875, 0, 1)

  -- Black overlay (BORDER layer = above BACKGROUND, below the model) for the race tint. Retail extends
  -- the overlay 52px past the bg bottom to cover the seam below the model viewport.
  local overlay = model:CreateTexture(nil, "BORDER")
  -- DOWNPORT: 3.3.5a textures have no SetColorTexture; SetTexture(r,g,b) fills a solid color.
  if overlay.SetColorTexture then overlay:SetColorTexture(0, 0, 0) else overlay:SetTexture(0, 0, 0) end
  overlay:SetPoint("TOPLEFT", bgTL, "TOPLEFT", 0, 0)
  overlay:SetPoint("BOTTOMRIGHT", bgBR, "BOTTOMRIGHT", 0, 52)

  model._neBgTL, model._neBgTR, model._neBgBL, model._neBgBR = bgTL, bgTR, bgBL, bgBR
  model._neBgOverlay = overlay
  model._neRaceBgBuilt = true
end

local function applyRaceBackground()
  buildBackground()
  local model = _G.CharacterModelFrame
  if not model or not model._neRaceBgBuilt then return end

  local _, raceFile = UnitRace("player")
  if not raceFile then return end

  local q1, q2, q3, q4 = quarterSourcesFor(raceFile)
  model._neBgTL:SetTexture(q1)
  model._neBgTR:SetTexture(q2)
  model._neBgBL:SetTexture(q3)
  model._neBgBR:SetTexture(q4)

  -- Desaturate (retail's PaperDollBgDesaturate). Combined with the overlay -> muted atmospheric look.
  -- DOWNPORT: SetDesaturated returns false if the shader is unsupported; harmless (stays full color).
  for _, t in ipairs({ model._neBgTL, model._neBgTR, model._neBgBL, model._neBgBR }) do
    if t.SetDesaturated then pcall(t.SetDesaturated, t, true) end
  end

  local alpha = RACE_OVERLAY_ALPHA[raceFile:upper()] or 0.7
  model._neBgOverlay:SetAlpha(alpha)
end

CP.ApplyRaceBackground = applyRaceBackground

-- Reusable lookup (for a future InspectFrame port): 4 quarter sources + overlay alpha for a race file.
CP.RaceBgQuarters = function(raceFile)
  local q1, q2, q3, q4 = quarterSourcesFor(raceFile)
  local alpha = RACE_OVERLAY_ALPHA[(raceFile or ""):upper()] or 0.7
  return q1, q2, q3, q4, alpha
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled(MODULE) then return end
  local ok, err = pcall(applyRaceBackground)
  if not ok then log("ModelArea boot failed: " .. tostring(err)) end
end)
