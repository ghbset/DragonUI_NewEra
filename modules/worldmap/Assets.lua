-- DragonUI_NewEra/modules/worldmap/Assets.lua — art registration for the world map.
--
-- DOWNPORT of NewEra/WorldMap/Assets.lua. The 1.15 source registers a handful of sheets by FDID and
-- lets the engine's own atlas registry supply the coordinates; 3.3.5a has no such registry, so every
-- rect below is transcribed from `ReferenceAddons/NewEra/Generated/AtlasData.lua` — the reference
-- addon's generated atlas database, which is the authority for all of them. Nothing here was
-- measured by eye.
--
-- THE ONE RULE: never register an FDID whose BLP is not on disk. RegisterLocal only installs a
-- redirect, so a missing file does not error — the texture silently fails to load and everything
-- using it renders BLANK, with nothing to say why. (The 1.15 source's own Assets.lua closes with
-- exactly that warning.) Every sheet below is in Textures/WorldMap/ or Textures/Spellbook/.
--
-- The breadcrumb's three sheets are NOT here: they moved to core/NavBar.lua with the widget they
-- dress, when the map's breadcrumb and the Adventure Guide's became one implementation.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end
if not (NE.tex and NE.tex.RegisterLocal) then return end

NE.worldmap = NE.worldmap or {}

local MAP_ART    = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\WorldMap\\"
local COMMON_ART = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\"
local SB_ART     = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Spellbook\\"

-- ---------------------------------------------------------------------------------------
-- Sheets
-- ---------------------------------------------------------------------------------------

-- The shared world-map landmark sheet. This client serves the VANILLA layout at
-- Interface\Minimap\POIIcons; retail's 256x512 sheet has the same grid with modern art, so the
-- client's own WorldMap_GetPOITextureCoords crop still lands on the right icon after a straight file
-- substitution. That is why the swap needs no coordinate table of its own (Pins.lua).
NE.tex.RegisterLocal(136441, COMMON_ART .. "136441-poiicons.blp")
NE.worldmap.poiIconsFDID = 136441

-- The quest-log chrome sheet. Already on disk for the spellbook, and it carries most of the panel:
-- the zone-header tab, the tracking tick, the cog, the collapse arrows, the row glow, the frame.
NE.tex.RegisterLocal(5684744, SB_ART .. "5684744-questlog.blp")

NE.tex.RegisterLocal(5684755, MAP_ART .. "5684755-questlogbackground.blp")   -- the panel parchment
NE.tex.RegisterLocal(5684767, MAP_ART .. "5684767-questlogframe2x.blp")      -- 2x border, for big windows
NE.tex.RegisterLocal(5151356, MAP_ART .. "5151356-questlogquesttypeicons.blp")
NE.tex.RegisterLocal(5320914, MAP_ART .. "5320914-questmapicons.blp")
NE.tex.RegisterLocal(904010,  MAP_ART .. "904010-questmaplogatlas.blp")
NE.tex.RegisterLocal(5756295, MAP_ART .. "5756295-minimapfilter.blp")
NE.tex.RegisterLocal(3500068, MAP_ART .. "3500068-waypoinmappinui.blp")
NE.tex.RegisterLocal(1121272, MAP_ART .. "1121272-objecticonsatlas.blp")
-- These four are OVERRIDES, not additions: this client ships older, lower-detail art at the same
-- Interface\Minimap\ paths, so loading by FDID through NE.tex is what picks up the modern version.
NE.tex.RegisterLocal(136430,  MAP_ART .. "136430-minimap-trackingborder.blp")
NE.tex.RegisterLocal(136467,  MAP_ART .. "136467-ui-minimap-background.blp")
NE.tex.RegisterLocal(136477,  MAP_ART .. "136477-ui-minimap-zoombutton-highlight.blp")
NE.tex.RegisterLocal(3509691, MAP_ART .. "3509691-ui-minimap-zoombutton-toggle.blp")

-- ---------------------------------------------------------------------------------------
-- The quest-log panel
-- ---------------------------------------------------------------------------------------

