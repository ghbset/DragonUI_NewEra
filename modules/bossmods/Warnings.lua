-- DragonUI_NewEra/modules/bossmods/Warnings.lua — retail's Blizzard_EncounterWarnings: three
-- movable boss-alert TEXT tiers ("Boss Warning - Critical / - Medium / - Minor"), fed by DBM.
--
-- Downport of ReferenceAddons/NewEra/Alerts/BossMods/Warnings.lua. Retail's own frames are
-- per-tier FRIZQT 24/20/18 OUTLINE, centred text flanked by two 30x30 rounded spell icons; newest
-- replaces current (there is NO queue); colour and duration are data-driven. Geometry, fonts and
-- the default positions below are the source's, measured off retail.
--
-- DOWNPORT:
--   * NE.editmode registration (per-tier retail EncounterEvents systemIndex, the settings-int
--     codec, RegisterToggleableFrames) is gone — Register.lua registers each tier with
--     NE.RegisterHUDFrame instead, and the two settings that RENDER are options there.
--   * NE.font.Shadowed does not exist in this addon. It was a workaround for the modern engine
--     drawing no shadow from a per-string SetShadowOffset; on 3.3.5a per-string shadows work, so
--     the font is set directly.
--   * C_Timer.NewTimer's handle is replaced by an expiry stamp checked on the frame's own
--     OnUpdate — one less dependency, and cancelling is an assignment.
--   * Animation:SetTarget does not exist here, so the one swing group that drove the view and both
--     icons becomes one group per region, played together.
--   * MaskTexture is dead → the flanking icons use the texcoord trim + CDM ring (PORT_PLAN §C.3).

local NE = DragonUI_NewEra
local BM = NE.bossmods
if not BM then return end

local L        = NE.L
local setShown = BM.SetShown
local setAtlas = BM.SetAtlas
local cropIcon = BM.CropIcon

local FONT = NE.font and NE.font.FRIZ or "Fonts\\FRIZQT__.TTF"
local DEFAULT_DURATION = 3.0   -- DBM_Announce carries no duration (retail's is data-driven)

-- Geometry/positions/fonts as measured from retail by the source.
local TIERS = {
  { key = "Critical", id = "BossWarningCritical", w = 600, h = 48, fontH = 24, y = -40,
    label = L["Boss Warning - Critical"] },
  { key = "Medium",   id = "BossWarningMedium",   w = 550, h = 36, fontH = 20, y = -90,
    label = L["Boss Warning - Medium"] },
  { key = "Minor",    id = "BossWarningMinor",    w = 500, h = 36, fontH = 18, y = -130,
    label = L["Boss Warning - Minor"] },
}
BM.WARNING_TIERS = TIERS

-- Each tier carries the two retail warning settings that actually render here. Retail's set also
-- has Visibility and TooltipAnchor; a transient text popup has no idle state to gate and no hover
-- target, so — per PORT_PLAN §C.1 — they are not stored rather than stored and ignored.
for _, t in ipairs(TIERS) do
  -- showIcons: the two flanking ability icons. Retail draws them, so they stay ON by default, but
  -- they are the one part of a warning that is pure decoration — the text already says what is
  -- coming — and they are easy to read as clutter beside a line of gold text. Per tier, like every
  -- other warning setting.
  BM.DEFAULTS[t.id] = { iconSize = 100, opacity = 100, scale = 100, showIcons = true }
end

-- The colour keyword → RGB map. DEFAULT is the WoW gold (NORMAL_FONT_COLOR ≈ 1, .82, 0) — every
-- retail boss-warning tier draws in this gold, Critical/Medium/Minor alike. DBM carries no colour
-- keyword, so in practice everything lands on the fallback; the table is what a second backend
-- would feed (BigWigs sends its colour as a string).
local GOLD = { 1, 0.82, 0 }
local COLORS = {
  red = {1, .2, .2}, orange = {1, .55, 0}, yellow = {1, 1, .1}, green = {.3, 1, .3},
  blue = {.3, .7, 1}, cyan = {.3, 1, 1}, purple = {.7, .4, 1}, white = {1, 1, 1},
  gold = GOLD,
}
local function rgb(c)
  if type(c) == "string" then local t = COLORS[c] or GOLD return t[1], t[2], t[3] end
  return GOLD[1], GOLD[2], GOLD[3]
end

local frames = {}   -- key -> frame

local function makeIcon(view)
  local ic = CreateFrame("Frame", nil, view)
  ic:SetSize(30, 30)
  local tex = ic:CreateTexture(nil, "ARTWORK"); tex:SetAllPoints(ic); ic.tex = tex
  cropIcon(tex)   -- DOWNPORT: was a CDM MaskTexture
  local ov = ic:CreateTexture(nil, "OVERLAY")
  setAtlas(ov, "UI-HUD-CoolDownManager-IconOverlay")
  ov:SetPoint("TOPLEFT", tex, "TOPLEFT", -6, 6); ov:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", 6, -7)
  ic:Hide()
  return ic
end

-- Duration is driven by the frame's own OnUpdate rather than a timer handle. `_expires = nil`
-- cancels; the script is only live while the frame is shown, so an idle tier costs nothing.
local function onUpdate(self)
  if not self._expires then
    -- NOTHING IS RUNNING ON THIS TIER, so it should not be on screen.
    --
    -- A tier that lingers shows its two flanking icons with no text between them — reported as
    -- "duplicate icons below the warning", and easy to mistake for DBM's own (it has none: both of
    -- its warning hosts are FontStrings only, DBM-Core.lua:7812 and :8849, zero textures between
    -- them). It gets here when the hide swing's OnFinished does not run, which is the same
    -- animation-end hazard as §C.5c: the fade leaves the view invisible, f:Hide() never happens, and
    -- the icons — child frames, so untouched by the view's alpha — stay lit.
    --
    -- The belt is the invariant rather than a patch on one path: no route out of a warning can leave
    -- a tier half-shown, because this runs every frame the frame is up.
    if not (self._editing or (self.HideAnim and self.HideAnim:IsPlaying())) then
      self.View.LeftIcon:Hide(); self.View.RightIcon:Hide()
      self:Hide()
    end
    return
  end
  -- Belt on the swing's end state, matching the rail's (BossMods.lua _OnUpdate): if the fade-in
  -- group never fired, placeRest never ran, and the warning would sit invisible for its whole
  -- duration. Only while the warning is up and nothing is animating it.
  local view = self.View
  if BM.NeedsAlphaRestore(view) and not (self.ShowAnim:IsPlaying() or self.HideAnim:IsPlaying()) then
    BM.ApplyAlpha(view, 1)
  end
  if GetTime() < self._expires then return end
  self._expires = nil
  if self.HideAnim then BM.StopAnim(self.HideAnim); self.HideAnim:Play() else self:Hide() end
