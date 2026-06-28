-- DragonUI_NewEra/modules/talents/Talents.lua — STANDALONE 3-column talent window.
--
-- DOWNPORT: NewEra Talents/Talents.lua (retail-style 3-column talent panel, RENDER-BEFORE-WIRE)
-- → WotLK 3.3.5a. NewEra hosted talents as TAB 2 of a shared PlayerSpellsFrame and used retail-
-- only masking (CreateMaskTexture / SetAtlasMask / AddMaskTexture) for round icons + sheen + an
-- ambient cloud/particle FX layer. NONE of that exists on 3.3.5a. So this port:
--   * builds a DEDICATED standalone window NE_TalentFrame (mirrors the spellbook's OWN window,
--     modules/spellbook/Window.lua buildWindow + SB.Host) via NE.chrome.Apply — NOT a tab.
--   * DROPS every mask: round icon clip, sheen masks, and the whole ambient FX layer (see -- VERIFY).
--   * distinguishes the "active/circle" shape with the GRAY SQUARE node frame (the spellbook's
--     passive-frame trick, modules/spellbook/Spellbook.lua ~165), since we can't clip square→round.
--   * widens geometry from vanilla's 7 tiers to WotLK's 11 tiers (COLS stays 4, 3 talent tabs).
--
-- This file is the LOOK/scaffold layer: frame build, node factory (T.CreateNode), layout math
-- (T.LAYOUT / T.nodeCenter), gate/edge primitives, T.FRAME geometry. The LIVE data layer (real
-- talents, preview/commit, dependency edges, points readout) is wired in Behavior.lua, which
-- defines T.Populate (the active OnShow path). NodeData.lua provides T.ResolveShape / T.SHAPE_ATLAS
-- / T.CAPSTONE_TIER. All three load around/after this file — guard their use.
--
-- Pure Lua (no XML). Dev: /netalents toggles the window; also rerouted from ToggleTalentFrame so
-- the default talent key opens it.

local NE = DragonUI_NewEra
local T = NE.talents or {}
NE.talents = T

