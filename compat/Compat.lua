-- DragonUI_NewEra/compat/Compat.lua
-- Modern-API shim LOADER. Loads first in the compat/ block (after bootstrap).
--
-- Purpose: detect !!!ClassicAPI, expose NE.compat capability booleans, and own a
-- tiny set of shared helpers (NE.compat.driver = the single OnUpdate timer frame,
-- NE.compat.scanTip = a scan tooltip) that the per-symbol shims reuse. This file
-- does NOT define C_* globals itself — each sibling file (C_Timer.lua, C_Item.lua,
-- ...) ensures its own global, only when missing, in TOC order.
--
-- DOWNPORT: NewEra (Classic 1.15) assumes all C_* namespaces exist natively. On
-- 3.3.5a most do not. We vendor minimal fallbacks and prefer ClassicAPI's richer
-- versions when that library is loaded (OptionalDep). NO hard dependency.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

-- ---------------------------------------------------------------------------
-- ClassicAPI detection. bootstrap.lua already set NE.hasClassicAPI from the
-- "!!!ClassicAPI" load name; re-evaluate here in case load order surprised us.
-- ---------------------------------------------------------------------------
local hasClassicAPI = _G["!!!ClassicAPI"] ~= nil
NE.hasClassicAPI = hasClassicAPI

-- ---------------------------------------------------------------------------
-- compat namespace + capability table. Each shim flips its bool true once it has
-- guaranteed its symbols. Consumers may read NE.compat.<cap> to branch, but the
-- v1 contract is simply: after compat/ loads, the modern globals exist.
-- ---------------------------------------------------------------------------
NE.compat = NE.compat or {}
local compat = NE.compat
compat.classicAPI = hasClassicAPI

-- Capability booleans (set by sibling files; default false here so reads are safe
-- even if a file failed to load).
compat.timer     = compat.timer     or false   -- C_Timer.After/NewTimer/NewTicker
compat.mixin     = compat.mixin     or false   -- Mixin/CreateFromMixins/CreateAndInitFromMixin
compat.texture   = compat.texture   or false   -- C_Texture.GetAtlasInfo/GetAtlasExists
compat.container = compat.container or false   -- C_Container.*
compat.item      = compat.item      or false   -- C_Item.*
compat.spell     = compat.spell     or false   -- C_Spell.*
compat.map       = compat.map       or false   -- C_Map.* (best-effort; some stubs)

-- Record of symbols we could only STUB (3.3.5 genuinely can't answer). Sibling
-- files append { sym=, why= }; COVERAGE.md documents these. Lets QA enumerate.
compat.stubs = compat.stubs or {}
function compat.RecordStub(sym, why)
    compat.stubs[#compat.stubs + 1] = { sym = sym, why = why }
end

-- ---------------------------------------------------------------------------
-- Shared OnUpdate timer driver. C_Timer (when we have to vendor it) and any other
-- shim needing delayed/repeating callbacks pulls from here, so we run exactly ONE
-- OnUpdate frame for the whole compat layer instead of one per call site.
-- API: NE.compat.driver.Add(delay, callback, iterations) -> handle
--      iterations: nil/0 = run once; >0 = run that many times; -1 = forever (ticker)
--      handle:Cancel(), handle:IsCancelled()
-- ---------------------------------------------------------------------------
local function buildDriver()
    local frame = CreateFrame("Frame", "DragonUI_NewEra_TimerDriver")
    local active = {}          -- set of live timer records
    local elapsedAccum = 0     -- not strictly needed; we store absolute targets

    local handleMethods = {}
    handleMethods.__index = handleMethods
    function handleMethods:Cancel()
        local rec = self._rec
        if rec then
            rec.cancelled = true
            active[rec] = nil
            self._rec = nil
        end
    end
    function handleMethods:IsCancelled()
        return self._rec == nil or self._rec.cancelled == true
    end

    local function Add(delay, callback, iterations)
        if type(delay) ~= "number" then delay = 0 end
        if delay < 0 then delay = 0 end
        local rec = {
            remaining   = delay,
            interval    = delay,
            callback    = callback,
            iterations  = iterations or 0,   -- 0 => single fire
            ticker      = (iterations ~= nil and iterations ~= 0),
            cancelled   = false,
        }
        local handle = setmetatable({ _rec = rec }, handleMethods)
        rec.handle = handle
        active[rec] = true
        frame:Show()
        return handle
    end

    frame:SetScript("OnUpdate", function(self, dt)
        local any = false
        for rec in pairs(active) do
            any = true
            if rec.cancelled then
                active[rec] = nil
            else
                rec.remaining = rec.remaining - dt
                if rec.remaining <= 0 then
                    -- fire
                    local cb = rec.callback
                    if rec.ticker then
                        -- ticker passes its handle, like retail C_Timer.NewTicker
                        if cb then
                            local ok = pcall(cb, rec.handle)
                            -- ignore errors so one bad callback can't kill the driver
                            local _ = ok
                        end
                        if rec.iterations and rec.iterations > 0 then
                            rec.iterations = rec.iterations - 1
                            if rec.iterations <= 0 then
                                rec.cancelled = true
                                active[rec] = nil
                            else
                                rec.remaining = rec.remaining + rec.interval
                            end
                        else
                            -- forever
                            rec.remaining = rec.remaining + rec.interval
                        end
                    else
                        -- one-shot: remove BEFORE calling so a re-entrant Add is safe
                        active[rec] = nil
                        rec.cancelled = true
                        if cb then pcall(cb) end
                    end
                end
            end
        end
        if not any then self:Hide() end
    end)
    frame:Hide()

    return { frame = frame, Add = Add }
end

if not compat.driver then
    compat.driver = buildDriver()
end

-- ---------------------------------------------------------------------------
-- Shared scan tooltip. ClassicAPI builds "CAPI_ScanTooltip"; we build our own so
-- the C_Spell/C_Item fallbacks don't depend on ClassicAPI's private frame. Named,
-- owned by WorldFrame, anchored off-screen. (3.3.5: GameTooltip scan pattern.)
-- ---------------------------------------------------------------------------
if not compat.scanTip then
    local tip = CreateFrame("GameTooltip", "DragonUI_NewEra_ScanTooltip", UIParent, "GameTooltipTemplate")
    tip:SetOwner(WorldFrame, "ANCHOR_NONE")
    compat.scanTip = tip
end
-- Helper: read line N's left text (1-based) from the scan tooltip after a Set*.
function compat.ScanTipLine(n)
    local fs = _G["DragonUI_NewEra_ScanTooltipTextLeft" .. n]
    return fs and fs:GetText() or nil
end

-- print nothing on success (per contract).
