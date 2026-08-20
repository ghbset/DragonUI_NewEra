-- DragonUI_NewEra/modules/merchant/SellAllJunk.lua — retail's one-click sell-all-junk button.
--
-- DOWNPORT of NewEra/MerchantFrame/SellAllJunk.lua. Retail's MerchantSellAllJunkButton calls
-- C_MerchantFrame.SellAllJunkItems and reads C_MerchantFrame.GetNumJunkItems for its enabled state;
-- neither exists on Era OR on 3.3.5a, so both are a bag walk — the 1.15 source's approach, with
-- three changes forced by this client:
--
--   * ITEM FACTS come from GetContainerItemLink + GetItemInfo, not C_Container.GetContainerItemInfo.
--     !!!ClassicAPI's GetContainerItemInfo hardcodes `hasNoValue = false` (so a worthless gray would
--     be counted and repeatedly "sold") AND runs a hidden-tooltip scan per slot, which is far too
--     expensive to do over every bag on every BAG_UPDATE. GetItemInfo's 11th return is the vendor
--     price on 3.3.5a: 0/nil means the vendor will not take it.
--   * Quest items are skipped. On this client a gray quest item is sellable by the API but losing it
--     is unrecoverable, so it is excluded the way DragonUI's own scrap-sell does.
--   * StaticPopup_ShowCustomGenericConfirmation is a retail/Era helper with no 3.3.5a counterpart,
--     so the confirmation is a normal StaticPopupDialogs entry. The popup is not optional: this is
--     an irreversible mass-liquidation behind one click.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.merchant = NE.merchant or {}
local Merch = NE.merchant
local L = NE.L

local POPUP = "DRAGONUI_NEWERA_SELL_ALL_JUNK"

-- A bag flagged ExcludeJunkSell has its grays protected. 3.3.5a has no bag flags, so this is always
-- false today; the seam is kept because it is the bags module's to fill if it ever grows the flag.
local function bagExcluded(bag)
  local cf = NE.containerframe
  return (cf and cf.IsBagExcludedFromJunk and cf.IsBagExcludedFromJunk(bag)) or false
end

-- Poor quality, vendor takes it, and not a quest item. Returns the stack count when it qualifies.
local function junkAt(bag, slot)
  local link = GetContainerItemLink and GetContainerItemLink(bag, slot)
  if not link then return nil end
  local _, _, quality, _, _, itemType, _, _, _, _, sellPrice = GetItemInfo(link)
  if quality ~= 0 then return nil end
  if not sellPrice or sellPrice <= 0 then return nil end
  if itemType == "Quest" then return nil end
  return true
end

