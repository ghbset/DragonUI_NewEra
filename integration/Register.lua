-- DragonUI_NewEra/integration/Register.lua
-- The single DragonUI handshake every NewEra panel module routes through.
--
-- Later-sprint panels NEVER touch DragonUI internals directly. They call
--   NE.RegisterPanel(spec)
-- and this file wires that spec into DragonUI's ModuleRegistry, MoversSystem,
-- and our own boot dispatcher + QA harness + options list. Every base-API call
-- is defensively guarded so a missing/renamed base symbol logs a warning instead
-- of erroring (load order between the parallel-built addon parts must never crash).
--
-- DOWNPORT: this whole file is new glue (no 1.15 NewEra counterpart); the 1.15
-- addon had its own settings UI, here we proxy into DragonUI's unified UX.

local NE = DragonUI_NewEra
if not NE then return end

-- ----------------------------------------------------------------------------
-- Small logging helper. Prefer DragonUI's :Print / :Error if present, else
-- fall back to DEFAULT_CHAT_FRAME so a missing base API still surfaces.
-- ----------------------------------------------------------------------------
local function warn(msg)
    local dragon = NE.dragon
    if dragon and type(dragon.Error) == "function" then
        -- DragonUI:Error(...) is a method (self-call).
        local ok = pcall(dragon.Error, dragon, "[NewEra] " .. msg)
        if ok then return end
    end
    if DEFAULT_CHAT_FRAME then
        DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r: " .. msg)
    end
end
NE._warn = NE._warn or warn

-- The ordered list the Options builder renders one toggle per panel from.
-- Each entry: { id, title, desc, refresh, order }. Kept here (not in Options.lua)
-- so it is populated even if DragonUI_Options never loads.
NE.optionPanels = NE.optionPanels or {}

-- ----------------------------------------------------------------------------
-- DB bootstrap. Panel ENABLE flags + the per-panel `enabled` toggles live in
-- DragonUI's profile (DragonUIDB) under profile.newera so the whole UX is
-- unified. Our own DragonUI_NewEraDB only holds per-char panel state.
-- ----------------------------------------------------------------------------
local function ensureProfile()
    local dragon = NE.dragon
    if not (dragon and dragon.db and dragon.db.profile) then
        return nil
    end
    local profile = dragon.db.profile
    if type(profile.newera) ~= "table" then
        profile.newera = { enabled = true }
    end
    if profile.newera.enabled == nil then
        profile.newera.enabled = true
    end
    if type(profile.newera.modules) ~= "table" then
        profile.newera.modules = {}
    end
    return profile.newera
end
NE.EnsureProfile = ensureProfile

-- Convenience: the newera config sub-table (may be nil pre-login).
function NE.Config()
    return ensureProfile()
end

-- ----------------------------------------------------------------------------
-- NE.OnReady — bootstrap.lua calls this once SavedVariables are loaded
-- (after ADDON_LOADED for our addon, i.e. DragonUI.db is already an AceDB).
-- ----------------------------------------------------------------------------
function NE.OnReady()
    local cfg = ensureProfile()
    if not cfg then
        warn("DragonUI.db.profile not available at OnReady; newera settings not initialised.")
        return
    end

    -- Re-run boot for any panel that registered BEFORE OnReady (load-order
    -- safety: a panel file may have called RegisterPanel before SavedVariables
    -- were ready, so its modules.Register entry now has a real default to read).
    for _, panel in ipairs(NE.optionPanels) do
        if cfg.modules[panel.id] == nil or type(cfg.modules[panel.id]) ~= "table" then
            cfg.modules[panel.id] = { enabled = true }
        end
    end
end

