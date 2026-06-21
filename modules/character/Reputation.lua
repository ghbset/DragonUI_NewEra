-- DragonUI_NewEra/modules/character/Reputation.lua — the Reputation secondary tab.
--
-- Fills the EMPTY pane DragonUI_NewEra_CharacterPane_Reputation (created by TabButtons.lua,
-- parented to NE.charpanel.frame.Inset). Collapsible faction-group HEADERS + per-faction
-- standing BARS, ported from NewEra/CharacterPanel/Reputation.lua.
--
-- DOWNPORT (CONTRACT_S1 §A.2/§B): NewEra used retail WowScrollBox + ScrollUtil + a custom
-- NE_ReputationFrame overlaying the stock ReputationFrame. 3.3.5a has neither WowScrollBox nor
-- a meaningful stock ReputationFrame inside our custom panel, so we render DIRECTLY into our
-- pane with a NAMED FauxScrollFrame (FauxScrollFrameTemplate's OnLoad concatenates
-- self:GetName().."ScrollBar" → an UNNAMED scroll frame ERRORS) + a recycled row pool, exactly
-- like the proven DragonflightUICharacter StatsPanel/EquipmentManager pattern.
--
-- DATA: GetNumFactions() + GetFactionInfo(i). 3.3.5a tuple (isHeader is at POSITION 9 — §B):
--   name, description, standingID, barMin, barMax, barValue, atWarWith, canToggleAtWar,
--   isHeader, isCollapsed, hasRep, isWatched, isChild
-- Bar tint per standing via the global FACTION_BAR_COLORS[standingID]. Headers toggle via
-- ExpandFactionHeader(i)/CollapseFactionHeader(i) (which renumber the list → we re-read).
--
-- GRACEFUL DEGRADATION (§A.5): every getter is pcall-guarded; if GetNumFactions/GetFactionInfo
-- are absent the pane shows a single "unavailable" line and logs a warning — NEVER errors.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

