-- DragonUI_NewEra/compat/C_EquipmentSet.lua — map the retail C_EquipmentSet
-- namespace (used by NewEra's Equipment Manager source) onto 3.3.5a's NATIVE
-- equipment-manager, which lives as a GLOBAL function family, NOT under
-- C_EquipmentSet (CONTRACT_S1 §A.4):
--
--   GetNumEquipmentSets()                  -> number
--   GetEquipmentSetInfo(index)             -> name, texture          (index is 1-based ORDINAL)
--   GetEquipmentSetInfoByName(name)        -> texture, index, isEquipped, numItems
--   UseEquipmentSet(name)                  -- equip the set
--   SaveEquipmentSet(name, iconIndex)      -- create/overwrite (iconIndex, NOT a path!)
--   DeleteEquipmentSet(name)
--   GetEquipmentSetItemIDs(name)           -> { [slot]=itemID }
--   GetEquipmentSetLocations(name)         -> { [slot]=location }
--   EquipmentSetContainsLockedItems(name)  -> bool
--   GetEquipmentSetIconInfo(index)         -> texture, realIndex
--
-- THE IMPEDANCE MISMATCH this shim resolves:
--   * retail keys sets by an opaque integer `setID`; 3.3.5 keys by NAME + a
--     volatile 1-based ordinal (the ordinal renumbers when a set is deleted).
--   * retail's icon argument is a texture PATH; 3.3.5's SaveEquipmentSet takes an
--     icon INDEX into the macro-icon list (GetMacroIconInfo).
--   So we synthesise a STABLE integer setID per name (id↔name maps, never reused
--   within a session) and convert texture-path icons to the nearest macro index.
--
-- This file is a thin namespace so any NewEra code that literally calls
-- C_EquipmentSet.* still works; the actual backend decision (native vs custom
-- ItemRack-model) lives in EquipmentSets.lua, which calls the same globals.
--
-- 3.3.5 LAW (project memory): native equipment API is FLAKY on private servers.
-- We PROBE GetNumEquipmentSets at load and set NE.cap.equipmentSets; if the probe
-- fails or the family is absent, EquipmentSets.lua falls back to a custom backend
-- and this shim's calls are simply never exercised. We NEVER clobber a real
-- C_EquipmentSet (ClassicAPI or a future server) — define only what's missing.

local NE = DragonUI_NewEra
if not NE then return end

NE.cap = NE.cap or {}

local function log(msg)
  if NE.charpanel and NE.charpanel._log then NE.charpanel._log(msg); return end
  if NE.Log then NE.Log("EQUIPCOMPAT", msg) end
end

-- ----------------------------------------------------------------------------
-- Capability probe. The native family is present AND callable?
-- ----------------------------------------------------------------------------
local function probeNative()
  -- DOWNPORT/REPORT: CLIENT-SIDE ONLY (deliberate). The native equipment-manager API
  -- (GetNumEquipmentSets / SaveEquipmentSet / UseEquipmentSet) depends on SERVER support — on servers
  -- that lack it, or where it's flaky or DISABLED (CVar equipmentManager=0 → "The Equipment Manager is
  -- disabled"), sets silently break. We use the self-contained client-side backend instead: sets live
  -- in our SavedVariables (DragonUI_NewEraDB) and equipping is a physical item swap, so it works on ANY
  -- server. Native is intentionally never used.
  return false
end

local NATIVE = probeNative()
NE.cap.equipmentSets = NATIVE
log("native equipment-set API " .. (NATIVE and "AVAILABLE" or "absent/flaky") ..
    " -> backend " .. (NATIVE and "NATIVE" or "CUSTOM"))

-- If the native family isn't usable, there's nothing to map onto — the custom
-- backend (EquipmentSets.lua) handles everything in Lua. Still publish an empty
-- namespace so a stray C_EquipmentSet.* reference doesn't nil-error; each method
-- degrades to a safe value.
if not NATIVE then
  if not _G.C_EquipmentSet then
    _G.C_EquipmentSet = {
      CanUseEquipmentSets        = function() return false end,
      GetNumEquipmentSets        = function() return 0 end,
      GetEquipmentSetIDs         = function() return {} end,
      GetEquipmentSetID          = function() return nil end,
      GetEquipmentSetInfo        = function() return nil end,
      GetItemIDs                 = function() return {} end,
      GetIgnoredSlots            = function() return {} end,
      CreateEquipmentSet         = function() end,
      SaveEquipmentSet           = function() end,
      ModifyEquipmentSet         = function() end,
      DeleteEquipmentSet         = function() end,
      UseEquipmentSet            = function() return false end,
      PickupEquipmentSet         = function() end,
      EquipmentSetContainsLockedItems = function() return false end,
      IgnoreSlotForSave          = function() end,
      UnignoreSlotForSave        = function() end,
      IsSlotIgnoredForSave       = function() return false end,
      ClearIgnoredSlotsForSave   = function() end,
    }
    NE.compat = NE.compat or {}
    NE.compat.stubs = NE.compat.stubs or {}
    NE.compat.stubs["C_EquipmentSet"] = "no native engine; custom backend live"
  end
  return
end

-- ----------------------------------------------------------------------------
-- NATIVE path: build the C_EquipmentSet.* adapter onto the 3.3.5 globals.
-- Never clobber an existing impl (ClassicAPI / future server / hydrate path).
-- ----------------------------------------------------------------------------
if _G.C_EquipmentSet and _G.C_EquipmentSet.GetNumEquipmentSets then
  -- Something already provides a real namespace; trust it.
  return
end

local C = _G.C_EquipmentSet or {}
_G.C_EquipmentSet = C

-- Stable setID <-> name synthesis. 3.3.5 names are the real identity; we mint a
-- monotonically-increasing integer id per name we see, and never reuse an id for
-- a different name in a session, so the pane's selectedSetID stays valid even as
-- the native ordinal renumbers under deletes.
local nameToID, idToName = {}, {}
local nextID = 1
local function idFor(name)
  if not name then return nil end
  local id = nameToID[name]
  if not id then
    id = nextID; nextID = nextID + 1
    nameToID[name] = id
    idToName[id] = name
  end
  return id
end
local function nameFor(id)
  return idToName[id]
end

-- Ordinal (native 1-based index) for a name — needed because some native getters
-- take the ordinal, not the name. Rebuilt each call (cheap; <=20 sets).
local function ordinalFor(name)
  local n = _G.GetNumEquipmentSets() or 0
  for i = 1, n do
    local iname = _G.GetEquipmentSetInfo(i)
    if iname == name then return i end
  end
  return nil
end

-- texture path -> macro-icon INDEX for SaveEquipmentSet. Scan the macro-icon list
-- for a matching path; fall back to index 1 ("question mark") if not found. Most
-- equip-set icons ARE equipped-item textures, which RefreshEquipmentSetIconInfo
-- prepends as NEGATIVE indices — SaveEquipmentSet accepts those too, so we first
-- try GetEquipmentSetIconInfo's negative range.
local function iconPathToIndex(path)
  if not path then return 1 end
  if type(path) == "number" then return path end  -- already an index
  if type(_G.GetEquipmentSetIconInfo) == "function" and type(_G.GetNumMacroIcons) == "function" then
    -- RefreshEquipmentSetIconInfo populates the equipped-item prefix; calling
    -- GetEquipmentSetInfoByName / any set getter keeps it fresh enough. Scan a
    -- bounded window (equipped items are few; macro icons are the bulk).
    local total = (_G.GetNumMacroIcons() or 0) + 19
    for i = 1, total do
      local tex = _G.GetEquipmentSetIconInfo(i)
      if tex == path then
        local _, realIndex = _G.GetEquipmentSetIconInfo(i)
        return realIndex or i
      end
    end
  end
  return 1
end

function C.CanUseEquipmentSets() return true end

function C.GetNumEquipmentSets()
  return _G.GetNumEquipmentSets() or 0
end

-- Array of synthesised setIDs, display order = native ordinal order.
function C.GetEquipmentSetIDs()
  local out = {}
  local n = _G.GetNumEquipmentSets() or 0
  for i = 1, n do
    local name = _G.GetEquipmentSetInfo(i)
    if name then out[#out + 1] = idFor(name) end
  end
  return out
end

function C.GetEquipmentSetID(name)
  if not name then return nil end
  local texture = _G.GetEquipmentSetInfoByName(name)
  if texture == nil and not ordinalFor(name) then return nil end
  return idFor(name)
end

-- retail shape: name, icon, setID, isEquipped, numItems, numEquipped,
--               numInInventory, numLost, numIgnored.
function C.GetEquipmentSetInfo(setID)
  local name = nameFor(setID)
  if not name then return nil end
  local texture, index, isEquipped, numItems = _G.GetEquipmentSetInfoByName(name)
  if texture == nil and index == nil then return nil end  -- gone
  -- 3.3.5 reports total + (implicitly) equipped via isEquipped only; we surface a
  -- best-effort split: when equipped, all items are equipped. numInInventory/Lost
  -- aren't exposed natively, so report 0 (the pane degrades the missing-item red
  -- colouring, which is cosmetic).
  numItems = numItems or 0
  local numEquipped = isEquipped and numItems or 0
  return name, texture, setID, isEquipped and true or false, numItems, numEquipped, 0, 0, 0
end

function C.GetItemIDs(setID)
  local name = nameFor(setID)
  if not name then return {} end
  if type(_G.GetEquipmentSetItemIDs) == "function" then
    return _G.GetEquipmentSetItemIDs(name) or {}
  end
  return {}
end

function C.GetIgnoredSlots(setID)
  -- 3.3.5 has GetEquipmentSetLocations(name) -> { [slot]=location }; a location of
  -- 1 (ITEM_INVENTORY_LOCATION_PLAYER-ish "ignored" sentinel) isn't exposed cleanly,
  -- so report none ignored (cosmetic; shirt/tabard default-ignore is handled in the
  -- save flow by the custom path, and native SaveEquipmentSet saves all slots).
  return {}
end

function C.CreateEquipmentSet(name, icon)
  if not name then return end
  _G.SaveEquipmentSet(name, iconPathToIndex(icon))
  idFor(name)
end

function C.SaveEquipmentSet(setID, icon)
  local name = nameFor(setID)
  if not name then return end
  if icon ~= nil then
    _G.SaveEquipmentSet(name, iconPathToIndex(icon))
  else
    -- Re-save keeping the current icon: read it back, convert, re-save.
    local tex = _G.GetEquipmentSetInfoByName(name)
    _G.SaveEquipmentSet(name, iconPathToIndex(tex))
  end
end

function C.ModifyEquipmentSet(setID, newName, newIcon)
  local name = nameFor(setID)
  if not name then return end
  if type(_G.RenameEquipmentSet) == "function" and newName and newName ~= name then
    _G.RenameEquipmentSet(name, newName)
    -- rebind the synthesised id to the new name
    nameToID[name] = nil
    nameToID[newName] = setID
    idToName[setID] = newName
    name = newName
  end
  if newIcon ~= nil then
    _G.SaveEquipmentSet(name, iconPathToIndex(newIcon))
  end
end

function C.DeleteEquipmentSet(setID)
  local name = nameFor(setID)
  if not name then return end
  _G.DeleteEquipmentSet(name)
  nameToID[name] = nil
  idToName[setID] = nil
end

function C.UseEquipmentSet(setID)
  local name = nameFor(setID)
  if not name then return false end
  if type(_G.EquipmentManager_EquipSet) == "function" then
    _G.EquipmentManager_EquipSet(name)   -- guards locked items + casting
  else
    _G.UseEquipmentSet(name)
  end
  return true
end

function C.PickupEquipmentSet(setID)
  local name = nameFor(setID)
  if name and type(_G.PickupEquipmentSet) == "function" then
    _G.PickupEquipmentSet(name)
  end
end

function C.EquipmentSetContainsLockedItems(setID)
  local name = nameFor(setID)
  if name and type(_G.EquipmentSetContainsLockedItems) == "function" then
    return _G.EquipmentSetContainsLockedItems(name) and true or false
  end
  return false
end

-- Ignored-slot scratch state: 3.3.5's SaveEquipmentSet has no per-save ignore API,
-- so these are no-ops on the native path (shirt/tabard get saved like any slot).
function C.IgnoreSlotForSave() end
function C.UnignoreSlotForSave() end
function C.IsSlotIgnoredForSave() return false end
function C.ClearIgnoredSlotsForSave() end

NE.compat = NE.compat or {}
NE.compat.equipmentSetBackend = "native"
