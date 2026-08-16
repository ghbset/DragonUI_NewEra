-- DragonUI_NewEra/modules/bossmods/BossMods.lua — retail-styled boss ability timers over DBM.
--
-- Downport of ReferenceAddons/NewEra/Alerts/BossMods/BossMods.lua (Classic 1.15). See
-- modules/bossmods/PORT_PLAN.md for the full contract; the short version:
--
-- ARCHITECTURE (the Questie pattern, applied to boss encounters):
--   The boss-mod addon owns DETECTION — it drives ability timers off combat-log and spell-cast
--   heuristics, which is the hard part no 3.3.5a ENCOUNTER_* event can give us for legacy raids.
--   We are just another consumer of its event bus, through ONE internal seam (BM.Bus*). The DBM
--   adapter (DBMAdapter.lua) feeds it; DBM's own bars/warnings are visually suppressed there so
--   there is no double-draw (sounds and voice stay DBM's). No DBM → this module never boots.
--
-- Retail parity note, carried over from the source: retail has NO native boss ability-timer bar
-- (those are DBM/BigWigs even on retail), so there is no Blizzard frame to copy 1:1 for the BAR
-- visuals — they are styled to the retail HUD aesthetic using the real UI-HUD-CoolDownManager-Bar
-- atlas. The RAIL, on the other hand, is retail's own Blizzard_EncounterTimeline, art and all.
--
-- DOWNPORT, in summary (each deviation is also marked inline):
--   * ~200 lines of retail Edit Mode settings codec (EM_CODEC / EncounterEvents(22) stored ints)
--     are gone. This addon has no Edit Mode reimplementation to read a layout out of, and no
--     retail layout import to stay compatible with, so settings live in DragonUI's profile and
--     store DISPLAY values — the same choice modules/cooldownviewer made.
--   * NE.editmode → NE.RegisterHUDFrame, wired in Register.lua.
--   * MaskTexture is dead on 3.3.5a → texcoord trim + the CDM overlay ring (§C.3).
--   * Animation:SetTarget does not exist → each animated region owns its own AnimationGroup.
--   * SetShown is banned (CONTRACTS §0) → the local `setShown` helper.
--   * BigWigs is not a supported backend here and Suppress.lua is not ported. BM.Bus* stays the
--     seam it was, so adding one later is a new adapter file and nothing else.

local NE = DragonUI_NewEra
NE.bossmods = NE.bossmods or {}
local BM = NE.bossmods

-- Config — retail "Boss Abilities" Bars view (EncounterTimeline Timer view): a rounded spell icon
-- + a depleting CDM bar. Atlas art = UI-HUD-CoolDownManager-* (Bar/BG/Pip/Overlay), colour =
-- ENCOUNTER_TIMELINE_TIMER_COLOR.
local ROW_W, ROW_H = 240, 28
local ICON_SZ      = 28
local SB_H         = 22       -- depleting bar height
local ROW_GAP      = 3
local TIMER_COLOR  = { 0.80, 0.10, 0.10 }   -- ENCOUNTER_TIMELINE_TIMER_COLOR
local MAX_BARS     = 12

-- Timeline (rail) view — retail's default ViewType=Timeline: icons slide along a vertical rail
-- toward "now". Same event data as the Bars view; BM.viewMode selects which renders.
-- Geometry from EncounterTimelineConstants.lua: CrossAxisExtent 55, icon 35 (TrackEvent),
-- HighlightTime 5. TL_WINDOW is the source's own linear-window adaptation (no track data here).
-- 426 = retail's rail length: line-left 193 + line-right 193 (CalculateShortTrackExtent) + 20+20
-- padding. Retail's cross-axis extent of 55 is deliberately NOT a constant here — see railWidth().
local RAIL_H = 426
local TL_ICON        = 35        -- retail TrackEvent icon size
local TL_WINDOW      = 12        -- visible window (s) ≈ retail Short-track duration
local TL_HIGHLIGHT   = 5         -- pip / imminent mark (retail HighlightTime = 5.0)
local TL_GROW        = 1.35      -- how much larger an event is drawn at the moment it lands
-- THE LAST SECOND. The swell is a smooth ramp, so there is no moment in it that says NOW; this is
-- that moment. Nothing new is drawn for it: the proc glow that has been up since the event went
-- imminent starts BLINKING, which is the cue the player is already watching becoming urgent rather
-- than a second thing to notice. Driven per tick as a pure function of remaining time, for the
-- reason §C.5h gives for the swell.
local TL_URGENT      = 1         -- s remaining at which the glow starts blinking
local FLASH_HZ       = 4         -- blinks per second inside that window
-- Tick dashes: solid horizontal marks crossing the rail at 1/3/5/7/9/11s — the line stays
-- CONTINUOUS and ticks are drawn on top, not cut into it. (This is why neither mask sheet is
-- shipped: the dashes were never a mask in the first place.)
local TICK_SECONDS   = { 1, 3, 5, 7, 9, 11 }
local TICK_W, TICK_H = 10, 2                  -- short dash centred on the 14px line
-- Measured average of the rail-line BLP pixels (alpha-weighted) — the line ART is a dark warm
-- grey, NOT white (its vertexColor is 1,1,1,1 but the texels are dark). Ticks use that so they
-- read as the same material.
local TICK_COLOR     = { 0.30, 0.28, 0.25, 1.0 }
-- Queue (retail's Queued track — a SORTED track above the linear rail for events too far out to
-- time-position; they stack in fixed slots, soonest-expiring nearest the rail, and drop onto the
-- rail once remaining ≤ TL_WINDOW). Slot size = retail SortedEventExtent(38), gap above the rail =
-- retail QueuedTrackDividerOffsetExtra(18).
local QUEUE_MAX  = 5
local QUEUE_SLOT = 38
local QUEUE_GAP  = 18
-- How far the queued track can reach ABOVE the rail's top edge when it is full. Not part of the
-- anchor's size any more (see updateAnchorSize) — kept because it is the answer to "how much room
-- does this need above it", which is a real question for anyone placing the frame.
BM.TIMELINE_QUEUE_EXTENT = QUEUE_GAP + QUEUE_MAX * QUEUE_SLOT   -- 18 + 5*38 = 208
BM.viewMode = BM.viewMode or "timeline"   -- "timeline" (rail) | "bars" (CDM bars)

-- The settings frame id. DOWNPORT: the source used retail's Edit Mode system name ("Boss
-- Abilities") because its settings WERE retail's; ours are our own, so this is just a table key.
local TIMELINE_ID = "BossAbilities"
BM.TIMELINE_ID = TIMELINE_ID

-- Retail's EncounterTimeline preset defaults, normalized to the in-game slider scale exactly as the
-- Cooldown Manager port does. Retail stores Transparency=50 as its FULLY-opaque end of a 50–100
-- slider; we follow CDM's normalized scheme (opacity% direct, 100 = full), so retail's 50 ⇒ our 100.
--
-- DOWNPORT: the source also persisted orientation / iconDirection / flipHorizontal / showSpellName's
-- sibling tooltipAnchor, none of which any renderer read — they existed to round-trip a retail
-- layout export. There is no such export here, so a stored value nothing reads would be worse than
-- no value at all. Only WIRED settings survive.
local BM_DEFAULTS = {
  [TIMELINE_ID] = {
    viewType   = "timeline",   -- "timeline" (rail) | "bars" (CDM bar rows)
    -- These four were stored-and-ignored in the 1.15 source, which marks all of them SHELL. The
    -- owner asked for them, so each is WIRED here rather than persisted for nothing: orientation and
    -- iconDirection drive the rail's axis (see isVertical/nowEdge/along), flipHorizontal mirrors a
    -- bar row, and tooltipAnchor drives a real hover tooltip.
    orientation   = "vertical",   -- "vertical" | "horizontal" — the rail's axis
    iconDirection = "right",      -- which way icons travel: vertical down / horizontal rightward
    flipHorizontal = false,       -- bars view: icon on the right, bar filling the other way
    tooltipAnchor = "cursor",     -- "hidden" | "default" (by the frame) | "cursor"
    iconSize   = 100,          -- %
    opacity    = 100,          -- % (floors at 50 in the options slider, as retail's does)
    background = 0,            -- % — the rail shadow plate / bars plate; retail default is invisible
    padding    = 2,            -- px between bar rows (Bars view)
    barWidth   = 100,          -- % of the depleting bar's width (Bars view)
    visibility = "incombat",   -- "always" | "incombat"
    showTimer  = true,         -- countdown text
    showSpellName = false,     -- ability name beside the rail icon
    -- The action-button proc glow on an imminent event. ON: it replaces retail's masked swirl,
    -- which cannot be drawn here (§C.5e), and without it the ring flash alone is very hard to spot.
    showGlow   = true,
    -- Retail's OverallSize, which NewEra's settings popup carried as its built-in Scale slider
    -- (50-200% == 0.5-2.0x). Applied through PinPixelPerfect's userScale so the frame stays pixel
    -- aligned at any size, which a bare SetScale would not be.
    scale      = 100,
    -- NE-only (no retail mapping): rail primary-axis length in px. Retail auto-sizes the rail to
    -- its event/track content, which we cannot know. 426 = retail's linear-rail length.
    length     = 426,
  },
}
BM.DEFAULTS = BM_DEFAULTS

-- ============================ Settings store =================================================
-- DOWNPORT: replaces BM.GetOpt's read through NE.editmode's stored retail layout + EM_CODEC.
-- Shape and behaviour copied from modules/cooldownviewer/CooldownViewer.lua's getOpt chokepoint:
-- one read path, defaults as the bottom layer, and every write re-applies live.

local function store(create)
  local cfg = NE.Config and NE.Config()
  if not cfg then return nil end
  local bm = cfg.bossmods
  if not bm then
    if not create then return nil end
    bm = {}
    cfg.bossmods = bm
  end
  if type(bm.frames) ~= "table" then
    if not create then return bm end
    bm.frames = {}
  end
  return bm
end
BM.Store = store

function BM.GetOpt(frameID, key)
  local bm = store(false)
  local frame = bm and bm.frames and bm.frames[frameID]
  if frame and frame[key] ~= nil then return frame[key] end
  local defs = BM_DEFAULTS[frameID]
  return defs and defs[key]
end

-- Write one setting and re-apply it live. Warnings.lua registers its own applier for its tiers.
function BM.SetOpt(frameID, key, value)
  local bm = store(true)
  if not (bm and bm.frames) then return end
  bm.frames[frameID] = bm.frames[frameID] or {}
  bm.frames[frameID][key] = value
  if frameID == TIMELINE_ID then
    if BM.ApplyConfig then BM.ApplyConfig() end
  elseif BM.ApplyWarningConfig then
    BM.ApplyWarningConfig()
  end
end

-- Restore one frame's settings to defaults.
function BM.ResetOpts(frameID)
  local bm = store(true)
  if not (bm and bm.frames) then return end
  bm.frames[frameID] = nil
  if frameID == TIMELINE_ID then
    if BM.ApplyConfig then BM.ApplyConfig() end
  elseif BM.ApplyWarningConfig then
    BM.ApplyWarningConfig()
  end
end

local function cfg(key) return BM.GetOpt(TIMELINE_ID, key) end
local function iconScale() return (cfg("iconSize") or 100) / 100 end
-- Rail primary-axis length (px). NE-only "Length" slider; falls back to RAIL_H.
local function railLen() return tonumber(cfg("length")) or RAIL_H end

-- The rail's CROSS-AXIS footprint: the widest thing actually on it, which is an event icon at the
-- current Icon Size (the line is 14 wide and the tick dashes 10).
--
-- DOWNPORT: retail's constant is 55 (EncounterTimelineConstants CrossAxisExtent), and this used it.
-- That number is a track-lane width for a layout system we do not have; here its only visible effect
-- was to make the editor handle half again wider than the icons inside it.
local function railWidth() return math.max(TL_ICON * iconScale(), 14) end

-- The rail's AXIS.
--
-- Orientation and Icon Direction were stored-but-never-read in the 1.15 source, which marks both
-- SHELL: its renderer only ever drew a vertical rail with "now" at the bottom. The owner asked for
-- them, so they are implemented rather than persisted and ignored, and every position on the rail
-- now resolves through these three functions instead of hard-coding BOTTOM and a +y offset.
--
--   isVertical()  Orientation.
--   nowEdge()     which EDGE of the rail is "now" — the point every event slides toward. This is
--                 what Icon Direction picks: retail's setting is left/right, which on a vertical
--                 rail reads as bottom/top, so one stored value means "the way icons travel" in
--                 either orientation.
--   along(dist)   a distance measured along the rail away from now, as (dx, dy) from nowEdge().
local function isVertical() return cfg("orientation") ~= "horizontal" end

local function nowEdge()
  local toward = (cfg("iconDirection") == "left") and "left" or "right"
  if isVertical() then return (toward == "right") and "BOTTOM" or "TOP" end
  return (toward == "right") and "RIGHT" or "LEFT"
end

local function along(dist)
  local edge = nowEdge()
  if     edge == "BOTTOM" then return 0,  dist
  elseif edge == "TOP"    then return 0, -dist
  elseif edge == "LEFT"   then return  dist, 0
  else                         return -dist, 0 end
end


-- ============================ 3.3.5a widget helpers ==========================================
-- DOWNPORT: the four things the source uses that this client does not have. Exposed on BM because
-- EventIcon.lua and Warnings.lua need the same substitutions.

-- CONTRACTS §0: SetShown does not exist on 3.3.5a.
local function setShown(region, on)
  if not region then return end
  if on then region:Show() else region:Hide() end
end
BM.SetShown = setShown

-- SetColorTexture is a later-expansion rename of SetTexture(r,g,b,a). !!!ClassicAPI supplies it,
-- but the fallback costs one branch and keeps the module standalone.
local function colorTexture(tex, r, g, b, a)
  if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end
BM.ColorTexture = colorTexture

-- The rounded-icon look. MaskTexture returns nil here (!!!ClassicAPI declares CreateMaskTexture
-- Private.Void), so we trim the icon's baked border with texcoords and let the CDM IconOverlay ring
-- draw the rounding — exactly the substitution modules/cooldownviewer/ItemMixins.lua makes.
local function cropIcon(tex)
  if not tex then return end
  if NE.tex and NE.tex.CropIcon then NE.tex.CropIcon(tex)
  elseif tex.SetTexCoord then tex:SetTexCoord(0.07, 0.93, 0.07, 0.93) end
end
BM.CropIcon = cropIcon

local function setAtlas(tex, name)
  if NE.tex and NE.tex.SetAtlas then return select(1, pcall(NE.tex.SetAtlas, tex, name)) end
  return false
end
BM.SetAtlas = setAtlas

-- Apply a rail atlas with the right orientation. The art is authored HORIZONTAL, so a horizontal
-- rail takes the plain rect and a vertical one takes the 8-arg (UL, LL, UR, LR) form that rotates
-- it. Re-applied on every layout, because Orientation can change under a live frame.
local function setRailAtlas(tex, atlasName)
  setAtlas(tex, atlasName)
  if not (NE.tex and NE.tex.GetAtlasRect) then return end
  local l, r, tp, bt = NE.tex.GetAtlasRect(atlasName)
  if isVertical() then tex:SetTexCoord(l, tp, r, tp, l, bt, r, bt)
  else                 tex:SetTexCoord(l, r, tp, bt) end
end

-- Alpha animation. DOWNPORT: 3.3.5a's Alpha animation takes a DELTA via SetChange;
-- SetFromAlpha/SetToAlpha are ClassicAPI's polyfill over it, and it only emits the SetChange once
-- BOTH halves are set — hence from-then-to, in that order. Same shape as
-- modules/cooldownviewer/Alerts.lua and modules/talents/Talents.lua.
function BM.AlphaAnim(ag, from, to, dur, order, smoothing, startDelay)
  local a = ag:CreateAnimation("Alpha")
  a:SetDuration(dur)
  if order then a:SetOrder(order) end
  if startDelay and a.SetStartDelay then a:SetStartDelay(startDelay) end
  if smoothing and a.SetSmoothing then a:SetSmoothing(smoothing) end
  if a.SetFromAlpha then a:SetFromAlpha(from); a:SetToAlpha(to)
  elseif a.SetChange then a:SetChange(to - from) end
  return a
end

-- Scale animation. DOWNPORT: two problems with the source's form, both real.
--   1. Animation:SetTarget does not exist on this client (zero occurrences anywhere in the AddOns
--      tree). 3.3.5a animations act on the region that OWNS the group, so a group that scales the
--      IconContainer must be created ON the IconContainer.
--   2. ClassicAPI's SetScaleFrom/SetScaleTo polyfill forwards (to - from) into the native
--      SetScale (WidgetAPI.lua:448-472), which for retail's 1 → 1.1 pop would scale the icon to
--      0.1 — a 90% shrink where a 10% grow was written. So drive the native setter directly with
--      the absolute multiplier, which is what 3.3.5a's Scale animation actually wants.
function BM.ScaleAnim(ag, to, dur, order, smoothing, endDelay)
  local a = ag:CreateAnimation("Scale")
  a:SetOrigin("CENTER", 0, 0)
  a:SetDuration(dur)
  if order then a:SetOrder(order) end
  if smoothing and a.SetSmoothing then a:SetSmoothing(smoothing) end
  if endDelay and a.SetEndDelay then a:SetEndDelay(endDelay) end
  a:SetScale(to, to)
  return a
end

-- DOWNPORT: `AnimationGroup:SetToFinalAlpha` does NOT exist on 3.3.5a, so this is a no-op here and
-- an alpha animation does NOT leave its region at the `to` value. Confirmed live — a
-- `/nebossmods debug` dump on a running feed reported every faded-in region as `shown=yes
-- alpha=0.00`, correctly sized, textured, anchored, and completely invisible. The rail line and the
-- warning frames rendered, because neither is animated; everything that fades did not.
--
-- So NOTHING in this module infers a final alpha from an animation. The call is left in for the
-- client that does implement it, and every fade sets its own end state explicitly — see
-- BM.FadeIn below. The same conclusion is recorded in modules/cooldownviewer/Alerts.lua:328
-- ("the animation moves it by -0.55 from wherever it happens to be"), which sets alpha by hand for
-- the same reason.
local function setToFinalAlpha(ag)
  if ag.SetToFinalAlpha then ag:SetToFinalAlpha(true) end
  return ag
end

-- THE Stop for this module. DOWNPORT, and a crash rather than a cosmetic difference:
--
--   AnimationGroup:Stop() called from inside that group's OWN OnFinished handler is an ACCESS
--   VIOLATION on 3.3.5a — ERROR #132, 0xC0000005 reading 0x00000034, reported by the client as
--   `Current Addon function: <unnamed>:Stop`.
--
-- The 1.15 source walks straight into it: finishBar hands `releaseBar` to the group as its
-- OnFinished payload, and releaseBar's first act is to Stop every group on the bar — including the
-- one currently firing. Era's engine tolerates the re-entry; this one frees the object and then
-- follows the pointer.
--
-- Two guards, because either alone leaves a hole. `_neFinishing` is set for the duration of a
-- handler, so a self-Stop is refused outright no matter what the widget reports; the IsPlaying
-- check covers every other path and makes stopping an idle group free.
function BM.StopAnim(ag)
  if not ag then return end
  if ag._neFinishing then return end                       -- inside this group's own OnFinished
  if ag.IsPlaying and not ag:IsPlaying() then return end    -- nothing to stop
  ag:Stop()
end
local stopAnim = BM.StopAnim

-- Set alpha across a frame AND its child frames.
--
-- DOWNPORT, and the second half of the alpha story: on 3.3.5a a frame's alpha is NOT inherited by
-- its children at render time — every frame carries its own — and the alpha ANIMATION that fades a
-- parent writes 0 into the children as it plays, without ever putting it back. Restoring the parent
-- alone leaves them at 0.
--
-- Confirmed live, after the first fix had already landed:
--     track:  alpha=1.00   ← restored
--     cont:   alpha=0.00   ← child frame, still invisible
--     cdHost: alpha=0.00   ← child frame, still invisible
-- which is exactly why the trail (a texture ON the track) drew while the icon and the countdown
-- (both child FRAMES) did not. A frame that owns child frames must therefore be faded as a tree.
local function applyAlpha(region, a)
  region:SetAlpha(a)
  local kids = region._neAlphaKids
  if not kids then return end
  for _, kid in ipairs(kids) do
    if kid then kid:SetAlpha(a) end
  end
end
BM.ApplyAlpha = applyAlpha

-- Declare which child frames a fade must carry with it. Called once, at build time.
function BM.SetAlphaChildren(frame, ...)
  frame._neAlphaKids = { ... }
end

-- Play a 0 → 1 fade and GUARANTEE it ends visible.
--
-- The animation supplies the flourish; the two alpha writes supply the result. `region` starts at 0
-- so there is a real fade to watch, and the group's OnFinished puts it — and its declared children —
-- at 1, because on this client the animation will not (see setToFinalAlpha above). If the group
-- never runs at all, the belt in _OnUpdate restores it within a frame, so the worst case is a
-- missing fade, never a missing event.
function BM.FadeIn(region, ag, alsoOnFinished)
  BM.OnFinished(ag, function()
    if alsoOnFinished then alsoOnFinished() end
    applyAlpha(region, 1)
  end)
  return ag
end

-- Start a fade that BM.FadeIn set up. Separate from the wiring because it runs per event, not per
-- frame build.
function BM.PlayFadeIn(region, ag)
  applyAlpha(region, 0)
  BM.StopAnim(ag)
  ag:Play()
end

-- True when a faded tree is not fully opaque — the belt's test, covering the children a restore of
-- the parent alone would miss.
local function needsAlphaRestore(region)
  if region:GetAlpha() < 1 then return true end
  for _, kid in ipairs(region._neAlphaKids or {}) do
    if kid and kid:GetAlpha() < 1 then return true end
  end
  return false
end
BM.NeedsAlphaRestore = needsAlphaRestore

-- Install an OnFinished handler that is safe to call the animation API from. Everything the module
-- runs on animation completion goes through here, so the `_neFinishing` guard above is never the
-- caller's job to remember.
function BM.OnFinished(ag, fn)
  ag:SetScript("OnFinished", function(self)
    self._neFinishing = true
    local ok, err = pcall(fn, self)
    self._neFinishing = nil
    -- A raise inside an animation callback is swallowed by the client on some paths; surface it
    -- rather than leaving a bar stuck mid-fade with no sign of why.
    if not ok and NE.Log then NE.Log("BOSSMODS", "OnFinished error: " .. tostring(err)) end
  end)
  return ag
end

local sizeBar, updateAnchorSize   -- forward decls (called before their definitions)

-- Retail timer text = SecondsFormatter OneLetter, 2 desired units, min Seconds
-- (EncounterTimelineConstants.lua:216): <1s → "0.4"; else "45s" / "1m30s" / "1h2m".
-- DOWNPORT: the source called NE.cd.FormatBarTime and carried an inline copy as a fallback. That
-- fallback would have BEEN the real path here — core/CooldownNumbers.lua only exposed FormatTime,
-- which is the bare cooldown-SWIPE format ("45", "2m"), not this one. FormatBarTime was added to
-- core alongside it rather than duplicating a formatter into a module.
local function fmtTime(t)
  if NE.cd and NE.cd.FormatBarTime then return NE.cd.FormatBarTime(t) end
  if t < 1 then return string.format("%.1f", t) end
  if t < 60 then return string.format("%ds", t) end
  local m, s = math.floor(t / 60), math.floor(t % 60)
  return s > 0 and string.format("%dm%ds", m, s) or string.format("%dm", m)
end

-- ============================ Anchor + driver ================================================
-- One OnUpdate runs only while there are live bars.

local anchor, rail
local activeCount = 0
-- active[owner] = { [key] = bar }  ;  list = flat array of live bars for sort/relayout
local active, list = {}, {}
local pool = {}
-- Bars that have left `list` but are still playing their finish/cancel fade. They are not live work
-- and nothing counts them as such — but the anchor has to stay up for them. See refreshDriver.
local finishing = {}

local function ensureAnchor()
  if anchor then return anchor end
  anchor = CreateFrame("Frame", "NE_BossModsAnchor", UIParent)
  anchor:SetSize(ROW_W, ROW_H)
  -- Fallback position only. Register.lua hands the frame to DragonUI's editor, which re-points it
  -- from the saved profile at PLAYER_LOGIN; this keeps it on screen if that has not run yet.
  anchor:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOM", -457, 336)
  if NE.FrameUtil and NE.FrameUtil.PinPixelPerfect then
    pcall(NE.FrameUtil.PinPixelPerfect, anchor)
  end

  -- The Bars view's backing plate, and the other half of the Background slider.
  --
  -- DOWNPORT-adjacent: the source shipped `damagemeters-background` and described it as exactly this
  -- — then never drew it, so Background moved the rail's shadow plate and did nothing at all in Bars
  -- view. Same art and the same slider, now actually behind the rows. Sized in layoutBarsPlate,
  -- because the rows stack DOWN out of the anchor and their extent is only known after a relayout.
  anchor.barsPlate = anchor:CreateTexture(nil, "BACKGROUND")
  setAtlas(anchor.barsPlate, "damagemeters-background")
  anchor.barsPlate:Hide()

  anchor:SetScript("OnUpdate", function() BM._OnUpdate() end)
  updateAnchorSize()   -- size to the active view (Timeline → narrow/tall, so the handle is vertical)
  anchor:Hide()        -- shown by refreshDriver when work exists
  return anchor
end

-- Cover the stacked rows, plus a small margin. Retail ships Background at 0, so by default this is
-- an invisible texture that costs one SetSize per relayout.
local PLATE_INSET = 6
local function layoutBarsPlate()
  local plate = anchor and anchor.barsPlate
  if not plate then return end
  if BM.viewMode ~= "bars" or #list == 0 then plate:Hide() return end
  local gap = cfg("padding") or ROW_GAP
  local w, h = 0, 0
  for i, bar in ipairs(list) do
    w = math.max(w, bar:GetWidth() or ROW_W)
    h = h + (bar:GetHeight() or ROW_H) + (i > 1 and gap or 0)
  end
  plate:ClearAllPoints()
  plate:SetPoint("TOPLEFT", anchor, "TOPLEFT", -PLATE_INSET, PLATE_INSET)
  plate:SetSize(w + PLATE_INSET * 2, h + PLATE_INSET * 2)
  plate:SetAlpha((cfg("background") or 0) / 100)
  plate:Show()
end

-- Size the movable anchor to the ACTIVE view's footprint so its editor drag handle matches what is
-- on screen: in Timeline view the anchor is the narrow vertical rail; in Bars view it is the bar row
-- width. NE.RegisterHUDFrame mirrors this size onto the draggable handle via the content frame's
-- OnSizeChanged, so the grab target follows a view swap or a Length change with no re-registration.
--
-- DOWNPORT: this reserved the queued track's full extent (five slots, 208px) above the rail so the
-- handle would wrap queued icons, since DragonUI's editor has no editModeSelectionTopOffset. Seen in
-- game that was plainly wrong: the queue is rarely more than a slot or two deep, so the handle stood
-- a third taller than anything drawn in it, and half again wider. The box now bounds the RAIL, which
-- is the part that is always there. Queued icons overhang the top — they still drag with it, being
-- children of this frame, and an honest box beats a box that covers space nothing occupies.
function updateAnchorSize()
  if not anchor then return end
  if BM.viewMode == "timeline" then
    if isVertical() then anchor:SetSize(railWidth(), railLen())
    else                 anchor:SetSize(railLen(), railWidth()) end
  else
    -- Bars view: one row, at the row's ACTUAL size — both sliders move it, so a fixed 240x28 handle
    -- stopped matching the moment either was touched. Same arithmetic as sizeBar.
    local sc = iconScale()
    local ip = ICON_SZ * sc
    local bw = (cfg("barWidth") or 100) / 100
    anchor:SetSize(ip + 4 + (ROW_W - ICON_SZ - 4) * bw, math.max(ROW_H, ip))
  end
end

local function refreshDriver()
  if not anchor then return end
  -- Visibility setting (retail: Always / In Encounter): "always" keeps the HUD (and the empty rail)
  -- up even with no live bars; "incombat" only while there is work. The editor always shows.
  --
  -- `#finishing` counts as work, and has to. finishBar detaches its bar immediately, so the LAST
  -- event of a fight drops activeCount to 0 while its fade is still playing — and an animation on a
  -- hidden frame does not advance, so hiding here would strand it: no OnFinished, no release, the
  -- bar never back in the pool and the last ability vanishing instead of popping.
  local always = cfg("visibility") == "always"
  local work = activeCount > 0 or #finishing > 0 or BM._editing or always
  setShown(anchor, work)
  if rail then
    setShown(rail, work and BM.viewMode == "timeline")
  end
end
BM.RefreshDriver = refreshDriver

-- ============================ Bars view ======================================================

local function makeBar()
  -- A row: rounded spell icon on the left + a depleting CDM bar on the right (retail's
  -- EncounterTimeline Timer-view event row).
  local bar = CreateFrame("Frame", nil, anchor)
  bar:SetSize(ROW_W, ROW_H)

  bar.icon = bar:CreateTexture(nil, "ARTWORK")
  bar.icon:SetSize(ICON_SZ, ICON_SZ)
  bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
  cropIcon(bar.icon)   -- DOWNPORT: was a CDM MaskTexture (§C.3)
  bar.iconOverlay = bar:CreateTexture(nil, "OVERLAY")
  setAtlas(bar.iconOverlay, "UI-HUD-CoolDownManager-IconOverlay")
  bar.iconOverlay:SetPoint("TOPLEFT", bar.icon, "TOPLEFT", -6, 6)
  bar.iconOverlay:SetPoint("BOTTOMRIGHT", bar.icon, "BOTTOMRIGHT", 6, -7)

  -- Depleting bar (right of the icon).
  local sb = CreateFrame("StatusBar", nil, bar)
  sb:SetHeight(SB_H)
  sb:SetMinMaxValues(0, 1)
  -- DOWNPORT: StatusBar:SetReverseFill is not present on every 3.3.5a build. Stubbed rather than
  -- guarded at each call site — without it a flipped bar still mirrors, it just drains from the
  -- same end as an unflipped one, which is a cosmetic loss rather than a broken layout.
  if not sb.SetReverseFill then sb.SetReverseFill = function() end end
  bar.sb = sb

  bar.barBG = sb:CreateTexture(nil, "BACKGROUND")
  setAtlas(bar.barBG, "UI-HUD-CoolDownManager-Bar-BG")
  bar.barBG:SetPoint("TOPLEFT", sb, "TOPLEFT", -2, 6)
  bar.barBG:SetPoint("BOTTOMRIGHT", sb, "BOTTOMRIGHT", 6, -6)

  if NE.tex and NE.tex.SetAtlasOnStatusBar then
    pcall(NE.tex.SetAtlasOnStatusBar, sb, "UI-HUD-CoolDownManager-Bar")
  else
    sb:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  end
  sb:SetStatusBarColor(TIMER_COLOR[1], TIMER_COLOR[2], TIMER_COLOR[3])

  -- Spark rides the leading edge of the fill — anchored to the fill texture's RIGHT (retail
  -- UpdateTimerSparkLayout:655), so it auto-tracks SetValue with no per-frame math.
  -- DOWNPORT: NE.tex.SetAtlasOnStatusBar alpha-0s the engine's own fill texture and draws the
  -- atlas as `_neOverlay` instead (core/Texture.lua:277-320). The engine texture keeps its
  -- geometry, but the VISIBLE leading edge is the overlay's, so anchor to that when it exists.
  bar.spark = sb:CreateTexture(nil, "OVERLAY")
  setAtlas(bar.spark, "UI-HUD-CoolDownManager-Bar-Pip")
  bar.spark:SetBlendMode("ADD")
  bar.spark:SetSize(10, SB_H + 16)
  local fillTex = sb._neOverlay or sb:GetStatusBarTexture()
  if fillTex then bar.spark:SetPoint("CENTER", fillTex, "RIGHT", 0, 0) end

  -- Duration (Name) text — both NumberFontNormal, LEFT-justified, per retail
  -- EncounterTimelineTimerEvent: Duration RIGHT→bar.RIGHT(-5); Name LEFT→bar.LEFT(+5),
  -- RIGHT→Duration.LEFT(-10). (timeText first so label can anchor to it.)
  -- Both carry a shadow under the NumberFont outline, for the reason applyCountdownFont records:
  -- these sit on the bar's own fill, which is a bright red gradient with a spark riding it.
  bar.timeText = sb:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  bar.timeText:SetJustifyH("LEFT")
  bar.timeText:SetWordWrap(false)
  bar.timeText:SetShadowColor(0, 0, 0, 1)
  bar.timeText:SetShadowOffset(1, -1)
  bar.timeText:SetPoint("RIGHT", sb, "RIGHT", -5, 2)

  bar.label = sb:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  bar.label:SetJustifyH("LEFT")
  bar.label:SetJustifyV("MIDDLE")
  bar.label:SetWordWrap(false)
  bar.label:SetShadowColor(0, 0, 0, 1)
  bar.label:SetShadowOffset(1, -1)
  bar.label:SetPoint("LEFT", sb, "LEFT", 5, 0)
  bar.label:SetPoint("RIGHT", bar.timeText, "LEFT", -10, 0)

  -- Finish (reached now) / cancel (stopped early) — retail Timer-event Finish = fade + slide-left;
  -- Cancel = fade. Played by finishBar before the bar is released (OnFinished → _done).
  -- DOWNPORT: no SetTarget — both animations act on `bar`, which owns the group, which is what the
  -- source's SetTarget(bar) asked for anyway.
  bar.FinishAnim = setToFinalAlpha(bar:CreateAnimationGroup())
  BM.AlphaAnim(bar.FinishAnim, 1, 0, 0.30, nil, "IN")
  local slide = bar.FinishAnim:CreateAnimation("Translation")
  slide:SetOffset(-40, 0); slide:SetDuration(0.30)
  if slide.SetSmoothing then slide:SetSmoothing("IN") end
  BM.OnFinished(bar.FinishAnim, function(self) if self._done then self._done() end end)

  bar.CancelAnim = setToFinalAlpha(bar:CreateAnimationGroup())
  BM.AlphaAnim(bar.CancelAnim, 1, 0, 0.20, nil, "IN")
  BM.OnFinished(bar.CancelAnim, function(self) if self._done then self._done() end end)

  -- Hover target for the Tooltips setting; see the note on the track's, in ensureTrack.
  bar:EnableMouse(true)
  bar:SetScript("OnEnter", function(self) BM.ShowBarTooltip(self, self._bar) end)
  bar:SetScript("OnLeave", function() BM.HideBarTooltip() end)

  sizeBar(bar)
  return bar
end

-- Apply the size-class config (Icon Size, Bar Width, Show Timer) to a Bars-view row: the icon
-- scales with Icon Size, the depleting bar's width scales with Bar Width, and the row resizes to
-- fit. (Timeline-view sizing is the track IconContainer scale — see ensureTrack / BM.ApplyConfig.)
function sizeBar(bar)
  local sc      = iconScale()
  local ip      = ICON_SZ * sc
  local bw      = (cfg("barWidth") or 100) / 100
  local baseBar = ROW_W - ICON_SZ - 4              -- the depleting-bar portion at 100%
  bar.icon:SetSize(ip, ip)
  bar:SetSize(ip + 4 + baseBar * bw, math.max(ROW_H, ip))
  bar.sb:SetHeight(SB_H * sc)
  setShown(bar.timeText, cfg("showTimer") ~= false)

  -- FLIP HORIZONTALLY (the fourth setting the 1.15 source left as SHELL). Mirrors the row: the icon
  -- moves to the right edge, the depleting bar runs the other way, and the label and countdown swap
  -- with it so the text still reads outward from the icon. Re-anchored rather than re-built, so it
  -- can be toggled on a live frame.
  local flipped = cfg("flipHorizontal") == true
  bar.icon:ClearAllPoints()
  bar.sb:ClearAllPoints()
  bar.timeText:ClearAllPoints()
  bar.label:ClearAllPoints()
  if flipped then
    bar.icon:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.sb:SetPoint("RIGHT", bar.icon, "LEFT", -4, 0)
    bar.sb:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.sb:SetReverseFill(true)
    bar.timeText:SetPoint("LEFT", bar.sb, "LEFT", 5, 2)
    bar.label:SetPoint("RIGHT", bar.sb, "RIGHT", -5, 0)
    bar.label:SetPoint("LEFT", bar.timeText, "RIGHT", 10, 0)
    bar.label:SetJustifyH("RIGHT")
  else
    bar.icon:SetPoint("LEFT", bar, "LEFT", 0, 0)
    bar.sb:SetPoint("LEFT", bar.icon, "RIGHT", 4, 0)
    bar.sb:SetPoint("RIGHT", bar, "RIGHT", 0, 0)
    bar.sb:SetReverseFill(false)
    bar.timeText:SetPoint("RIGHT", bar.sb, "RIGHT", -5, 2)
    bar.label:SetPoint("LEFT", bar.sb, "LEFT", 5, 0)
    bar.label:SetPoint("RIGHT", bar.timeText, "LEFT", -10, 0)
    bar.label:SetJustifyH("LEFT")
  end
end

-- Stop the rail icon's pulse AND put its scale back. DOWNPORT: on 3.3.5a a Scale animation drives
-- the owning region's scale directly, so stopping mid-pulse can leave the container at 1.1 or 0.9.
-- Every Stop goes through here so the icon can never drift away from its Icon Size setting.
-- The imminent proc glow (EventIcon.lua's SetImminent), gated on the setting. Routed through one
-- helper because a track is POOLED: a glow left running is inherited by whatever event recycles the
-- frame next, which would light up an ability that is nowhere near due.
-- The GLOW's alpha, as a pure function of time to go: full outside the urgent window, blinking at
-- FLASH_HZ inside it. Keyed on `remaining` rather than on GetTime, so every icon that enters the
-- window blinks the same way and any interruption self-corrects on the next frame.
local function flashAlpha(remaining)
  if not remaining or remaining > TL_URGENT then return 1 end
  return ((remaining * FLASH_HZ) % 1) < 0.5 and 1 or 0.15
end

-- `remaining` is optional: every "switch it off" caller omits it, which reads as not urgent and
-- restores full alpha — including the release path, where a pooled frame must carry neither a live
-- glow nor a dimmed one.
local function setImminent(track, on, remaining)
  local ic = track and track.IconContainer
  if not (ic and ic.SetImminent) then return end
  local want = (on and cfg("showGlow") ~= false) and true or false
  ic:SetImminent(want)
  if ic.SetFlash then ic:SetFlash(want and flashAlpha(remaining) or 1) end
end

-- How much larger an event is drawn, given the time left on it. 1.0 until it enters the highlight
-- window, then swelling smoothly to TL_GROW as it reaches "now".
local function growthScale(remaining)
  if not remaining or remaining >= TL_HIGHLIGHT then return 1 end
  if remaining <= 0 then return TL_GROW end
  return 1 + (TL_GROW - 1) * (1 - remaining / TL_HIGHLIGHT)
end

-- The icon's scale is Icon Size times that swell. One place, so the two can never disagree.
local function applyTrackScale(track, remaining)
  if not (track and track.IconContainer) then return end
  track.IconContainer:SetScale(iconScale() * growthScale(remaining))
end

-- The countdown reads over SPELL ART — the hardest background there is: busy, arbitrary, and often
-- brightest exactly where the digits are. Two things were wrong with leaving it a bare
-- NumberFontNormal fontstring, and neither is a missing cooldown swipe (the rail has none by design:
-- an event's POSITION is its countdown, and a swipe over the art would be a second one).
--
--   * It never moved with Icon Size. The track frame is always TL_ICON square and the icon assembly
--     is SCALED past it, so at 200% you got a 70px icon carrying the same 14px number.
--   * A thin outline is all the NumberFont family carries. Over spell art, at this frame's effective
--     scale, that is not enough separation on its own.
--
-- So the size follows the icon's drawn size, and a drop shadow goes under the outline — the same
-- pairing Warnings.lua uses to put text over the world.
local CD_FONT_RATIO = 0.46            -- of the drawn icon: ~16px at the default 35
local CD_FONT_MIN, CD_FONT_MAX = 9, 40

local function applyCountdownFont(track)
  local cd = track and track.cd
  if not cd then return end
  local size = TL_ICON * iconScale() * CD_FONT_RATIO
  size = math.max(CD_FONT_MIN, math.min(CD_FONT_MAX, size))
  -- The FACE comes from the client's own number font rather than a named file: it is the narrow one
  -- Blizzard draws cooldown digits with, and it is whatever this client actually ships.
  local path = _G.NumberFontNormal and _G.NumberFontNormal:GetFont()
  if path then cd:SetFont(path, size, "OUTLINE") end
  -- Checked by GETting rather than by SetFont's return, which is not dependable across builds. A
  -- fontstring with no font draws nothing at all, so this fallback is the difference between a
  -- smaller countdown and no countdown.
  if not cd:GetFont() then cd:SetFontObject("NumberFontNormal") end
  cd:SetShadowColor(0, 0, 0, 1)
  cd:SetShadowOffset(1, -1)
end

-- Back to rest size. Named for what it does now that the pulse is gone; every former stopPulse call
-- site wanted exactly this.
local function stopPulse(track)
  if not (track and track.IconContainer) then return end
  track.IconContainer:SetScale(iconScale())
end

-- NOTE: this runs FROM the finish/cancel OnFinished handler, which is why every Stop below goes
-- through stopAnim — see the crash note on BM.StopAnim.
local function releaseBar(bar)
  if not bar then return end
  bar._finishing = nil
  bar._previewFinishing = nil
  stopAnim(bar.FinishAnim)
  stopAnim(bar.CancelAnim)
  bar:Hide(); bar:SetAlpha(1)              -- finish/cancel faded it; SetToFinalAlpha left it 0
  if bar.track then
    local t = bar.track
    stopPulse(t)
    setImminent(t, false)        -- pooled frame: never hand a live glow to the next event
    t:Hide(); applyAlpha(t, 1)   -- the tree, not just the track (see applyAlpha)
    stopAnim(t.FinishAnim)
    stopAnim(t.FinishScale)
    stopAnim(t.CancelAnim)
    if t.IconContainer then t.IconContainer:SetScale(iconScale()) end   -- undo any finish pop
    -- Reset queue styling so a pooled track is reused clean (e.g. released while still queued).
    if t._queued then
      t._queued = false
      if t.IconContainer and t.IconContainer.SetEventState then t.IconContainer:SetEventState("normal") end
      if t.trail then t.trail:Show() end
    end
    t._highlighted = false
  end
  bar:ClearAllPoints()
  bar._endTime, bar._module, bar._text = nil, nil, nil
  bar._label, bar._paused, bar._pausedRemaining = nil, nil, nil
  bar._preview, bar._previewDur = nil, nil
  pool[#pool + 1] = bar
end

-- Remove a bar from the active maps (does not release — caller decides).
local function detach(bar)
  local m = active[bar._module]
  if m and m[bar._text] == bar then m[bar._text] = nil end
  for i = #list, 1, -1 do
    if list[i] == bar then table.remove(list, i) break end
  end
  activeCount = #list
end

-- ============================ Timeline (rail) view ===========================================
-- A vertical rail with the highlight pip; each event's icon rides it, its height set by remaining
-- time in _OnUpdate. Same event objects as the Bars view.

-- (Re)position the rail's continuous line halves, the tick dashes, and the pip for the current
-- Length. Pieces + ticks are stored as PURE fractions of the rail length so they re-point at any
-- Length.
local function layoutRail()
  if not rail then return end
  local len, w = railLen(), railWidth()
  local vert, edge = isVertical(), nowEdge()

  -- The shadow plate is a different atlas per axis; the sheet ships both.
  if rail.plate then
    setAtlas(rail.plate, vert and "combattimeline-line-shadow-vertical" or "combattimeline-line-shadow")
  end

  -- Each half is CENTRED at its midpoint fraction and sized explicitly rather than pinned by two
  -- opposite edges: one expression then covers both axes, where the two-point form needed TOP and
  -- BOTTOM by name.
  for _, p in ipairs(rail._pieces or {}) do
    local span = (p.topF - p.botF) * len
    setShown(p.tex, span > 0)
    setRailAtlas(p.tex, p.atlas)
    if vert then p.tex:SetSize(14, span) else p.tex:SetSize(span, 14) end
    p.tex:ClearAllPoints()
    p.tex:SetPoint("CENTER", rail, edge, along(((p.topF + p.botF) * 0.5) * len))
  end

  -- Dashes CROSS the line, so their long side is whichever axis the rail is not.
  for _, tk in ipairs(rail._ticks or {}) do
    if vert then tk.tex:SetSize(TICK_W, TICK_H) else tk.tex:SetSize(TICK_H, TICK_W) end
    tk.tex:ClearAllPoints()
    tk.tex:SetPoint("CENTER", rail, edge, along(tk.frac * len))
  end

  if rail.pip then
    rail.pip:ClearAllPoints()
    rail.pip:SetPoint("CENTER", rail, edge, along(len * (TL_HIGHLIGHT / TL_WINDOW)))
  end

  if rail.qdivider then  -- seam at the far end, where the queue stack begins
    if vert then rail.qdivider:SetSize(w, 10) else rail.qdivider:SetSize(10, w) end
    rail.qdivider:ClearAllPoints()
    rail.qdivider:SetPoint("CENTER", rail, edge, along(len + QUEUE_GAP * 0.5))
  end
end

-- The event trail, per axis. It streaks behind the icon, so which side that is depends on the
-- direction of travel — the opposite of nowEdge(). Sized and rotated to match: the art is a 32x2
-- horizontal strip, so a vertical rail rotates it.
local TRAIL_LONG, TRAIL_THIN, TRAIL_INSET = 44, 2, -10
function layoutTrail(track)
  local t = track and track.trail
  if not t then return end
  local edge = nowEdge()
  -- The trail hangs off the side the icon came FROM.
  local behind = (edge == "BOTTOM" and "TOP") or (edge == "TOP" and "BOTTOM")
              or (edge == "LEFT" and "RIGHT") or "LEFT"
  local opposite = (behind == "TOP" and "BOTTOM") or (behind == "BOTTOM" and "TOP")
                or (behind == "LEFT" and "RIGHT") or "LEFT"
  setRailAtlas(t, "combattimeline-line-icontrail")
  if isVertical() then t:SetSize(TRAIL_THIN, TRAIL_LONG) else t:SetSize(TRAIL_LONG, TRAIL_THIN) end
  t:ClearAllPoints()
  if isVertical() then
    t:SetPoint(opposite, track, behind, 0, behind == "TOP" and TRAIL_INSET or -TRAIL_INSET)
  else
    t:SetPoint(opposite, track, behind, behind == "RIGHT" and TRAIL_INSET or -TRAIL_INSET, 0)
  end
end

local function ensureRail()
  if rail then return rail end
  ensureAnchor()
  rail = CreateFrame("Frame", nil, anchor)
  -- The rail IS the anchor's footprint — updateAnchorSize sizes the anchor to it, per axis. Every
  -- position below is expressed against nowEdge(), the end events slide toward.
  rail:SetAllPoints(anchor)

  -- Shadow plate (retail Background = alpha 0 by default). Its atlas is chosen per axis in
  -- layoutRail, which runs before this frame is ever shown.
  local bg = rail:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(rail); rail.plate = bg
  bg:SetAlpha((cfg("background") or 0) / 100)

  -- The rail LINE: line-right (bottom half, seam→now) + line-left (top half, far→seam), 14 wide,
  -- rotated to vertical via the 8-arg SetTexCoord. The line is CONTINUOUS — one texture per half,
  -- no cuts; the ticks below are drawn ON TOP. Stored as TOP/BOTTOM fractions of the rail length so
  -- layoutRail() re-points them for any Length.
  -- The atlas NAME is recorded with each piece: Orientation can change on a live frame, and the
  -- texcoords have to be re-derived for the new axis (setRailAtlas, called from layoutRail).
  local pieces = {}
  local function half(atlasName, topF, botF)
    local t = rail:CreateTexture(nil, "ARTWORK")
    pieces[#pieces + 1] = { tex = t, atlas = atlasName, topF = topF, botF = botF }
    return t
  end
  half("combattimeline-line-right", 0.5, 0.0)   -- near half: centre seam → now (frac 0)
  half("combattimeline-line-left",  1.0, 0.5)   -- far half: far end (frac 1) → centre seam
  rail._pieces = pieces

  -- Solid horizontal tick dashes ON TOP of the line at 1/3/5/7/9/11s (OVERLAY > the ARTWORK line).
  rail._ticks = {}
  for _, s in ipairs(TICK_SECONDS) do
    local tk = rail:CreateTexture(nil, "OVERLAY")
    colorTexture(tk, TICK_COLOR[1], TICK_COLOR[2], TICK_COLOR[3], TICK_COLOR[4])
    rail._ticks[#rail._ticks + 1] = { tex = tk, frac = s / TL_WINDOW }   -- sized per axis in layoutRail
  end

  rail.pip = rail:CreateTexture(nil, "OVERLAY")
  setAtlas(rail.pip, "combattimeline-pip")
  rail.pip:SetSize(16, 16)

  -- Queue divider — a horizontal seam above the rail top where the queue stack begins. Hidden
  -- until something is queued (set in layoutQueue).
  rail.qdivider = rail:CreateTexture(nil, "ARTWORK")
  setAtlas(rail.qdivider, "combattimeline-cooldown-divider")
  rail.qdivider:Hide()   -- sized and placed per axis in layoutRail

  layoutRail()      -- position the pieces + pip + divider for the current Length
  rail:Hide()
  return rail
end

local function ensureTrack(bar)
  if bar.track then return bar.track end
  ensureRail()
  -- Track event = retail EncounterTimelineTrackEventTemplate (35x35): trail + IconContainer (the
  -- shared event-icon assembly) + countdown + Intro/Pulse animations.
  local f = CreateFrame("Frame", nil, rail)
  f:SetSize(TL_ICON, TL_ICON)

  -- Trail (OVERLAY sub -1, additive) — combattimeline-line-icontrail, streaking BEHIND the icon to
  -- highlight the rail as it moves. Retail fades it in by movement (TrailAlphaCurve); constant here.
  -- Sized, rotated and re-anchored per axis by layoutTrail, since "behind" depends on which way the
  -- icon is travelling.
  f.trail = f:CreateTexture(nil, "OVERLAY", nil, -1)
  f.trail:SetBlendMode("ADD")
  f.trail:SetAlpha(0.72)
  layoutTrail(f)

  -- The full icon assembly (1:1 EncounterTimelineEventIconTemplate — EventIcon.lua). Icon Size
  -- scales the whole assembly via the container's frame scale (the rail line is not icon-scaled).
  f.IconContainer = BM.MakeEventIcon and BM.MakeEventIcon(f)
  if f.IconContainer then f.IconContainer:SetPoint("CENTER"); f.IconContainer:SetScale(iconScale()) end

  -- Countdown number — on a host frame ABOVE the IconContainer, else the icon assembly (a child
  -- frame) renders over a plain parent fontstring and hides the number.
  f.cdHost = CreateFrame("Frame", nil, f)
  f.cdHost:SetAllPoints(f)
  f.cdHost:SetFrameLevel((f.IconContainer and f.IconContainer:GetFrameLevel() or f:GetFrameLevel()) + 5)
  f.cd = f.cdHost:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  f.cd:SetPoint("CENTER", f.cdHost, "CENTER", 0, 0)
  applyCountdownFont(f)   -- sized to the icon, outlined and shadowed; re-applied by ApplyConfig

  -- Spell name beside the icon (retail TrackEvent Name), shown by the Show Spell Name setting.
  f.name = f.cdHost:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.name:SetPoint("LEFT", f, "RIGHT", 6, 0); f.name:SetJustifyH("LEFT"); f.name:Hide()

  -- Hover target for the Tooltips setting. Mouse stays enabled and the SETTING decides whether the
  -- handlers draw anything — toggling EnableMouse instead would swallow clicks meant for whatever is
  -- behind the rail whenever tooltips were on, and leave the frame inert when they were off.
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self) BM.ShowBarTooltip(self, self._bar) end)
  f:SetScript("OnLeave", function() BM.HideBarTooltip() end)

  -- Intro: alpha fade-in (TrackEvent IntroAnimation, 0.2s). BM.FadeIn forces the end state, since
  -- the animation does not — this is the fade that left every rail icon invisible. The two child
  -- FRAMES are declared with it: fading the track alone restores the track alone (see applyAlpha).
  BM.SetAlphaChildren(f, f.IconContainer, f.cdHost)
  f.IntroAnim = setToFinalAlpha(f:CreateAnimationGroup())
  BM.AlphaAnim(f.IntroAnim, 0, 1, 0.2, nil, "OUT")
  BM.FadeIn(f, f.IntroAnim)

  -- THE IMMINENT GROW replaces retail's looping PulseAnimation (TrackEvent, 1→1.1→0.9).
  --
  -- The owner asked for an ability that is about to go off to "grow a little larger", which the
  -- pulse does not do: it oscillates around its base size, so on average it grows by nothing and the
  -- icon is as often SMALLER as bigger. A monotonic swell reads as a countdown instead of a
  -- heartbeat, and it is what was asked for.
  --
  -- It is also a per-tick SetScale rather than an animation, deliberately. Scale animations on this
  -- client leave the region wherever they stopped (the same hazard as §C.5c/d, which cost three
  -- rounds), and a LOOPING one fighting a per-tick scale over the same property has no good
  -- resolution. Driving it directly is exact, cheap, and cannot drift: growthScale() is a pure
  -- function of remaining time, so any interruption self-corrects on the next frame.
  f.PulseAnim = nil

  -- Finish: pop (IconContainer scale→1.35) + fade 0.2 (retail TrackEvent Finish). Cancel: fade 0.2.
  -- DOWNPORT: the pop and the fade act on DIFFERENT regions, which one group could only express via
  -- SetTarget. Two groups, played together; the fade's OnFinished is the one that drives release.
  f.FinishScale = f.IconContainer and f.IconContainer:CreateAnimationGroup() or nil
  if f.FinishScale then BM.ScaleAnim(f.FinishScale, 1.35, 0.2, nil, "OUT") end
  f.FinishAnim = setToFinalAlpha(f:CreateAnimationGroup())
  BM.AlphaAnim(f.FinishAnim, 1, 0, 0.2, nil, "IN")
  BM.OnFinished(f.FinishAnim, function(self)
    stopAnim(f.FinishScale)
    if f.IconContainer then f.IconContainer:SetScale(iconScale()) end
    if self._done then self._done() end
  end)

  f.CancelAnim = setToFinalAlpha(f:CreateAnimationGroup())
  BM.AlphaAnim(f.CancelAnim, 1, 0, 0.2, nil, "IN")
  BM.OnFinished(f.CancelAnim, function(self) if self._done then self._done() end end)

  bar.track = f
  return f
end

-- Play the two-group finish together (see ensureTrack).
local function playTrackFinish(track)
  if track.FinishScale then stopAnim(track.FinishScale); track.FinishScale:Play() end
  stopAnim(track.FinishAnim); track.FinishAnim:Play()
end

-- Show the visual for the active view; hide the other.
local function applyView(bar)
  if BM.viewMode == "timeline" then
    bar:Hide()                                  -- hide the CDM row
    local t = ensureTrack(bar)
    t._bar = bar
    if t.IconContainer then t.IconContainer:SetEventIcon(bar._icon); t.IconContainer:SetEventState("normal") end
    setShown(t.cd, cfg("showTimer") ~= false)
    if t.name then
      t.name:SetText(bar._label or bar._text or "")
      setShown(t.name, cfg("showSpellName") == true)
    end
    t._highlighted = false
    setImminent(t, false)        -- before the fade: it writes alpha down the tree (§C.5d)
    t:Show()
    if t.IntroAnim then BM.PlayFadeIn(t, t.IntroAnim) end
  else
    if bar.track then stopPulse(bar.track); bar.track:Hide() end
    bar:Show()
  end
end

-- Bars-view layout: sort by remaining time (ascending) + stack downward. (Timeline view positions
-- by time in _OnUpdate, so it skips stacking.)
local function relayout()
  -- Both exits go through layoutBarsPlate: on the timeline it is the call that takes the plate off
  -- screen after a view swap, and in Bars view the row extent it needs is only settled below.
  if BM.viewMode == "timeline" then layoutBarsPlate() return end
  local gap = cfg("padding") or ROW_GAP
  table.sort(list, function(a, b) return (a._endTime or 0) < (b._endTime or 0) end)
  local y = 0                                  -- accumulate per-row heights (rows vary with Icon Size)
  for _, bar in ipairs(list) do
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, -y)
    y = y + (bar:GetHeight() or ROW_H) + gap
  end
  layoutBarsPlate()
end

-- Queue layout (retail's Sorted "Queued" track). buf = the timeline bars currently beyond the
-- linear window (remaining > TL_WINDOW), gathered this tick. Sort soonest-first and drop them into
-- fixed slots above the rail: slot 1 (soonest) sits just above the rail top, the rest stack upward;
-- anything past QUEUE_MAX is hidden until a nearer event clears. Mirrors retail's
-- CalculateSortedEventOffset (soonest-expiring toward the rail end).
local queueBuf = {}
local function layoutQueue(buf)
  table.sort(buf, function(a, b) return (a._endTime or 0) < (b._endTime or 0) end)
  local len, shown = railLen(), 0
  for i, bar in ipairs(buf) do
    local t = bar.track
    if t then
      if i <= QUEUE_MAX then
        shown = shown + 1
        t:ClearAllPoints()
        t:SetPoint("CENTER", rail, nowEdge(),
                   along(len + QUEUE_GAP + (i - 1) * QUEUE_SLOT + QUEUE_SLOT * 0.5))
        t:Show()
      else
        t:Hide()   -- beyond the queue's capacity; re-shown when a nearer event leaves the queue
      end
    end
  end
  if rail and rail.qdivider then setShown(rail.qdivider, shown > 0) end
end

-- Animate an event OUT then release it: finish = it reached "now" (retail pop+fade / fade+slide);
-- cancel = it was stopped early (fade). Detaches immediately so the OnUpdate loop + counts ignore it
-- while the fade plays; the bar/track is released on the animation's OnFinished. Preview events skip
-- the anim (instant) so toggling the editor stays snappy.
local FINISH_TIMEOUT = 1.0   -- s; the longest fade is 0.30

-- Every route out of a fade ends here, exactly once: off the finishing list, back in the pool.
--
-- EXACTLY once matters. Both the animation's OnFinished and the timeout belt below can arrive, in
-- either order, and a second pass would push the same bar into the pool twice — two entries, one
-- frame, and eventually two live events drawing on top of each other. `_finishAt` is the token: it
-- is set once when the fade starts and cleared here.
local function endFinish(bar)
  if not bar._finishAt then return end
  for i = #finishing, 1, -1 do
    if finishing[i] == bar then table.remove(finishing, i) break end
  end
  bar._finishAt, bar._finishDone = nil, nil
  releaseBar(bar); relayout(); refreshDriver()
end

local function finishBar(bar, isCancel)
  if not bar or bar._finishing then return end
  bar._finishing = true
  detach(bar)
  if bar._preview then releaseBar(bar); relayout(); refreshDriver(); return end
  -- Listed BEFORE anything is played. detach() has already dropped activeCount, so on the last bar
  -- of a fight the very next refreshDriver would hide the anchor and strand this animation
  -- (see refreshDriver). The timestamp is the belt: _OnUpdate forces the release of anything still
  -- here after FINISH_TIMEOUT, so a fade whose OnFinished never arrives cannot pin the frame up or
  -- keep a bar out of the pool.
  bar._finishAt = GetTime()
  bar._finishDone = function() endFinish(bar) end
  finishing[#finishing + 1] = bar
  if BM.viewMode == "timeline" and bar.track then
    local t = bar.track
    stopPulse(t)
    if isCancel then
      t.CancelAnim._done = bar._finishDone
      stopAnim(t.CancelAnim); t.CancelAnim:Play()
    else
      t.FinishAnim._done = bar._finishDone
      playTrackFinish(t)
    end
    return
  end
  local ag = isCancel and bar.CancelAnim or bar.FinishAnim
  if ag then ag._done = bar._finishDone; stopAnim(ag); ag:Play() else bar._finishDone() end
end

-- ============================ The driver =====================================================

function BM._OnUpdate()
  local now = GetTime()
  local dirty = false
  local timeline = BM.viewMode == "timeline"
  for i = #list, 1, -1 do
    local bar = list[i]
    -- Paused (a DBM verb): freeze by re-extending _endTime each tick, so remaining stays constant
    -- AND the sort/queue math keeps seeing a coherent end time.
    if bar._paused then bar._endTime = now + (bar._pausedRemaining or 0) end
    local remaining = (bar._endTime or 0) - now
    -- Editor preview events loop like RETAIL's: its edit-mode events run the real state machine
    -- (EncounterTimeline.lua:257-266), so at "now" each plays the FULL finish pop before a fresh
    -- batch respawns at the top. Live events expire below.
    if remaining <= 0 and bar._preview then
      local t = bar.track
      if timeline and t and t.FinishAnim then
        if not bar._previewFinishing then
          bar._previewFinishing = true
          stopPulse(t)
          t.FinishAnim._done = function()
            bar._previewFinishing = nil
            if not bar._preview then return end      -- editor exited mid-pop
            bar._endTime = GetTime() + (bar._previewDur or TL_WINDOW)
            -- Runs inside FinishAnim's OnFinished. A DIFFERENT group, so the self-guard does not
            -- apply, but re-entering the animation API from a callback is the whole hazard class —
            -- PlayFadeIn stops through stopAnim, a no-op unless Intro is genuinely mid-play.
            BM.PlayFadeIn(t, t.IntroAnim)            -- re-fade at the top
          end
          playTrackFinish(t)
        end
      else
        -- Bar view (no rail icon): instant loop.
        bar._endTime = now + (bar._previewDur or TL_WINDOW)
        remaining = bar._previewDur or TL_WINDOW
      end
    end
    if bar._previewFinishing then   -- luacheck: ignore 542
      -- Frozen at the "now" pip while the pop plays (retail's finish freezes in place): no expiry,
      -- no reposition, and no pulse restart this tick.
    elseif remaining <= 0 then
      finishBar(bar, false); dirty = true   -- plays the finish anim, then releases (detaches now)
    elseif timeline then
      local t = bar.track
      if t then
        t.cd:SetText((bar._approx and "~" or "") .. fmtTime(remaining))
        -- Belt on the fade-in end state, ABOVE the railed/queued split: BM.FadeIn's OnFinished is
        -- the primary guarantee, and this catches a group that never fired. It sits here rather
        -- than in the railed branch because a queued event never reaches that branch — the live
        -- dump caught one sitting at alpha 0 for exactly that reason. One compare per bar per frame.
        if not t.IntroAnim:IsPlaying() and needsAlphaRestore(t) then applyAlpha(t, 1) end
        if remaining > TL_WINDOW then
          -- Beyond the linear window → queue it (positioned in layoutQueue after the loop).
          queueBuf[#queueBuf + 1] = bar
          if not t._queued then
            t._queued = true
            if t.IconContainer and t.IconContainer.SetEventState then t.IconContainer:SetEventState("queued") end
            if t.trail then t.trail:Hide() end                 -- queued icons don't slide → no trail
          end
          t._highlighted = false
          stopPulse(t)
          setImminent(t, false)
        else
          -- Inside the window → linear rail. Revert queued styling if it just dropped in.
          if t._queued then
            t._queued = false
            if t.IconContainer and t.IconContainer.SetEventState then t.IconContainer:SetEventState("normal") end
            if t.trail then t.trail:Show() end
          end
          t:Show()
          local frac = remaining / TL_WINDOW
          frac = (frac < 0 and 0) or (frac > 1 and 1) or frac   -- 0 is truthy in Lua, so this clamps
          t:ClearAllPoints()
          t:SetPoint("CENTER", rail, nowEdge(), along(railLen() * frac))   -- slides toward the pip
          layoutTrail(t)
          -- Imminent: play the highlight glow/swirl once on entry, pulse continuously inside.
          if remaining <= TL_HIGHLIGHT then
            if not t._highlighted then
              t._highlighted = true
              -- The ring flash is the ENTRY cue, one-shot, retail's own art.
              if t.IconContainer and t.IconContainer.PlayHighlight then t.IconContainer:PlayHighlight() end
            end
            -- The glow is SUSTAINED for the whole window, and is what actually carries at this
            -- size. Idempotent, so calling it every tick costs one comparison — and inside the
            -- last second it also spins the glow up and drives the ring's flash.
            setImminent(t, true, remaining)
            applyTrackScale(t, remaining)   -- and the icon swells as it closes on "now"
          else
            t._highlighted = false
            setImminent(t, false)
            stopPulse(t)
          end
        end
      end
    else
      bar.sb:SetValue(remaining)        -- spark auto-tracks (anchored to the fill texture)
      bar.timeText:SetText((bar._approx and "~" or "") .. fmtTime(remaining))
    end
  end
  if timeline then layoutQueue(queueBuf); wipe(queueBuf) end
  -- The belt on the finishing list. Nothing should ever reach the timeout — but a fade that failed
  -- to report back is exactly how the last bar of every fight used to leak, and this frame is up
  -- precisely because that list is not empty, so the check is free and self-terminating.
  for i = #finishing, 1, -1 do
    local b = finishing[i]
    if b._finishAt and (now - b._finishAt) > FINISH_TIMEOUT and b._finishDone then b._finishDone() end
  end
  if dirty then relayout() end
  if activeCount == 0 then refreshDriver() end
end

-- ============================ Hover tooltips =================================================
--
-- The fourth setting the source persisted and never read. DBM hands us a spellId on every timer
-- (DBM-Core.lua:10049, arg 6), so there is something real to show; the adapter now keeps it.
--
-- DOWNPORT: GameTooltip:SetSpellByID does not exist on 3.3.5a. The hyperlink form does the same job
-- and is what the client's own frames use. If the id is missing or the link fails — DBM raises
-- plenty of timers that are not a spell at all ("Combat starts", phase timers) — the ability's own
-- label is shown instead, which is still more than nothing.

function BM.HideBarTooltip()
  if GameTooltip then GameTooltip:Hide() end
end

function BM.ShowBarTooltip(owner, bar)
  if not (GameTooltip and owner and bar) then return end
  local anchorMode = cfg("tooltipAnchor") or "cursor"
  if anchorMode == "hidden" then return end

  GameTooltip:SetOwner(owner, anchorMode == "cursor" and "ANCHOR_CURSOR" or "ANCHOR_RIGHT")
  local shown = false
  if bar._spellID and GameTooltip.SetHyperlink then
    shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "spell:" .. tostring(bar._spellID))
  end
  if not shown then
    GameTooltip:SetText(bar._label or bar._text or "", 1, 0.82, 0)
  end
  GameTooltip:Show()
end

-- ============================ INTERNAL EVENT BUS (the backend seam) ==========================
-- Backend-agnostic timeline API the adapter feeds. A live event is keyed (owner, key); the DBM
-- adapter uses (its sentinel owner table, DBM's real timer id). `label` is the display text.
--
-- This seam is the whole reason a second backend would be one new file: nothing below here knows
-- what a DBM is.

function BM.BusStartBar(owner, key, label, dur, icon, isApprox, maxTime, spellID)
  if not owner or key == nil or not dur or dur <= 0 then return end
  ensureAnchor()
  active[owner] = active[owner] or {}
  local bar = active[owner][key]
  if not bar then
    if activeCount >= MAX_BARS then return end   -- silently cap
    bar = table.remove(pool) or makeBar()
    active[owner][key] = bar
    list[#list + 1] = bar
    activeCount = #list
  end
  bar._module, bar._text = owner, key
  bar._label = label or tostring(key)
  bar._paused, bar._pausedRemaining = nil, nil
  bar._endTime = GetTime() + dur
  bar._approx = isApprox and true or false
  bar._icon = icon
  bar._spellID = spellID          -- for the hover tooltip; nil for DBM's non-spell timers
  bar.sb:SetMinMaxValues(0, maxTime and maxTime > dur and maxTime or dur)
  bar.sb:SetValue(dur)
  if icon then bar.icon:SetTexture(icon); cropIcon(bar.icon); bar.icon:Show() else bar.icon:Hide() end
  bar.label:SetText(bar._label)
  if bar.track then bar.track._bar = bar end   -- the track's tooltip handler reads back through this
  bar._bar = bar                                -- ...and the bar row's does the same
  applyView(bar)        -- show the CDM row or the rail icon per BM.viewMode
  relayout()
  refreshDriver()
end

local function findBar(owner, key)
  local m = owner and active[owner]
  return m and key ~= nil and m[key] or nil
end

-- Does the bus already know this event? The DBM adapter asks before adopting a bar DBM drew without
-- telling anyone, so the ones it DID tell us about are not drawn twice.
function BM.BusHasBar(owner, key)
  return findBar(owner, key) ~= nil
end

function BM.BusStopBar(owner, key)
  local bar = findBar(owner, key)
  if not bar then return end
  -- Mapping decision (bus → retail's state machine): mods stop a bar both when the ability HAPPENS
  -- (typically moments before the estimated timer runs out) and when it is removed early (phase
  -- change / boss dead). Retail POPS an event that reaches its time (Finish) and fades one pulled
  -- early (Cancel). Discriminate on retail's own imminent threshold: a single-bar stop inside the
  -- highlight window reads as "it happened" → finish pop; earlier = genuine cancel fade. Bulk
  -- BusStopAll stays cancel-only (wipes / phase cleanups).
  local remaining = (bar._endTime or 0) - GetTime()
  finishBar(bar, remaining > TL_HIGHLIGHT)
end

function BM.BusStopAll(owner)
  local m = owner and active[owner]
  if not m then return end
  -- Snapshot first: finishBar → detach mutates active[owner] (can't mutate during pairs()).
  local bars = {}
  for _, bar in pairs(m) do bars[#bars + 1] = bar end
  for _, bar in ipairs(bars) do finishBar(bar, true) end
end

-- Pause/Resume/Update — DBM timer verbs. Pause freezes the remaining time (the tick loop
-- re-extends _endTime each frame so sorting and the queue math stay coherent) and shows the retail
-- paused badge on the rail icon.
function BM.BusPauseBar(owner, key)
  local bar = findBar(owner, key)
  if not bar or bar._paused then return end
  bar._pausedRemaining = math.max(0, (bar._endTime or 0) - GetTime())
  bar._paused = true
  if bar.track and bar.track.IconContainer and bar.track.IconContainer.SetEventState
     and not bar.track._queued then
    bar.track.IconContainer:SetEventState("paused")
  end
end

function BM.BusResumeBar(owner, key)
  local bar = findBar(owner, key)
  if not (bar and bar._paused) then return end
  bar._endTime = GetTime() + (bar._pausedRemaining or 0)
  bar._paused, bar._pausedRemaining = nil, nil
  if bar.track and bar.track.IconContainer and bar.track.IconContainer.SetEventState then
    bar.track.IconContainer:SetEventState(bar.track._queued and "queued" or "normal")
  end
end

function BM.BusUpdateBar(owner, key, elapsed, total)
  local bar = findBar(owner, key)
  if not bar then return end
  local remaining = math.max(0, (total or 0) - (elapsed or 0))
  if bar._paused then bar._pausedRemaining = remaining else bar._endTime = GetTime() + remaining end
  if total and total > 0 then
    bar.sb:SetMinMaxValues(0, total)
  end
end

-- ============================ Backend availability ===========================================
-- DOWNPORT: the source picked between BigWigs and DBM (auto/bigwigs/dbm, an options picker, and a
-- BigWigs bar-skin suppressor in Suppress.lua). Here DBM is the requirement, so this collapses to
-- "is it there". BM.Bus* above is untouched, so a BigWigs adapter remains a drop-in.

function BM.DBMPresent()
  local d = _G.DBM
  return (d and type(d.RegisterCallback) == "function") and true or false
end

-- What core/Modules.lua's requiresAddOn gate calls, and what Register.lua reports in the options.
function BM.Available() return BM.DBMPresent() end

-- ============================ Public surface (Register.lua) ==================================

function BM.GetAnchor() ensureAnchor() return anchor end

-- Switch between the rail Timeline view and the CDM Bars view (retail's ViewType setting).
function BM.SetViewMode(mode)
  BM.viewMode = (mode == "bars") and "bars" or "timeline"
  updateAnchorSize()
  for _, bar in ipairs(list) do applyView(bar) end
  if BM.viewMode ~= "timeline" then relayout() end
  refreshDriver()
end

-- Apply the full customization config to the live HUD. Called by the options appliers and once at
-- boot. Re-reads every setting and re-renders; size-only changes don't replay the icon Intro (only a
-- view swap does).
function BM.ApplyConfig()
  ensureAnchor()
  local newMode = (cfg("viewType") == "bars") and "bars" or "timeline"
  local modeChanged = newMode ~= BM.viewMode
  BM.viewMode = newMode
  updateAnchorSize()   -- keep the handle/footprint matching the active view (reads railLen)
  if rail then layoutRail() end          -- re-point the rail line/pip for the current Length
  anchor:SetAlpha((cfg("opacity") or 100) / 100)
  BM.Repin()   -- Scale (retail's OverallSize), re-pinned rather than a bare SetScale
  -- Background drives one plate per view: the rail's shadow, or the bars' backing (the latter also
  -- re-alpha'd by layoutBarsPlate, which relayout below reaches).
  if rail and rail.plate then rail.plate:SetAlpha((cfg("background") or 0) / 100) end
  local sc = iconScale()
  for _, bar in ipairs(list) do
    sizeBar(bar)
    if bar.track then
      if bar.track.IconContainer then bar.track.IconContainer:SetScale(sc) end
      applyCountdownFont(bar.track)   -- the number follows Icon Size with the icon
      layoutTrail(bar.track)   -- Orientation / Icon Direction move which side it streaks from
      setShown(bar.track.cd, cfg("showTimer") ~= false)
      if bar.track.name then
        bar.track.name:SetText(bar._label or bar._text or "")
        setShown(bar.track.name, cfg("showSpellName") == true)
      end
    end
    if modeChanged then applyView(bar) end
  end
  relayout()
  refreshDriver()
end

-- Re-pin on resolution / UI-scale change. Register.lua drives this from the same events the source's
-- boot() handled; routed through DragonUI's editor when it owns the frame, else a direct pin.
function BM.Repin()
  if not anchor then return end
  if NE.FrameUtil and NE.FrameUtil.PinPixelPerfect then
    pcall(NE.FrameUtil.PinPixelPerfect, anchor, (cfg("scale") or 100) / 100)
  end
end

-- Editor preview events — staggered durations spread along the rail so the timeline/bars are
-- POPULATED while editing; each LOOPS (slides to "now", resets to the top) so the frame animates
-- like the live feed. Mirrors retail's AddEditModeEvents. Cleared on exit.
local EDIT_PREVIEW = {
  -- Two long timers (> TL_WINDOW) seed the queue stack so it's visible/positionable.
  { "Cataclysm",      48, "Interface\\Icons\\Spell_Fire_Volcano" },
  { "Doom Bolt",      34, "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
  { "Impending Doom", 22, "Interface\\Icons\\Spell_Shadow_ShadowWordPain" },
  { "Lava Burst",     16, "Interface\\Icons\\Spell_Fire_Fireball02" },
  { "Mind Control",   11, "Interface\\Icons\\Spell_Shadow_ShadowWordDominate" },
  { "Enrage",          6, "Interface\\Icons\\Ability_Warrior_Charge" },
}

function BM.SetEditPreview(on)
  local pm = BM._previewModule or {}; BM._previewModule = pm
  BM.BusStopAll(pm)                      -- clear any existing preview first
  if not on then return end
  for i, e in ipairs(EDIT_PREVIEW) do
    BM.BusStartBar(pm, i, e[1], e[2], e[3], false, nil)   -- drives the normal render path
    local bar = active[pm] and active[pm][i]
    if bar then bar._preview, bar._previewDur = true, e[2] end  -- loop it (see _OnUpdate)
  end
  refreshDriver()
end

-- Editor enter/exit: populate a frozen preview so the (otherwise empty) frame is visible and
-- grabbable. Opacity previews live too — the slider floors at 50% and DragonUI's selection handle is
-- a separate overlay, so a dimmed anchor never affects grabbing.
function BM.SetEditActive(editing)
  ensureAnchor()
  BM._editing = editing and true or false
  BM.SetEditPreview(BM._editing)
  anchor:SetAlpha((cfg("opacity") or 100) / 100)
  refreshDriver()
end

-- ============================ Diagnostics ====================================================
--
-- `/nebossmods debug`. Everything below the render seam is covered by qa/offline/test_bossmods.lua;
-- this reports the half that only the client knows — resolved texture paths, effective scales, and
-- where the live frames actually ended up. It reads state, never changes it.

local function yn(v) return v and "yes" or "no" end
local function fmtPoint(f)
  if not f or f:GetNumPoints() == 0 then return "UNANCHORED" end
  local p, rel, relP, x, y = f:GetPoint(1)
  local name = "?"
  if rel == nil then name = "nil"
  elseif rel.GetName then name = rel:GetName() or "<unnamed>" end
  return string.format("%s->%s.%s(%.0f,%.0f)", tostring(p), name, tostring(relP), x or 0, y or 0)
end
-- IsShown is the frame's OWN flag; IsVisible also accounts for the parent chain. Reporting only the
-- first is how a frame that is "shown" inside a hidden ancestor reads as fine. Same reasoning for
-- alpha: a child renders at the product of the chain, so its own value can be 1 and still not draw.
local function fmtFrame(f)
  if not f then return "MISSING" end
  return string.format("shown=%s visible=%s alpha=%.2f size=%.0fx%.0f scale=%.2f eff=%.2f %s",
    yn(f:IsShown()), yn(f.IsVisible and f:IsVisible()), f:GetAlpha() or 1,
    f:GetWidth() or 0, f:GetHeight() or 0,
    f:GetScale() or 1, f:GetEffectiveScale() or 1, fmtPoint(f))
end

-- Every region of the icon assembly, individually. The track's own trail texture rendering while
-- its child frames did not is the signature this exists to resolve: it separates "the container is
-- invisible" from "the container is fine and each texture inside it is not".
local function dumpRegions(out, frame, label)
  if not (frame and frame.GetRegions) then out("      " .. label .. ": MISSING") return end
  local n = 0
  for _, r in ipairs({ frame:GetRegions() }) do
    n = n + 1
    local layer, sub = r:GetDrawLayer()
    out(string.format("      %s[%d] %s %s/%s shown=%s alpha=%.2f size=%.0fx%.0f pts=%d tex=%s",
      label, n, tostring(r:GetObjectType()), tostring(layer), tostring(sub),
      yn(r:IsShown()), r:GetAlpha() or 1, r:GetWidth() or 0, r:GetHeight() or 0,
      r:GetNumPoints(), tostring(r.GetTexture and r:GetTexture() or (r.GetText and r:GetText()))))
  end
  if n == 0 then out("      " .. label .. ": no regions") end
end

function BM.Dump()
  local out = function(s) print("|cff1784d1BossTimers|r " .. s) end
  out(string.format("view=%s active=%d editing=%s visibility=%s opacity=%s",
    tostring(BM.viewMode), activeCount, yn(BM._editing), tostring(cfg("visibility")), tostring(cfg("opacity"))))
  out("anchor: " .. fmtFrame(anchor))
  if anchor then
    local p = anchor:GetParent()
    out("anchor parent: " .. ((p and p.GetName and (p:GetName() or "<unnamed>")) or "nil"))
  end
  out("rail: " .. fmtFrame(rail) .. (rail and rail.plate and string.format(" plateAlpha=%.2f", rail.plate:GetAlpha()) or ""))

  -- Did the art resolve? A miss here is an invisible texture that reports no error: NE.tex.SetAtlas
  -- returns false when the BLP was not shipped, and every caller here is pcall'd.
  local names = { "combattimeline-line-right", "combattimeline-line-left", "combattimeline-pip",
                  "combattimeline-fx-queued", "combattimeline-fx-highlight",
                  "UI-HUD-CoolDownManager-IconOverlay", "UI-HUD-CoolDownManager-Bar" }
  for _, n in ipairs(names) do
    local e = NE.tex._atlasEntry and NE.tex._atlasEntry(n)
    local file = e and NE.tex.Local and NE.tex.Local(e.file)
    out(string.format("atlas %-38s %s", n,
      (not e) and "|cffff5555UNREGISTERED|r"
      or (type(file) ~= "string") and ("|cffff5555NO LOCAL FILE|r (fdid " .. tostring(e.file) .. ")")
      or ("ok " .. file)))
  end

  out(string.format("live bars: %d (pool %d)", #list, #pool))
  for i, bar in ipairs(list) do
    if i > 3 then out("  …") break end
    local remaining = (bar._endTime or 0) - GetTime()
    out(string.format("  [%d] %s remaining=%.1f paused=%s", i, tostring(bar._label), remaining, yn(bar._paused)))
    if BM.viewMode == "timeline" then
      local t = bar.track
      if not t then out("      track: MISSING") else
        out("      track:  " .. fmtFrame(t) .. " queued=" .. yn(t._queued) .. " intro=" .. tostring(t.IntroAnim:IsPlaying()))
        local ic = t.IconContainer
        out("      cont:   " .. (ic and fmtFrame(ic) or "|cffff5555NO IconContainer|r (EventIcon.lua did not load)"))
        out("      cdHost: " .. fmtFrame(t.cdHost))
        if i == 1 then
          -- One track's full region breakdown; three would flood the chat frame.
          dumpRegions(out, t,  "track")
          dumpRegions(out, ic, "cont ")
          dumpRegions(out, t.cdHost, "cdH  ")
        end
      end
    else
      out("      row:   " .. fmtFrame(bar))
      out("      icon:  shown=" .. yn(bar.icon:IsShown()) .. " tex=" .. tostring(bar.icon:GetTexture()))
      local lo, hi = bar.sb:GetMinMaxValues()
      out(string.format("      fill:  value=%.1f of %.1f-%.1f sbw=%.0f label=%s",
        bar.sb:GetValue() or 0, lo or 0, hi or 0, bar.sb:GetWidth() or 0, tostring(bar.label:GetText())))
    end
  end
  if BM.DumpWarnings then BM.DumpWarnings(out, fmtFrame, fmtPoint) end
end

-- Pixel-perfect scale is handled the standard way: Register.lua pins the anchor via
-- NE.FrameUtil.PinPixelPerfect; ensureAnchor pins the base at creation; BM.Repin re-pins on
-- UI_SCALE_CHANGED / DISPLAY_SIZE_CHANGED. Every bar/fontstring is a child of the anchor and
-- inherits its pinned effective scale.
