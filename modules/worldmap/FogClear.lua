-- DragonUI_NewEra/modules/worldmap/FogClear.lua — unexplored zone art, shown but greyed back.
--
-- NOT A DOWNPORT. NewEra has no counterpart: Classic Era's MapCanvas has no fog-of-war overlays to
-- clear. This is built against 3.3.5a's own overlay system, and the mechanism is the one Mapster's
-- FogClear module established on this client — the technique, not the code, and explicitly not its
-- data (see "where the list comes from" below).
--
-- HOW FOG OF WAR ACTUALLY WORKS HERE, because none of this is guessable from the screen:
--
--   * `WorldMapDetailFrame` draws the zone's BASE art — mostly empty, the unexplored look.
--   * On top of it the client lays one OVERLAY per subzone you have DISCOVERED: the real terrain
--     art for that patch. `GetNumMapOverlays()` says how many, `GetMapOverlayInfo(i)` gives each
--     one's texture path, pixel size and offset, and the client blits them onto
--     `WorldMapOverlay1..NUM_WORLDMAP_OVERLAYS`.
--   * An overlay bigger than 256px is stored as a GRID of 256px files named `<Name>1`, `<Name>2`, …
--     row-major, and the last row and column are cropped to the next power of two — which is why
--     the layout maths below is fiddlier than "draw a texture".
--
-- So "removing the fog" is not removing anything. It is drawing the overlays the client would NOT
-- have drawn, and drawing them differently: an area you have been to renders in full colour on
-- ARTWORK, and one you have not renders tinted and half-transparent on BORDER, so that if you later
-- explore it the real art lands cleanly on top.
--
-- WHERE THE LIST COMES FROM. `GetNumMapOverlays()` only ever reports what THIS character has
-- discovered, and no API enumerates the rest — so knowing an unexplored subzone exists at all
-- requires a stored table. There are two here, and the module uses both:
--
--   * THE SEED (`modules/worldmap/OverlayData.lua`) — 886 overlays across 61 maps, generated from
--     the client's OWN `WorldMapOverlay.dbc` by `tools/worldmap-overlays/gen_overlays.py`. This is
--     what makes the map show ground nobody has walked, from the first login. Mapster solves the
--     same problem with a thousand hand-written lines; the client has the real table, so it is read
--     rather than transcribed — which also means it is right for whatever content THIS server ships
--     rather than right for retail.
--   * THE HARVEST (`NE.db.worldmap.overlays`) — every overlay any character on the account has been
--     seen to discover, recorded as it happens. It covers whatever the DBC does not know about,
--     which on a server with custom zones is the interesting part.
--
-- The HARVEST wins on conflict: it was observed on this client at runtime, and the seed was read off
-- a file. They agree everywhere it matters, and the harvest is the more direct evidence.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap

local FOG = {}
WM.fog = FOG

-- Default tint for an unexplored area: neutral grey at just over half opacity. Explored art is warm
-- parchment, so a desaturated wash reads immediately as "this is there, but it is not yours yet"
-- without going so dark that the terrain stops being legible.
local DEFAULT_TINT = { r = 0.60, g = 0.60, b = 0.60, a = 0.55 }

local floor, fmod, ceil = math.floor, math.fmod, math.ceil

-- ----------------------------------------------------------------------------
-- Store
-- ----------------------------------------------------------------------------

-- One integer per subzone. Mapster's packing, kept because it is the compact form this data has
-- always been stored in and there is no reason to invent another: width and height are under 1024,
-- and the offsets fit the remaining bits.
local function pack(w, h, x, y)   return w + h * 2^10 + x * 2^20 + y * 2^30 end
local function unpack4(id)
  return fmod(id, 2^10), fmod(floor(id / 2^10), 2^10), fmod(floor(id / 2^20), 2^10), floor(id / 2^30)
end
FOG._pack, FOG._unpack = pack, unpack4

local function store()
  if not NE.db then return nil end
  NE.db.worldmap = NE.db.worldmap or {}
  NE.db.worldmap.overlays = NE.db.worldmap.overlays or {}
  return NE.db.worldmap.overlays
end

function FOG.Tint()
  local t = NE.db and NE.db.worldmap and NE.db.worldmap.fog
  if type(t) == "table" and t.r then return t end
  return DEFAULT_TINT
end

