-- DragonUI_NewEra/modules/character/TitlesPane.lua — the Titles sidebar (Tab 2).
--
-- DOWNPORT/REPORT: NewEra DISABLED this tab because Classic Era 1.15 has no title system. WotLK 3.3.5
-- DOES (GetNumTitles / IsTitleKnown / GetTitleName / GetCurrentTitle / SetCurrentTitle), so we implement
-- a real title picker: a scrollable list of your KNOWN titles plus a "None" entry; click a row to set
-- that title. Current title is checked + highlighted.
--
-- Structure mirrors Skills.lua: a NAMED FauxScrollFrame + a `content` frame parented to the PANE (NOT
-- the scroll — FauxScrollFrame_Update hides the scroll when the list fits, which would take the rows
-- with it), windowed to the visible row count, with wheel scrolling and a flush-right custom scrollbar.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local ROW_H = 22

local function log(msg) if CP._log then CP._log("TITLES: " .. tostring(msg)) elseif NE.Log then NE.Log("TITLES", msg) end end

local function L(global, fallback)
  local v = _G[global]
  if type(v) == "string" and v ~= "" then return v end
  return fallback
end

-- DOWNPORT/REPORT: match the sidebar's own resolution — InsetRight may be on CP.InsetRight, not
-- CP.frame.InsetRight (buildSidebar uses `f.InsetRight or CP.InsetRight`).
local function host() return (CP.frame and CP.frame.InsetRight) or CP.InsetRight end
local function trim(s) return (tostring(s or "")):gsub("^%s+", ""):gsub("%s+$", "") end

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then return NE.tex.SetAtlas(tex, name, useAtlasSize) end
  return false
end

-- 3.3.5 GetTitleName returns the suffix/prefix form (often with a leading/trailing space).
local function titleText(id)
  local ok, name = pcall(GetTitleName, id)
  if ok and name and trim(name) ~= "" then return trim(name) end
  return nil
end

-- Build "Name <title>" immediately (optimistic) for the window header, without waiting for UnitPVPName
-- to catch up. GetTitleName gives a SUFFIX with a leading space (" the Explorer") or a PREFIX with a
-- trailing space ("Private "); combine accordingly. The event-driven CP.UpdateTitle (UnitPVPName)
-- corrects any odd format a frame later.
local function titledName(titleID)
  local base = (UnitName and UnitName("player")) or ""
  if not titleID or titleID == 0 then return base end
  local ok, raw = pcall(GetTitleName, titleID)
  if not ok or not raw or raw == "" then return base end
  if raw:sub(1, 1) == " " then return base .. raw
  elseif raw:sub(-1) == " " then return raw .. base
  else return base .. " " .. raw end
end

-- ---------------------------------------------------------------------------
-- Pane scaffold.
-- ---------------------------------------------------------------------------
local pane, scroll, content
local updateScroll         -- forward-declared: buildRow's OnClick (above its definition) calls it
local rowPool = {}
local flat = {}            -- ordered { { id = titleID (0 = None), text = display } }
local NUM_VISIBLE = 0
local emptyLabel
local _optimisticCurrent   -- titleID shown ticked right after a click (GetCurrentTitle lags a frame);
                           -- cleared by refresh() so open/event repaints read the real current title

local function getPane()
  if pane then return pane end
  pane = _G.NE_TitlesPane
  return pane
end

