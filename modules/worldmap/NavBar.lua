-- DragonUI_NewEra/modules/worldmap/NavBar.lua — the world map's breadcrumb.
--
-- DOWNPORT of NewEra/WorldMap/NavBar.lua. The 1.15 source is fifteen lines of real work wrapped in
-- a comment, because Era ships `NavBarTemplate` in FrameXML byte-identical to retail's — it just
-- instantiates one, anchors it, and points it at `WorldMapFrame:SetMapID`. 3.3.5a ships nothing, so
-- the WIDGET is rebuilt — but not here. It lives in **core/NavBar.lua**, shared with the Adventure
-- Guide, and this file is only the MODEL: what the trail says, and what clicking a crumb does.
--
-- (It did not start that way. This module first carried its own copy of the widget, and that copy
-- promptly re-introduced two faults the Adventure Guide's version had already fixed and documented
-- thirty lines away — Home sitting on top of the window's portrait, and crumbs drawn underneath
-- their own bar's regions. The owner asked whether the two should be one implementation; they
-- should, and now are.)
--
-- THE MODEL IS THIS CLIENT'S: `GetMapContinents()` / `GetMapZones(c)` / `SetMapZoom(c, z)` /
-- `GetCurrentMapContinent()` / `GetCurrentMapZone()`. The trail it produces is
--
--     [ World ] > [ Northrend ▾ ] > [ Dalaran ] > [ Dalaran City ▾ ]
--
-- which replaces the three dropdowns and the zoom-out button the chrome squelches.
--
-- DUNGEON FLOORS ARE NATIVE HERE. Era's instance uiMaps carry no art, which is why the 1.15 source
-- ships six hundred lines of tile-overlay workaround (DungeonMap.lua / DungeonMaps.lua). This
-- client renders floors itself — `GetNumDungeonMapLevels` / `SetDungeonMapLevel` /
-- `GetCurrentMapDungeonLevel` — so they are simply one more crumb, and none of that is ported.
--
-- INDEX 0 IS NOT A CONTINENT. `GetCurrentMapContinent()` returns 0 for the world view and
-- `GetCurrentMapZone()` returns 0 for "no zone selected". Both also shift while the player is
-- inside an instance or on a battleground map, so every call here is pcall'd and 0 is read as
-- "not selected" rather than as an index — CONTRACTS.md §0.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap

