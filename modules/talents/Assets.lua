-- DragonUI_NewEra/modules/talents/Assets.lua — Talent node-art atlas registration (Agent ASSETS).
--
-- DOWNPORT of NewEra/Talents/Assets.lua. NewEra reads its node texcoords from the generated
-- NE_ATLAS table (Generated/AtlasData.lua); here we TRANSCRIBE the rects we need into
-- NE.tex.atlases via NE.tex.RegisterAtlases (architect decision — coords live in NE.tex.atlases,
-- see core/Texture.lua; same pattern as modules/spellbook/Assets.lua).
--
-- IMPORTANT — the master node sheet 4556093-talents.blp is ALREADY shipped and ALREADY
-- NE.tex.RegisterLocal'd in modules/spellbook/Assets.lua. We do NOT re-ship the BLP and do NOT
-- re-register the file path. We only ADD atlas-name -> texcoord entries pointing at file=4556093.
--
-- Rects transcribed verbatim from NewEra/Generated/AtlasData.lua (all on sheet 4556093). The
-- magnitudes/format match the talents-* entries already in spellbook/Assets.lua (same sheet).
--
-- NewEra's renderer (Talents/Talents.lua ringAtlas) builds the border atlas as
-- "<stem>-<state>" where stem is talents-node-square / -circle / -apex-large and state is one of
-- gray|green|yellow|locked|red. There is NO bare "talents-node-square" atlas — only the per-state
-- variants. So we register the full state set for each of the three node shapes (minus the two
-- -gray base frames already registered by spellbook), plus -greenglow / -shadow / apex -glow, plus
-- the arrow heads, gate, and reset/undo buttons.

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterAtlases) then return end

local T = NE.talents or {}
NE.talents = T

-- ============================================================================
-- Node border state frames (sheet 4556093).
--   ALREADY registered in spellbook/Assets.lua (do NOT duplicate here):
--     talents-node-circle-gray, talents-node-square-gray, talents-sheen-node,
--     talents-node-circle-mask, talents-node-circle-sheenmask.
--   So the -gray base frame for square/circle is intentionally absent below.
-- ============================================================================

-- Square node — remaining border states + selectable greenglow + drop shadow.
NE.tex.RegisterAtlases({
  ["talents-node-square-green"]     = { file=4556093, left=0.490723, right=0.529785, top=0.879883, bottom=0.958008, width=40, height=40 },
  ["talents-node-square-yellow"]    = { file=4556093, left=0.534180, right=0.573242, top=0.732422, bottom=0.810547, width=40, height=40 },
  ["talents-node-square-locked"]    = { file=4556093, left=0.534180, right=0.573242, top=0.572266, bottom=0.650391, width=40, height=40 },
  ["talents-node-square-red"]       = { file=4556093, left=0.534180, right=0.573242, top=0.652344, bottom=0.730469, width=40, height=40 },
  ["talents-node-square-greenglow"] = { file=4556093, left=0.136230, right=0.218262, top=0.700195, bottom=0.864258, width=84, height=84 },
  ["talents-node-square-shadow"]    = { file=4556093, left=0.229004, right=0.267090, top=0.922852, bottom=0.999023, width=78, height=78 },
})

-- Circle node — remaining border states + selectable greenglow + drop shadow.
NE.tex.RegisterAtlases({
  ["talents-node-circle-green"]     = { file=4556093, left=0.106934, right=0.131348, top=0.606445, bottom=0.655273, width=40, height=40 },
  ["talents-node-circle-yellow"]    = { file=4556093, left=0.678223, right=0.702637, top=0.107422, bottom=0.156250, width=40, height=40 },
  ["talents-node-circle-locked"]    = { file=4556093, left=0.106934, right=0.131348, top=0.657227, bottom=0.706055, width=40, height=40 },
  ["talents-node-circle-red"]       = { file=4556093, left=0.106934, right=0.131348, top=0.708008, bottom=0.756836, width=40, height=40 },
  ["talents-node-circle-greenglow"] = { file=4556093, left=0.873047, right=0.913086, top=0.000977, bottom=0.081055, width=82, height=82 },
  ["talents-node-circle-shadow"]    = { file=4556093, left=0.534180, right=0.571289, top=0.888672, bottom=0.962891, width=76, height=76 },
})