local function forEachBagSlot(fn)
  for bag = 0, (NUM_BAG_SLOTS or 4) do
    if not bagExcluded(bag) then
      local slots = (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
      for slot = 1, slots do
        fn(bag, slot)
      end
    end
  end
end

local function countJunkItems()
  local n = 0
  forEachBagSlot(function(bag, slot)
    if junkAt(bag, slot) then n = n + 1 end
  end)
  return n
end

local function sellAllJunk()
  -- Only act at an open vendor AND on the merchant tab (not buyback) — retail's button is only
  -- enabled in that state too.
  if not MerchantFrame or not MerchantFrame:IsShown() then return end
  if MerchantFrame.selectedTab ~= 1 then return end

  local sold = 0
  forEachBagSlot(function(bag, slot)
    if junkAt(bag, slot) then
      -- UseContainerItem while a merchant is open SELLS the item (the engine plays the coin sound
      -- per item). Per-item pcall: one locked or mid-flight slot must not abort the sweep and
      -- leave the rest of the grays behind.
      if pcall(UseContainerItem, bag, slot) then sold = sold + 1 end
    end
  end)

  -- Say what happened. Retail leaves this to the per-item coin sound, but this sweep is deliberately
  -- stricter than "everything grey" — it skips quest items and anything the vendor will not pay for
  -- — so a run that sells four of your six greys is correct and looks like nothing happened without
  -- a line saying so. Same string and same convention as the combined bag's own junk sell
  -- (modules/bags/CombinedBag.lua), so the two report identically.
  if sold > 0 and DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage(string.format(L["Sold %d junk item(s)."], sold))
  end
end

-- ----------------------------------------------------------------------------
-- Button
-- ----------------------------------------------------------------------------

local refreshPending
local function refreshState()
  local btn = _G.NE_MerchantSellAllJunkButton
  if not btn then return end
  -- BAG_UPDATE fires in bursts on every loot and every bag move, all session — but this button is
  -- only on screen while a vendor is open. Skip the walk away from a vendor, and coalesce a burst
  -- into one next-frame count.
  if not btn:IsVisible() then return end
  if refreshPending then return end
  refreshPending = true
  C_Timer.After(0, function()
    refreshPending = false
    if not btn:IsVisible() then return end
    local has = countJunkItems() > 0
    if btn.Icon then SetDesaturation(btn.Icon, not has) end
    if has then btn:Enable() else btn:Disable() end
  end)
end

Merch.RefreshSellJunkState = refreshState

local function onClick(self)
  GameTooltip:Hide()
  StaticPopup_Show(POPUP)
end

local function onEnter(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText(L["Sell all junk items"])
  GameTooltip:Show()
end

function Merch.BuildSellAllJunk()
  if _G.NE_MerchantSellAllJunkButton then return end   -- idempotent across /reload
  if not _G.MerchantFrame then return end

  StaticPopupDialogs[POPUP] = StaticPopupDialogs[POPUP] or {
    text         = L["Sell all of your junk (gray) items?"],
    button1      = YES,
    button2      = NO,
    OnAccept     = sellAllJunk,
    timeout      = 0,
    whileDead    = 1,
    hideOnEscape = 1,
  }

  local btn = CreateFrame("Button", "NE_MerchantSellAllJunkButton", _G.MerchantFrame)
  btn:SetSize(36, 36)
  -- Retail's static XML position. postRepairButtons (MerchantFrame.lua) moves it on every update to
  -- whichever of retail's three branches applies, so this only covers the frame's first paint.
  btn:SetPoint("BOTTOMRIGHT", _G.MerchantFrame, "BOTTOMLEFT", 160, 33)

  local icon = btn:CreateTexture(nil, "BORDER")
  NE.tex.SetAtlas(icon, "spellicon-256x256-selljunk", false)
  -- Retail: useAtlasSize=false, no Size, no Anchor -> fill the parent (36x36). The recess BG added
  -- by MerchantFrame.lua's addRetailSlotBgs masks the chrome behind the icon's feathered edges.
  icon:SetAllPoints(btn)
  btn.Icon = icon

  btn:SetPushedTexture("Interface\\Buttons\\UI-Quickslot-Depress")
  btn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
  local hl = btn:GetHighlightTexture()
  if hl then hl:SetBlendMode("ADD") end

  btn:SetScript("OnClick", onClick)
  btn:SetScript("OnEnter", onEnter)
  btn:SetScript("OnLeave", function() GameTooltip:Hide() end)

  -- Refresh the enabled/desaturated state on merchant open + bag changes. Retail drives this from
  -- MerchantFrame_Update; BAG_UPDATE is hooked as well so the state stays right when junk moves
  -- while the window is already open (including as this button's own sweep empties the bags).
  btn:RegisterEvent("MERCHANT_SHOW")
  btn:RegisterEvent("MERCHANT_UPDATE")
  btn:RegisterEvent("BAG_UPDATE")
  btn:SetScript("OnEvent", refreshState)
  -- MERCHANT_SHOW can fire before MerchantFrame is actually shown (refreshState skips while
  -- invisible) — OnShow is the reliable "we are at a vendor now" recount.
  btn:SetScript("OnShow", refreshState)
  refreshState()
end
