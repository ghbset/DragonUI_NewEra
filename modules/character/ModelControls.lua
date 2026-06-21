-- DragonUI_NewEra/modules/character/ModelControls.lua — the modern DF model control bar (zoom in/out,
-- rotate L/R, reset) at the top of the 3D model. Ported from NewEra/CharacterPanel/ModelControls.lua.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): the model lives in our Inset (reparented + sized by the
-- foundation). The bar is a child of CharacterModelFrame; "is the panel shown" = our custom frame +
-- the Character tab being active.
--
-- 3.3.5a DOWNPORT (the hard part — NewEra targeted Era which had Model_OnMouseWheel + a controlFrame
-- rotation hook; 3.3.5a has NEITHER):
--   * ZOOM: 3.3.5a has NO Model_OnMouseWheel. PlayerModel exposes Get/SetPosition(x,y,z) where x is
--     the camera depth axis — moving it toward the camera zooms IN. We implement zoom by nudging the
--     x position, clamped to a sane range, plus wheel-zoom over the model. (SetCamDistanceScale exists
--     but is undocumented/uneven across cores; SetPosition is reliable.)
--   * ROTATE: 3.3.5a Model_OnUpdate reads the rotate buttons BY GLOBAL NAME
--     (_G[model:GetName().."RotateLeftButton"]) — there is NO model.controlFrame indirection. So we
--     cannot redirect it to our buttons. Instead we hide the vanilla wooden rotate buttons (a hidden
--     button is never PUSHED, so Model_OnUpdate no-ops on them) and drive Model_RotateLeft/Right
--     ourselves from our buttons' own OnUpdate while held.
--   * No NE.squelch helper here -> hide vanilla buttons directly (pcall-guarded).
--   * BTN_HPADDING/sizes/hover-reveal/alpha 0.5 are preserved from NewEra.
--
-- GRACEFUL DEGRADATION (§B): missing atlas art -> button face/icon blank but still clickable; every
-- model call pcall-guarded; OnUpdate watcher tolerates a torn-down model. Never errors out of boot.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE = "character"

local function log(msg) if CP._log then CP._log(msg) elseif NE.Log then NE.Log("CHARPANEL", msg) end end

local BTN_SIZE = 32
local BTN_HPADDING = -6        -- retail buttonHorizontalPadding (buttons overlap by 6px)
local ROTATE_REPEAT = 0.03     -- radians per tick while a rotate button is held (Model_RotateLeft step)
local ZOOM_REPEAT_INTERVAL = 0.05  -- seconds between zoom ticks while held
local ZOOM_STEP = 0.18         -- x-position delta per zoom tick (depth axis)
-- DOWNPORT: symmetric clamp around the default (x=0) so zoom works BOTH ways; the old [0,3.5] clamp
-- pinned the model at the closest position so "+"/zoom-in did nothing. Direction is flipped below.
local ZOOM_MIN = -3.0          -- farthest pull-back (zoom out)
local ZOOM_MAX = 3.0           -- closest (zoom in)

local DEFAULT_ALPHA = 0.5      -- retail ModelSceneControlFrame default alpha

-- ----------------------------------------------------------------------------
-- Zoom helpers — 3.3.5a SetPosition(x,y,z): x is the depth (zoom) axis.
-- ----------------------------------------------------------------------------
local function zoomModel(model, direction)
  if not (model and model.GetPosition and model.SetPosition) then return end
  local ok, x, y, z = pcall(model.GetPosition, model)
  if not ok or not x then return end
  -- DOWNPORT: direction>0 = zoom IN. The previous code did `x - dir*step`, which (per in-game test)
  -- zoomed the WRONG way; flipped to `x + dir*step` so "+" / scroll-up zoom in. Clamp [MIN,MAX].
  x = x + direction * ZOOM_STEP
  if x < ZOOM_MIN then x = ZOOM_MIN elseif x > ZOOM_MAX then x = ZOOM_MAX end
  pcall(model.SetPosition, model, x, y or 0, z or 0)
end

local function resetModel(model)
  if not model then return end
  -- Rotation back to the vanilla default (Model_OnLoad sets 0.61).
  if model.SetRotation then pcall(model.SetRotation, model, 0.61); model.rotation = 0.61 end
  if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
  if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1) end
  if model.SetPortraitZoom    then pcall(model.SetPortraitZoom, model, 0) end
end

