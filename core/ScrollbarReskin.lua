-- DragonUI_NewEra/core/ScrollbarReskin.lua — SHARED scrollbar reskin for any UIPanel ScrollFrame.
-- Visual port of retail's MinimalScrollBar over the CLASSIC Slider-based UIPanelScrollBar.
--
-- DOWNPORT: NewEra Core/ScrollbarReskin.lua → 3.3.5a.
--   * NE.scrollbar.Reskin (the Slider/UIPanelScrollBar path) PORTS DIRECTLY — UIPanelScrollFrame
--     Template + Slider + named ScrollUpButton/ScrollDownButton all exist on 3.3.5a. The only
--     change is SetShown → Show/Hide and routing setAtlas through NE.tex.SetAtlas.
--   * NE.scrollbar.AttachMinimal + AttachBottomShadow depend on RETAIL-ONLY infrastructure
--     (WowScrollBox, MinimalScrollBar template, EventFrame, ScrollUtil, BaseScrollBoxEvents,
--     RegisterCallback). None exist on 3.3.5a, so they are FEATURE-GATED v1 STUBS: they detect
--     the missing infra and return nil (no error). When/if a compat layer ships WowScrollBox they
--     light up unchanged. v1 panels use Reskin (the Slider path).
--
-- §2 CONTRACT: NE.scrollbar.* preserved.
--
-- The minimal-scrollbar atlas sheets are NOT in the Sprint-0 set, so even Reskin's art swaps
-- degrade gracefully (NE.tex.SetAtlas returns false → piece untextured) until §3 ships them; the
-- reposition/sizing/wheel-enable still work.

local NE = DragonUI_NewEra
NE.scrollbar = NE.scrollbar or {}

-- AttachMinimal — DOWNPORT STUB. Needs WowScrollBox + MinimalScrollBar (retail-only). No-op on
-- 3.3.5a; returns nil. Guarded so a caller that probes for modern infra degrades cleanly.
function NE.scrollbar.AttachMinimal(scrollBox, opts)
  if not scrollBox then return end
  if not (ScrollUtil and CreateFrame) then return end
  -- DOWNPORT: "EventFrame" frame type + "MinimalScrollBar" template don't exist on 3.3.5a;
  -- pcall the create so a missing template can't error. If it fails, bail (v1 stub).
  opts = opts or {}
  local parent = opts.parent or (scrollBox.GetParent and scrollBox:GetParent())
  local ok, bar = pcall(CreateFrame, "EventFrame", opts.name, parent, "MinimalScrollBar")
  if not ok or not bar then return end
  local x = opts.x or 0
  bar:SetPoint("TOPLEFT",    scrollBox, "TOPRIGHT",    x,  opts.top    or 0)
  bar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", x,  opts.bottom or 0)
  if opts.hideIfUnscrollable ~= nil then bar.hideIfUnscrollable = opts.hideIfUnscrollable end
  if ScrollUtil and ScrollUtil.InitScrollBoxWithScrollBar then
    if opts.list and ScrollUtil.InitScrollBoxListWithScrollBar then
      ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, bar, opts.view)
    else
      local view = opts.view or (CreateScrollBoxLinearView and CreateScrollBoxLinearView(0, 0, 0, 0, 0))
      ScrollUtil.InitScrollBoxWithScrollBar(scrollBox, bar, view)
    end
  end
  return bar
end

local SLIDER_WIDTH = 8
local THUMB_WIDTH  = 8
local THUMB_HEIGHT = 60
local ARROW_W      = 17
local ARROW_H      = 11
local CAP_H          = 8
local VISIBLE_GAP    = 6
local ARROW_GAP      = CAP_H + VISIBLE_GAP     -- 14
local SLIDER_Y_INSET = ARROW_H + ARROW_GAP     -- 25

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(tex, name, useAtlasSize)
  end
end

local function reskinArrowButton(button, normalAtlas, overAtlas, downAtlas, anchor)
  if not button then return end
  button:ClearAllPoints()
  local sb = button:GetParent()
  if anchor == "TOP" then
    button:SetPoint("BOTTOM", sb, "TOP", 0, ARROW_GAP)
  else
    button:SetPoint("TOP",    sb, "BOTTOM", 0, -ARROW_GAP)
  end
  local n = button:GetNormalTexture()
  local p = button:GetPushedTexture()
  local d = button:GetDisabledTexture()
  local h = button:GetHighlightTexture()
  if n then setAtlas(n, normalAtlas, false) end
  if p then setAtlas(p, downAtlas,   false) end
  if d then setAtlas(d, normalAtlas, false); d:SetDesaturated(true) end
  if h then
    setAtlas(h, overAtlas, false)
    h:SetBlendMode("ADD")
  end
  button:SetSize(ARROW_W, ARROW_H)
