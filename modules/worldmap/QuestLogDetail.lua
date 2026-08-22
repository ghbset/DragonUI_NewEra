-- DragonUI_NewEra/modules/worldmap/QuestLogDetail.lua — the quest-log panel's DETAIL pane.
--
-- DOWNPORT of NewEra/WorldMap/QuestLogDetail.lua, split out of QuestLogPanel.lua the same way the
-- 1.15 source splits it: same namespace (NE.questlogpanel), geometry and helpers handed across in
-- `P._priv` rather than re-derived, and `P._BuildDetail` exported for the list side to call. Loads
-- AFTER QuestLogPanel.lua.
--
-- Retail fills this pane through `QuestInfo_Display(QUEST_TEMPLATE_MAP_DETAILS/REWARDS)`, a
-- template system that does not exist on 3.3.5a. The visible content is instead reproduced from
-- this client's own quest-log API, which reads from a CURSOR the caller has to move first —
-- `SelectQuestLogEntry(index)` — so every getter below is meaningless until P.SelectQuest has run.
-- That is why RefreshDetail re-selects rather than trusting the cursor to have stayed put: the
-- stock quest log, the tracker and any other addon all move the same cursor.
--
-- The reward grid deliberately uses the client's own `GameTooltip:SetQuestLogItem("reward", i)` /
-- `("choice", i)` rather than building a tooltip from the returned fields. Those two calls are what
-- the stock quest log uses, so a server with custom reward text gets it right for free.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.questlogpanel = NE.questlogpanel or {}
local P = NE.questlogpanel
local _p = P._priv
if not _p then return end

local safe       = _p.safe
local levelColor = _p.levelColor
local GUTTER     = _p.GUTTER
local CONTENT_W  = _p.CONTENT_W
local TOP_BAND_H = _p.TOP_BAND_H

local FOOTER_H   = 30
local REWARD_SIZE = 32
local REWARD_COLS = 2

-- ----------------------------------------------------------------------------
-- Reward buttons
-- ----------------------------------------------------------------------------