NE.tex.RegisterAtlases({
  -- The parchment the quest list sits on. 307x510 native.
  ["questlog-main-background"]      = { file = 5684755, left = 0.302734, right = 0.602539, top = 0.001953, bottom = 0.998047, width = 307, height = 510 },
  -- The border around the list, and the filigree that caps it. `questlog-frame` is a 9-slice with
  -- 53px margins (AtlasSlice.lua) -- see QuestLogPanel for which of it is drawn.
  ["questlog-frame"]                = { file = 5684744, left = 0.001953, right = 0.210938, top = 0.076172, bottom = 0.285156, width = 107, height = 107 },
  ["questlog-frame-filigree"]       = { file = 5684744, left = 0.001953, right = 0.095703, top = 0.035156, bottom = 0.072266, width = 48,  height = 19  },
  ["questlog-frame-gradient-bottom"]= { file = 5684744, left = 0.214844, right = 0.814453, top = 0.076172, bottom = 0.205078, width = 307, height = 66  },
  -- The zone-header bar. A HORIZONTAL 3-slice: 18px end caps, stretched middle (AtlasSlice.lua
  -- l=18 r=18 t=0 b=0), which is why it cannot simply be stretched whole.
  ["questlog-tab"]                  = { file = 5684744, left = 0.001953, right = 0.126953, top = 0.289062, bottom = 0.332031, width = 64,  height = 22  },
  -- The +/- on a zone header.
  -- The map's filter button. Keys are LOWERCASE, which is the whole reason the button drew as a
  -- Blizzard panel button on first run: it was asked for "Map-Filter-Button", nothing matched, the
  -- SetAtlas call was pcall'd, and the seed texture stayed. Rects transcribed from NewEra's
  -- AtlasData.lua (lines 8285-8286).
  ["map-filter-button"]             = { file = 5756295, left = 0.398438, right = 0.773438, top = 0.015625, bottom = 0.765625, width = 48, height = 48 },
  ["map-filter-button-down"]        = { file = 5756295, left = 0.007812, right = 0.382812, top = 0.015625, bottom = 0.765625, width = 48, height = 48 },
  ["questlog-icon-expand"]          = { file = 5684744, left = 0.099609, right = 0.134766, top = 0.035156, bottom = 0.070312, width = 18,  height = 18  },
  ["questlog-icon-shrink"]          = { file = 5684744, left = 0.171875, right = 0.207031, top = 0.035156, bottom = 0.070312, width = 18,  height = 18  },
  -- The tracking checkbox, and its tick.
  ["questlog-icon-ticksquare"]      = { file = 5684744, left = 0.224609, right = 0.251953, top = 0.001953, bottom = 0.029297, width = 14,  height = 14  },
  ["questlog-icon-checkmark-yellow"]= { file = 5684744, left = 0.187500, right = 0.220703, top = 0.001953, bottom = 0.029297, width = 17,  height = 14  },
  -- The cog in the panel's top band.
  ["questlog-icon-setting"]         = { file = 5684744, left = 0.138672, right = 0.167969, top = 0.035156, bottom = 0.066406, width = 15,  height = 16  },
  -- The hover highlight on a row. A soft glow, so stretching it to any row width is fine.
  ["questlog-quest-glow-yellow"]    = { file = 5684744, left = 0.214844, right = 0.791016, top = 0.322266, bottom = 0.419922, width = 295, height = 50  },
})

-- The badge beside a quest's title. This client reports the tag through GetQuestLogTitle's
-- `questTag`, so the DATA has always been there and only the art was missing.
NE.tex.RegisterAtlases({
  ["questlog-questtypeicon-dungeon"] = { file = 5151356, left = 0.007812, right = 0.148438, top = 0.664062, bottom = 0.804688, width = 18, height = 18 },
  ["questlog-questtypeicon-raid"]    = { file = 5151356, left = 0.320312, right = 0.460938, top = 0.664062, bottom = 0.804688, width = 18, height = 18 },
  ["questlog-questtypeicon-group"]   = { file = 5151356, left = 0.007812, right = 0.148438, top = 0.820312, bottom = 0.960938, width = 18, height = 18 },
  ["questlog-questtypeicon-pvp"]     = { file = 5151356, left = 0.789062, right = 0.929688, top = 0.195312, bottom = 0.335938, width = 18, height = 18 },
  ["questlog-questtypeicon-daily"]   = { file = 5151356, left = 0.007812, right = 0.148438, top = 0.351562, bottom = 0.492188, width = 18, height = 18 },
  ["questlog-questtypeicon-heroic"]  = { file = 5151356, left = 0.164062, right = 0.304688, top = 0.195312, bottom = 0.335938, width = 18, height = 18 },
  ["questlog-questtypeicon-questfailed"] = { file = 5151356, left = 0.320312, right = 0.460938, top = 0.507812, bottom = 0.648438, width = 18, height = 18 },
})

-- ---------------------------------------------------------------------------------------
-- Canvas overlay art
-- ---------------------------------------------------------------------------------------

NE.tex.RegisterAtlases({
  -- The side-panel toggle's chevrons, in place of the "<" / ">" text characters it drew before.
  ["questcollapse-show-up"]   = { file = 904010, left = 0.862793, right = 0.878418, top = 0.064453, bottom = 0.095703, width = 32, height = 32 },
  ["questcollapse-show-down"] = { file = 904010, left = 0.862793, right = 0.878418, top = 0.031250, bottom = 0.062500, width = 32, height = 32 },
  ["questcollapse-hide-up"]   = { file = 904010, left = 0.536133, right = 0.551758, top = 0.966797, bottom = 0.998047, width = 32, height = 32 },
  ["questcollapse-hide-down"] = { file = 904010, left = 0.536133, right = 0.551758, top = 0.933594, bottom = 0.964844, width = 32, height = 32 },
  -- The drop shadow retail puts under the canvas's round corner buttons.
  ["mapcornershadow-right"]   = { file = 904010, left = 0.468750, right = 0.491211, top = 0.933594, bottom = 0.985352, width = 46, height = 53 },
})

-- REGISTERED BUT NOT YET CONSUMED. The sheets are on disk and the rects are transcribed, so wiring
-- these is a matter of building the UI that uses them rather than of finding art:
--   * 5756295 `Map-Filter-Button` and 3500068 `Waypoint-MapPin-*`, plus the 136430/136467/136477/
--     3509691 tracking-button chrome, are the two round buttons at the canvas's top-right. They want
--     the tracking/filters menu behind them (PORT_PLAN.md Phase 5) -- a button that opens nothing is
--     worse than no button.
--   * 1121272 `ObjectIconsAtlas` is the modern shared POI set (dungeon, raid, taxi node, innkeeper,
--     mailbox), which would finish the pin restyle 136441 started.
--   * 5320914 `ui-questpoi-questnumber` is the numbered POI blip. It needs the number the CLIENT
--     assigned that quest on the map, not the row's position in our list, or the badge and the pin
--     disagree -- which is worse than no badge.
--   * 5684767 is the 2x quest-log sheet, for a crisp border once the window is dragged large.
NE.worldmap.artNotes = "see modules/worldmap/ART_AUDIT.md"