-- ---------------------------------------------------------------------------
-- Local logger (graceful — NE.Log may be absent on a standalone load).
-- ---------------------------------------------------------------------------
local function log(msg)
  if CP._log then CP._log("REPUTATION: " .. tostring(msg)); return end
  if NE.Log then NE.Log("REPUTATION", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [reputation]: " .. tostring(msg))
  end
end

-- ---------------------------------------------------------------------------
-- Geometry (mirrors NewEra Reputation.lua's row rhythm).
-- ---------------------------------------------------------------------------
local ROW_HEIGHT   = 24    -- one FauxScroll row slot (header + entry share the slot height)
local BAR_W        = 132
local BAR_H        = 13
local LEFT_W       = 78    -- left cap (native rep-bar cap, scaled to BAR_W)
local RIGHT_W      = 54    -- right cap (78+54 = BAR_W)

-- Native 3.3.5a rep-bar art (Interface\PaperDollInfoFrame\...). Caps come off the
-- ReputationBar sheet; the grey fill is the Skills-Bar (tinted via SetStatusBarColor).
-- DOWNPORT: FDID 136570 does NOT exist on 3.3.5a — use the native Skills-Bar PATH, never that fdid.
local CAP_TEX  = "Interface\\PaperDollInfoFrame\\UI-Character-ReputationBar"
local FILL_TEX = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
-- Prefer the locally-shipped rep-bar BLP (FDID 136567) if registered, else the native path.
local function capSource()
  return (NE.tex and NE.tex.localFiles and NE.tex.localFiles[136567]) or CAP_TEX
end

-- Native stock rep-bar cap texcoords (ReputationFrame.xml LeftTexture/RightTexture).
local LEFT_TC  = { 0.691, 1.0,   0.047,  0.281 }
local RIGHT_TC = { 0.0,   0.164, 0.3906, 0.625 }

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then return NE.tex.SetAtlas(tex, name, useAtlasSize) end
  return false
end

-- ---------------------------------------------------------------------------
-- Collapsible header row (Options_ListExpand 3-piece + collapse chevron on the right).
-- DOWNPORT: NewEra used NE.listheader.Build (a Core helper that doesn't exist here) — built
-- inline. If the list-expand atlas isn't shipped the pieces degrade to untextured (still clickable).
-- ---------------------------------------------------------------------------
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
  h._bgMiddle:SetPoint("TOPLEFT",     h._bgLeft,  "TOPRIGHT")
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
  local cap = info.isCollapsed and "options_listexpand_right" or "options_listexpand_right_expanded"
  setAtlas(h._bgRight, cap, true)
  local idx = info.factionIndex
  h:SetScript("OnClick", function()
    -- 3.3.5a renumbers the faction list on expand/collapse → re-refresh after.
    if info.isCollapsed then
      if ExpandFactionHeader then pcall(ExpandFactionHeader, idx) end
    else
      if CollapseFactionHeader then pcall(CollapseFactionHeader, idx) end
    end
    if CP.RefreshReputation then CP.RefreshReputation() end
  end)
end

-- ---------------------------------------------------------------------------
-- Faction standing entry row (name + tinted standing bar w/ native cap chrome).
-- ---------------------------------------------------------------------------
local function buildEntry(parent)
  local e = CreateFrame("Button", nil, parent)
  e:SetHeight(ROW_HEIGHT)

  e._name = e:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  e._name:SetPoint("LEFT", e, "LEFT", 12, 0)
  e._name:SetJustifyH("LEFT")

  local bar = CreateFrame("StatusBar", nil, e)
  bar:SetSize(BAR_W, BAR_H)
  bar:SetPoint("RIGHT", e, "RIGHT", -4, 0)
  bar:SetStatusBarTexture(FILL_TEX)
  -- Force the fill DOWN to BORDER so the ARTWORK caps draw above it (stock rep-bar behaviour).
  local fillTex = bar:GetStatusBarTexture()
  if fillTex then fillTex:SetDrawLayer("BORDER") end
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(1)

  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints(bar)
  if barBg.SetColorTexture then barBg:SetColorTexture(0, 0, 0, 1) else barBg:SetTexture(0, 0, 0, 1) end

  -- DOWNPORT/REPORT: brown ReputationBar end-caps removed (clean bar). A 1px dark OUTLINE frames the
  -- bar WITHOUT covering the fill — the earlier solid overlay sat on the BORDER-layer fill and hid the
  -- colored progress ("appearing below the black background"). Outline = 4 edge lines at OVERLAY only.
  local function barEdge()
    local t = bar:CreateTexture(nil, "OVERLAY")
    if t.SetColorTexture then t:SetColorTexture(0, 0, 0, 0.9) else t:SetTexture(0, 0, 0, 0.9) end
    return t
  end
  local eT = barEdge(); eT:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1);  eT:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 1, 1);   eT:SetHeight(1)
  local eB = barEdge(); eB:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -1, -1); eB:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1); eB:SetHeight(1)
  local eL = barEdge(); eL:SetPoint("TOPLEFT", bar, "TOPLEFT", -1, 1);  eL:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", -1, -1); eL:SetWidth(1)
  local eR = barEdge(); eR:SetPoint("TOPRIGHT", bar, "TOPRIGHT", 1, 1); eR:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", 1, -1); eR:SetWidth(1)

  bar._text = bar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  bar._text:SetPoint("CENTER", bar, "CENTER", 0, 0)

  -- Right-anchor the name to the bar's left edge so a long faction name truncates cleanly.
  e._name:SetPoint("RIGHT", bar, "LEFT", -8, 0)

  e._bar = bar

  local hl = e:CreateTexture(nil, "HIGHLIGHT")
  if hl.SetColorTexture then hl:SetColorTexture(1, 1, 1, 0.10) else hl:SetTexture(1, 1, 1, 0.10) end
  hl:SetAllPoints(e)

  e:RegisterForClicks("LeftButtonUp")

  -- Hover swaps the bar text from standing label → numeric "value / max".
  e:HookScript("OnEnter", function(self)
    if self._bar and self._bar._progressText then self._bar._text:SetText(self._bar._progressText) end
  end)
  e:HookScript("OnLeave", function(self)
    if self._bar and self._bar._standingText then self._bar._text:SetText(self._bar._standingText) end
  end)
  return e
