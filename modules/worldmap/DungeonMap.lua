-- DragonUI_NewEra/modules/worldmap/DungeonMap.lua — browse a dungeon's floor maps from anywhere.
--
-- DOWNPORT of NewEra/WorldMap/DungeonMap.lua, and one of the few places where the 1.15 source's
-- technique transfers exactly even though its REASON does not.
--
-- Era needs it because its instance uiMaps carry no art at all: `WorldMapFrame:SetMapID(<dungeon>)`
-- shows nothing, so the source renders the classic tilesets by hand. This client renders instance
-- floors perfectly well — `GetNumDungeonMapLevels` / `SetDungeonMapLevel`, and the breadcrumb
-- already drives them — but ONLY while the player is standing inside the instance. The map switches
-- to them through SetMapToCurrentZone; `SetMapZoom(continent, zone)` has no dungeon entries, so
-- there is no way to look at Ulduar's map from Stormwind.
--
-- So the same overlay does a different job here: not "render art the client lacks" but "render art
-- the client will not show you from outside".
--
-- HOW THE TILES ARE LAID OUT. Same grid the engine uses for every map: 4 columns x 3 rows of 256px
-- tiles, ROW-MAJOR, index (row-1)*4 + col. That covers 1024x768 against a 1002x668 canvas, so the
-- right and bottom edges are clipped — which is what the client does too.
--
-- THE FILENAME IS PROBED, NOT DERIVED. A zone's tiles are `<Folder><1..12>`; a multi-floor dungeon's
-- are `<Folder><floor>_<1..12>`; and some single-floor dungeons use the zone form despite having a
-- floor row in DungeonMap.dbc. Rather than encode a rule and then a list of exceptions to it, both
-- forms are tried with SetTexture and whichever RESOLVES is kept — `GetTexture()` comes back nil for
-- a path the client cannot find, which is an existence check that cannot be wrong. (The same trick
-- the 1.15 source used to discover its own table, run per-dungeon instead of once by a human.)
--
-- ISOLATION. The overlay is a frame parented to WorldMapDetailFrame that fully covers it, draws
-- opaque and swallows mouse and wheel. It touches none of the canvas's own scale, anchor or POI
-- machinery, so showing a dungeon map cannot break normal map navigation and hiding it restores the
-- map exactly. Nothing here is protected and nothing is combat-gated.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap

local D = {}
WM.dungeon = D

local TILE   = 256
local COLS, ROWS = 4, 3

-- Folders that have a DungeonMap.dbc row but are not dungeons — the world map itself is one. Listing
-- them would put "Azeroth" in the dungeon menu, and picking it would draw the world map over the
-- world map.
local NOT_A_DUNGEON = { Azeroth = true, Kalimdor = true, Expansion01 = true, Northrend = true }

-- ----------------------------------------------------------------------------
-- Tile naming
-- ----------------------------------------------------------------------------

-- One texture, reused, purely to ask the client whether a path resolves.
local probe

-- Does this texture path exist?
--
-- `GetTexture() ~= nil` is NOT the check, and that was a real bug: when SetTexture is given a path
-- the client cannot find, it FAILS QUIETLY and the texture keeps whatever it had before. On a
-- reused probe that means the previous dungeon's path is still sitting there, GetTexture returns
-- non-nil, and every path on earth reports as existing -- so the wrong tile form gets chosen and
-- the wrong art is asked for.
--
-- Comparing the resolved path to the one asked for is the check that actually holds. Case-folded,
-- because the client normalises separators and case on the way in.
local function normalise(p)
  if type(p) ~= "string" then return nil end
  return p:lower():gsub("/", "\\")
end

local function fileExists(path)
  if not probe then
    probe = UIParent:CreateTexture(nil, "BACKGROUND")
    probe:Hide()
  end
  -- Cleared to a known-good path first, so a stale value can never be mistaken for a hit: if the
  -- path under test fails, GetTexture still reports THIS one, which will not compare equal.
  probe:SetTexture("Interface\\Buttons\\WHITE8X8")
  probe:SetTexture(path)
  local got = normalise(probe:GetTexture())
  local want = normalise(path)
  return got ~= nil and want ~= nil and got:find(want, 1, true) ~= nil
end
D._FileExists = fileExists

-- The two conventions, in the order worth trying: a dungeon with more than one floor is almost
-- always the underscored form, and a single-floor one almost always is not.
local function tilePath(folder, floor, index, underscored)
  local base = "Interface\\WorldMap\\" .. folder .. "\\" .. folder
  if underscored then
    return base .. floor .. "_" .. index
  end
  return base .. index
end

-- Which form this dungeon's floor uses, cached per folder+floor because the answer never changes
-- and the probe costs a texture load.
local formCache = {}

local function resolveForm(folder, floor)
  local key = folder .. ":" .. floor
  local cached = formCache[key]
  if cached ~= nil then return cached end
  local form = nil
  if fileExists(tilePath(folder, floor, 1, true)) then
    form = true
  elseif fileExists(tilePath(folder, floor, 1, false)) then
    form = false
  end
  formCache[key] = form == nil and false or form
  if form == nil then formCache[key] = nil end   -- unresolved: do not cache a wrong answer
  return form
end
D._ResolveForm = resolveForm

-- ----------------------------------------------------------------------------
-- The overlay
-- ----------------------------------------------------------------------------