-- What we have recorded for one map file, creating the bucket on demand.
local function overlaysFor(mapFile)
  local db = store()
  if not (db and mapFile) then return nil end
  db[mapFile] = db[mapFile] or {}
  return db[mapFile]
end
FOG.OverlaysFor = overlaysFor

-- Everything KNOWN for one map: the generated seed, with the harvest laid over it.
--
-- Built fresh per refresh rather than merged into the saved store, deliberately. Copying 886 seeded
-- rows into SavedVariables would bloat that file to restate what the addon already ships in Lua --
-- and worse, it would freeze today's generated table into every player's saved data, so re-running
-- the generator against a patched client would change nothing for anyone already logged in once.
local function knownFor(mapFile)
  local out = {}
  local seed = NE.worldmap.overlaySeed and NE.worldmap.overlaySeed[mapFile]
  if seed then
    for name, id in pairs(seed) do out[name] = id end
  end
  local bucket = overlaysFor(mapFile)
  if bucket then
    for name, id in pairs(bucket) do out[name] = id end   -- observed beats read-off-a-file
  end
  return out
end
FOG.KnownFor = knownFor


-- Harvested maps, harvested subzones, seeded maps, seeded subzones -- reported separately because
-- they answer different questions. The seed says how much the module knows out of the box; the
-- harvest says how much this account has added to it.
function FOG.Coverage()
  local maps, subzones = 0, 0
  local db = store()
  if db then
    for _, bucket in pairs(db) do
      maps = maps + 1
      for _ in pairs(bucket) do subzones = subzones + 1 end
    end
  end
  local sMaps, sSubs = 0, 0
  local seed = NE.worldmap.overlaySeed
  if seed then
    for _, bucket in pairs(seed) do
      sMaps = sMaps + 1
      for _ in pairs(bucket) do sSubs = sSubs + 1 end
    end
  end
  return maps, subzones, sMaps, sSubs
end

-- ----------------------------------------------------------------------------
-- Harvest
-- ----------------------------------------------------------------------------

local function safe(fn, ...)
  if type(fn) ~= "function" then return nil end
  local r = { pcall(fn, ...) }
  if not r[1] then return nil end
  return unpack(r, 2)
end

-- Read whatever the client is currently willing to tell us, record it, and hand back the set of
-- names that are discovered RIGHT NOW — which is what decides full colour versus tinted.
local function harvest(mapFile, bucket)
  local discovered = {}
  local n = safe(_G.GetNumMapOverlays) or 0
  if n <= 0 then return discovered end

  local prefixLen = #("Interface\\WorldMap\\" .. mapFile .. "\\") + 1
  for i = 1, n do
    local path, w, h, x, y = safe(_G.GetMapOverlayInfo, i)
    if type(path) == "string" and w and h and x and y then
      local name = path:sub(prefixLen)
      local id = pack(w, h, x, y)
      -- Two junk entries the client serves that are not real overlays: a zero record, and the
      -- 1x1 "pixelfix" spacer some zones carry. 131200 is the packed form of the other one.
      -- Recording either draws a stray dot on the map forever, since the store is permanent.
      if id ~= 0 and id ~= 131200 and name ~= "" and name:lower() ~= "pixelfix" then
        discovered[name] = true
        bucket[name] = id
      end
    end
  end
  return discovered
end

-- ----------------------------------------------------------------------------
-- Render
-- ----------------------------------------------------------------------------

-- The client pools its overlay textures by name and tracks the count in a global. Drawing more
-- overlays than it has ever needed means making more of them and telling it we did, or the next
-- client update walks off the end of its own pool.
local function acquireOverlay(index)
  local name = "WorldMapOverlay" .. index
  local tex = _G[name]
  if tex then return tex end
  local detail = _G.WorldMapDetailFrame
  if not detail then return nil end
  tex = detail:CreateTexture(name, "ARTWORK")
  if (_G.NUM_WORLDMAP_OVERLAYS or 0) < index then _G.NUM_WORLDMAP_OVERLAYS = index end
  return tex
end

