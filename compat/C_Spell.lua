-- DragonUI_NewEra/compat/C_Spell.lua
-- Ensures the C_Spell.* subset NewEra v1 uses exists.
--
-- DOWNPORT: Classic 1.15 namespaced spell queries under C_Spell. 3.3.5a uses
-- top-level GetSpellInfo / GetSpellTexture / GetSpellCooldown and has NO concept of
-- per-spell power-cost tables. v1 references (all source-guarded):
--   C_Spell.GetSpellDescription, C_Spell.GetSpellPowerCost,
--   C_Spell.GetSpellSubtext (via Core), texture/cooldown helpers.
-- If ClassicAPI built C_Spell (richer, scan-tooltip backed) we leave it and fill gaps.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local compat = NE.compat

C_Spell = C_Spell or {}
local C = C_Spell

-- GetSpellSubtext(spellID) -> rank string  ("Rank N"). 3.3.5: second return of
-- GetSpellInfo. (Also exposed as a global on 3.3.5; prefer it if present.)
if not C.GetSpellSubtext then
    function C.GetSpellSubtext(spellID)
        if not spellID then return nil end
        if type(GetSpellSubtext) == "function" then
            return GetSpellSubtext(spellID)
        end
        local _, rank = GetSpellInfo(spellID)
        return rank
    end
end

-- GetSpellTexture(spellID) -> iconID, originalIconID  (retail returns two; we mirror).
if not C.GetSpellTexture then
    function C.GetSpellTexture(spellID)
        if not spellID then return nil end
        local icon
        if type(GetSpellTexture) == "function" then
            icon = GetSpellTexture(spellID)
        end
        if not icon then
            icon = select(3, GetSpellInfo(spellID))
        end
        return icon, icon
    end
end

-- GetSpellCooldown(spellID) -> table { startTime, duration, isEnabled, modRate }
-- (retail shape). 3.3.5 global returns positional start, duration, enabled.
if not C.GetSpellCooldown then
    function C.GetSpellCooldown(spellID)
        local start, duration, enabled = GetSpellCooldown(spellID)
        if start == nil then return nil end
        return { startTime = start, duration = duration, isEnabled = enabled, modRate = 1 }
    end
end

-- GetSpellDescription(spellID) -> string : scrape the spell tooltip's last line.
-- 3.3.5 has no API for this; use our shared scan tooltip.
if not C.GetSpellDescription then
    function C.GetSpellDescription(spellID)
        if not spellID then return nil end
        local tip = compat.scanTip
        if not tip then return nil end
        tip:ClearLines()
        tip:SetHyperlink("spell:" .. spellID)
        local n = tip:NumLines()
        if n and n > 0 then
            return compat.ScanTipLine(n)
        end
        return nil
    end
end

-- GetSpellPowerCost(spellID) -> array of { type=, cost=, name=, ... }
-- 3.3.5 has NO per-spell power-cost API. NewEra reads costInfo.type / costInfo.cost
-- and matches against a power-bar's powerType. We cannot answer accurately, so return
-- an empty list (the source already does `... or {}` and the pairs() loop no-ops).
-- Recorded as a stub.
if not C.GetSpellPowerCost then
    function C.GetSpellPowerCost(spellID)
        return {}
    end
    compat.RecordStub("C_Spell.GetSpellPowerCost",
        "3.3.5 has no per-spell power-cost API; returns empty list (cost overlay shows nothing)")
end

-- GetSpellInfo wrapper (retail returns a table). Provide for completeness; v1 mostly
-- uses the global GetSpellInfo directly, but Core helpers may call the namespaced one.
if not C.GetSpellInfo then
    function C.GetSpellInfo(spellID)
        local name, rank, icon, _, _, _, castTime, minRange, maxRange = GetSpellInfo(spellID)
        if not name then return nil end
        return {
            name = name, rank = rank, iconID = icon, originalIconID = icon,
            castTime = castTime, minRange = minRange, maxRange = maxRange, spellID = spellID,
        }
    end
end

NE.compat.spell = true
