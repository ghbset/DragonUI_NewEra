-- DragonUI_NewEra/compat/C_Item.lua
-- Ensures the C_Item.* subset NewEra v1 uses exists.
--
-- DOWNPORT: Classic 1.15 namespaced item queries under C_Item. 3.3.5a uses top-level
-- GetItemInfo / GetItemSpell / GetItemQualityColor. v1 references:
--   C_Item.GetItemInfo, C_Item.GetItemSpell, C_Item.GetItemQualityColor
-- (all guarded by the source with `if C_Item and C_Item.Fn`). We forward to the
-- 3.3.5 globals. If ClassicAPI built C_Item we leave its richer methods and just fill
-- any of these three that are missing.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

C_Item = C_Item or {}
local C = C_Item

-- GetItemInfo(item) : identical signature/returns on 3.3.5 and Classic (name, link,
-- quality, ilvl, reqLevel, class, subclass, maxStack, equipLoc, texture, sellPrice).
if not C.GetItemInfo then
    C.GetItemInfo = GetItemInfo
end

-- GetItemSpell(item) -> spellName, spellID  (same on 3.3.5).
if not C.GetItemSpell then
    C.GetItemSpell = GetItemSpell
end

-- GetItemQualityColor(quality) -> r, g, b, hex  (same on 3.3.5).
if not C.GetItemQualityColor then
    if type(GetItemQualityColor) == "function" then
        C.GetItemQualityColor = GetItemQualityColor
    else
        -- Fallback from the global ITEM_QUALITY_COLORS table (always present on 3.3.5).
        function C.GetItemQualityColor(quality)
            local q = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
            if q then
                return q.r, q.g, q.b, q.hex
            end
            return 1, 1, 1, "|cffffffff"
        end
    end
end

-- GetItemIconByID(itemID) -> texture  (handy; v1 doesn't strictly need but ItemGrid
-- icons may). Forward to 3.3.5 GetItemIcon when present.
if not C.GetItemIconByID and type(GetItemIcon) == "function" then
    C.GetItemIconByID = GetItemIcon
end

NE.compat.item = true