-- ----------------------------------------------------------------------------
-- NE.RegisterPanel(spec)
--   spec = { id, title, desc, frame, openFn, closeFn, defaultPoint, order }
--
-- The one helper every panel module calls. Wires the panel into:
--   (1) profile.newera.modules[id] = { enabled = true }   (default)
--   (2) NE.modules.Register  (our boot dispatcher, from Core agent)
--   (3) NE.dragon.ModuleRegistry:Register  (DragonUI's module list)
--   (4) NE.dragon.MoversSystem:RegisterMover  (drag-to-move the frame)
--   (5) NE.qa.modules  (the /dnetest harness)
--   (6) NE.optionPanels  (the "New Era" options tab)
-- Every step is independently guarded.
-- ----------------------------------------------------------------------------
function NE.RegisterPanel(spec)
    if type(spec) ~= "table" or not spec.id then
        warn("RegisterPanel called without a spec.id; ignored.")
        return
    end

    local id    = spec.id
    local title = spec.title or id
    local desc  = spec.desc or ""

    -- (1) DB default. Guarded: profile may not exist yet pre-login; the default
    -- is re-asserted in OnReady for panels that registered early.
    local cfg = ensureProfile()
    if cfg then
        if type(cfg.modules[id]) ~= "table" then
            cfg.modules[id] = { enabled = true }
        elseif cfg.modules[id].enabled == nil then
            cfg.modules[id].enabled = true
        end
    end

    -- enabled() reads the live DB value, defaulting to true when DB is absent.
    local function isEnabled()
        local c = ensureProfile()
        if c and type(c.modules[id]) == "table" and c.modules[id].enabled ~= nil then
            return c.modules[id].enabled and true or false
        end
        return true
    end

    -- (2) Boot dispatcher (Core agent's Core/Modules.lua). No-op gracefully if
    -- NE.modules is nil so load order can't crash.
    if NE.modules and type(NE.modules.Register) == "function" then
        local ok, err = pcall(function()
            NE.modules.Register{
                name    = id,
                default = true,
                onBoot  = function()
                    -- Only open/show when the panel is enabled in config.
                    if isEnabled() and spec.openFn then
                        spec.openFn()
                    end
                end,
            }
        end)
        if not ok then
            warn("NE.modules.Register failed for '" .. id .. "': " .. tostring(err))
        end
    end

    -- (3) DragonUI ModuleRegistry. Real base API is either
    -- NE.dragon.ModuleRegistry:Register(name, moduleTable, displayName, desc, order)
    -- or the convenience wrapper NE.dragon:RegisterModule(...). Prefer whichever
    -- the base actually exposes. We pass a lightweight module table carrying an
    -- Enable refresh hook so DragonUI's enable/disable plumbing can drive us.
    local moduleTable = {
        ne_id = id,
        Enable = function()
            if spec.openFn then spec.openFn() end
        end,
        Disable = function()
            if spec.closeFn then spec.closeFn() end
        end,
        Refresh = function()
            if isEnabled() then
                if spec.openFn then spec.openFn() end
            else
                if spec.closeFn then spec.closeFn() end
            end
        end,
    }
    local dragon = NE.dragon
    if dragon then
        local registered = false
        local mr = dragon.ModuleRegistry
        if mr and type(mr.Register) == "function" then
            local ok, err = pcall(mr.Register, mr, "ne_" .. id, moduleTable, title, desc, spec.order)
            if ok then
                registered = true
            else
                warn("ModuleRegistry:Register failed for '" .. id .. "': " .. tostring(err))
            end
        end
        if not registered and type(dragon.RegisterModule) == "function" then
            local ok, err = pcall(dragon.RegisterModule, dragon, "ne_" .. id, moduleTable, title, desc, spec.order)
            if not ok then
                warn("RegisterModule failed for '" .. id .. "': " .. tostring(err))
            end
        elseif not registered and not mr then
            warn("DragonUI exposes neither ModuleRegistry nor RegisterModule; '" .. id .. "' not in module list.")
        end
    end

    -- (4) Mover. Guard if MoversSystem or the frame is absent.
    if dragon and dragon.MoversSystem and type(dragon.MoversSystem.RegisterMover) == "function" then
        if spec.frame then
            local ok, err = pcall(function()
                dragon.MoversSystem:RegisterMover{
                    name         = "ne_" .. id,
                    parent       = spec.frame,
                    text         = title,
                    configPath   = { "widgets", "ne_" .. id },
                    defaultPoint = spec.defaultPoint,
                }
            end)
            if not ok then
                warn("RegisterMover failed for '" .. id .. "': " .. tostring(err))
            end
        end
        -- No frame yet (lazily-created panel): the panel re-calls RegisterPanel
        -- or registers its mover itself once the frame exists. Silent by design.
    elseif dragon and not dragon.MoversSystem then
        warn("DragonUI.MoversSystem absent; '" .. id .. "' not movable.")
    end

    -- (5) QA harness list.
    if NE.qa then
        NE.qa.modules = NE.qa.modules or {}
        table.insert(NE.qa.modules, {
            name  = title,
            frame = spec.frame,
            open  = spec.openFn,
            close = spec.closeFn,
        })
    end

    -- (6) Options tab list (rendered by Options.lua). Store a refresh fn so the
    -- toggle callback can re-run this panel's enable without knowing internals.
    table.insert(NE.optionPanels, {
        id      = id,
        title   = title,
        desc    = desc,
        order   = spec.order or 999,
        refresh = moduleTable.Refresh,
    })

    return moduleTable
end
