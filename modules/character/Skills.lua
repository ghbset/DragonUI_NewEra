-- DragonUI_NewEra/modules/character/Skills.lua — the Skills secondary tab.
--
-- Fills the EMPTY pane DragonUI_NewEra_CharacterPane_Skills (created by TabButtons.lua, parented
-- to NE.charpanel.frame.Inset). Collapsible skill-type HEADERS + per-skill rank BARS, ported
-- from NewEra/CharacterPanel/Skills.lua (which itself mirrors its Reputation tab).
--
-- DOWNPORT (CONTRACT_S1 §A.2/§B): NewEra used retail WowScrollBox + ScrollUtil over the stock
-- SkillFrame. 3.3.5a has neither, so we render DIRECTLY into our pane with a NAMED
-- FauxScrollFrame (unnamed FauxScrollFrameTemplate ERRORS) + a recycled row pool — the proven
-- DragonflightUICharacter pattern.
--
-- DATA: GetNumSkillLines() + GetSkillLineInfo(i). 3.3.5a tuple:
--   skillName, header, isExpanded, skillRank, numTempPoints, skillModifier, skillMaxRank,
--   isAbandonable, stepCost, rankCost, minLevel, skillCostType, skillDescription
-- Headers toggle via ExpandSkillHeader(i)/CollapseSkillHeader(i) (renumbers the list → re-read).
--
-- GRACEFUL DEGRADATION (§A.5): every getter is pcall-guarded; if the skill API is absent the
-- pane shows an "unavailable" line and logs a warning — NEVER errors.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local function log(msg)
  if CP._log then CP._log("SKILLS: " .. tostring(msg)); return end
  if NE.Log then NE.Log("SKILLS", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [skills]: " .. tostring(msg))
  end
end

-- Geometry (matches Reputation.lua so the two list tabs share a rhythm).
local ROW_HEIGHT = 24
local BAR_W      = 132
local BAR_H      = 13
local LEFT_W     = 78
local RIGHT_W    = 54

-- Native 3.3.5a bar art (FDID 136570 does NOT exist — use the native Skills-Bar path).
local CAP_TEX  = "Interface\\PaperDollInfoFrame\\UI-Character-ReputationBar"
local FILL_TEX = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
local function capSource()
  return (NE.tex and NE.tex.localFiles and NE.tex.localFiles[136567]) or CAP_TEX
end

local LEFT_TC  = { 0.691, 1.0,   0.047,  0.281 }
local RIGHT_TC = { 0.0,   0.164, 0.3906, 0.625 }

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then return NE.tex.SetAtlas(tex, name, useAtlasSize) end
  return false
end

-- Collapsible header (Options_ListExpand 3-piece + chevron; degrades to untextured but clickable).
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
  local cap = info.isExpanded and "options_listexpand_right_expanded" or "options_listexpand_right"
  setAtlas(h._bgRight, cap, true)
  local idx = info.skillIndex
  h:SetScript("OnClick", function()
    if info.isExpanded then
      if CollapseSkillHeader then pcall(CollapseSkillHeader, idx) end
    else
      if ExpandSkillHeader then pcall(ExpandSkillHeader, idx) end
    end
    if CP.RefreshSkills then CP.RefreshSkills() end
  end)
end

-- Skill rank entry (name + tinted rank bar w/ native cap chrome).
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

  e._name:SetPoint("RIGHT", bar, "LEFT", -8, 0)
  e._bar = bar

  local hl = e:CreateTexture(nil, "HIGHLIGHT")
  if hl.SetColorTexture then hl:SetColorTexture(1, 1, 1, 0.10) else hl:SetTexture(1, 1, 1, 0.10) end
  hl:SetAllPoints(e)
  return e
end

local function updateEntry(e, info)
  e._name:SetText(info.name or "")

  local bar = e._bar
  local rank, maxRank = info.rank or 0, info.maxRank or 0
  if maxRank <= 0 then maxRank = 1; rank = 0 end
  bar:SetMinMaxValues(0, maxRank)
  bar:SetValue(rank)

  -- Color: yellow at cap / green trainable / grey not-learned (stock SkillFrame_Update logic).
  local r, g, b = 0.5, 0.5, 0.5
  if rank > 0 and rank >= maxRank then r, g, b = 1.0, 0.95, 0.1
  elseif rank > 0 then r, g, b = 0.2, 0.85, 0.2 end
  bar:SetStatusBarColor(r, g, b)

  bar._text:SetText(string.format("%d / %d", rank, maxRank))
end

-- ---------------------------------------------------------------------------
-- Pane scaffold (named FauxScrollFrame + pools).
-- ---------------------------------------------------------------------------
local pane
local scroll, content
local headerPool, entryPool = {}, {}
local flat = {}
local NUM_VISIBLE = 0
local emptyLabel

local function getPane()
  if pane then return pane end
  pane = _G.DragonUI_NewEra_CharacterPane_Skills or (CP.EnsurePane and CP.EnsurePane("Skills"))
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
      row:ClearAllPoints()
      row:SetWidth(rowW)
      row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
      row:Show()
    end
  end
end

local function refresh()
  if not getPane() then return end
  if not scroll then return end
  flat = {}

  if not (GetNumSkillLines and GetSkillLineInfo) then
    log("GetNumSkillLines/GetSkillLineInfo unavailable — Skills pane degraded")
    updateScroll()
    return
  end

  local ok, total = pcall(GetNumSkillLines)
  if not ok or not total then total = 0 end

  for i = 1, total do
    -- §B: pcall every getter.
    local ok2, name, header, isExpanded, rank, _, modifier, maxRank = pcall(GetSkillLineInfo, i)
    if ok2 and name then
      local info = {
        skillIndex = i, name = name, isHeader = header, isExpanded = isExpanded,
        rank = rank, maxRank = maxRank, modifier = modifier,
      }
      flat[#flat + 1] = { kind = header and "header" or "entry", info = info }
    end
  end

  updateScroll()
end
-- DOWNPORT/REPORT: surface (don't swallow) a refresh error so an empty Skills pane is diagnosable.
CP.RefreshSkills = function()
  local ok, err = pcall(refresh)
  if not ok then log("RefreshSkills error: " .. tostring(err)) end
end

local function recomputeVisible()
  if not scroll then return end
  local h = scroll:GetHeight() or 0
  NUM_VISIBLE = math.max(1, math.floor(h / ROW_HEIGHT))
end

local function build()
  local host = getPane()
  if not host then log("Skills pane host missing — cannot build"); return false end
  if scroll then return true end

  local bg = host:CreateTexture(nil, "BACKGROUND")
  if not setAtlas(bg, "character-panel-background", false) then bg:Hide() end
  bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)

  scroll = CreateFrame("ScrollFrame", "DragonUI_NewEra_SkillsScroll", host, "FauxScrollFrameTemplate")
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
  -- DOWNPORT: hand-built minimal scrollbar (Reskin's stock-slider re-skin didn't render).
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll, { x = -8 }) end

  -- DOWNPORT/REPORT (the empty-pane bug): the row container must be a child of the PANE, not of the
  -- faux ScrollFrame. FauxScrollFrame_Update HIDES the scroll frame whenever the list fits with no
  -- scrolling needed (numItems <= numToDisplay) — which took content + every row down with it (Honor
  -- only rendered because its list overflowed). Parent content to host (always shown), anchor it over
  -- the scroll rect, and raise it above the scroll frame so header buttons stay clickable.
  content = CreateFrame("Frame", nil, host)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
  content:SetHeight(1)
  content:SetFrameLevel(scroll:GetFrameLevel() + 5)

  emptyLabel = host:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  emptyLabel:SetPoint("TOP", host, "TOP", 0, -40)
  emptyLabel:SetWidth(200)
  emptyLabel:SetText(_G.SKILLS and (_G.SKILLS .. " unavailable") or "No skills.")
  emptyLabel:Hide()

  recomputeVisible()
  return true
end

local function init()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  if not build() then return end
  pcall(refresh)
  local host = getPane()
  if host and not host._neSkillsShowHooked then
    host._neSkillsShowHooked = true
    host:HookScript("OnShow", function() recomputeVisible(); pcall(refresh) end)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("SKILL_LINES_CHANGED")
boot:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if C_Timer and C_Timer.After then C_Timer.After(0, init) else init() end
  else
    CP.RefreshSkills()
  end
end)
