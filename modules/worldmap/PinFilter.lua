-- DragonUI_NewEra/modules/worldmap/PinFilter.lua — the map's filter button and what it switches.
--
-- WHAT THIS IS AND IS NOT. It is the filter mechanism: a registry of togglable categories, the round
-- button at the canvas's top-right that the `Map-Filter-Button` art was shipped for, the menu behind
-- it, and persistence. It is NOT the dungeon-and-raid pin data — that turned out to have no
-- trustworthy source on this client (AreaPOI.dbc carries 738 rows and exactly one names an instance;
-- the HD map patch adds two dungeon-entrance map areas, not a set) and inventing eighty coordinates
-- from memory is not a thing worth doing. The registry is the part that lets those slot in later
-- without touching this file: see PF.Register.
--
-- EVERY TOGGLE HERE DRIVES A FEATURE THAT ALREADY EXISTS, which is the reason there are three of them
-- and not a dozen. A filter menu whose entries do nothing is worse than no filter menu, and the same
-- goes for a category with no data behind it — so nothing is listed that cannot be switched.
--
-- WHY LANDMARKS ARE RE-HIDDEN EVERY REFRESH rather than hidden once: the client rebuilds and re-shows
-- `WorldMapFramePOI1..N` on every map update, so a single Hide() lasts until the next one. This
-- re-applies on the same OnMapChanged chain the pins, fog and breadcrumb already run on, which is
-- exactly when the client has finished laying them out.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap

local PF = {}
WM.filter = PF

-- ----------------------------------------------------------------------------
-- The registry
-- ----------------------------------------------------------------------------

-- Categories in menu order. Each is { key, label, get, set }, where get/set talk to whichever module
-- actually owns the behaviour — this file stores nothing itself, so there is no second copy of the
-- state to drift out of step with the feature.
local categories = {}
PF.categories = categories