end

local function makeFrame(t)
  local f = CreateFrame("Frame", "NE_" .. t.key .. "EncounterWarnings", UIParent)
  f:SetSize(t.w, t.h)
  f._id, f._key, f._label, f._baseIcon = t.id, t.key, t.label, 30
  f:SetFrameStrata("HIGH")
  -- Self-position to the retail default. Register.lua re-points it from the saved profile at
  -- PLAYER_LOGIN; without this the frame would render unanchored if that has not run yet.
  f:SetPoint("TOP", UIParent, "TOP", 0, t.y)
  f:Hide()
  f:SetScript("OnUpdate", onUpdate)
  if NE.FrameUtil and NE.FrameUtil.PinPixelPerfect then pcall(NE.FrameUtil.PinPixelPerfect, f) end

  local view = CreateFrame("Frame", nil, f)
  view:SetPoint("CENTER")
  view:SetSize(t.w, t.h)
  f.View = view

  local text = view:CreateFontString(nil, "OVERLAY")
  -- Black outline + drop shadow. DOWNPORT: the source needed a shadowed font OBJECT because
  -- per-string SetShadowOffset renders nothing on the modern (TBC 2.5.6) engine. It works on
  -- 3.3.5a, so the string configures itself and there is no font object to register.
  if not text:SetFont(FONT, t.fontH, "OUTLINE") then
    text:SetFontObject("GameFontNormalLarge")
  end
  text:SetShadowColor(0, 0, 0, 1)
  text:SetShadowOffset(1, -1)
  text:SetTextColor(rgb(nil))                  -- default WoW gold; overridden per warning
  text:SetJustifyH("CENTER"); text:SetJustifyV("MIDDLE"); text:SetWordWrap(true)
  text:SetPoint("CENTER")
  view.Text = text

  view.LeftIcon  = makeIcon(view)
  view.RightIcon = makeIcon(view)
  view.LeftIcon:SetPoint("RIGHT", text, "LEFT", -20, 0)    -- retail View.xml flanking offsets
  view.RightIcon:SetPoint("LEFT", text, "RIGHT", 20, 0)

  -- THE FLANKING ICONS ARE CHILD FRAMES OF THE VIEW, so they are part of its alpha tree and every
  -- fade below has to carry them. On 3.3.5a a parent's alpha does not reach child frames
  -- (PORT_PLAN §C.5d), and the swing's alpha animation writes 0 into them without putting it back —
  -- so a bare view:SetAlpha(1) restored the TEXT, which is a region of the view, and left the icons
  -- wherever the animation dropped them. Seen in game as the text and its icons in different
  -- states: icons adrift with no text, or text with no icons. Same fault the rail had, in the file
  -- that did not get re-read when the rail was fixed.
  BM.SetAlphaChildren(view, view.LeftIcon, view.RightIcon)

  -- Retail swing (EncounterWarningsSwingAnimationGroupTemplate): the warning slides UP, scale-pops
  -- and fades in, with the flanking icons spreading in from ±30 to their ±20 rest. Translation and
  -- Scale are both TRANSIENT here (the region snaps back to its anchor and base scale when the
  -- group ends), so we start displaced — low, wide, and 10% large — animate INTO place, and
  -- re-anchor to rest OnFinished, where the end-snap lands with no visible jump.
  -- (Retail's OutBack easing is unavailable on 3.3.5a → OUT smoothing.)
  -- ALPHA IS SET EXPLICITLY AT BOTH ENDS, never left to the animation. On 3.3.5a an alpha animation
  -- does not leave its region at the `to` value and SetToFinalAlpha does not exist — a live
  -- `/nebossmods debug` caught all three tiers as `view: shown=yes alpha=0.00` with correct text and
  -- 23s still on the clock, which is what "the warnings flash briefly" actually was: the swing fading
  -- in over 0.2s and then dropping straight back to invisible. See BossMods.lua's setToFinalAlpha.
  local SWING_Y, SPREAD, POP = 40, 10, 1.1
  local function placeRest()
    BM.ApplyAlpha(view, 1)           -- the end state the fade cannot be trusted to leave — TREE
    view:SetScale(1)
    view:ClearAllPoints();           view:SetPoint("CENTER", f, "CENTER", 0, 0)
    view.LeftIcon:ClearAllPoints();  view.LeftIcon:SetPoint("RIGHT", view.Text, "LEFT", -20, 0)
    view.RightIcon:ClearAllPoints(); view.RightIcon:SetPoint("LEFT", view.Text, "RIGHT", 20, 0)
  end
  local function placeStart()   -- displaced entrance state (low, icons wide, view large, invisible)
    BM.ApplyAlpha(view, 0)
    view:SetScale(POP)
    view:ClearAllPoints();           view:SetPoint("CENTER", f, "CENTER", 0, -SWING_Y)
    view.LeftIcon:ClearAllPoints();  view.LeftIcon:SetPoint("RIGHT", view.Text, "LEFT", -20 - SPREAD, 0)
    view.RightIcon:ClearAllPoints(); view.RightIcon:SetPoint("LEFT", view.Text, "RIGHT", 20 + SPREAD, 0)
  end
  f._placeRest, f._placeStart = placeRest, placeStart

  -- DOWNPORT: one group per animated region (no SetTarget). The VIEW's group owns OnFinished,
  -- since it is the longest and the one that must settle the layout.
  local sin = view:CreateAnimationGroup()
  if sin.SetToFinalAlpha then sin:SetToFinalAlpha(true) end
  BM.AlphaAnim(sin, 0, 1, 0.2, nil, "OUT")
  -- The pop reads 1.1 → 1.0 in retail. placeStart puts the view at 1.1, and 3.3.5a's Scale
  -- animation is a multiplier applied over the duration, so 1/1.1 lands it on 1.0.
  BM.ScaleAnim(sin, 1 / POP, 0.2, nil, "OUT")
  local sv = sin:CreateAnimation("Translation")
  sv:SetOffset(0, SWING_Y); sv:SetDuration(0.35)
  if sv.SetSmoothing then sv:SetSmoothing("OUT") end
  BM.OnFinished(sin, placeRest)   -- settle exactly at rest (cancels the transient snap)
  f.ShowAnim = sin

  local function iconSwing(icon, dx)
    local ag = icon:CreateAnimationGroup()
    local tr = ag:CreateAnimation("Translation")
    tr:SetOffset(dx, 0); tr:SetDuration(0.2)
    if tr.SetStartDelay then tr:SetStartDelay(0.1) end
    if tr.SetSmoothing then tr:SetSmoothing("OUT") end
    return ag
  end
  f.ShowAnimLeft  = iconSwing(view.LeftIcon,   SPREAD)
  f.ShowAnimRight = iconSwing(view.RightIcon, -SPREAD)

  -- Hide swing — fade out + slide down, then hide (retail plays the swing in reverse).
  local sout = view:CreateAnimationGroup()
  if sout.SetToFinalAlpha then sout:SetToFinalAlpha(true) end
  BM.AlphaAnim(sout, 1, 0, 0.2, nil, "IN")
  local ov = sout:CreateAnimation("Translation")
  ov:SetOffset(0, -20); ov:SetDuration(0.2)
  if ov.SetSmoothing then ov:SetSmoothing("IN") end
  BM.OnFinished(sout, function() f:Hide(); BM.ApplyAlpha(view, 1); placeRest() end)
  f.HideAnim = sout

  return f
end

local function frameFor(key)
  if frames[key] then return frames[key] end
  for _, t in ipairs(TIERS) do
    if t.key == key then frames[key] = makeFrame(t); return frames[key] end
  end
end
BM.WarningFrame = frameFor

-- Build all three up front. Register.lua needs the frames to hand to the editor at PLAYER_LOGIN,
-- and they are three empty hidden frames until something fires.
function BM.EnsureWarningFrames()
  for _, t in ipairs(TIERS) do frameFor(t.key) end
  return frames
end

-- Apply the per-tier config (Icon Size, Opacity) to all three warning frames. Called by the option
-- appliers and once at boot.
function BM.ApplyWarningConfig()
  for _, t in ipairs(TIERS) do
    local f = frames[t.key]
    if f then
      local sc = (BM.GetOpt(t.id, "iconSize") or 100) / 100
      local px = (f._baseIcon or 30) * sc
      f.View.LeftIcon:SetSize(px, px); f.View.RightIcon:SetSize(px, px)
      -- Applied live, so the toggle takes effect on a warning that is already up rather than the
      -- next one. Only ever HIDES here: showing is ShowWarning's call, since it needs an icon.
      if BM.GetOpt(t.id, "showIcons") == false then
        f.View.LeftIcon:Hide(); f.View.RightIcon:Hide()
      end
      -- Apply Opacity now only if the frame isn't mid-show (the fade owns alpha during a popup).
      if not (f._editing or (f.ShowAnim and f.ShowAnim:IsPlaying())) then
        f:SetAlpha((BM.GetOpt(t.id, "opacity") or 100) / 100)
      end
      -- Scale (retail's OverallSize), through PinPixelPerfect so the tier stays pixel aligned.
      if NE.FrameUtil and NE.FrameUtil.PinPixelPerfect then
        pcall(NE.FrameUtil.PinPixelPerfect, f, (BM.GetOpt(t.id, "scale") or 100) / 100)
      end
    end
  end
end

-- Public: show a warning in a tier (newest replaces current).
function BM.ShowWarning(key, text, color, icon, duration)
  local f = frameFor(key)
  if not f or not text or text == "" then return end
  if f._editing then return end                      -- don't interrupt the editor preview
  f._expires = nil

  f.View.Text:SetText(text)
  f.View.Text:SetTextColor(rgb(color))
  if icon and BM.GetOpt(f._id, "showIcons") ~= false then
    f.View.LeftIcon.tex:SetTexture(icon);  cropIcon(f.View.LeftIcon.tex);  f.View.LeftIcon:Show()
    f.View.RightIcon.tex:SetTexture(icon); cropIcon(f.View.RightIcon.tex); f.View.RightIcon:Show()
  else
    f.View.LeftIcon:Hide(); f.View.RightIcon:Hide()
  end

  -- Frame alpha carries the Opacity setting; the VIEW fades 0→1 within it during the swing.
  local op = (BM.GetOpt(f._id, "opacity") or 100) / 100
  BM.StopAnim(f.HideAnim)
  f:SetAlpha(op); BM.ApplyAlpha(f.View, 1)
  f:Show()
  f._placeStart()
  BM.StopAnim(f.ShowAnim);      f.ShowAnim:Play()
  BM.StopAnim(f.ShowAnimLeft);  f.ShowAnimLeft:Play()
  BM.StopAnim(f.ShowAnimRight); f.ShowAnimRight:Play()
  local d = (duration and duration > 0) and duration or DEFAULT_DURATION
  f._expires = GetTime() + d
end

-- DBM_Announce → tier (DBMAdapter.lua feeds this). DBM's explicit severity split is isSpecial (a
-- SPECIAL WARNING; regular announces are false) → Critical, mirroring retail's top tier. Among
-- regular announces, the PERSONAL types — "applies to you, or your job", per DBM-Core's own
-- Announce docs: you/stack/bait/moveto/fades → Medium; the rest → Minor. DBM carries no colour
-- keyword, so rgb() falls back to the retail gold.
local DBM_PERSONAL = { you = true, stack = true, bait = true, moveto = true, fades = true }
function BM.ShowWarningFromDBM(isSpecial, text, icon, announceType)
  local tier = isSpecial and "Critical"
            or (type(announceType) == "string" and DBM_PERSONAL[announceType] and "Medium")
            or "Minor"
  BM.ShowWarning(tier, text, nil, icon)
end

-- Editor preview: a sample alert per tier so an otherwise-invisible popup frame is visible and
-- grabbable. `_editing` also blocks live warnings from stomping it.
function BM.SetWarningEditActive(key, editing)
  local f = frameFor(key)
  if not f then return end
  f._editing = editing and true or false
  if f._editing then
    f._expires = nil
    BM.StopAnim(f.ShowAnim); BM.StopAnim(f.HideAnim)
    f._placeRest()
    f.View.Text:SetText(f._label or f._key)
    local ic = "Interface\\Icons\\Spell_Shadow_ShadowBolt"
    local withIcons = BM.GetOpt(f._id, "showIcons") ~= false
    f.View.LeftIcon.tex:SetTexture(ic);  cropIcon(f.View.LeftIcon.tex)
    f.View.RightIcon.tex:SetTexture(ic); cropIcon(f.View.RightIcon.tex)
    setShown(f.View.LeftIcon, withIcons); setShown(f.View.RightIcon, withIcons)
    f.View.Text:SetTextColor(rgb(nil))
    BM.ApplyAlpha(f.View, 1); f:SetAlpha(1); f:Show()
  else
    f:Hide()
    f:SetAlpha((BM.GetOpt(f._id, "opacity") or 100) / 100)   -- restore the configured opacity
  end
end

-- `/nebossmods debug`, warnings half. BM.Dump (BossMods.lua) calls this; `out` prints one prefixed
-- line, and `fmtFrame` / `fmtPoint` render the summaries. Both are PASSED IN rather than reached
-- for: they are locals over there, and a global lookup here would be nil — which is exactly what
-- the first cut of this did, turning the diagnostic into an error at the moment it was needed.
function BM.DumpWarnings(out, fmtFrame, fmtPoint)
  local now = GetTime()
  for _, t in ipairs(TIERS) do
    local f = frames[t.key]
    if not f then
      out("warn " .. t.key .. ": not built")
    else
      out(string.format("warn %-8s %s editing=%s",
        t.key, fmtFrame(f), tostring(f._editing and true or false)))
      -- The whole question for "it flashes": is the expiry stamp sane, and is the VIEW (which the
      -- swing fades and moves inside the frame) still opaque and in place once the swing ended?
      out(string.format("     expires=%s  showAnim=%s hideAnim=%s",
        f._expires and string.format("in %.2fs", f._expires - now) or "nil",
        tostring(f.ShowAnim and f.ShowAnim:IsPlaying()),
        tostring(f.HideAnim and f.HideAnim:IsPlaying())))
      out(string.format("     view: %s text=%q",
        fmtFrame(f.View), tostring(f.View.Text:GetText())))
      -- Text and icons are reported TOGETHER because the fault they exist to catch is the two
      -- disagreeing — on alpha, or on where they sit relative to one another.
      local txt = f.View.Text
      out(string.format("     text: shown=%s alpha=%.2f size=%.0fx%.0f %s",
        txt:IsShown() and "yes" or "no", txt:GetAlpha() or 1,
        txt:GetWidth() or 0, txt:GetHeight() or 0, fmtPoint(txt)))
      for _, side in ipairs({ "LeftIcon", "RightIcon" }) do
        local ic = f.View[side]
        out(string.format("     %-9s %s tex=%s", side .. ":", fmtFrame(ic),
          tostring(ic.tex and ic.tex:GetTexture())))
      end
    end
  end
end

-- Re-pin every tier on resolution / UI-scale change.
function BM.RepinWarnings()
  if not (NE.FrameUtil and NE.FrameUtil.PinPixelPerfect) then return end
  for _, t in ipairs(TIERS) do
    local f = frames[t.key]
    if f then pcall(NE.FrameUtil.PinPixelPerfect, f, (BM.GetOpt(t.id, "scale") or 100) / 100) end
  end
end