local function buildRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(ROW_H)
  b:RegisterForClicks("LeftButtonUp")

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD"); hl:SetAlpha(0.4); hl:SetAllPoints(b)

  local sel = b:CreateTexture(nil, "BACKGROUND")
  sel:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
  sel:SetTexCoord(0.2, 0.8, 0, 1); sel:SetBlendMode("ADD"); sel:SetAlpha(0.5)
  sel:SetAllPoints(b); sel:Hide(); b.Selected = sel

  local check = b:CreateTexture(nil, "OVERLAY")
  check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  check:SetSize(18, 18); check:SetPoint("RIGHT", b, "RIGHT", -4, 0); check:Hide(); b.Check = check

  local txt = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
  txt:SetPoint("LEFT", b, "LEFT", 8, 0); txt:SetPoint("RIGHT", b, "RIGHT", -24, 0)
  txt:SetJustifyH("LEFT"); b.text = txt

  b:SetScript("OnClick", function(self)
    if self.titleID == nil then return end
    -- Already the current title? Do nothing — no redundant SetCurrentTitle to the server on re-clicks.
    local current = (GetCurrentTitle and GetCurrentTitle()) or 0
    if self.titleID == current then return end
    if SetCurrentTitle then pcall(SetCurrentTitle, self.titleID) end
    -- DOWNPORT/REPORT: every listed title is OWNED (IsTitleKnown filter), so the set always succeeds —
    -- reflect it OPTIMISTICALLY right here (no C_Timer): move the tick + update the window header now.
    -- GetCurrentTitle/UnitPVPName only catch up a frame later (the UNIT_NAME_UPDATE event repaints from
    -- the real state then, which matches).
    _optimisticCurrent = self.titleID
    updateScroll()
    if CP.SetWindowTitle then pcall(CP.SetWindowTitle, titledName(self.titleID)) end
  end)
  return b
end

local function acquireRow()
  for _, r in ipairs(rowPool) do
    if not r._inUse then r._inUse = true; r:Show(); return r end
  end
  local r = buildRow(content)
  rowPool[#rowPool + 1] = r
  r._inUse = true
  return r
end

local function releaseAll()
  for _, r in ipairs(rowPool) do r._inUse = false; r:Hide() end
end

function updateScroll()   -- assigns the forward-declared local (see top of file)
  if not (scroll and content) then return end
  content:Show()
  releaseAll()

  local total = #flat
  if emptyLabel then if total == 0 then emptyLabel:Show() else emptyLabel:Hide() end end

  local nRows = NUM_VISIBLE > 0 and NUM_VISIBLE or 1
  if FauxScrollFrame_Update then FauxScrollFrame_Update(scroll, total, nRows, ROW_H) end
  local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(scroll)) or 0

  local current = _optimisticCurrent
  if current == nil then current = (GetCurrentTitle and GetCurrentTitle()) or 0 end

  for i = 1, nRows do
    local data = flat[offset + i]
    if data then
      local row = acquireRow()
      row.titleID = data.id
      row.text:SetText(data.text)
      local on = (data.id == current)
      if on then row.Selected:Show(); row.Check:Show(); row.text:SetTextColor(1, 0.82, 0)
      else row.Selected:Hide(); row.Check:Hide(); row.text:SetTextColor(1, 1, 1) end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_H)
      row:SetPoint("RIGHT", content, "RIGHT", 0, 0)
      row:Show()
    end
  end
end

