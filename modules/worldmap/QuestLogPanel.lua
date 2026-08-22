-- DragonUI_NewEra/modules/worldmap/QuestLogPanel.lua — retail's Quest Log side panel on the map.
--
-- DOWNPORT of NewEra/WorldMap/QuestLogPanel.lua (1,734 lines) + the shell of QuestLogDetail.lua.
-- The 1.15 source draws retail's QuestMapFrame over Era's `C_QuestLog` API; this client has no
-- C_QuestLog at all, so the VIEW is transcribed and the MODEL is rebuilt on 3.3.5a's own quest-log
-- API — `GetNumQuestLogEntries` / `GetQuestLogTitle` / `SelectQuestLogEntry` / `GetQuestLogQuestText`
-- / `GetQuestLogLeaderBoard` / `IsQuestWatched`. Everything below is that translation.
--
-- IT EXTENDS THE WINDOW, IT DOES NOT OVERLAY IT. Retail's combined Map & Quest Log widens the frame
-- by the panel's width and insets the canvas by the same amount, so the map keeps its own size and
-- the panel fills the space that was added. WorldMap.lua reads `P.PanelWidth()` on every geometry
-- pass and does exactly that; this file only has to report a number and ask for a re-layout.
--
-- ART. The 1.15 source dresses this in retail's questlog sheets (5684755 / 5684744 / 904010), none
-- of which are shipped here and none of which can be extracted from this machine. Rather than ship
-- a panel that renders blank, it is built from the art this addon ALREADY has — the stone body, the
-- InsetFrameTemplate nineslice and the minimal scrollbar — which is what the guild, social and
-- auction-house windows are made of too. It therefore matches the rest of the window set rather
-- than matching retail's quest log exactly. Dropping the real sheets in later is a restyle of this
-- file, not a rewrite: the row geometry below is retail's.
--
-- THE CLIENT'S OWN QUEST LIST IS SQUELCHED (WorldMap.lua's SQUELCH_GLOBALS: WorldMapQuestScrollFrame
-- and friends). `QuestLogFrame` — the standalone quest log on the L key — is deliberately left
-- alone; this is a second view of the same data, not a replacement for that window.
--
-- COMBAT. Selecting a quest draws its area blob, and `WorldMapBlobFrame` is PROTECTED on this
-- client — `DrawQuestBlob` throws in combat. Every blob call here is gated (PORT_PLAN.md §5.1).

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.questlogpanel = NE.questlogpanel or {}
local P  = NE.questlogpanel
local WM = NE.worldmap

-- ----------------------------------------------------------------------------
-- Geometry (retail's QuestMapFrame numbers, from the 1.15 source's live probe)
-- ----------------------------------------------------------------------------

local PANEL_W      = 330
local TOP_BAND_H   = 29     -- holds the search box + the settings cog
local ROW_H        = 22     -- a zone header, and a quest title row
local OBJ_H        = 14     -- one objective line
local ROW_INDENT   = 31     -- retail's quest-title x inset (clears the POI marker)
local OBJ_INDENT   = 42
local GUTTER       = 10
local CONTENT_W    = PANEL_W - (GUTTER * 2) - 14   -- 14 = the scrollbar gutter

-- ----------------------------------------------------------------------------
-- Model helpers
-- ----------------------------------------------------------------------------

-- pcall's results are passed straight through rather than packed into a table, because packing
-- LOSES ARITY: `#{ pcall(f) }` stops at the first nil, and this client's getters have holes in the
-- middle of their return lists. `GetQuestLogTitle` returns
--     title, level, tag, suggestedGroup, isHeader, isCollapsed, isComplete, isDaily
-- with `suggestedGroup` nil for almost every quest — so a table-and-unpack version silently
-- truncates at position 4 and every quest reads as a non-header with no complete or daily flag.
-- (Found by qa/offline/test_worldmap.lua, which is exactly why that harness exists.)
local function stripOk(ok, ...)
  if not ok then return nil end
  return ...
end

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  return stripOk(pcall(fn, ...))
end

-- 3.3.5a's GetQuestLogTitle does not return a quest ID. The ID is recoverable from the quest LINK,
-- which is the standard technique on this client and the only one that works — the blob renderer
-- and the POI system are both keyed on it.
local function questIDAt(index)
  local link = safe(_G.GetQuestLink, index)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match("|Hquest:(%d+):"))
end
P.QuestIDAt = questIDAt