local function acquireReward(parent, pool, i)
  local b = pool[i]
  if b then return b end

  b = CreateFrame("Button", nil, parent)
  b:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)   -- above the body it scrolls in
  b:SetSize(CONTENT_W / REWARD_COLS - 6, REWARD_SIZE + 4)

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(REWARD_SIZE, REWARD_SIZE)
  b.icon:SetPoint("LEFT", b, "LEFT", 0, 0)

  b.border = b:CreateTexture(nil, "OVERLAY")
  b.border:SetPoint("TOPLEFT", b.icon, "TOPLEFT", -1, 1)
  b.border:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", 1, -1)
  b.border:SetTexture("Interface\\Buttons\\UI-Quickslot2")
  b.border:SetTexCoord(0.2, 0.8, 0.2, 0.8)
  b.border:Hide()

  b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -2, 2)

  b.label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.label:SetPoint("LEFT", b.icon, "RIGHT", 4, 0)
  b.label:SetPoint("RIGHT", b, "RIGHT", -2, 0)
  b.label:SetJustifyH("LEFT")
  if b.label.SetWordWrap then b.label:SetWordWrap(false) end

  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")

  b:SetScript("OnEnter", function(self)
    if not (GameTooltip and self._slot) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    -- The client's own call, so custom server reward text comes through unchanged.
    local ok = pcall(GameTooltip.SetQuestLogItem, GameTooltip, self._kind, self._slot)
    if ok then GameTooltip:Show() else GameTooltip:Hide() end
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  pool[i] = b
  return b
end

local function dressReward(b, kind, slot, name, texture, numItems, quality)
  b._kind, b._slot = kind, slot
  b.icon:SetTexture(texture)
  b.label:SetText(name or "")
  if quality and _G.ITEM_QUALITY_COLORS and _G.ITEM_QUALITY_COLORS[quality] then
    local c = _G.ITEM_QUALITY_COLORS[quality]
    b.label:SetTextColor(c.r, c.g, c.b)
  else
    b.label:SetTextColor(1, 1, 1)
  end
  if numItems and numItems > 1 then b.count:SetText(numItems) else b.count:SetText("") end
  b.border:Show()
  b:Show()
end

-- ----------------------------------------------------------------------------
-- Build
-- ----------------------------------------------------------------------------

function P._BuildDetail(panel)
  if panel._neDetail then return panel._neDetail end

  local d = CreateFrame("Frame", "NE_WorldMapQuestDetail", panel)
  d:SetPoint("TOPLEFT",     panel, "TOPLEFT",      GUTTER, -6)
  d:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -(GUTTER + 4), 6)
  -- Clear of the list side AND of the panel itself: the detail pane's Back button, its reward
  -- tiles and its three footer buttons are all interactive, and a mouse-enabled parent on this
  -- client will swallow a child's clicks unless the child outranks it (see QuestLogPanel.Build).
  d:SetFrameLevel(panel:GetFrameLevel() + 4)
  d:Hide()

  -- Back, in the top band where the search box lives on the list side.
  local back = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
  back:SetSize(60, 20)
  back:SetPoint("TOPLEFT", d, "TOPLEFT", 0, 0)
  back:SetFrameLevel(d:GetFrameLevel() + 2)
  back:SetText("< " .. (_G.BACK or "Back"))
  back:SetScript("OnClick", function() P.Deselect() end)
  d.back = back

  -- The scrolling body.
  local scroll = CreateFrame("ScrollFrame", "NE_WorldMapQuestDetailScroll", d, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",     d, "TOPLEFT",      0, -(TOP_BAND_H))
  scroll:SetPoint("BOTTOMRIGHT", d, "BOTTOMRIGHT", -8, FOOTER_H + 4)
  scroll:SetFrameLevel(d:GetFrameLevel() + 1)
  local body = CreateFrame("Frame", nil, scroll)
  body:SetFrameLevel(scroll:GetFrameLevel() + 1)
  body:SetSize(CONTENT_W, 1)
  scroll:SetScrollChild(body)
  d.scroll, d.body = scroll, body
  if NE.scrollbar and NE.scrollbar.BuildCustomPixel then
    pcall(NE.scrollbar.BuildCustomPixel, scroll, { x = -4 })
  end

  -- Content, top to bottom. Every FontString is left-justified and word-wrapped; heights are read
  -- back after SetText so the layout follows the real wrapped height rather than a guess.
  d.title = body:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  d.title:SetPoint("TOPLEFT", body, "TOPLEFT", 0, 0)
  d.title:SetWidth(CONTENT_W)
  d.title:SetJustifyH("LEFT")

  d.objHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.objHeader:SetWidth(CONTENT_W)
  d.objHeader:SetJustifyH("LEFT")
  d.objHeader:SetText(_G.OBJECTIVES_LABEL or "Objectives")

  d.objText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.objText:SetWidth(CONTENT_W)
  d.objText:SetJustifyH("LEFT")

  d.objLines = {}

  d.descHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.descHeader:SetWidth(CONTENT_W)
  d.descHeader:SetJustifyH("LEFT")
  d.descHeader:SetText(_G.DESCRIPTION or "Description")

  d.descText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.descText:SetWidth(CONTENT_W)
  d.descText:SetJustifyH("LEFT")

  d.rewardHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.rewardHeader:SetWidth(CONTENT_W)
  d.rewardHeader:SetJustifyH("LEFT")

  d.choiceHeader = body:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.choiceHeader:SetWidth(CONTENT_W)
  d.choiceHeader:SetJustifyH("LEFT")

  d.moneyText = body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  d.moneyText:SetWidth(CONTENT_W)
  d.moneyText:SetJustifyH("LEFT")

  d.rewardPool = {}
  d.choicePool = {}

  -- Footer: the three actions retail puts under the detail pane.
  local function footerButton(text, x, onClick)
    local b = CreateFrame("Button", nil, d, "UIPanelButtonTemplate")
    b:SetSize(96, 22)
    b:SetPoint("BOTTOMLEFT", d, "BOTTOMLEFT", x, 2)
    b:SetFrameLevel(d:GetFrameLevel() + 2)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
  end

  d.trackBtn = footerButton(_G.TRACK_QUEST_ABBREV or "Track", 0, function()
    P.ToggleTrack(P.selectedIndex)
    if P.RefreshDetail then P.RefreshDetail() end
  end)

  -- Abandon reproduces the stock quest log's own flow (QuestLogFrameAbandonButton_OnClick): move
  -- the cursor, arm the abandon, then raise whichever popup matches whether the quest has items to
  -- destroy. Doing it any other way loses the "you will destroy N items" warning.
  d.abandonBtn = footerButton(_G.ABANDON_QUEST_ABBREV or "Abandon", 100, function()
    local index = P.selectedIndex
    if not index then return end
    safe(_G.SelectQuestLogEntry, index)
    safe(_G.SetAbandonQuest)
    local items = safe(_G.GetAbandonQuestItems)
    if items and _G.StaticPopup_Show then
      _G.StaticPopup_Show("ABANDON_QUEST_WITH_ITEMS", items)
    elseif _G.StaticPopup_Show then
      _G.StaticPopup_Show("ABANDON_QUEST", safe(_G.GetAbandonQuestName))
    end
  end)

  d.shareBtn = footerButton(_G.SHARE_QUEST_ABBREV or "Share", 200, function()
    local index = P.selectedIndex
    if not index then return end
    safe(_G.SelectQuestLogEntry, index)
    safe(_G.QuestLogPushQuest)
  end)

  panel._neDetail = d
  return d
end

-- ----------------------------------------------------------------------------
-- Fill
-- ----------------------------------------------------------------------------

-- Stack a region under the previous one and return the new running Y. Reading the height BACK after
-- the text is set is what makes a wrapped description lay out correctly — a fixed per-block height
-- would either clip long quest text or leave a hole under short text.
local function stack(region, y, gap)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", region:GetParent(), "TOPLEFT", 0, -(y + (gap or 0)))
  region:Show()
  return y + (gap or 0) + (region:GetHeight() or 0)
end

function P.RefreshDetail(index)
  local d = P.detail
  if not d then return end
  index = index or P.selectedIndex
  if not index then return end
  P.selectedIndex = index

  -- The cursor is shared with the stock quest log and the tracker, so it is re-pointed here rather
  -- than assumed — see the header.
  safe(_G.SelectQuestLogEntry, index)

  local title, level = safe(_G.GetQuestLogTitle, index)
  local description, objectives = safe(_G.GetQuestLogQuestText)

  local y = 0

  d.title:SetText(title or "")
  local c = levelColor(level)
  d.title:SetTextColor(c.r, c.g, c.b)
  y = stack(d.title, y, 0)

  -- Objectives: the summary line the quest text carries, then the live per-objective progress.
  if objectives and objectives ~= "" then
    y = stack(d.objHeader, y, 10)
    d.objText:SetText(objectives)
    y = stack(d.objText, y, 2)
  else
    d.objHeader:Hide(); d.objText:Hide()
  end

  local numObj = safe(_G.GetNumQuestLeaderBoards, index) or 0
  for j = 1, numObj do
    local fs = d.objLines[j]
    if not fs then
      fs = d.body:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetWidth(CONTENT_W - 8)
      fs:SetJustifyH("LEFT")
      d.objLines[j] = fs
    end
    local text, _, finished = safe(_G.GetQuestLogLeaderBoard, j, index)
    fs:SetText("- " .. (text or ""))
    if finished then fs:SetTextColor(0.2, 0.8, 0.2) else fs:SetTextColor(0.8, 0.8, 0.8) end
    y = stack(fs, y, 2)
  end
  for j = numObj + 1, #d.objLines do d.objLines[j]:Hide() end

  if description and description ~= "" then
    y = stack(d.descHeader, y, 10)
    d.descText:SetText(description)
    y = stack(d.descText, y, 2)
  else
    d.descHeader:Hide(); d.descText:Hide()
  end

  -- Rewards. Choices first (retail's order), then guaranteed rewards, then money and XP.
  local function layoutRewards(pool, kind, count, getter, header, headerText)
    if count <= 0 then
      header:Hide()
      for i = 1, #pool do pool[i]:Hide() end
      return y
    end
    header:SetText(headerText)
    y = stack(header, y, 10)
    local rowTop = y + 4
    for i = 1, count do
      local name, texture, numItems, quality = getter(i)
      local b = acquireReward(d.body, pool, i)
      dressReward(b, kind, i, name, texture, numItems, quality)
      local col = (i - 1) % REWARD_COLS
      local row = math.floor((i - 1) / REWARD_COLS)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", d.body, "TOPLEFT",
                 col * (CONTENT_W / REWARD_COLS), -(rowTop + row * (REWARD_SIZE + 8)))
    end
    for i = count + 1, #pool do pool[i]:Hide() end
    local rows = math.ceil(count / REWARD_COLS)
    return rowTop + rows * (REWARD_SIZE + 8)
  end

  local numChoices = safe(_G.GetNumQuestLogChoices) or 0
  y = layoutRewards(d.choicePool, "choice", numChoices,
        function(i) return safe(_G.GetQuestLogChoiceInfo, i) end,
        d.choiceHeader, _G.REWARD_CHOOSE or "Choose one:")

  local numRewards = safe(_G.GetNumQuestLogRewards) or 0
  y = layoutRewards(d.rewardPool, "reward", numRewards,
        function(i) return safe(_G.GetQuestLogRewardInfo, i) end,
        d.rewardHeader, _G.REWARD_ITEMS_ONLY or "You will receive:")

  -- Money and XP, on one line each when present.
  local money = safe(_G.GetQuestLogRewardMoney) or 0
  local xp    = safe(_G.GetQuestLogRewardXP) or 0
  local bits = {}
  if money > 0 then bits[#bits + 1] = NE.money.Text(money) end
  if xp > 0 then
    bits[#bits + 1] = (_G.BONUS_OBJECTIVE_EXPERIENCE_FORMAT
                       and string.format(_G.BONUS_OBJECTIVE_EXPERIENCE_FORMAT, xp))
                      or (xp .. " " .. (_G.XP or "XP"))
  end
  if #bits > 0 then
    d.moneyText:SetText(table.concat(bits, "   "))
    y = stack(d.moneyText, y, 10)
  else
    d.moneyText:Hide()
  end

  d.body:SetHeight(math.max(y + 8, 1))

  -- The Track button reads as a toggle, so its label has to say which way it will go.
  local tracked = P.IsTracked(index)
  d.trackBtn:SetText(tracked and (_G.UNTRACK_QUEST_ABBREV or "Untrack")
                             or (_G.TRACK_QUEST_ABBREV or "Track"))

  -- Sharing is only possible for a quest the client says is shareable; the button is disabled
  -- rather than hidden so the footer does not reflow under the player.
  local shareable = safe(_G.GetQuestLogPushable)
  if shareable then d.shareBtn:Enable() else d.shareBtn:Disable() end
end