-- Apex (capstone) node — full state set + the apex glow (named -glow, no -green prefix).
-- The apex shape REUSES talents-node-square-shadow for its drop shadow (see shadowAtlas in
-- Talents.lua), so no separate apex shadow is needed.
NE.tex.RegisterAtlases({
  ["talents-node-apex-large-gray"]   = { file=4556093, left=0.093262, right=0.134277, top=0.768555, bottom=0.850586, width=84, height=84 },
  ["talents-node-apex-large-green"]  = { file=4556093, left=0.093262, right=0.134277, top=0.852539, bottom=0.934570, width=84, height=84 },
  ["talents-node-apex-large-yellow"] = { file=4556093, left=0.490723, right=0.531738, top=0.475586, bottom=0.557617, width=84, height=84 },
  ["talents-node-apex-large-locked"] = { file=4556093, left=0.490723, right=0.531738, top=0.307617, bottom=0.389648, width=84, height=84 },
  ["talents-node-apex-large-red"]    = { file=4556093, left=0.490723, right=0.531738, top=0.391602, bottom=0.473633, width=84, height=84 },
  ["talents-node-apex-large-glow"]   = { file=4556093, left=0.229004, right=0.301270, top=0.776367, bottom=0.920898, width=148, height=148 },
})

-- ============================================================================
-- Edge art (arrow heads), prereq gate, and the reset/undo chrome buttons.
-- ============================================================================
NE.tex.RegisterAtlases({
  ["talents-arrow-head-gray"]   = { file=4556093, left=0.421387, right=0.435059, top=0.144531, bottom=0.167969, width=14, height=12 },
  ["talents-arrow-head-yellow"] = { file=4556093, left=0.465332, right=0.479004, top=0.144531, bottom=0.167969, width=14, height=12 },
  ["talents-gate"]              = { file=4556093, left=0.000488, right=0.082520, top=0.965820, bottom=0.993164, width=84, height=14 },
  ["talents-button-reset"]      = { file=4556093, left=0.770020, right=0.789551, top=0.107422, bottom=0.146484, width=20, height=20 },
  ["talents-button-undo"]       = { file=4556093, left=0.748535, right=0.769043, top=0.107422, bottom=0.146484, width=21, height=20 },
  -- Bottom-bar strip (the solid bar behind Apply/Reset/points) — same shipped 4556093 sheet. The
  -- scaffold's f.bottomBar already SetAtlas'es this name; it was just never registered.
  ["talents-background-bottombar"] = { file=4556093, left=0.000488, right=0.787598, top=0.000977, bottom=0.081055, width=1612, height=82 },
})

-- ============================================================================
-- DROPPED (out of scope this phase — NOT registered here):
--   * Mask / sheenmask atlases on separate (not-this-sheet) BLPs:
--       talents-node-square-sheenmask (4731572), talents-node-apex-large-mask (7532041),
--       talents-node-apex-bar (7532048). talents-node-circle-mask / -circle-sheenmask are
--       already registered by spellbook/Assets.lua.
--   * Animation sheets: talents-animations-clouds (4723109), -animations-particles (4732064),
--       -animations-mask-full (4722778).
-- ============================================================================

