-- DragonUI_NewEra/modules/character/Honor.lua — the Honor (PvP) secondary tab.
--
-- Fills the EMPTY pane DragonUI_NewEra_CharacterPane_Honor (created by TabButtons.lua, parented
-- to NE.charpanel.frame.Inset). PvP rank BADGE + progress bar + collapsible honor-stat sections
-- (Today / Yesterday / This Week / Last Week / Lifetime), ported from
-- NewEra/CharacterPanel/Honor.lua.
--
-- DOWNPORT (CONTRACT_S1 §A.2/§B): NewEra used a retail WowScrollBox factory (CP.CreateHonorPane)
-- over the stock HonorFrame. 3.3.5a has no WowScrollBox, so we render DIRECTLY into our pane with
-- a NAMED FauxScrollFrame (unnamed FauxScrollFrameTemplate ERRORS) over a flat header/row list.
--
-- DATA (3.3.5a HonorFrame.lua — these tuples DIFFER from NewEra's Classic source; transcribed
-- from the live FrameXML):
--   GetPVPSessionStats()    -> hk, cp            (NO dishonorable kills on WotLK)
--   GetPVPYesterdayStats()  -> hk, contribution
--   GetPVPThisWeekStats()   -> hk, contribution  (exists; stock UI leaves it commented out)
--   GetPVPLastWeekStats()   -> hk, dk?, contribution, rank  (guarded; may be absent on a realm)
--   GetPVPLifetimeStats()   -> hk, highestRank   (NO lifetime DK on WotLK)
--   UnitPVPRank("player"); GetPVPRankInfo(rank) -> rankName, rankNumber; GetPVPRankProgress() 0..1
-- Badge = Interface\PvPRankBadges\PvPRank%02d. DOWNPORT: dishonorable-kill rows from the Classic
-- schema are DROPPED (no WotLK API) rather than rendered as "--".
--
-- GRACEFUL DEGRADATION (§A.5): every getter is pcall-guarded; missing data → that row reads "--";
-- if the whole PvP API is gone the pane shows an unranked hint and logs — NEVER errors.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local function log(msg)
  if CP._log then CP._log("HONOR: " .. tostring(msg)); return end
  if NE.Log then NE.Log("HONOR", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [honor]: " .. tostring(msg))
  end
end

local function L(global, fallback)
  local v = _G[global]
  if type(v) == "string" and v ~= "" then return v end
  return fallback
end

-- Geometry. DOWNPORT/REPORT: Honor content is DETERMINISTIC (rank block + exactly 5 sections × 2 rows),
-- so it is sized to FIT the ~338px viewport when fully expanded (48 + 5*22 + 10*16 = 318) — no scroll
-- needed, which sidesteps the no-clip overflow + absolute-scroll quirks entirely. Collapsing only frees
-- more room. (Skills/Reputation have unbounded lists and keep real windowed scrolling.)
local HEADER_H = 22
local ROW_H    = 16
local RANK_H   = 48    -- badge + progress-bar block (fits the 1–2 line unranked hint at full width)

local FILL_TEX = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then return NE.tex.SetAtlas(tex, name, useAtlasSize) end
  return false
end

-- Only numbers/strings reach SetText (a stray table tostring'd into a row = the breakage NewEra
-- guarded against).
local function disp(v)
  local t = type(v)
  if t == "number" or t == "string" then return tostring(v) end
  return "--"
end

-- Stat section schema (WotLK-adapted: no dishonorable kills).
local HK      = L("HONORABLE_KILLS", "Honorable Kills")
local CONTRIB = L("CONTRIBUTION_POINTS", "Honor Points")

local SECTIONS = {
  { title = L("HONOR_THIS_SESSION", "Today"),    keys = { { HK, "sessionHK" }, { CONTRIB, "sessionCP" } } },
  { title = L("HONOR_YESTERDAY", "Yesterday"),   keys = { { HK, "yHK" }, { CONTRIB, "yCP" } } },
  { title = L("HONOR_THISWEEK", "This Week"),     keys = { { HK, "twHK" }, { CONTRIB, "twCP" } } },
  { title = L("HONOR_LASTWEEK", "Last Week"),     keys = { { HK, "lwHK" }, { CONTRIB, "lwCP" } } },
  { title = L("HONOR_LIFETIME", "Lifetime"),      keys = { { HK, "lHK" }, { L("HIGHEST_RANK", "Highest Rank"), "lRankName" } } },
}

-- ---------------------------------------------------------------------------
-- Row builders.
-- ---------------------------------------------------------------------------
local function buildHeader(parent)
  local h = CreateFrame("Button", nil, parent)
  h:SetHeight(HEADER_H)

  h._bgLeft = h:CreateTexture(nil, "BACKGROUND")
  setAtlas(h._bgLeft, "options_listexpand_left", true)
  h._bgLeft:SetPoint("LEFT", h, "LEFT", 0, 0)

  h._bgRight = h:CreateTexture(nil, "BACKGROUND")
  setAtlas(h._bgRight, "options_listexpand_right_expanded", true)
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

local function buildValueRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(ROW_H)
  row._label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row._label:SetPoint("LEFT", row, "LEFT", 18, 0)
  row._label:SetJustifyH("LEFT")
  row._value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row._value:SetPoint("RIGHT", row, "RIGHT", -10, 0)
  row._value:SetJustifyH("RIGHT")
  return row
end

-- The rank block: badge + title + progress bar (+ unranked hint).
local function buildRankBlock(parent)
  local r = CreateFrame("Frame", nil, parent)
  r:SetHeight(RANK_H)

  r.icon = r:CreateTexture(nil, "ARTWORK")
  r.icon:SetSize(28, 28)
  r.icon:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -2)

  r.title = r:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  r.title:SetPoint("LEFT", r.icon, "RIGHT", 8, 0)
  r.title:SetJustifyH("LEFT")

  local bar = CreateFrame("StatusBar", nil, r)
  bar:SetHeight(13)
  -- Anchor bar + hint to the BLOCK (not the icon): the icon is hidden when unranked, and anchoring to
  -- a hidden region dragged the bar/hint up into an overlap with the next header.
  bar:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -32)
  bar:SetPoint("RIGHT", r, "RIGHT", -12, 0)
  bar:SetStatusBarTexture(FILL_TEX)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  local well = bar:CreateTexture(nil, "BACKGROUND")
  well:SetAllPoints(bar)
  if well.SetColorTexture then well:SetColorTexture(0, 0, 0, 0.55) else well:SetTexture(0, 0, 0, 0.55) end
  r.bar = bar

  r.hint = r:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  r.hint:SetPoint("TOPLEFT", r, "TOPLEFT", 14, -22)
  r.hint:SetPoint("RIGHT", r, "RIGHT", -12, 0)
  r.hint:SetJustifyH("LEFT")
  r.hint:SetWordWrap(true)
  r.hint:SetText("Earn honorable kills in battlegrounds and world PvP to gain rank.")
  r.hint:Hide()
  return r
