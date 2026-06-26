-- DragonUI_NewEra/modules/talents/SpecTabs.lua — dual-spec BOTTOM tabs (+ rename cog).
--
-- Two tabs along the bottom of NE_TalentFrame (same DF metal tab art as the spellbook/character
-- panel, via NE.tabs.ReskinClassicTab) switch the VIEWED spec. Behavior owns the data:
--   * T._activeGroup — the live spec (GetActiveTalentGroup); the ONLY editable one.
--   * T._viewGroup   — the spec currently displayed; set here on click.
--
-- Each tab shows the spec NAME: a CUSTOM name (set via the cog button, persisted per-character) or
-- the default "Primary"/"Secondary". The tab auto-sizes to its text. Names are letters-only, capped
-- at 16 chars. Tabs only appear when GetNumTalentGroups() >= 2 (Dual Talent Specialization learned).

local NE = DragonUI_NewEra
local T  = NE.talents or {}
NE.talents = T

local MAX_NAME = 16

-- ---- per-character custom names: NE.db.talentSpecNames[charKey][group] = "name" -------------------
local function charKey()
  if NE.CharKey then return NE.CharKey() end
  return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?")
end
local function customName(group)
  local db = NE.db
  local c = db and db.talentSpecNames and db.talentSpecNames[charKey()]
  return c and c[group]
end
local function setCustomName(group, name)
  local db = NE.db
  if not db then return end
  name = (name or ""):gsub("[^%a ]", "")            -- letters + spaces only
  name = name:gsub("^%s+", ""):gsub("%s+$", "")     -- trim
  if #name > MAX_NAME then name = name:sub(1, MAX_NAME) end
  db.talentSpecNames = db.talentSpecNames or {}
  local key = charKey()
  db.talentSpecNames[key] = db.talentSpecNames[key] or {}
  db.talentSpecNames[key][group] = (name ~= "") and name or nil   -- blank clears -> default
end
local function defaultName(group) return (group == 1) and "Primary" or "Secondary" end
local function specName(group) return customName(group) or defaultName(group) end

-- ---- rename dialog (opened by the cog) ------------------------------------------------------------
StaticPopupDialogs["NE_TALENT_RENAME_SPEC"] = {
  text = "Rename this specialization (letters only, max " .. MAX_NAME .. "):",
  button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
  hasEditBox = 1, maxLetters = MAX_NAME,
  OnShow = function(self)
    local eb = self.editBox or _G[(self:GetName() or "") .. "EditBox"]
    if not eb then return end
    eb:SetText((self.data and self.data.current) or "")
    eb:HighlightText()
    -- strip any non-letter as it's typed/pasted (keeps spaces)
    eb:SetScript("OnTextChanged", function(box)
      local txt = box:GetText()
      local clean = txt:gsub("[^%a ]", "")
      if clean ~= txt then box:SetText(clean) end
    end)
  end,
  OnAccept = function(self)
    local eb = self.editBox or _G[(self:GetName() or "") .. "EditBox"]
    if self.data and self.data.group then
      setCustomName(self.data.group, eb and eb:GetText() or "")
      if T.RefreshSpecTabs then T.RefreshSpecTabs() end
    end
  end,
  EditBoxOnEnterPressed = function(editBox)
    local d = editBox:GetParent()
    if d.data and d.data.group then
      setCustomName(d.data.group, editBox:GetText() or "")
      if T.RefreshSpecTabs then T.RefreshSpecTabs() end
    end
    d:Hide()
  end,
  EditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end,
  timeout = 0, whileDead = 1, hideOnEscape = 1, exclusive = 1,
}

-- ---- selected/deselected tab art (mirrors character/TabButtons setTabArt) --------------------------
local function setTabArt(tab, selected)
  if not tab then return end
  local n = tab:GetName()
  local function set(suffix, show)
    local t = _G[n .. suffix]
    if t then if show then t:Show() else t:Hide() end end
  end
  set("Left",  not selected); set("Middle",  not selected); set("Right",  not selected)
  set("LeftDisabled", selected); set("MiddleDisabled", selected); set("RightDisabled", selected)
  local hl = tab._neCustomHL
  if hl then
    local a = selected and 0 or 0.4
    if hl.left   and hl.left.SetAlpha   then hl.left:SetAlpha(a)   end
    if hl.middle and hl.middle.SetAlpha then hl.middle:SetAlpha(a) end
    if hl.right  and hl.right.SetAlpha  then hl.right:SetAlpha(a)  end
  end
