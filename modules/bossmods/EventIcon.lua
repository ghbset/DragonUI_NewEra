-- DragonUI_NewEra/modules/bossmods/EventIcon.lua — retail's EncounterTimelineEventIconTemplate
-- (EncounterTimelineTemplates.xml:51-168), the shared event-icon assembly the rail's tracks build.
--
-- Downport of ReferenceAddons/NewEra/Alerts/BossMods/EventIcon.lua. Atlas sizes, anchors, draw
-- sublevels and animation values all still match retail source.
--
-- Which STATES actually fire: retail drives deadly/paused/queued off C_EncounterTimeline, which
-- does not exist here. Two of the three are reachable anyway — `paused` from DBM's own pause verb
-- (DBM_TimerPause) and `queued` from the rail's own queued track — so only `deadly` is built and
-- never shown. It costs two textures and keeps the assembly a faithful copy.
--
-- DOWNPORT, in summary:
--   * Both MaskTextures are gone. Frame:CreateMaskTexture returns nil on 3.3.5a (!!!ClassicAPI
--     declares it Private.Void), so the icon is rounded by a texcoord trim under the CDM overlay
--     ring instead. The highlight SWIRL, which retail clips with the second mask, is not ported at
--     all — unmasked it is a filled disc three times the icon's width. See the block on it below,
--     and PORT_PLAN.md §C.3 / §C.5e.
--   * Animation:SetTarget does not exist here, so the one HighlightAnimation that drove two
--     textures becomes one group per texture, played together by PlayHighlight.
--   * SetShown is banned (CONTRACTS §0) → BM.SetShown.

local NE = DragonUI_NewEra
local BM = NE.bossmods
if not BM then return end

local setShown  = BM.SetShown
local setAtlas  = BM.SetAtlas
local cropIcon  = BM.CropIcon

-- The imminent FX, standing in for the swirl retail draws and we cannot (see the block below).
-- Embedded in this addon and already driven by the Cooldown Manager's alerts
-- (modules/cooldownviewer/Alerts.lua:375), so this is the same renderer the rest of the UI uses for
-- "look at this now" rather than a second vocabulary invented here.
local LCG = LibStub and LibStub("LibCustomGlow-1.0", true)
local GLOW_FREQUENCY = 0.35   -- matches the Cooldown Manager's ButtonGlow cadence

-- Disable texel snapping (retail does this for smooth motion); guarded — these texture methods do
-- not exist on 3.3.5a, so in practice this is a no-op kept for forward-compat.
local function noSnap(t)
  if t.SetTexelSnappingBias then t:SetTexelSnappingBias(0) end
  if t.SetSnapToPixelGrid then t:SetSnapToPixelGrid(false) end
end