-- ----------------------------------------------------------------------------
-- Button factory. Square gray face + centered 16x16 icon + ADD-blend hover glow + press offset.
-- ----------------------------------------------------------------------------
local function makeButton(parent, iconAtlas, onClick)
  local btn = CreateFrame("Button", nil, parent)
  btn:SetSize(BTN_SIZE, BTN_SIZE)
  btn:SetHitRectInsets(4, 4, 4, 4)

  -- Icon: 16x16 centered, OVERLAY.
  local icon = btn:CreateTexture(nil, "OVERLAY")
  icon:SetSize(16, 16)
  icon:SetPoint("CENTER")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(icon, iconAtlas, false) end
  btn.Icon = icon

  -- Normal face: common-button-square-gray-up. DOWNPORT: SetNormalTexture on 3.3.5a accepts EITHER a
  -- path or a texture object; we pass a texture object we've atlas-set (matches NewEra) — but if the
  -- atlas is missing, NE.tex.SetAtlas left it blank, which is fine (button still clickable).
  local normal = btn:CreateTexture(nil, "BACKGROUND")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(normal, "common-button-square-gray-up", false) end
  normal:SetAllPoints(btn)
  btn:SetNormalTexture(normal)

  -- Pushed face: common-button-square-gray-down, offset (1,-1).
  local pushed = btn:CreateTexture(nil, "BACKGROUND")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(pushed, "common-button-square-gray-down", false) end
  pushed:SetPoint("TOPLEFT",     btn, "TOPLEFT",      1, -1)
  pushed:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  1, -1)
  btn:SetPushedTexture(pushed)

  -- Highlight: the icon atlas drawn ADD at 0.4 over the icon bounds -> subtle "icon glows" hover.
  local hl = btn:CreateTexture(nil, "HIGHLIGHT")
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(hl, iconAtlas, false) end
  hl:SetPoint("TOPLEFT",     icon, "TOPLEFT",     0, 0)
  hl:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.4)
  btn:SetHighlightTexture(hl)

  btn:SetScript("OnMouseDown", function(self) self.Icon:AdjustPointsOffset(1, -1) end)
  btn:SetScript("OnMouseUp",   function(self) self.Icon:AdjustPointsOffset(-1, 1) end)
  if onClick then btn:SetScript("OnClick", onClick) end
  return btn
end

-- Attach hold-to-zoom: OnMouseDown fires one step + installs an OnUpdate accumulator; OnMouseUp clears.
local function attachZoomHold(btn, model, direction)
  btn:SetScript("OnMouseDown", function(self)
    self.Icon:AdjustPointsOffset(1, -1)
    zoomModel(model, direction)
    self._acc = 0
    self:SetScript("OnUpdate", function(s, elapsed)
      s._acc = (s._acc or 0) + elapsed
      if s._acc >= ZOOM_REPEAT_INTERVAL then
        s._acc = 0
        zoomModel(model, direction)
      end
    end)
  end)
  btn:SetScript("OnMouseUp", function(self)
    self.Icon:AdjustPointsOffset(-1, 1)
    self:SetScript("OnUpdate", nil)
  end)
end

-- Attach hold-to-rotate: drive Model_RotateLeft/Right ourselves each tick while held. DOWNPORT: 3.3.5a
-- Model_OnUpdate can't be redirected to our buttons (it reads vanilla buttons by name), so we own the
-- rotation drive here. A quick tap still produces one rotation step on MouseDown.
local function attachRotateHold(btn, model, dir)  -- dir: "L" or "R"
  local fn = (dir == "L") and _G.Model_RotateLeft or _G.Model_RotateRight
  btn:SetScript("OnMouseDown", function(self)
    self.Icon:AdjustPointsOffset(1, -1)
    if fn then pcall(fn, model, ROTATE_REPEAT) end
    self._acc = 0
    self:SetScript("OnUpdate", function(s, elapsed)
      s._acc = (s._acc or 0) + elapsed
      -- ~30 ticks/sec feel; Model_RotateLeft itself plays a sound, so step at a modest rate.
      if s._acc >= 0.03 then
        s._acc = 0
        if fn then pcall(fn, model, ROTATE_REPEAT) end
      end
    end)
  end)
  btn:SetScript("OnMouseUp", function(self)
    self.Icon:AdjustPointsOffset(-1, 1)
    self:SetScript("OnUpdate", nil)
  end)
end