-- Lay one stored overlay out as its grid of 256px pieces. Returns the running texture count.
local function drawOverlay(detail, prefix, name, id, discovered, tint, count)
  local w, h, offX, offY = unpack4(id)
  local cols, rows = ceil(w / 256), ceil(h / 256)

  for row = 1, rows do
    -- The bottom row is cropped: its PIXEL height is the remainder, but the FILE is the next power
    -- of two up, so the texcoord is the ratio between them. Same for the right-hand column.
    local pixelH = (row < rows) and 256 or (fmod(h, 256) ~= 0 and fmod(h, 256) or 256)
    local fileH  = (row < rows) and 256 or 16
    while fileH < pixelH do fileH = fileH * 2 end

    for col = 1, cols do
      local pixelW = (col < cols) and 256 or (fmod(w, 256) ~= 0 and fmod(w, 256) or 256)
      local fileW  = (col < cols) and 256 or 16
      while fileW < pixelW do fileW = fileW * 2 end

      count = count + 1
      local tex = acquireOverlay(count)
      if not tex then return count end

      tex:SetWidth(pixelW)
      tex:SetHeight(pixelH)
      tex:SetTexCoord(0, pixelW / fileW, 0, pixelH / fileH)
      tex:ClearAllPoints()
      tex:SetPoint("TOPLEFT", detail, "TOPLEFT",
                   offX + 256 * (col - 1), -(offY + 256 * (row - 1)))
      tex:SetTexture(prefix .. name .. (((row - 1) * cols) + col))

      if discovered then
        tex:SetVertexColor(1, 1, 1)
        tex:SetAlpha(1)
        tex:SetDrawLayer("ARTWORK")
      else
        -- BORDER, one layer down, so that the day this area IS explored its full-colour art draws
        -- over the tinted copy rather than fighting it within a layer.
        tex:SetVertexColor(tint.r, tint.g, tint.b)
        tex:SetAlpha(tint.a)
        tex:SetDrawLayer("BORDER")
      end
      tex:Show()
    end
  end
  return count
end

function FOG.Refresh()
  local detail = _G.WorldMapDetailFrame
  if not (detail and _G.WorldMapFrame and _G.WorldMapFrame:IsShown()) then return end
  if not FOG.enabled then return end

  local mapFile = safe(_G.GetMapInfo)
  if type(mapFile) ~= "string" or mapFile == "" then return end

  local bucket = overlaysFor(mapFile)
  if not bucket then return end

  local discovered = harvest(mapFile, bucket)
  local known = knownFor(mapFile)
  local prefix = "Interface\\WorldMap\\" .. mapFile .. "\\"
  local tint = FOG.Tint()

  local count = 0
  for name, id in pairs(known) do
    count = drawOverlay(detail, prefix, name, id, discovered[name], tint, count)
  end
  FOG.lastDrawn = count

  -- Retire whatever the client (or a deeper map) left behind.
  for i = count + 1, (_G.NUM_WORLDMAP_OVERLAYS or 0) do
    local tex = _G["WorldMapOverlay" .. i]
    if tex then tex:Hide() end
  end
end

-- Hand the client's own overlays back: full colour, ARTWORK, and let its next update place them.
function FOG.Restore()
  for i = 1, (_G.NUM_WORLDMAP_OVERLAYS or 0) do
    local tex = _G["WorldMapOverlay" .. i]
    if tex then
      tex:SetVertexColor(1, 1, 1)
      tex:SetAlpha(1)
      tex:SetDrawLayer("ARTWORK")
    end
  end
  if type(_G.WorldMapFrame_Update) == "function" then pcall(_G.WorldMapFrame_Update) end
end

-- ----------------------------------------------------------------------------
-- Boot
-- ----------------------------------------------------------------------------

function FOG.Arm()
  if FOG._armed then return end
  FOG._armed = true
  -- Default ON, but the filter's saved choice wins: forcing it true here would switch the overlays
  -- back on every login for a player who turned them off.
  local saved = NE.db and NE.db.worldmap and NE.db.worldmap.poiFilters
  saved = saved and saved.fog
  FOG.enabled = (saved == nil) or (saved and true or false)

  -- Chained onto the map-change signal rather than hooking WorldMapFrame_Update a second time:
  -- WorldMap.lua already owns that hook and calls this at its tail, AFTER the client has placed its
  -- own overlays — which is exactly when ours must re-place them.
  local prev = WM.OnMapChanged
  WM.OnMapChanged = function()
    if prev then pcall(prev) end
    FOG.Refresh()
  end

  FOG.Refresh()
end