end

local function buildTrack(sb)
  if sb._neTrackBegin then return end

  local begin = sb:CreateTexture(nil, "BACKGROUND")
  setAtlas(begin, "minimal-scrollbar-track-top", true)
  begin:SetPoint("TOP", sb, "TOP", 0, 0)

  local endTex = sb:CreateTexture(nil, "BACKGROUND")
  setAtlas(endTex, "minimal-scrollbar-track-bottom", true)
  endTex:SetPoint("BOTTOM", sb, "BOTTOM", 0, 0)

  local middle = sb:CreateTexture(nil, "BACKGROUND")
  setAtlas(middle, "!minimal-scrollbar-track-middle", false)
  middle:SetPoint("TOPLEFT",     begin,  "BOTTOMLEFT")
  middle:SetPoint("BOTTOMRIGHT", endTex, "TOPRIGHT")

  sb._neTrackBegin, sb._neTrackEnd, sb._neTrackMiddle = begin, endTex, middle
end

local function buildThumb(sb)
  if not sb.SetThumbTexture then return end
  local thumb = sb:GetThumbTexture()
  if not thumb then return end

  setAtlas(thumb, "minimal-scrollbar-small-thumb-middle", false)
  thumb:SetSize(THUMB_WIDTH, THUMB_HEIGHT)

  if not sb._neThumbCapHost then
    local host = CreateFrame("Frame", nil, sb)
    host:SetFrameLevel((sb:GetFrameLevel() or 1) + 5)
    host:SetPoint("TOPLEFT",     thumb, "TOPLEFT",     0, 0)
    host:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0, 0)
    sb._neThumbCapHost = host
  end
  if not sb._neThumbCapTop then
    local capTop = sb._neThumbCapHost:CreateTexture(nil, "OVERLAY")
    setAtlas(capTop, "minimal-scrollbar-small-thumb-top", true)
    capTop:SetPoint("TOP", sb._neThumbCapHost, "TOP", 0, 0)
    sb._neThumbCapTop = capTop
  end
  if not sb._neThumbCapBot then
    local capBot = sb._neThumbCapHost:CreateTexture(nil, "OVERLAY")
    setAtlas(capBot, "minimal-scrollbar-small-thumb-bottom", true)
    capBot:SetPoint("BOTTOM", sb._neThumbCapHost, "BOTTOM", 0, 0)
    sb._neThumbCapBot = capBot
  end

  if not sb._neThumbHoverHooked then
    sb._neThumbHoverHooked = true
    local function applyState(suffix)
      setAtlas(thumb,             "minimal-scrollbar-small-thumb-middle" .. suffix, false)
      setAtlas(sb._neThumbCapTop, "minimal-scrollbar-small-thumb-top"    .. suffix, true)
      setAtlas(sb._neThumbCapBot, "minimal-scrollbar-small-thumb-bottom" .. suffix, true)
    end
    sb:HookScript("OnEnter",     function() applyState("-over") end)
    sb:HookScript("OnLeave",     function() applyState("")      end)
    sb:HookScript("OnMouseDown", function() applyState("-down") end)
    sb:HookScript("OnMouseUp",   function() applyState("-over") end)
  end
end

-- DOWNPORT helper: SetShown is absent on 3.3.5a — Show/Hide by a boolean.
local function setShown(obj, on)
  if not obj then return end
  if on then obj:Show() else obj:Hide() end
end