-- The quest log as a flat display list. Entries are one of:
--   { kind = "header",    index, title, collapsed }
--   { kind = "quest",     index, title, level, tag, complete, daily, watched }
--   { kind = "objective", text, finished }
--
-- Objectives are only emitted for the SELECTED quest, which is retail's behaviour and this
-- client's: an expanded list of every objective of every quest is the old quest log, not this one.
local function buildList(selectedIndex)
  local out = {}
  local numEntries = safe(_G.GetNumQuestLogEntries)
  if type(numEntries) ~= "number" then return out end

  for i = 1, numEntries do
    local title, level, tag, group, isHeader, isCollapsed, isComplete, isDaily =
      safe(_G.GetQuestLogTitle, i)
    if title then
      if isHeader then
        out[#out + 1] = { kind = "header", index = i, title = title, collapsed = isCollapsed }
      else
        local watched = safe(_G.IsQuestWatched, i) and true or false
        out[#out + 1] = {
          -- `group` is the SUGGESTED GROUP SIZE, and it is carried because the quest tag is a
          -- localised string and this is not: a quest with a suggested group and no recognised tag
          -- still earns the group badge.
          kind = "quest", index = i, title = title, level = level, tag = tag, group = group,
          complete = (isComplete == 1), failed = (isComplete == -1),
          daily = isDaily and true or false, watched = watched,
        }
        if selectedIndex == i then
          local n = safe(_G.GetNumQuestLeaderBoards, i) or 0
          for j = 1, n do
            local text, _, finished = safe(_G.GetQuestLogLeaderBoard, j, i)
            if text then
              out[#out + 1] = { kind = "objective", text = text, finished = finished and true or false }
            end
          end
        end
      end
    end
  end
  return out
end
P.BuildList = buildList

-- Quest-level colour. This client's own ladder where it has one, our shared five-tier fallback
-- where it does not — the tier names match core/FrameUtil.lua's NE.difficultyTier.
local TIER_COLOR = {
  impossible    = { r = 1.00, g = 0.10, b = 0.10 },
  verydifficult = { r = 1.00, g = 0.50, b = 0.25 },
  difficult     = { r = 1.00, g = 0.82, b = 0.00 },
  standard      = { r = 0.25, g = 0.75, b = 0.25 },
  trivial       = { r = 0.50, g = 0.50, b = 0.50 },
}

local function levelColor(level)
  local c = safe(_G.GetQuestDifficultyColor, level) or safe(_G.GetDifficultyColor, level)
  if type(c) == "table" and c.r then return c end
  return TIER_COLOR[NE.difficultyTier(level)] or TIER_COLOR.difficult
end

-- ----------------------------------------------------------------------------
-- The map blob
-- ----------------------------------------------------------------------------

-- WorldMapBlobFrame is protected: DrawQuestBlob raises in combat. Every call goes through here, and
-- in combat it is simply dropped rather than deferred — a blob drawn thirty seconds late, for a
-- quest the player has since stopped looking at, is worse than no blob.
local function drawBlob(questId, show)
  local blob = _G.WorldMapBlobFrame
  if not (blob and questId and blob.DrawQuestBlob) then return end
  if InCombatLockdown and InCombatLockdown() then return end
  pcall(blob.DrawQuestBlob, blob, questId, show and true or false)
end

local function clearBlob()
  if P.blobQuestID then
    drawBlob(P.blobQuestID, false)
    P.blobQuestID = nil
  end
end

local function showBlob(index)
  clearBlob()
  local id = questIDAt(index)
  if not id then return end
  P.blobQuestID = id
  drawBlob(id, true)
end
P.ClearBlob = clearBlob

-- ----------------------------------------------------------------------------
-- Selection
-- ----------------------------------------------------------------------------

-- Selecting a quest does three things: it points the client's own quest-log cursor at it (every
-- Get* below reads from that cursor, so it must move first), it draws the area blob, and it swaps
-- the list for the detail pane.
function P.SelectQuest(index)
  if not index or type(_G.SelectQuestLogEntry) ~= "function" then return end
  safe(_G.SelectQuestLogEntry, index)
  P.selectedIndex = index
  showBlob(index)
  P.ShowDetail(index)
end

function P.Deselect()
  P.selectedIndex = nil
  clearBlob()
  P.ShowList()
end

-- ----------------------------------------------------------------------------
-- Tracking
-- ----------------------------------------------------------------------------

function P.IsTracked(index)
  return safe(_G.IsQuestWatched, index) and true or false
end

function P.ToggleTrack(index)
  if not index then return end
  if P.IsTracked(index) then
    safe(_G.RemoveQuestWatch, index)
  else
    -- The client caps how many quests can be watched at once and says nothing when the cap is hit,
    -- so the message is ours. MAX_WATCHABLE_QUESTS is the client's own constant.
    local cap = _G.MAX_WATCHABLE_QUESTS or 25
    local n = safe(_G.GetNumQuestWatches) or 0
    if n >= cap then
      if UIErrorsFrame and _G.QUEST_WATCH_TOO_MANY then
        UIErrorsFrame:AddMessage(_G.QUEST_WATCH_TOO_MANY, 1.0, 0.1, 0.1, 1.0)
      end
      return
    end
    safe(_G.AddQuestWatch, index)
  end
  -- The stock tracker reads its list from the same watch state; nudge it so both views agree.
  if type(_G.QuestWatch_Update) == "function" then pcall(_G.QuestWatch_Update) end
  if type(_G.QuestLog_Update) == "function" then pcall(_G.QuestLog_Update) end
  P.Refresh()
end

-- ----------------------------------------------------------------------------
-- Art helpers
-- ----------------------------------------------------------------------------

-- A HORIZONTAL 3-slice out of one atlas rect: two fixed end caps and a stretched middle.
--
-- `questlog-tab`, the zone-header bar, is 64px wide with 18px caps (the reference addon's
-- AtlasSlice.lua records l=18 r=18 t=0 b=0). A zone header is ~290px, so stretching the whole thing
-- would pull those rounded caps out to four and a half times their width -- which does not read as
-- a wider bar, it reads as a smeared one. Three pieces, cropped from the same texture.
--
-- Returns nil when the art is missing, which every caller treats as "draw the plain version".
local function hSlice(parent, layer, atlasName, capPx)
  local entry = NE.tex._atlasEntry and NE.tex._atlasEntry(atlasName)
  local src = entry and NE.tex.localFiles and NE.tex.localFiles[entry.file]
  if not (entry and src and entry.width and entry.width > 0) then return nil end

  local uPerPx = (entry.right - entry.left) / entry.width
  local capU   = capPx * uPerPx
  local o = { cap = capPx, height = entry.height or 22, pieces = {} }
  for i = 1, 3 do
    local t = parent:CreateTexture(nil, layer)
    t:SetTexture(src)
    o.pieces[i] = t
  end
  o.pieces[1]:SetTexCoord(entry.left,          entry.left + capU,  entry.top, entry.bottom)
  o.pieces[2]:SetTexCoord(entry.left + capU,   entry.right - capU, entry.top, entry.bottom)
  o.pieces[3]:SetTexCoord(entry.right - capU,  entry.right,        entry.top, entry.bottom)

  function o:Layout(anchor, x, y, width, height)
    height = height or self.height
    local L, M, R = self.pieces[1], self.pieces[2], self.pieces[3]
    L:ClearAllPoints(); L:SetPoint("TOPLEFT", anchor, "TOPLEFT", x, y); L:SetSize(self.cap, height)
    R:ClearAllPoints(); R:SetPoint("TOPLEFT", anchor, "TOPLEFT", x + width - self.cap, y)
    R:SetSize(self.cap, height)
    M:ClearAllPoints(); M:SetPoint("TOPLEFT", L, "TOPRIGHT", 0, 0)
    M:SetSize(math.max(width - self.cap * 2, 1), height)
  end
  function o:Show() for _, t in ipairs(self.pieces) do t:Show() end end
  function o:Hide() for _, t in ipairs(self.pieces) do t:Hide() end end
  return o
end

-- Swap a Button's state texture for an atlas. On 3.3.5a the setter takes a PATH, not a texture
-- object, so the texture is seeded from the sheet and then cropped through the Get*Texture handle --
-- the same pattern core/MaxMin.lua and PanelChrome's close button use.
local function atlasState(button, setter, getter, atlasName, size)
  local entry = NE.tex._atlasEntry and NE.tex._atlasEntry(atlasName)
  local src = entry and NE.tex.localFiles and NE.tex.localFiles[entry.file]
  if not (button and entry and src) then return false end
  -- Not every state-texture pair exists on every widget on this client -- CheckButton has
  -- SetCheckedTexture but no getter on some builds -- and calling a nil field is an error, not a
  -- graceful degrade. Check both halves before touching either.
  if type(button[setter]) ~= "function" or type(button[getter]) ~= "function" then return false end
  button[setter](button, src)
  local t = button[getter](button)
  if not t then return false end
  t:SetTexCoord(entry.left, entry.right, entry.top, entry.bottom)
  t:ClearAllPoints()
  t:SetPoint("CENTER")
  t:SetSize(size or entry.width or 16, size or entry.height or 16)
  -- Recorded because nothing else can tell afterwards: this crops by hand rather than going through
  -- NE.tex.SetAtlas, so the texture carries no trace of which atlas it is. A state texture that
  -- silently kept its fallback and one that took the real art look identical to any inspection.
  t._neAtlas = atlasName
  return true
end

-- The tag this client reports for a quest, mapped to the badge retail draws for it. `questTag` is
-- the LOCALISED string ("Dungeon", "Elite", "PvP"...), which is no use as a key -- but the numeric
-- facts beside it are: `GetQuestLogTitle` also returns the suggested group size, and a daily flag.
local function typeAtlasFor(entry)
  if entry.failed then return "questlog-questtypeicon-questfailed" end
  if entry.daily  then return "questlog-questtypeicon-daily" end
  local tag = entry.tag
  if type(tag) == "string" then
    -- Compared against the client's own localised constants rather than English literals, so a
    -- non-English client keeps its badges.
    if _G.RAID    and tag == _G.RAID    then return "questlog-questtypeicon-raid" end
    if _G.DUNGEON and tag == _G.DUNGEON then return "questlog-questtypeicon-dungeon" end
    if _G.PVP     and tag == _G.PVP     then return "questlog-questtypeicon-pvp" end
    if _G.ELITE   and tag == _G.ELITE   then return "questlog-questtypeicon-heroic" end
    if _G.GROUP   and tag == _G.GROUP   then return "questlog-questtypeicon-group" end
  end
  if entry.group and entry.group > 0 then return "questlog-questtypeicon-group" end
  return nil
end

-- ----------------------------------------------------------------------------
-- Rows
-- ----------------------------------------------------------------------------

local rowPool = {}

local function acquireRow(parent, i)
  local r = rowPool[i]
  if r then return r end

  r = CreateFrame("Button", nil, parent)
  -- Above the scroll child, for the same reason the panel's own children are (see P.Build).
  r:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
  r:SetWidth(CONTENT_W)

  -- The zone-header bar. Built once per pooled row and shown only for headers.
  r.tab = hSlice(r, "BACKGROUND", "questlog-tab", 18)
  if r.tab then r.tab:Hide() end

  -- The hover highlight: retail's own soft glow, stretched to the row (it has no hard edge, so it
  -- takes any width). Falls back to a flat tint if the sheet is not there.
  r.hover = r:CreateTexture(nil, "ARTWORK")
  r.hover:SetAllPoints(r)
  if not NE.tex.SetAtlas(r.hover, "questlog-quest-glow-yellow", false) then
    r.hover:SetTexture(1, 1, 1, 0.08)
  end
  r.hover:Hide()

  r.text = r:CreateFontString(nil, "OVERLAY", "GameFontNormalLeft")
  r.text:SetPoint("LEFT", r, "LEFT", ROW_INDENT, 0)
  r.text:SetPoint("RIGHT", r, "RIGHT", -24, 0)
  r.text:SetJustifyH("LEFT")
  if r.text.SetWordWrap then r.text:SetWordWrap(false) end

  -- A zone header's +/-, and a quest row's type badge, sit in the same slot: one is only ever shown
  -- when the other is not.
  r.marker = r:CreateTexture(nil, "OVERLAY")
  r.marker:SetSize(18, 18)
  r.marker:SetPoint("LEFT", r, "LEFT", GUTTER - 2, 0)

  -- The tracking checkbox, in retail's tick-square art.
  r.track = CreateFrame("CheckButton", nil, r)
  r.track:SetFrameLevel(r:GetFrameLevel() + 1)   -- and the checkbox above the row it sits on
  r.track:SetSize(18, 18)
  r.track:SetPoint("RIGHT", r, "RIGHT", -2, 0)
  if not atlasState(r.track, "SetNormalTexture", "GetNormalTexture", "questlog-icon-ticksquare", 14)
  then
    -- No sheet: keep the client's own checkbox, which is at least the right shape.
    r.track:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
    r.track:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
    r.track:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
  else
    atlasState(r.track, "SetPushedTexture",  "GetPushedTexture",  "questlog-icon-ticksquare", 14)
    atlasState(r.track, "SetCheckedTexture", "GetCheckedTexture", "questlog-icon-checkmark-yellow", 17)
  end
  r.track:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  r.track:SetScript("OnClick", function(self)
    P.ToggleTrack(self:GetParent()._index)
  end)

  r:SetScript("OnEnter", function(self) if self._hoverable then self.hover:Show() end end)
  r:SetScript("OnLeave", function(self) self.hover:Hide() end)

  rowPool[i] = r
  return r
