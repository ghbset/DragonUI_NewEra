-- DragonUI_NewEra/integration/Options.lua
-- Adds a "New Era" tab to the DragonUI options panel (the DragonUI_Options
-- companion addon). The tab lists one enable toggle per registered NewEra panel.
--
-- DragonUI_Options is a separate, possibly LoadOnDemand-ish addon: it may load
-- AFTER us, or already be loaded. We handle both: register now if its
-- OptionsPanel is present, otherwise hook ADDON_LOADED for "DragonUI_Options".
--
-- DOWNPORT: new glue; the 1.15 NewEra addon had a bespoke settings frame. We
-- proxy each panel's `enabled` flag into DragonUI's profile + PanelControls.

local NE = DragonUI_NewEra
if not NE then return end

local OPTIONS_ADDON = "DragonUI_Options"
local TAB_KEY       = "newera"
local TAB_TITLE     = "New Era"
local TAB_ORDER     = 16

-- The list the builder iterates is owned by Register.lua. Keep a safe handle.
NE.optionPanels = NE.optionPanels or {}

-- ----------------------------------------------------------------------------
-- builder(scroll): called by OptionsPanel each time the tab is shown.
-- `scroll` is an AceGUI ScrollFrame; controls are added via NE.dragon.PanelControls
-- (Controls:AddHeading / AddDescription / AddToggle, all of which :AddChild it).
-- Must never error when the panel list is empty.
-- ----------------------------------------------------------------------------
local function builder(scroll)
    local dragon = NE.dragon
    local C = dragon and dragon.PanelControls
    if not C then
        -- No PanelControls to render with; nothing we can safely draw.
        return
    end

    C:AddHeading(scroll, TAB_TITLE)
    C:AddDescription(scroll,
        "NewEra panels ported onto DragonUI. Toggle a panel below to enable or disable it. "
        .. "Panels appear here as their modules load.")
    if C.AddSpacer then C:AddSpacer(scroll) end

    local panels = NE.optionPanels
    if not panels or #panels == 0 then
        C:AddDescription(scroll, "No panels loaded yet \226\128\148 they appear here as modules load.")
        return
    end

    -- Stable display order.
    local ordered = {}
    for _, p in ipairs(panels) do ordered[#ordered + 1] = p end
    table.sort(ordered, function(a, b)
        if (a.order or 999) == (b.order or 999) then
            return tostring(a.title) < tostring(b.title)
        end
        return (a.order or 999) < (b.order or 999)
    end)

    for _, panel in ipairs(ordered) do
        local id = panel.id
        C:AddToggle(scroll, {
            label  = panel.title or id,
            desc   = panel.desc,
            -- dbPath resolves against DragonUI.db.profile; SetDBValue autocreates
            -- intermediate tables, so this is safe even pre-default.
            dbPath = "newera.modules." .. id .. ".enabled",
            callback = function(value)
                -- Re-run this panel's enable/disable without touching internals.
                if type(panel.refresh) == "function" then
                    local ok = pcall(panel.refresh)
                    if not ok and NE._warn then
                        NE._warn("options toggle refresh failed for '" .. tostring(id) .. "'")
                    end
                elseif NE.modules and type(NE.modules.SetEnabled) == "function" then
                    pcall(NE.modules.SetEnabled, id, value)
                end
            end,
        })
    end
end
NE.OptionsBuilder = builder

-- ----------------------------------------------------------------------------
-- Registration with whichever DragonUI_Options instance is available.
-- ----------------------------------------------------------------------------
local registered = false

local function tryRegister()
    if registered then return true end
    local dragon = NE.dragon
    local panel = dragon and dragon.OptionsPanel
    if not (panel and type(panel.RegisterTab) == "function") then
        return false
    end
    local ok, err = pcall(panel.RegisterTab, panel, TAB_KEY, TAB_TITLE, builder, TAB_ORDER)
    if ok then
        registered = true
        return true
    end
    if NE._warn then NE._warn("OptionsPanel:RegisterTab failed: " .. tostring(err)) end
    return false
end

-- Case A: DragonUI_Options already loaded (OptionsPanel present) -> register now.
if not tryRegister() then
    -- Case B: hook ADDON_LOADED and register once DragonUI_Options arrives.
    local f = CreateFrame("Frame")
    f:RegisterEvent("ADDON_LOADED")
    f:SetScript("OnEvent", function(self, _, name)
        -- Retry on the DragonUI_Options load specifically, but also opportunistically
        -- on any load in case OptionsPanel appeared via a different addon name.
        if (name == OPTIONS_ADDON or NE.dragon and NE.dragon.OptionsPanel) and tryRegister() then
            self:UnregisterEvent("ADDON_LOADED")
        end
    end)
end
