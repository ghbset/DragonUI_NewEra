-- DragonUI_NewEra/modules/worldmap/WorldMap.lua — modern (Dragonflight) chrome on the client's
-- own world map.
--
-- DOWNPORT of NewEra/WorldMap/WorldMap.lua (Classic 1.15) — but far less of a port than the rest of
-- this addon, and the header is worth reading before the code.
--
-- WHY THIS IS A REBUILD. Every other window here reskins the same Blizzard frame the 1.15 source
-- reskins, so the port is art plus geometry. Not this one. NewEra's map is written against Classic
-- Era's MapCanvas — `WorldMapFrame.ScrollContainer`, `MapCanvasScrollControllerMixin`, `SetMapID`,
-- uiMapIDs, pin pools, data providers, `C_Map`. **None of it exists on 3.3.5a**, which ships a
-- tile-and-dropdown map: a fixed 1002x668 `WorldMapDetailFrame` of twelve tiles, three dropdowns,
-- and `SetMapZoom(continent, zone)`. compat/C_Map.lua in this addon already says as much — it stubs
-- `GetMapInfo` to nil and records that the world map is out of scope for the C_Map shim.
--
-- So the STRUCTURE below is NewEra's (a HIGH-level border frame carrying the nineslice, portrait,
-- title and controls, over a canvas that starts under a 67px title/canvas spacer) and the geometry
-- constants are NewEra's, but everything they act on is this client's. See PORT_PLAN.md for the
-- feature-by-feature mapping and for what was deliberately not ported.
--
-- WHAT CARRIES OVER EXACTLY. NewEra's 702x534 window is sized so its canvas is 697x465, which is
-- aspect 1.4989 against the child's 1002/668 = 1.5 — the child fits with no letterboxing at scale
-- 697/1002. **3.3.5a's WorldMapDetailFrame is that same 1002x668**, so the window size, the spacer
-- and the scale all transfer unchanged. The client's own `WORLDMAP_WINDOWED_SIZE` (~0.573) does
-- not, so we use OUR scale — and, importantly, we move the client's constant onto it rather than
-- only writing `WORLDMAP_SETTINGS.size`. `size == WORLDMAP_WINDOWED_SIZE` is this client's one and
-- only "am I windowed?" test; breaking that identity is what made the first in-game run repaint the
-- whole fullscreen map chrome around a 702-wide window. See layoutCanvas.
--
-- MAXIMIZE IS OURS, NOT BLIZZARD'S. The client's "maximized" map is a 1024x768 fullscreen panel
-- with a completely different layout, its own border art and a UIPanel `area = "full"` entry. We
-- never go there: the map is held in WINDOWED mode always, and our maximize simply computes a
-- bigger window at the same aspect. That is exactly the trick the 1.15 source plays for the same
-- reason (it pins `miniWorldMap = 1` so Blizzard only ever takes the safe minimize branch and
-- supplies the maximized look from its own private flag).
--
-- POSITIONING. PORT_PLAN.md §3 originally recommended leaving the map in `UIPanelWindows`. That was
-- reversed on the evidence: this client's windowed-map geometry is entangled with that entry (the
-- client rewrites it on every size toggle), and the one addon demonstrably re-homing this frame on
-- 3.3.5a — Mapster — clears it. So we clear it too and place the window the way every other window
-- in this addon is placed: NE.FrameUtil.PersistWindowPosition for the player's own spot,
-- NE.panelmgr for the shared row, NE.FrameUtil.EscClose for ESC.
--
-- COMBAT. `WorldMapBlobFrame` is PROTECTED on this client — touching its parent, points, scale or
-- visibility in combat throws. Every geometry pass here therefore runs through
-- NE.FrameUtil.AfterCombat. See §5.1 of PORT_PLAN.md.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap
local PC = NE.panelchrome
local SQ = NE.squelch

-- ----------------------------------------------------------------------------
-- Geometry
--
-- NewEra's numbers, which land on this client because the canvas child is the same size (header).
-- Nothing below hard-codes the client's own scale constant: DETAIL_W/H are read off the live frame
-- with these as the fallback, and our scale is derived from the canvas rect.
-- ----------------------------------------------------------------------------

local FRAME_W, FRAME_H = 702, 534   -- retail's minimized WorldMapFrame, confirmed in the 1.15 source
local SPACER_H         = 67         -- retail TITLE_CANVAS_SPACER_FRAME_HEIGHT
local INSET_L, INSET_R = 2, 3       -- retail's canvas insets inside the nineslice
local INSET_B          = 2
local TITLE_BAR_H      = 21         -- where the stone body starts, under the title band

local DEFAULT_TL_X, DEFAULT_TL_Y = 16, -116   -- retail's default screen position

-- The detail frame's intrinsic (unscaled) size. 1002x668 on every client that ships this map; read
-- live anyway so a modified client is followed rather than assumed.
local FALLBACK_DETAIL_W, FALLBACK_DETAIL_H = 1002, 668

local function detailSize()
  local d = _G.WorldMapDetailFrame
  if not d then return FALLBACK_DETAIL_W, FALLBACK_DETAIL_H end
  -- GetWidth/GetHeight report the frame's own units, unaffected by whatever scale is on it.
  local w = d.GetWidth and d:GetWidth() or nil
  local h = d.GetHeight and d:GetHeight() or nil
  if not w or not h or w <= 0 or h <= 0 then return FALLBACK_DETAIL_W, FALLBACK_DETAIL_H end
  return w, h
end

-- ONE NUMBER DESCRIBES THE WINDOW: the CANVAS width, in the frame's own units. Everything else
-- follows from it — the canvas height by the map child's fixed 1002/668 aspect, the frame by adding
-- the insets, the spacer and whatever the side panel is claiming.
--
-- That is worth doing deliberately rather than storing a width AND a height. The whole geometry is
-- built on the canvas and the child sharing an aspect ratio, so that the map fills the window with
-- no letterbox; two independent numbers can express a window that violates it, and then the map
-- sits in a stone box with dead space down one side. With one number that state cannot be reached —
-- which is what makes free-dragging the corner safe (see the resize grip in wireControls).
--
-- It also collapses three cases into one. "Minimized", "maximized" and "the size the player dragged
-- it to" are now the same code path with a different canvas width.
local DEFAULT_CANVAS_W = FRAME_W - INSET_L - INSET_R   -- 697, the number NewEra's 702 was chosen for
local MIN_CANVAS_W     = 420   -- below this the zone labels stop being readable

local function canvasAspect()
  local dw, dh = detailSize()
  if not (dw and dh and dh > 0) then return 1.5 end
  return dw / dh
end

local function round(v) return math.floor((v or 0) + 0.5) end

-- The widest the window may get: 80% of the screen, so it never runs off the sides. Also the cap
-- the maximize preset is clamped to.
local function maxCanvasW()
  local pw, ph
  if GetPhysicalScreenSize then
    local ok, a, b = pcall(GetPhysicalScreenSize)
    if ok then pw, ph = a, b end
  end
  if not (pw and ph and pw > 0 and ph > 0) then return 1200 end
  local base = 768 / ph            -- the same base the pixel-pin uses
  return (pw * 0.80) / base - INSET_L - INSET_R
end

-- The maximize preset. Targets a share of screen HEIGHT in physical pixels so it looks the same at
-- every resolution, then derives the width from the aspect.
local function maximizedCanvasW()
  local _, ph
  if GetPhysicalScreenSize then
    local ok, _a, b = pcall(GetPhysicalScreenSize)
    if ok then ph = b end
  end
  if not (ph and ph > 0) then return math.min(1002, maxCanvasW()) end
  local base = 768 / ph
  local frameH  = (ph * 0.55) / base   -- 1.15's constant: comfortably bigger, doesn't own the screen
  local canvasH = frameH - SPACER_H - INSET_B
  return math.min(canvasH * canvasAspect(), maxCanvasW())