function PF.Register(key, label, get, set)
  if type(key) ~= "string" or type(get) ~= "function" or type(set) ~= "function" then return end
  for _, c in ipairs(categories) do
    if c.key == key then
      c.label, c.get, c.set = label or c.label, get, set
      return c
    end
  end
  local c = { key = key, label = label or key, get = get, set = set }
  categories[#categories + 1] = c
  return c
end

function PF.Get(key)
  for _, c in ipairs(categories) do
    if c.key == key then
      local ok, v = pcall(c.get)
      return ok and v and true or false
    end
  end
  return nil
end

function PF.Set(key, on)
  for _, c in ipairs(categories) do
    if c.key == key then
      pcall(c.set, on and true or false)
      return true
    end
  end
  return false
end

function PF.Toggle(key)
  local v = PF.Get(key)
  if v == nil then return false end
  return PF.Set(key, not v)
end

-- ----------------------------------------------------------------------------
-- Saved state
-- ----------------------------------------------------------------------------

local function store()
  if not NE.db then return nil end
  NE.db.worldmap = NE.db.worldmap or {}
  NE.db.worldmap.poiFilters = NE.db.worldmap.poiFilters or {}
  return NE.db.worldmap.poiFilters
end
PF._Store = store

-- Default ON. A filter the player has never touched should show everything; an unset key must not
-- read as "hidden" or the map comes up empty on a fresh profile.
local function saved(key)
  local db = store()
  if not db then return true end
  if db[key] == nil then return true end
  return db[key] and true or false
end

local function save(key, on)
  local db = store()
  if db then db[key] = on and true or false end
end

PF._Saved, PF._Save = saved, save

-- ----------------------------------------------------------------------------
-- Landmarks
-- ----------------------------------------------------------------------------

-- The client's own map pins: flight points, towns, PvP objectives. Verified against this client
-- rather than assumed — a `/neworldmap pins` dump in Howling Fjord returns five landmarks, all
-- settlements, and Utgarde Keep (which is in that zone) is not among them. There are no dungeon
-- entrances in here to filter, which is why this is one toggle and not a set of categories.
function PF.ApplyLandmarks()
  local show = saved("landmarks")
  local i = 1
  while true do
    local b = _G["WorldMapFramePOI" .. i]
    if not b then break end
    -- Only the ones the client has actually placed for this map: the rest are pooled leftovers it
    -- has already hidden, and showing those would put stale pins back on the map.
    if show then
      if b._neFilterHidden then
        b._neFilterHidden = nil
        if b.Show then b:Show() end
      end
    elseif b:IsShown() then
      b._neFilterHidden = true
      if b.Hide then b:Hide() end
    end
    i = i + 1
  end
end

-- ----------------------------------------------------------------------------
-- Built-in categories
-- ----------------------------------------------------------------------------

local function registerBuiltins()
  -- Quest objectives. Retail's filter menu leads with this one, and it is genuinely the client's own
  -- switch — WM.SetQuestObjectives persists it, flips the client's toggle and re-runs the update.
  if WM.SetQuestObjectives and WM.QuestObjectivesShown then
    PF.Register("questObjectives", _G.SHOW_QUEST_OBJECTIVES_ON_MAP_TEXT or "Quest Objectives",
      function() return WM.QuestObjectivesShown() end,
      function(on) WM.SetQuestObjectives(on) end)
  end

  PF.Register("landmarks", _G.MINIMAP_TRACKING_TARGET or "Map Landmarks",
    function() return saved("landmarks") end,
    function(on)
      save("landmarks", on)
      PF.ApplyLandmarks()
    end)

  -- Explored-area overlays. FogClear already gates its own redraw on FOG.enabled, so this switches
  -- that flag and asks it to redraw or clear — the module keeps owning the behaviour.
  local fog = WM.fog
  if fog and fog.Refresh and fog.Restore then
    PF.Register("fog", _G.WORLD_MAP_FILTER_SHOW_EXPLORED or "Explored Areas",
      function() return saved("fog") end,
      function(on)
        save("fog", on)
        fog.enabled = on and true or false
        if on then pcall(fog.Refresh) else pcall(fog.Restore) end
      end)
  end
end

-- ----------------------------------------------------------------------------
-- The menu
-- ----------------------------------------------------------------------------

function PF.MenuList()
  local list = {
    { text = _G.FILTER or "Filter", isTitle = true, notCheckable = true },
  }
  for _, c in ipairs(categories) do
    local key = c.key
    list[#list + 1] = {
      text = c.label,
      checked = function() return PF.Get(key) end,
      keepShownOnClick = true,
      func = function()
        PF.Set(key, not PF.Get(key))
        if WM.OnMapChanged then pcall(WM.OnMapChanged) end
      end,
    }
  end
  return list
end

function PF.OpenMenu(anchor)
  local nb = NE.navbar
  if nb and nb.OpenMenu then
    nb.OpenMenu(anchor or PF.button, PF.MenuList())
    return true
  end
  return false
end

-- ----------------------------------------------------------------------------
-- The button
-- ----------------------------------------------------------------------------

local SIZE = 32

-- Anchored to the ZOOM VIEWPORT when there is one, because that frame is exactly the canvas rect and
-- therefore tracks every resize for free. Parented to the WINDOW either way — a child of the
-- viewport would be clipped and magnified along with the map, which is the last thing a control
-- should do.
local function anchorTo()
  return _G.NE_WorldMapViewport or _G.WorldMapDetailFrame
end

function PF.Build(parent)
  if PF.button then return PF.button end
  parent = parent or WM.frame
  if not (parent and CreateFrame) then return nil end

  local b = CreateFrame("Button", "NE_WorldMapFilterButton", parent)
  b:SetSize(SIZE, SIZE)
  -- Above the canvas by LEVEL, not by parentage: a child does not reliably outrank its parent for
  -- draw order or mouse input on this client, which is the fault every control in this window has
  -- hit at least once.
  if b.SetFrameLevel then b:SetFrameLevel((parent:GetFrameLevel() or 1) + 20) end

  local rel = anchorTo()
  if rel then
    b:SetPoint("TOPRIGHT", rel, "TOPRIGHT", -4, -4)
  else
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -60, -30)
  end

  b:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
  local nt = b:GetNormalTexture()
  if nt and nt.SetAllPoints then nt:SetAllPoints(b) end
  -- LOWERCASE. The atlas keys in this addon are lowercase, and asking for "Map-Filter-Button" simply
  -- missed -- the SetAtlas call is pcall'd, so it failed silently and left the seed texture, which
  -- is why the button first drew as a Blizzard panel button. Recorded on the texture so the
  -- diagnostic can report whether the art actually landed rather than leaving it to the eye.
  if nt and NE.tex and NE.tex.SetAtlas then
    -- SetAtlas RETURNS whether it found the entry, and that return is the only honest signal. The
    -- first version recorded `nt._neAtlas` instead, which belongs to the status-bar helper and is
    -- never set here -- so the diagnostic reported "NOT APPLIED" for art that was on screen.
    local okCall, applied = pcall(NE.tex.SetAtlas, nt, "map-filter-button", false)
    b._neAtlasApplied = (okCall and applied) and "map-filter-button" or nil
  end

  b:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
  local pt = b:GetPushedTexture()
  if pt and pt.SetAllPoints then pt:SetAllPoints(b) end
  if pt and NE.tex and NE.tex.SetAtlas then
    pcall(NE.tex.SetAtlas, pt, "map-filter-button-down", false)
  end

  b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight")
  local ht = b:GetHighlightTexture()
  if ht and ht.SetAllPoints then ht:SetAllPoints(b) end

  b:RegisterForClicks("LeftButtonUp")
  b:SetScript("OnClick", function(self) PF.OpenMenu(self) end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(_G.FILTER or "Filter")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  PF.button = b
  return b
end

-- Re-anchored on every layout pass: the viewport is rebuilt and resized as the window changes, and
-- the button has to follow the canvas's corner rather than the window's.
function PF.Relayout()
  local b = PF.button
  if not b then return end
  local rel = anchorTo()
  if not rel then return end
  b:ClearAllPoints()
  b:SetPoint("TOPRIGHT", rel, "TOPRIGHT", -4, -4)
end

-- ----------------------------------------------------------------------------
-- Arming
-- ----------------------------------------------------------------------------

function PF.Arm()
  if PF._armed then return end
  PF._armed = true

  registerBuiltins()

  -- Reconcile the saved state into the modules that own it, once, before anything draws. Without
  -- this a filter switched off last session comes back on until the player opens the menu.
  local fog = WM.fog
  if fog then fog.enabled = saved("fog") end

  PF.Build(WM.frame)
  PF.Relayout()
  PF.ApplyLandmarks()

  -- Chained onto whatever the other modules already registered rather than replacing it: every one
  -- of them wants this signal, and the last file to load must not silently win.
  local prev = WM.OnMapChanged
  WM.OnMapChanged = function()
    if prev then pcall(prev) end
    PF.Relayout()
    PF.ApplyLandmarks()
  end
end
