-- DragonUI_NewEra/core/Modules.lua — central module registry + reload-gated boot dispatcher.
--
-- DOWNPORT: NewEra Core/Modules.lua → 3.3.5a, re-homed onto DragonUI's DB. NewEra read enable
-- flags from its own SV (NE.db.modules.enabled). Per CONTRACTS §2 + §4, the DragonUI-facing toggle
-- lives in NE.dragon.db.profile.newera with shape `modules.<id>.enabled`. So IsEnabled/SetEnabled
-- read/write THAT location first (coordinated with the Integration agent), falling back to NewEra's
-- own SV and the registered default. The dispatcher, requires-chains, RIVALS/conflict logic, and
-- sub-boots port unchanged (all plain Lua + WoW events available on 3.3.5a).
--
-- §2 CONTRACT:
--   NE.modules.Register{ name=, default=, onBoot=fn }   (also accepts NewEra's Register(name, opts))
--   reload-gated boot dispatcher reading NE.dragon.db.profile.newera.modules.<id>.enabled.
--
-- THE RELOAD-GATED CONTRACT: disabling only writes the flag; a disabled module's onBoot is never
-- invoked on the next /reload. "Disabled" == "absence of boot", not teardown.

local NE = DragonUI_NewEra
NE.modules = NE.modules or {}
local Mods = NE.modules

Mods.registry = Mods.registry or {}   -- name -> opts
Mods.order    = Mods.order    or {}   -- registration order
Mods.booted   = Mods.booted   or {}   -- name -> true once booted this session

-- DOWNPORT: the DragonUI-backed enable store. Returns the `modules` table inside
-- NE.dragon.db.profile.newera, creating the chain lazily. nil if DragonUI's DB isn't ready yet.
local function dragonModulesTable(create)
  local dragon = NE.dragon
  local db = dragon and dragon.db
  local profile = db and db.profile
  if not profile then return nil end
  if not profile.newera then
    if not create then return nil end
    profile.newera = { enabled = true }
  end
  if not profile.newera.modules then
    if not create then return nil end
    profile.newera.modules = {}
  end
  return profile.newera.modules
end
Mods._dragonModulesTable = dragonModulesTable   -- exposed for the Integration agent / options

-- Enable state. Reads DragonUI's profile first, then NewEra's own SV, then the registered default.
function Mods.IsEnabled(name)
  local opts = Mods.registry[name]
  local default = not (opts and opts.default == false)
  -- (1) DragonUI profile: modules.<id>.enabled
  local dm = dragonModulesTable(false)
  if dm and dm[name] and dm[name].enabled ~= nil then
    return dm[name].enabled and true or false
  end
  -- (2) NewEra's own SV (legacy / standalone).
  if NE.db and NE.db.modules and NE.db.modules.enabled then
    local v = NE.db.modules.enabled[name]
    if v ~= nil then return v and true or false end
  end
  return default
end

-- Write the flag only. Reload-gated. Writes BOTH stores so either reader is consistent.
function Mods.SetEnabled(name, on)
  on = on and true or false
  -- DragonUI profile (the canonical store).
  local dm = dragonModulesTable(true)
  if dm then
    dm[name] = dm[name] or {}
    dm[name].enabled = on
  end
  -- NewEra SV mirror (so a standalone-loaded build still honours it).
  if NE.db then
    NE.db.modules = NE.db.modules or {}
    NE.db.modules.enabled = NE.db.modules.enabled or {}
    NE.db.modules.enabled[name] = on
  end
  local booted = Mods.booted[name] and true or false
  Mods.reloadPending = (booted ~= on) or Mods.reloadPending
  if Mods.onReloadPending then pcall(Mods.onReloadPending) end
end

Mods.blockedBy = Mods.blockedBy or {}
Mods.missingAddOn = Mods.missingAddOn or {}

function Mods.AddOnSatisfied(name)
  local opts = Mods.registry[name]
  local dep = opts and opts.requiresAddOn
  if not dep or type(dep.present) ~= "function" then return true end
  local ok, present = pcall(dep.present)
  return (ok and present) and true or false
end

-- Rival-addon yield ("play ball").
Mods.RIVALS = {
  BAGS       = { "Bagnon", "Bagshui", "ArkInventory", "AdiBags", "Baganator",
                 "Combuctor", "OneBag3", "tdBag2", "Sorted" },
  NAMEPLATES = { "Plater", "TidyPlates_ThreatPlates", "TidyPlates", "NeatPlates",
                 "Kui_Nameplates", "BetterBlizzPlates" },
  AUCTION    = { "Auctionator", "TradeSkillMaster", "aux-addon", "Auc-Advanced",
                 "AuctionLite" },
  ACTIONBARS = { "Bartender4", "Dominos" },
  CHAT       = { "Prat-3.0", "Chattynator" },
  TOOLTIP    = { "TipTac" },
}

Mods.conflictCache = Mods.conflictCache or {}

-- DOWNPORT: NewEra used C_AddOns.IsAddOnLoaded; on 3.3.5a use NE.IsAddOnLoaded (the FrameUtil
-- shim that prefers the global IsAddOnLoaded).
function Mods.ConflictedBy(name)
  local cached = Mods.conflictCache[name]
  if cached ~= nil then return cached or nil end
  local opts = Mods.registry[name]
  local rivals = opts and opts.conflictsWith
  local found = false
  if rivals then
    for _, addon in ipairs(rivals) do
      if NE.IsAddOnLoaded and NE.IsAddOnLoaded(addon) then found = addon; break end
    end
  end
  Mods.conflictCache[name] = found
  return found or nil
end

function Mods.ConflictOverride(name)
  local dm = dragonModulesTable(false)
  if dm and dm[name] and dm[name].conflictOverride ~= nil then
    return dm[name].conflictOverride and true or false
  end
  local t = NE.db and NE.db.modules and NE.db.modules.conflictOverride
  return (t and t[name]) and true or false
end

function Mods.SetConflictOverride(name, on)
  on = on and true or nil
  local dm = dragonModulesTable(true)
  if dm then
    dm[name] = dm[name] or {}
    dm[name].conflictOverride = on
  end
  if NE.db then
    NE.db.modules = NE.db.modules or {}
    NE.db.modules.conflictOverride = NE.db.modules.conflictOverride or {}
    NE.db.modules.conflictOverride[name] = on
  end
  Mods.reloadPending = true
  if Mods.onReloadPending then pcall(Mods.onReloadPending) end
end

function Mods.EffectivelyEnabled(name)
  if not Mods.IsEnabled(name) then return false end
  local opts = Mods.registry[name]
  if opts and opts.requiresAddOn and not Mods.AddOnSatisfied(name) then return false end
  if opts and opts.conflictsWith and not Mods.ConflictOverride(name) and Mods.ConflictedBy(name) then
    return false
  end
  return true
end

-- Dispatcher. One shared event frame.
local dispatcher = CreateFrame("Frame")
local wanted = {}

dispatcher:RegisterEvent("PLAYER_LOGIN")
dispatcher:RegisterEvent("PLAYER_ENTERING_WORLD")

local function shouldBoot(name)
  if not Mods.IsEnabled(name) then return false end
  local opts = Mods.registry[name]
  if opts and opts.requires then
    for _, dep in ipairs(opts.requires) do
      if not Mods.EffectivelyEnabled(dep) then
        if Mods.blockedBy[name] ~= dep and NE.Log then
          NE.Log("MODULES", name.." skipped: requires "..dep.." (disabled)")
        end
        Mods.blockedBy[name] = dep
        return false
      end
    end
  end
  if opts and opts.requiresAddOn and not Mods.AddOnSatisfied(name) then
    Mods.missingAddOn[name] = opts.requiresAddOn.label or "(addon)"
    return false
  end
  if opts and opts.conflictsWith and not Mods.ConflictOverride(name) and Mods.ConflictedBy(name) then
    return false
  end
  return true
end

Mods.subBoots = Mods.subBoots or {}

dispatcher:SetScript("OnEvent", function(_, event, arg1, ...)
  local list = wanted[event]
  if not list then return end
  for _, name in ipairs(list) do
    local opts = Mods.registry[name]
    if opts and opts.onBoot and shouldBoot(name) then
      Mods.booted[name] = true
      local ok, err = pcall(opts.onBoot, event, arg1, ...)
      if not ok and NE.Log then NE.Log("MODULES", "onBoot error in "..name..": "..tostring(err)) end
      local subs = Mods.subBoots[name]
      if subs then
        for _, e in ipairs(subs) do
          if e.every or not e.ran then
            e.ran = true
            local ok2, err2 = pcall(e.fn, event, arg1, ...)
            if not ok2 and NE.Log then NE.Log("MODULES", "sub-boot error in "..name..": "..tostring(err2)) end
          end
        end
      end
    end
  end
end)

function Mods.OnBoot(family, fn, opts)
  local entry = { fn = fn, every = (opts and opts.everyFire) and true or false }
  if Mods.booted[family] then
    entry.ran = true
    local ok, err = pcall(fn)
    if not ok and NE.Log then NE.Log("MODULES", "sub-boot error in "..family..": "..tostring(err)) end
    if not entry.every then return end
  end
  local list = Mods.subBoots[family]
  if not list then list = {}; Mods.subBoots[family] = list end
  list[#list + 1] = entry
end

-- Register. DOWNPORT: accepts EITHER NewEra's positional Register(name, opts) OR the §2 table form
-- Register{ name=, default=, onBoot=, events=/event=, ... }.
function Mods.Register(arg1, arg2)
  local name, opts
  if type(arg1) == "table" then
    opts = arg1
    name = opts.name
  else
    name = arg1
    opts = arg2 or {}
  end
  if not name then
    if NE.Log then NE.Log("MODULES", "Register called without a name") end
    return
  end
  if Mods.registry[name] then
    if NE.Log then NE.Log("MODULES", "duplicate module registration: "..tostring(name)) end
    return
  end
  Mods.registry[name] = opts
  Mods.order[#Mods.order + 1] = name
  -- DOWNPORT: default events. A module that supplies onBoot but no events still wants to boot —
  -- default it to PLAYER_LOGIN (the §2 onBoot intent), where DragonUI's DB is guaranteed ready.
  local evs = opts.events or (opts.event and { opts.event }) or (opts.onBoot and { "PLAYER_LOGIN" }) or nil
  if evs and opts.onBoot then
    for _, ev in ipairs(evs) do
      wanted[ev] = wanted[ev] or {}
      wanted[ev][#wanted[ev] + 1] = name
      dispatcher:RegisterEvent(ev)
    end
  end
end

function Mods.GetAll() return Mods.order, Mods.registry end
function Mods.Get(name) return Mods.registry[name] end
function Mods.IsBooted(name) return Mods.booted[name] and true or false end
