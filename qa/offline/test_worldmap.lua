-- qa/offline/test_worldmap.lua — offline harness for the world map port (modules/worldmap).
--
--   luajit qa/offline/test_worldmap.lua        (from the addon root)
--
-- What this covers that a syntax gate cannot. This module is almost entirely arithmetic and
-- suppression against a frame tree that only exists inside the client, and it is the one module in
-- this addon that is a REBUILD rather than a downport — so there is no 1.15 source to diff against
-- when something comes out wrong. The stub below is that tree, transcribed from the real 3.3.5a
-- world map (Interface 30300, cross-checked against Mapster 1.3.9, which re-homes the same frame on
-- the same client and is therefore ground truth for which globals exist and which of them carry a
-- scale of their own).
--
-- The four facts the port is built around, and which every assertion here exists to protect:
--
--   1. WorldMapDetailFrame is 1002x668 — the same size as Era's canvas child — so NewEra's window
--      geometry transfers, but the client's own WORLDMAP_WINDOWED_SIZE does NOT. The chrome must
--      derive its scale from the canvas rect and write THAT into WORLDMAP_SETTINGS.size.
--   2. WorldMap_ToggleSizeUp/Down re-Show the client's chrome on every size change, so hiding it
--      once is not enough. That is what core/Squelch.lua is for, and it is asserted directly.
--   3. WorldMapBlobFrame is PROTECTED: DrawQuestBlob raises in combat.
--   4. The close button's OnClick must stay Blizzard's, or closing the map fails in combat.
--
-- The core toolkit (panelchrome / nineslice / portrait / scrollbar / panelmgr) is STUBBED — it has
-- its own coverage, and stubbing it keeps every assertion below about THIS module. core/Squelch.lua
-- and core/MaxMin.lua are loaded FOR REAL: both are new, both were written for this port, and both
-- are behaviour rather than art.

local ADDON = (arg and arg[0] or ""):match("^(.*)qa/offline/[^/]+$") or "./"

local chr10 = string.char(10)
local fails, checks = 0, 0
local function ok(cond, what)
  checks = checks + 1
  if not cond then fails = fails + 1; print("FAIL  " .. what) else print("ok    " .. what) end
end
local function eq(a, b, what)
  ok(a == b, what .. "  (got " .. tostring(a) .. ", want " .. tostring(b) .. ")")
end
local function near(a, b, what, tol)
  tol = tol or 0.001
  ok(type(a) == "number" and math.abs(a - b) <= tol,
     what .. "  (got " .. tostring(a) .. ", want ~" .. tostring(b) .. ")")
end

-- ── widget stubs ────────────────────────────────────────────────────────────

_G = _G or getfenv(0)