end

local function updateEntry(e, info)
  e._name:SetText(info.name or "")

  local bar = e._bar
  local barMax = (info.barMax or 0) - (info.barMin or 0)
  local barVal = (info.barValue or 0) - (info.barMin or 0)
  if barMax <= 0 then barMax = 1; barVal = 0 end
  bar:SetMinMaxValues(0, barMax)
  bar:SetValue(barVal)

  local color = _G.FACTION_BAR_COLORS and _G.FACTION_BAR_COLORS[info.standingID or 4]
  if color then bar:SetStatusBarColor(color.r, color.g, color.b) end

  local standingText = ""
  local sid = info.standingID or 4
  if _G["FACTION_STANDING_LABEL" .. sid] then standingText = _G["FACTION_STANDING_LABEL" .. sid] end
  bar._standingText = standingText
  bar._progressText = string.format("%d / %d", barVal, barMax)
  bar._text:SetText(standingText)

  -- Click → select this faction (drives the stock detail/watch system, if present).
  local idx = info.factionIndex
  e:SetScript("OnClick", function()
    if SetSelectedFaction then pcall(SetSelectedFaction, idx) end
  end)
end

-- ---------------------------------------------------------------------------
-- Build the pane scaffold: a named FauxScrollFrame + recycled header/entry pools.
-- ---------------------------------------------------------------------------
local pane            -- DragonUI_NewEra_CharacterPane_Reputation
local scroll, content
local headerPool, entryPool = {}, {}
local flat = {}       -- ordered list of { kind="header"/"entry", info=... }
local NUM_VISIBLE = 0

local function getPane()
  if pane then return pane end
  pane = _G.DragonUI_NewEra_CharacterPane_Reputation
        or (CP.EnsurePane and CP.EnsurePane("Reputation"))
  return pane
end

