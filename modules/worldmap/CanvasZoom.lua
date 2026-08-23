-- DragonUI_NewEra/modules/worldmap/CanvasZoom.lua — magnify the map canvas itself.
--
-- WHY THIS IS WORTH DOING ON THIS CLIENT. The engine lays every map tile out at 256x256. The HD map
-- patch on this machine ships them at 1024x1024 — verified by reading the BLP headers out of
-- patch-M.mpq — so roughly FOUR TIMES the detail that exists on disk is discarded at every zoom
-- level the stock map can reach. Magnifying here is not making pixels bigger; it is showing art that
-- was already there. On a stock client (256px tiles) it magnifies instead, which is still useful for
-- readability but is a weaker reason.
--
-- THE ONE HARD CONSTRAINT: CLIPPING. 3.3.5a has no `SetClipsChildren`. The only widget that clips
-- its children is a ScrollFrame, so magnification has to happen INSIDE one:
--
--     viewport (ScrollFrame, exactly the canvas area)
--       + content (the scroll child, sized to the magnified map)
--           + WorldMapDetailFrame   (tiles, fog overlays, our dungeon overlay)
--           + WorldMapButton        (and the landmark pins, which ARE its children)
--           + WorldMapFrameAreaFrame
--           + WorldMapPlayerUpper / Lower
--           + WorldMapPOIFrame      (the numbered quest markers)
--
-- THE CONTAINER SCALES; THE FRAMES DO NOT CHANGE SIZE. This is the load-bearing decision. Every one
-- of those frames keeps its own 1002x668 geometry, so the client's own pin arithmetic — which works
-- in canvas-local units — stays correct without knowing anything about zoom. Fog, the dungeon
-- overlay and the landmark pins come along as children, for free. Scaling the frames individually
-- instead would have meant re-deriving every pin position by hand.
--
-- WORLDMAPPOIFRAME IS IN THAT LIST AND HAS TO BE. It is NOT a child of WorldMapButton (an earlier
-- comment here and in Pins.lua both said it was, and the offline harness modelled it that way, which
-- is why this went unnoticed): on 3.3.5a it is a sibling of WorldMapDetailFrame, hanging off
-- WorldMapFrame at scale 1 and merely anchored to the detail frame's corner. Left outside the
-- viewport it was neither clipped — quest markers drew over the chrome once you panned — nor
-- correctly placed, because its scale is what converts the client's canvas offsets into screen
-- pixels. WorldMap.lua's applyClientSpaceScale owns that scale; this file only owns its parent and
-- anchor, exactly as it does for the rest of the canvas.
--
-- QUEST BLOBS ARE HIDDEN WHILE ZOOMED, DELIBERATELY. `WorldMapBlobFrame` is PROTECTED: reparenting
-- it risks taint and cannot happen in combat at all. Mapster hit the same wall and answers it with
-- `Mapster:HideBlobs()` during its scale drag, so this does the same — the blob frame is never
-- reparented, it is squelched while magnified and restored at fit. The cost is visible and was
-- agreed up front: the green quest-area shading goes away while you are zoomed in.
--
-- Squelched rather than merely hidden because the client re-shows that frame on every quest update;
-- a plain Hide() would last until the next one, then come back unclipped over the chrome.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap

local CZ = {}
WM.canvaszoom = CZ

-- 4.0 is where this client's HD tiles run out of real detail (1024 source px over a 256px layout).
-- Past that it magnifies pixels, which is a different and much less interesting thing.
local MIN_ZOOM, MAX_ZOOM = 1.0, 4.0
local STEP = 1.15

CZ.MIN_ZOOM, CZ.MAX_ZOOM, CZ.STEP = MIN_ZOOM, MAX_ZOOM, STEP

-- Reparented into the content frame. The blob frame is NOT in this list and must never be added to
-- it — see the header.
local CANVAS_FRAMES = {
  "WorldMapDetailFrame", "WorldMapButton", "WorldMapFrameAreaFrame",
  "WorldMapPlayerUpper", "WorldMapPlayerLower", "WorldMapPOIFrame",
}