-- Public entry — the classic Slider/UIPanelScrollBar reskin. Works on 3.3.5a.
function NE.scrollbar.Reskin(scroll, opts)
  if not scroll then return end
  local sb = scroll.ScrollBar or scroll.scrollBar
  if not sb then return end
  if not sb.ScrollUpButton then
    local sbName = sb.GetName and sb:GetName()
    if sbName then
      sb.ScrollUpButton   = _G[sbName .. "ScrollUpButton"]
      sb.ScrollDownButton = _G[sbName .. "ScrollDownButton"]
    end
  end

  opts = opts or {}
  local xOffset            = opts.x                  or 7
  local strataHigh         = opts.strataHigh         ~= false
  local hideIfUnscrollable = opts.hideIfUnscrollable == true

  local CLASSIC_TRACK = { "Top", "Bottom", "Middle", "Background", "trackBG", "Track" }
  local function hideClassicTrack()
    for _, key in ipairs(CLASSIC_TRACK) do
      local r = sb[key]
      if r and r ~= sb._neTrackBegin and r ~= sb._neTrackEnd and r ~= sb._neTrackMiddle
         and r.Hide then r:Hide() end
    end
  end
  hideClassicTrack()
  if not sb._neTrackHideHooked then
    sb._neTrackHideHooked = true
    sb:HookScript("OnShow", hideClassicTrack)
  end

  scroll:EnableMouseWheel(true)

  sb:ClearAllPoints()
  sb:SetPoint("TOPLEFT",    scroll, "TOPRIGHT",    xOffset, -SLIDER_Y_INSET)
  sb:SetPoint("BOTTOMLEFT", scroll, "BOTTOMRIGHT", xOffset,  SLIDER_Y_INSET)
  sb:SetWidth(SLIDER_WIDTH)
  sb:SetHitRectInsets(-2, -2, 0, 0)

  if strataHigh then
    sb:SetFrameStrata("HIGH")
    if sb.ScrollUpButton   then sb.ScrollUpButton:SetFrameStrata("HIGH")   end
    if sb.ScrollDownButton then sb.ScrollDownButton:SetFrameStrata("HIGH") end
  end
  sb:EnableMouse(true)

  reskinArrowButton(sb.ScrollUpButton,
    "minimal-scrollbar-arrow-top", "minimal-scrollbar-arrow-top-over",
    "minimal-scrollbar-arrow-top-down", "TOP")
  reskinArrowButton(sb.ScrollDownButton,
    "minimal-scrollbar-arrow-bottom", "minimal-scrollbar-arrow-bottom-over",
    "minimal-scrollbar-arrow-bottom-down", "BOTTOM")
  if sb.ScrollUpButton   then sb.ScrollUpButton:EnableMouse(true)   end
  if sb.ScrollDownButton then sb.ScrollDownButton:EnableMouse(true) end

  buildTrack(sb)
  buildThumb(sb)

  local function refreshThumb()
    local yr = (scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange()) or 0
    local show = yr and yr > 1
    local thumb = sb.GetThumbTexture and sb:GetThumbTexture()
    setShown(thumb, show)                          -- DOWNPORT: SetShown → setShown helper
    setShown(sb._neThumbCapHost, show)
  end
  scroll:HookScript("OnScrollRangeChanged", refreshThumb)
  if C_Timer and C_Timer.After then C_Timer.After(0, refreshThumb) end

  if hideIfUnscrollable then
    scroll.scrollBarHideable = true
    local function applyVisibility()
      local yrange = scroll.GetVerticalScrollRange and scroll:GetVerticalScrollRange() or 0
      local visible = yrange > 0
      setShown(sb.ScrollUpButton, visible)
      setShown(sb.ScrollDownButton, visible)
      setShown(sb, visible)
    end
    scroll:HookScript("OnScrollRangeChanged", applyVisibility)
    if C_Timer and C_Timer.After then C_Timer.After(0, applyVisibility) end
  else
    scroll.scrollBarHideable = nil
    if sb.ScrollUpButton   then sb.ScrollUpButton:Show()   end
    if sb.ScrollDownButton then sb.ScrollDownButton:Show() end
    sb:Show()
    scroll:HookScript("OnScrollRangeChanged", function()
      if sb.ScrollUpButton   then sb.ScrollUpButton:Show()   end
      if sb.ScrollDownButton then sb.ScrollDownButton:Show() end
      sb:Show()
    end)
  end
end