local function acquireHeader()
  for _, h in ipairs(headerPool) do
    if not h._inUse then h._inUse = true; h:Show(); return h end
  end
  local h = buildHeader(content)
  headerPool[#headerPool + 1] = h
  h._inUse = true
  return h
end

local function acquireEntry()
  for _, en in ipairs(entryPool) do
    if not en._inUse then en._inUse = true; en:Show(); return en end
  end
  local en = buildEntry(content)
  entryPool[#entryPool + 1] = en
  en._inUse = true
  return en
end

local function releaseAll()
  for _, h in ipairs(headerPool) do h._inUse = false; h:Hide() end
  for _, en in ipairs(entryPool) do en._inUse = false; en:Hide() end
end

local emptyLabel

-- Paint the visible window of rows for the current scroll offset.
local function updateScroll()
  if not (scroll and content) then return end
  content:Show()
  releaseAll()

  local total = #flat
  if emptyLabel then if total == 0 then emptyLabel:Show() else emptyLabel:Hide() end end

  local nRows = NUM_VISIBLE > 0 and NUM_VISIBLE or 1
  if FauxScrollFrame_Update then FauxScrollFrame_Update(scroll, total, nRows, ROW_HEIGHT) end
  local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(scroll)) or 0

  local rowW = (content:GetWidth() or 200)
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
      local indent = data.info.isChild and 12 or 0
      row:ClearAllPoints()
      row:SetWidth(rowW - indent)
      row:SetPoint("TOPLEFT", content, "TOPLEFT", indent, -(i - 1) * ROW_HEIGHT)
      row:Show()
    end
  end
end

-- Rebuild `flat` from the live faction list, then repaint.
local function refresh()
  if not getPane() then return end
  if not scroll then return end   -- build() not done yet
  flat = {}

  if not (GetNumFactions and GetFactionInfo) then
    log("GetNumFactions/GetFactionInfo unavailable — Reputation pane degraded")
    updateScroll()
    return
  end

  local ok, total = pcall(GetNumFactions)
  if not ok or not total then total = 0 end

  for i = 1, total do
    -- §B: pcall every getter; isHeader is at POSITION 9.
    local ok2, name, description, standingID, barMin, barMax, barValue,
          atWarWith, canToggleAtWar, isHeader, isCollapsed, hasRep, isWatched, isChild = pcall(GetFactionInfo, i)
    if ok2 and name then
      local info = {
        factionIndex = i,
        name = name, description = description, standingID = standingID,
        barMin = barMin, barMax = barMax, barValue = barValue,
        isHeader = isHeader, isCollapsed = isCollapsed, isChild = isChild,
      }
      flat[#flat + 1] = { kind = isHeader and "header" or "entry", info = info }
    end
  end

  updateScroll()
end
-- DOWNPORT/REPORT: surface (don't swallow) a refresh error so an empty Reputation pane is diagnosable.
CP.RefreshReputation = function()
  local ok, err = pcall(refresh)
  if not ok then log("RefreshReputation error: " .. tostring(err)) end
end

local function recomputeVisible()
  if not scroll then return end
  local h = scroll:GetHeight() or 0
  NUM_VISIBLE = math.max(1, math.floor(h / ROW_HEIGHT))
end

local function build()
  local host = getPane()
  if not host then log("Reputation pane host missing — cannot build"); return false end
  if scroll then return true end

  -- Class-themed content background (matches the other secondary tabs); degrades silently.
  local bg = host:CreateTexture(nil, "BACKGROUND")
  if not setAtlas(bg, "character-panel-background", false) then bg:Hide() end
  bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)

  -- NAMED FauxScrollFrame (§B: name REQUIRED — template OnLoad uses self:GetName()).
  scroll = CreateFrame("ScrollFrame", "DragonUI_NewEra_RepScroll", host, "FauxScrollFrameTemplate")
  -- DOWNPORT/REPORT: viewport inset to sit INSIDE the engraved inset box (top/left margin), leaving a
  -- right gutter for the scrollbar (pushed out to the frame border by the negative BuildCustom x below).
  scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 10, -12)
  scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -24, 10)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, updateScroll)
  end)
  -- DOWNPORT/REPORT: wheel scrolling via the (hidden) Faux slider value; auto-clamps to its range.
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
  -- Reskin the classic slider to the DF minimal bar (no-op art if the sheet isn't shipped).
  -- DOWNPORT: hand-built minimal scrollbar (Reskin's stock-slider re-skin didn't render).
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll, { x = -8 }) end

  -- DOWNPORT/REPORT (the empty-pane bug): parent content to the PANE, not the faux ScrollFrame.
  -- FauxScrollFrame_Update hides the scroll frame when the list fits (numItems <= numToDisplay),
  -- which dragged content + every row down with it. Anchor over the scroll rect, raise above it so
  -- faction header expand/collapse buttons stay clickable.
  content = CreateFrame("Frame", nil, host)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
  content:SetHeight(1)
  content:SetFrameLevel(scroll:GetFrameLevel() + 5)

  emptyLabel = host:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  emptyLabel:SetPoint("TOP", host, "TOP", 0, -40)
  emptyLabel:SetWidth(200)
  emptyLabel:SetText(_G.REPUTATION and (_G.REPUTATION .. " unavailable") or "No reputations.")
  emptyLabel:Hide()

  recomputeVisible()
  return true
end

-- ---------------------------------------------------------------------------
-- Boot: build lazily, refresh on faction events + whenever the pane is shown.
-- ---------------------------------------------------------------------------
local function init()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  if not build() then return end
  pcall(refresh)
  -- Re-refresh on pane show (Inset width may differ; faction list may have changed).
  local host = getPane()
  if host and not host._neRepShowHooked then
    host._neRepShowHooked = true
    host:HookScript("OnShow", function() recomputeVisible(); pcall(refresh) end)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("UPDATE_FACTION")
boot:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    -- Defer one frame so TabButtons.lua has created the pane.
    if C_Timer and C_Timer.After then C_Timer.After(0, init) else init() end
  else
    CP.RefreshReputation()
  end
end)
