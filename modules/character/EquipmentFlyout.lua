-- DragonUI_NewEra/modules/character/EquipmentFlyout.lua — per-slot popout flyout: a
-- small arrow on each equipped paperdoll slot that opens a grid of bag items fitting
-- that slot; click one to equip it. Ported from retail's EquipmentFlyout (which the
-- 3.3.5 client does not load) + NewEra's port of it.
--
-- 3.3.5 DOWNPORTS vs the NewEra source:
--   * `local NE = DragonUI_NewEra`; arrows are wired onto the (reparented) Blizzard
--     slot buttons, which live in CP.frame.Inset now.
--   * Flyout parents to CP.frame (not _G.CharacterFrame) so it inherits the panel
--     scale; the frame falls back to UIParent if the panel isn't built yet.
--   * Equip uses the ItemRack physical swap (PickupContainerItem/PickupInventoryItem)
--     to match EquipmentSets.lua's backend (more reliable than EquipItemByName on
--     private servers — project memory). Out-of-combat only.
--   * C_Container routed via compat with positional-global fallbacks; GetItemInfoInstant
--     guarded (falls back to GetItemInfo equip-location at arg 9).
--   * No SetShown (Show/Hide); SetNormalTexture takes a path; pcall around getters.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local function log(msg) if CP._log then CP._log(msg) end end

-- Geometry.
local ITEMS_PER_ROW = 5
local EFITEM_W, EFITEM_H = 37, 37
local EFITEM_XOFF, EFITEM_YOFF = 4, -5
local BORDER = 3
local MAXBAG = _G.NUM_BAG_SLOTS or 4
local ARROW_TEX = "Interface\\PaperDollInfoFrame\\UI-GearManager-FlyoutButton"

-- Which bag-item equip locations fit each inventory slot.
local SLOT_INVTYPES = {
  [1]  = { INVTYPE_HEAD = true },
  [2]  = { INVTYPE_NECK = true },
  [3]  = { INVTYPE_SHOULDER = true },
  [4]  = { INVTYPE_BODY = true },
  [5]  = { INVTYPE_CHEST = true, INVTYPE_ROBE = true },
  [6]  = { INVTYPE_WAIST = true },
  [7]  = { INVTYPE_LEGS = true },
  [8]  = { INVTYPE_FEET = true },
  [9]  = { INVTYPE_WRIST = true },
  [10] = { INVTYPE_HAND = true },
  [11] = { INVTYPE_FINGER = true },
  [12] = { INVTYPE_FINGER = true },
  [13] = { INVTYPE_TRINKET = true },
  [14] = { INVTYPE_TRINKET = true },
  [15] = { INVTYPE_CLOAK = true },
  [16] = { INVTYPE_WEAPON = true, INVTYPE_2HWEAPON = true, INVTYPE_WEAPONMAINHAND = true },
  [17] = { INVTYPE_WEAPON = true, INVTYPE_WEAPONOFFHAND = true, INVTYPE_SHIELD = true, INVTYPE_HOLDABLE = true },
  [18] = { INVTYPE_RANGED = true, INVTYPE_RANGEDRIGHT = true, INVTYPE_THROWN = true, INVTYPE_RELIC = true },
  [19] = { INVTYPE_TABARD = true },
  [0]  = { INVTYPE_AMMO = true },
}

