-- DragonUI_NewEra/modules/character/EquipmentSets.lua — Equipment-Manager backend.
--
-- ONE API surface (NE.equipsets) that mirrors retail's C_EquipmentSet return shapes
-- so the pane (EquipmentManagerPane.lua) is identical regardless of which backend is
-- live. Backend is RESOLVED at runtime, never guessed (project memory Law 1):
--
--   * NATIVE  — when NE.cap.equipmentSets (compat/C_EquipmentSet.lua probed the
--               3.3.5 global equip family and it answered). Thin passthrough to the
--               C_EquipmentSet adapter shim → the engine does the swap.
--   * CUSTOM  — the default on private servers (the native equip API is FLAKY there
--               — project memory). Sets are stored per-character in NE.db via
--               NE.CharKey(), and equip is the ItemRack-model physical swap
--               (PickupContainerItem/PickupInventoryItem + a lock watcher) proven on
--               3.3.5a/Epoch in DragonflightUICharacter/EquipmentManager.lua. We do
--               NOT trust the Blizzard equipment-set engine for the actual swap.
--
-- The pane consumes: GetSetIDs / GetNumSets / GetSetID / GetSetInfo / GetItemIDs /
-- Create / Save / Modify / Delete / Use / Pickup / SeedDefaultIgnored / MAX_SETS +
-- the ignore-slot scratch helpers + RegisterChanged / RegisterSwapFinished.
--
-- DOWNPORT notes vs NewEra source:
--   * `local NE = DragonUI_NewEra` (not the `NE = NE or {}` global).
--   * charKey() -> NE.CharKey().
--   * Custom equip is the ItemRack physical-swap model, not EquipItemByName (more
--     reliable on private servers; handles 2H→offhand clear; lock-aware retry).
--   * C_Container is provided by compat/; NUM_BAG_SLOTS guarded (4 if absent).

local NE = DragonUI_NewEra
NE.equipsets = NE.equipsets or {}
local M = NE.equipsets

local function log(msg)
  if NE.charpanel and NE.charpanel._log then NE.charpanel._log(msg) end
end

-- Constants. Vanilla equippable inventory slots: 1 Head … 19 Tabard (contiguous).
local FIRST_SLOT, LAST_SLOT = 1, 19
local NUM_SLOTS = LAST_SLOT
local MAXBAG = _G.NUM_BAG_SLOTS or 4   -- bags 0..MAXBAG (backpack + 4)
-- Retail ignores Shirt (4) and Tabard (19) on a new set.
local DEFAULT_IGNORED = { [4] = true, [19] = true }
M.MAX_SETS = _G.MAX_EQUIPMENT_SETS_PER_PLAYER or 10

-- ----------------------------------------------------------------------------
-- Backend resolution. NE.cap.equipmentSets is set by compat/C_EquipmentSet.lua.
-- ----------------------------------------------------------------------------
local function usingNative()
  return NE.cap and NE.cap.equipmentSets == true and _G.C_EquipmentSet ~= nil
end
M.UsingNative = usingNative

