-- DragonUI_NewEra/modules/character/Assets.lua — CharacterPanel art registration (Sprint 1, Agent F).
--
-- DOWNPORT: mirrors NewEra/CharacterPanel/Assets.lua, but
--   (1) paths point at OUR addon (Textures\CharacterPanel\...), and
--   (2) the atlas-name -> texcoord rects that NewEra read from its generated global NE_ATLAS are
--       TRANSCRIBED here into NE.tex.atlases via NE.tex.RegisterAtlases (architect decision:
--       coords live in NE.tex.atlases, NOT C_Texture.RegisterAtlas — the 3.3.5a client has no
--       native atlas DB; see core/Texture.lua + Textures/Assets.lua ARCHITECT DECISION block).
--
-- This file ships ONLY the CharacterPanel-SPECIFIC sheets + the atlas families that Core does NOT
-- already register. Shared chrome (UI-Frame-Metal nineslice, UI-Background-Rock, InsetFrame inner-
-- border, tab sheet 4707839, RedButton close 4698972, minimal-scrollbar family) lives in Core's
-- Textures/Assets.lua and is consumed from there — do NOT re-register it here (disabling this
-- module must not drop shared art from Social/Battlefield/etc.).
--
-- Source coord rects transcribed from NewEra/Generated/AtlasData.lua (build 12.0.5.67451):
--   ui-character-info-<class>-bg   -> AtlasData.lua:13756-13770
--   classicon-<class>              -> AtlasData.lua:2402-2414
--   options_listexpand_*           -> AtlasData.lua:519,8672-8674
--   common-icon-{zoomin,...,undo}  -> AtlasData.lua:2762-2779
--   common-button-square-gray-*    -> AtlasData.lua:2570-2571

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\CharacterPanel\\"

-- ============================================================================
-- 1. fdid -> shipped BLP path  (NE.tex.RegisterLocal)
-- ============================================================================

-- Class-themed PaperDoll backgrounds (UI-Character-Info-<Class>-bg + Title/Line/ItemLevel bounce).
NE.tex.RegisterLocal(1400895, P .. "1400895-character-info-classes-a.blp")   -- 1024x1024 DXT5; Mage/Monk/Paladin/Priest/Rogue/Shaman/Warlock/Warrior
NE.tex.RegisterLocal(1400896, P .. "1400896-character-info-classes-b.blp")   -- 1024x512  DXT5; DeathKnight/DemonHunter/Druid/Hunter
NE.tex.RegisterLocal(5882640, P .. "5882640-character-panel-background.blp") -- 1024x512  DXT5; retail overall pane bg

-- Class-icon sheet (12 classes, 128x128 each). Portrait.lua swaps the portrait to the class icon
-- on the PaperDoll tab (architect decision: CLASS icon, not spec icon — no spec system on 3.3.5a).
-- DOWNPORT(user): class icons are CIRCULAR. The retail 1662186 sheet is SQUARE (NewEra masks it with
-- CreateMaskTexture, which returns nil on 3.3.5a). So we baked a circular alpha mask into each class
-- cell offline (DXT5→DDS decode → per-cell circle mask → TGA). Same layout, so the texcoords below
-- are unchanged. Half-res (1024x512) RLE TGA; normalized texcoords are resolution-independent.
NE.tex.RegisterLocal(1662186, P .. "1662186-classicon.blp")                  -- circular class icons (baked)

-- Char-Paperdoll-{Parts,Horizontal,Vertical} — inner-border edges/corners + slot frames.
NE.tex.RegisterLocal(410247, P .. "410247-charpaperdoll.blp")                -- 32x16  DXT5; horizontal h-tile edges
NE.tex.RegisterLocal(410248, P .. "410248-charpaperdoll.blp")                -- 256x128 DXT5; parts (corners, slot frames, gap-fillers)
NE.tex.RegisterLocal(410249, P .. "410249-charpaperdoll.blp")                -- 16x32  DXT5; vertical v-tile edges

-- Model controls (modern square buttons + icon overlays). NOTE: both these sheets are uncompressed
-- ARGB8888 (BLP2 encoding 3) — large but 3.3.5a-loadable; see ASSETS.md validation notes.
NE.tex.RegisterLocal(3534438, P .. "3534438-common-buttons-icons.blp")       -- 1024x1024 DXT5; common-button-square-gray-{up,down}
NE.tex.RegisterLocal(3487944, P .. "3487944-common-buttons-icons.blp")       -- 2048x1024 ARGB8888; common-icon-* family

-- Options_ListExpand — collapsible faction/skill header art (uncompressed ARGB8888).
NE.tex.RegisterLocal(4571485, P .. "4571485-options-listexpand.blp")         -- 128x128 ARGB8888

