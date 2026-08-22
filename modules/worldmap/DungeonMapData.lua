-- DragonUI_NewEra/modules/worldmap/DungeonMapData.lua
--
-- GENERATED. Do not hand-edit -- re-run tools/worldmap-overlays/gen_dungeonmaps.py.
--
-- Which art folder each instance's floor maps live in, and how many floors it has,
-- joined from this client's own WorldMapArea.dbc (patch-M.mpq) and DungeonMap.dbc (patch-M.mpq).
--
-- The client renders these itself, but ONLY while the player is standing inside the
-- instance -- SetMapZoom has no dungeon entries, so there is no way to look at a
-- dungeon's map from outside it. This is what lets the map browse to one.
--
-- The tile FILENAME is deliberately not encoded here. A zone's tiles are
-- `<Folder><1..12>`, a multi-floor dungeon's are `<Folder><floor>_<1..12>`, and a few
-- single-floor dungeons use the zone form anyway -- so DungeonMap.lua probes both with
-- SetTexture and keeps whichever resolves, rather than encoding a rule with exceptions.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}

-- folder -> ordered list of floor indices.
NE.worldmap.dungeonFloors = {
  ["AhnQiraj"] = { 1, 2, 3 },
  ["Ahnkahet"] = { 1 },
  ["AuchenaiCrypts"] = { 1, 2 },
  ["Azeroth"] = { 1 },
  ["AzjolNerub"] = { 1, 2, 3 },
  ["BlackTemple"] = { 1, 2, 3, 4, 5, 6, 7 },
  ["BlackfathomDeeps"] = { 1, 2, 3 },
  ["BlackrockDepths"] = { 1, 2 },
  ["BlackrockSpire"] = { 1, 2, 3, 4, 5, 6, 7 },
  ["BlackwingLair"] = { 1, 2, 3, 4 },
  ["CoTStratholme"] = { 1 },
  ["CoilfangReservoir"] = { 1 },
  ["DeeprunTram"] = { 1, 2 },
  ["DireMaul"] = { 1, 2, 3, 4, 5, 6 },
  ["DrakTharonKeep"] = { 1, 2 },
  ["Gnomeregan"] = { 1, 2, 3, 4 },
  ["GruulsLair"] = { 1 },
  ["Gundrak"] = { 1 },
  ["HallsofLightning"] = { 1, 2 },
  ["HallsofReflection"] = { 1 },
  ["HellfireRamparts"] = { 1 },
  ["IcecrownCitadel"] = { 1, 2, 3, 4, 5, 6, 7, 8 },
  ["Karazhan"] = { 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 },
  ["MagistersTerrace"] = { 1, 2 },
  ["MagtheridonsLair"] = { 1 },
  ["ManaTombs"] = { 1 },
  ["Maraudon"] = { 1, 2 },
  ["MoltenCore"] = { 1 },
  ["Naxxramas"] = { 1, 2, 3, 4, 5, 6 },
  ["Nexus80"] = { 1, 2, 3, 4 },
  ["Northrend"] = { 1, 2 },
  ["OnyxiasLair"] = { 1 },
  ["Ragefire"] = { 1 },
  ["RazorfenDowns"] = { 1 },
  ["RazorfenKraul"] = { 1 },
  ["ScarletMonastery"] = { 1, 2, 3, 4 },
  ["Scholomance"] = { 1, 2, 3, 4 },
  ["SethekkHalls"] = { 1, 2 },
  ["ShadowLabyrinth"] = { 1 },
  ["ShadowfangKeep"] = { 1, 2, 3, 4, 5, 6, 7 },
  ["Stratholme"] = { 1, 2 },
  ["SunwellPlateau"] = { 1 },
  ["TempestKeep"] = { 1 },
  ["TheArcatraz"] = { 1, 2, 3 },
  ["TheArgentColiseum"] = { 1, 2 },
  ["TheBloodFurnace"] = { 1 },
  ["TheBotanica"] = { 1 },
  ["TheDeadmines"] = { 1, 2 },
  ["TheEyeofEternity"] = { 1 },
  ["TheForgeofSouls"] = { 1 },
  ["TheMechanar"] = { 1, 2 },
  ["TheNexus"] = { 1 },
  ["TheShatteredHalls"] = { 1 },
  ["TheSlavePens"] = { 1 },
  ["TheSteamvault"] = { 1, 2 },
  ["TheStockade"] = { 1 },
  ["TheTempleOfAtalHakkar"] = { 1, 2, 3 },
  ["TheUnderbog"] = { 1 },
  ["Uldaman"] = { 1, 2 },
  ["Ulduar"] = { 1, 2, 3, 4, 5 },
  ["Ulduar77"] = { 1 },
  ["UtgardeKeep"] = { 1, 2, 3 },
  ["UtgardePinnacle"] = { 1, 2 },
  ["VaultofArchavon"] = { 1 },
  ["VioletHold"] = { 1 },
  ["WailingCaverns"] = { 1 },
}