-- f:SetEventIcon(fileID) — the spell icon.
-- f:SetEventState("normal"|"deadly"|"paused"|"queued") — swaps the border overlay (retail priority
--   Deadly > Paused > Queued > Normal).
-- f:PlayHighlight() — the imminent glow+swirl one-shot (EncounterTimelineEventIconMixin).
function BM.MakeEventIcon(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(35, 35)   -- retail EncounterTimelineEventIconTemplate

  -- ARTWORK: the spell icon. Retail rounds it with the CDM mask and insets the mask 1px at the top;
  -- with no mask to inset, the trim below plus the overlay ring carry the same look.
  local icon = f:CreateTexture(nil, "ARTWORK")
  noSnap(icon)
  icon:SetAllPoints(f)
  cropIcon(icon)
  f.IconTexture = icon

  -- OVERLAY sub 0: the four border overlays (one shown at a time), all inset -7,6 / 7,-7.
  local function border(atlas, hidden)
    local t = f:CreateTexture(nil, "OVERLAY", nil, 0)
    noSnap(t)
    setAtlas(t, atlas)
    t:SetPoint("TOPLEFT", f, "TOPLEFT", -7, 6); t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 7, -7)
    if hidden then t:Hide() end
    return t
  end
  f.NormalOverlay = border("UI-HUD-CoolDownManager-IconOverlay")
  f.DeadlyOverlay = border("combattimeline-fx-deadlyglow-base", true)
  f.PausedOverlay = border("combattimeline-fx-pause", true)
  f.QueuedOverlay = border("combattimeline-fx-queued", true)

  -- OVERLAY sub 1: deadly additive glow + the paused badge.
  f.DeadlyGlow = f:CreateTexture(nil, "OVERLAY", nil, 1)
  setAtlas(f.DeadlyGlow, "combattimeline-fx-deadlyglow-overlay"); f.DeadlyGlow:SetBlendMode("ADD")
  f.DeadlyGlow:SetPoint("TOPLEFT", f, "TOPLEFT", -7, 6); f.DeadlyGlow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 7, -7)
  f.DeadlyGlow:Hide()
  f.PausedIcon = f:CreateTexture(nil, "OVERLAY", nil, 1)
  setAtlas(f.PausedIcon, "combattimeline-fx-pause-icon"); f.PausedIcon:SetSize(16, 16)
  f.PausedIcon:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 4); f.PausedIcon:Hide()

  -- OVERLAY sub 2: highlight glow ring (alpha 0; animated to 0.7).
  f.HighlightGlow = f:CreateTexture(nil, "OVERLAY", nil, 2)
  setAtlas(f.HighlightGlow, "combattimeline-fx-highlight")
  f.HighlightGlow:SetPoint("TOPLEFT", f, "TOPLEFT", -8, 7); f.HighlightGlow:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 8, -8)
  f.HighlightGlow:SetAlpha(0)

  -- THE HIGHLIGHT SWIRL IS NOT PORTED, and its OVERLAY sub-3 slot stays empty.
  --
  -- Retail's EncounterTimelineEventIconTemplate puts `combattimeline-fx-highlight-fx` here, a
  -- 108x108 additive quad rotating -180° behind the icon, CLIPPED to the icon by
  -- combattimeline-fx-highlight-mask. There is no clip available on 3.3.5a, and an earlier build
  -- shipped it unmasked on the guess that it would read as a soft bloom slightly wider than the
  -- ring. It does not. Sampling the sheet directly settles it:
  --
  --     combattimeline-fx-highlight     86x86   centre alpha  38, ring alpha 149  -> a RING
  --     combattimeline-fx-highlight-fx  107x107 centre alpha 211, ring alpha 155  -> a FILLED DISC
  --
  -- A solid 211-alpha disc three times the width of a 35px icon, drawn additively over the spell
  -- art and its neighbours on the rail. That is what the owner saw. modules/cooldownviewer/Alerts.lua
  -- reached the identical conclusion about retail's PandemicFX quads and declined them for the same
  -- reason ("Worse than no FX"); this follows that precedent rather than re-litigating it.
  --
  -- What remains is the GLOW RING, which the sample above confirms is genuinely hollow and so needs
  -- no clip at all. It is the part that carries the signal — this ability is imminent — and it is
  -- what retail's highlight reads as from a distance. The rotation went with the swirl: there is
  -- nothing left for it to spin.
  --
  -- The ring group ENDS HIDDEN, set explicitly. A 1 → 0 fade does not leave a region at 0 on this
  -- client any more than a 0 → 1 fade leaves it at 1 (PORT_PLAN §C.5c), and a highlight that never
  -- switches off is a permanent glow on a stale icon.
  local glowAG = f.HighlightGlow:CreateAnimationGroup()
  if glowAG.SetToFinalAlpha then glowAG:SetToFinalAlpha(true) end
  BM.AlphaAnim(glowAG, 0, 0.7, 0.2, 1, "IN")
  BM.AlphaAnim(glowAG, 0.7, 0, 0.2, 2, "OUT")
  BM.OnFinished(glowAG, function() f.HighlightGlow:SetAlpha(0) end)
  f.HighlightGlowAnim = glowAG

  function f:SetEventIcon(fileID)
    -- DOWNPORT: the source's fallback was the raw fileID 134400. 3.3.5a's SetTexture cannot read a
    -- FileDataID at all (retail/Era only), so it is spelled as the path to the same art.
    self.IconTexture:SetTexture(fileID or "Interface\\Icons\\INV_Misc_QuestionMark")
    cropIcon(self.IconTexture)   -- SetTexture resets texcoords, so re-trim after every swap
  end

  function f:SetEventState(state)
    setShown(self.NormalOverlay, state == nil or state == "normal")
    setShown(self.DeadlyOverlay, state == "deadly"); setShown(self.DeadlyGlow, state == "deadly")
    setShown(self.PausedOverlay, state == "paused"); setShown(self.PausedIcon, state == "paused")
    setShown(self.QueuedOverlay, state == "queued")
  end

  function f:PlayHighlight()
    -- BM.StopAnim, not a raw Stop: on 3.3.5a stopping a group is only safe when it is genuinely
    -- playing and never from inside its own OnFinished. See the note on BM.StopAnim.
    BM.StopAnim(self.HighlightGlowAnim); self.HighlightGlowAnim:Play()
  end

  -- f:SetImminent(on) — the action-button proc glow, held for as long as the event is inside the
  -- highlight window.
  --
  -- This is the REPLACEMENT for the swirl above, not an addition to the retail look for its own
  -- sake. Retail's flourish is a one-shot ring flash plus a masked swirl; with the swirl gone the
  -- ring alone turned out to be far too subtle to catch on a moving rail — the owner's read, and
  -- easy to believe at an effective scale of 0.53. The ring still fires (it is retail's own art and
  -- the entry cue), and the glow supplies the visibility the swirl was carrying.
  --
  -- Idempotent by design: _OnUpdate calls this every tick while an event is imminent, and
  -- ButtonGlow_Start would otherwise restart its intro animation 60 times a second.
  function f:SetImminent(on)
    on = on and true or false
    if on == self._imminent then return end
    self._imminent = on
    if not LCG then return end
    if on then
      -- No colour: the untinted proc glow is the gold the player already reads as "now", and it is
      -- what "Button Glow" means everywhere else in this UI. One glow per frame, so no key.
      if LCG.ButtonGlow_Start then LCG.ButtonGlow_Start(self, nil, GLOW_FREQUENCY) end
    elseif LCG.ButtonGlow_Stop then
      LCG.ButtonGlow_Stop(self)
    end
  end

  return f
end