-- Only these carry the canvas scale. WorldMapPOIFrame is deliberately absent: it is adopted for
-- clipping and anchoring only, and its scale is the canvas-to-client ratio that
-- applyClientSpaceScale (WorldMap.lua) works out — writing the canvas scale on it here would fight
-- that and put every quest marker back in the wrong place.
local SCALED = {
  WorldMapDetailFrame = true, WorldMapButton = true, WorldMapFrameAreaFrame = true,
}

CZ.zoom = MIN_ZOOM
CZ.scrollX, CZ.scrollY = 0, 0

local function clampZoom(z)
  z = tonumber(z) or MIN_ZOOM
  if z < MIN_ZOOM then return MIN_ZOOM end
  if z > MAX_ZOOM then return MAX_ZOOM end
  return z
end

-- ----------------------------------------------------------------------------
-- Quest blobs
-- ----------------------------------------------------------------------------

-- Erase the quest blob while magnified, redraw it at fit.
--
-- NOT Hide(), AND NOT THE SQUELCH. `WorldMapBlobFrame` is protected, and our own squelch registry
-- refuses protected regions outright (S.IsProtectedish) -- correctly, because forcing visibility on
-- a protected frame is how taint starts. The first cut of this function tried to squelch it anyway
-- and was silently refused, which is exactly the failure the guard exists to produce.
--
-- Mapster solves it with the blob frame's OWN drawing API: `DrawQuestBlob(questId, false)` erases
-- the blob without touching the frame's parent, scale or visibility, and ShowBlobs redraws it after
-- recalculating hit translations. That is what is mirrored here.
--
-- It matters because the blob frame is deliberately NOT adopted into the clipping viewport, so a
-- blob drawn while magnified would be positioned against a canvas that has moved underneath it and
-- would spill outside the viewport with nothing to clip it.
local function blobsFollowZoom(zoomed)
  local blob = _G.WorldMapBlobFrame
  if not blob then return end

  local settings = _G.WORLDMAP_SETTINGS
  local selected = settings and settings.selectedQuest
  if not selected then return end

  local act = function()
    if zoomed then
      if blob.DrawQuestBlob then blob:DrawQuestBlob(selected.questId, false) end
    else
      if _G.WorldMapBlobFrame_CalculateHitTranslations then
        _G.WorldMapBlobFrame_CalculateHitTranslations()
      end
      if blob.DrawQuestBlob and not selected.completed then
        blob:DrawQuestBlob(selected.questId, true)
      end
    end
  end

  -- DrawQuestBlob is a protected method: calling it in combat is what the deferral is for. Not an
  -- error path -- the blob simply catches up when combat ends.
  if InCombatLockdown and InCombatLockdown() then
    if NE.FrameUtil and NE.FrameUtil.AfterCombat then NE.FrameUtil.AfterCombat(act) end
    return
  end
  pcall(act)
end
CZ._BlobsFollowZoom = blobsFollowZoom

-- ----------------------------------------------------------------------------
-- Building
-- ----------------------------------------------------------------------------

local function build(f)
  if CZ.viewport then return true end
  if not (f and CreateFrame) then return false end

  local viewport = CreateFrame("ScrollFrame", "NE_WorldMapViewport", f)
  local content  = CreateFrame("Frame", "NE_WorldMapZoomContent", viewport)
  content:SetPoint("TOPLEFT", viewport, "TOPLEFT", 0, 0)
  if viewport.SetScrollChild then viewport:SetScrollChild(content) end

  -- Above the window's own art, below the controls the chrome puts on top of the map.
  if viewport.SetFrameLevel then viewport:SetFrameLevel((f:GetFrameLevel() or 1) + 1) end

  CZ.viewport, CZ.content = viewport, content
  CZ.originalParent = {}
  return true
end

-- Move the canvas frames into the content frame, remembering where each came from so the whole
-- thing can be undone.
local function adopt()
  if CZ.adopted or not CZ.content then return end
  local moved = 0
  for _, name in ipairs(CANVAS_FRAMES) do
    local w = _G[name]
    if w and w.SetParent then
      CZ.originalParent[name] = w:GetParent()
      if pcall(w.SetParent, w, CZ.content) then moved = moved + 1 end
    end
  end
  CZ.adopted = moved > 0
  CZ.adoptedCount = moved