-- Retail's band geometry, relative to the map's title/canvas spacer.
local BAR_H       = 34
local BAR_Y       = -23
-- 59 from the spacer, which itself starts 2 inside the frame, puts the trail at x=61 — clear of the
-- round portrait, which reaches out to about x=54 from the window's top-left corner. The Adventure
-- Guide found this first ("a 14px navbar start sat the Home crumb text right on top of that icon
-- art"); this module found it a second time by shipping 10 and being told.
local BAR_INSET_L = 59
local BAR_INSET_R = 10

-- ----------------------------------------------------------------------------
-- The map model
-- ----------------------------------------------------------------------------

-- pcall's results are passed straight through rather than packed: packing LOSES ARITY, because
-- `#{ pcall(f) }` stops at the first nil and this client's getters have holes in the middle of
-- their return lists.
local function stripOk(ok, ...)
  if not ok then return nil end
  return ...
end

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  return stripOk(pcall(fn, ...))
end

-- These two return a VARARG list of names, so the results ARE packed and the success flag stripped.
local function packedCall(fn, ...)
  if type(fn) ~= "function" then return {} end
  local r = { pcall(fn, ...) }
  if not r[1] then return {} end
  table.remove(r, 1)
  return r
end

local function continentNames() return packedCall(_G.GetMapContinents) end

local function zoneNames(continent)
  if not continent or continent <= 0 then return {} end
  return packedCall(_G.GetMapZones, continent)
end

local function currentContinent()
  local c = safe(_G.GetCurrentMapContinent)
  return type(c) == "number" and c or 0
end

local function currentZone()
  local z = safe(_G.GetCurrentMapZone)
  return type(z) == "number" and z or 0
end

local function setZoom(continent, zone)
  if type(_G.SetMapZoom) ~= "function" then return end
  pcall(_G.SetMapZoom, continent, zone)

  -- Tell ModernMapMarkers the map moved.
  --
  -- It redraws off WORLD_MAP_UPDATE and short-circuits when the continent and zone it last drew for
  -- are unchanged — and its own throttle can swallow the event that would have told it, leaving the
  -- PREVIOUS zone's markers sitting on the new map (a Deadmines pin in Hillsbrad). `ForceRedraw`
  -- exists for exactly this: it clears the pair so the next update passes.
  --
  -- This is not a guess about its internals. Its own `NavigateToTransportDest` pairs SetMapZoom with
  -- ForceRedraw in this order, so it is that addon's own idiom for "I moved the map myself" — and
  -- our breadcrumb moves the map the same way its transport popup does. Costs nothing when it is
  -- not installed.
  if _G.MMM and _G.MMM.ForceRedraw then pcall(_G.MMM.ForceRedraw) end
end

-- Floor labels. This client keys them off the map's art token — DUNGEON_FLOOR_DALARAN1 and friends
-- — with a numbered fallback for floors it has no string for.
local function floorLabel(index)
  local token = safe(_G.GetMapInfo)
  if type(token) == "string" then
    local s = _G["DUNGEON_FLOOR_" .. token:upper() .. index]
    if s then return s end
  end
  if _G.FLOOR_NUMBER then
    local ok, s = pcall(string.format, _G.FLOOR_NUMBER, index)
    if ok and s then return s end
  end
  return tostring(index)
end

local function numFloors()
  local n = safe(_G.GetNumDungeonMapLevels)
  return type(n) == "number" and n or 0
end

local function currentFloor()
  local n = safe(_G.GetCurrentMapDungeonLevel)
  return type(n) == "number" and n or 0
end

-- The trail for whatever the map is currently showing. Entry 1 is always Home; core/NavBar.lua
-- owns everything past that.
-- Every dungeon we have floor data for, as a nested menu off Home. `menuList` + `hasArrow` is
-- EasyMenu's own submenu shape; sixty-odd entries is a long list, but it is one the player scans
-- alphabetically rather than reads, and grouping it by expansion would need data the floor table
-- does not carry.
local function dungeonMenu()
  local D = WM.dungeon
  if not (D and D.List) then return nil end
  local list = {}
  for _, folder in ipairs(D.List()) do
    list[#list + 1] = { text = folder, notCheckable = true,
                        func = function() D.Show(folder) end }
  end
  if #list == 0 then return nil end
  return list
end

local function buildTrail()
  local trail = {}
  local worldId = _G.WORLDMAP_WORLD_ID or 0
  local D = WM.dungeon

  -- Home is the world view, and its own menu lists every continent — so the whole map is one click
  -- away from anywhere, which is the job the squelched zoom-out button used to do.
  trail[#trail + 1] = {
    name    = _G.WORLD or "World",
    OnClick = function()
      if D and D.Dismiss then D.Dismiss() end
      setZoom(worldId)
    end,
    listFunc = function()
      local list = {}
      for i, name in ipairs(continentNames()) do
        list[#list + 1] = { text = name, notCheckable = true,
                            func = function()
                              if D and D.Dismiss then D.Dismiss() end
                              setZoom(i)
                            end }
      end
      -- The client cannot navigate to a dungeon map -- SetMapZoom has no entries for them, and it
      -- only ever shows one while the player is standing in it. This is the way in.
      local dungeons = dungeonMenu()
      if dungeons then
        list[#list + 1] = { text = _G.DUNGEONS or "Dungeons", notCheckable = true,
                            hasArrow = true, menuList = dungeons }
      end
      return list
    end,
  }

  -- A dungeon is showing: the trail describes IT, not whatever zone is underneath.
  if D and D.IsShowing and D.IsShowing() then
    local floors = D.Floors(D.folder) or {}
    trail[#trail + 1] = {
      name    = D.folder,
      OnClick = function() end,
      listFunc = #floors > 1 and function()
        local list = {}
        for _, fl in ipairs(floors) do
          list[#list + 1] = { text = (_G.FLOOR_NUMBER and _G.FLOOR_NUMBER:format(fl)) or tostring(fl),
                              notCheckable = true,
                              func = function() D.Show(D.folder, fl) end }
        end
        return list
      end or nil,
    }
    return trail
  end

  local c = currentContinent()
  if c <= 0 then return trail end
  local cName = continentNames()[c]
  if not cName then return trail end

  trail[#trail + 1] = {
    name    = cName,
    OnClick = function() setZoom(c) end,
    listFunc = function()
      local list = {}
      for i, name in ipairs(zoneNames(c)) do
        list[#list + 1] = { text = name, notCheckable = true, func = function() setZoom(c, i) end }
      end
      return list
    end,
  }

  local z = currentZone()
  if z <= 0 then return trail end
  local zName = zoneNames(c)[z]
  if not zName then return trail end

  trail[#trail + 1] = { name = zName, OnClick = function() setZoom(c, z) end }

  -- Floors, when the map showing has them.
  local floors = numFloors()
  if floors > 1 then
    local here = currentFloor()
    trail[#trail + 1] = {
      name    = floorLabel(here > 0 and here or 1),
      OnClick = function() end,
      listFunc = function()
        local list = {}
        for i = 1, floors do
          list[#list + 1] = { text = floorLabel(i), notCheckable = true,
                              func = function()
                                if type(_G.SetDungeonMapLevel) == "function" then
                                  pcall(_G.SetDungeonMapLevel, i)
                                end
                              end }
        end
        return list
      end,
    }
  end

  return trail
end
WM.BuildNavTrail = buildTrail   -- test seam: the trail is assertable without building a widget

-- ----------------------------------------------------------------------------
-- Build
-- ----------------------------------------------------------------------------

function WM.BuildNavBar()
  local f = WM.frame
  local spacer = WM.spacer
  if not (f and spacer and NE.navbar and NE.navbar.Create) then return f and f._neNavBar end
  if f._neNavBar then return f._neNavBar end

  local host = WM.border or f
  local bar = NE.navbar.Create(host, {
    name       = "NE_WorldMapNavBar",
    height     = BAR_H,
    frameLevel = (host:GetFrameLevel() or 1) + 3,
    trailFunc  = buildTrail,
    -- Declared, not measured. The bar is pinned left and right into the spacer and so has no width
    -- of its own, and an anchored rect on this client lags a resize by a layout pass — which left
    -- the backing plate at the PREVIOUS window's size every time the map changed size: a black band
    -- running out past the window's right edge after minimising, and stopping short of it after
    -- maximising. This window's entire geometry is derived from one number, so that number is the
    -- honest answer, and it is right mid-drag too (it carries the drag's transient width).
    widthFunc = function()
      local canvasW = WM.CurrentCanvasWidth and WM.CurrentCanvasWidth() or 0
      return math.floor(canvasW + 0.5) - BAR_INSET_L - BAR_INSET_R
    end,
  })
  bar:SetPoint("TOPLEFT",  spacer, "TOPLEFT",   BAR_INSET_L, BAR_Y)
  bar:SetPoint("TOPRIGHT", spacer, "TOPRIGHT", -BAR_INSET_R, BAR_Y)

  f._neNavBar = bar
  WM.navbar = bar

  -- Re-fit whenever the window resizes (maximize, or the side panel opening). WorldMap.lua calls
  -- OnGeometryChanged at the tail of every geometry pass. Chained onto whatever is already
  -- registered rather than replacing it — the last file to load must not silently win.
  local prevGeom = WM.OnGeometryChanged
  WM.OnGeometryChanged = function(frame)
    if prevGeom then pcall(prevGeom, frame) end
    bar:Relayout()
  end

  -- And whenever the map itself changes: WorldMap.lua calls OnMapChanged from its
  -- WorldMapFrame_Update hook, which fires on every SetMapZoom and zone change.
  local prevMap = WM.OnMapChanged
  WM.OnMapChanged = function()
    if prevMap then pcall(prevMap) end
    bar:Refresh()
  end

  -- Every time the map opens. Cheap, and it is the one moment the player is certainly looking at
  -- the bar, so a trail that somehow missed a refresh corrects itself rather than staying wrong.
  f:HookScript("OnShow", function() bar:Refresh() end)

  bar:Relayout()
  return bar
end

function WM.RefreshNavBar()
  if WM.navbar then WM.navbar:Refresh() end
end