end

local TAB_NAMES = { "NE_TalentSpecTab1", "NE_TalentSpecTab2" }

local function buildTab(g)
  local f = T.frame
  local name = TAB_NAMES[g]
  local tab = _G[name]
  if tab then return tab end
  local ok, t = pcall(CreateFrame, "Button", name, f, "CharacterFrameTabButtonTemplate")
  if ok and t then tab = t else
    tab = CreateFrame("Button", name, f, "UIPanelButtonTemplate"); tab._nePlain = true
  end
  tab:SetID(g)
  tab:SetScript("OnClick", function(self)
    if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
    T._viewGroup = self:GetID()
    if T.RefreshSpecTabs then T.RefreshSpecTabs() end
    if T.Refresh then T.Refresh() end
  end)
  if not tab._nePlain and NE.tabs and NE.tabs.ReskinClassicTab then
    pcall(NE.tabs.ReskinClassicTab, name, {})
  end
  return tab
end

-- Rename cog: a gear seated to the right of the tab row; opens the rename dialog for the VIEWED spec.
local function buildCog()
  local f = T.frame
  if T._specCog then return T._specCog end
  local cog = CreateFrame("Button", "NE_TalentSpecCog", f)
  cog:SetSize(18, 18)
  cog.Icon = cog:CreateTexture(nil, "ARTWORK")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Icon, "questlog-icon-setting", true)) then
    cog.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Icon:SetSize(16, 16)
  end
  cog.Icon:SetPoint("CENTER")
  cog.Hi = cog:CreateTexture(nil, "HIGHLIGHT")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Hi, "questlog-icon-setting", true)) then
    cog.Hi:SetTexture("Interface\\Buttons\\UI-OptionsButton"); cog.Hi:SetSize(16, 16)
  end
  cog.Hi:SetPoint("CENTER"); cog.Hi:SetBlendMode("ADD"); cog.Hi:SetAlpha(0.4)
  cog:SetFrameLevel((f:GetFrameLevel() or 1) + 10)
  -- top-right of the button anchored to the top-right of the talent BACKGROUND (inside the chrome),
  -- with a small buffer so it isn't touching the window border.
  cog:SetPoint("TOPRIGHT", f.bg or f, "TOPRIGHT", -8, -8)
  cog:SetScript("OnClick", function()
    local g = T._viewGroup or 1
    StaticPopup_Show("NE_TALENT_RENAME_SPEC", nil, nil, { group = g, current = customName(g) or "" })
  end)
  cog:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Rename specialization", 1, 1, 1)
    GameTooltip:Show()
  end)
  cog:SetScript("OnLeave", function() GameTooltip:Hide() end)
  T._specCog = cog
  return cog
end

-- Build-once + update. Called from Behavior.Populate (and the tabs' own click). No-op with 1 spec.
function T.RefreshSpecTabs()
  local f = T.frame
  if not f then return end
  local num = (GetNumTalentGroups and (GetNumTalentGroups() or 1)) or 1   -- VERIFY: GetNumTalentGroups on 3.3.5a
  if num < 2 then
    for g = 1, 2 do local t = _G[TAB_NAMES[g]]; if t then t:Hide() end end
    if T._specCog then T._specCog:Hide() end
    return
  end
  local viewG = T._viewGroup or T._activeGroup or 1
  for g = 1, 2 do
    local tab = buildTab(g)
    local txt = _G[TAB_NAMES[g] .. "Text"]
    if txt then txt:SetText(specName(g)) elseif tab.SetText then tab:SetText(specName(g)) end
    tab:Show()
  end
  -- size each tab to its (possibly renamed) text + chain them along the bottom edge
  if NE.tabs and NE.tabs.SizeAndAnchorTabs then
    NE.tabs.SizeAndAnchorTabs(f, TAB_NAMES, { startX = 14, startY = 0, parentPoint = "BOTTOMLEFT" })
  end
  for g = 1, 2 do setTabArt(_G[TAB_NAMES[g]], g == viewG) end
  buildCog():Show()   -- anchored top-right inside the window (set in buildCog)
end