end

-- Dress one row from a display-list entry. Returns the height it consumed.
local function dressRow(r, entry)
  r._index = entry.index
  r.hover:Hide()

  if entry.kind == "header" then
    r._hoverable = true
    r:SetHeight(ROW_H)
    -- The bar the header sits on, inset a little so consecutive headers do not touch.
    if r.tab then
      r.tab:Layout(r, 0, -1, CONTENT_W, ROW_H - 2)
      r.tab:Show()
    end
    r.text:SetPoint("LEFT", r, "LEFT", GUTTER + 1, 0)
    r.text:SetText(entry.title or "")
    r.text:SetTextColor(1, 0.82, 0)
    -- The +/- moves to the RIGHT on a header, which is where retail puts it.
    r.marker:ClearAllPoints()
    r.marker:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    if not NE.tex.SetAtlas(r.marker,
         entry.collapsed and "questlog-icon-expand" or "questlog-icon-shrink", false) then
      r.marker:Hide()
    else
      r.marker:SetSize(18, 18)
      r.marker:Show()
    end
    r.track:Hide()
    r:SetScript("OnClick", function(self)
      -- Collapsing renumbers every entry after this one, so nothing may be cached across the call.
      if entry.collapsed then
        safe(_G.ExpandQuestHeader, self._index)
      else
        safe(_G.CollapseQuestHeader, self._index)
      end
      P.Refresh()
    end)
    r:Show()
    return ROW_H

  elseif entry.kind == "quest" then
    r._hoverable = true
    r:SetHeight(ROW_H)
    if r.tab then r.tab:Hide() end
    r.text:SetPoint("LEFT", r, "LEFT", ROW_INDENT, 0)
    local label = entry.title or ""
    if entry.level and entry.level > 0 then
      label = "[" .. entry.level .. "] " .. label
    end
    if entry.complete then
      label = label .. " " .. (_G.QUEST_COMPLETE and ("(" .. _G.QUEST_COMPLETE .. ")") or "")
    elseif entry.failed then
      label = label .. " " .. (_G.FAILED and ("(" .. _G.FAILED .. ")") or "")
    end
    r.text:SetText(label)
    local c = levelColor(entry.level)
    r.text:SetTextColor(c.r, c.g, c.b)
    -- The type badge, back on the LEFT where a quest's marker belongs.
    r.marker:ClearAllPoints()
    r.marker:SetPoint("LEFT", r, "LEFT", GUTTER - 2, 0)
    local badge = typeAtlasFor(entry)
    if badge and NE.tex.SetAtlas(r.marker, badge, false) then
      r.marker:SetSize(18, 18)
      r.marker:Show()
    else
      r.marker:Hide()
    end
    r.track:Show()
    r.track:SetChecked(entry.watched)
    r:SetScript("OnClick", function(self) P.SelectQuest(self._index) end)
    r:Show()
    return ROW_H

  else -- objective
    r._hoverable = false
    r:SetHeight(OBJ_H)
    if r.tab then r.tab:Hide() end
    r.text:SetPoint("LEFT", r, "LEFT", OBJ_INDENT, 0)
    r.text:SetText("- " .. (entry.text or ""))
    if entry.finished then
      r.text:SetTextColor(0.2, 0.8, 0.2)
    else
      r.text:SetTextColor(0.8, 0.8, 0.8)
    end
    r.marker:Hide()
    r.track:Hide()
    r:SetScript("OnClick", nil)
    r:Show()
    return OBJ_H
  end