end

-- ---------------------------------------------------------------------------
-- Data gather (every getter pcall-guarded; missing → nil → row "--").
-- ---------------------------------------------------------------------------
local function safe(fn, ...)
  if type(fn) ~= "function" then return end
  local r = { pcall(fn, ...) }
  if r[1] then return select(2, unpack(r)) end
end

local function gatherStats()
  local s = {}
  s.sessionHK, s.sessionCP = safe(GetPVPSessionStats)
  s.yHK, s.yCP             = safe(GetPVPYesterdayStats)
  s.twHK, s.twCP           = safe(GetPVPThisWeekStats)
  -- LastWeek tuple varies (hk, dk, contribution, rank) — take HK + contribution defensively.
  local lwHK, lw2, lw3     = safe(GetPVPLastWeekStats)
  s.lwHK = lwHK
  s.lwCP = (lw3 ~= nil) and lw3 or lw2   -- contribution is arg2 or arg3 depending on dk presence
  local lHK, highestRank   = safe(GetPVPLifetimeStats)
  s.lHK = lHK
  local lRankName = highestRank and safe(GetPVPRankInfo, highestRank)
  s.lRankName = lRankName or L("NONE", "None")
  return s
end

-- ---------------------------------------------------------------------------
-- Pane scaffold (named FauxScrollFrame; flat list of rank block + headers + rows).
-- ---------------------------------------------------------------------------
local pane, scroll, content, rankBlock
local sectionHeaders = {}   -- title -> header button
local valueRows      = {}   -- key   -> value row
local expanded       = {}   -- title -> bool (default true)
local flat           = {}
local NUM_VISIBLE    = 0
local unavailLabel