-- buildControlBar(model, opts). Defaults target the CharacterPanel model.
local function buildControlBar(model, opts)
  model = model or _G.CharacterModelFrame
  if not model or model._neControlBar then return end
  opts = opts or {}

  -- Wheel-zoom over the model (3.3.5a wires no wheel handler on CharacterModelFrame). delta>0 = in.
  if not model._neWheelZoom then
    model._neWheelZoom = true
    model:EnableMouseWheel(true)
    model:HookScript("OnMouseWheel", function(self, delta) zoomModel(self, delta) end)
  end

  -- Click-drag: LEFT = rotate, RIGHT = pan (move the character within the frame). DOWNPORT: we own
  -- both so right-drag panning works (vanilla only does left-drag rotate). Cursor-delta driven.
  if not model._neDragWired then
    model._neDragWired = true
    model:EnableMouse(true)
    model:RegisterForDrag("LeftButton", "RightButton")
    model:SetScript("OnMouseDown", function(self, button)
      if button ~= "LeftButton" and button ~= "RightButton" then return end
      self._dragBtn = button
      self._dragLX, self._dragLY = GetCursorPosition()
    end)
    model:SetScript("OnMouseUp", function(self) self._dragBtn = nil end)
    model:HookScript("OnUpdate", function(self)
      if not self._dragBtn then return end
      -- DOWNPORT/REPORT (janky release): the physical button is the source of truth. OnMouseUp is MISSED
      -- when the cursor leaves the model mid-drag (release happens off-frame), so _dragBtn stuck and the
      -- doll kept rotating/panning. Self-terminate the instant the button is no longer held, anywhere.
      local ok, down = pcall(IsMouseButtonDown, self._dragBtn)
      if not (ok and down) then self._dragBtn = nil; return end
      local mx, my = GetCursorPosition()
      local dx = mx - (self._dragLX or mx)
      local dy = my - (self._dragLY or my)
      self._dragLX, self._dragLY = mx, my
      if self._dragBtn == "LeftButton" then
        local rot = (self.rotation or 0) - dx * 0.012
        if self.SetRotation then pcall(self.SetRotation, self, rot); self.rotation = rot end
      elseif self._dragBtn == "RightButton" then
        local ok, px, py, pz = pcall(self.GetPosition, self)
        if ok and px and self.SetPosition then
          -- DOWNPORT/REPORT: right-drag pan follows the cursor. Horizontal was inverted (now +dx);
          -- vertical was already correct (+dy) — over-swapping it once inverted up/down, restored here.
          pcall(self.SetPosition, self, px, (py or 0) + dx * 0.004, (pz or 0) + dy * 0.004)
        end
      end
    end)
  end

  local rotateButtons = opts.rotateButtons or {
    "CharacterModelFrameRotateLeftButton",
    "CharacterModelFrameRotateRightButton",
  }
  local panelCheck = opts.panelCheck or function()
    return CP.frame and CP.frame:IsShown()
       and (CP._activeTab == nil or CP._activeTab == "Character")
  end

  -- Hide the vanilla wooden rotate buttons. DOWNPORT: no NE.squelch -> Hide() directly. A hidden
  -- button is never in the PUSHED state, so the vanilla Model_OnUpdate rotation no-ops on them; our
  -- own buttons drive rotation instead.
  for _, name in ipairs(rotateButtons) do
    local b = _G[name]
    if b then pcall(function() b:Hide(); if b.SetAlpha then b:SetAlpha(0) end end) end
  end

  -- Bar container. Width = 2 + 5*(32-6) = 132. Hover-reveal; alpha 0.5 default (per retail).
  local bar = CreateFrame("Frame", "DragonUI_NewEra_ModelControlFrame", model)
  bar:SetSize(2 + 5 * (BTN_SIZE + BTN_HPADDING), BTN_SIZE)
  bar:SetPoint("TOP", model, "TOP", 0, -4)
  bar:SetAlpha(DEFAULT_ALPHA)
  bar:Hide()
  model._neControlBar = bar

  local function placeButton(btn, prev)
    btn:ClearAllPoints()
    if prev then btn:SetPoint("LEFT", prev, "RIGHT", BTN_HPADDING, 0)
    else btn:SetPoint("LEFT", bar, "LEFT", 0, 0) end
  end

  local btnZoomIn = makeButton(bar, "common-icon-zoomin", nil)
  attachZoomHold(btnZoomIn, model, 1)
  placeButton(btnZoomIn, nil)

  local btnZoomOut = makeButton(bar, "common-icon-zoomout", nil)
  attachZoomHold(btnZoomOut, model, -1)
  placeButton(btnZoomOut, btnZoomIn)

  local btnRotL = makeButton(bar, "common-icon-rotateleft", nil)
  attachRotateHold(btnRotL, model, "L")
  placeButton(btnRotL, btnZoomOut)

  local btnRotR = makeButton(bar, "common-icon-rotateright", nil)
  attachRotateHold(btnRotR, model, "R")
  placeButton(btnRotR, btnRotL)

  local btnReset = makeButton(bar, "common-icon-undo", function() resetModel(model) end)
  placeButton(btnReset, btnRotR)

  -- Hover-reveal via cursor-rect polling (PlayerModel:IsMouseOver is unreliable on 3.3.5a). Bar shows
  -- at alpha 1 while the cursor is over the model OR the bar; hides entirely otherwise. Only while the
  -- panel + Character tab are shown.
  local function isMouseInside(frame)
    if not (frame and frame:IsVisible()) then return false end
    local x, y = GetCursorPosition()
    local s = frame:GetEffectiveScale() or 1
    if s <= 0 then return false end
    local mx, my = x / s, y / s
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    local right, top   = frame:GetRight(), frame:GetTop()
    if not (left and bottom and right and top) then return false end
    return mx >= left and mx <= right and my >= bottom and my <= top
  end

  local watcher = CreateFrame("Frame")
  watcher:SetScript("OnUpdate", function()
    if not panelCheck() then
      if bar:IsShown() then bar:Hide() end
      return
    end
    if isMouseInside(model) or isMouseInside(bar) then
      if not bar:IsShown() then bar:Show(); bar:SetAlpha(1) end
    else
      if bar:IsShown() then bar:Hide(); bar:SetAlpha(DEFAULT_ALPHA) end
    end
  end)
  model._neControlWatcher = watcher
end

CP.BuildModelControls = buildControlBar

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled(MODULE) then return end
  local ok, err = pcall(buildControlBar)
  if not ok then log("ModelControls boot failed: " .. tostring(err)) end
end)