-- ============================================================================
-- NE.scrollbar.BuildCustom — hand-built minimal scrollbar for a named
-- FauxScrollFrameTemplate. (DOWNPORT: built FROM SCRATCH because Reskin's
-- in-place re-skin of the stock UIPanelScrollBar Slider was not rendering — the
-- user still saw the default Blizzard bar. This widget OWNS its own track+thumb
-- frames and merely DRIVES the FauxScrollFrame's hidden internal slider so all
-- the existing FauxScrollFrame_Update / FauxScrollFrame_GetOffset row logic keeps
-- working untouched.)
--
-- How it syncs: a FauxScrollFrameTemplate contains a hidden Slider named
-- "<name>ScrollBar". FauxScrollFrame_Update() sets that slider's min/max and
-- FauxScrollFrame_GetOffset() reads slider:GetValue()/step. So we:
--   * Hide the stock slider + its two arrow buttons (Hide, not remove — Faux
--     still reads/writes the slider's value).
--   * Poll the slider's GetMinMaxValues / GetValue (cheap, OnUpdate-throttled +
--     OnVerticalScroll/OnScrollRangeChanged hooks) to size & place our thumb.
--   * On thumb drag, map the pixel position back to a slider value and
--     slider:SetValue() — which fires the scrollframe's OnVerticalScroll, i.e.
--     the SAME path the wheel uses. No row logic is duplicated.
--   * Hide the whole bar when the content fits (max <= min).
-- Idempotent via scrollFrame._neCustomBar.
-- ----------------------------------------------------------------------------

local CB_WIDTH      = 8      -- track + thumb width
local CB_CAP_H      = 8      -- top/bottom cap height (track + thumb)
local CB_MIN_THUMB  = 24     -- never let the thumb shrink below this
local CB_X_INSET    = -2     -- bar x relative to the pane's right edge

local function cbSetThumbState(bar, suffix)
  setAtlas(bar._thumbMid, "minimal-scrollbar-small-thumb-middle" .. suffix, false)
  setAtlas(bar._thumbTop, "minimal-scrollbar-small-thumb-top"    .. suffix, true)
  setAtlas(bar._thumbBot, "minimal-scrollbar-small-thumb-bottom" .. suffix, true)
end

-- Read the FauxScrollFrame's hidden slider, size+place the thumb, toggle the bar.
local function cbSync(bar)
  local slider = bar._slider
  if not slider then return end
  local minV, maxV = slider:GetMinMaxValues()
  minV = minV or 0; maxV = maxV or 0
  local range = maxV - minV
  -- Content fits → hide the whole custom bar (and keep the stock bits hidden).
  if range <= 0 then
    bar:Hide()
    return
  end
  bar:Show()

  local trackH = bar:GetHeight() or 0
  if trackH <= 0 then return end

  -- Thumb height ~ proportion of visible:total, but we only know the value
  -- range (in steps). Use a fixed-ish thumb that still shrinks on long lists.
  local thumbH = trackH * 0.40
  if range > 0 then
    -- shrink as the scrollable range grows; clamp to a sane band.
    thumbH = trackH * math.max(0.18, math.min(0.6, 1 / (1 + range / (trackH))))
  end
  if thumbH < CB_MIN_THUMB then thumbH = CB_MIN_THUMB end
  if thumbH > trackH then thumbH = trackH end
  bar._thumb:SetHeight(thumbH)

  local val = slider:GetValue() or minV
  local frac = (val - minV) / range
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local travel = trackH - thumbH
  bar._thumb:ClearAllPoints()
  bar._thumb:SetPoint("TOP", bar, "TOP", 0, -(frac * travel))
end

-- Drag handler: convert the thumb's top Y (relative to the track) into a slider
-- value and write it back (which scrolls the rows via OnVerticalScroll).
local function cbOnThumbUpdate(thumb)
  local bar = thumb._bar
  local slider = bar and bar._slider
  if not slider then return end
  local minV, maxV = slider:GetMinMaxValues()
  minV = minV or 0; maxV = maxV or 0
  local range = maxV - minV
  if range <= 0 then return end

  local trackTop = bar:GetTop()
  local thumbTop = thumb:GetTop()
  local trackH   = bar:GetHeight() or 0
  local thumbH   = thumb:GetHeight() or 0
  local travel   = trackH - thumbH
  if not (trackTop and thumbTop) or travel <= 0 then return end

  local frac = (trackTop - thumbTop) / travel
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local newVal = minV + frac * range
  if math.abs(newVal - (slider:GetValue() or minV)) >= 0.5 then
    slider:SetValue(newVal)         -- fires scrollFrame OnVerticalScroll → rows update
  end
end