local function build()
  if D.frame then return D.frame end
  local detail = _G.WorldMapDetailFrame
  if not detail then return nil end

  -- Parented to the detail frame so it inherits the canvas scale for free: the chrome scales that
  -- frame rather than resizing it, so a child laid out in its 1002x668 units is correct at every
  -- window size with no arithmetic of our own.
  local f = CreateFrame("Frame", "NE_WorldMapDungeonOverlay", detail)
  f:SetAllPoints(detail)
  f:SetFrameLevel((detail:GetFrameLevel() or 1) + 10)
  f:EnableMouse(true)        -- opaque: clicks must not fall through to the zone map underneath
  f:EnableMouseWheel(true)
  f:Hide()

  -- An opaque backing, so whatever the tiles do not cover reads as the dungeon's own dark ground
  -- rather than as the world map showing through the gaps.
  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints(f)
  f.bg:SetTexture(0, 0, 0, 1)

  f.tiles = {}
  for row = 1, ROWS do
    for col = 1, COLS do
      local i = (row - 1) * COLS + col
      local t = f:CreateTexture(nil, "ARTWORK")
      t:SetSize(TILE, TILE)
      t:SetPoint("TOPLEFT", f, "TOPLEFT", (col - 1) * TILE, -(row - 1) * TILE)
      f.tiles[i] = t
    end
  end

  D.frame = f
  return f
end

-- ----------------------------------------------------------------------------
-- Public
-- ----------------------------------------------------------------------------

-- Every folder we have floor data for that actually looks like a dungeon, sorted. Not filtered on
-- the tiles resolving: that would probe 66 dungeons' worth of textures to build a menu, and a
-- dungeon whose art is missing simply draws nothing when picked.
function D.List()
  local out = {}
  for folder in pairs(WM.dungeonFloors or {}) do
    if not NOT_A_DUNGEON[folder] then out[#out + 1] = folder end
  end
  table.sort(out)
  return out
end

function D.Floors(folder)
  return (WM.dungeonFloors or {})[folder]
end

function D.IsShowing()
  return D.frame ~= nil and D.frame:IsShown()
end

function D.Show(folder, floor)
  if not (WM.dungeonFloors and WM.dungeonFloors[folder]) then return false end
  local f = build()
  if not f then return false end

  local floors = WM.dungeonFloors[folder]
  if not (floors and floors[1]) then return false end   -- no floors is not a dungeon we can draw
  floor = floor or D.floor
  -- A floor from the previous dungeon is meaningless here; fall back to its first.
  local valid = false
  for _, fl in ipairs(floors) do
    if fl == floor then valid = true; break end
  end
  if not valid then floor = floors[1] end

  D.folder, D.floor = folder, floor

  local underscored = resolveForm(folder, floor)
  D.form = underscored
  local drawn = 0
  for i = 1, COLS * ROWS do
    local t = f.tiles[i]
    t:SetTexture(nil)
    if underscored == nil then
      t:Hide()
    else
      local path = tilePath(folder, floor, i, underscored)
      t:SetTexture(path)
      -- Compared, not merely non-nil, for the same reason fileExists is: a failed SetTexture leaves
      -- the previous art in place, and a pooled tile's previous art is the LAST DUNGEON'S. That is
      -- how asking for one dungeon can put another one on the screen.
      local got = normalise(t:GetTexture())
      local want = normalise(path)
      if got and want and got:find(want, 1, true) then
        t:Show(); drawn = drawn + 1
      else
        t:SetTexture(nil)
        t:Hide()
      end
    end
  end
  D.tilesDrawn = drawn

  -- Nothing resolved: do not put an empty black plate over a perfectly good map and call it a
  -- dungeon. Say so instead -- a silent no-op here reads as "the map broke".
  if drawn == 0 then
    D.folder, D.floor = nil, nil
    f:Hide()
    if NE.Log then NE.Log("WORLDMAP", "no tiles for dungeon " .. tostring(folder)) end
    if UIErrorsFrame then
      UIErrorsFrame:AddMessage("No map art for " .. tostring(folder), 1.0, 0.3, 0.3, 1.0)
    end
    return false
  end

  f:Show()
  if WM.OnMapChanged then pcall(WM.OnMapChanged) end   -- the breadcrumb re-reads the trail
  -- Covering the canvas is a map change as far as a neighbour is concerned; leaving its pins on top
  -- of a dungeon they have nothing to do with is worse than having none.
  if _G.MMM and _G.MMM.ForceRedraw then pcall(_G.MMM.ForceRedraw) end
  return drawn > 0
end

function D.Hide()
  if not D.frame then return end
  D.frame:Hide()
  D.folder, D.floor, D.tilesDrawn = nil, nil, nil
  if WM.OnMapChanged then pcall(WM.OnMapChanged) end
end

-- Leaving the dungeon view is what any ordinary navigation means, so the breadcrumb's other crumbs
-- call this before doing their own thing rather than each having to remember to.
function D.Dismiss()
  if D.IsShowing() then D.Hide() end
end

-- The overlay is a child of the canvas and the map is a window: closing the window while a dungeon
-- is up would reopen on it, which is not where the player left off.
function D.Arm()
  if D._armed then return end
  D._armed = true
  local map = WM.frame
  if map then map:HookScript("OnHide", function() D.Dismiss() end) end
end