end

local function clampCanvasW(w)
  w = tonumber(w) or DEFAULT_CANVAS_W
  local hi = math.max(maxCanvasW(), MIN_CANVAS_W)
  if w < MIN_CANVAS_W then return MIN_CANVAS_W end
  if w > hi then return hi end
  return w
end
WM.ClampCanvasWidth = clampCanvasW

-- The canvas width the window should be showing right now.
--
-- A drag in progress is not a special mode -- it is just a different width, held somewhere that is
-- not the saved variables until the player lets go. That is what keeps the resize honest: there is
-- no code path anywhere that sizes the window from anything but this one number, so the shape can
-- never leave the map's aspect ratio, not even for the single frame that a snap-on-release leaves.
-- EACH MODE OWNS A WIDTH. Minimized and maximized are two states, each with its own remembered
-- size, and dragging the corner changes the size of whichever one you are in.
--
-- The previous model made maximize a size you fell OUT of: dragging cleared the mode, so the button
-- flipped its label and art every time the window was rescaled, and a maximized window dragged to a
-- size you liked could never be returned to -- maximize always went back to the computed preset.
-- Both complaints were the same mistake. Two slots remove it: the mode only changes when the button
-- is clicked, and neither size can overwrite the other.
--
-- It also makes the old "restore width" bookkeeping unnecessary, and with it the guards that kept
-- getting this wrong -- a restore width equal to the preset is not representable when the two live
-- in different keys.
local function widthKey(maximized)
  return maximized and "canvasWMax" or "canvasW"
end
WM.WidthKey = widthKey

local function defaultWidth(maximized)
  if maximized then return maximizedCanvasW() end
  return DEFAULT_CANVAS_W
end
WM.DefaultWidth = defaultWidth

-- THE MAXIMIZED WIDTH IS NEVER THE SMALLER OF THE TWO. Two independent sizes can be dragged past
-- each other, and once they cross, the words on the button stop being true: "maximize" takes you to
-- the smaller window and "minimize" to the larger one. Seen in game as the button appearing inverted
-- -- it was not; the labels were right and the two sizes had swapped places behind them.
--
-- Enforced on the way OUT as well as on the way in, so a pair already saved in the wrong order comes
-- good immediately rather than only after the next drag.
local function canvasWidths()
  local db = NE.db and NE.db.worldmap
  local small = clampCanvasW((db and db.canvasW) or defaultWidth(false))
  local big   = clampCanvasW((db and db.canvasWMax) or defaultWidth(true))
  if big < small then big = small end
  return small, big
end
WM.CanvasWidths = canvasWidths

local function currentCanvasW()
  if WM.dragCanvasW then return clampCanvasW(WM.dragCanvasW) end
  local small, big = canvasWidths()
  return WM.maximized and big or small
end
WM.CurrentCanvasWidth = currentCanvasW

-- MAXIMIZE IS A MODE, NOT A MEASUREMENT, and keeping those two apart is the whole lesson of this
-- control. A previous version had the button answer "am I maximized?" by comparing the current
-- canvas width against the preset, so that a window DRAGGED out to full width would offer to
-- minimize. That reads well and cost four separate faults: the button performed the opposite of its
-- own label (the action still branched on the mode while the label came from the measurement); a
-- saved width left by an earlier build could put the answer permanently at "yes", stranding the
-- button on minimize with maximize unreachable; and because the mode also drove the side panel, the
-- panel and its toggle could both vanish with nothing left to restore them.
--
-- So the mode is the only thing anyone asks about. `WM.maximized` is true exactly while the player
-- has chosen the preset size, the button reflects and toggles precisely that, and a window dragged
-- to any width -- including the widest one available -- is simply not in the mode, which is honest:
-- the button says "maximize" and clicking it does exactly that.



-- The side panel EXTENDS the window rather than overlaying the canvas, exactly as retail's combined
-- Map & Quest Log does: the map keeps its own width and the panel fills the space that was added
-- for it. So its width is added to the frame AFTER the canvas has been sized, never taken out of it.
local function sidePanelWidth()
  local p = NE.questlogpanel
  if p and p.PanelWidth then
    local ok, w = pcall(p.PanelWidth)
    if ok and type(w) == "number" then return w end
  end
  return 0
end

-- Rounded, and that matters at the default: 697 / 1.5 is 464.67, and a canvas height of 465 is what
-- makes the window come out at retail's 534 rather than 533.67. Half a pixel of drift is invisible
-- once, and cumulative across a chain of derived anchors.
local function windowSize()
  local cw = round(currentCanvasW())
  local ch = round(cw / canvasAspect())
  return cw + INSET_L + INSET_R + sidePanelWidth(), ch + SPACER_H + INSET_B
end
WM.WindowSize = windowSize

-- ----------------------------------------------------------------------------
-- Suppressing the client's own chrome
-- ----------------------------------------------------------------------------

-- Named widgets that must stop drawing. Anything this client does not define is skipped silently —
-- a downport routinely names widgets only some clients have, and absence is not an error.
local SQUELCH_GLOBALS = {
  -- The windowed map's own border art and title.
  "WorldMapFrameMiniBorderLeft",
  "WorldMapFrameMiniBorderRight",
  "WorldMapFrameTitle",
  "WorldMapTitleButton",          -- the client's drag bar; our title band drags instead
  -- The fullscreen dim behind the map. We are a window, not a takeover.
  "BlackoutWorld",
  -- Navigation, replaced by the NavBar breadcrumb (NavBar.lua).
  "WorldMapContinentDropDown",
  "WorldMapZoneDropDown",
  "WorldMapZoneMinimapDropDown",
  "WorldMapZoomOutButton",
  "WorldMapMagnifyingGlassButton",
  -- The floor selector, which the breadcrumb's last crumb replaces on a multi-level map. Easy to
  -- miss: the client only shows it where GetNumDungeonMapLevels() > 0, so it stays invisible
  -- everywhere except the handful of maps that have floors, and then appears floating over the
  -- chrome (Dalaran, Ulduar, Icecrown). Squelching the widget does not disable the FEATURE -- the
  -- breadcrumb drives SetDungeonMapLevel directly.
  "WorldMapLevelDropDown",
  "WorldMapLevelUpButton",
  "WorldMapLevelDownButton",
  -- Size toggles, replaced by our own maximize/minimize button (core/MaxMin.lua).
  "WorldMapFrameSizeUpButton",
  "WorldMapFrameSizeDownButton",
  -- The native on-map quest list, replaced by the side panel (QuestLogPanel.lua).
  "WorldMapQuestScrollFrame",
  "WorldMapQuestDetailScrollFrame",
  "WorldMapQuestRewardScrollFrame",
  "WorldMapQuestShowObjectives",
  "WorldMapTrackQuest",
}

