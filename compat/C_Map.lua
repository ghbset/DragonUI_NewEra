-- DragonUI_NewEra/compat/C_Map.lua
-- Ensures the C_Map.* subset exists, best-effort.
--
-- DOWNPORT: Classic 1.15's C_Map is a uiMapID-based world-map model that 3.3.5a
-- simply does not have (3.3.5 uses SetMapToCurrentZone / GetCurrentMapAreaID /
-- GetPlayerMapPosition with a totally different id space). The v1 modules
-- (CharacterPanel, Spellbook, Talents, QuestFrame, MerchantFrame, MailFrame) do NOT
-- call C_Map — it's referenced only by NewEra's WorldMap/Minimap/Quest map providers
-- which are out of scope for v1. CONTRACTS §1 still asks for a best-effort shim so
-- anything that incidentally probes C_Map gets safe nils rather than a nil-index
-- error. Every method here is a SAFE STUB and is recorded.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local compat = NE.compat

C_Map = C_Map or {}
local C = C_Map

-- GetBestMapForUnit(unit) -> uiMapID. No uiMapID space on 3.3.5; best-effort returns
-- the legacy current-zone area id (NOT a uiMapID — callers that compare against retail
-- ids will mismatch, which is fine: v1 never calls this). nil if unavailable.
if not C.GetBestMapForUnit then
    function C.GetBestMapForUnit(unit)
        if unit and unit ~= "player" then return nil end
        if type(GetCurrentMapAreaID) == "function" then
            -- ensure map is pointed at the player's zone without disturbing user view
            -- as little as possible; SetMapToCurrentZone is the 3.3.5 way.
            if type(SetMapToCurrentZone) == "function" then
                pcall(SetMapToCurrentZone)
            end
            local id = GetCurrentMapAreaID()
            return id
        end
        return nil
    end
    compat.RecordStub("C_Map.GetBestMapForUnit",
        "no uiMapID on 3.3.5; returns legacy GetCurrentMapAreaID (id space differs from retail)")
end

-- GetMapInfo(uiMapID) -> table { mapID, name, mapType, parentMapID }. 3.3.5 cannot
-- map a retail uiMapID; return nil. Recorded.
if not C.GetMapInfo then
    function C.GetMapInfo(uiMapID)
        return nil
    end
    compat.RecordStub("C_Map.GetMapInfo",
        "no uiMapID->map metadata on 3.3.5; returns nil")
end

-- GetPlayerMapPosition(uiMapID, unit) -> position table with :GetXY(). 3.3.5's
-- GetPlayerMapPosition returns positional x, y for the CURRENT map. We wrap it in a
-- minimal position object exposing GetXY() to match the retail return shape. The
-- uiMapID argument is ignored (we use whatever map is currently selected).
if not C.GetPlayerMapPosition then
    local posMethods = {}
    posMethods.__index = posMethods
    function posMethods:GetXY()
        return self.x, self.y
    end
    function C.GetPlayerMapPosition(uiMapID, unit)
        unit = unit or "player"
        if type(GetPlayerMapPosition) ~= "function" then return nil end
        local x, y = GetPlayerMapPosition(unit)
        if not x or (x == 0 and y == 0) then return nil end
        return setmetatable({ x = x, y = y }, posMethods)
    end
    compat.RecordStub("C_Map.GetPlayerMapPosition",
        "wraps legacy GetPlayerMapPosition; ignores uiMapID arg, uses current map")
end

NE.compat.map = true
