-- DragonUI_NewEra/compat/C_Container.lua
-- Ensures C_Container.* exists, mapping to 3.3.5 GetContainer* globals.
--
-- DOWNPORT: Classic 1.15 namespaced the container API under C_Container and changed
-- GetContainerItemInfo to return a TABLE. 3.3.5a has top-level functions returning
-- POSITIONAL values. This shim adapts positional -> table for GetContainerItemInfo
-- (the fields NewEra v1 reads: iconFileID, stackCount, isLocked, quality, hyperlink,
-- itemID) and forwards the rest. If ClassicAPI already built C_Container (same table
-- return shape) we leave each method it defined and only fill gaps.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

C_Container = C_Container or {}
local C = C_Container

-- Simple forwards (positional in == positional out on 3.3.5; same on Classic API).
if not C.GetContainerNumSlots then
    C.GetContainerNumSlots = GetContainerNumSlots
end
if not C.GetContainerItemLink then
    C.GetContainerItemLink = GetContainerItemLink
end
if not C.GetContainerNumFreeSlots then
    C.GetContainerNumFreeSlots = GetContainerNumFreeSlots
end
if not C.UseContainerItem then
    C.UseContainerItem = UseContainerItem
end
if not C.PickupContainerItem then
    C.PickupContainerItem = PickupContainerItem
end
if not C.GetContainerItemID then
    C.GetContainerItemID = GetContainerItemID  -- present on 3.3.5a TrinityCore client
end
if not C.GetContainerItemCooldown then
    C.GetContainerItemCooldown = GetContainerItemCooldown
end

-- GetContainerItemInfo(bag, slot) -> table | nil  (the load-bearing adapter).
-- 3.3.5 returns: texture, itemCount, locked, quality, readable, lootable, link.
if not C.GetContainerItemInfo then
    function C.GetContainerItemInfo(bag, slot)
        local texture, itemCount, locked, quality, readable, lootable, link =
            GetContainerItemInfo(bag, slot)
        if texture == nil then return nil end
        local itemID
        if C.GetContainerItemID then
            itemID = C.GetContainerItemID(bag, slot)
        end
        return {
            iconFileID  = texture,
            stackCount  = itemCount,
            isLocked    = locked,
            quality     = quality,
            isReadable  = readable,
            hasLoot     = lootable,
            hyperlink   = link,
            itemID      = itemID,
            isFiltered  = false,
            hasNoValue  = false,
            isBound     = nil,
        }
    end
end

-- GetContainerItemQuestInfo(bag, slot) -> table  (retail shape).
-- 3.3.5: GetContainerItemQuestInfo returns isQuestItem, questId, isActive (positional).
-- v1 only reads .isQuestItem / .questId, so adapt positional -> table; if the global
-- is absent, return a safe empty table (no quest item) and record the partial.
if not C.GetContainerItemQuestInfo then
    if type(GetContainerItemQuestInfo) == "function" then
        function C.GetContainerItemQuestInfo(bag, slot)
            local isQuestItem, questId, isActive = GetContainerItemQuestInfo(bag, slot)
            return {
                isQuestItem = isQuestItem,
                questID     = questId,
                questId     = questId,        -- tolerate both casings
                isActive    = isActive,
            }
        end
    else
        function C.GetContainerItemQuestInfo(bag, slot)
            return { isQuestItem = nil, questID = nil, questId = nil, isActive = nil }
        end
        NE.compat.RecordStub("C_Container.GetContainerItemQuestInfo",
            "no native GetContainerItemQuestInfo on this client; returns empty (no quest item)")
    end
end

NE.compat.container = true
