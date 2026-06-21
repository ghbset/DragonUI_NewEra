-- DragonUI_NewEra/core/NineSliceLayouts.lua — retail nineslice layout data + the atlas COORD
-- tables the Core agent owns.
--
-- DOWNPORT: NewEra Core/NineSliceLayouts.lua → 3.3.5a. NewEra's layouts referenced retail atlas
-- nicknames that resolved through the GENERATED NE_ATLAS global. Per the ARCHITECT DECISION
-- (CONTRACTS §2): the Core agent OWNS the atlas COORD tables. So this file does two jobs:
--   (1) RegisterAtlas the coord rects for every atlas these layouts use (transcribed from
--       NewEra's Generated/AtlasData.lua — the exact left/right/top/bottom + width/height).
--   (2) AddLayout the nineslice piece tables (verbatim from NewEra, minus retail-only fields).
-- The Asset agent (Textures/Assets.lua) supplies fdid→BLP path via NE.tex.RegisterLocal; we
-- supply atlas-name→{fdid, coords}. We do NOT call NE.tex.RegisterLocal here (that's §3's job).
--
-- Coord entries are { file=<FDID>, left=, right=, top=, bottom=, width=, height= }, identical to
-- NewEra's NE_ATLAS rows so the texcoords are pixel-correct against the same BLP sheets.

local NE = DragonUI_NewEra
NE.nineslice = NE.nineslice or {}
NE.nineslice.layouts = NE.nineslice.layouts or {}

-- ============================================================================
-- ATLAS COORD TABLES (owned by Core; transcribed from NewEra Generated/AtlasData.lua)
-- ============================================================================
-- UI-Frame-Metal family (corners FDID 2406979, vert edges 2406984, horiz edges 2406987),
-- the PortraitMetal corner, the InsetFrameTemplate inner-border (1723831/1723832/1723833),
-- and the TopTileStreaks band (1723833). These are the Sprint-0 minimum atlas set (§3).
NE.tex.RegisterAtlases({
  -- Metal corners (sheet 2406979).
  ["ui-frame-metal-cornertopleft-2x"]        = { file = 2406979, left = 0.001953, right = 0.294922, top = 0.001953, bottom = 0.294922, width = 150, height = 150 },
  ["ui-frame-metal-cornertopright-2x"]       = { file = 2406979, left = 0.298828, right = 0.591797, top = 0.001953, bottom = 0.294922, width = 150, height = 150 },
  ["ui-frame-metal-cornertoprightdouble-2x"] = { file = 2406979, left = 0.595703, right = 0.888672, top = 0.001953, bottom = 0.294922, width = 150, height = 150 },
  ["ui-frame-metal-cornerbottomleft-2x"]     = { file = 2406979, left = 0.298828, right = 0.423828, top = 0.298828, bottom = 0.423828, width = 64,  height = 64  },
  ["ui-frame-metal-cornerbottomright-2x"]    = { file = 2406979, left = 0.427734, right = 0.552734, top = 0.298828, bottom = 0.423828, width = 64,  height = 64  },
  ["ui-frame-portraitmetal-cornertopleft-2x"]= { file = 2406979, left = 0.001953, right = 0.294922, top = 0.298828, bottom = 0.591797, width = 150, height = 150 },
  -- Metal edges (vert-tile sheet 2406984, horiz-tile sheet 2406987).
  ["!ui-frame-metal-edgeleft-2x"]   = { file = 2406984, left = 0.001953, right = 0.294922, top = 0.000000, bottom = 1.000000, width = 150, height = 32  },
  ["!ui-frame-metal-edgeright-2x"]  = { file = 2406984, left = 0.298828, right = 0.591797, top = 0.000000, bottom = 1.000000, width = 150, height = 32  },
  ["_ui-frame-metal-edgetop-2x"]    = { file = 2406987, left = 0.000000, right = 1.000000, top = 0.003906, bottom = 0.589844, width = 64,  height = 150 },
  ["_ui-frame-metal-edgebottom-2x"] = { file = 2406987, left = 0.000000, right = 0.500000, top = 0.597656, bottom = 0.847656, width = 32,  height = 64  },
  -- TopTileStreaks band (sheet 1723833).
  ["_ui-frame-toptilestreaks"]      = { file = 1723833, left = 0.000000, right = 1.000000, top = 0.007812, bottom = 0.343750, width = 256, height = 43  },
  -- InsetFrameTemplate inner border: corners (1723831), L/R tiles (1723832), T/B tiles (1723833).
  ["ui-frame-innertopleft"]       = { file = 1723831, left = 0.757812, right = 0.804688, top = 0.554688, bottom = 0.601562, width = 6, height = 6 },
  ["ui-frame-innertopright"]      = { file = 1723831, left = 0.820312, right = 0.867188, top = 0.554688, bottom = 0.601562, width = 6, height = 6 },
  ["ui-frame-innerbotleftcorner"] = { file = 1723831, left = 0.632812, right = 0.679688, top = 0.554688, bottom = 0.601562, width = 6, height = 6 },
  ["ui-frame-innerbotright"]      = { file = 1723831, left = 0.695312, right = 0.742188, top = 0.554688, bottom = 0.601562, width = 6, height = 6 },
  ["!ui-frame-innerlefttile"]     = { file = 1723832, left = 0.484375, right = 0.531250, top = 0.000000, bottom = 1.000000, width = 3, height = 256 },
  ["!ui-frame-innerrighttile"]    = { file = 1723832, left = 0.562500, right = 0.609375, top = 0.000000, bottom = 1.000000, width = 3, height = 256 },
  ["_ui-frame-innertoptile"]      = { file = 1723833, left = 0.000000, right = 1.000000, top = 0.906250, bottom = 0.929688, width = 256, height = 3 },
  ["_ui-frame-innerbottile"]      = { file = 1723833, left = 0.000000, right = 1.000000, top = 0.867188, bottom = 0.890625, width = 256, height = 3 },
})

-- RedButton close-button family (sheet 4698972) — used by PanelChrome.ModernizeCloseButton.
NE.tex.RegisterAtlases({
  ["redbutton-exit-2x"]          = { file = 4698972, left = 0.152344, right = 0.292969, top = 0.007812, bottom = 0.304688, width = 36, height = 38 },
  ["redbutton-exit-disabled-2x"] = { file = 4698972, left = 0.152344, right = 0.292969, top = 0.320312, bottom = 0.617188, width = 36, height = 38 },
  ["redbutton-exit-pressed-2x"]  = { file = 4698972, left = 0.152344, right = 0.292969, top = 0.632812, bottom = 0.929688, width = 36, height = 38 },
  ["redbutton-highlight-2x"]     = { file = 4698972, left = 0.449219, right = 0.589844, top = 0.007812, bottom = 0.304688, width = 36, height = 38 },
})

-- Panel-tab family (sheet 4707839) — used by Tabs.lua.
NE.tex.RegisterAtlases({
  ["uiframe-tab-left"]          = { file = 4707839, left = 0.015625, right = 0.562500, top = 0.816406, bottom = 0.957031, width = 35, height = 36 },
  ["uiframe-tab-right"]         = { file = 4707839, left = 0.015625, right = 0.593750, top = 0.667969, bottom = 0.808594, width = 37, height = 36 },
  ["_uiframe-tab-center"]       = { file = 4707839, left = 0.000000, right = 0.015625, top = 0.175781, bottom = 0.316406, width = 1,  height = 36 },
  ["uiframe-activetab-left"]    = { file = 4707839, left = 0.015625, right = 0.562500, top = 0.496094, bottom = 0.660156, width = 35, height = 42 },
  ["uiframe-activetab-right"]   = { file = 4707839, left = 0.015625, right = 0.593750, top = 0.324219, bottom = 0.488281, width = 37, height = 42 },
  ["_uiframe-activetab-center"] = { file = 4707839, left = 0.000000, right = 0.015625, top = 0.003906, bottom = 0.167969, width = 1,  height = 42 },
})

-- Minimal-scrollbar family (track/arrows sheet 4331838, thumb caps 5142787, thumb middle
-- 5142784) — used by ScrollbarReskin.lua. These sheets are NOT in the Sprint-0 minimum set, so
-- the scrollbar reskin degrades gracefully (native art kept) until §3 ships them; the coords are
-- registered now so it lights up automatically once the BLPs land.
NE.tex.RegisterAtlases({
  ["minimal-scrollbar-track-top"]    = { file = 4331838, left = 0.164062, right = 0.226562, top = 0.609375, bottom = 0.734375, width = 8, height = 8 },
  ["minimal-scrollbar-track-bottom"] = { file = 4331838, left = 0.085938, right = 0.148438, top = 0.765625, bottom = 0.890625, width = 8, height = 8 },
  ["!minimal-scrollbar-track-middle"]= { file = 4332072, left = 0.015625, right = 0.140625, top = 0.000000, bottom = 0.000977, width = 8, height = 1 },
  ["minimal-scrollbar-arrow-top"]         = { file = 4331838, left = 0.687500, right = 0.820312, top = 0.015625, bottom = 0.187500, width = 17, height = 11 },
  ["minimal-scrollbar-arrow-top-over"]    = { file = 4331838, left = 0.390625, right = 0.523438, top = 0.218750, bottom = 0.390625, width = 17, height = 11 },
  ["minimal-scrollbar-arrow-top-down"]    = { file = 4331838, left = 0.835938, right = 0.968750, top = 0.015625, bottom = 0.187500, width = 17, height = 11 },
  ["minimal-scrollbar-arrow-bottom"]      = { file = 4331838, left = 0.242188, right = 0.375000, top = 0.812500, bottom = 0.984375, width = 17, height = 11 },
  ["minimal-scrollbar-arrow-bottom-over"] = { file = 4331838, left = 0.539062, right = 0.671875, top = 0.015625, bottom = 0.187500, width = 17, height = 11 },
  ["minimal-scrollbar-arrow-bottom-down"] = { file = 4331838, left = 0.390625, right = 0.523438, top = 0.015625, bottom = 0.187500, width = 17, height = 11 },
  ["minimal-scrollbar-small-thumb-middle"]      = { file = 5142784, left = 0.484375, right = 0.609375, top = 0.000977, bottom = 0.699219, width = 8, height = 715 },
  ["minimal-scrollbar-small-thumb-middle-over"] = { file = 5142784, left = 0.328125, right = 0.453125, top = 0.000977, bottom = 0.699219, width = 8, height = 715 },
  ["minimal-scrollbar-small-thumb-middle-down"] = { file = 5142784, left = 0.171875, right = 0.296875, top = 0.000977, bottom = 0.699219, width = 8, height = 715 },
  ["minimal-scrollbar-small-thumb-top"]       = { file = 5142787, left = 0.312500, right = 0.437500, top = 0.843750, bottom = 0.968750, width = 8, height = 8 },
  ["minimal-scrollbar-small-thumb-top-over"]  = { file = 5142787, left = 0.468750, right = 0.593750, top = 0.843750, bottom = 0.968750, width = 8, height = 8 },
  ["minimal-scrollbar-small-thumb-top-down"]  = { file = 5142787, left = 0.468750, right = 0.593750, top = 0.687500, bottom = 0.812500, width = 8, height = 8 },
  ["minimal-scrollbar-small-thumb-bottom"]      = { file = 5142787, left = 0.609375, right = 0.734375, top = 0.484375, bottom = 0.609375, width = 8, height = 8 },
  ["minimal-scrollbar-small-thumb-bottom-over"] = { file = 5142787, left = 0.312500, right = 0.437500, top = 0.687500, bottom = 0.812500, width = 8, height = 8 },
  ["minimal-scrollbar-small-thumb-bottom-down"] = { file = 5142787, left = 0.765625, right = 0.890625, top = 0.484375, bottom = 0.609375, width = 8, height = 8 },
})

-- ============================================================================
-- LAYOUT TABLES (verbatim from NewEra, retail-only fields kept — they're harmless data)
-- ============================================================================

-- The mainline panel chrome (no portrait). Used by non-portrait frames.
NE.nineslice.AddLayout("ButtonFrameTemplateNoPortrait", {
  disableSharpening = true,
  TopLeftCorner     = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopLeft-2x",     w = 75, h = 75, x = -8, y = 16 },
  TopRightCorner    = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopRight-2x",    w = 75, h = 75, x =  4, y = 16 },
  BottomLeftCorner  = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft-2x",  w = 32, h = 32, x = -8, y = -3 },
  BottomRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight-2x", w = 32, h = 32, x =  4, y = -3 },
  TopEdge    = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeTop-2x",    h = 75 },
  BottomEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom-2x", h = 32 },
  LeftEdge   = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeLeft-2x",   w = 75 },
  RightEdge  = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeRight-2x",  w = 75 },
})
-- §2 contract requires "ButtonFrameTemplate" by name — alias it to the no-portrait metal chrome.
NE.nineslice.AddLayout("ButtonFrameTemplate", NE.nineslice.layouts["ButtonFrameTemplateNoPortrait"])

-- InsetFrameTemplate — the THIN GOLD inner border that wraps an inset's content area.
NE.nineslice.AddLayout("InsetFrameTemplate", {
  TopLeftCorner     = { layer = "BORDER", subLevel = -5, atlas = "UI-Frame-InnerTopLeft",        w = 6, h = 6 },
  TopRightCorner    = { layer = "BORDER", subLevel = -5, atlas = "UI-Frame-InnerTopRight",       w = 6, h = 6 },
  BottomLeftCorner  = { layer = "BORDER", subLevel = -5, atlas = "UI-Frame-InnerBotLeftCorner",  w = 6, h = 6, x = 0, y = -1 },
  BottomRightCorner = { layer = "BORDER", subLevel = -5, atlas = "UI-Frame-InnerBotRight",       w = 6, h = 6, x = 0, y = -1 },
  TopEdge    = { layer = "BORDER", subLevel = -5, atlas = "_UI-Frame-InnerTopTile",   h = 3 },
  BottomEdge = { layer = "BORDER", subLevel = -5, atlas = "_UI-Frame-InnerBotTile",   h = 3 },
  LeftEdge   = { layer = "BORDER", subLevel = -5, atlas = "!UI-Frame-InnerLeftTile",  w = 3 },
  RightEdge  = { layer = "BORDER", subLevel = -5, atlas = "!UI-Frame-InnerRightTile", w = 3 },
})

-- PortraitFrameTemplate — same metal family, with the circular-cutout top-left corner.
NE.nineslice.AddLayout("PortraitFrameTemplate", {
  disableSharpening = true,
  TopLeftCorner     = { layer = "OVERLAY", atlas = "UI-Frame-PortraitMetal-CornerTopLeft-2x", w = 75, h = 75, x = -13, y = 16 },
  TopRightCorner    = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopRight-2x",        w = 75, h = 75, x =   4, y = 16 },
  BottomLeftCorner  = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft-2x",      w = 32, h = 32, x = -13, y = -3 },
  BottomRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight-2x",     w = 32, h = 32, x =   4, y = -3 },
  TopEdge    = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeTop-2x",    h = 75 },
  BottomEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom-2x", h = 32 },
  LeftEdge   = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeLeft-2x",   w = 75 },
  RightEdge  = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeRight-2x",  w = 75 },
})

-- PortraitFrameTemplateMinimizable — "Double" right corner (max/min button room).
NE.nineslice.AddLayout("PortraitFrameTemplateMinimizable", {
  disableSharpening = true,
  TopLeftCorner     = { layer = "OVERLAY", atlas = "UI-Frame-PortraitMetal-CornerTopLeft-2x",  w = 75, h = 75, x = -13, y = 16 },
  TopRightCorner    = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopRightDouble-2x",   w = 75, h = 75, x =   4, y = 16 },
  BottomLeftCorner  = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft-2x",       w = 32, h = 32, x = -13, y = -3 },
  BottomRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight-2x",      w = 32, h = 32, x =   4, y = -3 },
  TopEdge    = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeTop-2x",    h = 75 },
  BottomEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom-2x", h = 32 },
  LeftEdge   = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeLeft-2x",   w = 75 },
  RightEdge  = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeRight-2x",  w = 75 },
})

-- ButtonFrameTemplateNoPortraitMinimizable — plain metal frame WITH the Double top-right corner.
NE.nineslice.AddLayout("ButtonFrameTemplateNoPortraitMinimizable", {
  disableSharpening = true,
  TopLeftCorner     = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopLeft-2x",        w = 75, h = 75, x = -12, y = 16 },
  TopRightCorner    = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopRightDouble-2x", w = 75, h = 75, x =   4, y = 16 },
  BottomLeftCorner  = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft-2x",     w = 32, h = 32, x = -12, y = -3 },
  BottomRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight-2x",    w = 32, h = 32, x =   4, y = -3 },
  TopEdge    = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeTop-2x",    h = 75 },
  BottomEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom-2x", h = 32 },
  LeftEdge   = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeLeft-2x",   w = 75 },
  RightEdge  = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeRight-2x",  w = 75 },
})

-- HeldBagLayout — PortraitFrameTemplate with the SMALL portrait corner (36x36 portrait).
-- DOWNPORT: NewEra used "UI-Frame-PortraitMetal-CornerTopLeftSmall-2x"; that small-cutout corner
-- isn't in the Sprint-0 sheet set, so we reuse the standard portrait corner. The piece falls back
-- gracefully (SetAtlas returns false → piece hidden) if the small variant isn't registered.
NE.nineslice.AddLayout("HeldBagLayout", {
  disableSharpening = true,
  TopLeftCorner     = { layer = "OVERLAY", atlas = "UI-Frame-PortraitMetal-CornerTopLeft-2x", w = 75, h = 75, x = -13, y = 16 },
  TopRightCorner    = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerTopRight-2x",        w = 75, h = 75, x =   4, y = 16 },
  BottomLeftCorner  = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomLeft-2x",      w = 32, h = 32, x = -13, y = -3 },
  BottomRightCorner = { layer = "OVERLAY", atlas = "UI-Frame-Metal-CornerBottomRight-2x",     w = 32, h = 32, x =   4, y = -3 },
  TopEdge    = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeTop-2x",    h = 75 },
  BottomEdge = { layer = "OVERLAY", atlas = "_UI-Frame-Metal-EdgeBottom-2x", h = 32 },
  LeftEdge   = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeLeft-2x",   w = 75 },
  RightEdge  = { layer = "OVERLAY", atlas = "!UI-Frame-Metal-EdgeRight-2x",  w = 75 },
})
