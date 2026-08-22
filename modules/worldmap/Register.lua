-- DragonUI_NewEra/modules/worldmap/Register.lua — boot wiring for the world map.
--
-- WorldMapFrame lives in FrameXML on this client, not in a LoadOnDemand addon as it does on Era, so
-- there is nothing to wait for: one PLAYER_LOGIN builds the whole thing. Reload-gated like every
-- other window toggle — turning the module off writes the flag and the next /reload simply never
-- boots it, leaving the client's own map untouched.
--
-- THE RIVAL CHECK IS THE INTERESTING PART. Unlike the other windows here, this one has a real
-- chance of not being the only addon that wants the frame: Mapster clears
-- `UIPanelWindows["WorldMapFrame"]` and takes over drag, scale, strata, borders and the POI math
-- outright. Two addons cannot own it. `conflictsWith` makes ours stand down and report as
-- conflicted in the options rather than fight — with the standard per-module `conflictOverride`
-- escape hatch for a player who wants ours instead. See core/Modules.lua's RIVALS.WORLDMAP.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local WM = NE.worldmap
local L  = NE.L
if not WM then return end

local MODULE = "WorldMap"

local function boot()
  -- Order matters: the chrome builds the window and the spacer that everything else anchors to,
  -- then the breadcrumb, then the pins, then the side panel (which asks the chrome to re-lay-out
  -- around it, so the chrome must already be up).
  WM.Arm()
  if WM.BuildNavBar then WM.BuildNavBar() end
  if WM.ArmPins then WM.ArmPins() end
  if WM.dungeon and WM.dungeon.Arm then WM.dungeon.Arm() end
  if NE.questlogpanel and NE.questlogpanel.Arm then NE.questlogpanel.Arm() end
  if WM.fog and WM.fog.Arm then WM.fog.Arm() end
  -- The magnifier before the wheel, which only drives it: arming the driver on its own would give
  -- the player a wheel that silently does nothing.
  if WM.canvaszoom and WM.canvaszoom.Arm then WM.canvaszoom.Arm() end
  if WM.wheel and WM.wheel.Arm then WM.wheel.Arm() end
  if WM.filter and WM.filter.Arm then WM.filter.Arm() end
end

if NE.modules and NE.modules.Register then
  NE.modules.Register{
    name     = MODULE,
    default  = true,
    label    = L["World map"],
    category = "Windows",
    -- Same string the options row renders (integration/Options.lua): one key, one translation.
    desc     = L["Modern frame, portrait and breadcrumb navigation on the world map, with the quest "
             .. "log as a side panel. Stands down automatically when a dedicated map addon "
             .. "(Mapster, Carbonite) is installed. Reload (/reload) to apply."],
    conflictsWith = NE.modules.RIVALS and NE.modules.RIVALS.WORLDMAP,
    events   = { "PLAYER_LOGIN" },
    onBoot   = boot,
  }
end

-- ONE TOGGLE, NOT FOUR. Fog, magnification and the filter were each registered as modules of their
-- own, on the reasoning that a player should be able to switch off the invasive parts individually.
-- That was the wrong shape: this is one window, it reads as one feature, and four rows for it in the
-- options is four decisions where the player wanted one. The runtime controls that matter are on the
-- map itself -- the filter button switches fog, quest objectives and landmark pins live, with no
-- reload -- so the options row is about the WINDOW, and everything in it lives or dies together.
--
-- ----------------------------------------------------------------------------
-- QA harness entry (optional; guarded). Unlike the merchant and inspect windows, this one CAN be
-- opened on demand — ToggleWorldMap is always available — so the harness gets a real open/close
-- rather than a no-op.
-- ----------------------------------------------------------------------------
if NE.qa then
  NE.qa.modules = NE.qa.modules or {}
  table.insert(NE.qa.modules, {
    name  = L["World map"],
    frame = _G.WorldMapFrame,
    open  = function()
      local f = _G.WorldMapFrame
      if f and not f:IsShown() then
        if _G.ToggleWorldMap then _G.ToggleWorldMap() else f:Show() end
      end
    end,
    close = function()
      local f = _G.WorldMapFrame
      if f and f:IsShown() then
        if HideUIPanel then HideUIPanel(f) else f:Hide() end
      end
    end,
  })
end