end

function CZ.Release()
  if not CZ.adopted then return false end
  for _, name in ipairs(CANVAS_FRAMES) do
    local w, p = _G[name], CZ.originalParent[name]
    if w and p and w.SetParent then pcall(w.SetParent, w, p) end
  end
  CZ.adopted = false
  blobsFollowZoom(false)
  return true
end

-- ----------------------------------------------------------------------------
-- Layout
-- ----------------------------------------------------------------------------

-- The scrollable slack in each axis: how far the magnified map extends past the viewport.
function CZ.Range()
  local g = CZ.geom
  if not g then return 0, 0 end
  local s = g.fit * CZ.zoom
  return math.max(0, g.dw * s - g.canvasW), math.max(0, g.dh * s - g.canvasH)
end

local function clampScroll()
  local rx, ry = CZ.Range()
  if CZ.scrollX < 0 then CZ.scrollX = 0 elseif CZ.scrollX > rx then CZ.scrollX = rx end
  if CZ.scrollY < 0 then CZ.scrollY = 0 elseif CZ.scrollY > ry then CZ.scrollY = ry end
end
CZ._ClampScroll = clampScroll

local function pushScroll()
  local vp = CZ.viewport
  if not vp then return end
  if vp.SetHorizontalScroll then vp:SetHorizontalScroll(CZ.scrollX) end
  if vp.SetVerticalScroll   then vp:SetVerticalScroll(CZ.scrollY) end
end

-- Called from layoutCanvas once the fit scale for this window size is known. This function owns the
-- parent, anchor and scale of the canvas frames from here on — it runs last and overrides what the
-- geometry pass just set, so there is exactly ONE place those three things are decided.
function CZ.Apply(f, geom)
  if not (f and geom and geom.fit and geom.fit > 0) then return false end
  if not build(f) then return false end
  CZ.geom = geom
  adopt()

  local vp, content = CZ.viewport, CZ.content
  vp:ClearAllPoints()
  vp:SetPoint("TOPLEFT", f, "TOPLEFT", geom.insetL, -geom.spacerH)
  vp:SetSize(geom.canvasW, geom.canvasH)

  local s = geom.fit * CZ.zoom
  content:SetSize(geom.dw * s, geom.dh * s)

  for _, name in ipairs(CANVAS_FRAMES) do
    local w = _G[name]
    if w then
      if SCALED[name] and w.SetScale then w:SetScale(s) end
      if w.ClearAllPoints and w.SetPoint then
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
      end
    end
  end

  -- Re-assert the POI layer's frame level after the adoption, exactly as the client's own
  -- WorldMapFrame_ResetFrameLevels does: reparenting can drop a frame to its new parent's level, and
  -- a quest marker painted UNDER the map tiles is invisible rather than obviously broken.
  local poi = _G.WorldMapPOIFrame
  if poi and poi.SetFrameLevel and _G.WORLDMAP_POI_FRAMELEVEL then
    poi:SetFrameLevel(_G.WORLDMAP_POI_FRAMELEVEL)
  end

  clampScroll()
  pushScroll()
  vp:Show()

  blobsFollowZoom(CZ.IsZoomed())
  return true
end

-- ----------------------------------------------------------------------------
-- Zoom
-- ----------------------------------------------------------------------------

function CZ.Level()    return CZ.zoom end
function CZ.IsZoomed() return CZ.zoom > MIN_ZOOM + 0.001 end

-- Set the zoom, keeping the point currently under (ax, ay) — viewport-local pixels — stationary.
-- Without the anchor a zoom drifts toward the top-left corner and whatever is being examined slides
-- out from under the cursor, which is the entire reason a zoom is being used.
function CZ.SetLevel(z, ax, ay)
  local g = CZ.geom
  z = clampZoom(z)
  local before = CZ.zoom
  if math.abs(z - before) < 0.0001 then return false end

  if g then
    local k = z / before
    ax = ax or (g.canvasW * 0.5)
    ay = ay or (g.canvasH * 0.5)
    CZ.scrollX = (CZ.scrollX + ax) * k - ax
    CZ.scrollY = (CZ.scrollY + ay) * k - ay
  end

  CZ.zoom = z
  -- Back at fit there is no slack to hold a pan in, so the offset is dropped rather than clamped:
  -- zooming out and back in should return to the middle, not to wherever the last pan ended.
  if z <= MIN_ZOOM + 0.0001 then CZ.scrollX, CZ.scrollY = 0, 0 end

  if WM.ApplyGeometry then WM.ApplyGeometry() end
  return true
