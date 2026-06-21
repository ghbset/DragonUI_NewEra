-- DragonUI_NewEra/compat/Mixin.lua
-- Ensures Mixin / CreateFromMixins / CreateAndInitFromMixin exist.
--
-- DOWNPORT: 3.3.5a has no Mixin family. ClassicAPI provides it; if present we leave
-- it. Otherwise we define the trivial Blizzard-equivalent implementations. These are
-- pure-table helpers (no frame/API deps) so the fallback is safe to vendor verbatim.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local select = select
local pairs = pairs

-- Mixin(object, ...) : shallow-copy each mixin table's fields onto object.
if not Mixin then
    function Mixin(object, ...)
        for i = 1, select("#", ...) do
            local mixin = select(i, ...)
            if mixin then
                for k, v in pairs(mixin) do
                    object[k] = v
                end
            end
        end
        return object
    end
end

-- CreateFromMixins(...) : new table with the given mixins applied.
if not CreateFromMixins then
    function CreateFromMixins(...)
        return Mixin({}, ...)
    end
end

-- CreateAndInitFromMixin(mixin, ...) : create, then call obj:Init(...).
if not CreateAndInitFromMixin then
    function CreateAndInitFromMixin(mixin, ...)
        local object = CreateFromMixins(mixin)
        object:Init(...)
        return object
    end
end

NE.compat.mixin = true
