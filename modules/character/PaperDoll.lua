-- DragonUI_NewEra/modules/character/PaperDoll.lua — the class-themed background behind the stats pane.
--
-- ARCHITECTURE (CONTRACT_S1 §A0 / VISUAL_SPEC): mirrors retail's CharacterStatsPane.ClassBackground —
-- a per-class backdrop (197x355, ui-character-info-<classfile>-bg) anchored TOPLEFT(0,0) of
-- NE_CharacterStatsPane. The atlases (FDID 1400895 / 1400896) + their rects are registered by Agent F's
-- Assets.lua; we just pick the player's class atlas and seat it.
--
-- Ported from NewEra/CharacterPanel/PaperDoll.lua. The pane is built lazily by Sidebar.lua (on first
-- sidebar build); buildSidebar calls CP.ApplyClassBackground the moment NE_CharacterStatsPane exists,
-- and a login-time retry covers the already-built / late-load case.
--
-- 3.3.5 GOTCHAS (§B): no SetShown (Show/Hide); NE.tex.SetAtlas returns false if the class-bg sheet
-- isn't shipped → we simply skip (the marble inset bg from InsetFrames.lua remains; graceful).

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local function log(msg)
  if CP._log then CP._log(msg); return end
  if NE.Log then NE.Log("PAPERDOLL", msg) end
end

-- classfile (UnitClass) -> atlas name. All 12 are registered in Assets.lua; 3.3.5 only has the 9
-- vanilla+wrath classes, but resolving the rest is harmless (a custom server could add them).
local CLASS_BG_ATLAS = {
  DRUID       = "ui-character-info-druid-bg",
  HUNTER      = "ui-character-info-hunter-bg",
  MAGE        = "ui-character-info-mage-bg",
  PALADIN     = "ui-character-info-paladin-bg",
  PRIEST      = "ui-character-info-priest-bg",
  ROGUE       = "ui-character-info-rogue-bg",
  SHAMAN      = "ui-character-info-shaman-bg",
  WARLOCK     = "ui-character-info-warlock-bg",
  WARRIOR     = "ui-character-info-warrior-bg",
  DEATHKNIGHT = "ui-character-info-deathknight-bg",
  DEMONHUNTER = "ui-character-info-demonhunter-bg",
  MONK        = "ui-character-info-monk-bg",
}

-- Apply the class background to NE_CharacterStatsPane (built by Sidebar.lua).
local function applyClassBackground()
  local pane = _G.NE_CharacterStatsPane or (CP._sidebar)
  if not pane then return end
  local _, classFile = UnitClass("player")
  if not classFile then return end
  local atlas = CLASS_BG_ATLAS[classFile]
  if not atlas then log("no class bg atlas for " .. tostring(classFile)); return end

  local bg = pane._neClassBg
  if not bg then
    -- Below the stat rows + marble inset, above nothing. Retail anchors TOPLEFT(0,0), useAtlasSize.
    bg = pane:CreateTexture(nil, "BACKGROUND", nil, -3)
    bg:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
    bg:SetSize(197, 355)
    bg:SetAlpha(0.55)   -- DOWNPORT: dim slightly so the stat text stays legible over the art
    pane._neClassBg = bg
  end

  if NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(bg, atlas, false) then
    bg:Show()
  else
    -- Atlas not shipped → leave the marble inset bg; hide our (blank) texture so it can't blank art.
    bg:Hide()
  end
end
CP.ApplyClassBackground = applyClassBackground

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  applyClassBackground()
  -- Retry shortly in case Sidebar.lua hasn't built the pane yet (PaperDoll loads before Sidebar).
  if not (_G.NE_CharacterStatsPane and _G.NE_CharacterStatsPane._neClassBg) then
    if C_Timer and C_Timer.After then C_Timer.After(0.5, applyClassBackground) end
  end
end)
