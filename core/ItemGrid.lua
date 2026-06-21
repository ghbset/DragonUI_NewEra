-- DragonUI_NewEra/core/ItemGrid.lua — reusable combined item-grid ENGINE (NE.itemgrid).
--
-- DOWNPORT: NewEra Core/ItemGrid.lua → 3.3.5a. The engine (pooled ContainerFrameItemButton-
-- Template buttons re-parented to per-container proxy frames so Era's native handlers resolve the
-- bag via GetParent():GetID()) is structurally portable. 3.3.5a adaptations:
--   * C_Container.* / C_Item.* come from the compat shim (CONTRACTS §1); we still feature-gate the
--     lowest-level calls so a missing shim can't hard-error.
--   * C_NewItems / NEW_ITEM_ATLAS_BY_QUALITY do NOT exist on 3.3.5a → the new-item glow path is
--     feature-gated (no-op).
--   * Enum.ItemQuality may be absent → Poor constant feature-gated to 0.
--   * SetShown → Show/Hide (HighlightContainer/ClearHighlight/JunkIcon).
--   * NE.slot.* (a sibling Core helper not in this sprint's deliverables) is feature-gated; when
--     absent we paint empty slots inline so the grid still works standalone.
--   * SetItemButtonQuality is the 4-arg-on-Era form; 3.3.5a's takes (button, quality) — we call
--     it pcall-safe with the extra arg, which 3.3.5a ignores.
--
-- §2 CONTRACT: NE.itemgrid.* preserved (NE.itemgrid.New, instance :Refresh, etc.).

local NE = DragonUI_NewEra
NE.itemgrid = NE.itemgrid or {}
local G = NE.itemgrid

NE.containerframe = NE.containerframe or {}
local M = NE.containerframe

-- DOWNPORT: SetShown shim.
local function setShown(obj, on)
  if not obj then return end
  if on then obj:Show() else obj:Hide() end
end

-- Does this item have an on-use effect? Cached by itemID.
local onUseCache = {}
local function itemHasOnUse(info)
  if not info then return false end
  local id = info.itemID
  if id and onUseCache[id] ~= nil then return onUseCache[id] end
  local key = info.hyperlink or id
  if not (key and C_Item and C_Item.GetItemSpell) then return false end
  local has = C_Item.GetItemSpell(key) ~= nil
  if id then onUseCache[id] = has end
  return has
end

-- Shared overlay hydration.
local OVERLAY_KEYS = {
  "BagStaticTop", "BagStaticBottom",
  "UpgradeIcon",
  "BattlepayItemTexture",
  "ExtendedSlot", "ExtendedOverlay", "ExtendedOverlay2",
}

local function silenceOverlays(btn)
  for _, key in ipairs(OVERLAY_KEYS) do
    local tex = btn[key]
    if tex and tex.Hide then tex:Hide() end
  end
  if btn.searchOverlay then btn.searchOverlay:Hide() end
end

-- Quest-STARTER detection (the "!" bang) via a hidden scanning tooltip, cached per itemID.
local _questScanTip
local _questStarterCache = {}
local QUEST_STARTS_TEXT = (type(ITEM_STARTS_QUEST) == "string" and ITEM_STARTS_QUEST) or "Begins a Quest"
local function itemStartsQuest(bag, slot, itemID)
  if itemID == nil then return false end
  local cached = _questStarterCache[itemID]
  if cached ~= nil then return cached end
  if not _questScanTip then
    _questScanTip = CreateFrame("GameTooltip", "NE_QuestScanTip", UIParent, "GameTooltipTemplate")
    _questScanTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  _questScanTip:ClearLines()
  _questScanTip:SetBagItem(bag, slot)
  local found = false
  for i = 1, _questScanTip:NumLines() do
    local fs = _G["NE_QuestScanTipTextLeft" .. i]
    local t = fs and fs:GetText()
    if t and t:find(QUEST_STARTS_TEXT, 1, true) then found = true; break end
  end
  _questStarterCache[itemID] = found
  return found
end

-- DOWNPORT: container quest-info shim — 3.3.5a has the global GetContainerItemQuestInfo
-- (returns isQuestItem, questId, isActive); C_Container.GetContainerItemQuestInfo is a compat
-- wrapper if present.
local function containerQuestInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemQuestInfo then
    local qi = C_Container.GetContainerItemQuestInfo(bag, slot)
    if type(qi) == "table" then return qi.isQuestItem, qi.questID, qi.isActive end
  end
  if GetContainerItemQuestInfo then
    return GetContainerItemQuestInfo(bag, slot)
  end
  return nil
end

-- Per-item conditional overlays — quest border, junk coin, new-item glow.
local function updateItemOverlays(btn, bag, slot, info)
  local quality = info and info.quality
  local noValue = info and info.hasNoValue

  local qt = btn.IconQuestTexture or (btn.GetName and _G[btn:GetName() .. "IconQuestTexture"])
  if qt then
    local isQuestItem, questID, isActive
    if info then
      isQuestItem, questID, isActive = containerQuestInfo(bag, slot)
    end
    local startsQuest = (isQuestItem or questID) and (not questID)
      and info and itemStartsQuest(bag, slot, info.itemID)
    if (questID and not isActive) or startsQuest then
      if TEXTURE_ITEM_QUEST_BANG then qt:SetTexture(TEXTURE_ITEM_QUEST_BANG) end; qt:Show()
    elseif questID or isQuestItem then
      if TEXTURE_ITEM_QUEST_BORDER then qt:SetTexture(TEXTURE_ITEM_QUEST_BORDER) end; qt:Show()
    else
      qt:Hide()
    end
  end

  if btn.JunkIcon then
    local POOR = (Enum and Enum.ItemQuality and Enum.ItemQuality.Poor) or 0
    local atMerchant = MerchantFrame and MerchantFrame:IsShown()
    setShown(btn.JunkIcon, (quality == POOR and not noValue and atMerchant) and true or false)
  end

  -- DOWNPORT: C_NewItems doesn't exist on 3.3.5a → the new-item glow is a no-op (feature-gated).
  local newTex = btn.NewItemTexture
  if newTex and C_NewItems and C_NewItems.IsNewItem then
    local isNew = info and C_NewItems.IsNewItem(bag, slot)
    if isNew then
      local atlas = (quality and NEW_ITEM_ATLAS_BY_QUALITY and NEW_ITEM_ATLAS_BY_QUALITY[quality])
        or "bags-glow-white"
      if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(newTex, atlas) end
      newTex:Show()
      if btn.flashAnim and not btn.flashAnim:IsPlaying() then btn.flashAnim:Play() end
      if btn.newitemglowAnim and not btn.newitemglowAnim:IsPlaying() then btn.newitemglowAnim:Play() end
    else
      newTex:Hide()
      if btn.flashAnim and btn.flashAnim:IsPlaying() then btn.flashAnim:Stop() end
      if btn.newitemglowAnim and btn.newitemglowAnim:IsPlaying() then btn.newitemglowAnim:Stop() end
    end
  elseif newTex then
    newTex:Hide()
  end
end

-- Clear the new-item glow on hover. DOWNPORT: C_NewItems feature-gated.
local function hookNewItemClear(btn)
  if not btn or btn._neGlowClearHook then return end
  btn._neGlowClearHook = true
  btn:HookScript("OnEnter", function(self)
    local parent = self.GetParent and self:GetParent()
    local bag  = self._bagID  or (parent and parent.GetID and parent:GetID())
    local slot = self._slotID or (self.GetID and self:GetID())
    if bag and slot and C_NewItems and C_NewItems.RemoveNewItem then
      C_NewItems.RemoveNewItem(bag, slot)
    end
    if self.NewItemTexture then self.NewItemTexture:Hide() end
    if self.flashAnim and self.flashAnim:IsPlaying() then self.flashAnim:Stop() end
    if self.newitemglowAnim and self.newitemglowAnim:IsPlaying() then self.newitemglowAnim:Stop() end
  end)
end

-- Back-compat exports.
M.UpdateItemOverlays = updateItemOverlays
G.ItemStartsQuest = itemStartsQuest
M.HookNewItemClear   = hookNewItemClear
M.SilenceOverlays    = silenceOverlays

-- Authenticator "locked" slot — shared visual. DOWNPORT: IsAccountSecured feature-gated.
local LOCK_ATLAS = "bags-padlock-authenticator"

function M.WantLockedSlots()
  if M._hideLocked then return false end
  return not (IsAccountSecured and IsAccountSecured())
end

local function lockOnEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_NONE")
  if ContainerFrameItemButton_CalculateItemTooltipAnchors then
    ContainerFrameItemButton_CalculateItemTooltipAnchors(self, GameTooltip)
  else
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  end
  GameTooltip:SetText(BACKPACK_AUTHENTICATOR_INCREASE_SIZE or "", 1, 1, 1, 1, true)
  GameTooltip:Show()
end

function M.ApplyLockedSlot(btn, locked)
  if locked then
    if not btn._neLock then
      local lock = CreateFrame("Frame", nil, btn)
      lock:SetAllPoints(btn)
      lock:EnableMouse(true)
      local tex = lock:CreateTexture(nil, "OVERLAY")
      if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(tex, LOCK_ATLAS) end
      tex:SetSize(41, 49)
      tex:SetPoint("CENTER")
      lock.tex = tex
      lock:SetScript("OnEnter", lockOnEnter)
      lock:SetScript("OnLeave", GameTooltip_Hide)
      btn._neLock = lock
    end
    btn._neLock:SetFrameLevel(btn:GetFrameLevel() + 5)
    btn._neLock:Show()
    btn:EnableMouse(false)
  elseif btn._neLock then
    btn._neLock:Hide()
    btn:EnableMouse(true)
  end
end

-- DOWNPORT: NE.slot.* (a sibling Core helper, not ported this sprint) is feature-gated. When
-- absent these inline helpers keep the grid self-sufficient.
local function slotWireTooltip(b)
  if NE.slot and NE.slot.WireTooltip then NE.slot.WireTooltip(b); return end
  -- Inline fallback: standard container item tooltip.
  if b._neTooltipWired then return end
  b._neTooltipWired = true
  b:SetScript("OnEnter", function(self)
    local bag, slot = self._bagID, self._slotID
    if not (bag and slot) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.UpdateTooltip then self.UpdateTooltip = nil end
    GameTooltip:SetBagItem(bag, slot)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
local function slotMarkEmpty(b) if NE.slot and NE.slot.MarkEmpty then NE.slot.MarkEmpty(b) end end
local function slotApplyEmpty(b)
  if NE.slot and NE.slot.ApplyEmpty then NE.slot.ApplyEmpty(b); return end
  if SetItemButtonTexture then SetItemButtonTexture(b, nil) end
end

-- Grid instance factory.
function G.New(opts)
  local self = {
    host       = opts.host,
    columns    = opts.columns or 10,
    itemSize   = opts.itemSize or 37,
    spacingX   = opts.spacingX or 5,
    spacingY   = opts.spacingY or 5,
    originX    = opts.originX or 8,
    originY    = opts.originY or -66,
    direction  = opts.direction or "TLBR",
    slotDescending = opts.slotDescending or false,
    slotCount  = opts.slotCount,
    cellPos    = opts.cellPos,
    isSlotLocked = opts.isSlotLocked,
    sortExtendedLast = opts.sortExtendedLast,
    namePrefix = opts.namePrefix or "NE_GridItem",
    _containers = opts.containers,
    pool       = {},
    proxies    = {},
  }

  local function containerList()
    if type(self._containers) == "function" then return self._containers() end
    return self._containers
  end

  local function getProxy(container)
    local p = self.proxies[container]
    if not p then
      p = CreateFrame("Frame", self.namePrefix .. "Proxy" .. (container < 0 and "m" .. -container or container), self.host)
      p:SetID(container)
      p:SetAllPoints(self.host)
      self.proxies[container] = p
    end
    return p
  end

  local function getButton(index)
    local b = self.pool[index]
    if b then return b end
    b = CreateFrame("Button", self.namePrefix .. index, self.host, "ContainerFrameItemButtonTemplate")
    b:SetSize(self.itemSize, self.itemSize)
    slotWireTooltip(b)
    slotMarkEmpty(b)
    silenceOverlays(b)
    hookNewItemClear(b)
    if not b.BagIndicator then
      local ind = b:CreateTexture(nil, "OVERLAY", nil, 2)
      ind:SetTexture("Interface\\Store\\store-item-highlight")
      ind:SetPoint("CENTER")
      ind:Hide()
      b.BagIndicator = ind
    end
    self.pool[index] = b
    return b
  end

  local function cellXY(index, totalRows)
    local cell = index - 1
    local col, row
    if self.direction == "BRTL" then
      local colFromRight  = cell % self.columns
      local rowFromBottom = math.floor(cell / self.columns)
      col = (self.columns - 1) - colFromRight
      row = (totalRows - 1) - rowFromBottom
    else
      col = cell % self.columns
      row = math.floor(cell / self.columns)
    end
    local x =  self.originX + col * (self.itemSize + self.spacingX)
    local y =  self.originY - row * (self.itemSize + self.spacingY)
    return x, y
  end

  local function numSlots(c)
    if self.slotCount then return self.slotCount(c) or 0 end
    return (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(c)) or 0
  end

  function self:Refresh()
    local containers = containerList()
    self._maxRight, self._maxDown = 0, 0
    local total = 0
    for _, c in ipairs(containers) do
      total = total + numSlots(c)
    end
    local totalRows = math.ceil(total / self.columns)

    local entries = {}
    for _, bag in ipairs(containers) do
      local n = numSlots(bag)
      local sFrom, sTo, sStep = 1, n, 1
      if self.slotDescending then sFrom, sTo, sStep = n, 1, -1 end
      for slot = sFrom, sTo, sStep do
        local locked = self.isSlotLocked and self.isSlotLocked(bag, slot) or false
        entries[#entries + 1] = { bag = bag, slot = slot, locked = locked }
      end
    end
    if self.sortExtendedLast then
      local anyLocked = false
      for _, e in ipairs(entries) do if e.locked then anyLocked = true; break end end
      if anyLocked then
        local reordered, locked = {}, {}
        for _, e in ipairs(entries) do
          if e.locked then locked[#locked + 1] = e else reordered[#reordered + 1] = e end
        end
        for _, e in ipairs(locked) do reordered[#reordered + 1] = e end
        entries = reordered
      end
    end

    self._lastLocked = nil
    do
      for index = 1, #entries do
        local e = entries[index]
        local bag, slot = e.bag, e.slot
        local btn = getButton(index)

        local proxy = getProxy(bag)
        if btn:GetParent() ~= proxy then
          if InCombatLockdown() then
            btn._pendingParent = bag
          else
            btn:SetParent(proxy)
            btn._pendingParent = nil
          end
        end
        btn:SetID(slot)
        btn:SetFrameLevel((opts.frameLevel and opts.frameLevel()) or (self.host:GetFrameLevel() + 5))
        btn._bagID, btn._slotID = bag, slot
        local info = C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag, slot)

        local cooldown = _G[btn:GetName() .. "Cooldown"] or btn.Cooldown
        if cooldown and C_Container and C_Container.GetContainerItemCooldown then
          if itemHasOnUse(info) then
            local cdStart, cdDuration, cdEnable = C_Container.GetContainerItemCooldown(bag, slot)
            if CooldownFrame_Set then CooldownFrame_Set(cooldown, cdStart, cdDuration, cdEnable) end
            local g = (cdDuration and cdDuration > 0 and cdEnable == 0) and 0.4 or 1
            if SetItemButtonTextureVertexColor then SetItemButtonTextureVertexColor(btn, g, g, g) end
          else
            if CooldownFrame_Set then CooldownFrame_Set(cooldown, 0, 0, 0) end
            if SetItemButtonTextureVertexColor then SetItemButtonTextureVertexColor(btn, 1, 1, 1) end
          end
        end

        local x, y
        if self.cellPos then
          x, y = self.cellPos(index - 1)
        else
          x, y = cellXY(index, totalRows)
        end
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", self.host, "TOPLEFT", x, y)
        if x + self.itemSize > self._maxRight then self._maxRight = x + self.itemSize end
        if -y + self.itemSize > self._maxDown then self._maxDown = -y + self.itemSize end

        silenceOverlays(btn)
        if info then
          if SetItemButtonTexture then SetItemButtonTexture(btn, info.iconFileID) end
          if SetItemButtonCount then SetItemButtonCount(btn, info.stackCount) end
          if SetItemButtonQuality then pcall(SetItemButtonQuality, btn, info.quality, info.itemID) end
          if SetItemButtonDesaturated then SetItemButtonDesaturated(btn, info.isLocked) end
          local icon = btn.icon or _G[btn:GetName() .. "IconTexture"]
          if icon then
            icon:SetTexCoord(0, 1, 0, 1)
            icon:ClearAllPoints()
            icon:SetAllPoints(btn)
          end
          if btn.searchOverlay then
            setShown(btn.searchOverlay, info.isFiltered and true or false)
          end
        else
          slotApplyEmpty(btn)
          if SetItemButtonCount then SetItemButtonCount(btn, 0) end
          if SetItemButtonDesaturated then SetItemButtonDesaturated(btn, false) end
          if btn.searchOverlay then btn.searchOverlay:Hide() end
        end
        updateItemOverlays(btn, bag, slot, info)

        local locked = e.locked
        M.ApplyLockedSlot(btn, locked)
        if locked then self._lastLocked = btn end

        btn:Show()
      end
    end

    for i = #entries + 1, #self.pool do
      self.pool[i]:Hide()
      self.pool[i]._bagID  = nil
      self.pool[i]._slotID = nil
    end

    local contentW, contentH
    if self.cellPos then
      contentW, contentH = self._maxRight, self._maxDown
    else
      contentW = self.columns * self.itemSize + (self.columns - 1) * self.spacingX
      contentH = totalRows * self.itemSize + math.max(totalRows - 1, 0) * self.spacingY
    end
    return total, totalRows, contentW, contentH
  end

  function self:GetLastLockedButton()
    return self._lastLocked
  end

  function self:FlushPendingParents()
    for _, btn in ipairs(self.pool) do
      if btn._pendingParent ~= nil then
        btn:SetParent(getProxy(btn._pendingParent))
        btn._pendingParent = nil
      end
    end
  end

  function self:ForEachButton(fn)
    for _, btn in ipairs(self.pool) do
      if btn:IsShown() then fn(btn) end
    end
  end

  function self:HighlightContainer(bagID)
    for _, btn in ipairs(self.pool) do
      if btn.BagIndicator then setShown(btn.BagIndicator, btn:IsShown() and btn._bagID == bagID) end
    end
  end

  function self:ClearHighlight()
    for _, btn in ipairs(self.pool) do
      if btn.BagIndicator then btn.BagIndicator:Hide() end
    end
  end

  return self
end