end

-- ----------------------------------------------------------------------------
-- Build
-- ----------------------------------------------------------------------------

-- Handed to QuestLogDetail.lua, which is split out of this file the same way the 1.15 source splits
-- it: same namespace, geometry and helpers passed across rather than re-derived.
P._priv = {
  PANEL_W = PANEL_W, GUTTER = GUTTER, CONTENT_W = CONTENT_W,
  TOP_BAND_H = TOP_BAND_H, safe = safe, levelColor = levelColor,
}

function P.Build()
  if P.frame then return P.frame end
  local map = WM and WM.frame
  if not map then return nil end

  local f = CreateFrame("Frame", "NE_WorldMapQuestLogPanel", WM.border or map)
  f:SetWidth(PANEL_W)
  -- Seats itself in the space WorldMap.lua adds for it: from under the title band down to the
  -- frame's bottom, hard against the right edge inside the border.
  f:SetPoint("TOPRIGHT",    map, "TOPRIGHT",    -3, -21)
  f:SetPoint("BOTTOMRIGHT", map, "BOTTOMRIGHT", -3,   2)
  f:SetFrameLevel(((WM.border or map):GetFrameLevel() or 1) + 2)
  -- The panel eats clicks rather than passing them through to the map behind it. That is wanted --
  -- but it is also why EVERY child of this frame needs an explicit frame level above it. On this
  -- client a child does NOT reliably outrank its parent for mouse input, so a mouse-enabled parent
  -- swallows its own children's clicks. In game that read as three separate bugs -- the cog did
  -- nothing, the search box would not focus, and no quest row could be clicked or tracked -- which
  -- were one bug wearing three hats, and the same one that had just made the breadcrumb invisible.
  f:EnableMouse(true)
  local LVL = f:GetFrameLevel()

  -- The recessed dark inset the whole window set puts under its content.
  local inset = CreateFrame("Frame", nil, f)
  inset:SetPoint("TOPLEFT",     f, "TOPLEFT",      2, -2)
  inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -2,  2)
  inset:SetFrameLevel(f:GetFrameLevel())
  -- The parchment the quest list sits on -- retail's own, and the reason this panel used to read as
  -- a dark slab: there was no panel ART behind it at all, only a tinted recess over the window's
  -- stone. With the parchment in, the recess is not wanted; it is kept only as the fallback for a
  -- client where the sheet fails to resolve, because a panel with NOTHING behind it is worse than
  -- one that is merely too dark.
  --
  -- DOWNPORT: the 1.15 source draws this at its native 307x510, anchored to the scroll's top-left
  -- and deliberately not stretched. That window is a fixed size; this one is resizable, so a native
  -- draw would leave bare stone below the parchment on any window taller than 510. It is stretched
  -- to the inset instead -- it is a paper texture with no hard detail, and it takes it.
  local parchment = inset:CreateTexture(nil, "BACKGROUND")
  parchment:SetAllPoints(inset)
  local havePaper = NE.tex.SetAtlas(parchment, "questlog-main-background", false)
  if not havePaper then parchment:Hide() end
  f.parchment = parchment

  local fill = inset:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(inset)
  -- 0.55, and this number has moved around, so here is the whole reasoning in one place.
  --
  -- The rest of the window set recesses at 0.85-0.9 (the Adventure Guide's content inset, the
  -- inspect window's). Those are small wells inside a window whose stone body is visible all around
  -- them, and that CONTRAST is what makes them read as sunk. This panel is not that shape: it is a
  -- full-height column taking a third of the window, with the map filling almost all of the rest --
  -- so there is barely any body left in view to contrast against, and at the house depth it just
  -- reads as a hole cut in the window.
  --
  -- (It was 0.45, then 0.30, chasing a panel that looked black for an unrelated reason: the window
  -- was painting its stone at PC.BODY_TINT rather than full brightness, so everything laid over it
  -- came out the same colour. That is fixed in WorldMap.lua's paintBody. This number is now about
  -- the panel's SIZE, which is the thing that actually makes it different from the other insets.)
  -- Over the parchment this is only a wash, to keep the quest text readable against the paper; with
  -- no parchment it IS the background, and has to carry the recess on its own.
  fill:SetTexture(0, 0, 0, havePaper and 0.25 or 0.55)
  f.fill = fill
  NE.nineslice.ApplyLayout(inset, "InsetFrameTemplate")
  f.inset = inset

  -- Top band: the search box, and a cog for the map-objective toggle the squelched checkbox used
  -- to own. Both sit above the inset's content, not inside the scroll.
  local search = CreateFrame("EditBox", "NE_WorldMapQuestSearch", f, "InputBoxTemplate")
  search:SetHeight(20)
  search:SetPoint("TOPLEFT",  f, "TOPLEFT",   GUTTER + 6, -6)
  search:SetPoint("TOPRIGHT", f, "TOPRIGHT", -(GUTTER + 22), -6)
  search:SetFrameLevel(LVL + 2)
  search:SetAutoFocus(false)
  search:SetScript("OnTextChanged", function(self)
    P.filter = self:GetText()
    if P.filter == "" then P.filter = nil end
    P.Refresh()
  end)
  search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
  f.search = search

  local cog = CreateFrame("Button", nil, f)
  cog:SetSize(16, 16)
  cog:SetPoint("TOPRIGHT", f, "TOPRIGHT", -GUTTER, -8)
  cog:SetFrameLevel(LVL + 2)
  if not atlasState(cog, "SetNormalTexture", "GetNormalTexture", "questlog-icon-setting", 15) then
    cog:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
  end
  cog:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
  cog:SetScript("OnClick", function(self) P.OpenCogMenu(self) end)
  cog:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(_G.OPTIONS or "Options")
    GameTooltip:Show()
  end)
  cog:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.cog = cog

  -- The list.
  local scroll = CreateFrame("ScrollFrame", "NE_WorldMapQuestLogScroll", f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",     f, "TOPLEFT",      GUTTER, -(TOP_BAND_H + 4))
  scroll:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(GUTTER + 8), 8)
  scroll:SetFrameLevel(LVL + 2)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetFrameLevel(scroll:GetFrameLevel() + 1)
  content:SetSize(CONTENT_W, 1)
  scroll:SetScrollChild(content)
  f.scroll, f.content = scroll, content
  -- BuildCustomPixel, not Reskin: this client's UIPanelScrollFrameTemplate names its slider
  -- `$parentScrollBar` with no parentKey, so Reskin's `scroll.ScrollBar` lookup is nil and it
  -- returns without touching anything (core/ScrollbarReskin.lua's own header records this).
  if NE.scrollbar and NE.scrollbar.BuildCustomPixel then
    pcall(NE.scrollbar.BuildCustomPixel, scroll, { x = -4 })
  end

  -- The filigree that caps the top of the list, and the gradient that fades out its bottom. Both are
  -- pure decoration: they are skipped silently if their sheet is missing.
  local filigree = inset:CreateTexture(nil, "ARTWORK")
  if NE.tex.SetAtlas(filigree, "questlog-frame-filigree", true) then
    filigree:ClearAllPoints()
    filigree:SetPoint("TOP", inset, "TOP", 0, 2)
  else
    filigree:Hide()
  end

  local gradient = inset:CreateTexture(nil, "ARTWORK")
  if NE.tex.SetAtlas(gradient, "questlog-frame-gradient-bottom", false) then
    gradient:ClearAllPoints()
    gradient:SetPoint("BOTTOMLEFT",  inset, "BOTTOMLEFT",   2, 2)
    gradient:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -2, 2)
    gradient:SetHeight(66)
  else
    gradient:Hide()
  end

  -- The detail pane lives on the same panel and swaps with the list.
  if P._BuildDetail then P.detail = P._BuildDetail(f) end

  P.frame = f
  P.shown = false
  f:Hide()
  return f
end

-- ----------------------------------------------------------------------------
-- Refresh
-- ----------------------------------------------------------------------------

function P.Refresh()
  local f = P.frame
  if not (f and f:IsShown()) then return end
  if P.detailShown then
    if P.RefreshDetail then P.RefreshDetail() end
    return
  end

  local list = buildList(P.selectedIndex)
  local filter = P.filter and P.filter:lower() or nil

  -- A filter hides quest rows that do not match, and any header left with nothing under it. That
  -- needs a look-ahead rather than a per-row decision, so the surviving headers are worked out in
  -- one pass first. Objectives ride with their quest and are matched on the QUEST's title, not on
  -- their own text — filtering "kill" should not strand an objective under a hidden quest.
  local rowVisible = {}
  if filter then
    local lastHeader
    for i, entry in ipairs(list) do
      if entry.kind == "header" then
        lastHeader = i
        rowVisible[i] = false
      elseif entry.kind == "quest" then
        local hit = entry.title and entry.title:lower():find(filter, 1, true) and true or false
        rowVisible[i] = hit
        if hit and lastHeader then rowVisible[lastHeader] = true end
        entry._filteredOut = not hit
      else
        -- An objective inherits its quest's fate; the quest is always the entry just above it.
        rowVisible[i] = rowVisible[i - 1] and true or false
      end
    end
  end

  local y = 0
  local n = 0
  for i, entry in ipairs(list) do
    local skip = filter and not rowVisible[i]
    if not skip then
      n = n + 1
      local r = acquireRow(f.content, n)
      local h = dressRow(r, entry)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
      y = y + h
    end
  end

  for i = n + 1, #rowPool do rowPool[i]:Hide() end
  -- Writing the content height fires the scroll frame's OnScrollRangeChanged, which is what the
  -- custom bar syncs off — so the thumb re-sizes itself and no explicit sync call is needed here.
  f.content:SetHeight(math.max(y, 1))
end

function P.ShowList()
  P.detailShown = false
  local f = P.frame
  if not f then return end
  if f.scroll then f.scroll:Show() end
  if f.search then f.search:Show() end
  if P.detail then P.detail:Hide() end
  P.Refresh()
end

function P.ShowDetail(index)
  local f = P.frame
  if not (f and P.detail) then return end
  P.detailShown = true
  if f.scroll then f.scroll:Hide() end
  if f.search then f.search:Hide() end
  P.detail:Show()
  if P.RefreshDetail then P.RefreshDetail(index) end
end

-- ----------------------------------------------------------------------------
-- Visibility — the bit WorldMap.lua reads
-- ----------------------------------------------------------------------------

-- The width the map window must add for this panel. Zero when the panel is hidden, and zero while
-- the map is MAXIMIZED — retail collapses the side panel on the fullscreen map, and WorldMap.lua
-- calls SetMaximized before its geometry pass so this already reads 0 by the time it is asked.
-- MAXIMIZING NO LONGER COLLAPSES THE PANEL, and the flag is kept only so callers can ask.
--
-- The collapse was copied from retail, where maximizing means FULLSCREEN and the map needs the
-- room. This window is not that: it goes to a preset size, and the panel EXTENDS it rather than
-- covering the map, so there is no room to reclaim. What the copy actually produced was the panel
-- disappearing on maximize, the toggle that would bring it back disappearing with it, and no way
-- to recover without minimizing again -- and if the maximize state got stuck, no way at all.
function P.PanelWidth()
  if not P.shown then return 0 end
  return PANEL_W
end

-- Switching mode adopts that mode's remembered answer. The toggle stays on screen throughout, so
-- either default can be overridden in place and the override sticks for that mode only.
function P.SetMaximized(maximized)
  P.maximized = maximized and true or false
  P.shown = P.ShownFor(P.maximized)

  local f = P.frame
  if not f and P.shown then f = P.Build() end
  if f then
    if P.shown then f:Show() else f:Hide() end
  end
  if P.shown then P.Refresh() end
  -- The caller re-runs the map's geometry after this, so the window resizes around the change.
  if WM and WM.RefreshSidePanelToggle then WM.RefreshSidePanelToggle() end
end

-- EACH MAP MODE REMEMBERS ITS OWN ANSWER, and they default differently: the small window has no room
-- to spare, so it opens without the panel; the maximized one does, so it keeps it. Clicking the
-- toggle sets the answer for the mode you are in, and the other mode is left alone.
local function panelKey(maximized)
  return maximized and "questPanelMax" or "questPanel"
end

local function defaultShown(maximized)
  return maximized and true or false
end

function P.ShownFor(maximized)
  local db = NE.db and NE.db.worldmap
  local v = db and db[panelKey(maximized)]
  if v == nil then return defaultShown(maximized) end
  return v and true or false
end
P._PanelKey = panelKey

function P.SetShown(shown)
  P.shown = shown and true or false
  if NE.db then
    NE.db.worldmap = NE.db.worldmap or {}
    NE.db.worldmap[panelKey(P.maximized)] = P.shown
  end
  local f = P.Build()
  if f then
    if P.shown then f:Show() else f:Hide() end
  end
  -- Re-run the map's geometry so the window widens or narrows around the panel.
  if WM and WM.ApplyGeometry then WM.ApplyGeometry() end
  if P.shown then P.Refresh() end
  if WM and WM.RefreshSidePanelToggle then WM.RefreshSidePanelToggle() end
end

function P.Toggle()
  P.SetShown(not P.shown)
end

-- ----------------------------------------------------------------------------
-- The cog menu
-- ----------------------------------------------------------------------------

-- One entry, and it is the one the squelched `WorldMapQuestShowObjectives` checkbox used to own.
-- Driving the client's own toggle function keeps the CVar and the blob state consistent instead of
-- reimplementing what it does.
-- The one entry is the one the squelched `WorldMapQuestShowObjectives` checkbox used to own.
-- Driving the client's own toggle function keeps the CVar and the blob state consistent instead of
-- reimplementing what it does.
--
-- Built through core/Menu.lua rather than raw EasyMenu. That is the house pattern here, and its
-- real value is that the TREE is separate from the render: `P.CogMenuGenerator` can be walked and
-- its callback invoked by the offline harness, so "the cog opens nothing" and "the cog opens a menu
-- whose entry does nothing" stop being the same observation. EasyMenu stays as the fallback for a
-- client where core/Menu.lua finds no backend.
function P.CogMenuGenerator(_, root)
  local WM = NE.worldmap
  root:CreateTitle(_G.MAP_AND_QUEST_LOG or "Quest Objectives")
  root:CreateCheckbox(
    _G.SHOW_QUEST_OBJECTIVES_ON_MAP or "Show quest objectives on the map",
    function() return WM and WM.QuestObjectivesShown and WM.QuestObjectivesShown() or false end,
    function()
      -- Routed through the chrome's own setter rather than poking the checkbox here: it persists
      -- the choice, applies it through the client, and re-places the markers, and doing two of
      -- those three is how the setting came to be off with nothing to say so.
      if WM and WM.SetQuestObjectives then
        WM.SetQuestObjectives(not WM.QuestObjectivesShown())
      end
    end)
  return root
end

function P.OpenCogMenu(anchor)
  if NE.menu and NE.menu.ToggleAnchored then
    NE.menu.ToggleAnchored(P.CogMenuGenerator, anchor,
      { point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = -2 })
    return
  end
  if not _G.EasyMenu then return end
  if not P._menuHost then
    P._menuHost = CreateFrame("Frame", "NE_WorldMapQuestCogMenu", UIParent, "UIDropDownMenuTemplate")
  end
  local box = _G.WorldMapQuestShowObjectives
  _G.EasyMenu({
    { text = _G.MAP_AND_QUEST_LOG or "Quest Objectives", isTitle = true, notCheckable = true },
    {
      text = _G.SHOW_QUEST_OBJECTIVES_ON_MAP or "Show quest objectives on the map",
      checked = box and box.GetChecked and box:GetChecked() and true or false,
      func = function()
        if not box then return end
        box:SetChecked(not box:GetChecked())
        if type(_G.WorldMapQuestShowObjectives_Toggle) == "function" then
          pcall(_G.WorldMapQuestShowObjectives_Toggle)
        end
      end,
    },
  }, P._menuHost, anchor, 0, 0, "MENU")
end

-- ----------------------------------------------------------------------------
-- Boot
-- ----------------------------------------------------------------------------

local events = CreateFrame("Frame")

function P.Arm()
  if P._armed then return end
  P._armed = true

  P.Build()
  P.maximized = (WM and WM.maximized) and true or false
  P.shown = P.ShownFor(P.maximized)

  for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_UPDATE", "QUEST_ACCEPTED", "UNIT_QUEST_LOG_CHANGED" }) do
    events:RegisterEvent(e)
  end
  events:SetScript("OnEvent", function() P.Refresh() end)

  -- The panel only exists while the map does: clear the blob on close so a quest area is not left
  -- painted on a hidden frame.
  local map = WM and WM.frame
  if map then
    map:HookScript("OnHide", function() clearBlob() end)
  end

  P.SetShown(P.shown)
end