function NE.scrollbar.BuildCustom(scrollFrame, opts)
  if not scrollFrame then return end
  if scrollFrame._neCustomBar then return scrollFrame._neCustomBar end

  local name = scrollFrame.GetName and scrollFrame:GetName()
  -- Locate the FauxScrollFrame's hidden slider + arrow buttons.
  local slider = (name and _G[name .. "ScrollBar"]) or scrollFrame.ScrollBar or scrollFrame.scrollBar
  if not slider then return end
  local sName = slider.GetName and slider:GetName()
  local upBtn   = (sName and _G[sName .. "ScrollUpButton"])
  local downBtn = (sName and _G[sName .. "ScrollDownButton"])

  opts = opts or {}
  local xInset = opts.x ~= nil and -opts.x or CB_X_INSET

  -- Hide the stock scrollbar + arrows (do NOT remove — Faux still drives the
  -- slider value). Re-hide on any attempt to show them.
  local function hideStock()
    if slider then slider:Hide() end
    if upBtn then upBtn:Hide() end
    if downBtn then downBtn:Hide() end
  end
  hideStock()
  if slider.HookScript then slider:HookScript("OnShow", function(s) s:Hide() end) end
  if upBtn and upBtn.HookScript then upBtn:HookScript("OnShow", function(s) s:Hide() end) end
  if downBtn and downBtn.HookScript then downBtn:HookScript("OnShow", function(s) s:Hide() end) end

  -- ---- the custom bar frame (= the track) ----------------------------------
  local bar = CreateFrame("Frame", nil, scrollFrame)
  bar:SetWidth(CB_WIDTH)
  -- Anchor to the right edge of the scroll pane, inset a little, full height.
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT",     scrollFrame, "TOPRIGHT", xInset, 0)
  bar:SetPoint("BOTTOMLEFT",  scrollFrame, "BOTTOMRIGHT", xInset, 0)
  bar:SetFrameStrata("HIGH")
  bar:SetFrameLevel((scrollFrame:GetFrameLevel() or 1) + 6)
  bar._slider = slider

  -- track: top cap + bottom cap + tiled middle
  local tTop = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tTop, "minimal-scrollbar-track-top", true)
  tTop:SetWidth(CB_WIDTH); tTop:SetHeight(CB_CAP_H)
  tTop:SetPoint("TOP", bar, "TOP", 0, 0)

  local tBot = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tBot, "minimal-scrollbar-track-bottom", true)
  tBot:SetWidth(CB_WIDTH); tBot:SetHeight(CB_CAP_H)
  tBot:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)

  local tMid = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tMid, "!minimal-scrollbar-track-middle", false)
  tMid:SetPoint("TOPLEFT",     tTop, "BOTTOMLEFT",  0, 0)
  tMid:SetPoint("BOTTOMRIGHT", tBot, "TOPRIGHT",    0, 0)

  -- ---- the thumb -----------------------------------------------------------
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(CB_WIDTH)
  thumb:SetHeight(CB_MIN_THUMB)
  thumb:SetPoint("TOP", bar, "TOP", 0, 0)
  thumb:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
  thumb:EnableMouse(true)
  thumb._bar = bar
  bar._thumb = thumb

  local thMid = thumb:CreateTexture(nil, "ARTWORK")
  setAtlas(thMid, "minimal-scrollbar-small-thumb-middle", false)
  thMid:SetPoint("TOPLEFT",     thumb, "TOPLEFT",     0,  -CB_CAP_H)
  thMid:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0,   CB_CAP_H)
  bar._thumbMid = thMid

  local thTop = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thTop, "minimal-scrollbar-small-thumb-top", true)
  thTop:SetWidth(CB_WIDTH); thTop:SetHeight(CB_CAP_H)
  thTop:SetPoint("TOP", thumb, "TOP", 0, 0)
  bar._thumbTop = thTop

  local thBot = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thBot, "minimal-scrollbar-small-thumb-bottom", true)
  thBot:SetWidth(CB_WIDTH); thBot:SetHeight(CB_CAP_H)
  thBot:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  bar._thumbBot = thBot

  -- drag: while held, follow the cursor (clamped) and write the slider value.
  thumb:SetScript("OnMouseDown", function(self)
    cbSetThumbState(bar, "-down")
    self._dragging = true
    self:SetScript("OnUpdate", function(s)
      -- Follow the cursor: place the thumb under the mouse Y, clamped to track.
      local trackTop = bar:GetTop()
      local trackH   = bar:GetHeight() or 0
      local thumbH   = s:GetHeight() or 0
      if not trackTop then return end
      local _, cursorY = GetCursorPosition()
      local scale = bar:GetEffectiveScale() or 1
      cursorY = cursorY / scale
      -- desired thumb-top so the grab point stays under cursor (center grab is fine)
      local desiredTop = cursorY + (thumbH / 2)
      local maxTop = trackTop
      local minTop = trackTop - (trackH - thumbH)
      if desiredTop > maxTop then desiredTop = maxTop end
      if desiredTop < minTop then desiredTop = minTop end
      s:ClearAllPoints()
      s:SetPoint("TOP", bar, "TOP", 0, -(maxTop - desiredTop))
      cbOnThumbUpdate(s)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self._dragging = false
    self:SetScript("OnUpdate", nil)
    cbSetThumbState(bar, "")
    cbSync(bar)              -- snap the thumb to the canonical slider position
  end)
  thumb:SetScript("OnEnter", function() if not thumb._dragging then cbSetThumbState(bar, "-over") end end)
  thumb:SetScript("OnLeave", function() if not thumb._dragging then cbSetThumbState(bar, "") end end)

  -- keep the wheel working (FauxScrollFrames usually wire it; ensure enabled).
  scrollFrame:EnableMouseWheel(true)

  -- ---- syncing -------------------------------------------------------------
  local function sync() cbSync(bar) end
  scrollFrame:HookScript("OnVerticalScroll",     sync)
  scrollFrame:HookScript("OnScrollRangeChanged", sync)
  -- The slider value is set by FauxScrollFrame_Update (which the row refreshers
  -- call) and by the wheel; mirror those via the slider's own value change.
  if slider.HookScript then slider:HookScript("OnValueChanged", sync) end

  -- Throttled OnUpdate fallback so the thumb tracks (and the bar re-appears when
  -- content grows) even if a refresher updates the slider without firing a hook
  -- we caught. DOWNPORT: driven off the scrollFrame (always shown while the panel
  -- is open) NOT the bar — a hidden frame fires no OnUpdate, so a bar that hid
  -- itself when content fit could never re-show itself. (cheap; ~10/sec)
  local accum = 0
  scrollFrame:HookScript("OnUpdate", function(self, elapsed)
    accum = accum + (elapsed or 0)
    if accum < 0.1 then return end
    accum = 0
    if not thumb._dragging then cbSync(bar) end
  end)

  scrollFrame._neCustomBar = bar
  if C_Timer and C_Timer.After then C_Timer.After(0, sync) else sync() end
  return bar
end

-- ============================================================================
-- NE.scrollbar.BuildCustomPixel — DOWNPORT/REPORT: a PIXEL-SCROLL variant of BuildCustom for a
-- plain ScrollFrame (NOT a FauxScrollFrame). The faithful-NewEra stats sidebar builds ALL rows at
-- cumulative Y in one tall content frame and scrolls by PIXELS (NewEra used a retail WowScrollBox,
-- absent on 3.3.5a). This widget OWNS its own track+thumb and drives the ScrollFrame's
-- SetVerticalScroll directly, reading GetVerticalScrollRange()/GetVerticalScroll() for the thumb.
--
-- Reuses the SAME track/thumb art + drag feel as BuildCustom; only the value source/sink differ:
--   * range  = scrollFrame:GetVerticalScrollRange()
--   * value  = scrollFrame:GetVerticalScroll()
--   * set    = scrollFrame:SetVerticalScroll(v)
-- Idempotent via scrollFrame._neCustomBar.
-- ----------------------------------------------------------------------------

-- Read the ScrollFrame's pixel scroll range/value, size+place the thumb, toggle the bar.
local function cbpSync(bar)
  local sf = bar._scrollFrame
  if not sf then return end
  local range = (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
  if range <= 0 then
    bar:Hide()
    return
  end
  bar:Show()

  local trackH = bar:GetHeight() or 0
  if trackH <= 0 then return end

  -- Thumb height ~ proportion of visible:total. visible = trackH-ish; total = visible + range.
  local visible = (sf.GetHeight and sf:GetHeight()) or trackH
  local total   = visible + range
  local thumbH  = trackH * (visible / total)
  if thumbH < CB_MIN_THUMB then thumbH = CB_MIN_THUMB end
  if thumbH > trackH then thumbH = trackH end
  bar._thumb:SetHeight(thumbH)

  local val  = (sf.GetVerticalScroll and sf:GetVerticalScroll()) or 0
  local frac = val / range
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local travel = trackH - thumbH
  bar._thumb:ClearAllPoints()
  bar._thumb:SetPoint("TOP", bar, "TOP", 0, -(frac * travel))
end

-- Drag handler: convert the thumb's top Y into a pixel scroll value and write it back.
local function cbpOnThumbUpdate(thumb)
  local bar = thumb._bar
  local sf = bar and bar._scrollFrame
  if not sf then return end
  local range = (sf.GetVerticalScrollRange and sf:GetVerticalScrollRange()) or 0
  if range <= 0 then return end

  local trackTop = bar:GetTop()
  local thumbTop = thumb:GetTop()
  local trackH   = bar:GetHeight() or 0
  local thumbH   = thumb:GetHeight() or 0
  local travel   = trackH - thumbH
  if not (trackTop and thumbTop) or travel <= 0 then return end

  local frac = (trackTop - thumbTop) / travel
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  sf:SetVerticalScroll(frac * range)
end

function NE.scrollbar.BuildCustomPixel(scrollFrame, opts)
  if not scrollFrame then return end
  if scrollFrame._neCustomBar then return scrollFrame._neCustomBar end

  opts = opts or {}
  local xInset = opts.x ~= nil and -opts.x or CB_X_INSET

  -- ---- the custom bar frame (= the track) ----------------------------------
  local bar = CreateFrame("Frame", nil, scrollFrame)
  bar:SetWidth(CB_WIDTH)
  bar:ClearAllPoints()
  bar:SetPoint("TOPLEFT",    scrollFrame, "TOPRIGHT",    xInset, 0)
  bar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", xInset, 0)
  bar:SetFrameStrata("HIGH")
  bar:SetFrameLevel((scrollFrame:GetFrameLevel() or 1) + 6)
  bar._scrollFrame = scrollFrame

  -- track: top cap + bottom cap + tiled middle
  local tTop = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tTop, "minimal-scrollbar-track-top", true)
  tTop:SetWidth(CB_WIDTH); tTop:SetHeight(CB_CAP_H)
  tTop:SetPoint("TOP", bar, "TOP", 0, 0)

  local tBot = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tBot, "minimal-scrollbar-track-bottom", true)
  tBot:SetWidth(CB_WIDTH); tBot:SetHeight(CB_CAP_H)
  tBot:SetPoint("BOTTOM", bar, "BOTTOM", 0, 0)

  local tMid = bar:CreateTexture(nil, "BACKGROUND")
  setAtlas(tMid, "!minimal-scrollbar-track-middle", false)
  tMid:SetPoint("TOPLEFT",     tTop, "BOTTOMLEFT",  0, 0)
  tMid:SetPoint("BOTTOMRIGHT", tBot, "TOPRIGHT",    0, 0)

  -- ---- the thumb -----------------------------------------------------------
  local thumb = CreateFrame("Frame", nil, bar)
  thumb:SetWidth(CB_WIDTH)
  thumb:SetHeight(CB_MIN_THUMB)
  thumb:SetPoint("TOP", bar, "TOP", 0, 0)
  thumb:SetFrameLevel((bar:GetFrameLevel() or 1) + 2)
  thumb:EnableMouse(true)
  thumb._bar = bar
  bar._thumb = thumb

  local thMid = thumb:CreateTexture(nil, "ARTWORK")
  setAtlas(thMid, "minimal-scrollbar-small-thumb-middle", false)
  thMid:SetPoint("TOPLEFT",     thumb, "TOPLEFT",     0,  -CB_CAP_H)
  thMid:SetPoint("BOTTOMRIGHT", thumb, "BOTTOMRIGHT", 0,   CB_CAP_H)
  bar._thumbMid = thMid

  local thTop = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thTop, "minimal-scrollbar-small-thumb-top", true)
  thTop:SetWidth(CB_WIDTH); thTop:SetHeight(CB_CAP_H)
  thTop:SetPoint("TOP", thumb, "TOP", 0, 0)
  bar._thumbTop = thTop

  local thBot = thumb:CreateTexture(nil, "OVERLAY")
  setAtlas(thBot, "minimal-scrollbar-small-thumb-bottom", true)
  thBot:SetWidth(CB_WIDTH); thBot:SetHeight(CB_CAP_H)
  thBot:SetPoint("BOTTOM", thumb, "BOTTOM", 0, 0)
  bar._thumbBot = thBot

  -- drag: while held, follow the cursor (clamped) and write the scroll value.
  thumb:SetScript("OnMouseDown", function(self)
    cbSetThumbState(bar, "-down")
    self._dragging = true
    self:SetScript("OnUpdate", function(s)
      local trackTop = bar:GetTop()
      local trackH   = bar:GetHeight() or 0
      local thumbH   = s:GetHeight() or 0
      if not trackTop then return end
      local _, cursorY = GetCursorPosition()
      local scale = bar:GetEffectiveScale() or 1
      cursorY = cursorY / scale
      local desiredTop = cursorY + (thumbH / 2)
      local maxTop = trackTop
      local minTop = trackTop - (trackH - thumbH)
      if desiredTop > maxTop then desiredTop = maxTop end
      if desiredTop < minTop then desiredTop = minTop end
      s:ClearAllPoints()
      s:SetPoint("TOP", bar, "TOP", 0, -(maxTop - desiredTop))
      cbpOnThumbUpdate(s)
    end)
  end)
  thumb:SetScript("OnMouseUp", function(self)
    self._dragging = false
    self:SetScript("OnUpdate", nil)
    cbSetThumbState(bar, "")
    cbpSync(bar)
  end)
  thumb:SetScript("OnEnter", function() if not thumb._dragging then cbSetThumbState(bar, "-over") end end)
  thumb:SetScript("OnLeave", function() if not thumb._dragging then cbSetThumbState(bar, "") end end)

  -- mouse wheel scrolls by pixels.
  scrollFrame:EnableMouseWheel(true)
  scrollFrame:HookScript("OnMouseWheel", function(self, delta)
    local range = (self.GetVerticalScrollRange and self:GetVerticalScrollRange()) or 0
    if range <= 0 then return end
    local cur = (self.GetVerticalScroll and self:GetVerticalScroll()) or 0
    local step = opts.wheelStep or 30
    local nv = cur - (delta * step)
    if nv < 0 then nv = 0 elseif nv > range then nv = range end
    self:SetVerticalScroll(nv)
  end)

  -- ---- syncing -------------------------------------------------------------
  local function sync() cbpSync(bar) end
  scrollFrame:HookScript("OnVerticalScroll",     sync)
  scrollFrame:HookScript("OnScrollRangeChanged", sync)

  -- Throttled OnUpdate fallback so the thumb tracks (and the bar re-appears when content grows).
  local accum = 0
  scrollFrame:HookScript("OnUpdate", function(self, elapsed)
    accum = accum + (elapsed or 0)
    if accum < 0.1 then return end
    accum = 0
    if not thumb._dragging then cbpSync(bar) end
  end)

  scrollFrame._neCustomBar = bar
  if C_Timer and C_Timer.After then C_Timer.After(0, sync) else sync() end
  return bar