-- UI-Character-ReputationBar end caps (ReputationBarTemplate).
NE.tex.RegisterLocal(136567, P .. "136567-ui-character-reputationbar.blp")   -- 256x64 DXT5
-- NOTE: source ships NO 136570 sheet (contract listed it as "if present" — it is not). Skipped.

-- Campaign header-icon sheet (Skill collapse/expand campaign_headericon_* atlases; ARGB8888).
NE.tex.RegisterLocal(4499236, P .. "4499236-campaign-headericon.blp")        -- 2048x1024 ARGB8888

-- Race DressUpBackground quarters — stitched 4-per-race behind the 3D model.
-- Path mirrors retail Interface\DressUpFrame\DressUpBackground-<Race><1-4>.blp keyed by UnitRace.
-- All 8 Era races shipped (incl. Gnome/Troll, which Era's CASC lacks → maps Gnome->Dwarf, Troll->Orc).
for _, fr in ipairs({
  -- Alliance
  {131089, "Dwarf1"},    {131090, "Dwarf2"},    {131091, "Dwarf3"},    {131092, "Dwarf4"},
  {131093, "Human1"},    {131094, "Human2"},    {131095, "Human3"},    {131096, "Human4"},
  {131097, "NightElf1"}, {131098, "NightElf2"}, {131099, "NightElf3"}, {131100, "NightElf4"},
  {455998, "Gnome1"},    {455999, "Gnome2"},    {456000, "Gnome3"},    {456001, "Gnome4"},
  -- Horde
  {131101, "Orc1"},      {131102, "Orc2"},      {131103, "Orc3"},      {131104, "Orc4"},
  {131105, "Scourge1"},  {131106, "Scourge2"},  {131107, "Scourge3"},  {131108, "Scourge4"},
  {131109, "Tauren1"},   {131110, "Tauren2"},   {131111, "Tauren3"},   {131112, "Tauren4"},
  {456006, "Troll1"},    {456007, "Troll2"},    {456008, "Troll3"},    {456009, "Troll4"},
}) do
  NE.tex.RegisterLocal(fr[1], P .. "RaceBackground\\" .. fr[1] .. "-DressUpBackground-" .. fr[2] .. ".blp")
end

-- ============================================================================
-- 2. atlas-name -> texcoord rect  (NE.tex.RegisterAtlases)
--    CharacterPanel-specific atlases not already registered by Core.
--    Rects transcribed verbatim from NewEra/Generated/AtlasData.lua (see header).
-- ============================================================================

-- Class-themed PaperDoll backgrounds (197x355 each).
NE.tex.RegisterAtlases({
  ["ui-character-info-deathknight-bg"] = { file=1400896, left=0.000977, right=0.193359, top=0.001953, bottom=0.695312, width=197, height=355 },
  ["ui-character-info-demonhunter-bg"] = { file=1400896, left=0.195312, right=0.387695, top=0.001953, bottom=0.695312, width=197, height=355 },
  ["ui-character-info-druid-bg"]       = { file=1400896, left=0.389648, right=0.582031, top=0.001953, bottom=0.695312, width=197, height=355 },
  ["ui-character-info-hunter-bg"]      = { file=1400896, left=0.583984, right=0.776367, top=0.001953, bottom=0.695312, width=197, height=355 },
  ["ui-character-info-mage-bg"]        = { file=1400895, left=0.000977, right=0.193359, top=0.000977, bottom=0.347656, width=197, height=355 },
  ["ui-character-info-monk-bg"]        = { file=1400895, left=0.000977, right=0.193359, top=0.349609, bottom=0.696289, width=197, height=355 },
  ["ui-character-info-paladin-bg"]     = { file=1400895, left=0.195312, right=0.387695, top=0.000977, bottom=0.347656, width=197, height=355 },
  ["ui-character-info-priest-bg"]      = { file=1400895, left=0.195312, right=0.387695, top=0.349609, bottom=0.696289, width=197, height=355 },
  ["ui-character-info-rogue-bg"]       = { file=1400895, left=0.389648, right=0.582031, top=0.000977, bottom=0.347656, width=197, height=355 },
  ["ui-character-info-shaman-bg"]      = { file=1400895, left=0.389648, right=0.582031, top=0.349609, bottom=0.696289, width=197, height=355 },
  ["ui-character-info-warlock-bg"]     = { file=1400895, left=0.583984, right=0.776367, top=0.000977, bottom=0.347656, width=197, height=355 },
  ["ui-character-info-warrior-bg"]     = { file=1400895, left=0.778320, right=0.970703, top=0.000977, bottom=0.347656, width=197, height=355 },
})

-- Stat-sidebar HEADER + ROW backgrounds (sheet 1400895 — already shipped above). DOWNPORT: these
-- coords weren't registered, so the Sidebar's SetAtlas missed and fell back to a brown tint on the
-- section headers. Registering them shows the real Blizzard header/row art. (Coords: AtlasData 13760-13768.)
NE.tex.RegisterAtlases({
  ["ui-character-info-title"]            = { file=1400895, left=0.000977, right=0.192383, top=0.698242, bottom=0.737305, width=196, height=40 },
  ["ui-character-info-line-bounce"]      = { file=1400895, left=0.000977, right=0.154297, top=0.769531, bottom=0.788086, width=157, height=19 },
  ["ui-character-info-itemlevel-bounce"] = { file=1400895, left=0.000977, right=0.159180, top=0.739258, bottom=0.767578, width=162, height=29 },
})

-- Class icons (128x128 each). evoker has no 3.3.5a class, kept for parity (never selected).
NE.tex.RegisterAtlases({
  ["classicon-deathknight"] = { file=1662186, left=0.000488, right=0.062988, top=0.000977, bottom=0.125977, width=128, height=128 },
  ["classicon-demonhunter"] = { file=1662186, left=0.000488, right=0.062988, top=0.127930, bottom=0.252930, width=128, height=128 },
  ["classicon-druid"]       = { file=1662186, left=0.000488, right=0.062988, top=0.254883, bottom=0.379883, width=128, height=128 },
  ["classicon-evoker"]      = { file=1662186, left=0.000488, right=0.062988, top=0.381836, bottom=0.506836, width=128, height=128 },
  ["classicon-hunter"]      = { file=1662186, left=0.000488, right=0.062988, top=0.508789, bottom=0.633789, width=128, height=128 },
  ["classicon-mage"]        = { file=1662186, left=0.000488, right=0.062988, top=0.635742, bottom=0.760742, width=128, height=128 },
  ["classicon-monk"]        = { file=1662186, left=0.000488, right=0.062988, top=0.762695, bottom=0.887695, width=128, height=128 },
  ["classicon-paladin"]     = { file=1662186, left=0.063965, right=0.126465, top=0.000977, bottom=0.125977, width=128, height=128 },
  ["classicon-priest"]      = { file=1662186, left=0.063965, right=0.126465, top=0.127930, bottom=0.252930, width=128, height=128 },
  ["classicon-rogue"]       = { file=1662186, left=0.063965, right=0.126465, top=0.254883, bottom=0.379883, width=128, height=128 },
  ["classicon-shaman"]      = { file=1662186, left=0.063965, right=0.126465, top=0.381836, bottom=0.506836, width=128, height=128 },
  ["classicon-warlock"]     = { file=1662186, left=0.063965, right=0.126465, top=0.508789, bottom=0.633789, width=128, height=128 },
  ["classicon-warrior"]     = { file=1662186, left=0.063965, right=0.126465, top=0.635742, bottom=0.760742, width=128, height=128 },
})

-- Collapsible header art (ReputationHeaderTemplate / Skills collapse).
NE.tex.RegisterAtlases({
  ["_options_listexpand_middle"]       = { file=4571485, left=0.000000, right=0.007812, top=0.218750, bottom=0.421875, width=1,  height=26 },
  ["options_listexpand_left"]          = { file=4571485, left=0.007812, right=0.101562, top=0.656250, bottom=0.859375, width=12, height=26 },
  ["options_listexpand_right"]         = { file=4571485, left=0.007812, right=0.226562, top=0.437500, bottom=0.640625, width=28, height=26 },
  ["options_listexpand_right_expanded"]= { file=4571485, left=0.242188, right=0.460938, top=0.437500, bottom=0.640625, width=28, height=26 },
})

-- Model-control icon overlays (zoom/rotate/undo) + square button face.
NE.tex.RegisterAtlases({
  ["common-icon-rotateleft"]        = { file=3487944, left=0.126465, right=0.175293, top=0.756836, bottom=0.854492, width=20, height=20 },
  ["common-icon-rotateright"]       = { file=3487944, left=0.126465, right=0.175293, top=0.856445, bottom=0.954102, width=20, height=20 },
  ["common-icon-undo"]              = { file=3487944, left=0.378418, right=0.503418, top=0.252930, bottom=0.502930, width=25, height=25 },
  ["common-icon-zoomin"]            = { file=3487944, left=0.504395, right=0.629395, top=0.000977, bottom=0.250977, width=25, height=25 },
  ["common-icon-zoomout"]           = { file=3487944, left=0.756348, right=0.881348, top=0.000977, bottom=0.250977, width=25, height=25 },
  ["common-button-square-gray-down"]= { file=3534438, left=0.000977, right=0.250977, top=0.284180, bottom=0.534180, width=42, height=42 },
  ["common-button-square-gray-up"]  = { file=3534438, left=0.000977, right=0.250977, top=0.536133, bottom=0.786133, width=42, height=42 },
})
