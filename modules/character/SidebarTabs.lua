-- DragonUI_NewEra/modules/character/SidebarTabs.lua — the 3-tab sidebar strip (PaperDollSidebarTabs).
--
-- ARCHITECTURE (CONTRACT_S1 §A0 / VISUAL_SPEC): a 168x35 strip above NE.charpanel.InsetRight with 3
-- tabs (33x35 each). Ported from NewEra/CharacterPanel/SidebarTabs.lua, re-hosted on OUR custom frame's
-- InsetRight (not Blizzard's CharacterFrame):
--   Tab1  Character / Stats  — player FACE portrait icon → SelectSidebar(1)
--   Tab2  Titles             — permanently DISABLED (no title system on 3.3.5) → tooltip explains
--   Tab3  Equipment Manager  — → SelectSidebar(3) → NE.charpanel.ShowEquipManager (Agent E; guarded)
--
-- The strip art is the STOCK 3.3.5a sheet Interface\PaperDollInfoFrame\PaperDollSidebarTabs (canonical
-- since vanilla, present on this client) — used by raw path + texcoord (no atlas registration needed).
--
-- 3.3.5 GOTCHAS (§B): SetPortraitTexture is natively circular; SetMotionScriptsWhileDisabled may be
-- absent (pcall); no SetShown (Show/Hide); raise nothing (the strip parents to InsetRight). Clicking a
-- tab plays the stock tab SFX. The strip mirrors InsetRight's visibility via OnShow/OnHide hooks.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

-- DOWNPORT: Interface\PaperDollInfoFrame\PaperDollSidebarTabs is a Cata+ sheet absent on 3.3.5a. We
-- SHIP the real Blizzard sheet (from ElvUI_Enhanced's copy) so NewEra's texcoords render exactly. The
-- 64x256 layout matches NewEra's TC rects (decorLeft → 28x11px, etc.).
local SIDEBAR_BLP = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\CharacterPanel\\PaperDollSidebarTabs"

local function log(msg)
  if CP._log then CP._log(msg); return end
  if NE.Log then NE.Log("SIDEBARTABS", msg) end
end

-- Texcoords transcribed from NewEra/CharacterPanel/SidebarTabs.lua (the stock PaperDollSidebarTabs layout).
local TC = {
  decorLeft    = { 0.01562500, 0.45312500, 0.00390625, 0.04687500 },  -- 28x11
  decorRight   = { 0.01562500, 0.45312500, 0.05468750, 0.10546875 },  -- 28x13
  tabBg        = { 0.01562500, 0.79687500, 0.61328125, 0.78125000 },  -- inactive 50x43
  tabBgActive  = { 0.01562500, 0.79687500, 0.78906250, 0.95703125 },  -- active row
  tabHider     = { 0.01562500, 0.54687500, 0.11328125, 0.18750000 },  -- 34x19 bottom cap
  tabHighlight = { 0.01562500, 0.50000000, 0.19531250, 0.31640625 },  -- 31x31 hover
  titlesIcon   = { 0.01562500, 0.53125000, 0.32421875, 0.46093750 },  -- Tab2 icon
  equipIcon    = { 0.01562500, 0.53125000, 0.46875000, 0.60546875 },  -- Tab3 icon
}

local function L(global, fallback)
  local v = _G[global]
  if type(v) == "string" and v ~= "" then return v end
  return fallback
end

-- Build one tab. iconKind: "face" = player portrait (Tab1); "tex" = sub-rect of the sheet.
local function buildTab(id, parent, name, iconKind, texCoord, tooltip, enabled, onClick)
  local tab = CreateFrame("Button", name, parent)
  tab:SetSize(33, 35)
  tab._tabId = id

  -- Show tooltips even while disabled (so the Titles tab can explain why it's off). May be absent.
  if tab.SetMotionScriptsWhileDisabled then pcall(tab.SetMotionScriptsWhileDisabled, tab, true) end

  -- Tab BG (BACKGROUND). styleTab swaps inactive/active rows.
  local bg = tab:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(SIDEBAR_BLP)
  bg:SetSize(50, 43)
  bg:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", -9, -2)
  bg:SetTexCoord(unpack(TC.tabBg))
  tab.TabBg = bg

  -- Icon (ARTWORK).
  local icon = tab:CreateTexture(nil, "ARTWORK")
  tab.Icon = icon
  if iconKind == "face" then
    -- Player face portrait, inset to 29x31 so the tab's selected/hover border shows around it.
    icon:SetSize(29, 31)
    icon:SetPoint("BOTTOM", tab, "BOTTOM", 1, 0)
    local function refreshFace()
      if SetPortraitTexture then pcall(SetPortraitTexture, icon, "player") end
      icon:SetTexCoord(0.109375, 0.890625, 0.09375, 0.90625)
    end
    refreshFace()
    local ev = CreateFrame("Frame", nil, tab)
    ev:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(_, evt, unit)
      if evt == "UNIT_PORTRAIT_UPDATE" and unit and unit ~= "player" then return end
      refreshFace()
    end)
  else
    icon:SetSize(33, 35)
    icon:SetPoint("BOTTOM", tab, "BOTTOM", 1, -2)
    icon:SetTexture(SIDEBAR_BLP)
    if texCoord then icon:SetTexCoord(unpack(texCoord)) end
  end

  -- Hider (OVERLAY) — caps the bottom of an UNSELECTED tab; styleTab hides it when selected.
  local hider = tab:CreateTexture(nil, "OVERLAY")
  hider:SetTexture(SIDEBAR_BLP)
  hider:SetSize(34, 19)
  hider:SetPoint("BOTTOM")
  hider:SetTexCoord(unpack(TC.tabHider))
  tab.Hider = hider

  -- Highlight (HIGHLIGHT layer = auto-render on mouseover).
  local hl = tab:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture(SIDEBAR_BLP)
  hl:SetSize(31, 31)
  hl:SetPoint("TOPLEFT", 2, -3)
  hl:SetTexCoord(unpack(TC.tabHighlight))
  tab.Highlight = hl

  tab:SetScript("OnEnter", function(self)
    if not (tooltip and tooltip.title) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(tooltip.title, 1, 1, 1)
    if not self:IsEnabled() and tooltip.disabled then
      GameTooltip:AddLine(tooltip.disabled, 1, 0.1, 0.1, true)
    end
    GameTooltip:Show()
  end)
  tab:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Disabled state: alpha 0.5 + desaturated icon.
  tab:SetScript("OnEnable", function(self)
    self:SetAlpha(1)
    if self.Icon and self.Icon.SetDesaturated then self.Icon:SetDesaturated(false) end
  end)
  tab:SetScript("OnDisable", function(self)
    self:SetAlpha(0.5)
    if self.Icon and self.Icon.SetDesaturated then self.Icon:SetDesaturated(true) end
  end)

  if onClick then
    tab:SetScript("OnClick", function(self, ...)
      if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
      onClick(self, ...)
    end)
  end

  if enabled then tab:Enable() else tab:Disable() end
  return tab
end

-- Selected/unselected styling (NewEra PaperDollFrame_UpdateSidebarTabs).
local function styleTab(tab, selected)
  if not tab then return end
  if selected then
    if tab.Hider then tab.Hider:Hide() end
    if tab.Highlight then tab.Highlight:Hide() end
    if tab.TabBg then tab.TabBg:SetTexCoord(unpack(TC.tabBgActive)) end
  else
    if tab.Hider then tab.Hider:Show() end
    if tab.Highlight then tab.Highlight:Show() end
    if tab.TabBg then tab.TabBg:SetTexCoord(unpack(TC.tabBg)) end
  end
end

local function buildSidebarTabs()
  local f = CP.frame
  local insetRight = f and (f.InsetRight or CP.InsetRight)
  if not insetRight then log("buildSidebarTabs: InsetRight not ready"); return end
  if f._neSidebarTabs then return f._neSidebarTabs end

  local strip = CreateFrame("Frame", "NE_PaperDollSidebarTabs", insetRight)
  strip:SetSize(168, 35)
  -- Anchored ABOVE InsetRight (NewEra offsets verbatim).
  strip:SetPoint("BOTTOMRIGHT", insetRight, "TOPRIGHT", -6, -1)
  f._neSidebarTabs = strip
  CP.SidebarTabs = strip

  -- Decorative caps.
  local dl = strip:CreateTexture(nil, "ARTWORK")
  dl:SetTexture(SIDEBAR_BLP); dl:SetSize(28, 11)
  dl:SetPoint("BOTTOMLEFT"); dl:SetTexCoord(unpack(TC.decorLeft))
  strip.DecorLeft = dl

  local dr = strip:CreateTexture(nil, "ARTWORK")
  dr:SetTexture(SIDEBAR_BLP); dr:SetSize(28, 13)
  dr:SetPoint("BOTTOMRIGHT"); dr:SetTexCoord(unpack(TC.decorRight))
  strip.DecorRight = dr

  -- Build right-to-left (NewEra chain anchors).
  -- Tab3: Equipment Manager → SelectSidebar(3) (which routes to ShowEquipManager, guarded).
  local tab3 = buildTab(3, strip, "NE_PaperDollSidebarTab3", "tex", TC.equipIcon,
    { title = L("PAPERDOLL_EQUIPMENTMANAGER", "Equipment Manager") }, true,
    function() if CP.SelectSidebar then CP.SelectSidebar(3) end end)
  tab3:SetPoint("BOTTOMRIGHT", strip, "BOTTOMRIGHT", -30, 0)
  strip.Tab3 = tab3

  -- Tab2: Titles — ENABLED on 3.3.5 (WotLK has the title system, unlike Classic Era which NewEra
  -- targeted). Selects the titles pane (CP.SelectSidebar(2) → TitlesPane.ShowTitles).
  local tab2 = buildTab(2, strip, "NE_PaperDollSidebarTab2", "tex", TC.titlesIcon,
    { title = L("PAPERDOLL_SIDEBAR_TITLES", "Titles") }, true,
    function() if CP.SelectSidebar then CP.SelectSidebar(2) end end)
  tab2:SetPoint("RIGHT", tab3, "LEFT", -4, 0)
  strip.Tab2 = tab2

  -- Tab1: Character — player face portrait → SelectSidebar(1) (stats pane).
  local tab1 = buildTab(1, strip, "NE_PaperDollSidebarTab1", "face", nil,
    { title = L("PAPERDOLL_SIDEBAR_STATS", "Character") }, true,
    function() if CP.SelectSidebar then CP.SelectSidebar(1) end end)
  tab1:SetPoint("RIGHT", tab2, "LEFT", -4, 0)
  strip.Tab1 = tab1

  -- Selected-state helper consumed by CP.SelectSidebar (Sidebar.lua).
  CP.SetSidebarTabSelected = function(index)
    styleTab(strip.Tab1, index == 1)
    styleTab(strip.Tab2, index == 2)
    styleTab(strip.Tab3, index == 3)
  end
  CP.SetSidebarTabSelected(CP._activeSidebar or 1)

  -- Strip visibility mirrors InsetRight (sidebar expanded). DOWNPORT: no SetShown — Show/Hide only.
  insetRight:HookScript("OnShow", function() strip:Show() end)
  insetRight:HookScript("OnHide", function() strip:Hide() end)
  if not insetRight:IsShown() then strip:Hide() end

  return strip
end
CP.BuildSidebarTabs = buildSidebarTabs

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  local ok, err = pcall(buildSidebarTabs)
  if not ok then log("sidebar tabs build failed: " .. tostring(err)) end
end)