-- The classic panel art. Matched on texture PATH rather than by name, because this client leaves
-- most of those regions unnamed — the same technique the merchant and inspect ports use on their
-- unnamed quadrants.
--
-- `interface\worldmap\` is the whole map art directory, and that INCLUDES the map itself
-- (WorldMapDetailTile1..12 are `Interface\WorldMap\Dalaran\Dalaran1` and so on). Matching that
-- broadly is only safe because the walk below never visits WorldMapDetailFrame — see KEEP_FRAMES.
-- `interface\questframe\` is the parchment the three quest panels are drawn on.
local CLASSIC_ART = { "interface\\worldmap\\", "interface\\questframe\\", "ui-worldmap" }

-- Plain substrings, matched with find(..., true). No Lua patterns: a path is full of characters
-- that would need escaping, and nobody should have to remember which entry in the list is which.
local function isClassicArt(region)
  local path = region and region.GetTexture and region:GetTexture()
  if type(path) ~= "string" then return false end
  path = path:lower()
  for _, needle in ipairs(CLASSIC_ART) do
    if path:find(needle, 1, true) then return true end
  end
  return false
end

-- Child frames the sweep must not touch: the map itself, the things drawn on top of it, and our
-- own. Everything else hanging off WorldMapFrame is chrome.
local KEEP_FRAMES = {
  WorldMapDetailFrame = true,      -- IS the map
  WorldMapButton = true,           -- the click/hover surface over it
  WorldMapPOIFrame = true,         -- landmark pins
  WorldMapFrameAreaFrame = true,   -- the zone label
  WorldMapBlobFrame = true,        -- quest areas (and protected — never touch it here)
  PlayerArrowFrame = true, PlayerArrowEffectFrame = true,
  WorldMapPlayerUpper = true, WorldMapPlayerLower = true,
  WorldMapCorpse = true, WorldMapDeathRelease = true,
  WorldMapTooltip = true,
}

local function isOurs(frame)
  local f = _G.WorldMapFrame
  if not f then return false end
  return frame == f._neBorder or frame == f._neSpacer or frame == f._neSideToggle
      or frame == WM.navbar or frame == (NE.questlogpanel and NE.questlogpanel.frame)
end

local LAYERS = { "BACKGROUND", "BORDER", "ARTWORK", "OVERLAY", "HIGHLIGHT" }

local function sweepRegions(frame)
  for _, layer in ipairs(LAYERS) do
    NE.FrameUtil.ForEachRegion(frame, "Texture", layer, function(r)
      if isClassicArt(r) then SQ.Hide(r) end
    end)
  end
end

local function suppressClassicChrome()
  local f = _G.WorldMapFrame
  if not f then return end

  SQ.HideGlobals(SQUELCH_GLOBALS)

  -- The window's own regions...
  sweepRegions(f)

  -- ...and one level down. The first in-game run found the client's backdrop quadrants and the
  -- quest-panel parchment were NOT on WorldMapFrame — they hang off child frames, so a sweep of the
  -- window alone left a full 1024x768 of classic art painted around our 702-wide window.
  for _, child in ipairs({ f:GetChildren() }) do
    local name = child.GetName and child:GetName()
    if not (name and KEEP_FRAMES[name]) and not isOurs(child) then
      sweepRegions(child)
    end
  end
end
WM.SuppressClassicChrome = suppressClassicChrome

-- ----------------------------------------------------------------------------
-- The border frame — everything modern draws here, above the canvas
-- ----------------------------------------------------------------------------

-- The canvas children sit at frame levels the client chooses (`WORLDMAP_POI_FRAMELEVEL` and up), so
-- the chrome is lifted clear of all of them rather than relying on a strata split. Same strata means
-- no interaction with tooltips, dropdowns or the panel row.
local function chromeLevel(f)
  local base = (f.GetFrameLevel and f:GetFrameLevel()) or 1
  local poi  = _G.WORLDMAP_POI_FRAMELEVEL or 0
  return math.max(base + 50, poi + 20)
end

local function buildBorderFrame(f)
  if f._neBorder then return f._neBorder end

  local border = CreateFrame("Frame", "NE_WorldMapBorderFrame", f)
  border:SetAllPoints(f)
  border:SetFrameLevel(chromeLevel(f))
  -- The chrome covers the whole window including the canvas. Without this the border (or a child of
  -- it) swallows clicks before they reach the map, and click-to-zoom stops working. The interactive
  -- children below opt back IN one at a time.
  border:EnableMouse(false)
  f._neBorder = border

  -- 1. The metal nineslice. A child frame of its own so its OVERLAY regions draw at the border's
  -- level rather than the window's.
  local ns = CreateFrame("Frame", nil, border)
  ns:SetAllPoints(border)
  ns:SetFrameLevel(border:GetFrameLevel())
  ns:EnableMouse(false)
  NE.nineslice.ApplyLayout(ns, "PortraitFrameTemplate")
  border.NineSlice = ns

  -- 2. The 3px dark separator between the title band and the canvas. Its right edge is anchored to
  -- the spacer (built below) so it stops at the map, not at the side panel.
  local sep = border:CreateTexture(nil, "BACKGROUND", nil, -5)
  if NE.tex.SetAtlas(sep, "_UI-Frame-InnerTopTile", false) then
    sep:SetHorizTile(true)
    sep:SetHeight(3)
    sep:SetPoint("TOPLEFT", border, "TOPLEFT", INSET_L, -(SPACER_H - 4))
    border.Separator = sep
  else
    sep:Hide()
  end

  -- 3. The portrait in the corner cutout. ARTWORK, not OVERLAY — the nineslice's PortraitMetal
  -- corner sits at OVERLAY, and a portrait on the same layer renders on top of the cutout that is
  -- supposed to frame it (the "icon eclipses the border" bug the 1.15 source documents).
  local portrait = border:CreateTexture(nil, "ARTWORK")
  portrait:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookIcon")
  NE.portrait.ApplyCutout(portrait, border)
  border.Portrait = portrait

  -- 4. Title band + text, above the whole chrome stack.
  local band = PC.TitleBand(border)
  band:SetFrameLevel(border:GetFrameLevel() + 5)
  local fs = band:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  border.Title = fs
  PC.SetTitle(border, WORLD_MAP or "Map", fs, band)

  return border
end

-- The title/canvas spacer. Retail's 67px band whose BOTTOMLEFT is where the canvas starts and whose
-- RIGHT edge stops at the map (not at the side panel), so the NavBar never runs under the panel.
local function buildSpacer(f)
  if f._neSpacer then return f._neSpacer end
  local sp = CreateFrame("Frame", nil, f)
  sp:EnableMouse(false)
  sp:SetPoint("TOPLEFT", f, "TOPLEFT", INSET_L, 0)
  sp:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -INSET_R, -SPACER_H)
  f._neSpacer = sp
  WM.spacer = sp
  return sp
end

-- The stone body, painted under the canvas. Starts below the title band and runs flush to the
-- frame's bottom-right — the same three lines every other window in this set paints for itself.
local ROCK_FDID = 374155

local function paintBody(f)
  local bg = f._neBg
  if not bg then
    bg = f:CreateTexture(nil, "BACKGROUND", nil, -6)
    f._neBg = bg
  end
  local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[ROCK_FDID]
  bg:SetTexture(rockPath or ROCK_FDID, "REPEAT", "REPEAT")
  bg:SetHorizTile(true)
  bg:SetVertTile(true)
  bg:SetTexCoord(0, 1, 0, 1)
  -- FULL brightness, which is what every other window that paints its own body does
  -- (modules/inspect/InspectFrame.lua:216, modules/merchant/MerchantFrame.lua). PC.BODY_TINT is the
  -- 0.32 multiplier PanelChrome's own ApplyBodyFill uses on its default rect; applying it a second
  -- time here made this window roughly three times darker than the rest of the set, and once the
  -- quest panel laid its recess over the top the whole right-hand side read as flat black rather
  -- than as an inset cut into stone.
  bg:SetVertexColor(1, 1, 1)
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT",     f, "TOPLEFT",      INSET_L, -TITLE_BAR_H)
  bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -INSET_R,  INSET_B)
  bg:Show()
end

-- ----------------------------------------------------------------------------
-- The map's tooltip
-- ----------------------------------------------------------------------------

-- `WorldMapTooltip` is the tooltip every quest pin and landmark on the canvas uses, and it came up
-- with its text and its border but NO background -- the map showing straight through it, which on
-- parchment is close to unreadable.
--
-- It is a child of WorldMapFrame, which is the part that makes it ours to think about: it inherits
-- this window's strata, and this window is no longer where the client put it. Mapster lifts the same
-- frame to TOOLTIP strata on the same client for the same reason.
--
-- REPAIRED, NOT IMPOSED. Both halves are conditional -- the backdrop is only supplied if the frame
-- has none, and the colour only if what it has is effectively transparent. A skin that has
-- deliberately styled this tooltip keeps its styling; only a tooltip with nothing behind its text
-- gets touched.
local TOOLTIP_BACKDROP = {
  bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 5, right = 5, top = 5, bottom = 5 },
}

local function ensureTooltipBackdrop(tt)
  if not (tt and tt.SetBackdrop) then return end

  local bd = tt.GetBackdrop and tt:GetBackdrop()
  if not (bd and bd.bgFile) then
    pcall(tt.SetBackdrop, tt, TOOLTIP_BACKDROP)
  end

  -- GetBackdropColor throws on a frame with no backdrop at all, which is exactly the state we may
  -- have just left -- so it is pcall'd rather than guarded on the read above having worked.
  local ok, _, _, _, a = pcall(tt.GetBackdropColor, tt)
  if not ok or not a or a < 0.1 then
    pcall(tt.SetBackdropColor, tt, 0, 0, 0, 0.9)
    pcall(tt.SetBackdropBorderColor, tt, 1, 1, 1, 1)
  end

  tt:SetFrameStrata("TOOLTIP")
end

local function repairMapTooltip()
  local tt = _G.WorldMapTooltip
  if not tt or tt._neTooltipRepaired then return end
  tt._neTooltipRepaired = true
  -- On every show, not once: the tooltip is re-used by everything on the canvas and anything that
  -- re-owns it can leave it in a different state than we found it in.
  if tt.HookScript then tt:HookScript("OnShow", ensureTooltipBackdrop) end
  ensureTooltipBackdrop(tt)
end
WM.RepairTooltip = repairMapTooltip

-- ----------------------------------------------------------------------------
-- The client's quest display
-- ----------------------------------------------------------------------------

-- Quest markers and objective blobs on this client are gated behind ONE checkbox --
-- `WorldMapQuestShowObjectives` -- and the chrome squelches it, because it is a stock tickbox
-- floating over our layout and the cog menu offers the same switch. Squelching the WIDGET is fine.
-- Squelching it and then never touching its STATE is not: the client reads that checkbox to decide
-- whether to draw quest POIs and blobs at all, so the map came up with no quest markers on it.
--
-- Mapster hit the same thing and settles it the same way (Mapster.lua:132-134): hide the box, set it
-- checked, and call the toggle so the client applies it. `WorldMapFrame_UpdateQuests` after that is
-- what actually places the markers.
function WM.SetQuestObjectives(on)
  on = on and true or false
  if NE.db then
    NE.db.worldmap = NE.db.worldmap or {}
    NE.db.worldmap.questObjectives = on
  end
  local box = _G.WorldMapQuestShowObjectives
  if box and box.SetChecked then box:SetChecked(on) end

  -- SET A STATE, DO NOT TOGGLE. This used to call WorldMapQuestShowObjectives_Toggle()
  -- unconditionally -- and that function TOGGLES, so asking for the value it already held flipped it
  -- to the opposite one. Driven from the filter menu, which asks for an explicit value every time,
  -- the result was a switch that appeared to do nothing.
  --
  -- The CVar is the actual state on this client; the checkbox and the toggle function are both just
  -- ways of reaching it. So write it directly, then only fall back to the client's own toggle if the
  -- CVar did not end up where it was asked to be -- which is a measurement, not an assumption about
  -- which mechanism this build uses.
  local want = on and "1" or "0"
  if type(_G.SetCVar) == "function" then pcall(_G.SetCVar, "questPOI", want) end

  local reads = nil
  if type(_G.GetCVarBool) == "function" then
    local okc, v = pcall(_G.GetCVarBool, "questPOI")
    if okc then reads = v and true or false end
  end

  if reads ~= on then
    if type(_G.WorldMapQuestShowObjectives_Toggle) == "function" then
      pcall(_G.WorldMapQuestShowObjectives_Toggle)
    elseif box and box.GetScript then
      local fn = box:GetScript("OnClick")
      if fn then pcall(fn, box) end
    end
  end

  if type(_G.WorldMapFrame_UpdateQuests) == "function" then
    pcall(_G.WorldMapFrame_UpdateQuests)
  end
end

function WM.QuestObjectivesShown()
  local v = NE.db and NE.db.worldmap and NE.db.worldmap.questObjectives
  if v == nil then return true end   -- on by default: a map with no quest markers is not the point
  return v and true or false
end

-- ----------------------------------------------------------------------------
-- The canvas
-- ----------------------------------------------------------------------------

-- Scale and seat the client's map stack inside our window.
--
-- Only WorldMapDetailFrame is ANCHORED: WorldMapButton, WorldMapFrameAreaFrame and
-- WorldMapBlobFrame are all anchored to it by the client and follow it. They each carry their own
-- scale, though, so all four are scaled together — this is exactly the set Mapster scales
-- (Mapster.lua SizeUp/SizeDown), which is the ground truth for which frames need it on this client.
--
-- WorldMapPOIFrame is deliberately NOT scaled: it is a child of WorldMapButton and inherits the
-- scale from it. Scaling it as well would square the factor and throw every landmark pin off.
-- THE PLAYER ARROW. `PlayerArrowFrame` is a Model, and a Model's CONTENT does not scale with its
-- frame -- `SetModelScale` is a second, independent multiplier. Blizzard sets it per map mode, and
-- because we force this client into windowed mode it keeps the small windowed value, then our canvas
-- scale shrinks it again on top. Two reductions compounding is why the arrow came out tiny.
--
-- Mapster solves the same problem with a slider (default 0.88, range 0.5-2.0) because it scales
-- WorldMapFrame wholesale and only needs a taste adjustment. We scale WorldMapDetailFrame and its
-- siblings instead, so whether the arrow has already shrunk depends on where the client parented it
-- -- which differs between builds and is not worth asserting from memory.
--
-- So it is MEASURED, not assumed: the arrow's effective scale is compared against the canvas's, and
-- the value is multiplied UP when the arrow does not already ride the canvas.
--
-- THE GOAL IS PROPORTION TO THE TERRAIN, not a constant size on screen. The arrow marks a spot on
-- the ground, so it has to grow and shrink with the ground -- which is what Mapster gets for free by
-- scaling WorldMapFrame wholesale, arrow and tiles together, and then applying 0.88 on top.
--
-- The first cut of this had both branches backwards (it divided where it should pass through, and
-- passed through where it should multiply). The in-game numbers are what caught it: arrowEff 0.53,
-- detailEff 0.59, canvasScale 1.10 -- and 0.53 x 1.10 = 0.58, so UIParent is at 0.53, the arrow sits
-- at scale 1.0 under it, and the canvas is UIParent scaled by ours. The arrow was therefore NOT
-- tracking the map at all, and dividing would have made that worse.
--
--     rides the canvas  ->  already proportionate  ->  use the value as-is
--     does not          ->  multiply by the canvas scale so it tracks the map
--
-- Either way the arrow ends up at 0.88 relative to the terrain, which is Mapster's tested default.
local ARROW_SCALE_DEFAULT = 0.88

local function applyArrowScale()
  local d = _G.WorldMapDetailFrame
  local arrow = _G.PlayerArrowFrame
  if not (d and arrow and arrow.SetModelScale) then return end

  local base = NE.db and NE.db.worldmap and NE.db.worldmap.arrowScale
  if type(base) ~= "number" or base <= 0 then base = ARROW_SCALE_DEFAULT end

  local ds = d.GetEffectiveScale and d:GetEffectiveScale()
  local as = arrow.GetEffectiveScale and arrow:GetEffectiveScale()
  local ridesCanvas = (type(ds) == "number" and type(as) == "number"
                       and ds > 0 and math.abs(as - ds) < 0.001)

  local canvas = WM.canvasScale
  if not (type(canvas) == "number" and canvas > 0) then canvas = 1 end
  local model = ridesCanvas and base or (base * canvas)

  WM.arrowRidesCanvas, WM.arrowModelScale = ridesCanvas, model
  pcall(arrow.SetModelScale, arrow, model)
  local fx = _G.PlayerArrowEffectFrame
  if fx and fx.SetModelScale then pcall(fx.SetModelScale, fx, model) end
end
WM.ApplyArrowScale = applyArrowScale

local function layoutCanvas(f)
  local d = _G.WorldMapDetailFrame
  if not d then return end

  local dw, dh = detailSize()
  -- MEASURED, not modelled. This used to read windowSize() — the size the frame is *supposed* to
  -- be — which is identical to its real rect every time except the one that matters: while the
  -- player is dragging the corner, StartSizing owns the rect and the model has not moved yet. So
  -- the map sat frozen at its old size until the mouse came up and the model caught up, which is
  -- exactly what it looked like. Reading the frame makes the layout follow whatever the rect
  -- actually is, and the two agree everywhere else.
  local frameW, frameH = f:GetWidth(), f:GetHeight()
  if not (frameW and frameH and frameW > 0 and frameH > 0) then
    frameW, frameH = windowSize()
  end
  -- The side panel EXTENDS the window, so its width comes back off before the canvas is measured —
  -- the map keeps its own size and the panel fills the space that was added for it.
  local canvasW = frameW - INSET_L - INSET_R - sidePanelWidth()
  local canvasH = frameH - SPACER_H - INSET_B
  local scale = math.min(canvasW / dw, canvasH / dh)
  if scale <= 0 then return end
  WM.canvasScale = scale

  -- BOTH of these, and the second one is not optional — it is the fix for the first in-game fault
  -- this port hit, where the client repainted its whole FULLSCREEN chrome around our window.
  --
  -- `WORLDMAP_SETTINGS.size` is what the POI math multiplies by (`WorldMapFrame_DisplayQuestPOI`)
  -- and what the clamp is derived from (`WorldMapFrame_SetPOIMaxBounds`), so it has to carry OUR
  -- scale or every pin lands in the wrong place.
  --
  -- But `WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE` is ALSO this client's one and only
  -- "am I in windowed mode?" test — the client's own code asks it, and so does every addon that
  -- cares (ModernMapMarkers_UI.lua:762 and :942 are the copies on this machine). Writing our scale
  -- into `size` alone breaks that identity, the answer flips to "fullscreen", and the client puts
  -- its 1024x768 border, quest panels and backdrop quadrants back up around a 702-wide window.
  --
  -- So the CONSTANT moves with the setting. It is a plain FrameXML global, nothing reads it for
  -- anything but this comparison, and keeping the two equal is what makes every mode check agree
  -- with what is actually on screen. The client's original value is kept in WM.clientWindowedSize
  -- (captured once at boot, before this ever runs) for the one caller that needs the real one.
  if _G.WORLDMAP_SETTINGS then _G.WORLDMAP_SETTINGS.size = scale end
  _G.WORLDMAP_WINDOWED_SIZE = scale

  for _, name in ipairs({ "WorldMapDetailFrame", "WorldMapButton",
                          "WorldMapFrameAreaFrame", "WorldMapBlobFrame" }) do
    local w = _G[name]
    if w and w.SetScale then w:SetScale(scale) end
  end

  -- Anchor offsets are read in the ANCHORED frame's own units, and this frame is scaled — so the
  -- offsets are divided by the scale to land at (INSET_L, -SPACER_H) in the window's units.
  -- After the canvas scale for this pass is set, because it is measured against it.
  applyArrowScale()

  d:ClearAllPoints()
  d:SetPoint("TOPLEFT", f, "TOPLEFT", INSET_L / scale, -SPACER_H / scale)

  -- Canvas magnification, which OWNS the parent, anchor and scale of the canvas frames once it is
  -- built -- so it runs after the lines above and overrides them. At zoom 1.0 the result is
  -- identical to what they just set; there is deliberately no second code path for "not zoomed".
  local cz = WM.canvaszoom
  if cz and cz.Apply then
    cz.Apply(f, { fit = scale, canvasW = canvasW, canvasH = canvasH,
                  insetL = INSET_L, spacerH = SPACER_H, dw = dw, dh = dh })
  end

  -- The title/canvas spacer's right edge stops at the MAP, not at the window — otherwise the
  -- breadcrumb (which spans the spacer) runs on across the quest-log panel's search box and cog.
  -- Re-anchored here rather than at build time because the panel can open and close at any point.
  local sp = f._neSpacer
  if sp then
    sp:ClearAllPoints()
    sp:SetPoint("TOPLEFT", f, "TOPLEFT", INSET_L, 0)
    sp:SetPoint("BOTTOMRIGHT", f, "TOPRIGHT", -(INSET_R + sidePanelWidth()), -SPACER_H)
  end

  -- The blob frame caches hit translations against the scale it last saw. Clearing xRatio is how
  -- the client is told to recompute them (Mapster does the same after every scale write).
  local blob = _G.WorldMapBlobFrame
  if blob then
    blob.xRatio = nil
    if _G.WorldMapBlobFrame_CalculateHitTranslations then
      pcall(_G.WorldMapBlobFrame_CalculateHitTranslations)
    end
  end

  if _G.WorldMapFrame_SetPOIMaxBounds then pcall(_G.WorldMapFrame_SetPOIMaxBounds) end
end

-- ----------------------------------------------------------------------------
-- Geometry pass
-- ----------------------------------------------------------------------------

-- Declared here rather than beside wireControls: WM.SetMaximized below re-syncs the button's glyph,
-- and a local referenced before its `local` statement would silently resolve to a global instead.
local maxMinButton

local applyGeometryNow   -- forward declaration; ApplyGeometry defers this through AfterCombat

applyGeometryNow = function()
  local f = _G.WorldMapFrame
  if not f or not f._neChromed then return end

  NE.FrameUtil.PinPixelPerfect(f, 1.0)
  f:SetSize(windowSize())

  layoutCanvas(f)
  paintBody(f)

  -- Re-assert the pieces the client re-anchors on its own size passes.
  local close = _G.WorldMapFrameCloseButton
  local border = f._neBorder
  if close and border then
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", border, "TOPRIGHT", 1, 0)
  end

  if WM.RefreshSidePanelToggle then WM.RefreshSidePanelToggle() end

  -- Let the row re-tile around the new size. Reflow self-defers in combat.
  -- Not mid-drag, though: the drag pins the window's TOPLEFT so it grows right and down, and a
  -- reflow would re-anchor it out from under the cursor on every frame.
  if not WM.sizing and NE.panelmgr and NE.panelmgr.Reflow then NE.panelmgr.Reflow() end

  -- Downstream phases hang off this: the NavBar re-fits its band, the side panel re-seats itself.
  -- pcall'd so one broken listener cannot take the geometry pass down with it -- but the error is
  -- LOGGED rather than swallowed. A silent pcall here is how the first in-game fault stayed
  -- invisible: the bar drew its plate, the refresh after it failed, and nothing said so.
  if WM.OnGeometryChanged then
    local okg, err = pcall(WM.OnGeometryChanged, f)
    if not okg and NE.Log then NE.Log("WORLDMAP", "OnGeometryChanged: " .. tostring(err)) end
  end
end

-- The public entry. WorldMapBlobFrame is protected on this client, so every pass that touches the
-- canvas stack waits for combat to end (PORT_PLAN.md §5.1).
function WM.ApplyGeometry()
  NE.FrameUtil.AfterCombat(applyGeometryNow)
end

-- Switch between our windowed and our maximized size. `persist` writes the preference; the
-- reconciliation on open passes false so re-asserting a restored state is not mistaken for a choice.
function WM.SetMaximized(maximized, persist)
  maximized = maximized and true or false

  WM.maximized = maximized
  if persist and NE.db then
    NE.db.worldmap = NE.db.worldmap or {}
    NE.db.worldmap.maximized = maximized
  end
  -- Retail collapses the quest-log side panel on the maximized map. Tell it BEFORE the geometry
  -- pass so sidePanelWidth() already reads 0.
  local p = NE.questlogpanel
  if p and p.SetMaximized then pcall(p.SetMaximized, maximized) end
  if maxMinButton then maxMinButton:SetStateSilently(maximized) end
  WM.ApplyGeometry()
end

-- What canvas width the cursor is currently asking for, while the bottom-right corner is held.
--
-- GetCursorPosition() reports in UIParent's coordinate space; GetLeft()/GetTop() report in the
-- frame's own. This window is pixel-pinned, so those two scales differ — dividing the cursor by the
-- frame's OWN effective scale is what puts both into the same space. (It is the same correction the
-- 1.15 source documents for its click maths, and getting it wrong does not error: the window simply
-- resizes at the wrong rate.)
--
-- Both axes are measured and the TIGHTER fit wins, so dragging up or left shrinks the window even
-- though only one number comes out of it.
local function canvasWidthAtCursor(f)
  local scale = f:GetEffectiveScale()
  if not (scale and scale > 0) then return nil end
  -- The origin is the one CAPTURED AT MOUSE-DOWN, never the frame's live rect, and that is the
  -- difference between a resize and a runaway.
  --
  -- Re-reading `f:GetLeft()/GetTop()` every frame closes a feedback loop: the window is clamped to
  -- the screen, so once it grows past an edge the clamp SHIFTS it -- which moves the origin, which
  -- makes the cursor look further from it, which grows the window, which clamps harder. Two or
  -- three frames of that and it has run all the way to the maximum, which is what "resizing the
  -- small window makes it jump to full size" was.
  local origin = WM.dragOrigin
  local left = origin and origin.left or f:GetLeft()
  local top  = origin and origin.top  or f:GetTop()
  if not (left and top) then return nil end
  local cx, cy = GetCursorPosition()
  cx, cy = cx / scale, cy / scale
  local byWidth  = (cx - left) - INSET_L - INSET_R - sidePanelWidth()
  local byHeight = ((top - cy) - SPACER_H - INSET_B) * canvasAspect()
  return math.min(byWidth, byHeight)
end

-- Read the canvas width back out of a frame the player has just dragged, and adopt it. Taken as
-- the TIGHTER of the two fits so that dragging either edge does something: pull the bottom up and
-- the height is the constraint, pull the right-hand edge and the width is.
function WM.AdoptDraggedSize()
  local f = _G.WorldMapFrame
  if not f then return end
  local byWidth  = (f:GetWidth() or 0) - INSET_L - INSET_R - sidePanelWidth()
  local byHeight = ((f:GetHeight() or 0) - SPACER_H - INSET_B) * canvasAspect()
  WM.SetCanvasWidth(math.min(byWidth, byHeight))
end

-- Set the width of the mode the window is currently in; `nil` restores that mode's default.
--
-- DRAGGING NO LONGER LEAVES THE MAXIMIZE MODE. It used to, on the reasoning that choosing a
-- different size is choosing not to be in the preset -- but the visible result was the maximize
-- button changing its label and its art every time the window was rescaled, and a maximized window
-- dragged to a comfortable size could never be returned to. Resizing now adjusts the size of the
-- state you are in and leaves the state alone.
function WM.SetCanvasWidth(width)
  if NE.db then
    NE.db.worldmap = NE.db.worldmap or {}
    local db = NE.db.worldmap
    db[widthKey(WM.maximized)] = width and clampCanvasW(width) or nil

    -- The mode being dragged wins and the other yields, so the drag always does what the cursor
    -- asks and the pair can never cross. Dragging the small window past the large one takes the
    -- large one with it, and vice versa.
    local small = clampCanvasW(db.canvasW or defaultWidth(false))
    local big   = clampCanvasW(db.canvasWMax or defaultWidth(true))
    if big < small then
      if WM.maximized then db.canvasW = big else db.canvasWMax = small end
    end
  end
  WM.ApplyGeometry()
end

-- ----------------------------------------------------------------------------
-- Controls
-- ----------------------------------------------------------------------------

-- The title band is mouse-enabled so the window drags by its title bar, and it spans the whole top
-- of the frame -- which means it lies directly over the close and maximize buttons. In game that
-- showed up as a maximize button you had to mouse over *near* rather than *on*: the band was taking
-- the hover, and only the few pixels of button hanging below it responded. Two independent fixes,
-- because either alone would leave the other latent: the buttons are lifted clear of the band's
-- level, and the band is stopped short of them.
local CONTROL_LEVEL_BUMP = 12   -- the band sits at +5; anything on top of it must clear that

local function wireControls(f, border)
  -- The close button: TEXTURES ONLY. Its OnClick is Blizzard's and stays Blizzard's — the same
  -- taint rule the merchant and inspect ports document. An insecure replacement makes closing the
  -- window fail in combat.
  --
  -- AND IT IS NOT REPARENTED, which is the whole of what went wrong the first time this shipped.
  -- The 1.15 source says so in as many words, and this port reparented it anyway:
  --
  --     "DON'T reparent the close button ... Kept parented to WorldMapFrame, its native secure
  --      UIPanelCloseButton_OnClick -> HideUIPanel(WorldMapFrame) closes the map ... cross-parent
  --      SetPoint to our border is fine for positioning."
  --
  -- That handler is `HideUIPanel(self:GetParent())`. Move the button onto our border frame and the
  -- X stops closing the MAP and starts hiding the CHROME instead — and since nothing ever shows the
  -- border again, the window stays gutted for the rest of the session and comes back gutted on the
  -- next open. Which is exactly what it did.
  --
  -- A frame level is absolute within its strata, not relative to its parent, so the button can stay
  -- a child of WorldMapFrame and still draw above every piece of our chrome. Position is a
  -- cross-parent SetPoint, which is allowed and costs nothing.
  local close = _G.WorldMapFrameCloseButton
  if close then
    close:SetParent(f)
    close:SetFrameLevel(border:GetFrameLevel() + CONTROL_LEVEL_BUMP)
    PC.ModernizeCloseButton(close, { frameLevelBump = false })
    close:ClearAllPoints()
    close:SetPoint("TOPRIGHT", border, "TOPRIGHT", 1, 0)
  end

  -- Our own maximize/minimize, in place of the client's two size buttons (squelched above). This
  -- never enters the client's fullscreen mode — see the header.
  if not maxMinButton and NE.maxmin and NE.maxmin.Build then
    maxMinButton = NE.maxmin.Build(border, {
      name       = "NE_WorldMapMaxMinButton",
      anchorTo   = close,
      maximized  = WM.maximized,
      -- The window's own answer, asked fresh each time the button draws or is hovered, so the glyph
      -- and the tooltip cannot fall out of step with the size the map is actually at.
      stateFunc  = function() return WM.maximized and true or false end,
      frameLevel = border:GetFrameLevel() + CONTROL_LEVEL_BUMP,
      onMaximize = function() WM.SetMaximized(true,  true) end,
      onMinimize = function() WM.SetMaximized(false, true) end,
    })
  end

  -- Stop the drag band before the buttons rather than under them. The title text is anchored to the
  -- band, so it re-centres over the slightly narrower strip -- a dozen pixels left of dead centre,
  -- which is what retail does anyway once its own controls are in that corner.
  local band = border._neTitleBand
  if band then
    band:ClearAllPoints()
    band:SetPoint("TOPLEFT", border, "TOPLEFT", 58, -1)
    if maxMinButton then
      band:SetPoint("TOPRIGHT", maxMinButton, "TOPLEFT", -2, -1)
    else
      band:SetPoint("TOPRIGHT", border, "TOPRIGHT", -52, -1)
    end
    band:SetHeight(20)
  end

  -- The side-panel toggle, at the bottom-right corner of the CANVAS (retail's SidePanelToggle
  -- position). A plain chevron rather than retail's QuestCollapse-Show/Hide art, which is on a
  -- sheet this addon does not ship — see modules/worldmap/Assets.lua.
  if not f._neSideToggle then
    local t = CreateFrame("Button", "NE_WorldMapSidePanelToggle", border)
    t:SetSize(32, 32)
    t:SetFrameLevel(border:GetFrameLevel() + 5)
    -- Retail's own QuestCollapse chevrons. The FontString stays as the fallback for a client where
    -- the sheet does not resolve; RefreshSidePanelToggle drives whichever of the two actually did.
    t.chevron = t:CreateTexture(nil, "ARTWORK")
    t.chevron:SetAllPoints(t)
    t.arrow = t:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t.arrow:SetPoint("CENTER")
    t:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    t:SetScript("OnClick", function()
      local p = NE.questlogpanel
      if p and p.Toggle then p.Toggle() end
    end)
    t:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(_G.QUEST_LOG or "Quest Log")
      GameTooltip:Show()
    end)
    t:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    f._neSideToggle = t
    WM.sideToggle = t
  end

  -- The resize grip, bottom-right, in retail's own chat-window grabber art (this client ships it).
  --
  -- The drag is FREE -- the player pulls the corner wherever they like -- but only the resulting
  -- CANVAS WIDTH is kept, and the height is re-derived from it. So the window can never end up at an
  -- aspect the map does not fill, and letting go always snaps to a shape with no dead space in it.
  -- Either axis works, because the width is taken from whichever of the two fits is tighter.
  --
  -- NOT IN COMBAT. Re-laying the canvas out touches WorldMapBlobFrame's scale, and that frame is
  -- protected on this client -- a live drag would throw on the first mouse-move. Every other
  -- geometry pass defers through AfterCombat, which a drag cannot do: there is nothing to defer,
  -- the player is holding the mouse down NOW. So the grip refuses, and says so.
  if not f._neSizeGrip then
    local grip = CreateFrame("Button", "NE_WorldMapSizeGrip", border)
    grip:SetSize(16, 16)
    grip:SetFrameLevel(border:GetFrameLevel() + CONTROL_LEVEL_BUMP)
    grip:SetPoint("BOTTOMRIGHT", border, "BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:RegisterForClicks("RightButtonUp")

    local function finishDrag(self)
      if not WM.sizing then return end
      WM.sizing = false
      self:SetScript("OnUpdate", nil)
      if WM.dragWasClamped and f.SetClampedToScreen then
        f:SetClampedToScreen(true)
        WM.dragWasClamped = nil
      end
      local w = WM.dragCanvasW
      WM.dragCanvasW = nil
      WM.dragOrigin = nil
      -- A mouse-down with no movement leaves no width to adopt. Passing that nil straight through
      -- would read as "reset to default" and silently throw away the size the player already had.
      if w then WM.SetCanvasWidth(w) end
    end

    grip:SetScript("OnMouseDown", function(self, button)
      if button == "RightButton" then return end
      if InCombatLockdown and InCombatLockdown() then
        if UIErrorsFrame and _G.ERR_NOT_IN_COMBAT then
          UIErrorsFrame:AddMessage(_G.ERR_NOT_IN_COMBAT, 1.0, 0.1, 0.1, 1.0)
        end
        return
      end

      -- Pin the TOPLEFT for the duration, so the window grows right and down and the corner stays
      -- under the cursor. UIParent's BOTTOMLEFT is the screen's origin at every scale, and anchor
      -- offsets are read in the anchored frame's own units -- which is what GetLeft/GetTop return --
      -- so these two numbers go straight across with no scale conversion.
      local left, top = f:GetLeft(), f:GetTop()
      if left and top then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
      end
      -- ...and remember it, because every frame of the drag measures against THIS, not against
      -- wherever the window has since ended up (see canvasWidthAtCursor).
      WM.dragOrigin = (left and top) and { left = left, top = top } or nil

      -- Clamping off for the duration. It exists to stop the player losing the window off-screen,
      -- but during a resize it MOVES the frame, and a moving frame under a fixed origin makes the
      -- corner drift away from the cursor. Restored on release, which re-clamps in one step.
      WM.dragWasClamped = true
      if f.SetClampedToScreen then f:SetClampedToScreen(false) end

      WM.sizing = true
      WM.dragCanvasW = currentCanvasW()

      self:SetScript("OnUpdate", function(selfBtn)
        -- Released somewhere the button never saw: OnMouseUp is not guaranteed if the cursor left
        -- the grip, and a drag that never ends leaves the window following the mouse for good.
        if IsMouseButtonDown and not IsMouseButtonDown("LeftButton") then
          finishDrag(selfBtn)
          return
        end
        local w = canvasWidthAtCursor(f)
        if w then
          WM.dragCanvasW = clampCanvasW(w)
          applyGeometryNow()
        end
      end)
    end)

    grip:SetScript("OnMouseUp", function(self) finishDrag(self) end)

    -- Right-click restores the size it opens at out of the box. A window that drags to any size
    -- needs a way back that does not involve the player guessing at the original number.
    grip:SetScript("OnClick", function(_, button)
      if button ~= "RightButton" then return end
      WM.SetCanvasWidth(nil)
    end)

    grip:SetScript("OnEnter", function(self)
      if not GameTooltip then return end
      GameTooltip:SetOwner(self, "ANCHOR_LEFT")
      GameTooltip:SetText(L["Drag to resize"])
      GameTooltip:AddLine(L["Right-click to reset the size."], 1, 1, 1, true)
      GameTooltip:Show()
    end)
    grip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

    f._neSizeGrip = grip
    WM.sizeGrip = grip
  end

  -- Drag by the title band, saved account-wide, and taking part in the shared panel row until the
  -- player drops the window somewhere themselves.
  local band = border._neTitleBand
  if band then band:EnableMouse(true) end
  NE.FrameUtil.PersistWindowPosition(f, "worldmap",
    { point = "TOPLEFT", relPoint = "TOPLEFT", x = DEFAULT_TL_X, y = DEFAULT_TL_Y }, band)
end

-- Re-seat the side-panel toggle and point its chevron the way the click will go. Called from the
-- geometry pass (the canvas edge moves when the panel opens) and by the panel itself when it
-- toggles.
--
-- ALWAYS VISIBLE. It used to hide on the maximized map, mirroring retail -- where maximize means
-- fullscreen and there is no side panel to toggle. Here maximize is just a bigger window, so hiding
-- the toggle removed the only way to reopen a panel that maximizing had already closed. Between them
-- the panel and its control could both disappear with nothing left to bring either back.
function WM.RefreshSidePanelToggle()
  local f = _G.WorldMapFrame
  local t = f and f._neSideToggle
  if not t then return end
  t:Show()

  -- `hide` closes the panel, `show` opens it. The atlas names read backwards from the button's own
  -- arrow, which is why this is spelled out: they are named for what the panel will DO, not for
  -- which way the chevron points.
  local shown = NE.questlogpanel and NE.questlogpanel.shown
  local atlas = shown and "questcollapse-hide-up" or "questcollapse-show-up"
  if t.chevron and NE.tex.SetAtlas(t.chevron, atlas, false) then
    t.chevron:Show()
    t.arrow:SetText("")
  else
    if t.chevron then t.chevron:Hide() end
    t.arrow:SetText(shown and ">" or "<")
  end
  t:ClearAllPoints()
  -- Bottom-right of the MAP, i.e. inside the window's right edge less whatever the panel claims.
  t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(INSET_R + sidePanelWidth()), INSET_B + 2)
  t:Show()
end

-- ----------------------------------------------------------------------------
-- Boot
-- ----------------------------------------------------------------------------

-- Hold the client in WINDOWED mode. Its fullscreen mode is a different frame layout with its own
-- border art and a UIPanel `area = "full"` entry, and we never want it (header). Calling the
-- client's own toggle keeps the UIPanel bookkeeping consistent — we do not write that table
-- ourselves beyond clearing the entry below.
local function forceWindowedMode()
  -- Capture the client's OWN windowed constant before layoutCanvas replaces it (see the long note
  -- there). This is the only place that can: after the first geometry pass the global is ours.
  if WM.clientWindowedSize == nil then
    WM.clientWindowedSize = _G.WORLDMAP_WINDOWED_SIZE or false
  end

  local settings = _G.WORLDMAP_SETTINGS
  local alreadyWindowed = settings and WM.clientWindowedSize
                          and settings.size == WM.clientWindowedSize
  if not alreadyWindowed and type(_G.WorldMap_ToggleSizeDown) == "function" then
    -- The client's own toggle, not our own reimplementation of it: it hides the whole fullscreen
    -- layout (border, backdrop quadrants, the three quest panels) as well as resizing, and it keeps
    -- the UIPanelWindows bookkeeping consistent on the way through.
    pcall(_G.WorldMap_ToggleSizeDown)
  end
  if SetCVar then pcall(SetCVar, "miniWorldMap", 1) end
end

-- Take the map out of the secure panel row so it can be a free-floating window like the rest of
-- this addon's panels (header). ESC still closes it, via UISpecialFrames.
--
-- RE-RUNNABLE ON PURPOSE. `WorldMap_ToggleSizeUp/Down` REWRITE `UIPanelWindows["WorldMapFrame"]` —
-- clearing the entry once at boot is not enough, because the client puts it back on the next size
-- change and the panel manager then starts moving and resizing a window we are positioning
-- ourselves. Called from boot, from both size-toggle hooks, and on every show.
local function detachFromPanelSystem(f)
  if _G.UIPanelWindows then _G.UIPanelWindows["WorldMapFrame"] = nil end
  if f.SetAttribute then
    pcall(f.SetAttribute, f, "UIPanelLayout-enabled", false)
  end
  if f:GetParent() ~= UIParent then f:SetParent(UIParent) end
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  NE.FrameUtil.EscClose(f)

  -- Deliberately NOT SetResizable/StartSizing. The client's sizing machinery drags the two edges
  -- independently, which means it can put the window in a shape the map does not fill -- and it did:
  -- the frame stretched free of the map during the drag and only snapped back on release. The grip
  -- drives the size itself instead, from the single canvas width, so the shape is correct on every
  -- frame rather than corrected at the end of one. See the grip in wireControls.
end
WM.DetachFromPanelSystem = detachFromPanelSystem

-- Re-assert our layout after anything the client does that re-anchors or re-scales the map stack.
local function installHooks(f)
  if f._neHooked then return end
  f._neHooked = true

  -- While the corner is held the frame's rect changes every frame, and the map has to follow it --
  -- otherwise the player drags an empty stone box around and only sees the result on release.
  f:HookScript("OnSizeChanged", function(self)
    if not WM.sizing then return end
    layoutCanvas(self)
    paintBody(self)
    if WM.RefreshSidePanelToggle then WM.RefreshSidePanelToggle() end
    if WM.OnGeometryChanged then pcall(WM.OnGeometryChanged, self) end
  end)

  f:HookScript("OnShow", function()
    -- The client re-runs its own size logic on show; ours goes on top of it.
    detachFromPanelSystem(f)
    -- Belt: if anything hid the chrome while the map was closed, the window would open gutted and
    -- STAY gutted, because nothing else ever shows it again. That is the shape the reparented close
    -- button produced, and it is cheap to make impossible rather than merely fixed.
    if f._neBorder and not f._neBorder:IsShown() then f._neBorder:Show() end
    WM.ApplyGeometry()
    if NE.panelmgr and NE.panelmgr.Promote then NE.panelmgr.Promote(f) end
  end)

  -- Both size toggles rewrite WORLDMAP_SETTINGS.size, the four scales and the detail anchor. Hook
  -- rather than replace: the functions stay secure and we run at their tail.
  for _, name in ipairs({ "WorldMap_ToggleSizeUp", "WorldMap_ToggleSizeDown" }) do
    if type(_G[name]) == "function" then
      hooksecurefunc(name, function()
        -- Both of these put the UIPanelWindows entry back; take it out again before the geometry
        -- pass, or the panel manager fights us for the window's position on the very next show.
        detachFromPanelSystem(f)
        WM.ApplyGeometry()
      end)
    end
  end

  -- Map changes (a new continent/zone, entering an instance) re-run the client's update, which
  -- re-places POIs against WORLDMAP_SETTINGS.size. Re-assert the bounds so they clamp to ours.
  if type(_G.WorldMapFrame_Update) == "function" then
    hooksecurefunc("WorldMapFrame_Update", function()
      if _G.WorldMapFrame_SetPOIMaxBounds then pcall(_G.WorldMapFrame_SetPOIMaxBounds) end
      if WM.OnMapChanged then
        local okm, err = pcall(WM.OnMapChanged)
        if not okm and NE.Log then NE.Log("WORLDMAP", "OnMapChanged: " .. tostring(err)) end
      end
    end)
  end
end

-- Build once, on the first PLAYER_LOGIN. WorldMapFrame lives in FrameXML here (not a LoadOnDemand
-- addon as it is on Era), so there is nothing to wait for.
function WM.Arm()
  local f = _G.WorldMapFrame
  if not f or f._neChromed then return end
  f._neChromed = true

  WM.frame = f
  WM.maximized = (NE.db and NE.db.worldmap and NE.db.worldmap.maximized) or false

  forceWindowedMode()
  detachFromPanelSystem(f)
  suppressClassicChrome()

  f:SetFrameStrata("DIALOG")
  local spacer = buildSpacer(f)
  local border = buildBorderFrame(f)
  WM.border = border

  -- Now that the spacer exists, stop the separator at the map's right edge.
  if border.Separator then
    border.Separator:SetPoint("RIGHT", spacer, "RIGHT", 0, 0)
  end

  wireControls(f, border)
  installHooks(f)

  -- After the squelch, because that is what turned it off, and after the chrome, because
  -- WorldMapFrame_UpdateQuests places the markers against the canvas we have just laid out.
  WM.SetQuestObjectives(WM.QuestObjectivesShown())
  repairMapTooltip()

  if NE.panelmgr and NE.panelmgr.Register then NE.panelmgr.Register(f) end

  applyGeometryNow()
end

WM.Rechrome = WM.Arm   -- the 1.15 source's name for the same entry point