-- ============================================================================
-- Spec backgrounds (DATA ONLY this phase).
--   The 18 background painting sheets + their 27 per-spec atlas rects are a SEPARATE art step
--   and are NOT registered here. We port the class/spec -> atlas-name map + the default-tab
--   constant so the data exists; CLASS_BACKGROUND entries may reference not-yet-registered
--   atlases (they no-op until a later step registers them — that's expected).
-- ============================================================================

-- Background nickname PER TAB, in the talent-tab order GetNumTalentTabs returns (index 1..3).
-- The render code shows the DOMINANT spec's background (tab with most points spent). classFile =
-- the UPPER-CASE token from UnitClass. Each nickname's texcoords will be registered later.
T.CLASS_BACKGROUND = {
  WARRIOR = { "talents-background-warrior-arms",          "talents-background-warrior-fury",        "talents-background-warrior-protection" },
  PALADIN = { "talents-background-paladin-holy",          "talents-background-paladin-protection",  "talents-background-paladin-retribution" },
  HUNTER  = { "talents-background-hunter-beastmastery",   "talents-background-hunter-marksmanship", "talents-background-hunter-survival" },
  ROGUE   = { "talents-background-rogue-assassination",   "talents-background-rogue-outlaw",        "talents-background-rogue-subtlety" },
  PRIEST  = { "talents-background-priest-discipline",     "talents-background-priest-holy",         "talents-background-priest-shadow" },
  SHAMAN  = { "talents-background-shaman-elemental",      "talents-background-shaman-enhancement",  "talents-background-shaman-restoration" },
  MAGE    = { "talents-background-mage-arcane",           "talents-background-mage-fire",           "talents-background-mage-frost" },
  WARLOCK = { "talents-background-warlock-affliction",    "talents-background-warlock-demonology",  "talents-background-warlock-destruction" },
  DRUID   = { "talents-background-druid-balance",         "talents-background-druid-feral",         "talents-background-druid-restoration" },
}
-- Fallback used before the dominant tab is known (no points yet).
T.DEFAULT_BACKGROUND_TAB = 1

-- Spec backgrounds (Phase-1 art step DONE): 9 classes x 3 trees = 27 atlases on 18 sheets.
-- Sheets downscaled 2048->1024 POT (2048-wide crashes this client) via blpconverter; rects are
-- the ORIGINAL normalized texcoords (resolution-independent). DEATHKNIGHT bg art absent in the
-- NewEra source (4631290/4631293 not shipped) -> DK falls back to warrior-arms via BackgroundNick.

NE.tex.RegisterLocal(4631392, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631392-talents-bg.blp")
NE.tex.RegisterLocal(4631395, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631395-talents-bg.blp")
NE.tex.RegisterLocal(4631337, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631337-talents-bg.blp")
NE.tex.RegisterLocal(4631340, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631340-talents-bg.blp")
NE.tex.RegisterLocal(4631310, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631310-talents-bg.blp")
NE.tex.RegisterLocal(4631313, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631313-talents-bg.blp")
NE.tex.RegisterLocal(4631374, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631374-talents-bg.blp")
NE.tex.RegisterLocal(4631377, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631377-talents-bg.blp")
NE.tex.RegisterLocal(4631348, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631348-talents-bg.blp")
NE.tex.RegisterLocal(4631371, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631371-talents-bg.blp")
NE.tex.RegisterLocal(4631381, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631381-talents-bg.blp")
NE.tex.RegisterLocal(4631383, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631383-talents-bg.blp")
NE.tex.RegisterLocal(4631318, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631318-talents-bg.blp")
NE.tex.RegisterLocal(4631321, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631321-talents-bg.blp")
NE.tex.RegisterLocal(4631386, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631386-talents-bg.blp")
NE.tex.RegisterLocal(4631389, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631389-talents-bg.blp")
NE.tex.RegisterLocal(4631299, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631299-talents-bg.blp")
NE.tex.RegisterLocal(4631304, "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\4631304-talents-bg.blp")

NE.tex.RegisterAtlases({
  ["talents-background-warrior-arms"] = { file=4631392, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-warrior-fury"] = { file=4631392, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-warrior-protection"] = { file=4631395, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-paladin-holy"] = { file=4631337, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-paladin-protection"] = { file=4631337, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-paladin-retribution"] = { file=4631340, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-hunter-beastmastery"] = { file=4631310, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-hunter-marksmanship"] = { file=4631310, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-hunter-survival"] = { file=4631313, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-rogue-assassination"] = { file=4631374, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-rogue-outlaw"] = { file=4631374, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-rogue-subtlety"] = { file=4631377, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-priest-discipline"] = { file=4631348, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-priest-holy"] = { file=4631348, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-priest-shadow"] = { file=4631371, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-shaman-elemental"] = { file=4631381, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-shaman-enhancement"] = { file=4631381, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-shaman-restoration"] = { file=4631383, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-mage-arcane"] = { file=4631318, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-mage-fire"] = { file=4631318, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-mage-frost"] = { file=4631321, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-warlock-affliction"] = { file=4631386, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-warlock-demonology"] = { file=4631386, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-warlock-destruction"] = { file=4631389, left=0.000488, right=0.787598, top=0.000977, bottom=0.756836, width=1612, height=774 },
  ["talents-background-druid-balance"] = { file=4631299, left=0.000488, right=0.787598, top=0.000488, bottom=0.378418, width=1612, height=774 },
  ["talents-background-druid-feral"] = { file=4631299, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
  ["talents-background-druid-restoration"] = { file=4631304, left=0.000488, right=0.787598, top=0.379395, bottom=0.757324, width=1612, height=774 },
})
