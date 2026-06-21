-- DragonUI_NewEra/compat/C_Timer.lua
-- Ensures C_Timer.After / NewTimer / NewTicker exist.
--
-- DOWNPORT: 3.3.5a has no native C_Timer. ClassicAPI provides one via an
-- AnimationGroup pool; if it (or any other lib) already defined C_Timer.After we
-- leave it. Otherwise we vendor an implementation backed by the single shared
-- OnUpdate driver frame in NE.compat.driver (Compat.lua) — one frame for the whole
-- addon, no per-call frame churn.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local driver = NE.compat.driver  -- { Add(delay, cb, iterations) -> handle }

C_Timer = C_Timer or {}

-- C_Timer.After(seconds, callback) : fire callback once after `seconds`.
if not C_Timer.After then
    function C_Timer.After(seconds, callback)
        driver.Add(seconds, callback, 0)  -- 0 iterations => single fire
    end
end

-- C_Timer.NewTimer(seconds, callback) : like After, but returns a cancellable
-- handle ( :Cancel(), :IsCancelled() ). Callback receives the handle.
if not C_Timer.NewTimer then
    function C_Timer.NewTimer(seconds, callback)
        return driver.Add(seconds, callback, 1)  -- exactly one fire, cancellable
    end
end

-- C_Timer.NewTicker(seconds, callback[, iterations]) : repeat every `seconds`.
-- iterations nil => forever; otherwise fire that many times. Returns a handle.
if not C_Timer.NewTicker then
    function C_Timer.NewTicker(seconds, callback, iterations)
        -- driver: iterations -1 => forever, >0 => that many
        return driver.Add(seconds, callback, iterations and iterations > 0 and iterations or -1)
    end
end

NE.compat.timer = true