end

-- AttachBottomShadow — DOWNPORT STUB. Needs WowScrollBox callbacks (BaseScrollBoxEvents,
-- RegisterCallback, GetDerivedScrollRange) — retail-only. Returns nil on 3.3.5a.
function NE.scrollbar.AttachBottomShadow(scrollBox, host, opts)
  if not scrollBox then return end
  if not (scrollBox.RegisterCallback and _G.BaseScrollBoxEvents and scrollBox.GetDerivedScrollRange) then
    return   -- DOWNPORT: modern scroll-box infra absent; v1 stub.
  end
  opts = opts or {}
  local holder = CreateFrame("Frame", nil, host or scrollBox)
  holder:SetPoint("BOTTOMLEFT",  scrollBox, "BOTTOMLEFT",  0, 0)
  holder:SetPoint("BOTTOMRIGHT", scrollBox, "BOTTOMRIGHT", 0, 0)
  holder:SetHeight(opts.height or 66)
  holder:SetFrameLevel((scrollBox:GetFrameLevel() or 1) + 5)
  local tex = holder:CreateTexture(nil, "OVERLAY")
  tex:SetAllPoints(holder)
  NE.tex.SetAtlas(tex, "questlog-frame-gradient-bottom", false)
  holder:SetAlpha(0)

  local function update()
    local range = (scrollBox.GetDerivedScrollRange and scrollBox:GetDerivedScrollRange()) or 0
    if range <= 0 then holder:SetAlpha(0); return end
    local pct = (scrollBox.GetScrollPercentage and scrollBox:GetScrollPercentage()) or 0
    local delta = (1 - pct) * range
    holder:SetAlpha(math.max(0, math.min(1, delta / holder:GetHeight())))
  end
  scrollBox:RegisterCallback(BaseScrollBoxEvents.OnScroll, update, holder)
  scrollBox:RegisterCallback(BaseScrollBoxEvents.OnLayout, update, holder)
  if C_Timer and C_Timer.After then C_Timer.After(0, update) end
  holder.Update = update
  return holder
end
