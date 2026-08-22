-- DragonUI_NewEra/modules/worldmap/Pins.lua — the map's pins and its zone label.
--
-- DOWNPORT of the parts of NewEra's pin work that this client can actually support. Read this
-- header before assuming a missing feature was an oversight — most of what the 1.15 source does
-- here has no target on 3.3.5a, and the reasons are specific rather than general:
--
--   * NO PIN POOLS TO RESTYLE. NewEra's pins are MapCanvas data-provider pins it creates itself.
--     This client draws its own: landmark pins out of `GetNumMapLandmarks` / `GetMapLandmarkInfo`
--     onto `WorldMapPOIFrame`, and numbered quest pins out of `QuestPOIGetIconInfo` via
--     `WorldMapFrame_DisplayQuestPOI`. So this file RESTYLES the client's pins in place; it never
--     creates a pin, and it never supplies pin DATA.
--
--   * IT DELIBERATELY SEEDS NOTHING. NewEra's UtilityPois / Dungeons / OutlandPois files exist
--     because Era's data layer ships no vanilla POIs. On this realm's client that job is already
--     done by ModernMapMarkers (dungeon, raid, world-boss, boat, zeppelin, tram and portal
--     markers), and a second seeder would put two markers on every dungeon entrance. See
--     PORT_PLAN.md §2.
--
--   * THE PLAYER ARROW CANNOT BE RESTYLED. `PlayerArrowFrame` and `PlayerArrowEffectFrame` are
--     `Model` frames on this client, not textures — `SetModelScale` is the only lever there is, so
--     NewEra's `UI-WorldMapArrow-2x` swap has nothing to attach to.
--
-- PINS ARE ALREADY CONSTANT-SIZE HERE, which is worth writing down because it looks like a bug
-- waiting to happen and is not. `WorldMapPOIFrame` is NOT one of the frames the chrome scales: the
-- client computes each pin's offset as `normalized * WorldMapDetailFrame:GetWidth() *
-- WORLDMAP_SETTINGS.size`, i.e. already in the WINDOW's units. So pins stay the same size as the
-- map is resized, which is what retail does, and no counter-scaling is needed or wanted — adding
-- some would square the factor and throw every pin off its landmark.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap

-- ----------------------------------------------------------------------------
-- The modern POI sheet
-- ----------------------------------------------------------------------------

-- Retail's POIIcons sheet has the same GRID as the vanilla one this client ships — same cell
-- pitch, modern art in the cells — so the client's own `WorldMap_GetPOITextureCoords(textureIndex)`
-- crop still lands on the right icon after a straight file substitution. That is the entire
-- mechanism: no coordinate table, no per-icon mapping, one SetTexture per pin.
--
-- Gated on the BLP actually being on disk. modules/worldmap/Assets.lua does not register the FDID
-- until it is shipped, so `NE.tex.Local` comes back nil, this returns false, and the map keeps the
-- client's own pin art. A missing sheet must degrade to "no restyle" and never to blank pins.
local function modernPOISheet()
  return NE.tex and NE.tex.Local and NE.tex.Local(WM.poiIconsFDID or 136441) or nil
end

-- Re-point one pin's texture at the modern sheet, preserving whatever texcoords the client already
-- cropped onto it. Reading the crop BACK rather than recomputing it is what keeps this independent
-- of the client's own index-to-cell table.
--
-- Takes either shape, because the client uses both: a landmark pin is a BUTTON whose art is its
-- normal texture, while a quest POI (`questFrame.poiIcon`) is a bare TEXTURE. Passing the second to
-- a button-only version silently did nothing.
local function reskinPin(pin)
  local src = modernPOISheet()
  if not (pin and src) then return false end
  local tex = pin
  if pin.GetNormalTexture then
    tex = pin:GetNormalTexture()
  elseif not pin.GetTexCoord then
    return false
  end
  if not (tex and tex.GetTexCoord) then return false end
  local l, r, t, b = tex:GetTexCoord()
  if not l then return false end
  tex:SetTexture(src)
  tex:SetTexCoord(l, r, t, b)
  return true
end

-- Walk every landmark pin the client has built. They are named WorldMapFramePOI1..N — the client
-- pools them by index and hides the surplus, so walking until the name stops resolving covers
-- exactly the set that exists.
local function reskinAllLandmarkPins()
  if not modernPOISheet() then return end
  local i = 1
  while true do
    local b = _G["WorldMapFramePOI" .. i]
    if not b then break end
    reskinPin(b)
    i = i + 1
  end
end

-- ----------------------------------------------------------------------------
-- The zone label
-- ----------------------------------------------------------------------------

-- `WorldMapFrameAreaLabel` is the big zone name that fades in over the canvas, with
-- `WorldMapFrameAreaDescription` under it. The client draws both in the classic gold serif with no
-- shadow, which reads badly over the modern chrome and over dark map art. Retail's treatment is a
-- larger face with a hard shadow, so that is what is applied — the same one the boss-timer
-- countdown ended up needing for the same reason (a label sitting on top of arbitrary art needs a
-- shadow under its outline to stay readable).
--
-- Font only. Position, fade and TEXT are all the client's, so nothing here can desynchronise from
-- what map is actually showing.
local function styleAreaLabel()
  local label = _G.WorldMapFrameAreaLabel
  if label and not label._neStyled then
    label._neStyled = true
    NE.font.Set(label, NE.font.FRIZ, 32, "", GameFontNormalHuge or GameFontNormalLarge)
    label:SetTextColor(1, 0.82, 0)
    label:SetShadowColor(0, 0, 0, 1)
    label:SetShadowOffset(1, -1)
  end

  local desc = _G.WorldMapFrameAreaDescription
  if desc and not desc._neStyled then
    desc._neStyled = true
    NE.font.Set(desc, NE.font.FRIZ, 20, "", GameFontNormalLarge or GameFontNormal)
    desc:SetTextColor(1, 1, 1)
    desc:SetShadowColor(0, 0, 0, 1)
    desc:SetShadowOffset(1, -1)
  end
end

-- ----------------------------------------------------------------------------
-- Boot
-- ----------------------------------------------------------------------------

function WM.ArmPins()
  if WM._pinsArmed then return end
  WM._pinsArmed = true

  styleAreaLabel()
  reskinAllLandmarkPins()

  -- The client rebuilds its landmark pins on every map change, which throws away our texture swap —
  -- so re-run at the tail of its own update rather than trying to keep a pin permanently dressed.
  -- Chained onto whatever the NavBar already registered rather than replacing it: both want this
  -- signal, and the last file to load must not silently win.
  local prev = WM.OnMapChanged
  WM.OnMapChanged = function()
    if prev then pcall(prev) end
    reskinAllLandmarkPins()
  end

  -- QUEST pins are deliberately left alone, and the reason is worth keeping.
  --
  -- This used to hook WorldMapFrame_DisplayQuestPOI and run the quest icon through reskinPin too.
  -- That is wrong, and it is wrong in a way that LOOKS like a texture bug rather than a logic one:
  -- reskinPin re-points a texture at the POIIcons sheet while KEEPING the crop the client had put
  -- on it. That works for a landmark pin, whose crop was computed against POIIcons in the first
  -- place. A quest pin's art is not from POIIcons at all -- so it kept a crop meant for a different
  -- sheet, and the marker came out as a block of unrelated icons.
  --
  -- The right art for these is `ui-questpoi-questnumber` (sheet 5320914, shipped), but drawing it
  -- needs the NUMBER the client assigned that quest, not the position of a row in our own list --
  -- get that wrong and the badge on the map disagrees with the badge in the panel, which is worse
  -- than the client's own perfectly serviceable icon. Until that number is available, the client
  -- keeps its quest pins.
end
