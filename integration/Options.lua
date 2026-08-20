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
local L = NE.L

local OPTIONS_ADDON = "DragonUI_Options"
local TAB_KEY       = "newera"
-- Product name, deliberately not localized: it's how the addon is listed everywhere else.
local TAB_TITLE     = "New Era"
local TAB_ORDER     = 16

-- The list the builder iterates is owned by Register.lua. Keep a safe handle.
NE.optionPanels = NE.optionPanels or {}

-- Extension point: a module that owns settings beyond a simple enable toggle appends
--   { order = <n>, build = function(scroll, Controls) ... end }
-- here, and the builder renders it after the built-in sections. Added for the Cooldown Manager,
-- whose ten per-viewer settings live here rather than in an Edit Mode popup (see
-- modules/cooldownviewer/PORT_PLAN.md §B1). Each section is pcall-guarded so one module's bad
-- control can't blank the whole tab.
NE.optionSections = NE.optionSections or {}

function NE.RegisterOptionSection(spec)
    if type(spec) ~= "table" or type(spec.build) ~= "function" then return end
    spec.order = spec.order or 999
    table.insert(NE.optionSections, spec)
    table.sort(NE.optionSections, function(a, b) return a.order < b.order end)
end

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
        L["NewEra panels ported onto DragonUI. Toggle a panel below to enable or disable it. "
        .. "Panels appear here as their modules load."])
    if C.AddSpacer then C:AddSpacer(scroll) end

    -- (Per-window enable toggles live in the "Windows" section below; we intentionally do NOT also
    -- render NE.optionPanels here — that produced a redundant duplicate toggle per window.)

    -- ----------------------------------------------------------------------------
    -- Windows — enable/disable each replacement window. RELOAD-GATED: toggling only writes the flag;
    -- a disabled module simply isn't booted on the next /reload (the Blizzard default frame is used).
    -- ----------------------------------------------------------------------------
    if NE.modules and NE.modules.IsEnabled then
        C:AddHeading(scroll, L["Windows"])
        C:AddDescription(scroll,
            L["Use DragonUI's window in place of the Blizzard default. Changes take effect after a /reload."])
        -- The per-window "Retail bags" restyle toggle stays hidden (the combined bag replaces it), but
        -- the combined bag itself IS toggleable so players can turn our bag UI off entirely and fall
        -- back to the stock Blizzard bags. To also re-expose the per-window restyle, add a row:
        --   { id = "bags", label = "Retail bags" }
        -- No Character panel or Collections rows here: DragonUI ships both of those windows itself,
        -- so ours were removed outright rather than kept as a second replacement over the top.
        local WINDOWS = {
            { id = "Spellbook",   label = SPELLBOOK or L["Spellbook"] },
            { id = "Talents",     label = TALENTS or L["Talents"] },
            { id = "Professions", label = L["Professions"] },
            { id = "AuctionHouse", label = L["Auction House"] },
            { id = "Social",      label = L["Social (Friends/Who/Guild/Chat/Raid)"] },
            -- A reskin rather than a replacement window: OFF here means Blizzard's own inspect
            -- window, untouched.
            { id = "Inspect",     label = L["Inspect window"],
              desc = L["Modern frame, portrait and tabs on the inspect window, with its Character "
                     .. "tab laid out like the character window. Reload (/reload) to apply."] },
            -- Also a reskin, not a replacement window: OFF means Blizzard's own vendor frame.
            { id = "MerchantFrame", label = L["Merchant window"],
              desc = L["Modern frame, portrait and tabs on the vendor window, plus a sell-all-junk "
                     .. "button and the buyback undo arrow. Reload (/reload) to apply."] },
            { id = "LFG",         label = L["Looking For Group (Dungeon/Raid Finder)"] },
            { id = "combinedbag", label = L["Combined bag (all-in-one)"],
              desc = L["Our all-in-one bag window. Turn OFF to use the stock Blizzard bags instead. Reload (/reload) to apply."] },
        }
        for _, w in ipairs(WINDOWS) do
            local id = w.id
            C:AddToggle(scroll, {
                label   = w.label,
                desc    = w.desc or L["Reload (/reload) to apply."],
                getFunc = function() return NE.modules.IsEnabled(id) and true or false end,
                setFunc = function(v)
                    if NE.modules.SetEnabled then pcall(NE.modules.SetEnabled, id, v) end
                end,
                requiresReload = true,
            })
        end
    end

    -- Adventure Guide (Encounter Journal) doesn't go through the NE.modules registry above (it
    -- wires into DragonUI's own ModuleRegistry as "ne_EncounterJournal", like every other DragonUI
    -- module) -- add it here explicitly so it's visible on this tab too.
    C:AddToggle(scroll, {
        label   = L["Adventure Guide (Encounter Journal)"],
        desc    = L["Boss and loot browser. Requires a /reload to take effect (the micro button doesn't re-check this live)."],
        getFunc = function()
            local modules = dragon.db.profile.modules
            local m = modules and modules["ne_EncounterJournal"]
            return not (type(m) == "table" and m.enabled == false)
        end,
        setFunc = function(v)
            if not dragon.db.profile.modules then dragon.db.profile.modules = {} end
            if not dragon.db.profile.modules["ne_EncounterJournal"] then
                dragon.db.profile.modules["ne_EncounterJournal"] = {}
            end
            dragon.db.profile.modules["ne_EncounterJournal"].enabled = v
        end,
        requiresReload = true,
    })

    -- ----------------------------------------------------------------------------
    -- Window scaling — a mode dropdown (UI scale / none / custom) + a custom-size slider per window.
    -- Backed by NE.scale (NE.db.scale[window]); changes apply IMMEDIATELY to the live frame.
    -- ----------------------------------------------------------------------------
    if C.AddSpacer then C:AddSpacer(scroll) end
    C:AddHeading(scroll, L["Window Scaling"])
    local S = NE.scale
    if not S then
        -- core/Scale.lua isn't loaded — surface it instead of silently showing nothing.
        C:AddDescription(scroll,
            L["Scaling controls are unavailable: the 'core\\Scale.lua' file isn't loaded. Make sure your "
            .. "installed DragonUI_NewEra includes core/Scale.lua AND its line in the .toc, then /reload."])
    elseif not (C.AddDropdown and C.AddSlider) then
        C:AddDescription(scroll, L["Scaling controls need a newer DragonUI options panel (AddSlider/AddDropdown)."])
    else
        C:AddDescription(scroll,
            L["Each window's size: \"Use UI scale\" follows the game's UI Scale slider, \"No scaling\" "
            .. "stays pixel-perfect, \"Custom\" uses its slider. The custom slider is greyed out and "
            .. "locked unless that window's mode is set to Custom."])
        local AceGUI = LibStub and LibStub("AceGUI-3.0")
        local MODES = { ui = L["Use UI scale"], none = L["No scaling"], custom = L["Custom"] }
        -- Keys are core/Scale.lua's window keys; every one of these frames registers itself with
        -- NE.scale.SetFrame(key, frame) as it builds, so a change here lands on the live window.
        -- A window that hasn't been opened yet this session simply has no frame registered — the
        -- setting still persists and applies on its first build.
        local WINDOWS = {
            { key = "spellbook",       label = SPELLBOOK or L["Spellbook"] },
            { key = "talents",         label = TALENTS or L["Talents"] },
            { key = "professions",     label = L["Professions"] },
            { key = "social",          label = L["Social"] },
            { key = "guild",           label = GUILD or L["Guild"] },
            { key = "lfg",             label = L["Looking For Group"] },
            { key = "auctionhouse",    label = L["Auction House"] },
            { key = "cooldownmanager", label = L["Cooldown Manager"] },
            { key = "encounterjournal", label = L["Adventure Guide"] },
            { key = "combinedbag",     label = L["Combined Bag"] },
        }

        -- One window's stacked controls: a centered column header, a mode dropdown, and a custom-scale
        -- slider that disables/re-enables live as the mode dropdown changes (no /reload needed).
        local function buildColumn(parent, key, label)
            if AceGUI then
                local hdr = AceGUI:Create("Heading")
                hdr:SetText(label)
                hdr:SetFullWidth(true)
                parent:AddChild(hdr)
            end
            local slider
            C:AddDropdown(parent, {
                label   = L["Scale mode"],
                values  = MODES,
                getFunc = function() local m = S.Get(key); return m end,
                setFunc = function(v)
                    S.SetMode(key, v)
                    if slider then slider:SetDisabled(v ~= "custom") end
                end,
            })
            slider = C:AddSlider(parent, {
                label    = L["Custom scale"],
                min      = S.MIN or 0.5, max = S.MAX or 1.5, step = 0.05,
                getFunc  = function() local _, c = S.Get(key); return c end,
                setFunc  = function(v) S.SetCustom(key, v) end,
                disabled = function() return S.Get(key) ~= "custom" end,
            })
        end

        if AceGUI then
            -- Side-by-side columns, each a vertical stack (wraps onto further rows via the Flow
            -- layout once WINDOWS outgrows a single row of 0.32-width columns).
            local row = AceGUI:Create("SimpleGroup")
            row:SetFullWidth(true)
            row:SetLayout("Flow")
            scroll:AddChild(row)
            for _, w in ipairs(WINDOWS) do
                local col = AceGUI:Create("SimpleGroup")
                col:SetRelativeWidth(0.32)
                col:SetLayout("List")
                row:AddChild(col)
                buildColumn(col, w.key, w.label)
            end
        else
            -- No AceGUI containers available: fall back to a flat vertical list.
            for _, w in ipairs(WINDOWS) do
                C:AddHeading(scroll, w.label)
                buildColumn(scroll, w.key, w.label)
            end
        end
    end

    -- Module-contributed sections (NE.RegisterOptionSection). Guarded individually: a module whose
    -- section errors must not take the rest of the tab down with it.
    for _, section in ipairs(NE.optionSections) do
        local ok, err = pcall(section.build, scroll, C)
        if not ok and NE._warn then
            NE._warn("options section '" .. tostring(section.id or "?") .. "' failed: " .. tostring(err))
        end
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