-- ----------------------------------------------------------------------------
-- Change / swap notification. The pane registers callbacks; we fire on mutation
-- and on inventory/bag updates so the equipped check + missing-item colouring stay
-- live. In native mode we also relay the real engine events.
-- ----------------------------------------------------------------------------
local changedCallbacks, swapCallbacks = {}, {}
function M.RegisterChanged(fn) changedCallbacks[#changedCallbacks + 1] = fn end
function M.RegisterSwapFinished(fn) swapCallbacks[#swapCallbacks + 1] = fn end
local function fireChanged() for _, fn in ipairs(changedCallbacks) do pcall(fn) end end
local function fireSwap(result, setID) for _, fn in ipairs(swapCallbacks) do pcall(fn, result, setID) end end

-- ----------------------------------------------------------------------------
-- Container helpers — route through compat C_Container, with a positional-global
-- fallback so the backend works even if compat hasn't shimmed everything.
-- ----------------------------------------------------------------------------
local function bagNumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  return GetContainerNumSlots(bag) or 0
end
local function bagItemLink(bag, slot)
  if C_Container and C_Container.GetContainerItemLink then return C_Container.GetContainerItemLink(bag, slot) end
  return GetContainerItemLink(bag, slot)
end

-- Item identity (ItemRack model): item string minus the trailing unique/level
-- number, so the same gear matches across instances. Accepts links or ids.
local function itemString(link)
  if not link then return nil end
  if type(link) == "number" then return tostring(link) end
  return link:match("item:(.+):%-?%d+") or link:match("item:(%d+)")
end
local function itemIDFromLink(link)
  if not link then return nil end
  if type(link) == "number" then return link end
  local id = link:match("item:(%d+)")
  return id and tonumber(id) or nil
end
local function sameID(a, b)
  if not a or not b then return false end
  return a:match("^(%-?%d+)") == b:match("^(%-?%d+)")
end
local function slotItem(invSlot) return itemString(GetInventoryItemLink("player", invSlot)) end

-- ----------------------------------------------------------------------------
-- Per-character store: NE.db.equipmentSets[charKey] = { nextID, sets = { [id]=set } }.
--   set = { id, name, icon, items = { [slot]=itemString }, ignored = { [slot]=bool } }
-- ----------------------------------------------------------------------------
local function store()
  local db = NE.db
  if not db then return nil end
  db.equipmentSets = db.equipmentSets or {}
  local key = NE.CharKey()
  local s = db.equipmentSets[key]
  if not s then s = { nextID = 1, sets = {} }; db.equipmentSets[key] = s end
  return s
end

-- Transient "ignored slots for the next save" scratch state.
local pendingIgnored = {}

-- Capture currently-equipped gear (skipping ignored slots) as item strings.
local function snapshotGear(ignored)
  local items = {}
  for slot = FIRST_SLOT, LAST_SLOT do
    if not (ignored and ignored[slot]) then
      local id = slotItem(slot)
      if id then items[slot] = id end
    end
  end
  return items
end

-- Find an item (exact, then base-id) in bags, skipping already-used sources.
local function findInBags(idStr, used)
  for pass = 1, 2 do
    for bag = 0, MAXBAG do
      local n = bagNumSlots(bag)
      for slot = 1, n do
        local key = bag * 100 + slot
        if not (used and used[key]) then
          local bi = itemString(bagItemLink(bag, slot))
          if bi and ((pass == 1 and bi == idStr) or (pass == 2 and sameID(bi, idStr))) then
            return bag, slot, key
          end
        end
      end
    end
  end
end

local function findFreeBagSlot(used)
  for bag = 0, MAXBAG do
    local n = bagNumSlots(bag)
    for slot = 1, n do
      local key = bag * 100 + slot
      if not (used and used[key]) and not bagItemLink(bag, slot) then
        return bag, slot, key
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- Read API.
-- ----------------------------------------------------------------------------
function M.CanUse()
  if usingNative() then return true end
  return NE.db ~= nil
end

function M.GetSetIDs()
  if usingNative() then return C_EquipmentSet.GetEquipmentSetIDs() or {} end
  local s = store()
  local ids = {}
  if s then
    for id in pairs(s.sets) do ids[#ids + 1] = id end
    table.sort(ids)
  end
  return ids
end

function M.GetNumSets()
  if usingNative() then return C_EquipmentSet.GetNumEquipmentSets() or 0 end
  local s = store()
  if not s then return 0 end
  local n = 0
  for _ in pairs(s.sets) do n = n + 1 end
  return n
end

function M.GetSetID(name)
  if usingNative() then return C_EquipmentSet.GetEquipmentSetID(name) end
  local s = store()
  if not s then return nil end
  for id, set in pairs(s.sets) do
    if set.name == name then return id end
  end
  return nil
end

-- name, icon, setID, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored
function M.GetSetInfo(setID)
  if usingNative() then return C_EquipmentSet.GetEquipmentSetInfo(setID) end
  local s = store()
  local set = s and s.sets[setID]
  if not set then return nil end

  local numItems, numEquipped, numInInventory, numLost, numIgnored = 0, 0, 0, 0, 0
  for slot = FIRST_SLOT, LAST_SLOT do
    if set.ignored and set.ignored[slot] then numIgnored = numIgnored + 1 end
    local want = set.items[slot]
    if want then
      numItems = numItems + 1
      local cur = slotItem(slot)
      if cur and sameID(cur, want) then
        numEquipped = numEquipped + 1
      elseif findInBags(want) then
        numInInventory = numInInventory + 1
      else
        numLost = numLost + 1
      end
    end
  end
  local isEquipped = numItems > 0 and numEquipped == numItems
  return set.name, set.icon, setID, isEquipped, numItems, numEquipped, numInInventory, numLost, numIgnored
end

function M.GetItemIDs(setID)
  if usingNative() then return C_EquipmentSet.GetItemIDs(setID) or {} end
  local s = store()
  local set = s and s.sets[setID]
  if not set then return {} end
  local ids = {}
  for slot = FIRST_SLOT, LAST_SLOT do ids[slot] = itemIDFromLink(set.items[slot] and ("item:" .. set.items[slot])) end
  return ids
end

function M.ContainsLockedItems(setID)
  if usingNative() then return C_EquipmentSet.EquipmentSetContainsLockedItems(setID) end
  return false
end

-- ----------------------------------------------------------------------------
-- Ignored-slot scratch state (mirrors C_EquipmentSet's save-ignore API).
-- ----------------------------------------------------------------------------
function M.ClearIgnored()
  if usingNative() then C_EquipmentSet.ClearIgnoredSlotsForSave(); return end
  wipe(pendingIgnored)
end
function M.IgnoreSlot(slot)
  if usingNative() then C_EquipmentSet.IgnoreSlotForSave(slot); return end
  pendingIgnored[slot] = true
end
function M.UnignoreSlot(slot)
  if usingNative() then C_EquipmentSet.UnignoreSlotForSave(slot); return end
  pendingIgnored[slot] = nil
end
function M.IsSlotIgnored(slot)
  if usingNative() then return C_EquipmentSet.IsSlotIgnoredForSave(slot) end
  return pendingIgnored[slot] == true
end
function M.GetIgnoredSlots(setID)
  if usingNative() then return C_EquipmentSet.GetIgnoredSlots(setID) or {} end
  local s = store()
  local set = s and s.sets[setID]
  local out = {}
  if set and set.ignored then
    for slot, v in pairs(set.ignored) do out[slot] = v and true or false end
  end
  return out
end
function M.LoadIgnoredFromSet(setID)
  if usingNative() then return end
  wipe(pendingIgnored)
  local s = store()
  local set = s and s.sets[setID]
  if set and set.ignored then
    for slot, v in pairs(set.ignored) do if v then pendingIgnored[slot] = true end end
  end
end
function M.SeedDefaultIgnored()
  if usingNative() then
    if C_EquipmentSet.IgnoreSlotForSave then C_EquipmentSet.IgnoreSlotForSave(4); C_EquipmentSet.IgnoreSlotForSave(19) end
    return
  end
  wipe(pendingIgnored)
  for slot in pairs(DEFAULT_IGNORED) do pendingIgnored[slot] = true end
end

-- A sensible default icon for a freshly-saved set (chest, then head, then ?).
local function defaultIcon()
  return GetInventoryItemTexture("player", 5)
      or GetInventoryItemTexture("player", 1)
      or "Interface\\Icons\\INV_Misc_QuestionMark"
end

-- ----------------------------------------------------------------------------
-- Mutations.
-- ----------------------------------------------------------------------------
function M.Create(name, icon)
  if usingNative() then C_EquipmentSet.CreateEquipmentSet(name, icon); fireChanged(); return end
  local s = store()
  if not s or not name or name == "" then return end
  local id = s.nextID
  s.nextID = id + 1
  local ignored = {}
  for slot, v in pairs(pendingIgnored) do if v then ignored[slot] = true end end
  s.sets[id] = {
    id = id, name = name,
    icon = icon or defaultIcon(),
    items = snapshotGear(ignored),
    ignored = ignored,
  }
  fireChanged()
end

function M.Save(setID, icon)
  if usingNative() then C_EquipmentSet.SaveEquipmentSet(setID, icon); fireChanged(); return end
  local s = store()
  local set = s and s.sets[setID]
  if not set then return end
  local ignored = {}
  for slot, v in pairs(pendingIgnored) do if v then ignored[slot] = true end end
  set.items = snapshotGear(ignored)
  set.ignored = ignored
  if icon then set.icon = icon end
  fireChanged()
end

function M.Modify(setID, newName, newIcon)
  if usingNative() then C_EquipmentSet.ModifyEquipmentSet(setID, newName, newIcon); fireChanged(); return end
  local s = store()
  local set = s and s.sets[setID]
  if not set then return end
  if newName and newName ~= "" then set.name = newName end
  if newIcon then set.icon = newIcon end
  fireChanged()
end

function M.Delete(setID)
  if usingNative() then C_EquipmentSet.DeleteEquipmentSet(setID); fireChanged(); return end
  local s = store()
  if s and s.sets[setID] then
    s.sets[setID] = nil
    fireChanged()
  end
end

-- ----------------------------------------------------------------------------
-- Equip a set (CUSTOM backend) — ItemRack physical-swap model.
-- Out-of-combat only; equips are restricted in combat. A lock watcher runs further
-- passes as item locks clear so multi-swaps (and the 2H→offhand clear) settle.
-- ----------------------------------------------------------------------------
local pendingEquipName       -- name of the set mid-swap (lock watcher target)
local pendingEquipSetID      -- combat-queued equip
local activeSetID            -- last requested set id (for "is equipped" hints)

local function anythingLocked()
  for i = 1, NUM_SLOTS do
    if IsInventoryItemLocked(i) then return true end
  end
  for bag = 0, MAXBAG do
    local n = bagNumSlots(bag)
    for slot = 1, n do
      if select(3, GetContainerItemInfo(bag, slot)) then return true end
    end
  end
  return false
end

local function swapBagToSlot(bag, slot, invSlot)
  if CursorHasItem() or SpellIsTargeting() then return false end
  ClearCursor()
  PickupContainerItem(bag, slot)
  PickupInventoryItem(invSlot)
  return true
end

-- One pass of the swap for a set. Returns the number of swaps issued.
local function doPass(set)
  if not set or anythingLocked() then return 0 end
  local used, swaps = {}, 0
  for invSlot = FIRST_SLOT, LAST_SLOT do
    if not (set.ignored and set.ignored[invSlot]) then
      local target = set.items[invSlot]
      if target and not sameID(slotItem(invSlot), target) then
        local bag, slot = findInBags(target, used)
        if bag then
          -- 2H into main hand: clear the off-hand into a free bag slot first.
          if invSlot == 16 then
            local eloc = select(9, GetItemInfo(bagItemLink(bag, slot) or ""))
            if eloc == "INVTYPE_2HWEAPON" and GetInventoryItemLink("player", 17) then
              local fb, fs, fk = findFreeBagSlot(used)
              if fb and not CursorHasItem() then
                ClearCursor(); PickupInventoryItem(17); PickupContainerItem(fb, fs)
                used[fk] = 1
              end
            end
          end
          if swapBagToSlot(bag, slot, invSlot) then
            used[bag * 100 + slot] = 1
            swaps = swaps + 1
          end
        end
      end
    end
  end
  return swaps
end

local function doEquipCustom(setID)
  local s = store()
  local set = s and s.sets[setID]
  if not set then return end
  activeSetID = setID
  pendingEquipName = set.name
  doPass(set)          -- first pass; lock watcher finishes the rest
end

function M.Use(setID)
  if usingNative() then
    C_EquipmentSet.UseEquipmentSet(setID)
    return
  end
  if InCombatLockdown() then
    pendingEquipSetID = setID
    if UIErrorsFrame then
      UIErrorsFrame:AddMessage(ERR_NOT_IN_COMBAT or "Can't do that in combat", 1.0, 0.1, 0.1, 1.0)
    end
    return
  end
  doEquipCustom(setID)
  ClearCursor()
  fireSwap(true, setID)
  fireChanged()
end

-- Put a set on the cursor (drop on an action bar for a one-click equip). Native
-- only; the custom backend has no engine cursor type for this.
function M.Pickup(setID)
  if usingNative() and C_EquipmentSet.PickupEquipmentSet then
    C_EquipmentSet.PickupEquipmentSet(setID)
    return true
  end
  return false
end

function M.IsEquipped(setID)
  local _, _, _, eq = M.GetSetInfo(setID)
  return eq and true or false
end

-- ----------------------------------------------------------------------------
-- Event plumbing.
--   * lock watcher (ITEM_LOCK_CHANGED): run further custom swap passes.
--   * PLAYER_REGEN_ENABLED: flush a combat-queued custom equip.
--   * BAG_UPDATE / PLAYER_EQUIPMENT_CHANGED: keep the pane's live colouring fresh.
--   * EQUIPMENT_SETS_CHANGED / EQUIPMENT_SWAP_FINISHED: relay native engine events.
-- ----------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ITEM_LOCK_CHANGED")
ev:RegisterEvent("PLAYER_EQUIPMENT_CHANGED")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("EQUIPMENT_SETS_CHANGED")
ev:RegisterEvent("EQUIPMENT_SWAP_FINISHED")
ev:SetScript("OnEvent", function(_, event, ...)
  if event == "ITEM_LOCK_CHANGED" then
    if pendingEquipName and not usingNative() and not anythingLocked() then
      local s = store()
      local set = s and s.sets[activeSetID]
      if set and set.name == pendingEquipName then
        local swaps = doPass(set)
        if swaps == 0 then
          pendingEquipName = nil
          fireSwap(true, activeSetID)
          fireChanged()
        end
      else
        pendingEquipName = nil
      end
    end
    return
  end
  if event == "PLAYER_REGEN_ENABLED" then
    if pendingEquipSetID and not usingNative() then
      local id = pendingEquipSetID
      pendingEquipSetID = nil
      M.Use(id)
    end
    return
  end
  if event == "EQUIPMENT_SWAP_FINISHED" then
    local result, name = ...
    -- native passes a name; map to our synthesised id when possible.
    local sid = name and M.GetSetID(name) or nil
    fireSwap(result, sid)
    fireChanged()
    return
  end
  -- EQUIPMENT_SETS_CHANGED / PLAYER_EQUIPMENT_CHANGED / BAG_UPDATE.
  fireChanged()
end)

log("equipment-set backend = " .. (usingNative() and "NATIVE" or "CUSTOM"))
