-- DragonUI_NewEra/modules/worldmap/Diagnostics.lua — /neworldmap, a state dump for the map.
--
-- This module is a REBUILD against a frame tree nobody can read from outside the game — there is no
-- 1.15 source to diff against, and the 3.3.5a FrameXML is not on disk here. When something comes out
-- wrong on screen, the whole question is "which widget is that, and who still owns it", and a
-- screenshot cannot answer it. This prints the answer.
--
-- It is specifically built around the two faults the first in-game run produced, because both were
-- invisible from the picture alone:
--
--   * The client repainted its FULLSCREEN chrome around our window, because
--     `WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE` — this client's one and only "am I
--     windowed?" test — stopped being true the moment we wrote our own scale into `size`. The MODE
--     block below prints both numbers and whether they still agree.
--   * The breadcrumb drew its background plate and no crumbs. That happened TWICE, for two
--     different reasons, and telling them apart is most of why this file exists. First the bar's
--     anchored width had not resolved on the pass that laid it out, so no crumb was ever built.
--     Then, once they were built, they were painted over by the bar's own OVERLAY sheen because
--     nothing had pinned their frame level above it — and this dump reported them as shown, sized
--     and textured, which was all true and none of it visible. The NAVBAR block now prints the
--     measured width, the trail depth, each crumb's FRAME LEVEL, and its text colour and anchor, so
--     "not built", "built and covered" and "built and drawn off the edge" all read differently.
--
-- Report-only: it reads widgets and never writes one, so it is safe to run at any time, including
-- in combat.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local WM = NE.worldmap
if not WM then return end