local function addPointApi(o)
  o._points = {}
  function o:ClearAllPoints() self._points = {} end
  function o:SetPoint(...) self._points[#self._points + 1] = { ... } end
  function o:SetAllPoints(other) self._points = { { "ALLPOINTS", other } } end
  function o:SetWidth(w) self._w = w end
  function o:SetHeight(h) self._h = h end
  -- A frame pinned TOPLEFT + TOPRIGHT (or BOTTOMRIGHT) into a sized parent has no explicit width,
  -- and the client resolves it from the anchors. The breadcrumb bar is exactly that shape and its
  -- whole layout is driven off GetWidth, so the stub has to answer honestly rather than return 0.
  local function spannedWidth(self)
    local left, right
    for _, pt in ipairs(self._points) do
      if pt[1] == "TOPLEFT" and type(pt[2]) == "table" then left = pt end
      if (pt[1] == "TOPRIGHT" or pt[1] == "BOTTOMRIGHT") and type(pt[2]) == "table" then
        right = right or pt
      end
    end
    if not (left and right and left[2] == right[2]) then return nil end
    local pw = left[2].GetWidth and left[2]:GetWidth()
    if not pw or pw == 0 then return nil end
    return pw - (left[4] or 0) + (right[4] or 0)
  end
  -- The frame's rect in its OWN coordinate space, which is the space GetCursorPosition has to be
  -- divided into before the two can be compared. Modelled off a TOPLEFT anchor to UIParent's
  -- BOTTOMLEFT, which is exactly how the resize pins the window for the duration of a drag.
  function o:GetLeft()
    for _, pt in ipairs(self._points) do
      if pt[1] == "TOPLEFT" and type(pt[2]) == "table" then return pt[4] or 0 end
    end
    return self._left or 0
  end
  function o:GetTop()
    for _, pt in ipairs(self._points) do
      if pt[1] == "TOPLEFT" and type(pt[2]) == "table" then return pt[5] or 0 end
    end
    return self._top or 0
  end
  function o:GetWidth() return self._w or spannedWidth(self) or 0 end
  function o:GetHeight() return self._h or 0 end
  function o:SetSize(w, h) self._w, self._h = w, h end
  function o:SetAlpha(a) self._alpha = a end
  function o:GetAlpha() return self._alpha or 1 end
  function o:Show() self._shown = true end
  function o:Hide() self._shown = false end
  function o:IsShown() return self._shown and true or false end
  function o:IsVisible() return self._shown and true or false end
end

-- The first SetPoint of `obj`, as point, relativeTo, relativePoint, x, y.
local function pointOf(obj, i)
  local p = obj and obj._points and obj._points[i or 1]
  if not p then return nil end
  if type(p[2]) == "number" then return p[1], nil, p[1], p[2], p[3] end
  return p[1], p[2], p[3], p[4], p[5]
end

local function findPoint(obj, want)
  for i = 1, #(obj._points or {}) do
    local p, rel, rp, x, y = pointOf(obj, i)
    if p == want then return p, rel, rp, x, y end
  end
  return nil
end

local function newTexture(layer, parent)
  local t = { _layer = layer or "ARTWORK", _shown = true, _parent = parent }
  addPointApi(t)
  function t:GetParent() return self._parent end
  -- A SetTexture the client cannot resolve FAILS QUIETLY and the texture KEEPS WHAT IT HAD. That is
  -- not a detail: it is why "asked for one dungeon, got another" is possible at all, and a stub that
  -- clears on failure makes the bug untestable. `_missingPaths` is how a test says a path is absent.
  _G._missingPaths = _G._missingPaths or {}
  function t:SetTexture(a)
    if a == nil then self._file = nil; return end
    if type(a) ~= "string" then self._file = nil; return end
    if _G._missingPaths[a:lower()] then return end   -- failed: keep the previous content
    self._file = a
  end
  function t:GetTexture() return self._file end
  function t:SetTexCoord(...) self._tc = { ... } end
  function t:GetTexCoord() return unpack(self._tc or {}) end
  function t:SetDesaturated() end
  function t:SetVertexColor(r, g, b) self._vertex = { r, g, b } end
  function t:SetDrawLayer(l) self._layer = l end
  function t:SetHorizTile() end
  function t:SetVertTile() end
  function t:SetBlendMode() end
  function t:SetDrawLayer(l) self._layer = l end
  function t:GetDrawLayer() return self._layer end
  function t:GetObjectType() return "Texture" end
  return t
end

local function newFontString(layer, parent)
  local fs = { _shown = true, _layer = layer or "OVERLAY", _parent = parent }
  addPointApi(fs)
  function fs:GetParent() return self._parent end
  -- A FontString with text has a real height, and the detail pane stacks its blocks by reading it
  -- back. Returning 0 would pile every block on the same line and hide a layout fault.
  function fs:GetHeight() return self._h or (self._text and 12 or 0) end
  function fs:SetText(s) self._text = s end
  function fs:GetText() return self._text end
  function fs:GetStringWidth() return #(self._text or "") * 6 end
  function fs:SetFont(p, s) self._font, self._size = p, s; return true end
  function fs:SetFontObject(o) self._fontObject = o end
  function fs:SetJustifyH() end
  function fs:SetWordWrap() end
  function fs:SetTextColor(r, g, b) self._color = { r, g, b } end
  function fs:SetShadowColor() self._shadowColor = true end
  function fs:SetShadowOffset() self._shadowOffset = true end
  function fs:SetDrawLayer(l) self._layer = l end
  function fs:GetDrawLayer() return self._layer end
  function fs:GetObjectType() return "FontString" end
  return fs
end

-- A frame returned by CreateFrame is SHOWN, not hidden — code that relies on being able to lay
-- itself out at build time (the breadcrumb's refresh is gated on bar:IsShown()) depends on it.
local function newFrame(kind, name, parent)
  -- A child frame starts at its PARENT'S level, not above it -- which is the whole reason a crumb
  -- can be shown, sized and textured and still be painted over by a region of the bar it sits on.
  -- A stub that quietly hands out parent+1 makes that fault unaskable.
  local f = { _kind = kind or "Frame", _name = name, _parent = parent, _children = {},
              _regions = {}, _scripts = {}, _events = {}, _shown = true,
              _level = (parent and parent._level) or 1 }
  if parent and parent._children then table.insert(parent._children, f) end
  addPointApi(f)
  function f:GetName() return self._name end
  function f:GetParent() return self._parent end
  function f:SetParent(p)
    -- Reparenting has to actually MOVE the child, or a test cannot tell "adopted into the zoom
    -- viewport" from "left where it was and the assertion looked at the wrong field".
    local old = self._parent
    if old and old._children then
      for i, c in ipairs(old._children) do
        if c == self then table.remove(old._children, i); break end
      end
    end
    self._parent = p
    if p and p._children then table.insert(p._children, self) end
  end
  -- ScrollFrame is the only widget on this client that clips its children, so the magnifier is built
  -- out of one and the stub has to model its three calls.
  function f:SetScrollChild(c) self._scrollChild = c end
  function f:GetScrollChild() return self._scrollChild end
  function f:SetHorizontalScroll(v) self._hscroll = v end
  function f:GetHorizontalScroll() return self._hscroll or 0 end
  function f:SetVerticalScroll(v) self._vscroll = v end
  function f:GetVerticalScroll() return self._vscroll or 0 end
  function f:GetObjectType() return self._kind end
  function f:EnableMouse(v) self._mouse = v end
  function f:EnableMouseWheel() end
  function f:SetFrameLevel(l) self._level = l end
  function f:GetFrameLevel() return self._level end
  function f:SetFrameStrata(s) self._strata = s end
  function f:GetFrameStrata() return self._strata end
  function f:SetToplevel(v) self._toplevel = v end
  function f:SetMovable(v) self._movable = v end
  function f:SetClampedToScreen(v) self._clamped = v end
  function f:RegisterForDrag() end
  function f:StartMoving() end
  function f:StartSizing(point) self._sizingFrom = point end
  function f:StopMovingOrSizing() self._sizingFrom = nil end
  function f:SetResizable(v) self._resizable = v end
  function f:SetMinResize(w, h) self._minResize = { w, h } end
  function f:SetMaxResize(w, h) self._maxResize = { w, h } end
  function f:SetAttribute(k, v) self._attrs = self._attrs or {}; self._attrs[k] = v end
  function f:GetAttribute(k) return self._attrs and self._attrs[k] end
  function f:SetScale(s) self._scale = s end
  function f:GetScale() return self._scale or 1 end
  function f:GetEffectiveScale() return self._scale or 1 end
  function f:IsProtected() return self._protected and true or false end
  function f:RegisterEvent(e) self._events[e] = true end
  function f:UnregisterAllEvents() self._events = {} end
  function f:RegisterForClicks() end
  function f:SetScript(s, fn) self._scripts[s] = { fn } end
  function f:GetScript(s) local l = self._scripts[s]; return l and l[1] end
  function f:HookScript(s, fn)
    self._scripts[s] = self._scripts[s] or {}
    table.insert(self._scripts[s], fn)
  end
  function f:Fire(s, ...) for _, fn in ipairs(self._scripts[s] or {}) do fn(self, ...) end end
  function f:Show() if not self._shown then self._shown = true; self:Fire("OnShow") end end
  function f:Hide() if self._shown then self._shown = false; self:Fire("OnHide") end end
  function f:CreateTexture(n, layer, _, sub)
    local t = newTexture(layer, self); t._sub = sub
    table.insert(self._regions, t)
    if n then _G[n] = t end
    return t
  end
  function f:CreateFontString(n, layer)
    local fs = newFontString(layer, self)
    table.insert(self._regions, fs)
    if n then _G[n] = fs end
    return fs
  end
  function f:GetRegions() return unpack(self._regions) end
  function f:GetChildren() return unpack(self._children) end
  function f:GetPoint(i)
    local p, rel, rp, x, y = pointOf(self, i)
    if not p then return nil end
    return p, rel or self._parent, rp, x, y
  end
  function f:GetNumPoints() return #self._points end
  -- Set*Texture accepts either a path or a texture object, and Get*Texture always hands back a
  -- TEXTURE — that asymmetry is the whole reason core/MaxMin.lua seeds from a path and then crops
  -- through the handle, so the stub has to model it rather than store whatever it was given.
  local function stateSetter(key)
    return function(self, arg)
      if type(arg) == "string" then
        local t = newTexture("ARTWORK", self)
        t:SetTexture(arg)
        self[key] = t
      else
        self[key] = arg
      end
    end
  end
  f.SetNormalTexture    = stateSetter("_normal")
  f.SetPushedTexture    = stateSetter("_pushed")
  f.SetHighlightTexture = stateSetter("_highlight")
  f.SetDisabledTexture  = stateSetter("_disabled")
  function f:GetNormalTexture() return self._normal end
  function f:GetPushedTexture() return self._pushed end
  function f:GetHighlightTexture() return self._highlight end
  function f:GetDisabledTexture() return self._disabled end
  -- The checked TEXTURE and the checked STATE are unrelated things that were briefly sharing a
  -- field here, so ticking a box wiped its art. They are separate on the client too.
  f.SetCheckedTexture = stateSetter("_checkedTex")
  function f:GetCheckedTexture() return self._checkedTex end
  function f:SetChecked(v) self._checked = v and true or false end
  function f:GetChecked() return self._checked end
  function f:Enable() self._enabled = true end
  function f:Disable() self._enabled = false end
  function f:IsEnabled() return self._enabled ~= false end
  function f:SetText(t) self._text = t end
  function f:GetText() return self._text end
  function f:SetAutoFocus() end
  function f:ClearFocus() end
  function f:SetScrollChild(c) self._scrollChild = c end
  function f:GetScrollChild() return self._scrollChild end
  function f:SetHitRectInsets() end
  -- A frame with NO backdrop errors on GetBackdropColor, which is the state the map's tooltip was
  -- actually found in -- and the reason the repair pcalls that read rather than guarding on it.
  function f:SetBackdrop(bd) self._backdrop = bd; if bd then self._bdColor = { 1, 1, 1, 1 } end end
  function f:GetBackdrop() return self._backdrop end
  function f:SetBackdropColor(r, g, b, a) self._bdColor = { r, g, b, a } end
  function f:GetBackdropColor()
    if not self._backdrop then error("no backdrop") end
    return unpack(self._bdColor or { 0, 0, 0, 0 })
  end
  function f:SetBackdropBorderColor() end
  if name then _G[name] = f end
  return f
end

function CreateFrame(kind, name, parent, template) return newFrame(kind, name, parent) end

function hooksecurefunc(a, b, c)
  -- Both signatures: hooksecurefunc(name, post) and hooksecurefunc(table, key, post).
  local tbl, key, post
  if type(a) == "string" then tbl, key, post = _G, a, b else tbl, key, post = a, b, c end
  local orig = tbl[key]
  tbl[key] = function(...) local r = { orig(...) }; post(...); return unpack(r) end
end

UIParent = newFrame("Frame", "UIParent")
UIParent:SetSize(1920, 1080)
UIPanelWindows = { WorldMapFrame = { area = "center" } }
UISpecialFrames = {}
GameTooltip = { SetOwner = function() end, SetText = function() end, Show = function() end,
                Hide = function() end, SetQuestLogItem = function() end }
UIErrorsFrame = { AddMessage = function() end }
function GetPhysicalScreenSize() return 1920, 1080 end
-- Returns a BOOLEAN, as the real one does. Handing back the stored string instead would be a lie
-- with teeth: "0" is truthy in Lua, so a stub that returns it makes an off CVar read as on and any
-- code that trusts GetCVarBool passes the test while being wrong in game.
function GetCVarBool(k)
  local v = _G._cvars and _G._cvars[k]
  if v == nil then return false end
  if v == false or v == 0 or v == "0" or v == "" then return false end
  return true
end
function SetCVar(k, v) _G._cvars = _G._cvars or {}; _G._cvars[k] = v end
local inCombat = false
function InCombatLockdown() return inCombat end
-- A cursor the test can move and a button it can hold: the resize is driven off both, frame by
-- frame, rather than handed to the client's own sizing machinery.
local cursorX, cursorY = 0, 0
function GetCursorPosition() return cursorX, cursorY end
local mouseHeld = false
function IsMouseButtonDown() return mouseHeld end
-- C_Timer.After as a queue the test pumps by hand: the breadcrumb defers a retry through it when
-- the bar's anchored width has not resolved, and a fire-immediately stub would hide the difference
-- between "retried and recovered" and "never needed to".
local timerQueue = {}
C_Timer = { After = function(_, fn) timerQueue[#timerQueue + 1] = fn end }
function runTimers(rounds)
  for _ = 1, (rounds or 6) do
    local q = timerQueue
    if #q == 0 then return end
    timerQueue = {}
    for _, fn in ipairs(q) do fn() end
  end
end
function GetCVar(k) return _G._cvars and _G._cvars[k] end
function PlaySound() end
function HideUIPanel(f) f:Hide() end
strupper = string.upper
WORLD, QUEST_LOG, WORLD_MAP = "World", "Quest Log", "Map"
MAXIMIZE, MINIMIZE = "Maximize", "Minimize"
OBJECTIVES_LABEL, DESCRIPTION, BACK = "Objectives", "Description", "Back"
MAX_WATCHABLE_QUESTS = 25
-- The client's own localised quest-tag constants. The panel matches `questTag` against THESE rather
-- than English literals, so a non-English client keeps its type badges.
RAID, DUNGEON, PVP, ELITE, GROUP = "Raid", "Dungeon", "PvP", "Elite", "Group"

-- ── the 3.3.5a world-map frame tree ─────────────────────────────────────────

WORLDMAP_WINDOWED_SIZE = 0.588   -- the CLIENT's constant; the port must not reuse it
WORLDMAP_FULLMAP_SIZE  = 1.0
-- The client starts in its FULLSCREEN map mode, which is what makes forceWindowedMode a real
-- transition rather than a no-op. (A player who was already windowed is the uninteresting case.)
WORLDMAP_SETTINGS      = { size = WORLDMAP_FULLMAP_SIZE }
WORLDMAP_POI_FRAMELEVEL = 100
WORLDMAP_WORLD_ID      = 0

local WMF = newFrame("Frame", "WorldMapFrame", UIParent)
WMF:SetSize(623, 437)
newFrame("Frame", "WorldMapPositioningGuide", WMF)

local detail = newFrame("Frame", "WorldMapDetailFrame", WMF)
detail:SetSize(1002, 668)
newFrame("Button", "WorldMapButton", WMF):SetSize(1002, 668)
newFrame("Frame", "WorldMapFrameAreaFrame", WMF)
local blob = newFrame("Frame", "WorldMapBlobFrame", WMF)
blob._protected = true
local blobDraws = {}
function blob:DrawQuestBlob(id, show) blobDraws[#blobDraws + 1] = { id = id, show = show } end
newFrame("Frame", "WorldMapPOIFrame", WorldMapButton)
-- The client's landmark pins. It creates and re-shows WorldMapFramePOI1..N on every map update, so
-- anything that filters them has to re-apply rather than hide once -- which is the behaviour the
-- filter assertions drive.
for i = 1, 3 do
  local poi = newFrame("Button", "WorldMapFramePOI" .. i, WorldMapPOIFrame)
  poi:SetSize(16, 16)
  poi._texture = poi:CreateTexture(nil, "ARTWORK")
end

-- Chrome the port must suppress. Textures carry the classic art PATH so the path-matched sweep has
-- something real to find; the named widgets are frames.
local classicArt = WMF:CreateTexture("WorldMapFrameBorderTL", "BORDER")
classicArt:SetTexture("Interface\\WorldMap\\UI-WorldMap-Border-TL")
local keepMe = WMF:CreateTexture(nil, "BORDER")
keepMe:SetTexture("Interface\\SomethingElse\\NotTheMap")

-- THE MAP ITSELF lives under Interface\\WorldMap\\ too, which is the whole risk in matching that
-- directory broadly. These tiles must survive the sweep -- if they do not, the map goes blank.
local detailTiles = {}
for i = 1, 12 do
  local t = detail:CreateTexture("WorldMapDetailTile" .. i, "ARTWORK")
  t:SetTexture("Interface\\WorldMap\\Dalaran\\Dalaran" .. i)
  detailTiles[i] = t
end

-- The fullscreen backdrop quadrants and the quest parchment are NOT on WorldMapFrame -- they
-- hang off CHILD frames, which is why the first in-game run left a full 1024x768 of classic art
-- painted around a 702-wide window.
local questPanelChild = newFrame("Frame", "WorldMapQuestFrameBackdrop", WMF)
local parchment = questPanelChild:CreateTexture(nil, "BACKGROUND")
parchment:SetTexture("Interface\\QuestFrame\\QuestBackground")
local quadrantChild = newFrame("Frame", "WorldMapFrameBackdropHolder", WMF)
local quadrant = quadrantChild:CreateTexture(nil, "BACKGROUND")
quadrant:SetTexture("Interface\\WorldMap\\UI-WorldMap-Middle1")

for _, n in ipairs({ "WorldMapFrameMiniBorderLeft", "WorldMapFrameMiniBorderRight",
                     "WorldMapTitleButton", "BlackoutWorld",
                     "WorldMapContinentDropDown", "WorldMapZoneDropDown",
                     "WorldMapZoneMinimapDropDown", "WorldMapZoomOutButton",
                     "WorldMapMagnifyingGlassButton", "WorldMapFrameSizeUpButton",
                     "WorldMapFrameSizeDownButton", "WorldMapQuestScrollFrame",
                     "WorldMapQuestDetailScrollFrame", "WorldMapQuestRewardScrollFrame",
                     "WorldMapTrackQuest" }) do
  newFrame("Frame", n, WMF):Show()
end
-- The floor selector. The client only shows it where GetNumDungeonMapLevels() > 0, which is why it
-- went unnoticed until a map that HAS floors: it then floats over the chrome, showing "Dalaran City"
-- next to the breadcrumb crumb that replaced it.
for _, n in ipairs({ "WorldMapLevelDropDown", "WorldMapLevelUpButton", "WorldMapLevelDownButton" }) do
  newFrame("Frame", n, WMF):Show()
end
WorldMapQuestShowObjectives = newFrame("CheckButton", "WorldMapQuestShowObjectives", WMF)
WorldMapQuestShowObjectives:Show()
WorldMapFrameTitle = WMF:CreateFontString("WorldMapFrameTitle", "OVERLAY")
WorldMapFrameAreaLabel = WMF:CreateFontString("WorldMapFrameAreaLabel", "OVERLAY")
WorldMapFrameAreaDescription = WMF:CreateFontString("WorldMapFrameAreaDescription", "OVERLAY")

-- The canvas tooltip, as found: a child of the map window with NO backdrop at all, so its text sat
-- straight on the parchment.
newFrame("GameTooltip", "WorldMapTooltip", WMF)

local closeBtn = newFrame("Button", "WorldMapFrameCloseButton", WMF)
-- The client's own handler, verbatim in shape: `HideUIPanel(self:GetParent())`. A stub that just
-- no-ops cannot catch the fault this actually caused -- reparenting the button made the X hide the
-- CHROME instead of the map, permanently, because nothing ever shows the border again.
local CLOSE_HANDLER = function(self) HideUIPanel(self:GetParent()) end
closeBtn:SetScript("OnClick", CLOSE_HANDLER)

-- The overlay (fog-of-war) API. Only DISCOVERED subzones are ever reported -- which is the whole
-- reason the module has to keep a store of its own. `pixelfix` and the zero record are junk the
-- client genuinely serves and that must not be written to a permanent store.
NUM_WORLDMAP_OVERLAYS = 0
local OVERLAY_PREFIX = "Interface\\WorldMap\\Ashenvale\\"
local liveOverlays = {
  { "Astranaar",   300, 200, 100,  50 },
  { "pixelfix",      1,   1,   0,   0 },
}
function GetNumMapOverlays() return #liveOverlays end
function GetMapOverlayInfo(i)
  local o = liveOverlays[i]
  if not o then return nil end
  return OVERLAY_PREFIX .. o[1], o[2], o[3], o[4], o[5]
end

local poiBoundsCalls, hitTranslationCalls, sizeDownCalls = 0, 0, 0
function WorldMapFrame_SetPOIMaxBounds() poiBoundsCalls = poiBoundsCalls + 1 end
function WorldMapBlobFrame_CalculateHitTranslations() hitTranslationCalls = hitTranslationCalls + 1 end
-- The client's right-click zoom-out. Which script it is wired from varies by build, so the magnifier
-- guards the FUNCTION rather than the script -- and that is what this models.
zoomOutCalls = 0
function WorldMapZoomOutButton_OnClick() zoomOutCalls = zoomOutCalls + 1 end
function WorldMap_ToggleSizeDown()
  sizeDownCalls = sizeDownCalls + 1
  WORLDMAP_SETTINGS.size = WORLDMAP_WINDOWED_SIZE
  -- The client re-Shows its chrome here. This is fact (2) in the header, and it is exactly what
  -- makes a one-shot Hide() insufficient.
  for _, n in ipairs({ "WorldMapFrameMiniBorderLeft", "WorldMapFrameMiniBorderRight",
                       "WorldMapContinentDropDown", "WorldMapZoneDropDown" }) do
    if _G[n] then _G[n]:Show() end
  end
end
function WorldMap_ToggleSizeUp() end
function WorldMapFrame_Update() end
function WorldMapFrame_DisplayQuestPOI() end
local questToggleCalls, questUpdateCalls = 0, 0
-- It TOGGLES, and modelling that is the point: a stub that only counts calls cannot tell a setter
-- from a flip, and the flip was the bug -- asking for the value already held turned the markers off.
function WorldMapQuestShowObjectives_Toggle()
  questToggleCalls = questToggleCalls + 1
  SetCVar("questPOI", GetCVarBool("questPOI") and "0" or "1")
end
function WorldMapFrame_UpdateQuests() questUpdateCalls = questUpdateCalls + 1 end

-- ── the map model ───────────────────────────────────────────────────────────

local CONTINENTS = { "Eastern Kingdoms", "Kalimdor", "Outland", "Northrend" }
local ZONES = { [2] = { "Ashenvale", "Darkshore", "Durotar" } }
local curContinent, curZone, curFloor, numFloorsHere = 2, 1, 0, 0
function GetMapContinents() return unpack(CONTINENTS) end
function GetMapZones(c) return unpack(ZONES[c] or {}) end
function GetCurrentMapContinent() return curContinent end
function GetCurrentMapZone() return curZone end
local zoomCalls = {}
function SetMapZoom(c, z) zoomCalls[#zoomCalls + 1] = { c, z }; curContinent = c or 0; curZone = z or 0 end
function GetNumDungeonMapLevels() return numFloorsHere end
function GetCurrentMapDungeonLevel() return curFloor end
function SetDungeonMapLevel(i) curFloor = i end
-- The client's own hover-highlight call. It names the region under the cursor; the wheel turns that
-- NAME into an index by searching the live zone list, which is the part worth testing.
local highlightName = nil
function UpdateMapHighlight(x, y) return highlightName end
function SetMapToCurrentZone() curContinent, curZone = 2, 3 end
local currentMapFile = "Ashenvale"
function GetMapInfo() return currentMapFile end
FLOOR_NUMBER = "Floor %d"

-- ── the quest log ───────────────────────────────────────────────────────────
--
-- 3.3.5a shape: a FLAT list where headers and quests interleave, GetQuestLogTitle returns
-- (title, level, tag, group, isHeader, isCollapsed, isComplete, isDaily), and there is NO quest ID
-- in that return — it comes off the LINK.
local QLOG = {
  { title = "Ashenvale",        header = true },
  { title = "The Lost Pilot",   level = 20, id = 6383, complete = 0 },
  { title = "Ordanus",          level = 22, id = 6384, complete = 1, daily = true },
  { title = "Deep Ocean",       level = 25, id = 6390, complete = 0, tag = "Dungeon" },
  { title = "Durotar",          header = true },
  { title = "Vile Familiars",   level = 6,  id = 4021, complete = 0 },
}
local watched = {}
function GetNumQuestLogEntries() return #QLOG, 3 end
function GetQuestLogTitle(i)
  local e = QLOG[i]
  if not e then return nil end
  return e.title, e.level, e.tag, e.group, e.header, e.collapsed, e.complete, e.daily
end
function GetQuestLink(i)
  local e = QLOG[i]
  if not (e and e.id) then return nil end
  return "|cffffff00|Hquest:" .. e.id .. ":" .. (e.level or 1) .. "|h[" .. e.title .. "]|h|r"
end
function IsQuestWatched(i) return watched[i] and true or false end
function AddQuestWatch(i) watched[i] = true end
function RemoveQuestWatch(i) watched[i] = nil end
function GetNumQuestWatches() local n = 0; for _ in pairs(watched) do n = n + 1 end; return n end
local selectedEntry
function SelectQuestLogEntry(i) selectedEntry = i end
function GetQuestLogSelection() return selectedEntry end
function GetQuestLogQuestText() return "Find the pilot.", "Speak to the pilot." end
local OBJECTIVES = { [2] = { { "Pilot found", true }, { "Wreckage searched 0/1", false } } }
function GetNumQuestLeaderBoards(i) return #(OBJECTIVES[i] or {}) end
function GetQuestLogLeaderBoard(j, i)
  local o = OBJECTIVES[i] and OBJECTIVES[i][j]
  if not o then return nil end
  return o[1], "monster", o[2]
end
function GetNumQuestLogChoices() return 2 end
function GetQuestLogChoiceInfo(i) return "Choice " .. i, "icon" .. i, 1, 3 end
function GetNumQuestLogRewards() return 1 end
function GetQuestLogRewardInfo(i) return "Reward " .. i, "ricon", 2, 2 end
function GetQuestLogRewardMoney() return 12345 end
function GetQuestLogRewardXP() return 500 end
function GetQuestLogPushable() return true end
function CollapseQuestHeader(i) if QLOG[i] then QLOG[i].collapsed = 1 end end
function ExpandQuestHeader(i) if QLOG[i] then QLOG[i].collapsed = nil end end
function GetCoinTextureString(c) return "MONEY:" .. c end
function UnitLevel() return 20 end
function GetQuestGreenRange() return 5 end
ITEM_QUALITY_COLORS = { [2] = { r = 0, g = 1, b = 0 }, [3] = { r = 0, g = 0, b = 1 } }

-- ── addon stubs ─────────────────────────────────────────────────────────────

DragonUI_NewEra = {
  L = setmetatable({}, { __index = function(_, k) return k end }),
  db = { worldmap = {} },
  Log = function() end,
}
local NE = DragonUI_NewEra

local ROCK = [[Interface\AddOns\DragonUI_NewEra\Textures\Common\374155-uibackground-rock.blp]]
-- The RedButton family, as core/NineSliceLayouts.lua registers it. Not loaded here (that file is
-- one long table of art measurements with no behaviour to test), so the six names core/MaxMin.lua
-- reaches for are seeded directly.
local atlases = {}
for _, n in ipairs({ "redbutton-expand-2x", "redbutton-expand-pressed-2x",
                     "redbutton-condense-2x", "redbutton-condense-pressed-2x",
                     "redbutton-highlight-2x", "redbutton-exit-2x" }) do
  atlases[n] = { file = 4698972, left = 0, right = 1, top = 0, bottom = 1, width = 36, height = 38 }
end
NE.tex = {
  -- Only the sheets that are registered ELSEWHERE are seeded here. The world map's own sheets are
  -- deliberately left out so that modules/worldmap/Assets.lua has to register them itself -- with
  -- them pre-seeded, deleting a RegisterLocal changed nothing and the test said everything was fine.
  localFiles = { [374155] = ROCK,
                 [4698972] = [[Interface\AddOns\DragonUI_NewEra\Textures\Common&98972-redbutton-exit-2x.blp]] },
  RegisterLocal = function(fdid, path) NE.tex.localFiles[fdid] = path end,
  Local = function(fdid) return NE.tex.localFiles[fdid] end,
  RegisterAtlas = function(n, info) atlases[n] = info end,
  RegisterAtlases = function(t) for n, info in pairs(t) do atlases[n] = info end end,
  _atlasEntry = function(n) return atlases[n] end,
  HasAtlas = function(n) return atlases[n] ~= nil end,
  SetAtlas = function(tex, name)
    local e = atlases[name]
    if not (tex and e) then return false end
    local src = NE.tex.localFiles[e.file]
    if not src then return false end
    tex:SetTexture(src); tex:SetTexCoord(e.left, e.right, e.top, e.bottom)
    tex._atlas = name
    return true
  end,
}

local afterCombatQueue = {}
NE.FrameUtil = {
  AfterCombat = function(fn)
    if inCombat then afterCombatQueue[#afterCombatQueue + 1] = fn else fn() end
  end,
  PinPixelPerfect = function(f, s)
    f._pinned = s or 1
    -- What the real one computes at 1080p: 768/physicalHeight. Modelled rather than left at 1,
    -- because the resize converts cursor coordinates through exactly this number and a stub where
    -- every scale is 1 cannot tell a correct conversion from a missing one.
    f._scale = (768 / 1080) * (s or 1)
  end,
  EscClose = function(f)
    local n = type(f) == "string" and f or (f.GetName and f:GetName())
    for _, x in ipairs(UISpecialFrames) do if x == n then return end end
    table.insert(UISpecialFrames, n)
  end,
  PersistWindowPosition = function(f, key, default, handle)
    f._persistKey, f._persistDefault, f._dragHandle = key, default, handle
  end,
  RestoreWindowPosition = function() return false end,
  ForEachRegion = function(frame, kind, layer, fn)
    if not (frame and frame.GetRegions and fn) then return 0 end
    local regions = { frame:GetRegions() }
    for i = 1, #regions do
      local r = regions[i]
      if r and (not kind or r:GetObjectType() == kind)
           and (not layer or r:GetDrawLayer() == layer) then fn(r) end
    end
  end,
}
NE.frameutil = NE.FrameUtil
local function flushCombat()
  inCombat = false
  local q = afterCombatQueue; afterCombatQueue = {}
  for _, fn in ipairs(q) do fn() end
end

NE.font = { FRIZ = "Fonts\\FRIZQT__.TTF", MORPHEUS = "Fonts\\MORPHEUS.ttf",
            Set = function(fs, path, size, flags, fallback)
              if not fs:SetFont(path, size, flags or "") and fallback then
                fs:SetFontObject(fallback)
              end
            end }
NE.money = { Text = function(c) return "MONEY:" .. tostring(c) end }
NE.difficultyTier = function(level)
  local d = (level or 0) - 20
  if d >= 5 then return "impossible" elseif d >= 3 then return "verydifficult"
  elseif d >= -2 then return "difficult" elseif d >= -5 then return "standard"
  else return "trivial" end
end

NE.panelchrome = {
  BODY_TINT = { 0.32, 0.32, 0.32 },
  TitleBand = function(f)
    if f._neTitleBand then return f._neTitleBand end
    local b = CreateFrame("Frame", nil, f)
    f._neTitleBand = b
    return b
  end,
  SetTitle = function(f, text, fs, anchor)
    fs = fs or f.Title
    if fs and text then fs:SetText(text) end
    f._neTitle = fs
  end,
  ModernizeCloseButton = function(cb, opts) cb._modernized = opts or {} end,
}
NE.nineslice = {
  ApplyLayout = function(container, layout) container._layout = layout; return true end,
  AttachInset = function(parent)
    local ns = CreateFrame("Frame", nil, parent)
    ns:SetAllPoints(parent)
    ns:EnableMouse(false)
    ns._layout = "InsetFrameTemplate"
    return ns
  end,
}
NE.portrait = { ApplyCutout = function(tex, parent) tex._cutout = parent end }
NE.scrollbar = { BuildCustomPixel = function(sf) sf._neCustomBar = { }; return sf._neCustomBar end }

local panelmgrCalls = { register = 0, reflow = 0, promote = 0 }
NE.panelmgr = {
  Register = function() panelmgrCalls.register = panelmgrCalls.register + 1 end,
  Reflow   = function() panelmgrCalls.reflow = panelmgrCalls.reflow + 1 end,
  Promote  = function() panelmgrCalls.promote = panelmgrCalls.promote + 1 end,
  NoteDragStart = function() end, DragMoved = function() return true end,
  MarkUserPlaced = function() end,
}
NE.modules = {
  RIVALS = {},
  registry = {},
  Register = function(spec) NE.modules.registry[spec.name] = spec end,
}
NE.qa = { modules = {} }
EasyMenu = function() end
-- A stand-in for ModernMapMarkers. Only the seam matters: it redraws off WORLD_MAP_UPDATE and
-- short-circuits on an unchanged zone, so an addon that moves the map itself has to say so.
local mmmRedraws = 0
MMM = { ForceRedraw = function() mmmRedraws = mmmRedraws + 1 end }
local menuOpened
NE.menu = {
  ToggleAnchored = function(generator, anchor)
    local root = { children = {} }
    function root:CreateTitle(t) self.children[#self.children+1] = {kind="title", text=t}; return self end
    function root:CreateCheckbox(t, isSel, onClick)
      self.children[#self.children+1] = {kind="checkbox", text=t, isSelected=isSel, onClick=onClick}
      return self
    end
    function root:CreateButton(t, onClick)
      self.children[#self.children+1] = {kind="button", text=t, onClick=onClick}; return self
    end
    generator(nil, root)
    menuOpened = { root = root, anchor = anchor }
    return root
  end,
}
local chatLines = {}
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) chatLines[#chatLines + 1] = m end }
SLASH_NEWORLDMAP1, SLASH_NEWORLDMAP2 = nil, nil
SlashCmdList = {}

-- ── load the real files ─────────────────────────────────────────────────────

local function load(path)
  local chunk, err = loadfile(ADDON .. path)
  if not chunk then error("load " .. path .. ": " .. tostring(err)) end
  chunk()
end

load("core/Squelch.lua")
load("core/MaxMin.lua")
-- The RIVALS row lives in core/Modules.lua, which cannot be loaded here (it builds its own event
-- dispatcher against DragonUI's DB). Read it out of the file instead — the point of the assertion
-- is that the row EXISTS and names Mapster, which is a fact about the source, not about runtime.
local modulesSrc = io.open(ADDON .. "core/Modules.lua"):read("*a")

load("core/NavBar.lua")
load("modules/worldmap/Assets.lua")
load("modules/worldmap/WorldMap.lua")
load("modules/worldmap/NavBar.lua")
load("modules/worldmap/Pins.lua")
load("modules/worldmap/DungeonMapData.lua")
load("modules/worldmap/DungeonMap.lua")
load("modules/worldmap/CanvasZoom.lua")
load("modules/worldmap/WheelZoom.lua")
-- The generated seed loads first, exactly as the TOC orders it: FogClear reads it.
load("modules/worldmap/OverlayData.lua")
load("modules/worldmap/FogClear.lua")
load("modules/worldmap/PinFilter.lua")
load("modules/worldmap/QuestLogPanel.lua")
load("modules/worldmap/QuestLogDetail.lua")
-- The OTHER consumer of core/NavBar.lua. Loaded to prove the shared widget still serves both
-- shapes of trail -- the whole point of merging them.
load("modules/encounterjournal/NavBar.lua")
load("modules/worldmap/Diagnostics.lua")
load("modules/worldmap/Register.lua")

local WM = NE.worldmap
local P  = NE.questlogpanel

print("== rival gate ==")
ok(modulesSrc:find("WORLDMAP%s*=") ~= nil, "core/Modules.lua declares a WORLDMAP rivals row")
ok(modulesSrc:find('"Mapster"') ~= nil, "the WORLDMAP rivals row names Mapster")
ok(NE.modules.registry.WorldMap ~= nil, "the module registers itself")

-- ONE TOGGLE FOR THE WHOLE WINDOW. Fog, magnification and the filter were briefly modules of their
-- own; that is four options rows for what the player experiences as one feature. The controls worth
-- flipping in play are on the map itself, behind the filter button, and need no reload.
for _, gone in ipairs({ "WorldMapZoom", "WorldMapFilter", "WorldMapFog" }) do
  eq(NE.modules.registry[gone], nil, gone .. " is NOT a separate module -- one window, one switch")
end

-- REGISTERED IS NOT THE SAME AS OFFERED, and that gap is the bug this checks for. The module
-- registered itself, gated its own boot and reported conflicts correctly -- and the options panel
-- still had no row for it, because that panel renders a HARDCODED list rather than the registry. It
-- was switchable in principle and unswitchable in practice for the entire life of the port.
do
  local opts = io.open(ADDON .. "integration/Options.lua"):read("*a")
  ok(opts:find('id = "WorldMap"', 1, true) ~= nil,
     "the options panel actually renders a row for the map, not just the registry knowing about it")
end

-- Everything the window owns boots from the ONE module, or switching it off would leave pieces
-- running against a window that was never built.
do
  local src = io.open(ADDON .. "modules/worldmap/Register.lua"):read("*a")
  local bootChunk = src:match("local function boot%(%)(.-)\nend")
  ok(bootChunk ~= nil, "the map's boot function is readable")
  if bootChunk then
    for _, piece in ipairs({ "WM.Arm", "WM.fog.Arm", "WM.canvaszoom.Arm", "WM.wheel.Arm",
                             "WM.filter.Arm", "WM.dungeon.Arm" }) do
      ok(bootChunk:find(piece, 1, true) ~= nil, "  boot arms " .. piece)
    end
    -- Order is load-bearing in one place: the wheel only drives the magnifier.
    local zoomAt  = bootChunk:find("WM.canvaszoom.Arm", 1, true)
    local wheelAt = bootChunk:find("WM.wheel.Arm", 1, true)
    ok(zoomAt and wheelAt and zoomAt < wheelAt,
       "  and arms the magnifier before the wheel that drives it")
  end
end

ok(NE.modules.registry.WorldMap.conflictsWith ~= nil or NE.modules.RIVALS.WORLDMAP == nil,
   "the module declares conflictsWith when RIVALS.WORLDMAP exists")

-- ── boot ────────────────────────────────────────────────────────────────────

print("== boot ==")
WM.Arm()
WM.BuildNavBar()
WM.ArmPins()
WM.fog.Arm()
WM.dungeon.Arm()
P.Arm()

-- Snapshotted the moment boot finishes, because the quest-marker assertions live much further down
-- the file -- by which time the cog test has armed the same state, and a boot that never armed it
-- would look identical. (A mutation check caught exactly that.)
local bootQuestChecked = WorldMapQuestShowObjectives:GetChecked()
local bootToggleCalls, bootUpdateCalls = questToggleCalls, questUpdateCalls

ok(WMF._neChromed, "the chrome ran")
eq(UIPanelWindows.WorldMapFrame, nil, "the map is out of the secure panel row")
-- ...and STAYS out. Both of the client's size toggles rewrite that entry, so clearing it once at
-- boot leaves the panel manager free to start moving the window again on the next size change.
UIPanelWindows.WorldMapFrame = { area = "center" }
WorldMap_ToggleSizeDown()
eq(UIPanelWindows.WorldMapFrame, nil,
   "the entry is cleared again after a size toggle puts it back")
eq(WMF:GetAttribute("UIPanelLayout-enabled"), false, "and its UIPanel layout attribute is cleared")
ok(UISpecialFrames[1] == "WorldMapFrame", "ESC still closes it (UISpecialFrames)")
eq(WMF._strata, "DIALOG", "the window sits at DIALOG, like every other window in this addon")
eq(panelmgrCalls.register, 1, "it joins the shared panel row")
ok(sizeDownCalls >= 1, "the client is forced into windowed mode via its own toggle")
eq(_G._cvars and _G._cvars.miniWorldMap, 1, "and miniWorldMap is pinned")

-- ── fact 2: suppression must SURVIVE the client re-showing its chrome ───────

print("== suppression ==")
local mini = _G.WorldMapFrameMiniBorderLeft
ok(not mini:IsShown(), "the mini border is hidden")
ok(not _G.WorldMapContinentDropDown:IsShown(), "the continent dropdown is hidden")
ok(not _G.WorldMapFrameSizeUpButton:IsShown(), "the client's size buttons are hidden")
ok(not _G.WorldMapLevelDropDown:IsShown(),
   "and so is the floor selector, which the breadcrumb's last crumb replaces")
ok(not classicArt:IsShown(), "the classic border art is hidden (matched by path)")
ok(keepMe:IsShown(), "...and a texture that is NOT map art is left alone")
ok(not parchment:IsShown(), "quest parchment on a CHILD frame is hidden (the sweep goes a level down)")
ok(not quadrant:IsShown(), "and so is a backdrop quadrant on a child frame")
-- The safety net for matching the whole WorldMap art directory: the map must survive it.
local tilesShown = 0
for _, t in ipairs(detailTiles) do if t:IsShown() then tilesShown = tilesShown + 1 end end
eq(tilesShown, 12, "every map detail tile SURVIVES the sweep (same directory as the chrome)")

-- This is the assertion the whole helper exists for.
WorldMap_ToggleSizeDown()
ok(not mini:IsShown(), "the mini border STAYS hidden after the client re-shows it")
ok(not _G.WorldMapContinentDropDown:IsShown(), "the continent dropdown STAYS hidden too")

-- ── fact 1: geometry ────────────────────────────────────────────────────────

print("== geometry ==")
local FRAME_W, FRAME_H = 702, 534
local SPACER_H, INSET_L, INSET_R, INSET_B = 67, 2, 3, 2
local PANEL_W = 330

-- The panel opens by default, so close it first to measure the bare window.
P.SetShown(false)
eq(WMF:GetWidth(), FRAME_W, "the minimized window is retail's width")
eq(WMF:GetHeight(), FRAME_H, "the minimized window is retail's height")

local expectScale = math.min((FRAME_W - INSET_L - INSET_R) / 1002, (FRAME_H - SPACER_H - INSET_B) / 668)
near(WM.canvasScale, expectScale, "the canvas scale is derived from the canvas rect")
ok(WM.canvasScale ~= WM.clientWindowedSize,
   "and is NOT the scale the client itself was using")
near(WORLDMAP_SETTINGS.size, WM.canvasScale, "WORLDMAP_SETTINGS.size is written to OUR scale")
-- The identity every mode check on this client asks. Breaking it is what made the first in-game run
-- repaint the whole 1024x768 fullscreen chrome around a 702-wide window.
eq(WORLDMAP_SETTINGS.size, WORLDMAP_WINDOWED_SIZE,
   "...and WORLDMAP_WINDOWED_SIZE moves with it, so the client still believes it is windowed")
near(WM.clientWindowedSize, 0.588,
     "the client's ORIGINAL constant is captured before we take the global over")
ok(poiBoundsCalls > 0, "the POI bounds are re-run after the size write")
ok(hitTranslationCalls > 0, "the blob's hit translations are recalculated")
eq(blob.xRatio, nil, "the blob's cached ratio is cleared so the client recomputes it")

near(detail:GetScale(), WM.canvasScale, "WorldMapDetailFrame carries the scale")
near(WorldMapButton:GetScale(), WM.canvasScale, "so does WorldMapButton")
near(_G.WorldMapFrameAreaFrame:GetScale(), WM.canvasScale, "so does the area frame")
near(blob:GetScale(), WM.canvasScale, "so does the blob frame")
eq(_G.WorldMapPOIFrame._scale, nil,
   "WorldMapPOIFrame is NOT scaled (it inherits from WorldMapButton; scaling it would square it)")

-- WHERE THE MAP IS ANCHORED MOVED, deliberately. It used to hang off the window with its offsets
-- divided by its own scale; now the magnifier's clipping viewport carries the insets and the canvas
-- frames sit at the content frame's origin. The invariant the old assertions were really protecting
-- -- the map lands at (INSET_L, -SPACER_H) in WINDOW units -- is unchanged and is what is checked
-- here, one level up.
local p, rel, rp, x, y = pointOf(detail)
eq(p, "TOPLEFT", "the detail frame is anchored TOPLEFT")
eq(rel, WM.canvaszoom.content, "...to the zoom content frame, which is what clips it")
near(x, 0, "at the content origin")
near(y, 0, "in both axes")

-- Scoped, because this file is at Lua's 200-local ceiling for a main chunk.
do
  local _, vrel, _, vx, vy = pointOf(WM.canvaszoom.viewport)
  eq(vrel, WMF, "and the VIEWPORT is what hangs off the window")
  near(vx, INSET_L, "carrying the left inset in window units, undivided")
  near(vy, -SPACER_H, "and the title spacer above it")
  near(WM.canvaszoom.viewport:GetWidth(), WM.CurrentCanvasWidth(),
       "sized to exactly the canvas, so anything magnified past it is clipped", 0.5)
end

-- ── maximize ────────────────────────────────────────────────────────────────

print("== maximize ==")
WM.SetMaximized(true, true)
ok(WMF:GetWidth() > FRAME_W, "maximizing makes the window wider")
ok(WMF:GetHeight() > FRAME_H, "and taller")
-- The MAP's proportions, not the window's: the maximized mode opens the quest panel by default and
-- the minimized one does not, so the two windows legitimately have different shapes. What must not
-- change is the canvas itself.
near(WM.CurrentCanvasWidth() / (WMF:GetHeight() - SPACER_H - INSET_B),
     detail:GetWidth() / detail:GetHeight(),
     "the maximized map keeps the canvas aspect ratio", 0.02)
eq(NE.db.worldmap.maximized, true, "the preference is persisted")
-- STAYS AVAILABLE. It used to hide here, mirroring retail's fullscreen map -- but maximizing also
-- closed the panel, so hiding the toggle removed the only way to reopen it. Both could disappear
-- with nothing left to bring either back.
ok(WM.sideToggle:IsShown(), "the side-panel toggle stays available on the maximized map")
WM.SetMaximized(false, true)
eq(WMF:GetWidth(), FRAME_W, "minimizing puts the width back")
eq(NE.db.worldmap.maximized, false, "and persists that too")

-- ── fact 4: the close button ────────────────────────────────────────────────

print("== close button ==")
ok(closeBtn._modernized ~= nil, "the close button is reskinned")
eq(closeBtn:GetScript("OnClick"), CLOSE_HANDLER,
   "but its OnClick is STILL Blizzard's (replacing it blocks closing in combat)")
eq(closeBtn:GetParent(), WMF,
   "and it is NOT reparented -- that handler hides its parent, so the parent must stay the map")
ok(closeBtn:GetFrameLevel() > WMF._neBorder:GetFrameLevel(),
   "it draws above the chrome by LEVEL instead (a level is absolute, not relative to the parent)")

-- The fault itself, end to end.
closeBtn:Fire("OnClick")
ok(not WMF:IsShown(), "clicking the X closes the MAP")
ok(WMF._neBorder:IsShown(), "and leaves the chrome intact, so the next open is not gutted")
WMF:Show()
ok(WMF._neBorder:IsShown(), "which it is not")

-- ── the maximize/minimize button ────────────────────────────────────────────

print("== maxmin button ==")
local mm = WMF._neBorder._neMaxMin
ok(mm ~= nil, "the maximize/minimize button is built")
ok(not mm:IsMaximized(), "it starts on the restored (minimized) state")
eq(mm._normal._atlas, "redbutton-expand-2x",
   "a MINIMIZED map offers the maximize action, so it shows the EXPAND glyph")
mm:Fire("OnClick")
ok(mm:IsMaximized(), "clicking it flips the state")
eq(mm._normal._atlas, "redbutton-condense-2x", "and the glyph becomes CONDENSE")
ok(WMF:GetWidth() > FRAME_W, "and the window actually grew")
mm:Fire("OnClick")
eq(WMF:GetWidth(), FRAME_W, "clicking again restores it")

-- GLYPH AND TOOLTIP ARE ONE DECISION. They were two, and that cost a wrong fix: the window and the
-- button's cached flag drifted apart, which showed up as arrows pointing the wrong way AND a tooltip
-- naming the wrong action. The arrows got "fixed" by swapping the atlas mapping, which masked half
-- the symptom and left the other half. Asking the owner rather than caching makes the drift
-- impossible, so both halves are pinned here against the SAME source.
local tipText
local realSetText = GameTooltip.SetText
GameTooltip.SetText = function(self, t) tipText = t end

local function tooltipNow()
  tipText = nil
  mm:Fire("OnEnter")
  return tipText
end

ok(not WM.maximized, "with the window restored")
eq(mm._normal._atlas, "redbutton-expand-2x", "the glyph offers the maximize action")
eq(tooltipNow(), "Maximize", "and the tooltip names that same action")

WM.SetMaximized(true, false)
ok(mm:IsMaximized(), "maximizing the WINDOW moves the button with it")
eq(mm._normal._atlas, "redbutton-condense-2x", "the glyph follows")
eq(tooltipNow(), "Minimize", "and so does the tooltip -- they cannot name different actions")

-- The specific drift that shipped: the window changes behind the button's back. A cached flag would
-- keep answering the old value here; a question asked at draw time cannot.
mm._maximized = false
eq(mm:IsMaximized(), true, "a stale cached flag does not survive contact with the window's own answer")
eq(tooltipNow(), "Minimize", "so the tooltip still names the action the button will actually perform")

-- MAXIMIZE IS A MODE, AND THE SIZE ROUND-TRIPS THROUGH IT. Entering remembers the size being left;
-- leaving puts that size back. The previous design answered "am I maximized?" by comparing the
-- current width against the preset, which produced four separate faults -- the button doing the
-- opposite of its label, a saved width stranding it on minimize, the size not surviving a
-- minimize/maximize round trip, and the side panel and its toggle vanishing together.
WM.SetMaximized(false, false)
WM.SetCanvasWidth(880)
P.SetShown(true)
local chosen = WM.CurrentCanvasWidth()
ok(not mm:IsMaximized(), "a window at a size of its own is not in maximize mode")
eq(tooltipNow(), "Maximize", "so the button offers to maximize, whatever that size happens to be")

mm:Fire("OnClick")
ok(WM.maximized, "clicking it enters the mode")
eq(tooltipNow(), "Minimize", "and the button now offers the way back")
-- The GLYPH has to move on the click too, not merely the tooltip. It used to be drawn before the
-- callback ran -- i.e. from the state being left -- and only came right because this owner happens
-- to call SetStateSilently on the way back. An owner that did not would leave the button showing the
-- opposite of itself in both the art and the word.
eq(mm._normal._atlas, "redbutton-condense-2x", "and the glyph moved with it, on this same click")
ok(P.IsShown and P.IsShown() or P.shown, "the quest panel stays open across a maximize")
ok(WM.sideToggle:IsShown(), "and its toggle stays reachable")

mm:Fire("OnClick")
ok(not WM.maximized, "clicking again leaves the mode")
near(WM.CurrentCanvasWidth(), chosen, "and gives back the size you had before maximizing", 1)

-- The round trip has to survive repeating, which is what "my size is not kept" was about: the
-- restore width must only be written on the TRANSITION, never on a repeated call or a geometry pass.
mm:Fire("OnClick"); mm:Fire("OnClick")
near(WM.CurrentCanvasWidth(), chosen, "and again on a second round trip", 1)
WM.SetMaximized(true, false); WM.SetMaximized(true, false); WM.SetMaximized(false, false)
near(WM.CurrentCanvasWidth(), chosen,
     "and when the same mode is set twice -- a repeat must not overwrite the remembered size", 1)

-- The same click, with an owner that does NOT reconcile the button afterwards. This is what pins the
-- ordering rather than the world map's good manners.
do
  -- The owner's state changes INSIDE the callback, which is the shape that matters: `IsMaximized`
  -- prefers the live answer, so drawing the glyph before the callback runs draws the state being
  -- LEFT. A first attempt at this test gave the button no stateFunc, so it fell back to the cached
  -- flag -- which is set before either -- and the ordering could not bite at all. It scored zero.
  local ownerState = false
  local standalone = NE.maxmin.Build(newFrame("Frame", "NE_TestMaxMinHost", UIParent), {
    name = "NE_TestMaxMinButton",
    maximized = false,
    stateFunc  = function() return ownerState end,
    onMaximize = function() ownerState = true  end,
    onMinimize = function() ownerState = false end,
  })
  eq(standalone._normal._atlas, "redbutton-expand-2x", "a fresh button starts on the maximize glyph")
  standalone:Fire("OnClick")
  eq(standalone._normal._atlas, "redbutton-condense-2x",
     "one click flips the glyph, reading the owner AFTER it has changed its mind")
  standalone:Fire("OnClick")
  eq(standalone._normal._atlas, "redbutton-expand-2x", "and back again")
end

-- THE TWO SIZES ARE SEPARATE, which is what finally settled this control. Reported from a live
-- client: canvasW 1183.00 against a restore width of 1183.0016 -- the "size to come back to" had
-- become the maximize preset, so minimizing put the window back at exactly the size maximizing gives
-- it. Nothing moved, and the only thing the button appeared to do was flip its own label.
--
-- One shared width plus a remembered restore value is what made that reachable. Two keys cannot
-- express it: the modes cannot overwrite each other, so no guard is needed and none can be wrong.
do
  WM.SetMaximized(false, false)
  WM.SetCanvasWidth(720)
  local small = WM.CurrentCanvasWidth()

  WM.SetMaximized(true, false)
  WM.SetCanvasWidth(1000)
  local big = WM.CurrentCanvasWidth()
  ok(big > small + 1, "the maximized mode holds a size of its own")

  WM.SetMaximized(false, false)
  near(WM.CurrentCanvasWidth(), small, "minimizing returns to the small one", 0.5)
  WM.SetMaximized(true, false)
  near(WM.CurrentCanvasWidth(), big, "and maximizing to the size IT was last left at", 0.5)

  -- Repeating cannot degrade either of them.
  for _ = 1, 3 do WM.SetMaximized(false, false); WM.SetMaximized(true, false) end
  near(WM.CurrentCanvasWidth(), big, "however many times the two are swapped", 0.5)
  WM.SetMaximized(false, false)
  near(WM.CurrentCanvasWidth(), small, "in both directions", 0.5)

  -- THE BUTTON'S WORDS HAVE TO STAY TRUE. Two independent sizes can be dragged past each other, and
  -- once they cross, "maximize" takes you to the SMALLER window -- which is exactly what was seen in
  -- game and read as the button being inverted. The labels were right; the sizes had swapped.
  WM.SetMaximized(false, false)
  WM.SetCanvasWidth(1100)                 -- windowed, dragged out large
  WM.SetMaximized(true, false)
  WM.SetCanvasWidth(600)                  -- maximized, dragged in small: they would now cross
  local maxW = WM.CurrentCanvasWidth()
  WM.SetMaximized(false, false)
  local minW = WM.CurrentCanvasWidth()
  ok(maxW >= minW, "the maximized window is never smaller than the windowed one")

  -- The two rules are not the same rule twice. The read-time one guarantees what is on SCREEN; the
  -- write-time one keeps the stored pair ordered, so dragging one mode past the other CARRIES the
  -- other along instead of leaving it behind to be clamped later. Only the second survives dragging
  -- back down again -- which is what distinguishes them, and what a mutation of the write side has
  -- to fail on.
  WM.SetMaximized(false, false)
  NE.db.worldmap.canvasW, NE.db.worldmap.canvasWMax = 700, 700
  WM.SetCanvasWidth(1100)                 -- windowed dragged ABOVE the maximized size
  WM.SetCanvasWidth(750)                  -- then back down well below it
  WM.SetMaximized(true, false)
  near(WM.CurrentCanvasWidth(), 1100,
       "dragging the small window past the large one takes the large one with it, and it stays", 1)
  WM.SetMaximized(false, false)

  -- And a pair already saved the wrong way round comes good on READ, not only after another drag --
  -- which is what heals a profile that crossed them before this rule existed.
  NE.db.worldmap.canvasW, NE.db.worldmap.canvasWMax = 1100, 600
  WM.SetMaximized(true, false)
  local healedMax = WM.CurrentCanvasWidth()
  WM.SetMaximized(false, false)
  ok(healedMax >= WM.CurrentCanvasWidth(),
     "a crossed pair saved by an older build reads back in the right order")

  NE.db.worldmap.canvasWMax = nil
  WM.SetCanvasWidth(nil)
end

-- A width dragged out to the very edge is still not the MODE, and the button says so rather than
-- offering a minimize that would take the window somewhere it was never in.
WM.SetCanvasWidth(100000)
ok(not WM.maximized, "a window dragged to the widest available size is not in maximize mode")
eq(tooltipNow(), "Maximize", "and the button offers to maximize, which is what clicking will do")
mm:Fire("OnClick")
ok(WM.maximized, "as it does")
mm:Fire("OnClick")
ok(not WM.maximized, "and back")

WM.SetMaximized(false, false)
NE.db.worldmap.restoreW = nil
WM.SetCanvasWidth(nil)
P.SetShown(false)          -- left as it was found; the next section starts from a closed panel
GameTooltip.SetText = realSetText

-- ── the side panel ──────────────────────────────────────────────────────────

print("== side panel ==")
eq(P.PanelWidth(), 0, "a hidden panel claims no width")
P.SetShown(true)
eq(P.PanelWidth(), PANEL_W, "an open panel claims its width")
eq(WMF:GetWidth(), FRAME_W + PANEL_W, "the WINDOW widens by exactly that much")
near(WM.canvasScale, expectScale, "and the MAP keeps its own size — the panel does not squeeze it")
eq(WM.sideToggle.chevron._atlas, "questcollapse-hide-up",
   "the toggle wears retail's chevron, showing the action that CLOSES the open panel")
-- The breadcrumb spans the title/canvas spacer, so the spacer's right edge has to stop at the MAP
-- rather than at the window -- otherwise the trail runs on across the panel's search box and cog.
local spacerW = WM.spacer:GetWidth()
eq(spacerW, FRAME_W - INSET_L - INSET_R, "the title band stops at the map, not at the panel")
P.SetShown(false)
eq(WM.sideToggle.chevron._atlas, "questcollapse-show-up",
   "and flips to the one that re-opens it when the panel is closed")
eq(WMF:GetWidth(), FRAME_W, "closing it narrows the window back")

-- THE SMALL WINDOW OPENS WITHOUT THE PANEL; THE MAXIMIZED ONE WITH IT. Each mode remembers its own
-- answer, so an override sticks for that mode and leaves the other alone.
do
  NE.db.worldmap.questPanel, NE.db.worldmap.questPanelMax = nil, nil
  eq(P.ShownFor(false), false, "the mini window hides the quest log by default")
  eq(P.ShownFor(true),  true,  "and the maximized one shows it")

  WM.SetMaximized(false, false)
  ok(not P.shown, "so minimizing closes it")
  ok(WM.sideToggle:IsShown(), "with the toggle on screen to open it anyway")
  WM.SetMaximized(true, false)
  ok(P.shown, "and maximizing brings it back")

  -- An override is per mode, and survives switching away and back.
  WM.SetMaximized(true, false)
  P.SetShown(false)
  eq(NE.db.worldmap.questPanelMax, false, "closing it while maximized is remembered for that mode")
  WM.SetMaximized(false, false)
  WM.SetMaximized(true, false)
  ok(not P.shown, "and is still in force on the next maximize")

  WM.SetMaximized(false, false)
  P.SetShown(true)
  eq(NE.db.worldmap.questPanel, true, "opening it in the small window is remembered separately")
  WM.SetMaximized(true, false)
  ok(not P.shown, "without disturbing the maximized mode's own answer")

  NE.db.worldmap.questPanel, NE.db.worldmap.questPanelMax = nil, nil
  WM.SetMaximized(false, false)
end

-- THE PANEL IS NEVER TAKEN AWAY WITHOUT A WAY BACK. It used to be force-closed on maximize, copied
-- from retail -- where maximizing means fullscreen and the map wants the room -- and the toggle was
-- hidden there too, so the panel and the only control that could restore it disappeared together.
--
-- Now each mode carries its own answer and the toggle is always on screen, so whichever mode you are
-- in, the panel is one click away in either direction.
WM.SetMaximized(true, false)
P.SetShown(true)
eq(P.PanelWidth(), PANEL_W, "the panel can be open on the maximized map")
ok(WM.sideToggle:IsShown(), "with the toggle reachable to close it")
P.SetShown(false)
eq(P.PanelWidth(), 0, "closing it while maximized works normally")
ok(WM.sideToggle:IsShown(), "and the toggle is still there to open it again")
P.SetShown(true)
WM.SetMaximized(false, false)
P.SetShown(true)
eq(P.PanelWidth(), PANEL_W, "and the windowed map can have it open too")

-- ── the breadcrumb ──────────────────────────────────────────────────────────

print("== breadcrumb ==")
ok(WM.navbar ~= nil, "the navbar is built")
local crumbs = WM.navbar.crumbs
eq(crumbs[1].text:GetText(), "World", "crumb 1 is the world view")
eq(crumbs[2].text:GetText(), "Kalimdor", "crumb 2 is the current continent")
eq(crumbs[3].text:GetText(), "Ashenvale", "crumb 3 is the current zone")
ok(crumbs[3]._isLast, "the deepest crumb is marked current")
ok(not crumbs[1].endcap:IsShown(),
   "Home carries no separate connector -- its chevron has the notch built in")
ok(crumbs[2].endcap:IsShown(), "every other crumb does")
-- Chained flush, not spaced: the overhanging connector lands on the NEXT crumb's left padding, and
-- spacing them apart would draw it across a gap instead.
local _, rel = crumbs[3]:GetPoint(1)
eq(rel, crumbs[2], "each crumb anchors flush to the one before it")
-- Descending levels, leftmost highest, so each endcap draws OVER the crumb that follows it.
ok(crumbs[1]:GetFrameLevel() > crumbs[2]:GetFrameLevel(),
   "frame levels descend left to right, so the connectors interlock without a seam")
ok(crumbs[2].arrow:IsShown(), "the continent crumb has a dropdown (its zones)")
-- Home carries one too (the continent list), and it is the only crumb that is BOTH Home and
-- arrow-bearing -- so it is the only one that can catch a padding rule that treats those as one
-- three-way choice. The ▾ landed on top of the word "World".
ok(crumbs[1].arrow:IsShown(), "Home carries one as well -- the continent list")
local homeTextW = crumbs[1].text:GetStringWidth()
local plainHome = NE.navbar.CrumbWidth(true, false, homeTextW)
ok(crumbs[1]:GetWidth() > plainHome,
   "so Home is widened to make room for it, not sized as if it had none")

-- The second in-game fault: every crumb reported shown, sized and textured, and not one was on
-- screen, because nothing lifted them above the bar's own full-width OVERLAY sheen.
local barLevel = WM.navbar:GetFrameLevel()
ok(crumbs[1]:GetFrameLevel() > barLevel,
   "crumbs sit ABOVE the bar's own regions, not on the same level as them")
ok(crumbs[2].arrow:GetFrameLevel() > crumbs[2]:GetFrameLevel(),
   "and a crumb's dropdown arrow sits above the crumb")
ok(WM.navbar.sheen:GetDrawLayer() ~= "OVERLAY",
   "the bar's sheen is off the topmost layer too (belt to that brace)")
ok(not crumbs[3].arrow:IsShown(), "the zone crumb has none")

-- The backing plate is sized from the window's own model, not from the bar's anchored rect. An
-- anchored rect lags a resize by a layout pass on this client, so measuring it left the plate at the
-- PREVIOUS window's width every time the map changed size -- running out past the right edge after
-- minimising, and stopping short of it after maximising.
local function plateWidth() return WM.navbar.bg and WM.navbar.bg:GetWidth() or 0 end
local function barShouldBe()
  -- canvas width, less the bar's own left and right insets
  return math.floor(WM.CurrentCanvasWidth() + 0.5) - 59 - 10
end
near(plateWidth(), barShouldBe(), "the plate matches the window at its default size", 1)

-- Grow, then shrink, WITHOUT letting the stub resolve the bar's anchors in between -- which is
-- exactly the state the client is in on the pass right after a resize.
WM.SetCanvasWidth(900)
near(plateWidth(), barShouldBe(), "and still matches after the window grows", 1)
WM.SetCanvasWidth(500)
near(plateWidth(), barShouldBe(), "and after it shrinks -- no stale band left over", 1)
ok(plateWidth() < 900, "the plate is not left at the wider window's size")

-- ...and the assertions above only prove that because of THIS. The stub resolves anchored rects
-- synchronously, so a measured width is always fresh in it and the ordering inside availableWidth
-- cannot be told apart -- a mutation check said so. The client does not: on the pass right after a
-- resize the bar's rect still reports the width it had before. Freeze the measurement at a stale
-- value and the plate must still follow the window.
local realBarGetWidth = WM.navbar.GetWidth
WM.navbar.GetWidth = function() return 677 end     -- what the rect reported before the resize
WM.SetCanvasWidth(500)
near(plateWidth(), barShouldBe(),
     "the plate follows the window even while the bar's own rect still reports the old width", 1)
ok(plateWidth() < 600, "rather than the stale rect it would have measured")
WM.navbar.GetWidth = realBarGetWidth
WM.SetCanvasWidth(nil)

-- The fault the first in-game run showed: the bar is pinned left+right into the spacer and has
-- no explicit width, and the client does not resolve an anchored rect until its next layout
-- pass. The first refresh therefore asked a frame born microseconds ago how wide it was and got
-- 0. The old code returned there, and the breadcrumb stayed empty for the session.
local realGetWidth = WM.navbar.GetWidth
WM.navbar.GetWidth = function() return 0 end
-- Clear the last good result FIRST. Without this the assertion below is satisfied by the
-- trail depth left over from the previous refresh, and it passes whether the fallback works
-- or not -- which is exactly what a mutation check caught it doing.
WM.navbar._trailDepth = nil
WM.navbar._retried = nil
WM.RefreshNavBar()
runTimers()
WM.navbar.GetWidth = realGetWidth
eq(WM.navbar._trailDepth, 3,
   "an unresolved bar width falls back to the spacer rather than giving up on the trail")
ok(crumbs[2]:IsShown(), "and the crumbs are actually shown")

-- Clicking a crumb navigates -- and tells the neighbour that draws on our canvas.
zoomCalls = {}
local redrawsBefore = mmmRedraws
crumbs[2]:Fire("OnClick")
ok(mmmRedraws > redrawsBefore,
   "moving the map tells ModernMapMarkers to redraw, or it leaves the last zone's pins behind")
eq(zoomCalls[1] and zoomCalls[1][1], 2, "clicking the continent crumb zooms to that continent")
eq(zoomCalls[1] and zoomCalls[1][2], nil, "with no zone")

-- Index 0 is 'no selection', not an index.
curContinent, curZone = 0, 0
WM.RefreshNavBar()
eq(WM.navbar._trailDepth, 1, "on the world view the trail is just Home")
curContinent, curZone = 2, 1
WM.RefreshNavBar()
eq(WM.navbar._trailDepth, 3, "and it comes back on a zone map")

-- Dungeon floors are native here, so they are one more crumb.
numFloorsHere, curFloor = 3, 2
WM.RefreshNavBar()
eq(WM.navbar._trailDepth, 4, "a multi-floor map adds a floor crumb")
eq(WM.navbar.crumbs[4].text:GetText(), "Floor 2", "labelled with the current floor")
ok(WM.navbar.crumbs[4].arrow:IsShown(), "and offering the other floors")
numFloorsHere, curFloor = 0, 0
WM.RefreshNavBar()
eq(WM.navbar._trailDepth, 3, "an ordinary zone has no floor crumb")

-- ── the zone label ──────────────────────────────────────────────────────────

print("== zone label ==")
ok(WorldMapFrameAreaLabel._shadowOffset, "the zone label gets a shadow so it reads over map art")
eq(WorldMapFrameAreaLabel._size, 32, "at retail's size")
ok(WorldMapFrameAreaDescription._shadowOffset, "and so does the description under it")

-- ── the quest list ──────────────────────────────────────────────────────────

print("== quest list ==")
local list = P.BuildList(nil)
eq(#list, 6, "the flat list is headers and quests interleaved, as the client serves them")
eq(list[1].kind, "header", "entry 1 is a zone header")
eq(list[2].kind, "quest", "entry 2 is a quest")
eq(list[3].complete, true, "a complete quest is flagged")
eq(list[3].daily, true, "and a daily is flagged")

local sel = P.BuildList(2)
eq(#sel, 8, "selecting a quest adds ONLY its own objectives")
eq(sel[3].kind, "objective", "which follow it directly")
eq(sel[3].finished, true, "with their finished state carried through")

eq(P.QuestIDAt(2), 6383, "the quest ID is recovered from the link (the client's title call has none)")
eq(P.QuestIDAt(1), nil, "a header has no link and so no ID")

-- ── fact 3: the blob is protected ───────────────────────────────────────────

print("== blob (protected in combat) ==")
blobDraws = {}
P.SelectQuest(2)
eq(#blobDraws, 1, "selecting a quest draws its blob")
eq(blobDraws[1].id, 6383, "for the right quest")
eq(blobDraws[1].show, true, "showing it")
eq(selectedEntry, 2, "and the client's own quest cursor is moved first")

blobDraws = {}
inCombat = true
P.SelectQuest(4)
eq(#blobDraws, 0, "in combat NO blob call is made — DrawQuestBlob is protected and would raise")
flushCombat()

-- ── tracking ────────────────────────────────────────────────────────────────

print("== tracking ==")
watched = {}
ok(not P.IsTracked(2), "a quest starts untracked")
P.ToggleTrack(2)
ok(P.IsTracked(2), "toggling tracks it")
P.ToggleTrack(2)
ok(not P.IsTracked(2), "toggling again untracks it")

-- ── filtering ───────────────────────────────────────────────────────────────

print("== filtering ==")
P.SetShown(true)
P.Deselect()
P.filter = nil
P.Refresh()
local function shownRowTexts()
  local out = {}
  local i = 1
  while true do
    local body = P.frame.content
    local r = body and body._children and body._children[i]
    if not r then break end
    if r:IsShown() then out[#out + 1] = r.text:GetText() end
    i = i + 1
  end
  return out
end
local all = shownRowTexts()
eq(#all, 6, "with no filter every row is shown")

P.filter = "pilot"
P.Refresh()
local filtered = shownRowTexts()
eq(#filtered, 2, "filtering to one quest leaves that quest and its header")
eq(filtered[1], "Ashenvale", "the surviving header is kept")
ok(filtered[2]:find("Lost Pilot") ~= nil, "along with the matching quest")

P.filter = "zzzz"
P.Refresh()
eq(#shownRowTexts(), 0, "a filter matching nothing empties the list, headers included")
P.filter = nil
P.Refresh()

-- ── the detail pane ─────────────────────────────────────────────────────────

print("== detail pane ==")
ok(P.detail ~= nil, "the detail pane is built")
P.SelectQuest(2)
ok(P.detailShown, "selecting a quest swaps the list for the detail pane")
ok(not P.frame.scroll:IsShown(), "the list is hidden while the detail is up")
eq(P.detail.title:GetText(), "The Lost Pilot", "the detail shows the quest title")
eq(P.detail.descText:GetText(), "Find the pilot.", "and its description")
eq(P.detail.objText:GetText(), "Speak to the pilot.", "and its objective summary")
ok(P.detail.objLines[1]:GetText():find("Pilot found") ~= nil, "with the live objective lines under it")
ok(#P.detail.choicePool >= 2, "reward CHOICES get their own buttons")
eq(P.detail.choicePool[1]._kind, "choice", "tagged as choices for the client's own tooltip call")
eq(P.detail.rewardPool[1]._kind, "reward", "and rewards as rewards")
ok(P.detail.moneyText:GetText():find("12345") ~= nil, "money is shown")
ok(P.detail.moneyText:GetText():find("500") ~= nil, "and XP")

P.detail.back:Fire("OnClick")
ok(not P.detailShown, "Back returns to the list")
ok(P.frame.scroll:IsShown(), "and the list is visible again")

-- ── geometry defers out of combat ───────────────────────────────────────────

print("== combat deferral ==")
inCombat = true
local widthBefore = WMF:GetWidth()
WM.SetMaximized(true, false)
eq(WMF:GetWidth(), widthBefore, "no geometry is written in combat (the blob frame is protected)")
flushCombat()
ok(WMF:GetWidth() > widthBefore, "and it lands the moment combat ends")

-- ── resizing ──────────────────────────────────────────────────────
--
-- The window is described by ONE number -- the canvas width -- so that no drag can ever produce a
-- shape the map does not fill. These assertions are that invariant, plus the two ways the number
-- can be set (dragged, or reset) and the one time it must not be written at all (mid-drag).

print("== resizing ==")
P.SetShown(false)
WM.SetMaximized(false, false)
WM.SetCanvasWidth(nil)

ok(not WMF._resizable,
   "the client's own sizing machinery is deliberately NOT used -- it drags two edges independently")
local grip = WM.sizeGrip
ok(grip ~= nil, "there is a resize grip")
ok(grip:GetFrameLevel() > WMF._neBorder._neTitleBand:GetFrameLevel(),
   "and it outranks the chrome, like the other corner controls")

-- The invariant: whatever the width, the window is always the shape the map fills exactly.
local function assertNoLetterbox(what)
  local dw, dh = 1002, 668
  local cw = WMF:GetWidth() - INSET_L - INSET_R - P.PanelWidth()
  local ch = WMF:GetHeight() - SPACER_H - INSET_B
  near(cw / ch, dw / dh, what, 0.01)
end
-- Start this section from a known state. The quest panel's open/closed answer is now remembered PER
-- MODE -- the small window defaults to closed, the maximized one to open -- so the sections above,
-- which switch modes, leave it wherever the last mode they used wanted it. These assertions measure
-- the WINDOW, and the panel adds its width to that.
WM.SetMaximized(false, false)
WM.SetCanvasWidth(nil)
P.SetShown(false)

assertNoLetterbox("at the default size the canvas matches the map's aspect")

-- Dragging the corner. The window is NOT handed to the client's own sizing machinery -- that drags
-- two edges independently and can put the frame in a shape the map does not fill, which is what it
-- did: the window stretched free of the map and only snapped back on release. The grip drives the
-- size itself from the one canvas width, so the invariant holds on every frame of the drag.
local widthBefore = WMF:GetWidth()
local scaleBefore = WM.canvasScale

-- Park the window at a known origin so the cursor maths has something to measure against.
WMF:ClearAllPoints()
WMF:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 100, 700)

-- The width the cursor is asking for, worked out the long way: convert the cursor into the frame's
-- own coordinate space, measure both axes, take the tighter. Asserting against this catches the two
-- mistakes that leave the aspect correct and the SIZE wrong -- forgetting the scale conversion, and
-- taking the width without checking the height.
local function expectedCanvasW(cx, cy)
  local sc = WMF:GetEffectiveScale()
  local byW = (cx / sc - WMF:GetLeft()) - INSET_L - INSET_R - P.PanelWidth()
  local byH = ((WMF:GetTop() - cy / sc) - SPACER_H - INSET_B) * (1002 / 668)
  return math.min(byW, byH)
end
ok(WMF:GetEffectiveScale() ~= 1,
   "the window is pixel-pinned, so cursor coordinates need converting into its space")

-- Anchored CENTER at a known screen position, so the drag's TOPLEFT pin is something the test can
-- observe rather than something it set up itself.
WMF._left, WMF._top = 100, 700
WMF:ClearAllPoints()
WMF:SetPoint("CENTER", UIParent, "CENTER", 0, 0)

mouseHeld = true
grip:Fire("OnMouseDown", "LeftButton")
ok(WM.sizing, "mouse-down starts a drag")
eq((pointOf(WMF)), "TOPLEFT",
   "the window is re-pinned by its TOPLEFT, so it grows right and down under the cursor")
ok(WM.dragCanvasW ~= nil, "and the drag carries its own canvas width, not a saved one")
ok(WM.dragOrigin ~= nil and WM.dragOrigin.left == 100,
   "and the origin it measures against is captured ONCE, at mouse-down")
ok(not WMF._clamped, "screen clamping is off for the duration, so the frame cannot be shoved")

-- Pull the corner out and down. Deliberately to a point whose width and height do NOT agree: the
-- tighter fit has to win, and the window must not adopt the loose one even for one frame.
cursorX, cursorY = 700, 90
grip:Fire("OnUpdate")
ok(WM.canvasScale ~= scaleBefore, "the map re-scales live, so it tracks the drag")
assertNoLetterbox("and the window holds the map's aspect DURING the drag, not just after it")
near(WM.CurrentCanvasWidth(), WM.ClampCanvasWidth(expectedCanvasW(700, 90)),
     "at the width the cursor is actually asking for", 0.5)
local midWidth = WMF:GetWidth()
ok(midWidth > widthBefore, "the window has grown")

-- Keep dragging. Every intermediate frame has to hold the invariant too, not just the first.
cursorX, cursorY = 900, 60
grip:Fire("OnUpdate")
assertNoLetterbox("still holding it several frames in")
ok(WMF:GetWidth() > midWidth, "and still following the cursor")
near(WM.CurrentCanvasWidth(), WM.ClampCanvasWidth(expectedCanvasW(900, 60)),
     "still at the width the cursor asks for", 0.5)

-- Drag back in.
-- Pulled WIDE but SHORT: the height is now the tighter constraint, and the window must follow it
-- down rather than adopting the loose width.
cursorX, cursorY = 1500, 400
grip:Fire("OnUpdate")
assertNoLetterbox("and holding it while the height becomes the constraint")
near(WM.CurrentCanvasWidth(), WM.ClampCanvasWidth(expectedCanvasW(1500, 400)),
     "taking the TIGHTER of the two fits, not the width it was dragged to", 0.5)
ok(WMF:GetWidth() < midWidth, "so a wide-but-short drag narrows the window")

-- THE RUNAWAY. The window is clamped to the screen, so once it grows past an edge the clamp SHIFTS
-- it. Measuring against the frame's LIVE rect closes the loop: a shifted frame looks further from
-- the cursor, so the window grows, so it clamps harder -- and a few frames later it has run all the
-- way to the maximum. Shove the frame mid-drag and the requested width must not care.
-- Park the cursor somewhere the answer sits comfortably between the minimum and the screen cap:
-- shove the origin while the result is clamped at either end and BOTH readings come out the same,
-- which makes the assertion pass whether the fix is present or not. (A mutation check said so.)
cursorX, cursorY = 900, 200
grip:Fire("OnUpdate")
local steadyWidth = WM.CurrentCanvasWidth()
ok(steadyWidth > 420 and steadyWidth < WM.ClampCanvasWidth(99999) - 1,
   "the requested width is off both clamps, so a shove would actually show")
WMF._left, WMF._top = 40, 900          -- as a screen clamp would move it
WMF:ClearAllPoints()
WMF:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", 40, 900)
grip:Fire("OnUpdate")
near(WM.CurrentCanvasWidth(), steadyWidth,
     "the window moving mid-drag does not change the size the cursor is asking for", 0.5)
grip:Fire("OnUpdate")
near(WM.CurrentCanvasWidth(), steadyWidth, "and it does not creep frame on frame after that", 0.5)

mouseHeld = false
grip:Fire("OnMouseUp")
ok(not WM.sizing, "mouse-up ends the drag")
eq(WM.dragCanvasW, nil, "and the transient width is handed over rather than left behind")
eq(WM.dragOrigin, nil, "the captured origin is released with it")
ok(WMF._clamped, "and screen clamping comes back on")
assertNoLetterbox("the released window keeps the aspect")
ok(NE.db.worldmap.canvasW ~= nil, "and the size is persisted")

-- A click with no movement. There is no width to adopt, and passing that nil straight through would
-- read as "reset to default" and silently discard the size the player already had.
WM.SetCanvasWidth(760)
local kept = WM.CurrentCanvasWidth()
mouseHeld = true
grip:Fire("OnMouseDown", "LeftButton")
WM.dragCanvasW = nil                    -- as if no OnUpdate ever ran
mouseHeld = false
grip:Fire("OnMouseUp")
near(WM.CurrentCanvasWidth(), kept, "a click with no drag leaves the size alone", 0.5)

-- A release the button never saw. OnMouseUp is not guaranteed if the cursor left the grip, and a
-- drag that never ends leaves the window following the mouse for the rest of the session.
mouseHeld = true
grip:Fire("OnMouseDown", "LeftButton")
ok(WM.sizing, "a second drag starts")
mouseHeld = false
grip:Fire("OnUpdate")
ok(not WM.sizing, "and ends itself when the button turns out to have been released elsewhere")

-- The tighter of the two fits wins, so dragging either edge does something. An external resize to
-- wide-and-short is taken from the HEIGHT, and the width follows it down rather than letterboxing.
WMF:SetSize(1400, 400)
WM.AdoptDraggedSize()
assertNoLetterbox("a wide, short rect is taken from the height")
ok(WMF:GetWidth() < 1400, "so the window narrows to match rather than letterboxing")

-- Bounds.
WM.SetCanvasWidth(50)
ok(WM.CurrentCanvasWidth() >= 420, "a silly-small drag is clamped to a legible minimum")
WM.SetCanvasWidth(99999)
ok(WM.CurrentCanvasWidth() <= WM.ClampCanvasWidth(99999) + 0.01,
   "and a silly-large one is clamped to the screen")
-- Clamped on the way IN as well as on the way out. The read path clamps too, so an unclamped store
-- would still draw correctly -- but it would leave a nonsense number in the saved variables that
-- comes back the day someone plays at a bigger resolution.
ok(NE.db.worldmap.canvasW <= WM.ClampCanvasWidth(99999) + 0.01,
   "and what gets SAVED is the clamped value, not the raw drag")

-- Right-click resets.
WM.SetCanvasWidth(600)
grip:Fire("OnClick", "RightButton")
eq(NE.db.worldmap.canvasW, nil, "right-clicking the grip clears the stored size")
eq(WMF:GetWidth(), FRAME_W, "and the window returns to the size it opens at")

-- RESIZING ADJUSTS THE MODE YOU ARE IN; it does not leave it. Dragging used to clear the maximize
-- flag, so the button changed its label and its art every time the window was rescaled, and a
-- maximized window dragged to a size you liked could never be returned to -- maximize always went
-- back to the computed preset. Each mode owns a width instead.
WM.SetMaximized(true, true)
ok(WM.maximized, "maximized")
WM.SetCanvasWidth(1000)
ok(WM.maximized, "resizing does NOT drop out of the maximize mode")
eq(NE.db.worldmap.maximized, true, "so the button does not flip its label mid-drag")
near(WM.CurrentCanvasWidth(), 1000, "and the maximized mode adopts the dragged width", 0.5)

-- The two widths are independent: neither mode can overwrite the other's size.
WM.SetMaximized(false, true)
WM.SetCanvasWidth(700)
near(WM.CurrentCanvasWidth(), 700, "the windowed mode has its own width", 0.5)
WM.SetMaximized(true, true)
near(WM.CurrentCanvasWidth(), 1000, "and maximizing returns to the size IT was left at", 0.5)
WM.SetMaximized(false, true)
near(WM.CurrentCanvasWidth(), 700, "and back again, each remembering its own", 0.5)
NE.db.worldmap.canvasWMax = nil
WM.SetCanvasWidth(nil)
assertNoLetterbox("a custom size keeps the aspect too")

-- The side panel adds its width to the WINDOW without eating into the map.
local mapBefore = WM.canvasScale
P.SetShown(true)
near(WM.canvasScale, mapBefore, "opening the panel does not shrink the map")
assertNoLetterbox("and the canvas still matches the aspect with the panel open")
P.SetShown(false)
WM.SetCanvasWidth(nil)

-- ── interaction ───────────────────────────────────────────────────
--
-- The second in-game run turned up four dead controls: the cog did nothing, the search box
-- would not focus, no quest row could be clicked, and tracking could not be toggled. They
-- were ONE bug wearing four hats -- a mouse-enabled parent swallowing its own children's
-- clicks, because on this client a child does not reliably outrank its parent for input.
-- The maximize button had the same shape of fault from a different direction: the drag band
-- lay over it at the same level.

print("== window body ==")
-- An inset reads as an inset because of the CONTRAST with what surrounds it. This window painted
-- its stone at PC.BODY_TINT (0.32) where every other window that paints its own body uses full
-- brightness, so a normal-depth recess over it came out the same colour and the whole right-hand
-- side read as flat black.
local body = WMF._neBg
ok(body ~= nil, "the window paints a stone body")
ok(body._vertex and body._vertex[1] == 1,
   "at FULL brightness, like every other window in the set -- not tinted a second time")
ok(P.frame.inset ~= nil, "and the quest panel recesses into it")

print("== interaction ==")
P.SetShown(true)
P.Deselect()
local panelLevel = P.frame:GetFrameLevel()
ok(P.frame._mouse, "the panel eats clicks rather than passing them to the map behind")
ok(P.frame.search:GetFrameLevel() > panelLevel, "...so the search box outranks it")
ok(P.frame.cog:GetFrameLevel()    > panelLevel, "...and the cog does")
ok(P.frame.scroll:GetFrameLevel() > panelLevel, "...and the scroll frame does")
ok(P.frame.content:GetFrameLevel() > P.frame.scroll:GetFrameLevel(),
   "...and the scroll child outranks the scroll frame")

-- A row, and the checkbox on it.
local firstRow
for _, child in ipairs(P.frame.content._children or {}) do
  if child:IsShown() and child._index then firstRow = child; break end
end
ok(firstRow ~= nil, "the list built at least one row")
ok(firstRow:GetFrameLevel() > P.frame.content:GetFrameLevel(),
   "a quest row outranks the scroll child it sits on")
ok(firstRow.track:GetFrameLevel() > firstRow:GetFrameLevel(),
   "and its track checkbox outranks the row")

-- Clicking a QUEST row (not a header) selects it, all the way through to the detail pane.
local questRow
for _, child in ipairs(P.frame.content._children or {}) do
  if child:IsShown() and child._index == 2 then questRow = child; break end
end
ok(questRow ~= nil, "there is a row for quest index 2")
questRow:Fire("OnClick")
eq(P.selectedIndex, 2, "clicking the row selects that quest")
ok(P.detailShown, "and opens the detail pane")
P.Deselect()

-- Tracking, through the checkbox rather than the API.
watched = {}
P.Refresh()
for _, child in ipairs(P.frame.content._children or {}) do
  if child:IsShown() and child._index == 2 then questRow = child; break end
end
questRow.track:Fire("OnClick")
ok(P.IsTracked(2), "clicking the checkbox tracks the quest")
questRow.track:Fire("OnClick")
ok(not P.IsTracked(2), "and clicking it again untracks it")

-- The cog. The tree is asserted rather than the menu widget, so "opens nothing" and "opens a
-- menu whose entry does nothing" are different failures.
menuOpened = nil
P.frame.cog:Fire("OnClick")
ok(menuOpened ~= nil, "the cog opens a menu")
eq(menuOpened.anchor, P.frame.cog, "anchored to itself")
local entries = menuOpened.root.children
eq(#entries, 2, "with a title and one entry")
eq(entries[2].kind, "checkbox", "which is a checkbox")
-- The cog's state comes from the MODULE, not from poking the client's checkbox behind its back --
-- the checkbox is one of three things the switch has to move (state, the client's toggle, and a
-- re-place of the markers), and reading it alone was how it came to be off with nothing saying so.
WM.SetQuestObjectives(false)
ok(entries[2].isSelected() == false, "the cog reads the module's state")
entries[2].onClick()
ok(WorldMapQuestShowObjectives:GetChecked(), "and its click reaches the client's own checkbox")
ok(WM.QuestObjectivesShown(), "and the module's state with it")

-- The maximize button vs the drag band.
local band = WMF._neBorder._neTitleBand
ok(band._mouse, "the title band takes the mouse, so the window drags by its title bar")
ok(mm:GetFrameLevel() > band:GetFrameLevel(),
   "so the maximize button has to outrank it, or the band eats the hover")
ok(closeBtn:GetFrameLevel() > band:GetFrameLevel(), "and so does the close button")
local _, bandRel = findPoint(band, "TOPRIGHT")
eq(bandRel, mm, "and the band stops at the button rather than running under it")

-- ── dungeon maps ───────────────────────────────────────────────
--
-- This client renders instance floors perfectly well -- but only while the player is standing in the
-- instance. SetMapZoom has no dungeon entries, so there is no way to look at one from outside, and
-- that is the whole feature.

print("== dungeon maps ==")
local D = WM.dungeon
ok(D ~= nil, "the dungeon viewer is loaded")
ok(WM.dungeonFloors ~= nil, "with floor data generated from the client's own DungeonMap.dbc")

local list = D.List()
ok(#list > 30, "it knows a lot of dungeons  (" .. #list .. ")")
local hasAzeroth = false
for _, f in ipairs(list) do if f == "Azeroth" then hasAzeroth = true end end
ok(not hasAzeroth,
   "and the world map is NOT among them -- it has a floor row but picking it would draw the map on itself")
ok(D.Floors("BlackTemple") and #D.Floors("BlackTemple") == 7, "Black Temple has its seven floors")

-- Showing one. The stub resolves any texture path, so the underscored form wins -- which is the
-- form a multi-floor dungeon actually uses.
ok(not D.IsShowing(), "nothing is showing to begin with")
local redrawsBeforeDungeon = mmmRedraws
ok(D.Show("BlackTemple"), "showing a dungeon draws tiles")

-- THE STALE-TEXTURE TRAP. A path the client cannot find leaves the texture showing whatever it had
-- before -- and on a pooled tile, that is the LAST DUNGEON. Checking `GetTexture() ~= nil` therefore
-- reports every path on earth as existing, picks the wrong tile form, and puts the previous
-- dungeon's art on screen under the new dungeon's name.
_G._missingPaths = {}
for i = 1, 12 do
  _G._missingPaths[("interface\\worldmap\\scarletmonastery\\scarletmonastery1_%d"):format(i)] = true
  _G._missingPaths[("interface\\worldmap\\scarletmonastery\\scarletmonastery%d"):format(i)] = true
end
ok(not D.Show("ScarletMonastery"),
   "a dungeon whose art will not load reports failure instead of drawing the last one's")
ok(not D.IsShowing(), "and leaves no empty black plate over a perfectly good map")
eq(D.folder, nil, "and does not claim to be showing it")
_G._missingPaths = {}
ok(D.Show("BlackTemple"), "while one whose art IS there still draws")
ok(mmmRedraws > redrawsBeforeDungeon,
   "and tells the neighbour too -- its zone pins have no business on a dungeon floor")
ok(D.IsShowing(), "and the overlay is up")
eq(D.folder, "BlackTemple", "on the right dungeon")
eq(D.floor, 1, "starting at its first floor")
eq(D.tilesDrawn, 12, "as a full 4x3 grid of 256px tiles")
ok(D.frame:GetFrameLevel() > detail:GetFrameLevel(),
   "the overlay covers the canvas rather than sitting under it")
ok(D.frame._mouse, "and swallows clicks, so they do not fall through to the zone map")

-- The breadcrumb describes the DUNGEON while one is up, not the zone underneath.
local dTrail = WM.BuildNavTrail()
eq(#dTrail, 2, "the trail becomes World > <dungeon>")
eq(dTrail[2].name, "BlackTemple", "naming it")
ok(dTrail[2].listFunc ~= nil, "with its floors on the crumb")
eq(#dTrail[2].listFunc(), 7, "all seven of them")

D.Show("BlackTemple", 5)
eq(D.floor, 5, "picking a floor switches to it")

-- A floor number from the PREVIOUS dungeon is meaningless in the next one.
D.Show("Ahnkahet")
eq(D.floor, 1, "switching dungeons falls back to the new one's first floor")

-- Any ordinary navigation leaves the dungeon view.
dTrail = WM.BuildNavTrail()
dTrail[1].OnClick()
ok(not D.IsShowing(), "clicking Home dismisses the dungeon overlay")
local homeList = dTrail[1].listFunc()
local dungeonsEntry
for _, e in ipairs(homeList) do if e.hasArrow then dungeonsEntry = e end end
ok(dungeonsEntry ~= nil, "and Home's menu carries a Dungeons submenu -- the only way in")
ok(dungeonsEntry.menuList and #dungeonsEntry.menuList == #list, "listing every one of them")

-- ── fog of war ─────────────────────────────────────────────────
--
-- The whole feature is a difference: what the client reports discovered versus what the
-- store remembers. Everything below is about that gap being drawn, and drawn DIFFERENTLY.

print("== fog of war ==")
local FOG = WM.fog
ok(FOG ~= nil, "the fog module is loaded")
ok(FOG.enabled, "and armed")

-- The packing survives a round trip, including offsets big enough to reach the high bits.
local w, h, x, y = FOG._unpack(FOG._pack(300, 200, 100, 50))
eq(w, 300, "packed width round-trips")
eq(h, 200, "packed height round-trips")
eq(x, 100, "packed x offset round-trips")
eq(y, 50,  "packed y offset round-trips")

-- Harvest, from a map the client says has one real overlay and one junk record.
FOG.Refresh()
local bucket = FOG.OverlaysFor("Ashenvale")
ok(bucket.Astranaar ~= nil, "a discovered subzone is recorded")
eq(bucket.pixelfix, nil,
   "and the client's pixelfix spacer is NOT -- the store is permanent, so junk in it is forever")

-- Now the point of the whole thing: a subzone remembered from another character, which
-- THIS one has not discovered, is drawn anyway -- tinted, and a layer down.
bucket.Mystral = FOG._pack(256, 256, 400, 300)
FOG.Refresh()
local tinted, full = 0, 0
for i = 1, (NUM_WORLDMAP_OVERLAYS or 0) do
  local t = _G["WorldMapOverlay" .. i]
  if t and t:IsShown() then
    if t:GetDrawLayer() == "BORDER" then tinted = tinted + 1 else full = full + 1 end
  end
end
ok(full > 0,   "the explored subzone draws in full colour on ARTWORK")
ok(tinted > 0, "and the unexplored one draws on BORDER, under it")

-- The tint is actually applied, not merely the layer.
local tintedTex
for i = 1, (NUM_WORLDMAP_OVERLAYS or 0) do
  local t = _G["WorldMapOverlay" .. i]
  if t and t:IsShown() and t:GetDrawLayer() == "BORDER" then tintedTex = t; break end
end
ok(tintedTex ~= nil, "there is a tinted texture to inspect")
ok(tintedTex:GetAlpha() < 1, "it is semi-transparent")
ok(tintedTex._vertex and tintedTex._vertex[1] < 1, "and greyed rather than full colour")

-- A 300x200 overlay is a 2x1 grid of 256px files, and the right-hand column is cropped to
-- the next power of two -- which is the fiddly half of the layout and the easy half to get
-- silently wrong (it shows as a stretched smear, not an error).
local astranaarTiles = 0
for i = 1, (NUM_WORLDMAP_OVERLAYS or 0) do
  local t = _G["WorldMapOverlay" .. i]
  if t and t:IsShown() and (t:GetTexture() or ""):find("Astranaar", 1, true) then
    astranaarTiles = astranaarTiles + 1
  end
end
eq(astranaarTiles, 2, "a 300x200 overlay is drawn as two 256px pieces, not one")

-- Coverage: the seed and the harvest are reported apart, because they answer different questions.
local maps, subzones, seedMaps, seedSubs = FOG.Coverage()
ok(maps >= 1, "the store reports the maps it has harvested")
ok(subzones >= 2, "and the subzones in them")
ok(seedMaps > 40, "and the generated seed reports its own, far more of them  (" .. seedMaps .. " maps)")
ok(seedSubs > 500, "across hundreds of subzones  (" .. seedSubs .. ")")

-- THE POINT OF THE SEED: a map nothing has ever been harvested for still has overlays to draw,
-- because the client's own WorldMapOverlay.dbc knew about them. Without it the module can only
-- redraw what it has watched somebody discover.
local seededMap
for name in pairs(NE.worldmap.overlaySeed) do
  if not (NE.db.worldmap.overlays or {})[name] then seededMap = name; break end
end
ok(seededMap ~= nil, "there is a map with seed data and no harvest")
local known = FOG.KnownFor(seededMap)
local n = 0
for _ in pairs(known) do n = n + 1 end
ok(n > 0, "and it still knows overlays for it  (" .. n .. " on " .. tostring(seededMap) .. ")")

-- ...and a seed-only map actually DRAWS. Rendering from the harvest alone still draws everything
-- the earlier assertions look at, because those overlays were harvested -- so only a map with seed
-- data and nothing harvested can tell the union apart from the harvest. (A mutation check caught
-- this one being untested.)
local seedOnly, seedOnlyCount
for name, subs in pairs(NE.worldmap.overlaySeed) do
  if not (NE.db.worldmap.overlays or {})[name] then
    local c = 0
    for _ in pairs(subs) do c = c + 1 end
    if c > 0 then seedOnly, seedOnlyCount = name, c; break end
  end
end
ok(seedOnly ~= nil, "there is a map with seed data and nothing harvested")
currentMapFile = seedOnly
liveOverlays = {}                       -- this character has discovered nothing here
FOG.Refresh()
local drawnHere = 0
for i = 1, (NUM_WORLDMAP_OVERLAYS or 0) do
  local t = _G["WorldMapOverlay" .. i]
  if t and t:IsShown() and t:GetDrawLayer() == "BORDER" then drawnHere = drawnHere + 1 end
end
ok(drawnHere > 0,
   "a map this character has never explored still draws its overlays, tinted  (" .. drawnHere .. ")")
currentMapFile = "Ashenvale"
liveOverlays = { { "Astranaar", 300, 200, 100, 50 }, { "pixelfix", 1, 1, 0, 0 } }
FOG.Refresh()

-- The harvest wins on conflict: observed beats read-off-a-file.
local anyMap = next(NE.worldmap.overlaySeed)
local anySub = next(NE.worldmap.overlaySeed[anyMap])
FOG.OverlaysFor(anyMap)[anySub] = 12345
eq(FOG.KnownFor(anyMap)[anySub], 12345, "a harvested overlay overrides the seeded one")

-- Turning it off hands the client its own overlays back.
FOG.enabled = false
FOG.Restore()
local anyTinted = false
for i = 1, (NUM_WORLDMAP_OVERLAYS or 0) do
  local t = _G["WorldMapOverlay" .. i]
  if t and t:GetDrawLayer() == "BORDER" then anyTinted = true end
end
ok(not anyTinted, "disabling it puts every overlay back on ARTWORK at full colour")
FOG.enabled = true

-- ── the client's quest markers ───────────────────────────────────
--
-- Every quest POI and objective blob on this client is gated behind ONE checkbox. The chrome
-- squelches that checkbox -- correctly, it is a stock tickbox floating over our layout and the cog
-- offers the same switch -- but squelching the widget and never touching its STATE left the client
-- deciding not to draw quest markers at all, and nothing said so.

-- ── the canvas tooltip ────────────────────────────────────────────────────────────────
--
-- Every quest pin and landmark on the map uses WorldMapTooltip, and it came up with its text and
-- border but no BACKGROUND -- the map showing straight through, which over parchment is close to
-- unreadable. It is a child of the map window, so it also inherits a strata we have changed.

print("== canvas tooltip ==")
local tt = _G.WorldMapTooltip
ok(tt:GetBackdrop() ~= nil, "the tooltip has a backdrop")
ok(tt:GetBackdrop() and tt:GetBackdrop().bgFile ~= nil, "with a background file, not just an edge")
local _, _, _, ttAlpha = tt:GetBackdropColor()
ok(ttAlpha and ttAlpha > 0.1, "and it is actually opaque  (alpha " .. tostring(ttAlpha) .. ")")
eq(tt._strata, "TOOLTIP",
   "lifted to TOOLTIP strata -- as a child of the map it would otherwise inherit the window's")

-- REPAIRED, not imposed: a skin that has deliberately styled this tooltip keeps its styling.
tt._neTooltipRepaired = nil
tt:SetBackdrop({ bgFile = "Custom", edgeFile = "Custom" })
tt:SetBackdropColor(0.2, 0.3, 0.4, 0.8)
WM.RepairTooltip()
eq(tt:GetBackdrop().bgFile, "Custom", "an existing backdrop is left alone")
local cr, _, _, ca = tt:GetBackdropColor()
near(cr, 0.2, "and so is its colour", 0.001)
near(ca, 0.8, "and its alpha", 0.001)


print("== quest markers ==")
ok(not WorldMapQuestShowObjectives:IsShown(), "the client's own checkbox is hidden")
ok(bootQuestChecked, "but CHECKED at boot -- hiding the widget must not turn the feature off")
ok(WM.QuestObjectivesShown(), "and the module agrees the markers are on")
-- ASSERT THE STATE, NOT THE MECHANISM. This used to require the client's toggle to have been called,
-- which pinned HOW the state was applied rather than THAT it was -- and the how was the bug: that
-- function TOGGLES, so asking for the value already held flipped it. Driven from the filter menu,
-- which asks for an explicit value each time, the switch appeared to do nothing.
eq(GetCVarBool("questPOI"), true, "boot left the client's own state switched on")

-- The bug itself: setting the SAME value twice must be idempotent.
WM.SetQuestObjectives(true)
eq(WM.QuestObjectivesShown(), true, "asking for ON when already ON leaves it on")
eq(GetCVarBool("questPOI"), true, "and does not flip the client's state underneath it")
WM.SetQuestObjectives(true)
eq(GetCVarBool("questPOI"), true, "however many times it is asked")
WM.SetQuestObjectives(false)
eq(GetCVarBool("questPOI"), false, "and OFF still means off")
WM.SetQuestObjectives(false)
eq(GetCVarBool("questPOI"), false, "idempotently in that direction too")
WM.SetQuestObjectives(true)
ok(bootUpdateCalls > 0, "and re-placed the markers afterwards")

-- The cog drives the same switch, so the menu and the map cannot disagree.
menuOpened = nil
P.frame.cog:Fire("OnClick")
local cogEntry = menuOpened.root.children[2]
ok(cogEntry.isSelected(), "the cog reads the live state")
local beforeToggle, beforeUpdate = questToggleCalls, questUpdateCalls
cogEntry.onClick()
ok(not WM.QuestObjectivesShown(), "clicking it turns the markers off")
ok(not WorldMapQuestShowObjectives:GetChecked(), "through the client's own checkbox")
-- The CVar is the state; the toggle function is only one way of reaching it, and calling it blindly
-- was the bug. So what is asserted is that the client's own state MOVED, not which lever moved it.
eq(GetCVarBool("questPOI"), false, "and the client's own state follows")
ok(questUpdateCalls > beforeUpdate, "and re-placing the markers")
eq(NE.db.worldmap.questObjectives, false, "and the choice is persisted")
cogEntry.onClick()
ok(WM.QuestObjectivesShown(), "and back on again")

-- ── quest panel art ────────────────────────────────────────────
--
-- The panel used to draw a tinted recess and stock Blizzard checkboxes because there was no art for
-- anything else. There is now. These assertions are that each piece REACHED a widget -- an atlas
-- that fails to resolve leaves the fallback in place silently, which is exactly the failure mode
-- this whole module keeps re-learning.

print("== quest panel art ==")
P.SetShown(true)
P.Deselect()
P.filter = nil
P.Refresh()

ok(P.frame.parchment ~= nil and P.frame.parchment:IsShown(),
   "the list sits on retail's parchment, not on a tinted hole in the window")
eq(P.frame.parchment._atlas, "questlog-main-background", "which is the sheet, not a flat colour")
ok(P.frame.fill ~= nil, "the flat fill survives as a wash over it")
ok(P.frame.cog._normal and P.frame.cog._normal._neAtlas == "questlog-icon-setting",
   "the cog is retail's, not the stock options gear")

-- Rows: a header wears the tab bar and a collapse glyph; a quest wears its type badge and a tick.
local headerRow, questRow2, dungeonRow
for _, child in ipairs(P.frame.content._children or {}) do
  if child:IsShown() and child._index then
    local e = P.BuildList(nil)[1]
    if child.tab and child.tab.pieces[1]:IsShown() then headerRow = headerRow or child end
    if child._index == 2 then questRow2 = child end
    if child._index == 4 then dungeonRow = child end   -- "Deep Ocean", the tagged one
  end
end
ok(headerRow ~= nil, "a zone header draws the tab bar")
eq(#headerRow.tab.pieces, 3,
   "as THREE pieces -- two fixed caps and a stretched middle, not one smeared texture")
ok(headerRow.tab.pieces[1]:GetWidth() == 18 and headerRow.tab.pieces[3]:GetWidth() == 18,
   "with the caps at their native 18px whatever the header's width")
ok(headerRow.tab.pieces[2]:GetWidth() > 18, "and the middle carrying the rest of it")
-- ...and each piece is a different CROP of the sheet. Sizing alone cannot tell a real 3-slice from
-- three copies of the whole texture stretched to different widths, which is the smeared look the
-- slicing exists to avoid.
local capL = { headerRow.tab.pieces[1]:GetTexCoord() }
local mid  = { headerRow.tab.pieces[2]:GetTexCoord() }
local capR = { headerRow.tab.pieces[3]:GetTexCoord() }
ok(capL[2] < mid[2] and mid[2] < capR[2],
   "each piece crops a different slice of the sheet, left to right")
ok(capL[1] ~= mid[1], "so the left cap is not just the whole texture squashed")
eq(headerRow.marker._atlas, "questlog-icon-shrink", "an expanded header shows the collapse glyph")

ok(questRow2 ~= nil, "there is a quest row")
ok(not (questRow2.tab and questRow2.tab.pieces[1]:IsShown()),
   "a quest row does NOT wear the header bar")
ok(questRow2.track._normal and questRow2.track._normal._neAtlas == "questlog-icon-ticksquare",
   "its tracking box is retail's tick-square")
ok(questRow2.track._checkedTex and questRow2.track._checkedTex._neAtlas == "questlog-icon-checkmark-yellow",
   "with retail's checkmark when ticked")
ok(questRow2.hover._atlas == "questlog-quest-glow-yellow",
   "and the row hover is the real glow, not a flat white tint")

-- The type badge is driven by the client's own LOCALISED tag constants, so it survives translation.
ok(dungeonRow ~= nil, "there is a quest tagged as a dungeon")
eq(dungeonRow.marker._atlas, "questlog-questtypeicon-dungeon", "which earns the dungeon badge")
ok(questRow2.marker == nil or not questRow2.marker:IsShown() or questRow2.marker._atlas ~= "questlog-questtypeicon-dungeon",
   "and an untagged quest does not")

-- ── the shared breadcrumb, from the OTHER side ───────────────────────────────
--
-- core/NavBar.lua exists because the widget was written twice. These assertions are the
-- reason it can stay written once: the Adventure Guide's trail (Home > Instance > Boss, with
-- the boss-jump dropdown on the middle crumb) has a different shape from the map's, and the
-- shared widget has to lay out both -- including the collapse, which the map has never yet
-- been narrow enough to trigger.

print("== shared navbar ==")
ok(NE.navbar and NE.navbar.Create, "core/NavBar.lua exposes the shared builder")
ok(NE.ej and NE.ej.BuildNavTrail, "the Adventure Guide is a consumer of it")

-- The journal's trail, built from its own state.
NE.ej.frame = { _currentInstance = { name = "Ulduar", encounters = {
  { name = "Flame Leviathan" }, { name = "Razorscale" } } },
  _currentBoss = { name = "Razorscale" } }
local ejTrail = NE.ej.BuildNavTrail()
eq(#ejTrail, 3, "Home > Instance > Boss")
eq(ejTrail[1].name, "Home", "entry 1 is Home")
eq(ejTrail[2].name, "Ulduar", "entry 2 is the instance")
ok(ejTrail[2].listFunc ~= nil, "which carries the boss-jump dropdown")
eq(#ejTrail[2].listFunc(), 2, "listing every boss in it")
eq(ejTrail[3].name, "Razorscale", "entry 3 is the boss")
ok(ejTrail[3].listFunc == nil, "and carries no dropdown of its own")

-- Drive the shared widget with that trail on a bar too narrow for it, which is what makes
-- the middle crumb collapse.
local host = CreateFrame("Frame", nil, UIParent)
host:SetSize(400, 100)
local shared = NE.navbar.Create(host, {
  name = "TestNavBar", height = 34, frameLevel = 10,
  trailFunc = function() return ejTrail end,
  widthFunc = function() return 150 end,
})
shared:Relayout()
eq(shared._trailDepth, 3, "the shared widget lays out the journal's trail")
ok(shared.crumbs[1]:IsShown(), "Home is shown")
ok(shared.crumbs[3]:IsShown(), "and so is the crumb you are actually on")
ok(shared.overflow ~= nil and shared.overflow:IsShown(),
   "with the middle crumb folded into the overflow badge")
ok(not shared.crumbs[2]:IsShown(), "which is to say: the middle crumb is hidden")
eq(#(shared.overflow._hidden or {}), 1, "and the badge lists exactly what it swallowed")
eq(shared.overflow._hidden[1].name, "Ulduar", "namely the instance crumb")

-- Home never folds, however tight it gets.
shared._neOpts.widthFunc = function() return 40 end
shared:Refresh()
ok(shared.crumbs[1]:IsShown(), "Home survives even a bar too small for anything")

-- ── the diagnostic ──────────────────────────────────────────────
--
-- Report-only, so the only thing worth asserting is that every section runs without throwing
-- on a live tree. A dump that errors halfway is worse than no dump: it stops at the section
-- before the one you needed.

print("== diagnostic ==")
ok(SlashCmdList.NEWORLDMAP ~= nil, "/neworldmap is registered")
chatLines = {}
local okDump, dumpErr = pcall(SlashCmdList.NEWORLDMAP, "")
ok(okDump, "the full dump runs without error  " .. (okDump and "" or tostring(dumpErr)))
ok(#chatLines > 20, "and prints a real report  (got " .. #chatLines .. " lines)")
local joined = table.concat(chatLines, chr10)
ok(joined:find("client thinks it is windowed", 1, true) ~= nil, "including the windowed-mode identity")
ok(joined:find("leftover classic art", 1, true) ~= nil, "and the leftover-art list")
for _, section in ipairs({ "mode", "canvas", "chrome", "navbar", "panel", "fog", "addons",
                           "art", "squelch", "leftover" }) do
  ok(pcall(SlashCmdList.NEWORLDMAP, section), "section " .. section .. " runs on its own")
end

-- ── result ──────────────────────────────────────────────────────────────────

print("")


print("== canvas zoom ==")

-- The wheel MAGNIFIES the canvas. It does not navigate and it does not resize the window -- both of
-- those were built and thrown away before the right feature was understood, so both are asserted
-- against here rather than merely commented about.
local CZ = WM.canvaszoom
local WZ = WM.wheel
ok(CZ ~= nil, "the magnifier loads")
ok(WZ ~= nil, "and the wheel that drives it")

CZ.Arm(); WZ.Arm()
WM.SetCanvasWidth(nil)
CZ.Reset()

local function putCursor(fracX, fracY)
  local vp = CZ.viewport
  local l, t = vp:GetLeft(), vp:GetTop()
  local w, h = vp:GetWidth(), vp:GetHeight()
  local sc = vp:GetEffectiveScale() or 1
  cursorX, cursorY = (l + w * fracX) * sc, (t - h * fracY) * sc
end
local function cursorOverMap() putCursor(0.5, 0.5) end
local function cursorOffMap()  putCursor(-2.0, 0.5) end

-- The canvas frames are ADOPTED into the clipping viewport, because nothing else on this client
-- clips. Without that the magnified map would spill straight over the chrome.
ok(CZ.viewport ~= nil and CZ.content ~= nil, "a viewport and a content frame are built")
eq(WorldMapDetailFrame:GetParent(), CZ.content, "the detail frame moves into the content frame")
eq(WorldMapButton:GetParent(), CZ.content, "so does the button")
eq(_G.WorldMapPOIFrame:GetParent(), WorldMapButton,
   "and WorldMapPOIFrame stays under the button, so every pin is carried along for free")

-- THE ONE FRAME THAT MUST NOT MOVE. WorldMapBlobFrame is protected: reparenting it risks taint and
-- is impossible in combat. It is squelched while zoomed instead, which is the agreed trade.
ok(_G.WorldMapBlobFrame:GetParent() ~= CZ.content,
   "the PROTECTED blob frame is never reparented")

cursorOverMap()
local w0, h0 = WMF:GetWidth(), WMF:GetHeight()
local content0 = CZ.content:GetWidth()
zoomCalls = {}
local c0, z0 = GetCurrentMapContinent(), GetCurrentMapZone()

ok(WZ.OnWheel(1), "wheel up magnifies")
ok(CZ.Level() > 1.0, "the zoom level rises")
ok(CZ.content:GetWidth() > content0, "the content frame grows past the viewport")
eq(WMF:GetWidth(), w0, "the WINDOW does not resize -- that is the corner grip's job, not the wheel's")
eq(WMF:GetHeight(), h0, "in either axis")
eq(#zoomCalls, 0, "and it never navigates: SetMapZoom is not called")
eq(GetCurrentMapContinent(), c0, "the continent is untouched")
eq(GetCurrentMapZone(), z0, "and so is the zone")

-- Magnifying past fit creates slack to pan into; at fit there is none.
local rx, ry = CZ.Range()
ok(rx > 0 and ry > 0, "magnifying creates scrollable slack in both axes")

-- The blob is ERASED, not hidden: a protected frame must not have its parent, scale or visibility
-- forced, and our own squelch refuses protected regions for that reason.
WORLDMAP_SETTINGS.selectedQuest = { questId = 42, completed = false }
blobDraws = {}
CZ.Reset(); CZ.Step(1)
ok(#blobDraws > 0, "magnifying touches the quest blob")
eq(blobDraws[#blobDraws].show, false, "erasing it, via the frame's own DrawQuestBlob")
eq(_G.WorldMapBlobFrame:GetParent() ~= CZ.content, true,
   "without ever reparenting the protected frame")

-- CURSOR-ANCHORED. Without this the map drifts toward its top-left corner and whatever you leaned in
-- to look at slides out from under the pointer -- which is the whole reason to zoom in the first
-- place. The map point under the cursor must not move.
CZ.Reset()
putCursor(0.75, 0.25)
local ax, ay = CZ.CursorInViewport()
local beforePoint = { x = CZ.scrollX + ax, y = CZ.scrollY + ay }
local lvl0 = CZ.Level()
CZ.Step(1)
local k = CZ.Level() / lvl0
near((CZ.scrollX + ax) / k, beforePoint.x,
     "the map point under the cursor stays put horizontally", 0.5)
near((CZ.scrollY + ay) / k, beforePoint.y,
     "and vertically -- the zoom is anchored on the cursor, not the corner", 0.5)

-- Panning is on the RIGHT button: left-click over the canvas belongs to the client.
CZ.Reset()
CZ.Step(1); CZ.Step(1)
ok(CZ.IsZoomed(), "zoomed in")
cursorOverMap()
ok(CZ.BeginPan(), "right-drag starts a pan")
local sx0 = CZ.scrollX
putCursor(0.30, 0.5)
CZ._PanUpdate()
ok(CZ.scrollX ~= sx0, "and dragging moves the view")
ok(CZ.EndPan(), "releasing ends it, reporting that the mouse moved")

-- THE CLIENT ALSO USES RIGHT-CLICK, to zoom out a level -- which is why the first version of this
-- threw you up to the continent map at the end of every pan. A drag that MOVED must swallow the
-- click that ends it; a right-click that did not move must still reach the client and zoom out.
ok(CZ.ShouldSwallowClick("RightButton"),
   "a right-click that ended a real drag is swallowed, so panning does not navigate")
ok(not CZ.ShouldSwallowClick("LeftButton"), "left-click is never swallowed")

-- WHERE THE SWALLOW HAS TO LAND. Wrapping the button's OnClick alone did not stop it: the map still
-- jumped a level at the end of every pan, because this build reaches the zoom-out through a path
-- that wrapper never saw. So the guard is on the FUNCTION, and that is what is asserted.
zoomOutCalls = 0
WorldMapZoomOutButton_OnClick()
eq(zoomOutCalls, 0, "the zoom-out that ends a real pan is swallowed at the function")
ok(not CZ.ShouldSwallowClick("RightButton"), "and the swallow is spent on that one call")

WorldMapZoomOutButton_OnClick()
eq(zoomOutCalls, 1, "the very next right-click zooms out normally again")

-- A right-click with no movement: still the client's, still zooms out.
CZ.BeginPan()
CZ._PanUpdate()
ok(not CZ.EndPan(), "a right-click that never moved is not a pan")
zoomOutCalls = 0
WorldMapZoomOutButton_OnClick()
eq(zoomOutCalls, 1, "so it reaches the client and still zooms out a level")

CZ.Reset()
ok(not CZ.BeginPan(), "at fit there is nothing to pan, so a right-drag does nothing")

-- Limits, and honest reporting at them.
CZ.Reset()
for _ = 1, 40 do CZ.Step(1) end
near(CZ.Level(), CZ.MAX_ZOOM, "zoom stops at its maximum", 0.001)
ok(not WZ.OnWheel(1), "and the wheel reports unhandled there rather than eating the input")
for _ = 1, 40 do CZ.Step(-1) end
near(CZ.Level(), CZ.MIN_ZOOM, "and at fit on the way back", 0.001)
ok(not WZ.OnWheel(-1), "reporting unhandled again")
eq(CZ.scrollX, 0, "with the pan dropped, so zooming back in returns to the middle")
eq(blobDraws[#blobDraws].show, true, "and the blob is redrawn at fit")
ok(hitTranslationCalls > 0, "after its hit translations are recalculated, as Mapster does")
WORLDMAP_SETTINGS.selectedQuest = nil

-- Zoom does not survive a map change: an offset measured against one map means nothing on another.
CZ.Step(1)
ok(CZ.IsZoomed(), "zoomed in again")
WM.OnMapChanged()
ok(not CZ.IsZoomed(), "changing map drops the zoom")

-- Inert where scrolling means something else.
CZ.Reset()
cursorOffMap()
ok(not WZ.OnWheel(1), "the wheel does nothing with the cursor off the canvas")
eq(CZ.Level(), 1.0, "so scrolling the quest list does not magnify the map")

cursorOverMap()
WZ.SetEnabled(false)
ok(not WZ.OnWheel(1), "and nothing at all when the feature is switched off")
eq(CZ.Level(), 1.0, "leaving the zoom untouched")
WZ.SetEnabled(true)
CZ.Reset()

print("== pin filter ==")

-- The filter MECHANISM: a registry of categories, the button the Map-Filter-Button art was shipped
-- for, and persistence. Deliberately not dungeon/raid pin data -- this client has no trustworthy
-- source for that (AreaPOI.dbc: 738 rows, one instance name), and the registry is what lets it slot
-- in later without touching the module.
PF = WM.filter
ok(PF ~= nil, "the filter module loads")
PF.Arm()

ok(PF.button ~= nil, "the filter button is built")
do
  local _, rel = pointOf(PF.button)
  ok(rel == _G.NE_WorldMapViewport or rel == _G.WorldMapDetailFrame,
     "anchored to the canvas rect, so it follows every resize")
  eq(PF.button:GetParent(), WMF,
     "but PARENTED to the window -- a child of the viewport would be clipped and magnified with the map")
  ok(PF.button:GetFrameLevel() > WMF:GetFrameLevel(),
     "and lifted by LEVEL, since a child does not reliably outrank its parent on this client")
end

-- Every listed category must actually switch something. A menu entry that does nothing is worse
-- than no menu.
ok(#PF.categories >= 2, "categories are registered")
do
  local names = {}
  for _, c in ipairs(PF.categories) do names[#names + 1] = c.key end
  table.sort(names)
  ok(#names > 0, "with keys: " .. table.concat(names, ", "))
end

-- Landmarks: the client rebuilds and re-shows its POI buttons on every map update, so the filter has
-- to re-apply rather than hide once. A single Hide() would last until the next update.
poi1 = _G.WorldMapFramePOI1
ok(poi1 ~= nil, "the client has landmark pins to filter")
PF.Set("landmarks", true)
PF.ApplyLandmarks()
ok(poi1:IsShown(), "landmarks shown by default")
PF.Set("landmarks", false)
ok(not poi1:IsShown(), "switching the category off hides them")
poi1:Show()                                  -- the client re-showing it on a map update
PF.ApplyLandmarks()
ok(not poi1:IsShown(), "and re-applying puts them back down after the client re-shows them")
PF.Set("landmarks", true)
ok(poi1:IsShown(), "switching it back on restores them")

-- Persistence, and the default that matters: an unset key must read as SHOWN, or a fresh profile
-- comes up with an empty map.
eq(PF._Saved("neverTouched"), true, "a category the player has never touched defaults to shown")
PF.Set("landmarks", false)
eq(NE.db.worldmap.poiFilters.landmarks, false, "a choice is persisted")
PF.Set("landmarks", true)

-- Fog is switched through FogClear rather than duplicated here, so there is no second copy of the
-- state to drift.
if PF.Get("fog") ~= nil then
  PF.Set("fog", false)
  eq(WM.fog.enabled, false, "switching Explored Areas off reaches FogClear's own gate")
  PF.Set("fog", true)
  eq(WM.fog.enabled, true, "and back on")
end

-- Quest objectives reuse the client's own switch rather than a private flag.
if PF.Get("questObjectives") ~= nil then
  PF.Set("questObjectives", false)
  eq(WM.QuestObjectivesShown(), false, "Quest Objectives drives the client's own toggle")
  PF.Set("questObjectives", true)
  eq(WM.QuestObjectivesShown(), true, "in both directions")
end

-- The menu is built from the registry, so a category added later appears with no edit here.
PF.Register("dungeons", "Dungeons", function() return PF._Saved("dungeons") end,
            function(on) PF._Save("dungeons", on) end)
do
  local found = false
  for _, e in ipairs(PF.MenuList()) do
    if e.text == "Dungeons" then found = true end
  end
  ok(found, "a newly registered category appears in the menu with no change to the module")
end

print(("%d checks, %d failures"):format(checks, fails))
os.exit(fails == 0 and 0 or 1)