end

-- Where the cursor is inside the viewport, in viewport-local pixels; nil when it is not over it.
function CZ.CursorInViewport()
  local vp = CZ.viewport
  if not (vp and vp.GetLeft) then return nil end
  local left, top = vp:GetLeft(), vp:GetTop()
  local w, h = vp:GetWidth(), vp:GetHeight()
  local sc = vp.GetEffectiveScale and vp:GetEffectiveScale()
  if not (left and top and w and h and sc and w > 0 and h > 0 and sc > 0) then return nil end
  local cx, cy = GetCursorPosition()
  if not (cx and cy) then return nil end
  cx, cy = cx / sc, cy / sc
  local x, y = cx - left, top - cy
  if x < 0 or x > w or y < 0 or y > h then return nil end
  return x, y
end

function CZ.Step(direction)
  local ax, ay = CZ.CursorInViewport()
  local target = (direction > 0) and (CZ.zoom * STEP) or (CZ.zoom / STEP)
  return CZ.SetLevel(target, ax, ay)
end

function CZ.Reset()
  if CZ.zoom == MIN_ZOOM and CZ.scrollX == 0 and CZ.scrollY == 0 then return false end
  CZ.zoom, CZ.scrollX, CZ.scrollY = MIN_ZOOM, 0, 0
  if WM.ApplyGeometry then WM.ApplyGeometry() end
  return true
end

-- ----------------------------------------------------------------------------
-- Panning
-- ----------------------------------------------------------------------------

-- RIGHT button, not left. Left-click over the canvas belongs to the client — quest pins, landmark
-- tooltips, the zone-select click on a continent map — and stealing it to pan would break all three
-- for the sake of a gesture.
--
-- BUT RIGHT-CLICK IS NOT FREE EITHER, which is what shipped broken: the client uses it to zoom OUT a
-- level, so every pan ended by throwing you up to the continent map. The gesture is still the right
-- one — it just has to be told apart from a click, and the only thing that distinguishes them is
-- whether the mouse MOVED. So a pan that actually moved swallows the click that ends it, and a
-- right-click that did not move falls through to the client untouched and still zooms out.
--
-- The threshold is in screen pixels: big enough to absorb the shake of a real click, small enough
-- that a deliberate drag always clears it.
local PAN_THRESHOLD = 4
local function panUpdate()
  local vp, o = CZ.viewport, CZ.panOrigin
  if not (vp and o) then return end
  local sc = (vp.GetEffectiveScale and vp:GetEffectiveScale()) or 1
  local cx, cy = GetCursorPosition()
  if not (cx and cy and sc > 0) then return end
  cx, cy = cx / sc, cy / sc
  local dx, dy = cx - o.cx, cy - o.cy
  if not CZ.panMoved and (dx * dx + dy * dy) > (PAN_THRESHOLD * PAN_THRESHOLD) then
    CZ.panMoved = true
  end
  -- Drag right, the map follows the cursor, so the scroll offset moves the other way. Y is inverted
  -- again because scroll counts DOWN from the top while screen coordinates count up.
  CZ.scrollX = o.sx - dx
  CZ.scrollY = o.sy + dy
  clampScroll()
  pushScroll()
end

function CZ.BeginPan()
  if not CZ.IsZoomed() then return false end
  local vp = CZ.viewport
  if not vp then return false end
  local sc = (vp.GetEffectiveScale and vp:GetEffectiveScale()) or 1
  local cx, cy = GetCursorPosition()
  if not (cx and cy and sc > 0) then return false end
  CZ.panOrigin = { cx = cx / sc, cy = cy / sc, sx = CZ.scrollX, sy = CZ.scrollY }
  CZ.panMoved = false
  if vp.SetScript then vp:SetScript("OnUpdate", panUpdate) end
  return true