local function getPane()
  if pane then return pane end
  pane = _G.DragonUI_NewEra_CharacterPane_Honor or (CP.EnsurePane and CP.EnsurePane("Honor"))
  return pane
end

-- Variable row heights → we lay rows out absolutely from a running Y rather than a fixed slot.
-- We still drive scroll with a fixed "scroll step" via FauxScrollFrame, mapping offset→a Y cursor.
-- Simpler + robust: rebuild the flat list (each item carries its own height), then on scroll show
-- the slice that fits. Because the honor content is small/bounded we use a single fixed step.
local SCROLL_STEP = ROW_H

local function rebuildFlat(stats)
  flat = {}
  -- Rank block is always first.
  flat[#flat + 1] = { kind = "rank", h = RANK_H }
  for _, sec in ipairs(SECTIONS) do
    if expanded[sec.title] == nil then expanded[sec.title] = true end
    flat[#flat + 1] = { kind = "header", title = sec.title, h = HEADER_H }
    if expanded[sec.title] then
      for _, kd in ipairs(sec.keys) do
        flat[#flat + 1] = { kind = "row", label = kd[1], key = kd[2], h = ROW_H,
                            value = stats and disp(stats[kd[2]]) or "--" }
      end
    end
  end
end

local function totalHeight()
  local t = 0
  for _, it in ipairs(flat) do t = t + it.h end
  return t
end

-- Acquire/recycle widgets by stable identity (rank block is a singleton; headers keyed by title;
-- value rows keyed by data key) so we never thrash CreateFrame.
local function acquireHeader(title)
  local h = sectionHeaders[title]
  if not h then
    h = buildHeader(content)
    h:SetScript("OnClick", function()
      expanded[title] = not expanded[title]
      if CP.RefreshHonor then CP.RefreshHonor() end
    end)
    sectionHeaders[title] = h
  end
  h._name:SetText(title)
  setAtlas(h._bgRight, expanded[title] and "options_listexpand_right_expanded" or "options_listexpand_right", true)
  return h
end

local function acquireRow(key)
  local row = valueRows[key]
  if not row then row = buildValueRow(content); valueRows[key] = row end
  return row
end

local function hideAllDynamic()
  for _, h in pairs(sectionHeaders) do h:Hide() end
  for _, row in pairs(valueRows) do row:Hide() end
  if rankBlock then rankBlock:Hide() end
end

local function layout()
  if not (scroll and content) then return end
  hideAllDynamic()

  if unavailLabel then unavailLabel:Hide() end

  local rowW = content:GetWidth() or 200
  if rowW <= 0 then rowW = 200 end

  -- FauxScrollFrame here scrolls by pixels-as-steps: total "lines" = ceil(totalHeight/STEP).
  local total = totalHeight()
  local lineCount = math.ceil(total / SCROLL_STEP)
  local visLines  = NUM_VISIBLE > 0 and NUM_VISIBLE or 1
  if FauxScrollFrame_Update then FauxScrollFrame_Update(scroll, lineCount, visLines, SCROLL_STEP) end
  local offsetLines = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(scroll)) or 0
  local scrollPx = offsetLines * SCROLL_STEP

  -- DOWNPORT/REPORT (overflow-onto-tabs bug): content runs taller than the viewport, and 3.3.5a frames
  -- do NOT clip children — so rows past the bottom spilled below the box onto the tab buttons. CULL:
  -- only show an item that fits ENTIRELY within the scroll viewport band [0 .. -viewH]; hide the rest
  -- (revealed by scrolling). This is the windowing Skills/Reputation get for free from their fixed slots.
  local viewH = scroll:GetHeight() or 0
  -- Scroll DOWN must move content UP, so the first item's y grows POSITIVE (off the top) as scrollPx
  -- increases — the earlier -scrollPx pushed content DOWN (gap above the rank block on scroll).
  local y = scrollPx   -- top of the first item relative to content top (positive = scrolled off top)
  for _, it in ipairs(flat) do
    local w
    if it.kind == "rank" then
      if not rankBlock then rankBlock = buildRankBlock(content); CP._honorRank = rankBlock end
      w = rankBlock
    elseif it.kind == "header" then
      w = acquireHeader(it.title)
    else
      w = acquireRow(it.key)
      w._label:SetText(it.label)
      w._value:SetText(it.value or "--")
    end
    local top, bottom = y, y - it.h
    if top <= 0.5 and bottom >= -viewH - 0.5 then
      w:ClearAllPoints()
      w:SetWidth(rowW)
      w:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
      w:Show()
    else
      w:Hide()
    end
    y = y - it.h
  end
end

-- Apply rank data to the (already-built) rank block.
local function applyRank()
  if not rankBlock then return end
  local raw = safe(UnitPVPRank, "player")
  local rankName, rankNumber = safe(GetPVPRankInfo, raw)
  rankNumber = tonumber(rankNumber) or 0
  local progress = safe(GetPVPRankProgress) or 0

  -- Title sits beside the badge when ranked, or top-left (where the badge would be) when unranked.
  local function anchorTitle(withIcon)
    rankBlock.title:ClearAllPoints()
    if withIcon then
      rankBlock.title:SetPoint("LEFT", rankBlock.icon, "RIGHT", 8, 0)
    else
      rankBlock.title:SetPoint("TOPLEFT", rankBlock, "TOPLEFT", 14, -6)
    end
  end

  if rankNumber > 0 then
    rankBlock.icon:SetTexture(string.format("Interface\\PvPRankBadges\\PvPRank%02d", rankNumber))
    rankBlock.icon:Show()
    anchorTitle(true)
    rankBlock.title:SetText(string.format("%s (%s %d)", disp(rankName), L("RANK", "Rank"), rankNumber))
    rankBlock.bar:Show()
    rankBlock.hint:Hide()
  elseif progress and progress > 0 then
    rankBlock.icon:Hide()
    anchorTitle(false)
    rankBlock.title:SetText(L("PVP_UNRANKED", "Unranked"))
    rankBlock.bar:Show()
    rankBlock.hint:Hide()
  else
    rankBlock.icon:Hide()
    anchorTitle(false)
    rankBlock.title:SetText(L("PVP_UNRANKED", "Unranked"))
    rankBlock.bar:Hide()
    rankBlock.hint:Show()
  end

  local fg = safe(UnitFactionGroup, "player")
  if fg == "Alliance" then rankBlock.bar:SetStatusBarColor(0.05, 0.15, 0.36)
  else rankBlock.bar:SetStatusBarColor(0.63, 0.09, 0.09) end
  rankBlock.bar:SetValue(math.max(0, math.min(1, progress or 0)))
end

local function refresh()
  if not getPane() then return end
  if not scroll then return end

  local apiOk = type(UnitPVPRank) == "function" and type(GetPVPSessionStats) == "function"
  if not apiOk then
    log("PvP API unavailable — Honor pane degraded")
    flat = {}
    hideAllDynamic()
    if unavailLabel then unavailLabel:Show() end
    if FauxScrollFrame_Update then FauxScrollFrame_Update(scroll, 0, 1, SCROLL_STEP) end
    return
  end

  local stats = gatherStats()
  rebuildFlat(stats)
  -- Ensure the rank block exists before layout positions it, then fill it.
  if not rankBlock then rankBlock = buildRankBlock(content); CP._honorRank = rankBlock end
  layout()
  applyRank()
end
-- DOWNPORT/REPORT: surface (don't swallow) a refresh error so a broken Honor pane is diagnosable.
CP.RefreshHonor = function()
  local ok, err = pcall(refresh)
  if not ok then log("RefreshHonor error: " .. tostring(err)) end
end

local function recomputeVisible()
  if not scroll then return end
  local h = scroll:GetHeight() or 0
  NUM_VISIBLE = math.max(1, math.floor(h / SCROLL_STEP))
end

local function build()
  local host = getPane()
  if not host then log("Honor pane host missing — cannot build"); return false end
  if scroll then return true end

  local bg = host:CreateTexture(nil, "BACKGROUND")
  if not setAtlas(bg, "character-panel-background", false) then bg:Hide() end
  bg:SetPoint("TOPLEFT", host, "TOPLEFT", 2, -2)
  bg:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -2, 2)

  scroll = CreateFrame("ScrollFrame", "DragonUI_NewEra_HonorScroll", host, "FauxScrollFrameTemplate")
  -- DOWNPORT/REPORT: viewport inset to sit INSIDE the engraved inset box (top/left margin), leaving a
  -- right gutter for the scrollbar (pushed out to the frame border by the negative BuildCustom x below).
  scroll:SetPoint("TOPLEFT", host, "TOPLEFT", 10, -12)
  scroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -24, 10)
  scroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, SCROLL_STEP, layout)
  end)
  -- DOWNPORT/REPORT: wheel scrolling. BuildCustom hides the stock slider but Faux still drives it, so
  -- nudging the (hidden) slider's value scrolls + auto-clamps to its range. Without this the culled
  -- bottom rows were unreachable.
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = _G[(self:GetName() or "") .. "ScrollBar"]
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * SCROLL_STEP
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)
  scroll:HookScript("OnSizeChanged", function() recomputeVisible(); layout() end)
  -- DOWNPORT: hand-built minimal scrollbar (Reskin's stock-slider re-skin didn't render).
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll, { x = -8 }) end

  -- DOWNPORT/REPORT (the empty-pane bug): parent content to the PANE, not the faux ScrollFrame.
  -- FauxScrollFrame_Update hides the scroll frame when the list fits (no scroll needed), which would
  -- take content + rows with it. Honor renders today only because its list overflows; a low-content
  -- player (no honor data) would hit the same vanish. Anchor over the scroll rect, raise above it.
  content = CreateFrame("Frame", nil, host)
  content:SetPoint("TOPLEFT", scroll, "TOPLEFT", 0, 0)
  content:SetPoint("RIGHT", scroll, "RIGHT", 0, 0)
  content:SetHeight(1)
  content:SetFrameLevel(scroll:GetFrameLevel() + 5)

  unavailLabel = host:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  unavailLabel:SetPoint("TOP", host, "TOP", 0, -40)
  unavailLabel:SetWidth(200)
  unavailLabel:SetText(L("HONOR", "Honor") .. " unavailable")
  unavailLabel:Hide()

  recomputeVisible()
  return true
end

local function init()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  if not build() then return end
  pcall(refresh)
  local host = getPane()
  if host and not host._neHonorShowHooked then
    host._neHonorShowHooked = true
    host:HookScript("OnShow", function() recomputeVisible(); pcall(refresh) end)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_PVP_KILLS_CHANGED")
boot:RegisterEvent("PLAYER_PVP_RANK_CHANGED")
boot:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if C_Timer and C_Timer.After then C_Timer.After(0, init) else init() end
  else
    CP.RefreshHonor()
  end
end)