local function say(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1NE map|r " .. msg)
end

local function yn(v) return v and "|cff40ff40yes|r" or "|cffff4040no|r" end

-- Shorten a texture path to its last two components, so the dump stays readable in chat.
local function shortPath(p)
  if type(p) ~= "string" then return tostring(p) end
  local a, b = p:match("([^\\]+)\\([^\\]+)$")
  if a then return a .. "\\" .. b end
  return p
end

local function num(v)
  if type(v) ~= "number" then return "nil" end
  return string.format("%.2f", v)
end

local function pointOf(o)
  if not (o and o.GetPoint and o.GetNumPoints and o:GetNumPoints() > 0) then return "no anchor" end
  local p, rel, rp, x, y = o:GetPoint(1)
  local relName = rel and rel.GetName and rel:GetName() or (rel and "?" or "nil")
  return string.format("%s -> %s.%s (%s, %s)", tostring(p), tostring(relName), tostring(rp),
                       num(x), num(y))
end

-- ----------------------------------------------------------------------------
-- Sections
-- ----------------------------------------------------------------------------

local function dumpMode()
  local f = _G.WorldMapFrame
  say("|cffffd100mode|r")
  local size   = _G.WORLDMAP_SETTINGS and _G.WORLDMAP_SETTINGS.size
  local windowedConst = _G.WORLDMAP_WINDOWED_SIZE
  say("  WORLDMAP_SETTINGS.size = %s   WORLDMAP_WINDOWED_SIZE = %s", num(size), num(windowedConst))
  -- The identity every mode check on this client asks. If it is `no`, the client believes it is
  -- FULLSCREEN and will keep repainting the 1024x768 border, backdrop and quest panels.
  say("  client thinks it is windowed: %s", yn(size ~= nil and size == windowedConst))
  say("  client's ORIGINAL windowed constant (captured at boot): %s",
      WM.clientWindowedSize and num(WM.clientWindowedSize) or "not captured")
  -- Neither of the two globals above is ours to write any more: the client reads both on its way to
  -- a protected call, so an addon-written value makes the map unopenable in combat. If `size` has
  -- drifted off the constant, something ELSE has written it and that is worth seeing here.
  say("  our canvas scale = %s   with zoom = %s   client-space ratio = %s",
      num(WM.canvasScale), num(WM.effectiveScale), num(WM.clientSpaceRatio))
  say("  miniWorldMap cvar = %s   maximized = %s",
      tostring(GetCVar and GetCVar("miniWorldMap")), yn(WM.maximized))
  -- LEFT INTACT ON PURPOSE. Clearing this row is what made WorldMapFrame_SetMiniMode throw; the map
  -- is detached through the frame's own layout attributes instead, which is what the next line
  -- reports. "cleared" here is a FAULT, not the expected state.
  local f2 = _G.WorldMapFrame
  say("  UIPanelWindows entry = %s   layout attrs: defined=%s enabled=%s",
      _G.UIPanelWindows and _G.UIPanelWindows["WorldMapFrame"] and "present" or "|cffff4040cleared|r",
      tostring(f2 and f2.GetAttribute and f2:GetAttribute("UIPanelLayout-defined")),
      tostring(f2 and f2.GetAttribute and f2:GetAttribute("UIPanelLayout-enabled")))
  -- The window is one number now, so print it -- and print whether the shape it produced is one the
  -- map actually fills, which is the invariant the whole resize design exists to keep.
  local stored = NE.db and NE.db.worldmap and NE.db.worldmap.canvasW
  say("  canvas width = %s  (saved: %s)   sizing = %s",
      num(WM.CurrentCanvasWidth and WM.CurrentCanvasWidth()), stored and num(stored) or "default",
      yn(WM.sizing))
  if f and WM.CurrentCanvasWidth then
    local panelW = (NE.questlogpanel and NE.questlogpanel.PanelWidth and NE.questlogpanel.PanelWidth()) or 0
    local cw = (f:GetWidth() or 0) - 2 - 3 - panelW
    local ch = (f:GetHeight() or 0) - 67 - 2
    local want = select(1, (_G.WorldMapDetailFrame and _G.WorldMapDetailFrame:GetWidth()) or 1002)
               / ((_G.WorldMapDetailFrame and _G.WorldMapDetailFrame:GetHeight()) or 668)
    local have = (ch > 0) and (cw / ch) or 0
    say("  canvas aspect %s vs map %s  %s", num(have), num(want),
        (math.abs(have - want) < 0.02) and "|cff40ff40(no letterbox)|r"
                                        or "|cffff4040(LETTERBOXED -- dead space in the window)|r")
  end
  if f then
    say("  WorldMapFrame  %sx%s  scale %s  strata %s  shown %s",
        num(f:GetWidth()), num(f:GetHeight()), num(f:GetScale()),
        tostring(f:GetFrameStrata()), yn(f:IsShown()))
    say("  anchor: %s", pointOf(f))
  end
end

local function dumpCanvas()
  say("|cffffd100canvas|r")
  for _, name in ipairs({ "WorldMapDetailFrame", "WorldMapButton", "WorldMapFrameAreaFrame",
                          "WorldMapBlobFrame", "WorldMapPOIFrame" }) do
    local w = _G[name]
    if not w then
      say("  %s = |cffff4040absent|r", name)
    else
      say("  %s  %sx%s  scale %s  shown %s", name, num(w:GetWidth()), num(w:GetHeight()),
          num(w.GetScale and w:GetScale()), yn(w:IsShown()))
    end
  end
  local d = _G.WorldMapDetailFrame
  if d then say("  detail anchor: %s", pointOf(d)) end
end

-- Every VISIBLE texture still carrying classic map or quest art, on the window and one level down.
-- This is the list that should be EMPTY. Anything printed here is chrome the suppression missed,
-- and the owner column says which frame to add to the sweep.
local function dumpLeftoverArt()
  say("|cffffd100leftover classic art|r (this list should be empty)")
  local f = _G.WorldMapFrame
  if not f then return end

  local keep = {
    WorldMapDetailFrame = true, WorldMapButton = true, WorldMapPOIFrame = true,
    WorldMapFrameAreaFrame = true, WorldMapBlobFrame = true,
  }
  -- ...and our own frames. The first dump flagged this window's PORTRAIT, which is
  -- Interface\\QuestFrame\\UI-QuestLog-BookIcon drawn by us onto our own border: a true
  -- match for the pattern and entirely wrong to report. A list that cries wolf is worse than none.
  local ours = {
    [f._neBorder or false] = true,
    [f._neSpacer or false] = true,
    [f._neSideToggle or false] = true,
    [WM.navbar or false] = true,
    [(NE.questlogpanel and NE.questlogpanel.frame) or false] = true,
  }

  local found = 0
  local function scan(frame, owner)
    if not (frame and frame.GetRegions) then return end
    for _, r in ipairs({ frame:GetRegions() }) do
      if r.GetObjectType and r:GetObjectType() == "Texture" and r:IsShown() then
        local path = r.GetTexture and r:GetTexture()
        if type(path) == "string" then
          local low = path:lower()
          if low:find("interface\\worldmap\\", 1, true)
             or low:find("interface\\questframe\\", 1, true)
             or low:find("ui-worldmap", 1, true) then
            found = found + 1
            if found <= 24 then
              say("  %s  [%s]  %s  %sx%s", owner, tostring(r:GetDrawLayer()), shortPath(path),
                  num(r:GetWidth()), num(r:GetHeight()))
            end
          end
        end
      end
    end
  end

  scan(f, "WorldMapFrame")
  for _, child in ipairs({ f:GetChildren() }) do
    local name = child.GetName and child:GetName() or "<unnamed>"
    if not keep[name] and not ours[child] then scan(child, name) end
  end
  if found == 0 then
    say("  |cff40ff40none|r")
  elseif found > 24 then
    say("  ...and %d more (only the first 24 are listed)", found - 24)
  end
end

-- Named widgets the chrome is supposed to have silenced, and whether they actually are.
local function dumpSquelch()
  say("|cffffd100squelched widgets|r")
  local names = {
    "WorldMapFrameMiniBorderLeft", "WorldMapFrameMiniBorderRight", "WorldMapFrameTitle",
    "WorldMapTitleButton", "BlackoutWorld", "WorldMapContinentDropDown", "WorldMapZoneDropDown",
    "WorldMapZoneMinimapDropDown", "WorldMapZoomOutButton", "WorldMapMagnifyingGlassButton",
    "WorldMapFrameSizeUpButton", "WorldMapFrameSizeDownButton", "WorldMapQuestScrollFrame",
    "WorldMapQuestDetailScrollFrame", "WorldMapQuestRewardScrollFrame",
    "WorldMapQuestShowObjectives", "WorldMapTrackQuest",
  }
  local loud = {}
  for _, n in ipairs(names) do
    local w = _G[n]
    if w and w.IsShown and w:IsShown() then loud[#loud + 1] = n end
  end
  if #loud == 0 then
    say("  all quiet (%d checked)", #names)
  else
    for _, n in ipairs(loud) do
      local w = _G[n]
      say("  |cffff4040STILL SHOWN|r %s  %sx%s  squelched=%s", n,
          num(w:GetWidth()), num(w:GetHeight()),
          yn(NE.squelch and NE.squelch.IsSquelched and NE.squelch.IsSquelched(w)))
    end
  end
end

-- Fog of war. The one thing worth printing here is the DIFFERENCE between what the client is
-- willing to tell us about this map and what we have stored for it — because the gap IS the feature,
-- and if the two numbers match then nothing is being revealed and the module is doing nothing
-- visible however healthy it looks.
local function dumpFog()
  say("|cffffd100fog of war|r")
  local FOG = WM.fog
  if not FOG then say("  |cffff4040module not loaded|r"); return end
  say("  enabled = %s", yn(FOG.enabled))
  local maps, subzones, sMaps, sSubs = FOG.Coverage()
  say("  seed:  %d maps, %d subzones (generated from this client's WorldMapOverlay.dbc)",
      sMaps or 0, sSubs or 0)
  say("  store: %d maps, %d subzones harvested account-wide on top of it", maps, subzones)
  local t = FOG.Tint()
  say("  unexplored tint: %s/%s/%s at alpha %s", num(t.r), num(t.g), num(t.b), num(t.a))

  local mapFile = GetMapInfo and GetMapInfo()
  if type(mapFile) ~= "string" or mapFile == "" then
    say("  this map has no art token (an instance or battleground) -- nothing to draw")
    return
  end
  local live = (GetNumMapOverlays and GetNumMapOverlays()) or 0
  local bucket = FOG.OverlaysFor(mapFile) or {}
  local known = 0
  for _ in pairs(bucket) do known = known + 1 end
  say("  %s: client reports %d discovered, we remember %d", mapFile, live, known)
  if known > live then
    say("  |cff40ff40revealing %d unexplored subzone(s)|r", known - live)
  elseif known > 0 then
    say("  nothing extra to reveal here yet -- every remembered area is already explored")
  else
    say("  nothing remembered for this map yet")
  end
  say("  textures drawn on the last pass: %s", tostring(FOG.lastDrawn))
  say("  NUM_WORLDMAP_OVERLAYS = %s", tostring(_G.NUM_WORLDMAP_OVERLAYS))
end

-- Other addons drawing on OUR map. This module deliberately seeds no POI data of its own -- the job
-- is already done by ModernMapMarkers, and two seeders would put two markers on every dungeon
-- entrance -- so "cooperating with it" is a feature of this window, and a feature with no report on
-- it is a feature nobody can debug. MMM parents its pins to WorldMapDetailFrame and positions them
-- from that frame's own width, which our chrome SCALES rather than resizes, so they should follow
-- the map for free; this says whether they actually do.
local function dumpNeighbours()
  say("|cffffd100other map addons|r")
  local loaded = NE.IsAddOnLoaded and NE.IsAddOnLoaded("ModernMapMarkers")
  say("  ModernMapMarkers loaded = %s", yn(loaded))
  if not loaded then return end

  local detail = _G.WorldMapDetailFrame
  if not detail then return end

  -- Its pins are unnamed children of the detail frame, so they are counted rather than looked up.
  local total, shown, withTexture = 0, 0, 0
  local sample
  for _, child in ipairs({ detail:GetChildren() }) do
    if child.texture and child.markerName ~= nil then
      total = total + 1
      if child:IsShown() then shown = shown + 1 end
      local t = child.texture.GetTexture and child.texture:GetTexture()
      if t then withTexture = withTexture + 1 end
      if not sample and child:IsShown() then sample = child end
    end
  end
  say("  pins on the canvas: %d built, %d shown, %d textured", total, shown, withTexture)
  if total == 0 then
    say("  |cffff4040it has drawn nothing|r -- so the question is whether it RAN, not whether we hid it")
    say("  its saved settings: %s", _G.ModernMapMarkersDB and "present" or "|cffff4040absent|r")
    local db = _G.ModernMapMarkersDB
    if db then
      say("  filters: dungeons=%s raids=%s boats=%s portals=%s",
          yn(db.showDungeons), yn(db.showRaids), yn(db.showBoats), yn(db.showPortals))
    end
    say("  continent/zone it would key on: %s / %s",
        tostring(GetCurrentMapContinent and GetCurrentMapContinent()),
        tostring(GetCurrentMapZone and GetCurrentMapZone()))
  elseif sample then
    say("  sample pin: %sx%s at level %d  texture %s", num(sample:GetWidth()),
        num(sample:GetHeight()), sample:GetFrameLevel() or -1,
        shortPath(sample.texture:GetTexture()))
    say("  (our chrome sits at level %d; a pin below that is behind it)",
        (_G.WorldMapFrame and _G.WorldMapFrame._neBorder
         and _G.WorldMapFrame._neBorder:GetFrameLevel()) or -1)
  end
end

local function dumpChrome()
  say("|cffffd100chrome|r")
  local f = _G.WorldMapFrame
  local b = f and f._neBorder
  say("  border built = %s   spacer built = %s   navbar built = %s   panel built = %s",
      yn(b ~= nil), yn(f and f._neSpacer ~= nil), yn(WM.navbar ~= nil),
      yn(NE.questlogpanel and NE.questlogpanel.frame ~= nil))
  if b then
    say("  border level %d (POI frame level %s)", b:GetFrameLevel() or -1,
        tostring(_G.WORLDMAP_POI_FRAMELEVEL))
    say("  title = %q", tostring(b.Title and b.Title:GetText()))
    say("  portrait texture = %s", shortPath(b.Portrait and b.Portrait:GetTexture()))
    -- ApplyLayout leaves no marker on the container, so report what the chrome ASKED for and how
    -- many pieces actually landed -- which is the more useful question anyway.
    local pieces = 0
    if b.NineSlice and b.NineSlice.GetRegions then
      for _, r in ipairs({ b.NineSlice:GetRegions() }) do
        if r.GetObjectType and r:GetObjectType() == "Texture" and r:IsShown() then pieces = pieces + 1 end
      end
    end
    say("  nineslice: PortraitFrameTemplate, %d visible pieces", pieces)
  end
  -- The close button's handler hides its PARENT, so which frame that is decides whether the X
  -- closes the map or guts the window. It cost a session to learn; it costs one line to report.
  local close = _G.WorldMapFrameCloseButton
  if close then
    local parent = close:GetParent()
    local pname = parent and parent.GetName and parent:GetName() or "?"
    local right = (parent == f)
    say("  close button parent = %s %s  level %d", tostring(pname),
        right and "|cff40ff40(correct)|r" or "|cffff4040(WRONG -- the X will hide this, not the map)|r",
        close:GetFrameLevel() or -1)
    say("  border shown = %s", yn(b and b:IsShown()))

  -- The canvas tooltip. It is a CHILD of the map window, so it inherits this window's strata, and a
  -- tooltip with no background over parchment is unreadable rather than merely plain.
  local tt = _G.WorldMapTooltip
  if tt then
    local bd = tt.GetBackdrop and tt:GetBackdrop()
    local okc, r, g, bl, a = pcall(tt.GetBackdropColor, tt)
    say("  tooltip: strata %s  backdrop %s  colour %s/%s/%s alpha %s  repaired=%s",
        tostring(tt:GetFrameStrata()),
        (bd and bd.bgFile) and "|cff40ff40present|r" or "|cffff4040MISSING|r",
        okc and num(r) or "?", okc and num(g) or "?", okc and num(bl) or "?",
        okc and num(a) or "?", yn(tt._neTooltipRepaired))
  end
  end
  local sp = f and f._neSpacer
  if sp then say("  spacer %sx%s", num(sp:GetWidth()), num(sp:GetHeight())) end
  local bg = f and f._neBg
  say("  body fill = %s  shown=%s", shortPath(bg and bg:GetTexture()), yn(bg and bg:IsShown()))
end

local function dumpNavBar()
  say("|cffffd100navbar|r")
  local bar = WM.navbar
  if not bar then say("  |cffff4040not built|r"); return end
  say("  %sx%s  shown %s  level %d  trail depth %s",
      num(bar:GetWidth()), num(bar:GetHeight()), yn(bar:IsShown()),
      bar:GetFrameLevel() or -1, tostring(bar._trailDepth))
  say("  plate = %s  shown=%s  %sx%s", shortPath(bar.bg and bar.bg:GetTexture()),
      yn(bar.bg and bar.bg:IsShown()), num(bar.bg and bar.bg:GetWidth()),
      num(bar.bg and bar.bg:GetHeight()))
  -- A crumb that reports shown, sized and textured and is STILL not on screen has been painted
  -- over, and only the frame levels say so. That is exactly what the first in-game run did, and the
  -- dump could not tell it from a layout mistake -- hence these extra columns.
  say("  plate layer = %s   sheen layer = %s",
      tostring(bar.bg and bar.bg:GetDrawLayer()), tostring(bar.sheen and bar.sheen:GetDrawLayer()))
  local crumbs = bar.crumbs or {}
  if #crumbs == 0 then say("  |cffff4040no crumb widgets built|r"); return end
  for i, c in ipairs(crumbs) do
    say("  [%d] %q  w=%s  shown=%s  level=%d  bg=%s  arrow=%s  endcap=%s", i,
        tostring(c.text and c.text:GetText()), num(c:GetWidth()), yn(c:IsShown()),
        c:GetFrameLevel() or -1,
        yn(c.bg and c.bg:IsShown()), yn(c.arrow and c.arrow:IsShown()),
        yn(c.endcap and c.endcap:IsShown()))
    local t = c.text
    if t then
      local r, g, b, a = 1, 1, 1, 1
      if t.GetTextColor then r, g, b, a = t:GetTextColor() end
      say("       text shown=%s  colour %s/%s/%s alpha %s  at %s",
          yn(t:IsShown()), num(r), num(g), num(b), num(a), pointOf(t))
    end
  end
end

local function dumpPanel()
  say("|cffffd100quest panel|r")
  local P = NE.questlogpanel
  if not (P and P.frame) then say("  |cffff4040not built|r"); return end
  say("  shown = %s  PanelWidth() = %s  maximized = %s  detail = %s",
      yn(P.frame:IsShown()), num(P.PanelWidth and P.PanelWidth()), yn(P.maximized),
      yn(P.detailShown))
  say("  frame %sx%s  anchor: %s", num(P.frame:GetWidth()), num(P.frame:GetHeight()),
      pointOf(P.frame))
  local entries = P.BuildList and P.BuildList(P.selectedIndex) or {}
  local headers, quests = 0, 0
  for _, e in ipairs(entries) do
    if e.kind == "header" then headers = headers + 1
    elseif e.kind == "quest" then quests = quests + 1 end
  end
  say("  model: %d headers, %d quests  (filter = %s)", headers, quests, tostring(P.filter))
  say("  selected = %s  blob quest = %s", tostring(P.selectedIndex), tostring(P.blobQuestID))
end

-- Which of the art this module depends on actually resolved. A sheet whose BLP is missing makes
-- every texture using it render blank, and there is no error to say so.
local function dumpArt()
  say("|cffffd100art|r")
  for _, e in ipairs({ { 516763, "navbar sheet" }, { 516764, "navbar tile sheet" },
                       { 423808, "dropdown arrow" }, { 4698972, "redbutton" },
                       { 374155, "rock body" }, { 136441, "POI icons" } }) do
    local path = NE.tex and NE.tex.Local and NE.tex.Local(e[1])
    say("  %-18s %s  %s", e[2], yn(path ~= nil), path and shortPath(path) or "not registered")
  end
  local probe = WM._atlasProbe
  if not probe then
    probe = UIParent:CreateTexture(nil, "BACKGROUND")
    probe:Hide()
    WM._atlasProbe = probe
  end
  local missing = {}
  for _, name in ipairs({ "worldmap-navbar-button-tile", "worldmap-navbar-barbg-tile",
                          "worldmap-navbar-baroverlay-tile", "worldmap-navbar-endcap",
                          "worldmap-navbar-dropdown-arrow", "redbutton-expand-2x",
                          "redbutton-condense-2x", "_UI-Frame-InnerTopTile" }) do
    if not (NE.tex.SetAtlas and NE.tex.SetAtlas(probe, name, false)) then
      missing[#missing + 1] = name
    end
  end
  if #missing == 0 then
    say("  all atlases resolve")
  else
    say("  |cffff4040unresolved atlases|r: %s", table.concat(missing, ", "))
  end
end

-- ----------------------------------------------------------------------------
-- Slash command
-- ----------------------------------------------------------------------------

-- What the client itself offers as map POIs on the CURRENT map, and how the player arrow ended up
-- the size it is. Both are report-only.
--
-- The landmark list is here to answer a specific question with data instead of memory: this client's
-- `GetNumMapLandmarks` is the only native source of map pins, and whether it includes dungeon and
-- raid entrances (as opposed to flight points, towns and PvP objectives) decides whether "no dungeon
-- POIs" is something to build or something the client simply does not have. Guessing at that from
-- recollection is how the ModernMapMarkers detour started.
local function dumpPins()
  say("---- pins ----")

  local n = 0
  if type(_G.GetNumMapLandmarks) == "function" then
    local ok, v = pcall(_G.GetNumMapLandmarks)
    n = (ok and type(v) == "number") and v or 0
  else
    say("  |cffff4040GetNumMapLandmarks missing|r")
  end
  say("  landmarks on this map: %d", n)

  local kinds = {}
  for i = 1, n do
    local r = { pcall(_G.GetMapLandmarkInfo, i) }
    if r[1] then
      -- name, description, textureIndex, x, y  (arity varies by build, so read positionally)
      local name = tostring(r[2] or "?")
      local tex  = tostring(r[4] or "?")
      kinds[tex] = (kinds[tex] or 0) + 1
      if i <= 12 then say("    %2d  tex=%-4s  %s", i, tex, name) end
    end
  end
  if n > 12 then say("    ... %d more", n - 12) end

  local list = {}
  for tex, count in pairs(kinds) do list[#list + 1] = tex .. "x" .. count end
  table.sort(list)
  if #list > 0 then say("  textureIndex histogram: %s", table.concat(list, "  ")) end

  local arrow = _G.PlayerArrowFrame
  if arrow then
    local ds = _G.WorldMapDetailFrame and _G.WorldMapDetailFrame:GetEffectiveScale()
    -- The arrow and the quest-POI layer are positioned by the CLIENT, in their own units, against
    -- its own constant -- so their frame scale has to be the canvas-to-client ratio. If these two
    -- disagree with `client-space ratio` above, the markers are in the wrong place.
    say("  player arrow: frameScale = %s  modelScale = %s  arrowEff = %s  detailEff = %s",
        num(arrow.GetScale and arrow:GetScale()), num(WM.arrowModelScale),
        num(arrow.GetEffectiveScale and arrow:GetEffectiveScale()), num(ds))
    local poi = _G.WorldMapPOIFrame
    -- frameScale MUST read 1 here: the markers are placed by offset (WM.PlaceQuestPOI) so that they
    -- stay the client's size. A ratio on this frame magnifies the markers themselves.
    say("  quest-POI layer: frameScale = %s  parent = %s",
        num(poi and poi.GetScale and poi:GetScale()),
        poi and poi.GetParent and poi:GetParent() and (poi:GetParent():GetName() or "<unnamed>") or "?")

    -- The open-the-map ping. The CLIENT's is squelched and drawn by the engine for geometry this
    -- window does not have (see the ping section in WorldMap.lua); ours is a Model of our own under
    -- WorldMapButton, so it rides the canvas scale, the zoom and the clipping.
    --
    -- `model loaded` is the one that matters if the pulse is invisible rather than misplaced: the
    -- model path is the client's own, but a modified client could have moved it.
    local ping = WM.ping
    if ping then
      -- A TEXTURE, deliberately: a Model is drawn at the model file's own origin inside its frame, so
      -- it can miss the player even when its anchor is exactly on the arrow. `art` empty means no
      -- candidate path resolved on this client and the pulse is invisible rather than misplaced.
      say("  ping (ours): built = yes  shown = %s  at = %s",
          yn(ping.IsShown and ping:IsShown()),
          WM.pingAt and string.format("%.3f, %.3f", WM.pingAt.x, WM.pingAt.y) or "not placed yet")
      say("        art = %s  (%s)", WM.pingArt or "|cffff4040none resolved|r",
          ping.isModel and "MODEL -- db.worldmap.pingModel is set" or "texture, the default")
      -- PARENT IS THE FIELD TO READ IF IT IS MISPLACED AGAIN. A Model under the magnifier's
      -- ScrollFrame is rendered against a scrolled-away origin no matter how correct its anchor is;
      -- that is what put both the client's ping and our first one in the wrong hemisphere. It must
      -- read WorldMapFrame -- the same parent as PlayerArrowFrame, the Model that works.
      local pp = ping.GetParent and ping:GetParent()
      local ap = _G.PlayerArrowFrame and _G.PlayerArrowFrame.GetParent and _G.PlayerArrowFrame:GetParent()
      -- LEVEL matters as much as parent: WorldMapFrame is at the BOTTOM of this window's stack, so a
      -- ping left at its parent's level is painted over by the map tiles -- placed correctly and
      -- invisible, which looks like "the ping does not exist".
      say("        level = %s  (canvas %s, pins %s, chrome %s)%s",
          num(ping.GetFrameLevel and ping:GetFrameLevel()),
          num(_G.WorldMapDetailFrame and _G.WorldMapDetailFrame:GetFrameLevel()),
          num(_G.WorldMapPOIFrame and _G.WorldMapPOIFrame:GetFrameLevel()),
          num(WM.border and WM.border:GetFrameLevel()),
          (ping.GetFrameLevel and _G.WorldMapDetailFrame
             and ping:GetFrameLevel() <= _G.WorldMapDetailFrame:GetFrameLevel())
            and "  |cffff4040UNDER THE MAP|r" or "")
      say("        parent = %s  frameScale = %s  (arrow's parent = %s)%s",
          (pp and pp.GetName and pp:GetName()) or tostring(pp), num(ping.GetScale and ping:GetScale()),
          (ap and ap.GetName and ap:GetName()) or tostring(ap),
          (pp and ap and pp ~= ap) and "  |cffff4040MISMATCH|r" or "")
      if ping.GetPoint then
        local pt, rel, rpt, ox, oy = ping:GetPoint(1)
        say("        anchor = %s -> %s %s  offset = %s, %s%s", tostring(pt),
            (rel and rel.GetName and rel:GetName()) or tostring(rel), tostring(rpt),
            num(ox), num(oy),
            -- Sitting ON the arrow is the accurate answer and the one to expect. Falling back to the
            -- canvas means PlayerArrowFrame had no rect to anchor to, and the pulse is then a
            -- second, independently-rounded derivation of the same point -- close, but not exact.
            (WM.pingAnchor == "PlayerArrowFrame") and "  (on the arrow)"
              or "  |cffffd100(derived -- no arrow to sit on)|r")
      end
    elseif WM.pingRebound then
      say("  ping: handed back to the ENGINE, re-bound to %s (db.worldmap.pingClient)",
          tostring(WM.pingRebound))
    else
      say("  ping (ours): |cffff4040not built|r")
    end
    -- The client's, which must be down. If this says shown = yes the squelch has been lost and two
    -- pings are up, one of them in the wrong place.
    local cping = _G.WorldMapPing
    say("        client's ping: %s",
        cping and (cping:IsShown() and "|cffff4040still shown|r" or "squelched") or "absent")
  else
    say("  |cffff4040PlayerArrowFrame missing|r")
  end

  local wz = WM.wheel
  say("  wheel zoom: %s", wz and yn(wz.Enabled and wz.Enabled()) or "|cffff4040module absent|r")

  -- The filter, and what each category currently reads. Reported from the OWNING module in every
  -- case, so a category that has drifted from the feature it switches shows up here as a mismatch
  -- rather than as a menu tick that lies.
  local pf = WM.filter
  if pf and pf.categories then
    local parts = {}
    for _, c in ipairs(pf.categories) do
      parts[#parts + 1] = c.key .. "=" .. yn(pf.Get(c.key))
    end
    say("  filter: button %s  atlas %s  %s",
        pf.button and "|cff40ff40built|r" or "|cffff4040MISSING|r",
        (pf.button and pf.button._neAtlasApplied)
          and ("|cff40ff40" .. tostring(pf.button._neAtlasApplied) .. "|r")
          or "|cffff4040NOT APPLIED|r",
        table.concat(parts, "  "))
    say("    questPOI cvar = %s", yn(GetCVarBool and GetCVarBool("questPOI")))
  end

  -- The magnifier. Which frames it actually adopted is the thing to look at first if the map ever
  -- draws outside the window: anything NOT in the viewport is not being clipped.
  local cz = WM.canvaszoom
  if cz then
    local rx, ry = cz.Range()
    say("  magnify: pan-guard on %s", tostring(cz._wrappedFns or "|cffff4040NOTHING|r"))
    say("  magnify: level %sx  scroll %s/%s  range %s/%s  adopted %s frame(s)",
        num(cz.Level and cz.Level()), num(cz.scrollX), num(cz.scrollY), num(rx), num(ry),
        tostring(cz.adoptedCount or 0))
    local vp = cz.viewport
    if vp then
      say("    viewport %sx%s  content %sx%s",
          num(vp:GetWidth()), num(vp:GetHeight()),
          num(cz.content and cz.content:GetWidth()), num(cz.content and cz.content:GetHeight()))
    end
    for _, n in ipairs({ "WorldMapDetailFrame", "WorldMapButton", "WorldMapFrameAreaFrame",
                         "WorldMapPlayerUpper", "WorldMapBlobFrame" }) do
      local w = _G[n]
      if w then
        local inside = cz.content and w:GetParent() == cz.content
        say("    %-24s clipped = %s", n,
            inside and "|cff40ff40yes|r" or (n == "WorldMapBlobFrame" and "no (protected, by design)"
                                             or "|cffff4040NO|r"))
      end
    end
  end

  -- Which way round the maximize button actually is. Reported rather than reasoned about: the glyph
  -- and the tooltip now share one source, so if they still disagree with the window the fault is the
  -- atlas mapping and this line names the atlas to swap.
  local b = _G.NE_WorldMapMaxMinButton
  if b then
    local nt = b.GetNormalTexture and b:GetNormalTexture()
    -- All four answers on one line, because the three faults this control has had were told apart
    -- only by which of them disagreed: the window's mode, the button's answer, the glyph it drew and
    -- the word it offered.
    local tip = "?"
    if b.IsMaximized then
      tip = b:IsMaximized() and (_G.MINIMIZE or "Minimize") or (_G.MAXIMIZE or "Maximize")
    end
    say("  maxmin: window maximized = %s  button says = %s  glyph = %s  tooltip = %s",
        yn(WM.maximized), yn(b.IsMaximized and b:IsMaximized()),
        tostring(b._neGlyph or "?"), tostring(tip))
    -- Labelled for what they ARE. These two read 1183.00 and 1183.0016 in the field and the second
    -- was captioned "preset" -- it is the RESTORE width, and the two being equal was the whole bug.
    say("    canvasW=%s  restoreW=%s  MINIMIZE=%s MAXIMIZE=%s",
        num(WM.CurrentCanvasWidth and WM.CurrentCanvasWidth()),
        tostring(NE.db and NE.db.worldmap and NE.db.worldmap.restoreW),
        tostring(_G.MINIMIZE), tostring(_G.MAXIMIZE))
  end
end

local SECTIONS = {
  mode   = dumpMode,
  canvas = dumpCanvas,
  art    = dumpArt,
  chrome = dumpChrome,
  navbar = dumpNavBar,
  panel  = dumpPanel,
  squelch = dumpSquelch,
  leftover = dumpLeftoverArt,
  fog     = dumpFog,
  addons  = dumpNeighbours,
  pins    = dumpPins,
}

local ORDER = { "mode", "canvas", "chrome", "navbar", "panel", "pins", "fog", "addons", "art", "squelch",
                "leftover" }

SLASH_NEWORLDMAP1 = "/neworldmap"
SLASH_NEWORLDMAP2 = "/nemap"
SlashCmdList["NEWORLDMAP"] = function(msg)
  msg = (msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
  if not _G.WorldMapFrame then
    say("|cffff4040WorldMapFrame does not exist|r — nothing to report.")
    return
  end
  if msg ~= "" and SECTIONS[msg] then
    SECTIONS[msg]()
    return
  end
  if msg ~= "" then
    say("unknown section %q. One of: %s", msg, table.concat(ORDER, ", "))
    return
  end
  say("---- world map ----")
  for _, key in ipairs(ORDER) do SECTIONS[key]() end
  say("---- end ----  (/neworldmap <section> for just one: %s)", table.concat(ORDER, ", "))
end
