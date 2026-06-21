-- DragonUI_NewEra/modules/character/CloseButton.lua — ensure OUR custom frame's close button is the
-- DF red X (RedButton-Exit-2x family).
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): the close button belongs to OUR frame
-- (NE.charpanel.frame = "DragonUI_NewEra_Character"), not Blizzard's CharacterFrame. NE.chrome.Apply
-- (called from CharacterPanel.lua's buildFrame) already BUILDS + modernizes frame.CloseButton via
-- core/PanelChrome.lua. This file is a thin, idempotent re-assert so:
--   * the X is modernized even if NE.chrome.Apply's close-button step happened to no-op, and
--   * it sits ABOVE the chrome stack (nineslice top-right corner + title band) — frameLevelBump.
--
-- PanelChrome.ModernizeCloseButton already applies the Sprint-0 lessons (SetNormalTexture takes a
-- PATH not an object; degrades to native UIPanelCloseButton art if the atlas isn't shipped — never
-- blank). All ops are non-protected. Idempotent (the helper guards with _neCloseModernized).

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local function modernize()
  local f = CP.frame
  if not f or not f.CloseButton then return end
  if NE.panelchrome and NE.panelchrome.ModernizeCloseButton then
    -- frameLevelBump lifts the X above the nineslice + title-band stack so it isn't occluded.
    NE.panelchrome.ModernizeCloseButton(f.CloseButton, { frameLevelBump = 20 })
  end
  -- Make sure clicking it actually closes OUR frame (UIPanelCloseButton's default HideParent fires
  -- on the parent, which is our frame — so this is belt-and-suspenders for a re-anchored button).
  if not f.CloseButton._neCharClose then
    f.CloseButton._neCharClose = true
    f.CloseButton:HookScript("OnClick", function() if CP.Toggle then CP.Toggle(false) end end)
  end
end

CP.ModernizeCloseButton = modernize

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  -- Ensure the frame (and thus its CloseButton) exists, then modernize.
  if CP.BuildFrame then pcall(CP.BuildFrame) end
  local ok, err = pcall(modernize)
  if not ok and CP._log then CP._log("close button modernize failed: " .. tostring(err)) end
end)
