-- DragonUI_NewEra/modules/character/Currency.lua -- the Currency secondary tab.
--
-- Fills the EMPTY pane DragonUI_NewEra_CharacterPane_Currency (created by TabButtons.lua,
-- parented to NE.charpanel.frame.Inset). Renders the token/currency list with collapsible
-- category headers.
--
-- DOWNPORT (CONTRACT_S1 §B): 3.3.5a has no retail ScrollBox stack, so this tab uses a NAMED
-- FauxScrollFrame + manual header/entry row pool like the other secondary tabs.
--
-- DATA: GetCurrencyListSize() + GetCurrencyListInfo(i). 3.3.5 tuple shape differs by client,
-- but icon is at POSITION 8 on this branch. We read defensively and never hard-error.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local ROW_HEIGHT = 24

local function log(msg)
  if CP._log then CP._log("CURRENCY: " .. tostring(msg)); return end
  if NE.Log then NE.Log("CURRENCY", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [currency]: " .. tostring(msg))
  end
end

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then return NE.tex.SetAtlas(tex, name, useAtlasSize) end
  return false
end

local function L(global, fallback)
  local v = _G[global]
  if type(v) == "string" and v ~= "" then return v end
  return fallback
end

local function buildHeader(parent)
  local h = CreateFrame("Button", nil, parent)
  h:SetHeight(ROW_HEIGHT)

  h._bgLeft = h:CreateTexture(nil, "BACKGROUND")
  setAtlas(h._bgLeft, "options_listexpand_left", true)
  h._bgLeft:SetPoint("LEFT", h, "LEFT", 0, 0)

  h._bgRight = h:CreateTexture(nil, "BACKGROUND")
  setAtlas(h._bgRight, "options_listexpand_right", true)
  h._bgRight:SetPoint("RIGHT", h, "RIGHT", 0, 0)

  h._bgMiddle = h:CreateTexture(nil, "BACKGROUND")
  setAtlas(h._bgMiddle, "_options_listexpand_middle", false)
  h._bgMiddle:SetPoint("TOPLEFT", h._bgLeft, "TOPRIGHT")
  h._bgMiddle:SetPoint("BOTTOMRIGHT", h._bgRight, "BOTTOMLEFT")

  local hl = h:CreateTexture(nil, "HIGHLIGHT")
  if hl.SetColorTexture then hl:SetColorTexture(1, 1, 1, 0.10) else hl:SetTexture(1, 1, 1, 0.10) end
  hl:SetPoint("TOPLEFT", h._bgLeft, "TOPRIGHT")
  hl:SetPoint("BOTTOMRIGHT", h._bgRight, "BOTTOMLEFT")

  h._name = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h._name:SetPoint("LEFT", h, "LEFT", 12, 0)
  h._name:SetJustifyH("LEFT")
  h:RegisterForClicks("LeftButtonUp")

  return h
end

local function updateHeader(h, info)
  h._name:SetText(info.name or "")
  setAtlas(h._bgRight, info.isExpanded and "options_listexpand_right_expanded" or "options_listexpand_right", true)
  local idx = info.index
  h:SetScript("OnClick", function()
    if ExpandCurrencyList then
      -- DOWNPORT: 3.3.5 ExpandCurrencyList takes (index, expandFlag).
      pcall(ExpandCurrencyList, idx, info.isExpanded and 0 or 1)
    end
    if CP.RefreshCurrency then CP.RefreshCurrency() end
  end)
end

local function buildEntry(parent)
  local e = CreateFrame("Button", nil, parent)
  e:SetHeight(ROW_HEIGHT)

  e._icon = e:CreateTexture(nil, "ARTWORK")
  e._icon:SetSize(16, 16)
  e._icon:SetPoint("LEFT", e, "LEFT", 12, 0)

  e._name = e:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  e._name:SetPoint("LEFT", e._icon, "RIGHT", 8, 0)
  e._name:SetJustifyH("LEFT")

  e._count = e:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  e._count:SetPoint("RIGHT", e, "RIGHT", -10, 0)
  e._count:SetJustifyH("RIGHT")

  e._name:SetPoint("RIGHT", e._count, "LEFT", -8, 0)

  local hl = e:CreateTexture(nil, "HIGHLIGHT")
  if hl.SetColorTexture then hl:SetColorTexture(1, 1, 1, 0.10) else hl:SetTexture(1, 1, 1, 0.10) end
  hl:SetAllPoints(e)

  e:RegisterForClicks("LeftButtonUp")
  return e
end

local function updateEntry(e, info)
  e._name:SetText(info.name or "")
  e._count:SetText(tostring(info.count or 0))

  if info.icon and info.icon ~= "" then
    e._icon:SetTexture(info.icon)
    e._icon:Show()
  else
    e._icon:Hide()
  end

  local idx = info.index
  e:SetScript("OnClick", function()
    if SetCurrencyBackpack then pcall(SetCurrencyBackpack, idx, 1) end
  end)
end

local pane
local scroll, content
local headerPool, entryPool = {}, {}
local flat = {}
local NUM_VISIBLE = 0
local emptyLabel

local function getPane()
  if pane then return pane end
  pane = _G.DragonUI_NewEra_CharacterPane_Currency or (CP.EnsurePane and CP.EnsurePane("Currency"))
  return pane
end

local function acquireHeader()
  for _, h in ipairs(headerPool) do
    if not h._inUse then h._inUse = true; h:Show(); return h end
  end
  local h = buildHeader(content)
  h._inUse = true
  headerPool[#headerPool + 1] = h
  return h
end

local function acquireEntry()
  for _, e in ipairs(entryPool) do
    if not e._inUse then e._inUse = true; e:Show(); return e end
  end
  local e = buildEntry(content)
  e._inUse = true
  entryPool[#entryPool + 1] = e
  return e
end

local function releaseAll()
  for _, h in ipairs(headerPool) do h._inUse = false; h:Hide() end
  for _, e in ipairs(entryPool) do e._inUse = false; e:Hide() end
end

local function parseCurrencyInfo(idx)
  local ok, a, b, c, d, e, f, g, h = pcall(GetCurrencyListInfo, idx)
  if not ok or not a then return nil end

  local name = a
  local isHeader = b and true or false
  local isExpanded = c and true or false
  local isUnused = d and true or false
  local count = tonumber(f) or 0
  local icon = h or g

  return {
    index = idx,
    name = name,
    isHeader = isHeader,
    isExpanded = isExpanded,
    isUnused = isUnused,
    count = count,
    icon = icon,
  }
end

local function updateScroll()
  if not (scroll and content) then return end
  releaseAll()

  local total = #flat
  if emptyLabel then if total == 0 then emptyLabel:Show() else emptyLabel:Hide() end end

  local nRows = NUM_VISIBLE > 0 and NUM_VISIBLE or 1
  if FauxScrollFrame_Update then FauxScrollFrame_Update(scroll, total, nRows, ROW_HEIGHT) end
  local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(scroll)) or 0

  local rowW = content:GetWidth() or 200
  if rowW <= 0 then rowW = 200 end

  for i = 1, nRows do
    local data = flat[offset + i]
    if data then
      local row
      if data.kind == "header" then
        row = acquireHeader()
        updateHeader(row, data.info)
      else
        row = acquireEntry()
        updateEntry(row, data.info)
      end

      local indent = data.kind == "entry" and 8 or 0
      row:ClearAllPoints()
      row:SetWidth(rowW - indent)
      row:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -(i - 1) * ROW_HEIGHT)
      row:Show()
    end
  end
end

local function refresh()
  if not getPane() then return end
  if not scroll then return end
  flat = {}

  if not (GetCurrencyListSize and GetCurrencyListInfo) then
    log("GetCurrencyListSize/GetCurrencyListInfo unavailable -- Currency pane degraded")
    updateScroll()
    return
  end

  local ok, total = pcall(GetCurrencyListSize)
  if not ok or not total then total = 0 end

  for i = 1, total do
    local info = parseCurrencyInfo(i)
    if info and not info.isUnused then
      flat[#flat + 1] = { kind = info.isHeader and "header" or "entry", info = info }
    end
  end

  updateScroll()
end

CP.RefreshCurrency = function()
  local ok, err = pcall(refresh)
  if not ok then log("RefreshCurrency error: " .. tostring(err)) end
end

local function recomputeVisible()
  if not scroll then return end
  local h = scroll:GetHeight() or 0
  NUM_VISIBLE = math.max(1, math.floor(h / ROW_HEIGHT))
end

local function build()
  local host = getPane()
  if not host then log("Currency pane host missing -- cannot build"); return false end
  if scroll then return true end

  local bg = host:CreateTexture(nil, "BACKGROUND")
  if not setAtlas(bg, "character-panel-background", false) then bg:Hide() end
  bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)

  scroll = CreateFrame("ScrollFrame", "DragonUI_NewEra_CurrencyScroll", host, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 10, -12)
  scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -24, 10)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, updateScroll)
  end)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = _G[(self:GetName() or "") .. "ScrollBar"]
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * ROW_HEIGHT
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)
  scroll:HookScript("OnSizeChanged", function() recomputeVisible(); updateScroll() end)
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll, { x = -8 }) end

  content = CreateFrame("Frame", nil, host)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
  content:SetHeight(1)
  content:SetFrameLevel(scroll:GetFrameLevel() + 5)

  emptyLabel = host:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  emptyLabel:SetPoint("TOP", host, "TOP", 0, -40)
  emptyLabel:SetWidth(200)
  emptyLabel:SetText(L("CURRENCY", "Currency") .. " unavailable")
  emptyLabel:Hide()

  recomputeVisible()
  return true
end

local function init()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  if not build() then return end
  pcall(refresh)
  local host = getPane()
  if host and not host._neCurrencyShowHooked then
    host._neCurrencyShowHooked = true
    host:HookScript("OnShow", function() recomputeVisible(); pcall(refresh) end)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("CURRENCY_DISPLAY_UPDATE")
boot:RegisterEvent("KNOWN_CURRENCY_TYPES_UPDATE")
boot:RegisterEvent("PLAYER_MONEY")
boot:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if C_Timer and C_Timer.After then C_Timer.After(0, init) else init() end
  else
    CP.RefreshCurrency()
  end
end)
