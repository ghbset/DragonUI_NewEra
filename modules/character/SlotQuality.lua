-- DragonUI_NewEra/modules/character/SlotQuality.lua — item-quality border coloring on the 19 PaperDoll
-- equipment slots. Ported from NewEra/CharacterPanel/SlotQuality.lua.
--
-- WHY: 3.3.5a's PaperDollFrame never calls SetItemButtonQuality on the equipped slots, so their
-- IconBorder stays uncolored. We drive the call ourselves on equipment change + login; Core/ItemButton's
-- hooksecurefunc on SetItemButtonQuality then paints the retail-exact quality border (it resolves each
-- slot's IconBorder by .IconBorder or $parentIconBorder). PaperDollItemSlotButtonTemplate inherits
-- ItemButtonTemplate, so each slot carries the IconBorder texture the hook needs.
--
-- DOWNPORT vs NewEra:
--   * Quality read: NewEra used GetItemInfo(itemLink) (pos 3). On 3.3.5a GetInventoryItemQuality(unit,
--     slotID) returns the quality directly and is cache-independent (no nil while uncached), so we use
--     it as the primary source per the brief, with GetItemInfo as a fallback for the link.
--   * Family gate: NE.modules.IsEnabled("character") (foundation module id).
-- Triggered on PLAYER_EQUIPMENT_CHANGED (per-slot) + PLAYER_ENTERING_WORLD / PLAYER_LOGIN (full pass).

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE = "character"

local function log(msg) if CP._log then CP._log(msg) elseif NE.Log then NE.Log("CHARPANEL", msg) end end

-- The 19 character equipment slots (Ammo excluded — different button type). Order matches the
-- foundation's reparent list.
local SLOTS = {
  "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot",
  "CharacterBackSlot", "CharacterChestSlot", "CharacterShirtSlot",
  "CharacterTabardSlot", "CharacterWristSlot",
  "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
  "CharacterFinger0Slot", "CharacterFinger1Slot",
  "CharacterTrinket0Slot", "CharacterTrinket1Slot",
  "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

-- Color one slot's border by its equipped item quality (or hide it if empty).
local function updateSlotQuality(slot)
  if not slot or not slot.GetID then return end
  local id = slot:GetID()
  if not id or id == 0 then return end

  -- Primary: GetInventoryItemQuality (cache-independent on 3.3.5a). pcall — some private cores return
  -- nil/error for empty slots.
  local quality
  local ok, q = pcall(GetInventoryItemQuality, "player", id)
  if ok then quality = q end

  local itemLink = GetInventoryItemLink("player", id)
  -- Fallback: derive quality from the link if the direct getter gave nothing but an item is present.
  if quality == nil and itemLink then
    local ok2, _, _, q2 = pcall(GetItemInfo, itemLink)
    if ok2 then quality = q2 end
  end

  -- Route through the global so Core/ItemButton's hook paints the retail-exact border. nil quality
  -- (empty slot) -> SetItemButtonQuality hides the border.
  if SetItemButtonQuality then
    pcall(SetItemButtonQuality, slot, quality, itemLink)
  elseif NE.itembutton and NE.itembutton.ApplyQuality then
    -- DOWNPORT: belt-and-suspenders if the global is somehow absent on a private core.
    pcall(NE.itembutton.ApplyQuality, slot, quality)
  end
end

local function updateAllSlots()
  for _, name in ipairs(SLOTS) do
    updateSlotQuality(_G[name])
  end
end

-- CONTRACT surface (brief).
CP.UpdateAllSlots = updateAllSlots

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
boot:SetScript("OnEvent", function(_, event, slotID)
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled(MODULE) then return end
  if event == "PLAYER_EQUIPMENT_CHANGED" and slotID then
    -- Per-slot update is cheaper than a full walk.
    for _, name in ipairs(SLOTS) do
      local slot = _G[name]
      if slot and slot.GetID and slot:GetID() == slotID then
        updateSlotQuality(slot)
        return
      end
    end
    return
  end
  updateAllSlots()
end)