-- Slots that get an arrow.
local SLOT_NAMES = {
  "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
  "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
  "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
  "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
  "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

-- The weapon row opens DOWNWARD; everything else opens to the side.
local VERTICAL_FLYOUTS = { [16] = true, [17] = true, [18] = true }

-- ----------------------------------------------------------------------------
-- Container helpers — compat C_Container with positional-global fallback.
-- ----------------------------------------------------------------------------
local function bagNumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  return GetContainerNumSlots(bag) or 0
end
local function bagItemLink(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
  return GetContainerItemLink(bag, slot)
end
local function bagItemID(bag, slot)
  if C_Container and C_Container.GetContainerItemID then return C_Container.GetContainerItemID(bag, slot) end
  local link = bagItemLink(bag, slot)
  local id = link and link:match("item:(%d+)")
  return id and tonumber(id) or nil
end
-- equip location string for an item (id or link).
local function equipLocOf(itemOrLink)
  if type(GetItemInfoInstant) == "function" then
    local _, _, _, eloc = GetItemInfoInstant(itemOrLink)
    if eloc then return eloc end
  end
  return select(9, GetItemInfo(itemOrLink))
end

-- ----------------------------------------------------------------------------
-- Arrow facing.
-- ----------------------------------------------------------------------------
local function setArrowFacing(arrow, facing)
  local n, h = arrow:GetNormalTexture(), arrow:GetHighlightTexture()
  if not (n and h) then return end
  if facing == "down" then
    n:SetTexCoord(0.15625, 0.84375, 0.5, 0)
    h:SetTexCoord(0.15625, 0.84375, 1, 0.5)
  elseif facing == "up" then
    n:SetTexCoord(0.15625, 0.84375, 0, 0.5)
    h:SetTexCoord(0.15625, 0.84375, 0.5, 1)
  elseif facing == "left" then
    n:SetTexCoord(0.15625, 0, 0.84375, 0, 0.15625, 0.5, 0.84375, 0.5)
    h:SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 1, 0.84375, 1)
  else
    n:SetTexCoord(0.15625, 0.5, 0.84375, 0.5, 0.15625, 0, 0.84375, 0)
    h:SetTexCoord(0.15625, 1, 0.84375, 1, 0.15625, 0.5, 0.84375, 0.5)
  end
end

-- ----------------------------------------------------------------------------
-- Usability check — set the item on a hidden scanning tooltip and look for a RED
-- requirement line (level / class / proficiency all render red when unmet). A
-- broken-item durability line is also red but still equippable, so skip it.
-- ----------------------------------------------------------------------------
local DUR_PREFIX = ((DURABILITY_TEMPLATE or "Durability %d / %d"):match("^(.-)%s*%%%d")) or "Durability"
local scanTip
local function isUsable(bag, slot)
  if not scanTip then
    scanTip = CreateFrame("GameTooltip", "NE_EquipFlyoutScanTooltip", nil, "GameTooltipTemplate")
    scanTip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  scanTip:ClearLines()
  local ok = pcall(scanTip.SetBagItem, scanTip, bag, slot)
  if not ok then return true end   -- can't scan -> don't hide it
  for i = 2, scanTip:NumLines() do
    for _, side in ipairs({ "Left", "Right" }) do
      local fs = _G["NE_EquipFlyoutScanTooltipText" .. side .. i]
      if fs and fs:IsShown() then
        local txt = fs:GetText()
        local isDur = txt and txt:sub(1, #DUR_PREFIX) == DUR_PREFIX
        if txt and not isDur then
          local r, g, b = fs:GetTextColor()
          if r and r > 0.8 and g < 0.3 and b < 0.3 then return false end
        end
      end
    end
  end
  return true
end

-- ----------------------------------------------------------------------------
-- Bag enumeration for a slot.
-- ----------------------------------------------------------------------------
local function anyUsableForSlot(slotID)
  local accept = SLOT_INVTYPES[slotID]
  if not accept then return false end
  for bag = 0, MAXBAG do
    local n = bagNumSlots(bag)
    for s = 1, n do
      local id = bagItemID(bag, s)
      if id then
        local eloc = equipLocOf(id)
        if eloc and accept[eloc] and isUsable(bag, s) then return true end
      end
    end
  end
  return false
end

local function itemsForSlot(slotID)
  local accept = SLOT_INVTYPES[slotID]
  local out = {}
  if not accept then return out end
  for bag = 0, MAXBAG do
    local n = bagNumSlots(bag)
    for s = 1, n do
      local id = bagItemID(bag, s)
      if id then
        local eloc = equipLocOf(id)
        if eloc and accept[eloc] and isUsable(bag, s) then
          local texture, count, quality, link
          if C_Container and C_Container.GetContainerItemInfo then
            local info = C_Container.GetContainerItemInfo(bag, s)
            if info then
              texture = info.iconFileID
              count   = info.stackCount
              quality = info.quality
              link    = info.hyperlink
            end
          end
          if not texture then
            local tex, cnt, _, qual = GetContainerItemInfo(bag, s)
            texture, count, quality = tex, cnt, qual
          end
          out[#out + 1] = {
            bag = bag, slot = s, itemID = id,
            link = link or bagItemLink(bag, s),
            texture = texture,
            count = count or 1,
            quality = quality,
          }
        end
      end
    end
  end
  return out
end

-- ----------------------------------------------------------------------------
-- The shared flyout frame.
-- ----------------------------------------------------------------------------
local flyout

-- Equip a chosen item via the ItemRack physical swap (out of combat only).
local function equipItem(btn)
  local data = btn._data
  local slotID = flyout and flyout._slotID
  if not (data and slotID) then return end
  if InCombatLockdown() then
    if UIErrorsFrame then UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Can't do that in combat", 1, 0.1, 0.1, 1) end
    return
  end
  if CursorHasItem() or SpellIsTargeting() then return end

  -- 2H into main hand: clear the off-hand into the bag first.
  if slotID == 16 then
    local eloc = equipLocOf(data.itemID)
    if eloc == "INVTYPE_2HWEAPON" and GetInventoryItemLink("player", 17) then
      ClearCursor(); PickupInventoryItem(17); PutItemInBackpack()
      ClearCursor()
    end
  end

  ClearCursor()
  if C_Container and C_Container.PickupContainerItem then
    C_Container.PickupContainerItem(data.bag, data.slot)
  else
    PickupContainerItem(data.bag, data.slot)
  end
  PickupInventoryItem(slotID)
  ClearCursor()
  flyout:Hide()
end

local function makeFlyoutButton(i)
  local bf = flyout.buttonFrame
  local b = CreateFrame("Button", "NE_EquipFlyoutButton" .. i, bf, "ItemButtonTemplate")
  b:SetSize(EFITEM_W, EFITEM_H)
  if b.icon then b.icon:SetAllPoints(b) end
  local nt = b:GetNormalTexture()
  if nt then nt:SetTexture(nil); nt:Hide() end
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", equipItem)
  b:SetScript("OnDragStart", function(self)
    if self._data then
      if C_Container and C_Container.PickupContainerItem then C_Container.PickupContainerItem(self._data.bag, self._data.slot)
      else PickupContainerItem(self._data.bag, self._data.slot) end
    end
  end)
  b:SetScript("OnEnter", function(self)
    if not self._data then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetBagItem(self._data.bag, self._data.slot)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return b
end

local function buildFlyout()
  if flyout then return flyout end
  local parent = CP.frame or UIParent
  flyout = CreateFrame("Frame", "NE_EquipmentFlyout", parent)
  flyout:SetSize(43, 43)
  flyout:SetFrameStrata("HIGH")
  flyout:SetToplevel(true)
  flyout:Hide()
  flyout.buttons = {}

  local bf = CreateFrame("Frame", "NE_EquipmentFlyoutButtons", flyout)
  bf:EnableMouse(true)
  bf:SetClampedToScreen(true)
  -- Simple backdrop so the grid reads as a panel.
  if bf.SetBackdrop then
    bf:SetBackdrop({
      bgFile = "Interface\\Buttons\\WHITE8x8",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = false, edgeSize = 14,
      insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bf:SetBackdropColor(0, 0, 0, 0.85)
    bf:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end
  flyout.buttonFrame = bf

  -- Auto-hide when the mouse leaves the slot + arrow + flyout for a grace period.
  flyout:SetScript("OnUpdate", function(self, elapsed)
    local over = self:IsMouseOver() or self.buttonFrame:IsMouseOver()
      or (self._slotBtn and self._slotBtn:IsMouseOver())
      or (self._arrow and self._arrow:IsMouseOver())
    if over then self._leaveT = 0
    else
      self._leaveT = (self._leaveT or 0) + elapsed
      if self._leaveT > 0.25 then self:Hide() end
    end
  end)
  flyout:SetScript("OnHide", function(self)
    self._leaveT = 0
    if self._arrow and self._arrow._closedFacing then setArrowFacing(self._arrow, self._arrow._closedFacing) end
    self._slotID, self._slotBtn, self._arrow = nil, nil, nil
  end)
  return flyout
end

local function showFlyout(slotBtn, arrow)
  buildFlyout()
  local slotID = slotBtn:GetID()
  local items = itemsForSlot(slotID)
  if #items == 0 then flyout:Hide(); return end

  flyout._slotID = slotID
  flyout._slotBtn = slotBtn
  flyout._arrow = arrow
  flyout._leaveT = 0

  local bf = flyout.buttonFrame
  local n = #items
  local rows = math.ceil(n / ITEMS_PER_ROW)
  local perRow = math.min(n, ITEMS_PER_ROW)

  local rel = arrow or slotBtn
  flyout:ClearAllPoints()
  flyout:SetFrameLevel(slotBtn:GetFrameLevel() + 5)
  flyout:SetPoint("TOPLEFT", slotBtn, "TOPLEFT", -BORDER, BORDER)
  bf:ClearAllPoints()
  if VERTICAL_FLYOUTS[slotID] then
    bf:SetPoint("TOPLEFT", rel, "BOTTOMLEFT", 0, 0)
  else
    bf:SetPoint("TOPLEFT", rel, "TOPRIGHT", 0, -3)
  end
  bf:SetFrameLevel(flyout:GetFrameLevel() + 1)

  if arrow and arrow._openFacing then setArrowFacing(arrow, arrow._openFacing) end
  bf:SetWidth((perRow * EFITEM_W) + ((perRow - 1) * EFITEM_XOFF) + BORDER * 2 + 6)
  bf:SetHeight(EFITEM_H + ((rows - 1) * (EFITEM_H - EFITEM_YOFF)) + BORDER * 2 + 6)

  for i = #flyout.buttons + 1, n do flyout.buttons[i] = makeFlyoutButton(i) end
  for i = 1, #flyout.buttons do
    local b = flyout.buttons[i]
    if i <= n then
      local data = items[i]
      b._data = data
      if SetItemButtonTexture then SetItemButtonTexture(b, data.texture) elseif b.icon then b.icon:SetTexture(data.texture) end
      if SetItemButtonCount then SetItemButtonCount(b, data.count) end
      if SetItemButtonQuality then SetItemButtonQuality(b, data.quality, data.itemID) end
      b:ClearAllPoints()
      local col = (i - 1) % ITEMS_PER_ROW
      local row = math.floor((i - 1) / ITEMS_PER_ROW)
      b:SetPoint("TOPLEFT", bf, "TOPLEFT",
        BORDER + 3 + col * (EFITEM_W + EFITEM_XOFF),
        -BORDER - 3 - row * (EFITEM_H - EFITEM_YOFF))
      b:Show()
    else
      b:Hide()
    end
  end
  flyout:Show()
end

-- ----------------------------------------------------------------------------
-- Per-slot arrow buttons.
-- ----------------------------------------------------------------------------
local function attachArrow(slotBtn)
  if slotBtn._neFlyoutArrow then return slotBtn._neFlyoutArrow end
  local vertical = VERTICAL_FLYOUTS[slotBtn:GetID()] and true or false

  local arrow = CreateFrame("Button", nil, slotBtn)
  arrow._vertical = vertical
  arrow._closedFacing = vertical and "down" or "right"
  arrow._openFacing   = vertical and "up"   or "left"

  if vertical then
    arrow:SetSize(38, 16)
    arrow:SetPoint("TOP", slotBtn, "BOTTOM", 0, 4)
  else
    arrow:SetSize(16, 38)
    arrow:SetPoint("LEFT", slotBtn, "RIGHT", -8, 0)
  end
  -- SetNormalTexture/SetHighlightTexture take a PATH on 3.3.5.
  arrow:SetNormalTexture(ARROW_TEX)
  arrow:SetHighlightTexture(ARROW_TEX)
  arrow:SetFrameLevel((slotBtn:GetFrameLevel() or 1) + 2)
  setArrowFacing(arrow, arrow._closedFacing)
  arrow:Hide()

  arrow:SetScript("OnClick", function(self)
    if flyout and flyout:IsShown() and flyout._slotBtn == slotBtn then
      flyout:Hide()
    else
      showFlyout(slotBtn, self)
    end
  end)

  slotBtn._neFlyoutArrow = arrow
  return arrow
end

local function wireAllSlots()
  for _, name in ipairs(SLOT_NAMES) do
    local s = _G[name]
    if s and not s._neFlyoutWired then
      s._neFlyoutWired = true
      attachArrow(s)
    end
  end
end

-- Show arrows only on slots that have a usable swap candidate.
local function refreshArrows()
  for _, name in ipairs(SLOT_NAMES) do
    local s = _G[name]
    if s and s._neFlyoutArrow then
      if anyUsableForSlot(s:GetID()) then s._neFlyoutArrow:Show() else s._neFlyoutArrow:Hide() end
    end
  end
end

local function hideAllArrows()
  if flyout then flyout:Hide() end
  for _, name in ipairs(SLOT_NAMES) do
    local s = _G[name]
    if s and s._neFlyoutArrow then s._neFlyoutArrow:Hide() end
  end
end

CP.WireEquipmentFlyout       = wireAllSlots
CP.ShowEquipmentFlyoutArrows = refreshArrows
CP.HideEquipmentFlyoutArrows = hideAllArrows

local function onEquipTab()
  return CP._activeSidebar == 3 and CP.frame and CP.frame:IsShown()
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("BAG_UPDATE")
boot:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
boot:SetScript("OnEvent", function(_, event)
  if NE.modules and NE.modules.IsBooted and not NE.modules.IsBooted("character") then return end
  if event == "PLAYER_LOGIN" then
    wireAllSlots()
    if CP.frame and CP.frame.HookScript then
      CP.frame:HookScript("OnHide", hideAllArrows)
    end
  else
    if onEquipTab() then refreshArrows() end
  end
end)
