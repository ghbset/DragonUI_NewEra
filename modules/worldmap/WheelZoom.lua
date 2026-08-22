-- DragonUI_NewEra/modules/worldmap/WheelZoom.lua — scroll the wheel over the map to resize it.
--
-- WHAT MAPSTER ACTUALLY DOES, which is worth stating because guessing at it produced the wrong
-- feature first time round. Mapster's "zoom" is Scaling.lua: a drag handle in the corner running
-- `WorldMapFrame:SetScale(scale)` clamped to 0.2-1.5. It scales the WHOLE WINDOW -- chrome and map
-- together -- so the map draws larger and reads in more detail. There is no magnification of a
-- fixed-size canvas, no panning, and no mousewheel handling anywhere in its source.
--
-- So "zoom" here means what it means there: make the map bigger. This client cannot do anything
-- else. `WorldMapDetailFrame` draws one fixed tileset for one map, there is no magnification layer
-- underneath it, and 3.3.5a has no `SetClipsChildren` -- so a true zoom-and-pan would mean
-- reparenting four client frames (one of them protected) into a ScrollFrame purely to get clipping.
-- That is a different feature at a different risk, and not the one that was asked for.
--
-- THE FIRST VERSION OF THIS FILE STEPPED THE MAP HIERARCHY instead -- world -> continent -> zone.
-- That navigates, which is exactly what the wheel must not do: the wheel changes how big the map is,
-- never which map it is. Recorded because it is an easy mistake to make twice.
--
-- WHAT THE WHEEL ACTUALLY DRIVES. Two wrong answers were tried here before the right one: stepping
-- the map hierarchy (which NAVIGATES -- the wheel must never change which map you are looking at)
-- and stepping the window size (which is what Mapster's corner handle does, but is not
-- magnification). The wheel now drives modules/worldmap/CanvasZoom.lua, which magnifies the canvas
-- inside a clipping viewport; the corner grip keeps window sizing. Two controls, two jobs.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.worldmap = NE.worldmap or {}
local WM = NE.worldmap

local WZ = {}
WM.wheel = WZ

-- ----------------------------------------------------------------------------
-- Where the cursor is
-- ----------------------------------------------------------------------------

-- Returns the position inside the canvas as 0..1, or nil plus WHY. The two failures are not the same
-- and must not be collapsed: "the cursor is somewhere else on screen" is a reason to do nothing,
-- while "this frame will not give me a rect" is a reason to carry on regardless.
local function cursorOnMap()
  local btn = _G.WorldMapButton
  if not (btn and btn.GetLeft) then return nil, "unmeasurable" end
  local left, top = btn:GetLeft(), btn:GetTop()
  local w, h = btn:GetWidth(), btn:GetHeight()
  local scale = btn.GetEffectiveScale and btn:GetEffectiveScale()
  if not (left and top and w and h and scale) then return nil, "unmeasurable" end
  if not (w > 0 and h > 0 and scale > 0) then return nil, "unmeasurable" end

  local cx, cy = GetCursorPosition()
  if not (cx and cy) then return nil, "unmeasurable" end
  cx, cy = cx / scale, cy / scale

  local nx, ny = (cx - left) / w, (top - cy) / h
  if nx < 0 or nx > 1 or ny < 0 or ny > 1 then return nil, "outside" end
  return nx, ny
end

-- True only when the cursor is KNOWN to be somewhere other than the canvas. An unreadable rect must
-- not disable the wheel -- that would trade a working feature for a defensive check.
local function cursorElsewhere()
  local nx, why = cursorOnMap()
  return nx == nil and why == "outside"
end

-- ----------------------------------------------------------------------------
-- Stepping the size
-- ----------------------------------------------------------------------------

function WZ.Enabled()
  local db = NE.db and NE.db.worldmap
  if db and db.wheelZoom ~= nil then return db.wheelZoom and true or false end
  return true
end

function WZ.SetEnabled(on)
  if NE.db then
    NE.db.worldmap = NE.db.worldmap or {}
    NE.db.worldmap.wheelZoom = on and true or false
  end
end

-- Step the magnification one notch. Returns true only if the zoom ACTUALLY changed, so a wheel at
-- either end of its travel falls through to whatever else wanted the input rather than eating it.
function WZ.Step(direction)
  local cz = WM.canvaszoom
  if not (cz and cz.Step) then return false end
  return cz.Step(direction) and true or false
end

function WZ.ZoomIn()  return WZ.Step(1)  end
function WZ.ZoomOut() return WZ.Step(-1) end

function WZ.OnWheel(delta)
  if not WZ.Enabled() then return false end
  if type(delta) ~= "number" or delta == 0 then return false end
  -- Over the chrome, the breadcrumb or the quest list, the wheel belongs to whatever is under it.
  if cursorElsewhere() then return false end
  return WZ.Step(delta > 0 and 1 or -1)
end

-- ----------------------------------------------------------------------------
-- Wiring
-- ----------------------------------------------------------------------------

-- `WorldMapButton` already owns mouse input over the canvas, so the wheel belongs there rather than
-- on the window: it keeps the wheel inert over the chrome and the quest panel, where scrolling means
-- something else.
--
-- Any existing handler is CHAINED, not replaced. Nothing on this client sets one today, but a
-- neighbour is free to, and silently eating its wheel would be the same rudeness the squelch
-- registry exists to avoid.
function WZ.Arm()
  if WZ._armed then return end
  local btn = _G.WorldMapButton
  if not (btn and btn.EnableMouseWheel and btn.SetScript) then return end
  WZ._armed = true

  local previous = btn:GetScript("OnMouseWheel")
  btn:EnableMouseWheel(true)
  btn:SetScript("OnMouseWheel", function(self, delta)
    -- 3.3.5a passes the delta as the global `arg1` to handlers written without widget args; both
    -- forms are read, so this works whether the caller is the client or one of our own tests.
    local d = delta
    if type(d) ~= "number" then d = _G.arg1 end
    local handled = WZ.OnWheel(d)
    if not handled and previous then pcall(previous, self, d) end
  end)
end
