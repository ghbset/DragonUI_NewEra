-- DragonUI_NewEra/bootstrap.lua
-- Namespace + DragonUI handshake + SavedVariables. Loads before everything else.
--
-- CONVENTION (downport rule): every ported NewEra file begins with
--     local NE = DragonUI_NewEra
-- instead of NewEra's original `NE = NE or {}` global. This keeps NewEra's
-- pervasive `NE.*` references working with a one-line change per file, while
-- staying collision-safe (no global `NE` leak).

local ADDON = ...

DragonUI_NewEra = DragonUI_NewEra or {}
local NE = DragonUI_NewEra
NE.name    = ADDON
NE.version = "0.1.0-s0"

-- Hard dependency on the base HUD addon. The TOC `## Dependencies: DragonUI`
-- guarantees DragonUI's files have run by the time we parse.
NE.dragon = _G.DragonUI
if not NE.dragon then
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff5555DragonUI_NewEra|r requires DragonUI; not loading.")
    end
    NE.disabled = true
    return
end

-- Optional shim library. compat/ refines this and degrades gracefully if absent.
NE.hasClassicAPI = _G["!!!ClassicAPI"] ~= nil

-- Stable per-character key for per-char data inside the account-wide DB
-- (equipment sets, talent prefs). Mirrors NewEra's NE.CharKey(). Only valid
-- after PLAYER_LOGIN.
function NE.CharKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "")
end

-- Simple registry the QA harness reads: panels append { name=, frame=, open=, close= }.
NE.qa = NE.qa or { modules = {} }

-- SavedVariables. Our OWN db holds panel-internal per-char state ONLY
-- (equipment sets, talent prefs). Panel ENABLE flags and POSITIONS live in
-- DragonUI (DragonUIDB) via ModuleRegistry + MoversSystem for a unified UX.
local CURRENT_SCHEMA = 1
NE.migrations = NE.migrations or {}
NE.migrations[1] = function(db)
    db.equipmentSets = db.equipmentSets or {}   -- [charKey] = sets
    db.talents       = db.talents       or {}   -- [charKey] = talent prefs
end

local function applyMigrations(db)
    db.schema = db.schema or 0
    while db.schema < CURRENT_SCHEMA do
        local step = NE.migrations[db.schema + 1]
        if not step then break end
        step(db)
        db.schema = db.schema + 1
    end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("ADDON_LOADED")
boot:SetScript("OnEvent", function(self, _, name)
    if name ~= ADDON then return end
    DragonUI_NewEraDB = DragonUI_NewEraDB or {}
    applyMigrations(DragonUI_NewEraDB)
    NE.db = DragonUI_NewEraDB
    NE.ready = true
    if NE.OnReady then NE.OnReady() end   -- integration/Register.lua sets this
    self:UnregisterAllEvents()
end)