end

-- Returns whether the pan actually MOVED, which is what decides whether the click that ended it gets
-- swallowed. `panMoved` is deliberately left set for the OnClick that follows and is cleared there,
-- because on this client OnClick arrives after OnMouseUp.
function CZ.EndPan()
  if not CZ.panOrigin then return false end
  CZ.panOrigin = nil
  if CZ.viewport and CZ.viewport.SetScript then CZ.viewport:SetScript("OnUpdate", nil) end
  return CZ.panMoved and true or false
end

-- Should the click that just ended a drag be swallowed rather than reaching the client?
function CZ.ShouldSwallowClick(button)
  if button ~= "RightButton" then return false end
  return CZ.panMoved and true or false
end

CZ._PanUpdate = panUpdate

-- ----------------------------------------------------------------------------
-- Arming
-- ----------------------------------------------------------------------------

-- Changing which map is shown drops the zoom too: a pan offset measured against one map means
-- nothing on another.
function CZ.OnMapChanged()
  CZ.EndPan()
  CZ.Reset()
end

-- Zoom does not survive the map closing: a pan offset means nothing on a map that is not the one it
-- was measured against, and reopening already scrolled into a corner reads as broken.
function CZ.Arm()
  if CZ._armed then return end
  CZ._armed = true

  local btn = _G.WorldMapButton
  if btn and btn.HookScript then
    btn:HookScript("OnMouseDown", function(_, button)
      if (button or _G.arg1) == "RightButton" then CZ.BeginPan() end
    end)
    btn:HookScript("OnMouseUp", function(_, button)
      if (button or _G.arg1) == "RightButton" then CZ.EndPan() end
    end)

    -- REPLACED, not hooked. A hook cannot stop the client's own handler from running, and the
    -- client's right-click zooms the map out a level — so hooking would leave every pan ending on
    -- the continent map. The original is captured and called for everything except the one case that
    -- must not reach it: the click ending a drag that actually moved.
    if btn.GetScript and btn.SetScript then
      local originalOnClick = btn:GetScript("OnClick")
      CZ._originalOnClick = originalOnClick
      CZ._wrappedOnClick = originalOnClick ~= nil
      btn:SetScript("OnClick", function(self, button, ...)
        local b = button or _G.arg1
        if CZ.ShouldSwallowClick(b) then
          CZ.panMoved = false
          return
        end
        if originalOnClick then return originalOnClick(self, button, ...) end
      end)
    end
  end

  -- AND THE FUNCTIONS THEMSELVES, because wrapping the button's OnClick was not enough — the map
  -- still jumped up a level at the end of every pan. Which script the client wires its right-click
  -- zoom-out from is a detail of this build's FrameXML that is not worth deducing: whichever path
  -- fires, it ends up in one of these two functions, so the swallow is applied where they are rather
  -- than where they are called from.
  --
  -- Wrapped, not disabled: the guard is spent on the ONE call that ends a real drag, and every other
  -- right-click still zooms out exactly as it always did.
  for _, name in ipairs({ "WorldMapZoomOutButton_OnClick", "WorldMapButton_OnClick" }) do
    local original = _G[name]
    if type(original) == "function" and not CZ._wrapped then
      _G[name] = function(...)
        if CZ.panMoved then
          CZ.panMoved = false
          return
        end
        return original(...)
      end
      CZ._wrappedFns = (CZ._wrappedFns or "") .. name .. " "
    end
  end
  CZ._wrapped = true

  local map = WM.frame
  if map and map.HookScript then
    map:HookScript("OnHide", function() CZ.EndPan(); CZ.Reset() end)
  end

  -- Chained onto whatever the other modules already registered rather than replacing it: every one
  -- of them wants this signal, and the last file to load must not silently win.
  local prev = WM.OnMapChanged
  WM.OnMapChanged = function()
    if prev then pcall(prev) end
    CZ.OnMapChanged()
  end
end