-- Rebuild `flat` from the known-title list, then repaint.
local function refresh()
  if not getPane() then return end
  if not scroll then return end
  _optimisticCurrent = nil   -- open/event repaint → trust the real GetCurrentTitle
  flat = { { id = 0, text = L("PLAYER_TITLE_NONE", "None") } }

  if GetNumTitles and IsTitleKnown then
    local n = (pcall(GetNumTitles) and GetNumTitles()) or 0
    for id = 1, n do
      local okk, known = pcall(IsTitleKnown, id)
      -- DOWNPORT/REPORT: IsTitleKnown returns 0 for FALSE on this server (not nil), and 0 is TRUTHY in
      -- Lua — so `if okk and known` treated every title as known. Require it to be truthy AND not 0.
      if okk and known and known ~= 0 then
        local t = titleText(id)
        if t then flat[#flat + 1] = { id = id, text = t } end
      end
    end
  end

  updateScroll()
end
CP.RefreshTitles = function()
  local ok, err = pcall(refresh)
  if not ok then log("RefreshTitles error: " .. tostring(err)) end
end

local function recomputeVisible()
  if not scroll then return end
  local h = scroll:GetHeight() or 0
  NUM_VISIBLE = math.max(1, math.floor(h / ROW_H))
end

local function build()
  local h = getPane()
  if not h then
    -- Pane lives in InsetRight; create it lazily.
    local ir = host()
    if not ir then log("build: InsetRight not ready"); return false end
    pane = CreateFrame("Frame", "NE_TitlesPane", ir)
    pane:SetPoint("TOPLEFT",     ir, "TOPLEFT",      3, -3)
    pane:SetPoint("BOTTOMRIGHT", ir, "BOTTOMRIGHT", -3,  2)
    pane:Hide()
    h = pane
  end
  if scroll then return true end

  scroll = CreateFrame("ScrollFrame", "NE_TitlesScroll", h, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",     h, "TOPLEFT",      6, -8)
  scroll:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -10, 6)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_H, updateScroll)
  end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = _G[(self:GetName() or "") .. "ScrollBar"]
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * ROW_H
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)
  scroll:HookScript("OnSizeChanged", function() recomputeVisible(); updateScroll() end)
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll, { x = 0 }) end

  -- Row container: child of the PANE (not the scroll) so it survives the faux scroll hiding when the
  -- list fits. Anchored over the scroll rect, raised above it for clicks.
  content = CreateFrame("Frame", nil, h)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
  content:SetHeight(1)
  content:SetFrameLevel(scroll:GetFrameLevel() + 5)

  emptyLabel = h:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  emptyLabel:SetPoint("TOP", h, "TOP", 0, -40)
  emptyLabel:SetWidth(180)
  emptyLabel:SetText(L("NO_TITLES_TOOLTIP", "You haven't earned any titles."))
  emptyLabel:Hide()

  recomputeVisible()
  return true
end

-- ---------------------------------------------------------------------------
-- Show / hide. Mirrors the equipment manager's ShowEquipManager/HideEquipManager.
-- ---------------------------------------------------------------------------
function CP.ShowTitles()
  if not build() then return end
  if CP._sidebar and CP._sidebar.Hide then CP._sidebar:Hide() end
  if CP.HideEquipManager then pcall(CP.HideEquipManager) end
  pane:Show()
  CP.RefreshTitles()
  CP._activeSidebar = 2
end

function CP.HideTitles()
  if pane then pane:Hide() end
end

-- ---------------------------------------------------------------------------
-- Route sidebar index 2 → titles by chaining CP.SelectSidebar (set up by Sidebar.lua + the equipment
-- pane). index 2 shows titles; any other index hides titles and defers to the previous handler.
-- ---------------------------------------------------------------------------
local _prevSelectSidebar = CP.SelectSidebar
function CP.SelectSidebar(index)
  if tonumber(index) == 2 then
    CP._activeSidebar = 2
    CP.ShowTitles()
    if CP.SetSidebarTabSelected then pcall(CP.SetSidebarTabSelected, 2) end
    return
  end
  CP.HideTitles()
  if _prevSelectSidebar then return _prevSelectSidebar(index) end
end

-- ---------------------------------------------------------------------------
-- Boot: keep the list live as titles are earned / the current title changes.
-- ---------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("KNOWN_TITLES_UPDATE")
boot:RegisterEvent("PLAYER_TITLE_UPDATE")
boot:RegisterEvent("UNIT_NAME_UPDATE")   -- title display change → tick follows the real current title
boot:SetScript("OnEvent", function(_, event, unit)
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  if event == "UNIT_NAME_UPDATE" and unit and unit ~= "player" then return end
  -- Keep the window header's "Name <Title>" synced whenever the title changes, even if the pane is shut.
  if (event == "UNIT_NAME_UPDATE" or event == "PLAYER_TITLE_UPDATE") and CP.UpdateTitle then
    pcall(CP.UpdateTitle)
  end
  if CP._activeSidebar == 2 and pane and pane:IsVisible() then CP.RefreshTitles() end
end)