-- ----------------------------------------------------------------------------
-- Local logger + guard (so a missing helper never hard-errors the build).
-- ----------------------------------------------------------------------------
local function log(msg)
  if NE.Log then NE.Log("TALENTS", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [talents]: " .. tostring(msg))
  end
end
local function guard(label, fn)
  local ok, err = pcall(fn)
  if not ok then log(label .. " failed: " .. tostring(err)) end
  return ok
end

-- ----------------------------------------------------------------------------
-- Layout spec (DERIVED — no retail baseline exists for an Era-talent frame; WotLK adapts it).
-- ----------------------------------------------------------------------------
local NODE       = 36          -- node size (smaller/tighter, per retail comparison)
local ICON       = 32          -- icon within the node
-- Square nodes read visually larger than circle nodes: the square frame art draws its border by
-- OVERDRAWING the icon's outer edge, so the visible icon is bounded by the frame's transparent
-- inner WINDOW (chunkier than the round set). Scale the WHOLE square node down to the round set's
-- 56/64 footprint so it doesn't read larger than a circle node. (3.3.5a: round shapes ALSO use the
-- square art now — see SetVisual — but keeping the fit factor preserves the tuned node footprint.)
local SQUARE_NODE_FIT = 56 / 64
-- The icon sits BEHIND the frame border (ring), which has transparent padding + rounded corners, so
-- an icon sized to the full frame pokes its square corners out past the visible border. Inset the
-- icon to ~the border's inner window so it fills inside the frame cleanly. Tune if corners still show.
local ICON_INSET = 0.84
-- Square capstone (passive 31-pt talent) node size. Square icons fill the frame (icon == base, no
-- mask), so this IS the square-capstone icon size. Tuned smaller than the round apex (NODE+48=84).
local CAPSTONE_SQUARE_SIZE = 56
local PITCH_X    = 54          -- horizontal grid pitch (original width — user confirmed width was fine)
-- Vertical grid pitch. WotLK talent trees are 11 tiers deep (vs vanilla's 7), so the per-row pitch
-- is tightened 64→44 so all 11 rows fit the de-inflated 750-tall frame budget (see TALENT_H below).
local PITCH_Y    = 44
-- Extra drop before the deepest tier. The deepest-tier talent is rendered as a SCALED-UP capstone
-- node (~73px round / 56px square via SetVisual), so even though WotLK's bottom tier is normal
-- density, the enlarged node overhangs tier 10 at the 44px pitch. Half-heights: capstone ~37,
-- tier-10 node ~16 → need ≥53 center distance; pitch is 44, so add ~28 to clear it with a small gap.
local LAST_TIER_EXTRA = 28
local TREE_Y_SHIFT    = 16     -- small drop below the title band
local COLS       = 4           -- Era NUM_TALENT_COLUMNS (WotLK keeps 4 columns)
local TIERS      = 11          -- WotLK deepest tier (51-pt talent; vanilla was 7)
local TREE_GAP   = 132         -- gap between trees (tuned so the rightmost focal zone stays ~246px)
-- Per-tree header band (offsets tier 1 down from the tree top; the spec name is auto-centred in the
-- band above tier 1 by HEADER_CENTER_Y). Tuned so top->name, name->tier1, tier10->tier11 and
-- tier11->bottom are all ~equal (~28px). VERIFY against a screenshot — depends on the name height
-- and the exact top content edge; nudge this (name gaps) + TALENT_H (bottom gap) to fine-tune.
local HEADER_H   = 28
local BOTTOMBAR_H= 80
local INSET_L, INSET_R, INSET_T, INSET_B = 110, 84, 48, 20 -- content layout margin (trees/bar)
-- Content-fill insets. The bg must tuck fully UNDER the nineslice (which draws on OVERLAY over it)
-- or a transparent sliver shows between the chrome and the fill. Sides/bottom = 0 (the opaque
-- corner pieces cover the bg's square corners); top = 22 (just under the title band).
local CHROME_T, CHROME_B, CHROME_L, CHROME_R = 22, 0, 0, 0

-- Header (spec name + points) vertical CENTRE, in tree-local y (tree top = 0). Centred in the band
-- between the top nineslice's visible inner edge and the top edge of the tier-1 nodes.
local HEADER_CENTER_Y = ((INSET_T + TREE_Y_SHIFT - CHROME_T) - HEADER_H) / 2

local TREE_W = (COLS - 1) * PITCH_X + NODE        -- horizontal (162)
local TREE_H = (TIERS - 1) * PITCH_Y + NODE       -- vertical: (11-1)*44 + 36 = 476
local CONTENT_H = HEADER_H + TREE_H               -- 68 + 476 = 544

-- ----------------------------------------------------------------------------
-- Frame size. WotLK talent panel — narrower/shorter than retail's PlayerSpellsFrame (this is a
-- STANDALONE window, not a tab in a maximized shell). 3×(4-col × 11-tier) grids fit a 1214-wide
-- talents frame (trees left-anchored at INSET_L; the rightmost ~20% stays art-only — the spec
-- painting's focal subject sits top-right, so the cover-crop keeps top+right).
--
-- Height budget at PITCH_Y 44 / 11 tiers:
--   INSET_T 48 + TREE_Y_SHIFT 16 + HEADER_H 68 + TREE_H 476 (10*44+36) + LAST_TIER_EXTRA 28
--   + BOTTOMBAR_H 80 = 688, + ~62 breathing room ≈ 750. (Was vanilla 7-tier: 7 rows @ PITCH_Y 64
--   = 420 tree + a 55px capstone drop; the WotLK 11-tier tree at the tighter pitch lands the same
--   ~476 tree height, so the 750 frame budget holds.)
local TALENT_W = 1214
-- Height tuned so the gap below the deepest tier (tier11 -> top of the bottom bar) matches the other
-- ~28px gaps. = treeOffset(64) + NODE/2 + HEADER_H + 10*PITCH_Y + LAST_TIER_EXTRA + capstone half(28)
-- + GAP(28) + BOTTOMBAR_H(80) ≈ 714. VERIFY/tune with HEADER_H.
local TALENT_H = 714
-- Default top offset from UIParent TOP (this frame's own scaled units). Negative = below the top.
local FRAME_TOP_OFFSET = -55

-- ----------------------------------------------------------------------------
-- Node center, relative to the tree frame's TOPLEFT (retail anchors CENTER→TOPLEFT).
-- ----------------------------------------------------------------------------
local function nodeCenter(tier, column)
  -- x: prefer the per-tier CENTERED layout (built per tab by T.SetCenteredLayout) so a tier with
  -- fewer than COLS talents is packed + centered (3 talents -> middle centered, etc.); else the grid.
  local lay = T._tierColX
  local x = (lay and lay[tier] and lay[tier][column]) or ((column - 1) * PITCH_X + NODE / 2)
  -- The final (deepest) tier can take extra drop; WotLK sets LAST_TIER_EXTRA=0 → no-op.
  local extraLast = (tier == TIERS) and LAST_TIER_EXTRA or 0
  local y = -((tier - 1) * PITCH_Y) - NODE / 2 - HEADER_H - extraLast
  return x, y
end

-- Expose layout + helpers so Behavior.lua can drive real rendering.
T.LAYOUT = { NODE = NODE, ICON = ICON, PITCH = PITCH_X, PITCH_X = PITCH_X, PITCH_Y = PITCH_Y,
             COLS = COLS, TIERS = TIERS, HEADER_H = HEADER_H, HEADER_CENTER_Y = HEADER_CENTER_Y }
T.nodeCenter = nodeCenter

-- Build the per-tier centered column->x map for the CURRENT tab from its occupied (tier,column)
-- cells. Mirrors the reference TalentFrameBase TALENT_CENTER_ROWS mod: each tier's k talents are
-- packed and centered across the COLS-wide row. nodeCenter reads the result (T._tierColX).
-- `occupied` = array of { tier=, column= }. Edges connect occupied cells only, so empty columns
-- need no interpolation here.
function T.SetCenteredLayout(occupied)
  local byTier = {}
  for _, c in ipairs(occupied) do
    if c.tier and c.column then
      byTier[c.tier] = byTier[c.tier] or {}
      byTier[c.tier][c.column] = true
    end
  end
  local lay = {}
  for tier, cols in pairs(byTier) do
    local list = {}
    for col = 1, COLS do if cols[col] then list[#list + 1] = col end end
    local k = #list
    lay[tier] = {}
    local leftCenter = NODE / 2 + ((COLS - k) / 2) * PITCH_X   -- center-x of the first packed talent
    for m = 1, k do
      lay[tier][list[m]] = leftCenter + (m - 1) * PITCH_X
    end
  end
  T._tierColX = lay
end

-- Frame geometry (consumed by Behavior / others). The host insets the content by CHROME_*.
T.FRAME = {
  W = TALENT_W, H = TALENT_H,
  CHROME_T = CHROME_T, CHROME_B = CHROME_B, CHROME_L = CHROME_L, CHROME_R = CHROME_R,
  INSET_L = INSET_L, INSET_R = INSET_R, INSET_T = INSET_T, INSET_B = INSET_B,
  BOTTOMBAR_H = BOTTOMBAR_H,
}

-- ----------------------------------------------------------------------------
-- Node button factory (one square/circle/capstone node).
-- ----------------------------------------------------------------------------
local MOCK_ICONS = {
  "Interface\\Icons\\Spell_Holy_PowerInfusion",
  "Interface\\Icons\\Spell_Shadow_ShadowWordPain",
  "Interface\\Icons\\Spell_Holy_Smite",
  "Interface\\Icons\\Spell_Frost_FrostBolt02",
  "Interface\\Icons\\Spell_Nature_Lightning",
}

-- shape -> StateBorder atlas stem (state suffix appended). T.SHAPE_ATLAS comes from NodeData.lua.
-- VERIFY: on 3.3.5a the "circle" (active) shape can't be masked round, so NodeData maps it (and
-- square) to the square art family; this resolver just appends the state and tolerates a nil table.
local function ringAtlas(shape, state)
  local stem = (T.SHAPE_ATLAS and T.SHAPE_ATLAS[shape]) or "talents-node-square"
  return stem .. "-" .. state
end

-- shadow atlas per shape (square/circle have their own; capstone reuses square shadow).
local function shadowAtlas(shape)
  return "talents-node-square-shadow"   -- circle maps to square art on 3.3.5a; capstone reuses this too
end

-- selectable-glow atlas per shape. square/circle = "<stem>-greenglow"; the apex (capstone) glow is
-- named "talents-node-apex-large-glow" (no -green prefix).
local function glowAtlas(shape)
  return "talents-node-square-greenglow"   -- all shapes use the square glow on 3.3.5a (incl. capstone)
end

-- Hover-border alpha per state (full-bright on Normal/Selectable/Maxed; dim 0.4 otherwise).
local HOVER_ALPHA = { yellow = 1, green = 1, gray = 0.4, locked = 0.4, red = 0.4 }

local function CreateNode(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(NODE, NODE)

  b.shadow = b:CreateTexture(nil, "BACKGROUND")
  b.shadow:SetPoint("CENTER")   -- retail centres the shadow (soft halo); size set per shape

  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(ICON, ICON)
  b.icon:SetPoint("CENTER")

  -- VERIFY (mask DROPPED): NewEra clipped the square icon to a circle for round nodes via
  -- CreateMaskTexture + talents-node-circle-mask. CreateMaskTexture / AddMaskTexture are DEAD on
  -- 3.3.5a, so we DROP the round icon clip entirely. Round ("circle") nodes instead get the GRAY
  -- SQUARE frame (see SetVisual) — the spellbook's passive-frame trick — so the square icon fits
  -- its frame cleanly with no poking corners.

  -- the colored ring/frame; atlas swapped per (shape, state)
  b.ring = b:CreateTexture(nil, "OVERLAY")
  b.ring:SetPoint("CENTER")

  -- hover border (StateBorderHover): ADD copy of the ring, shown only on mouseover. Sub-level 1 so
  -- it sits just above the ring (OVERLAY/0).
  b.hover = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.hover:SetPoint("CENTER")
  b.hover:SetBlendMode("ADD")
  b.hover:Hide()

  -- Sheen: a soft diagonal glint that periodically sweeps across OWNED talents (subtle). NewEra
  -- masked this per-shape (dead on 3.3.5a). Since our nodes are square, we instead SLIDE the soft
  -- sheen across the node (its texcoord stays on the atlas sub-rect, so no bleed) with a fade
  -- envelope that's ~0 at the extremes — Behavior's OnUpdate driver flows it, active spec only.
  b.sheen = b:CreateTexture(nil, "ARTWORK", nil, 1)   -- above the icon, under the ring frame
  if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(b.sheen, "talents-sheen-node", false) end
  b.sheen:SetBlendMode("ADD")
  b.sheen:SetPoint("CENTER")
  b.sheen:Hide()

  -- "selectable" green glow (shown for available-not-maxed)
  b.glow = b:CreateTexture(nil, "OVERLAY", nil, 2)
  b.glow:SetPoint("CENTER")
  b.glow:SetBlendMode("ADD")
  b.glow:Hide()

  -- selectable-glow pulse (retail SelectableGlow.Anim: 0→0.15→0 over 2s, looping).
  b.glowAnim = b.glow:CreateAnimationGroup()
  b.glowAnim:SetLooping("REPEAT")
  if b.glowAnim.SetToFinalAlpha then b.glowAnim:SetToFinalAlpha(true) end
  local gIn  = b.glowAnim:CreateAnimation("Alpha")
  gIn:SetDuration(1); gIn:SetOrder(1); gIn:SetSmoothing("OUT")
  if gIn.SetFromAlpha then gIn:SetFromAlpha(0); gIn:SetToAlpha(0.15)
  else gIn:SetChange(0.15) end   -- 3.3.5a Alpha anim uses SetChange (delta), not From/To
  local gOut = b.glowAnim:CreateAnimation("Alpha")
  gOut:SetDuration(1); gOut:SetOrder(2); gOut:SetSmoothing("IN")
  if gOut.SetFromAlpha then gOut:SetFromAlpha(0.15); gOut:SetToAlpha(0)
  else gOut:SetChange(-0.15) end

  -- Spend flash: a quick gold pop over the node when a point is added during an edit (Behavior
  -- calls b:PlaySpend() when the rank increases). Soft proc-border glow, sized to the ring in
  -- SetVisual; fades fast. ADD blend over everything (sub-level 3 > glow's 2 > hover's 1).
  b.flash = b:CreateTexture(nil, "OVERLAY", nil, 3)
  b.flash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
  b.flash:SetBlendMode("ADD")
  b.flash:SetVertexColor(1, 0.9, 0.45)
  b.flash:SetPoint("CENTER")
  b.flash:Hide()
  b.flashAnim = b.flash:CreateAnimationGroup()
  local fIn = b.flashAnim:CreateAnimation("Alpha")
  fIn:SetDuration(0.07); fIn:SetOrder(1)
  if fIn.SetFromAlpha then fIn:SetFromAlpha(0); fIn:SetToAlpha(1) else fIn:SetChange(1) end
  local fOut = b.flashAnim:CreateAnimation("Alpha")
  fOut:SetDuration(0.38); fOut:SetOrder(2); fOut:SetSmoothing("OUT")
  if fOut.SetFromAlpha then fOut:SetFromAlpha(1); fOut:SetToAlpha(0) else fOut:SetChange(-1) end
  b.flashAnim:SetScript("OnFinished", function() b.flash:Hide() end)
  function b:PlaySpend()
    if not self.flash then return end
    self.flashAnim:Stop()
    self.flash:SetAlpha(0); self.flash:Show()
    self.flashAnim:Play()
  end

  -- rank number — small, centred just BELOW the icon (off the busy art so X/Y stays readable).
  -- Anchored to the ICON's bottom (not the button frame) so it tucks right under the visible art
  -- and clears the next tier's node at the tight 44px pitch. OUTLINE for legibility over the bg.
  b.rank = b:CreateFontString(nil, "OVERLAY")
  b.rank:SetJustifyH("CENTER")
  b.rank:SetFont((STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"), 10, "OUTLINE")
  b.rank:SetPoint("TOP", b.icon, "BOTTOM", 0, -1)

  -- shape: "square"|"circle"|"capstone"|"capstonesquare"  state: yellow|green|gray|locked|red
  function b:SetVisual(shape, state, iconTex, rankText)
    self._shape = shape
    -- A deepest-tier signature talent is "big" regardless of active/passive (a prominent final node).
    local big       = (shape == "capstone") or (shape == "capstonesquare")
    -- VERIFY: ALL shapes use the SQUARE art family on 3.3.5a (no round icon mask). "circle" (active)
    -- still routes here as square art — NodeData.lua decides which gray/colored frame stem to use.
    local base = big and (NODE + 48) or NODE                     -- final talent: large 84px footprint
    if shape == "capstonesquare" or shape == "capstone" then
      base = CAPSTONE_SQUARE_SIZE                                -- both deepest-tier nodes use the square capstone size
    else
      base = base * SQUARE_NODE_FIT                              -- scale the whole square node (56/64)
    end
    local ringAdj   = 0                                          -- StateBorder = node size; frames the icon
    self.ring:SetSize(base + ringAdj, base + ringAdj)
    self.icon:SetSize(base * ICON_INSET, base * ICON_INSET)     -- inset so corners tuck under the border
    if self.sheen then self.sheen:SetSize(base * ICON_INSET, base * ICON_INSET); self._sheenSpan = base * ICON_INSET end   -- peak = icon size (driver re-sizes per frame)
    if self.flash then self.flash:SetSize(base + ringAdj + 18, base + ringAdj + 18) end
    NE.tex.SetAtlas(self.ring, ringAtlas(shape, state), false)
    -- Shadow = soft halo (~1.9x the node). Size to the native dimension scaled by base/40.
    local shN = (shape == "circle") and 76 or 78
    local sc  = base / 40
    self.shadow:SetSize(shN * sc, shN * sc)
    NE.tex.SetAtlas(self.shadow, shadowAtlas(shape), false)
    self.icon:SetTexture(iconTex or MOCK_ICONS[1])
    -- dim icon when unavailable (retail desaturates locked/disabled)
    local dim = (state == "gray" or state == "locked")
    if self.icon.SetDesaturated then self.icon:SetDesaturated(dim) end
    self.icon:SetVertexColor(dim and 0.65 or 1, dim and 0.65 or 1, dim and 0.65 or 1)
    -- Hover border: ADD copy of the state ring at the ring's size, alpha per state.
    NE.tex.SetAtlas(self.hover, ringAtlas(shape, state), false)
    self.hover:SetSize(base + ringAdj, base + ringAdj)
    self._hoverAlpha = HOVER_ALPHA[state] or 1
    self.hover:SetAlpha(self._hoverAlpha)
    self.hover:Hide()

    -- Selectable glow: pulse (0→0.15→0, 2s) instead of a static fill.
    if state == "green" then
      NE.tex.SetAtlas(self.glow, glowAtlas(shape), false)
      self.glow:SetSize(base + 22, base + 22)
      self.glow:Show()
      if not self.glowAnim:IsPlaying() then self.glowAnim:Play() end
    else
      self.glowAnim:Stop()
      self.glow:Hide()
    end
    self.rank:SetText(rankText or "")
    if state == "green" then self.rank:SetTextColor(0.1, 1, 0.1)
    elseif state == "gray" or state == "locked" then self.rank:SetTextColor(0.6, 0.6, 0.6)
    else self.rank:SetTextColor(1, 0.82, 0) end
  end

  -- Hover show/hide as methods so Behavior's tooltip OnEnter/OnLeave can also drive the border.
  function b:ShowHover() if self.hover and (self._hoverAlpha or 0) > 0 then self.hover:Show() end end
  function b:HideHover() if self.hover then self.hover:Hide() end end
  b:SetScript("OnEnter", b.ShowHover)
  b:SetScript("OnLeave", b.HideHover)

  return b
end
T.CreateNode = CreateNode   -- exposed for Behavior.lua

-- ----------------------------------------------------------------------------
-- Per-tree frame: header + pooled nodes / edges / gates.
-- ----------------------------------------------------------------------------
local function CreateTreeFrame(parent, index)
  local tf = CreateFrame("Frame", "NE_TalentTreeFrame" .. index, parent)
  tf:SetSize(TREE_W, CONTENT_H)
  tf.index = index

  -- header — name + points, vertically centred in the chrome→tier-1 band (HEADER_CENTER_Y).
  tf.headerName = tf:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  if _G.SystemFont_Shadow_Large2 then tf.headerName:SetFontObject(_G.SystemFont_Shadow_Large2) end
  if tf.headerName.SetTextScale then tf.headerName:SetTextScale(0.9) end
  tf.headerName:SetPoint("CENTER", tf, "TOP", 0, HEADER_CENTER_Y)
  tf.headerName:SetTextColor(1, 1, 1)

  tf.headerPts = tf:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  if _G.Game32Font_Shadow2 then tf.headerPts:SetFontObject(_G.Game32Font_Shadow2) end
  tf.headerPts:SetPoint("LEFT", tf.headerName, "RIGHT", 8, 0)
  tf.headerPts:SetTextColor(0.1, 1.0, 0.1)   -- green when >0; set in Behavior

  -- pools (keyed by talent index for nodes; sequential for edges/gates)
  tf.nodePool, tf.edgePool, tf.gatePool = {}, {}, {}
  tf._edgeN, tf._gateN = 0, 0

  function tf:AcquireNode(idx)
    local n = self.nodePool[idx]
    if not n then n = CreateNode(self); self.nodePool[idx] = n end
    return n
  end
  function tf:HideUnusedNodes(used)
    for idx, n in pairs(self.nodePool) do if not used[idx] then n:Hide() end end
  end

  -- dependency edges = DIRECT dotted lines (3.3.5a has no CreateLine / no Texture:SetRotation, and
  -- the 8-arg SetTexCoord rotate trick needs a calibrated wrap texture — a solid one just fills a
  -- box). So Behavior draws the straight prereq->dependent line as evenly-spaced square pips; the
  -- pool just hands out reusable dot textures (under the nodes) and Behavior owns the geometry.
  function tf:AcquireDot()
    self._edgeN = self._edgeN + 1
    local d = self.edgePool[self._edgeN]
    if not d then
      d = self:CreateTexture(nil, "ARTWORK", nil, -2)   -- under nodes
      d:SetTexture("Interface\\Buttons\\WHITE8X8")
      self.edgePool[self._edgeN] = d
    end
    d:Show()
    return d
  end
  function tf:ResetEdges() self._edgeN = 0 end
  function tf:HideUnusedEdges()
    for i = self._edgeN + 1, #self.edgePool do self.edgePool[i]:Hide() end
  end

  -- tier gate ("Requires N points in <Tree>") anchored left of a tier row.
  function tf:AcquireGate()
    self._gateN = self._gateN + 1
    local g = self.gatePool[self._gateN]
    if not g then
      g = CreateFrame("Frame", nil, self)
      g:SetSize(124, 28)
      g.icon = g:CreateTexture(nil, "ARTWORK")
      g.icon:SetPoint("RIGHT", g, "RIGHT", 0, 0)
      NE.tex.SetAtlas(g.icon, "talents-gate", true)
      g.text = g:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      g.text:SetPoint("RIGHT", g.icon, "LEFT", -4, 1)
      g.text:SetTextColor(1, 0.64, 0.56)
      self.gatePool[self._gateN] = g
    end
    g:Show()
    return g
  end
  function tf:ResetGates() self._gateN = 0 end
  function tf:HideUnusedGates()
    for i = self._gateN + 1, #self.gatePool do self.gatePool[i]:Hide() end
  end

  return tf
end

-- ----------------------------------------------------------------------------
-- Background (single class painting behind the three trees). Behavior.Populate calls
-- T.SetBackground(tab) with the dominant tab; classBackgroundNick is the build-time fallback.
-- ----------------------------------------------------------------------------
function T.BackgroundNick(tab)
  local _, classFile = UnitClass("player")
  local list = T.CLASS_BACKGROUND and T.CLASS_BACKGROUND[classFile]
  return (list and list[tab or 1]) or (list and list[1]) or "talents-background-warrior-arms"
end
function T.SetBackground(tab)
  local f = T.frame
  if not (f and f.bg) then return end
  local nick = T.BackgroundNick(tab)
  NE.tex.SetAtlas(f.bg, nick, false)   -- sets texcoord to the atlas element's sub-rect
  -- "Cover" crop so the art isn't stretched, biased to keep the TOP and the RIGHT (the spec art's
  -- focal point sits top-right). At the 1214 talents width the dest is TALLER in aspect than the
  -- source → full height shows and the crop trims the LEFT-side atmosphere.
  local a = NE.tex.atlases and NE.tex.atlases[nick:lower()]
  if not a or not a.width or not a.height then return end
  local dw = TALENT_W - CHROME_L - CHROME_R
  local dh = TALENT_H - CHROME_T - CHROME_B - BOTTOMBAR_H
  local destA, srcA = dw / dh, a.width / a.height
  local L, R, Tp, B = a.left, a.right, a.top, a.bottom
  if destA > srcA then
    B = Tp + (B - Tp) * (srcA / destA)   -- dest wider → crop height; keep top
  else
    L = R - (R - L) * (destA / srcA)     -- dest taller → crop width; keep right (focal)
  end
  f.bg:SetTexCoord(L, R, Tp, B)
end
local function classBackgroundNick() return T.BackgroundNick(T.DEFAULT_BACKGROUND_TAB or 1) end

-- ----------------------------------------------------------------------------
-- VERIFY (ambient FX DROPPED): NewEra painted a drifting cloud + parallax dust atmosphere over the
-- spec background (talents-animations-clouds / -particles), every region clipped by a soft vignette
-- via CreateMaskTexture + talents-animations-mask-full. The whole FX stack RELIES on masking (the
-- vignette is what kept the clouds/dust from hard-clipping at the panel edges); masking is dead on
-- 3.3.5a, so the entire ambient FX layer is DROPPED. The static spec background (f.bg) remains.

-- ----------------------------------------------------------------------------
-- Build the STANDALONE window ONCE. Mirrors the spellbook's buildWindow (modules/spellbook/
-- Window.lua): bare CreateFrame on UIParent, NE.chrome.Apply portrait-frame chrome, a content-root
-- Host child inset by CHROME_*, ESC-close + open/close sounds. Hidden by default. Render-on-show
-- calls T.Populate (defined by Behavior.lua).
-- ----------------------------------------------------------------------------
local function buildWindow()
  if T.frame then return T.frame end

  local f = CreateFrame("Frame", "NE_TalentFrame", UIParent)
  f:SetSize(TALENT_W, TALENT_H)
  f:SetPoint("TOP", UIParent, "TOP", 0, FRAME_TOP_OFFSET)
  -- HIGH + toplevel so an enlarged window stays above the action/spell bars (which sit in MEDIUM);
  -- toplevel raises the clicked window within its strata.
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  -- Drag-to-move WITH saved position (persists account-wide across /reload + sessions, like the
  -- spellbook). Falls back to the default TOP anchor on first use.
  if NE.FrameUtil and NE.FrameUtil.PersistWindowPosition then
    NE.FrameUtil.PersistWindowPosition(f, "talents",
      { point = "TOP", relPoint = "TOP", x = 0, y = FRAME_TOP_OFFSET })
  else
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  end
  f:Hide()
  T.frame = f

  -- Open/close sounds (igCharacterInfoOpen/Close), via a child watcher (never on the frame).
  guard("sounds", function()
    if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
      NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
    end
  end)

  -- ESC close. EscClose registers with UISpecialFrames (out-of-combat path); fall back manually.
  guard("escClose", function()
    if NE.FrameUtil and NE.FrameUtil.EscClose then
      NE.FrameUtil.EscClose("NE_TalentFrame")
    else
      tinsert(UISpecialFrames, "NE_TalentFrame")
    end
  end)

  -- Modern DF chrome (nineslice on f.NineSlice + Rock bg + title). noPortrait=true: we own the
  -- portrait as a TALENT icon below (PanelChrome's default fill is the player portrait + a watcher).
  guard("chrome.Apply", function()
    if NE.chrome and NE.chrome.Apply then
      NE.chrome.Apply(f, {
        layout     = "PortraitFrameTemplate",
        title      = TALENTS or "Talents",
        noPortrait = true,
      })
    end
  end)

  -- Own the portrait region (mirrors the spellbook's pattern). The icon fill must sit ABOVE the
  -- host wood but BELOW the gold ring (a BORDER-layer texture on f.NineSlice), so host it on
  -- f.NineSlice too, at ARTWORK (< BORDER).
  guard("portrait", function()
    local ringFrame = f.NineSlice or f
    if not f.portrait then f.portrait = ringFrame:CreateTexture(nil, "ARTWORK") end
    if NE.portrait and NE.portrait.ApplyCutout then
      NE.portrait.ApplyCutout(f.portrait, f)
    end
    -- A talent-ish placeholder icon; Behavior.Populate may swap to the dominant spec icon.
    f.portrait:SetTexture("Interface\\Icons\\Ability_Marksmanship")
    f:HookScript("OnShow", function()
      if f.portrait and not f.portrait:GetTexture() then
        f.portrait:SetTexture("Interface\\Icons\\Ability_Marksmanship")
      end
    end)
  end)

  -- A dark fill behind the content so no transparent backdrop shows between content and chrome.
  do
    local tint = f:CreateTexture(nil, "BACKGROUND")
    if tint.SetColorTexture then
      tint:SetColorTexture(0.04, 0.04, 0.05, 1)
    else
      tint:SetTexture(0.04, 0.04, 0.05, 1)   -- VERIFY: 3.3.5a SetTexture(r,g,b,a) flat-color path
    end
    tint:SetPoint("TOPLEFT", CHROME_L, -CHROME_T)
    tint:SetPoint("BOTTOMRIGHT", -CHROME_R, CHROME_B)
    f.bgTint = tint
  end

  -- single class background over the fill, behind all three trees (above the bottom bar)
  do
    local bg = f:CreateTexture(nil, "BORDER")
    bg:SetPoint("TOPLEFT", CHROME_L, -CHROME_T)
    bg:SetPoint("BOTTOMRIGHT", -CHROME_R, CHROME_B + BOTTOMBAR_H)
    NE.tex.SetAtlas(bg, classBackgroundNick(), false)
    f.bg = bg
  end
  guard("setBackground", function() T.SetBackground(T.DEFAULT_BACKGROUND_TAB or 1) end)

  -- bottom bar (the Apply/Reset/points controls are wired in Behavior.lua; this is just the strip).
  do
    local bar = f:CreateTexture(nil, "ARTWORK")
    bar:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", CHROME_L, CHROME_B)
    bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -CHROME_R, CHROME_B)
    bar:SetHeight(BOTTOMBAR_H)
    NE.tex.SetAtlas(bar, "talents-background-bottombar", false)
    f.bottomBar = bar
  end

  -- Three tree frames, laid out left-to-right and CENTERED in the window. (Was left-anchored at
  -- INSET_L, which left dead space on the right.) Block = 3 trees + 2 gaps; margin centers it.
  f.trees = {}
  local treesBlockW = 3 * TREE_W + 2 * TREE_GAP
  local treesLeft   = (TALENT_W - treesBlockW) / 2
  for i = 1, 3 do
    local tf = CreateTreeFrame(f, i)
    tf:SetPoint("TOPLEFT", f, "TOPLEFT",
      treesLeft + (i - 1) * (TREE_W + TREE_GAP),
      -(INSET_T + TREE_Y_SHIFT))
    f.trees[i] = tf
  end

  -- Window scale: its OWN per-window setting via NE.scale (no longer tied to the spellbook). Modes:
  -- "ui" (follow the UI Scale slider), "none" (pixel-perfect), "custom" (slider). Re-applied on show.
  local function applyWindowScale(fr)
    if NE.scale and NE.scale.Apply then
      if fr and NE.scale.SetFrame then NE.scale.SetFrame("talents", fr) end
      NE.scale.Apply("talents")
    elseif fr and fr.SetScale then
      fr:SetScale(0.8)
    end
  end
  guard("windowScale", function() applyWindowScale(f) end)
  f:HookScript("OnShow", function(self) applyWindowScale(self) end)

  -- Render-on-show. Behavior.lua defines T.Populate; guard since it loads around/after this file.
  f:HookScript("OnShow", function()
    if T.Populate then guard("populate", T.Populate) end
  end)

  return f
end
T.Build = buildWindow

-- T.Host() — the content-root Frame the renderer parents everything to. Inset by the chrome
-- constants, created once (exactly like SB.Host()).
function T.Host()
  if T.host then return T.host end
  local f = T.frame or buildWindow()
  if not f then return nil end
  local host = CreateFrame("Frame", "NE_TalentHost", f)
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", f, "TOPLEFT", CHROME_L, -CHROME_T)
  host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -CHROME_R, CHROME_B)
  host:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
  T.host = host
  return host
end

-- ----------------------------------------------------------------------------
-- Show / hide / toggle.
-- ----------------------------------------------------------------------------
function T.SetShown(shown)
  local f = T.frame or buildWindow()
  if not f then return end
  if shown then f:Show() else f:Hide() end   -- content runs via OnShow (see buildWindow)
end
function T.Open()  T.SetShown(true)  end
function T.Close() T.SetShown(false) end
function T.Toggle()
  local f = T.frame or buildWindow()
  if not f then return end
  if f:IsShown() then f:Hide() else f:Show() end
end

-- ----------------------------------------------------------------------------
-- SLASH + Blizzard reroute. /netalents toggles the window; ToggleTalentFrame is rerouted so the
-- default talent key opens ours (original saved first).
-- ----------------------------------------------------------------------------
local function interceptBlizzard()
  if T._intercepted then return end
  T._intercepted = true
  if type(ToggleTalentFrame) == "function" and not T._origToggle then
    T._origToggle = ToggleTalentFrame
    -- TAINT: ToggleTalentFrame is an INSECURE FrameXML toggle (PlayerTalentFrame is LoadOnDemand
    -- on 3.3.5a — no conflict). Out-of-combat reroute; safe. This covers the keybind (TOGGLETALENTS),
    -- which looks up the global at press time.
    ToggleTalentFrame = function() T.Toggle() end
  end
  -- The micromenu's TalentMicroButton binds OnClick to the ORIGINAL ToggleTalentFrame *by reference*
  -- in FrameXML (<OnClick function="ToggleTalentFrame"/>), so reassigning the global never reaches it.
  -- Reroute the button's handler directly so it opens our window too.
  if TalentMicroButton and TalentMicroButton.SetScript then
    TalentMicroButton:SetScript("OnClick", function() T.Toggle() end)
  end
end

_G.SLASH_NETALENTS1 = "/netalents"
SlashCmdList = SlashCmdList or {}
SlashCmdList["NETALENTS"] = function() T.Toggle() end

-- ----------------------------------------------------------------------------
-- Boot. PLAYER_LOGIN builds the window + Host + Blizzard reroute. Scale/display events re-pin.
-- ----------------------------------------------------------------------------
local function boot(event)
  if event == "PLAYER_LOGIN" then
    buildWindow()
    T.Host()                       -- create the content root the renderer parents to
    guard("intercept", interceptBlizzard)
    return
  end
  if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    -- Re-assert the per-window scale (matters for "none"/pixel-perfect which depends on the UI scale).
    if T.frame then
      if NE.scale and NE.scale.Apply then guard("rescale", function() NE.scale.Apply("talents") end)
      elseif T.frame.SetScale then guard("rescale", function() T.frame:SetScale(0.8) end) end
    end
    return
  end
end

if NE.modules and NE.modules.Register then
  NE.modules.Register("Talents", {
    default  = true,
    label    = "Talents Panel",
    category = "Windows",
    desc     = "The modern talents window. Turn off to use the standard Blizzard talent window.",
    events   = { "PLAYER_LOGIN", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" },
    onBoot   = function(event) boot(event) end,
  })
else
  -- Standalone fallback boot if the module registry isn't available.
  local bf = CreateFrame("Frame")
  bf:RegisterEvent("PLAYER_LOGIN")
  bf:RegisterEvent("UI_SCALE_CHANGED")
  bf:RegisterEvent("DISPLAY_SIZE_CHANGED")
  bf:SetScript("OnEvent", function(_, event) boot(event) end)
end
