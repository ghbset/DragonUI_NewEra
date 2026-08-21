-- DragonUI_NewEra/modules/talents/Behavior.lua — real talent data + preview/commit wiring.
--
-- DOWNPORT: NewEra Talents/Behavior.lua (Era/Classic vanilla-grid talent API) -> 3.3.5a (WotLK).
-- Drives the 3 tree frames built in Talents.lua (the scaffold) from the LIVE 3.3.5a talent API:
--   * real nodes (GetTalentInfo) placed by (tier, column) on each per-tree frame
--   * dependency-bar edges (GetTalentPrereqs -> AXIS-ALIGNED strip + arrowhead, NOT rotated lines)
--   * preview/commit: click->AddPreviewTalentPoints, Apply (confirm) / Reset, points readout
--
-- WotLK API REMAP (vs the NewEra Era source):
--   * Era's GetTalentInfo returned a TABLE and C_SpecializationInfo.* wrappers. 3.3.5a has the FLAT
--     globals: GetTalentInfo (10-tuple), GetTalentTabInfo, GetActiveTalentGroup, GetNumTalentTabs,
--     GetNumTalents, GetTalentPrereqs. We re-table GetTalentInfo via talentInfo() below; everything
--     downstream keeps the table shape it expects. There is NO talentID on 3.3.5a, so the tooltip
--     and click paths key on (tab, index) instead.
--   * Preview talents shipped in patch 3.1: previewTalents gate, AddPreviewTalentPoints,
--     LearnPreviewTalents, ResetGroupPreviewTalentPoints, GetGroupPreviewTalentPointsSpent — all
--     native. AddPreviewTalentPoints on 3.3.5a takes NO sign/delta arg (adds +1); right-click
--     "remove a point" is done discard-and-re-add (see nodeRightClick).
--
-- Commit flow mirrors Blizzard's stock 3.3.5a Blizzard_TalentUI.lua: gated on previewTalents
-- (forced on while the window is open, restored on close), LearnPreviewTalents() commits (behind a
-- confirm), discard via ResetGroupPreviewTalentPoints. Nothing is destructive until the confirm.
--
-- EDGES: NewEra rotated arrow textures with atan2/cos/sin + Texture:SetRotation. SetRotation and
-- CreateLine DO NOT EXIST on 3.3.5a (both Cata+), so edges here are axis-aligned WHITE8X8 pips laid
-- along an ORTHOGONAL routed path (vertical drops + horizontal runs, like Blizzard's stock 3.3.5a
-- TalentFrame.lua branch drawing) rather than a free diagonal that would slice through unrelated
-- nodes. The router and its obstacle model live in the EDGE DRAWING block below.

local NE = DragonUI_NewEra
local L = NE.L
local T = NE.talents or {}

-- Triumvirate-only realm gate. Triumvirate ships a custom native dual-spec-unlock UI (gold cost +
-- a 3rd/4th spec tier) that other servers (Turtle WoW, Project Epoch, stock 3.3.5a) don't have; any
-- code that assumes it exists must be gated behind this so it doesn't run on a realm without it.
local function IsTriumvirate()
  return (GetRealmName and GetRealmName() or "") == "Triumvirate"
end
T.IsTriumvirate = IsTriumvirate
NE.talents = T

local PER_TIER     = 5   -- tier t needs (t-1)*5 points spent in that tree (WotLK == vanilla rule)
local PET_PER_TIER = 3   -- PET talents gate every 3 points/tier (not 5) — the WotLK pet rule

-- Pet talents exist ONLY for hunter pets (Ferocity / Tenacity / Cunning); GetPetTalentTree returns
-- nil for warlock/quest pets or no pet. This is the gate for showing the Pet tab + rendering it.
local function petHasTalents()
  if not GetPetTalentTree then return false end
  local ok, tree = pcall(GetPetTalentTree)
  return (ok and tree ~= nil and tree ~= "") and true or false
end
T.PetHasTalents = petHasTalents

-- True when the window is currently showing the PET talent view (Pet tab selected AND a talented pet
-- is out). Consumed by SpecTabs (tab art), Glyphs (pane visibility) and Populate.
function T.PetViewActive() return (T._petView and petHasTalents()) and true or false end
function T.SetPetView(on)
  T._petView = on and true or false
  if T._petView and T.GlyphsSetActive then T.GlyphsSetActive(false) end
end

-- ----------------------------------------------------------------------------
-- INSPECT MODE. The window renders ANOTHER unit's trees, read-only.
--
-- Every talent getter on 3.3.5a takes an `isInspect` flag in the same argument slot this file was
-- passing a hard `false` to (GetTalentInfo / GetNumTalentTabs / GetNumTalents / GetTalentTabInfo /
-- GetTalentPrereqs / GetActiveTalentGroup), and the client fills that side from the last
-- NotifyInspect. So inspect mode is one flag threaded through the reads plus `editable = false`:
-- no preview, no Apply/Reset, no spec switching, no glyphs (there is no inspect glyph API here).
--
-- Set by T.ShowInspect(unit) and cleared when the window closes, so the next open is the player's.
--
-- EVERY PLACE THE FLAG HAS TO REACH, and what each one does about it. Two bugs have already come
-- out of a call site that was missed (the portrait wearing the viewer's class, and issue #77's
-- tooltip), so the list is written down rather than rediscovered:
--
--   GetTalentInfo / GetNumTalentTabs / GetNumTalents / GetTalentTabInfo / GetTalentPrereqs
--                            pass `inspect` (Populate + talentInfo)
--   GetActiveTalentGroup     inspect only; stays ARGLESS on the player path on purpose
--   GameTooltip:SetTalent    passes `inspect` — the tooltip is not a getter but takes the same flag
--   UnitClass                the portrait's class circle AND T.BackgroundNick's spec painting
--   GetUnspentTalentPoints   never reached: unspentPoints returns 0 while inspecting
--   AddPreviewTalentPoints / LearnPreviewTalents / ResetGroupPreviewTalentPoints / the preview CVar
--                            never reached: editable is false, and wireNode refuses clicks
--   playerTierDepth          deliberately the PLAYER's; the talent TABLES are server-wide, so the
--                            depth is the same for whoever is being rendered
--   Glyphs / Loadouts / SpecTabs
--                            player-only by design; their panes and buttons are hidden in this mode
-- ----------------------------------------------------------------------------
function T.InspectUnit() return T._inspectUnit end
local function inspecting() return (T._inspectUnit and true) or false end
T.IsInspecting = inspecting

-- Edge tint: yellow (prereq satisfied + invested) vs dim gray (not yet active).
local EDGE_ACTIVE   = { 1.0, 0.82, 0.0,  0.95 }
local EDGE_INACTIVE = { 0.62, 0.58, 0.48, 0.85 }   -- muted tan, visible over the dark spec painting

-- Sound cues (3.3.5a named PlaySound kits; swap any of these to taste). pcall-guarded so a missing
-- name never errors. add/remove are tied to ACTUAL rank changes (see Populate), not raw clicks.
local SOUNDS = {
  add    = "igMainMenuOptionCheckBoxOn",   -- crisp tick when a point lands
  remove = "igCharacterInfoTab",           -- softer click when a point is refunded
  apply  = "gsTitleOptionOK",              -- clean, understated confirm when talents are committed
  spec   = "igMainMenuOpen",               -- whoosh on a successful spec switch
}
local function playSound(key)
  local s = SOUNDS[key]
  if s and PlaySound then pcall(PlaySound, s) end
end

-- ----------------------------------------------------------------------------
-- API adapter: GetTalentInfo (flat 10-tuple) -> the table shape the renderer expects.
-- 3.3.5a: name, iconTexture, tier, column, rank, maxRank, isExceptional, meetsPrereq,
--         previewRank, meetsPreviewPrereq. NO talentID exists (keyed on tab/index).
-- ----------------------------------------------------------------------------
local function talentInfo(tab, i, group, isPet)
  if not GetTalentInfo then return nil end
  local name, icon, tier, column, rank, maxRank, isExceptional,
        meetsPrereq, previewRank, meetsPreviewPrereq = GetTalentInfo(tab, i, inspecting(), isPet or false, group)
  if not name then return nil end
  return {
    name               = name,
    icon               = icon,
    tier               = tier,
    column             = column,
    rank               = rank or 0,
    maxRank            = maxRank or 0,
    isExceptional      = isExceptional,
    meetsPrereq        = meetsPrereq,
    previewRank        = previewRank,
    meetsPreviewPrereq = meetsPreviewPrereq,
    talentID           = nil,   -- none on 3.3.5a
  }
end

local function previewOn()
  local ok, v
  if GetCVarBool then ok, v = pcall(GetCVarBool, "previewTalents"); if ok then return v end end
  if GetCVar then ok, v = pcall(GetCVar, "previewTalents"); if ok then return v == "1" end end
  return false
end

local function unspentPoints(group, isPet)
  if inspecting() then return 0 end
  if GetUnspentTalentPoints then
    local ok, v = pcall(GetUnspentTalentPoints, false, isPet or false, group)
    if ok and v then return v end
  end
  if not isPet and UnitCharacterPoints then return UnitCharacterPoints("player") or 0 end
  return 0
end

local function previewSpent(group, isPet)
  if GetGroupPreviewTalentPointsSpent then
    local ok, v = pcall(GetGroupPreviewTalentPointsSpent, isPet or false, group)
    if ok and v then return v end
  end
  return 0
end

local function discardPreview(group, isPet)
  if InCombatLockdown and InCombatLockdown() then return end
  isPet = isPet or false
  if ResetPreviewTalentPoints then pcall(ResetPreviewTalentPoints) end
  if ResetGroupPreviewTalentPoints then
    pcall(ResetGroupPreviewTalentPoints, isPet, group)
    pcall(ResetGroupPreviewTalentPoints, group)
  end
  if not (AddPreviewTalentPoints and GetTalentInfo and GetNumTalentTabs) then return end
  for _pass = 1, 2 do
    for t = 1, (GetNumTalentTabs(false, isPet) or 0) do
      local n = (GetNumTalents and GetNumTalents(t, false, isPet)) or 0
      for i = n, 1, -1 do
        local info = talentInfo(t, i, group, isPet)
        if info then
          local staged = (info.previewRank or 0) - (info.rank or 0)
          if staged > 0 then pcall(AddPreviewTalentPoints, t, i, -staged, isPet, group) end
        end
      end
    end
  end
end
T.DiscardPreview = discardPreview

-- ----------------------------------------------------------------------------
-- State machine. Map a talentInfo to (state, displayRank).
-- ----------------------------------------------------------------------------
local function computeState(info, tabPointsSpent, preview, available, perTier)
  perTier = perTier or PER_TIER
  local liveRank    = info.rank or 0
  local displayRank = (preview and info.previewRank) or liveRank
  local meets       = (preview and info.meetsPreviewPrereq) or info.meetsPrereq
  local tierUnlocked= ((info.tier or 1) - 1) * perTier <= tabPointsSpent
  local forceDesat  = (available <= 0) and (displayRank == 0)
  local colored     = meets and tierUnlocked and not forceDesat
  local state
  if preview and displayRank < liveRank then
    state = "red"
  elseif not colored then
    state = (not tierUnlocked and displayRank == 0) and "locked" or "gray"
  elseif displayRank == 0 then
    state = "green"
  elseif displayRank >= (info.maxRank or displayRank) then
    state = "yellow"
  else
    state = "yellow"
  end
  return state, displayRank
end

-- ----------------------------------------------------------------------------
-- Node Interactions
-- ----------------------------------------------------------------------------
local function nodeLeftClick(self)
  if not AddPreviewTalentPoints then return end
  if self._isPet then
    pcall(AddPreviewTalentPoints, self._tab, self._index, 1, true, T._activeGroup or 1)
  else
    pcall(AddPreviewTalentPoints, self._tab, self._index, 1)
  end
end

local function nodeRightClick(self)
  if not AddPreviewTalentPoints then return end
  if self._isPet then
    pcall(AddPreviewTalentPoints, self._tab, self._index, -1, true, T._activeGroup or 1)
  else
    pcall(AddPreviewTalentPoints, self._tab, self._index, -1)
  end
end

local function nodeTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  if self._tab and self._index and GameTooltip.SetTalent then
    local isPet   = self._isPet or false
    local inspect = inspecting()
    local group   = isPet and (T._activeGroup or 1) or (T._viewGroup or T._activeGroup or 1)
    -- GameTooltip:SetTalent takes the same isInspect flag every talent GETTER does, in the same
    -- argument slot, and it is just as load-bearing: with a hard `false` the tooltip describes the
    -- talent YOU have at that (tab, index) rather than the one under the cursor (issue #77). No
    -- preview side to an inspected unit either, so that argument goes false with it.
    local preview = (not inspect) and previewOn() or false
    local ok = pcall(GameTooltip.SetTalent, GameTooltip, self._tab, self._index, inspect, isPet, group, preview)
    if not ok then
      ok = pcall(GameTooltip.SetTalent, GameTooltip, self._tab, self._index, inspect, isPet, group)
    end
    if ok then
      GameTooltip:Show()
      return
    end
  end
  if self._tipName then
    GameTooltip:SetText(self._tipName, 1, 1, 1, 1, true)
    GameTooltip:Show()
  end
end

local function wireNode(n)
  if n._wired then return end
  n._wired = true
  n:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  n:SetScript("OnClick", function(self, btn)
    if InCombatLockdown and InCombatLockdown() then return end
    -- Read-only while inspecting: the preview API has no inspect side, so a click here would spend
    -- YOUR points on whatever node happens to sit under the cursor.
    if T.IsInspecting and T.IsInspecting() then return end
    if not self._isPet and (T._viewGroup or 1) ~= (T._activeGroup or 1) then return end
    if btn == "LeftButton" then nodeLeftClick(self)
    elseif btn == "RightButton" then nodeRightClick(self) end
    nodeTooltip(self)
  end)
  n:SetScript("OnEnter", function(self)
    if self.ShowHover then self:ShowHover() end
    nodeTooltip(self)
  end)
  n:SetScript("OnLeave", function(self)
    if self.HideHover then self:HideHover() end
    GameTooltip:Hide()
  end)
end
T._WireNode = wireNode

-- ----------------------------------------------------------------------------
-- EDGE DRAWING & FLOW ENGINE
--
-- Edges are ORTHOGONAL polylines, never free diagonals. T.SetColumnLayout gives every
-- column ONE x across the whole tree, so the common case — a prereq directly above its
-- dependent in the same column — is already aligned and draws as a plain vertical. This
-- block handles the rest: a prereq that sits in a DIFFERENT column, where a straight
-- center-to-center line would cut diagonally across whatever node lies between the two
-- rows, which is exactly the "which talent needs which?" confusion to avoid.
--
-- So each edge is ROUTED: a handful of axis-aligned candidate paths (straight, an L,
-- a Z that jogs sideways in the corridor between two tier rows, or a wider detour
-- around a blocking node) are scored against this tree's node boxes and the cheapest
-- wins. Node art is a HARD obstacle; the rank text under each icon is a soft one
-- (avoided when there's an alternative, crossed when there isn't). Ties fall to the
-- straightest path, so an aligned link stays a single unbroken run, and a bent one
-- leaves the prereq's SIDE and drops into the dependent from above (see SIDE_EXIT).
-- ----------------------------------------------------------------------------
local sqrt, abs, floor = math.sqrt, math.abs, math.floor
local DOT_SIZE, DOT_GAP, HEAD_SIZE, FLOW_SPEED = 4, 9, 7, 16

-- Routing costs. Path cost = pixel length + bends + obstacles hit; HIT_HARD is large
-- enough that any collision-free route beats any route through a node.
local NODE_PAD  = 2                     -- slack around the art before a line counts as "through" it
local HIT_HARD, HIT_SOFT, BEND_COST = 1000, 6, 4
-- A bent edge should leave its PREREQ sideways and drop into the dependent from above, not drop out
-- of the prereq's underside and slide into the dependent's flank. Charged against any bent path whose
-- first leg is vertical. Above HIT_SOFT (so it outranks clipping a rank number) and far below
-- HIT_HARD (so it never argues a line through a node). Straight runs are exempt — they have no bend.
local SIDE_EXIT = 7
local RANK_HALF_W, RANK_DROP, RANK_H = 11, 1, 12   -- the "3/5" box hanging under an icon
local EMPTY = {}

-- Obstacle for one placed node, in tree-local coords (y is negative-down). Keyed by cell so the
-- edge's own endpoints can be excluded — a line always leaves/enters its own node.
local function addNodeRect(tf, tier, col, x, y, visual)
  local rects = tf._nodeRects
  if not rects then return end
  local vs   = visual or T.LAYOUT.NODE
  local half = vs / 2 + NODE_PAD
  local key  = tier * 10 + col
  tf._nodeHalf[key] = half
  rects[#rects + 1] = { key = key, cost = HIT_HARD, tier = tier, cx = x,
                        x0 = x - half, x1 = x + half, y0 = y - half, y1 = y + half }
  local top = y - vs * (T.LAYOUT.ICON_INSET or 0.84) / 2 - RANK_DROP
  rects[#rects + 1] = { key = key, cost = HIT_SOFT, tier = tier, cx = x,
                        x0 = x - RANK_HALF_W, x1 = x + RANK_HALF_W, y0 = top - RANK_H, y1 = top }
end

-- Clear vertical lanes for a detour past a node sitting on the direct path, nearest first. Derived
-- from where the rows in the way ACTUALLY sit rather than a fixed half-pitch offset — under the
-- centred layout a half-pitch step often lands straight on the neighbouring column.
local function sideLanes(rects, lo, hi, sx)
  local pitch = (T.LAYOUT and T.LAYOUT.PITCH_X) or 54
  local xs, seen = {}, {}
  for i = 1, #rects do
    local r = rects[i]
    if r.cost == HIT_HARD and r.tier > lo and r.tier < hi and not seen[r.cx] then
      seen[r.cx] = true
      xs[#xs + 1] = r.cx
    end
  end
  if #xs == 0 then return { sx } end
  table.sort(xs)
  local lanes = { xs[1] - pitch * 0.5, xs[#xs] + pitch * 0.5 }
  for i = 1, #xs - 1 do
    if xs[i + 1] - xs[i] > ((T.LAYOUT and T.LAYOUT.NODE) or 36) then
      lanes[#lanes + 1] = (xs[i] + xs[i + 1]) / 2
    end
  end
  -- nearest lane first, but strongly prefer one that stays inside the tree's own column band
  local width = (T.LAYOUT and T.LAYOUT.TREE_W) or ((((T.LAYOUT and T.LAYOUT.COLS) or 4) - 1) * pitch + 36)
  local function rank(x)
    return abs(x - sx) + ((x < 0 or x > width) and 1000 or 0)
  end
  table.sort(lanes, function(a, b) return rank(a) < rank(b) end)
  return lanes
end

-- Mid-y of each tier-to-tier corridor: gapY[t] is the clear band between tier t and t+1. Rebuilt per
-- tab because nodeCenter's y depends on T._nodeYShift (shallow pet trees are centred vertically).
local function buildGapY()
  local tiers = (T.LAYOUT and T.LAYOUT.TIERS) or 11
  local g = {}
  for t = 1, tiers - 1 do
    local _, y1 = T.nodeCenter(t, 1)
    local _, y2 = T.nodeCenter(t + 1, 1)
    g[t] = (y1 + y2) / 2
  end
  return g
end

-- Every candidate segment is axis-aligned, so "does it hit this box" is a plain AABB overlap.
local function pathCost(pts, rects, skipA, skipB)
  local n = #pts / 2
  local cost = (n - 2) * BEND_COST
  if n > 2 and abs(pts[3] - pts[1]) < 0.5 then cost = cost + SIDE_EXIT end
  for i = 1, n - 1 do
    local ax, ay = pts[i * 2 - 1], pts[i * 2]
    local bx, by = pts[i * 2 + 1], pts[i * 2 + 2]
    cost = cost + abs(bx - ax) + abs(by - ay)
    local x0, x1 = ax, bx; if x0 > x1 then x0, x1 = x1, x0 end
    local y0, y1 = ay, by; if y0 > y1 then y0, y1 = y1, y0 end
    for k = 1, #rects do
      local r = rects[k]
      if r.key ~= skipA and r.key ~= skipB
         and not (x1 < r.x0 or x0 > r.x1 or y1 < r.y0 or y0 > r.y1) then
        cost = cost + r.cost
      end
    end
  end
  return cost
end

-- Drop repeated and collinear points so a degenerate Z scores (and draws) as the straight line it is.
local function tidyPath(pts)
  local out = {}
  for i = 1, #pts, 2 do
    local x, y = pts[i], pts[i + 1]
    local n = #out
    if not (n >= 2 and abs(out[n - 1] - x) < 0.5 and abs(out[n] - y) < 0.5) then
      out[n + 1], out[n + 2] = x, y
    end
  end
  local k = 2
  while k * 2 <= #out - 2 do
    local ax, ay = out[k * 2 - 3], out[k * 2 - 2]
    local bx, by = out[k * 2 - 1], out[k * 2]
    local cx, cy = out[k * 2 + 1], out[k * 2 + 2]
    if (abs(ax - bx) < 0.5 and abs(bx - cx) < 0.5) or (abs(ay - by) < 0.5 and abs(by - cy) < 0.5) then
      table.remove(out, k * 2); table.remove(out, k * 2 - 1)
    else
      k = k + 1
    end
  end
  return out
end

local function routeCandidates(tf, sx, sy, ex, ey, sTier, dTier)
  local gapY, rects = tf._gapY or EMPTY, tf._nodeRects or EMPTY
  local out = {}
  -- Straight run — only when the two nodes actually line up (a diagonal is never a candidate).
  if abs(ex - sx) < 0.5 or abs(ey - sy) < 0.5 then
    out[#out + 1] = { sx, sy, ex, ey }
  end
  local lo, hi = sTier, dTier
  if lo > hi then lo, hi = hi, lo end
  -- Corridors available to a sideways jog, nearest the DEPENDENT first: entering a talent from
  -- directly above reads as "this is what feeds it" better than sliding in from the side.
  local corridors = {}
  if hi > lo then
    if dTier >= sTier then
      for t = hi - 1, lo, -1 do corridors[#corridors + 1] = gapY[t] end
    else
      for t = lo, hi - 1 do corridors[#corridors + 1] = gapY[t] end
    end
  else
    corridors[#corridors + 1] = gapY[lo - 1]   -- same tier: hop over...
    corridors[#corridors + 1] = gapY[lo]       -- ...or under the row
  end
  for i = 1, #corridors do
    local g = corridors[i]
    if g then out[#out + 1] = { sx, sy, sx, g, ex, g, ex, ey } end
  end
  -- Plain Ls (one bend, so these win over a Z whenever they're clear). Side-exit first: it's the
  -- preferred shape (see SIDE_EXIT), and the vertical-first one is the fallback when it's blocked.
  out[#out + 1] = { sx, sy, ex, sy, ex, ey }
  out[#out + 1] = { sx, sy, sx, ey, ex, ey }
  -- Two rows or more apart: allow a swing out into a clear lane to get around a node sitting on the
  -- direct path (a same-column prereq with an unrelated talent parked between the two).
  local g1, g2 = gapY[lo], gapY[hi - 1]
  if g1 and g2 and abs(g1 - g2) > 0.5 then
    local lanes = sideLanes(rects, lo, hi, sx)
    for i = 1, math.min(#lanes, 2) do
      local jx = lanes[i]
      out[#out + 1] = { sx, sy, sx, g1, jx, g1, jx, g2, ex, g2, ex, ey }
    end
  end
  return out
end

-- Pull the path's ends back to the node borders so the dots start and stop clear of the art. Both
-- walk segment by segment, so a trim longer than the first/last leg eats into the next one.
local function trimStart(pts, amount)
  while amount > 0 and #pts >= 4 do
    local dx, dy = pts[3] - pts[1], pts[4] - pts[2]
    local len = sqrt(dx * dx + dy * dy)
    if len > amount + 0.01 then
      pts[1] = pts[1] + dx / len * amount
      pts[2] = pts[2] + dy / len * amount
      return true
    end
    table.remove(pts, 1); table.remove(pts, 1)
    amount = amount - len
  end
  return #pts >= 4
end

local function trimEnd(pts, amount)
  while amount > 0 and #pts >= 4 do
    local n = #pts
    local dx, dy = pts[n - 3] - pts[n - 1], pts[n - 2] - pts[n]
    local len = sqrt(dx * dx + dy * dy)
    if len > amount + 0.01 then
      pts[n - 1] = pts[n - 1] + dx / len * amount
      pts[n]     = pts[n] + dy / len * amount
      return true
    end
    pts[n] = nil; pts[n - 1] = nil
    amount = amount - len
  end
  return #pts >= 4
end

-- Walk the polyline by arc length so the flow stays evenly spaced around the corners.
local function positionEdge(edge, phase)
  local dots, span, gap, pts, cum = edge.dots, edge.span, edge.gap, edge.pts, edge.cum
  local nseg = #cum - 1
  for i = 1, #dots do
    local dist = ((i - 1) * gap + phase) % span
    local s = 1
    while s < nseg and dist > cum[s + 1] do s = s + 1 end
    local segLen = cum[s + 1] - cum[s]
    local t = (segLen > 0) and ((dist - cum[s]) / segLen) or 0
    local ax, ay = pts[s * 2 - 1], pts[s * 2]
    local bx, by = pts[s * 2 + 1], pts[s * 2 + 2]
    local d = dots[i]
    d:ClearAllPoints()
    d:SetPoint("CENTER", edge.tf, "TOPLEFT", ax + (bx - ax) * t, ay + (by - ay) * t)
  end
end

local SHEEN_SWEEP, SHEEN_PEAK = 0.7, 0.40
local GLINT_MIN, GLINT_MAX    = 0.25, 0.95
local sin, pi, random = math.sin, math.pi, math.random

local function updateSheen(node, clock)
  local s = node.sheen
  if not s then return end
  local st = node._sheenStart
  if not st then if s:IsShown() then s:Hide() end return end
  local t = (clock - st) / SHEEN_SWEEP
  if t < 0 or t >= 1 then node._sheenStart = nil; s:Hide(); return end
  local env  = sin(pi * t)
  local full = node._sheenSpan or 28
  local sz = full * env
  if sz < 1 then sz = 1 end
  s:SetSize(sz, sz)
  local d = full * (t - 0.5)
  s:ClearAllPoints()
  s:SetPoint("CENTER", node, "CENTER", d, -d)
  s:SetAlpha(SHEEN_PEAK)
  s:Show()
end

local function ensureFlowDriver(f)
  if f._edgeFlow then return end
  f._edgeFlow = true
  T._edgePhase = 0
  T._sheenClock = 0
  T._nextGlint = 0
  f:HookScript("OnUpdate", function(self, dt)
    dt = dt or 0
    T._edgePhase = (T._edgePhase or 0) + dt * FLOW_SPEED
    if T._edgePhase > 1e6 then T._edgePhase = 0 end
    local clock = (T._sheenClock or 0) + dt
    if clock > 1e6 then clock = 0; T._nextGlint = 0 end
    T._sheenClock = clock
    local trees = self.trees
    if not trees then return end
    for i = 1, 3 do
      local tf = trees[i]
      if tf then
        local el = tf._edgeList
        if el then for j = 1, #el do positionEdge(el[j], T._edgePhase) end end
        local sl = tf._sheenList
        if sl then for j = 1, #sl do updateSheen(sl[j], clock) end end
      end
    end
    if clock >= (T._nextGlint or 0) then
      local cand = {}
      for i = 1, 3 do
        local sl = trees[i] and trees[i]._sheenList
        if sl then for j = 1, #sl do cand[#cand + 1] = sl[j] end end
      end
      local n = #cand
      if n > 0 then
        if n > 1 and T._lastGlint then
          for k = n, 1, -1 do if cand[k] == T._lastGlint then table.remove(cand, k); break end end
        end
        local pick = cand[random(#cand)]
        pick._sheenStart = clock
        T._lastGlint = pick
      end
      local mult = math.max(1, 6 - n)
      T._nextGlint = clock + (GLINT_MIN + random(0, math.floor((GLINT_MAX - GLINT_MIN) * 1000)) / 1000) * mult
    end
  end)
end

local function drawEdge(tf, sTier, sCol, dTier, dCol, color)
  local sx, sy = T.nodeCenter(sTier, sCol)
  local ex, ey = T.nodeCenter(dTier, dCol)
  if abs(ex - sx) < 1 and abs(ey - sy) < 1 then return end

  local rects = tf._nodeRects or EMPTY
  local skipA, skipB = sTier * 10 + sCol, dTier * 10 + dCol
  local cands = routeCandidates(tf, sx, sy, ex, ey, sTier, dTier)
  local best, bestCost
  for i = 1, #cands do
    local pts = tidyPath(cands[i])
    if #pts >= 4 then
      local cost = pathCost(pts, rects, skipA, skipB)
      if not bestCost or cost < bestCost then best, bestCost = pts, cost end
    end
  end
  if not best then return end

  local halves = tf._nodeHalf or EMPTY
  local fallback = T.LAYOUT.NODE / 2
  if not (trimStart(best, (halves[skipA] or fallback) + 1)) then return end
  if not (trimEnd(best, (halves[skipB] or fallback) + 1)) then return end

  local cum, span = { 0 }, 0
  local n = #best / 2
  for i = 1, n - 1 do
    local dx = best[i * 2 + 1] - best[i * 2 - 1]
    local dy = best[i * 2 + 2] - best[i * 2]
    span = span + sqrt(dx * dx + dy * dy)
    cum[i + 1] = span
  end
  if span <= 0 then return end

  local count = floor(span / DOT_GAP + 0.5)
  if count < 1 then count = 1 end
  local gap = span / count
  local dots = {}
  for _ = 1, count do
    local d = tf:AcquireDot()
    d:SetSize(DOT_SIZE, DOT_SIZE)
    d:SetVertexColor(color[1], color[2], color[3], color[4])
    dots[#dots + 1] = d
  end
  local edge = { tf = tf, pts = best, cum = cum, span = span, gap = gap, dots = dots }
  tf._edgeList[#tf._edgeList + 1] = edge
  positionEdge(edge, T._edgePhase or 0)
end

-- ----------------------------------------------------------------------------
-- BOTTOM BAR SETUP
-- ----------------------------------------------------------------------------
StaticPopupDialogs["NE_TALENTS_LEARN"] = {
  text = CONFIRM_LEARN_PREVIEW_TALENTS or "Learn the selected talents? Spent points cannot be refunded without a respec.",
  button1 = YES, button2 = NO,
  OnAccept = function()
    if LearnPreviewTalents then pcall(LearnPreviewTalents, T.PetViewActive and T.PetViewActive() or false) end
    playSound("apply")
  end,
  hideOnEscape = 1, timeout = 0, exclusive = 1, whileDead = 1,
}

local function buildBottomBar(f)
  if f._barBuilt then return end
  f._barBuilt = true

  f.pointsText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.pointsText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", (T.FRAME.CHROME_L or 0) + 24, (T.FRAME.CHROME_B or 0) + 30)
  f.pointsText:SetText("")

  local apply = CreateFrame("Button", "NE_TalentApplyButton", f, "UIPanelButtonTemplate")
  apply:SetSize(120, 26)
  apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -((T.FRAME.CHROME_R or 0) + 24), (T.FRAME.CHROME_B or 0) + 27)
  apply:SetText(APPLY or "Apply")
  apply:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    StaticPopup_Show("NE_TALENTS_LEARN")
  end)
  f.apply = apply

  local reset = CreateFrame("Button", "NE_TalentResetButton", f, "UIPanelButtonTemplate")
  reset:SetSize(120, 26)
  reset:SetPoint("RIGHT", apply, "LEFT", -8, 0)
  reset:SetText(RESET or "Reset")
  reset:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    discardPreview(T._activeGroup or 1, T.PetViewActive and T.PetViewActive() or false)
    if T.Refresh then T.Refresh() end
  end)
  f.reset = reset

  local activate = CreateFrame("Button", "NE_TalentActivateButton", f, "UIPanelButtonTemplate")
  activate:SetSize(160, 26)
  activate:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -((T.FRAME.CHROME_R or 0) + 24), (T.FRAME.CHROME_B or 0) + 27)
  activate:SetText(L["Activate"])
  activate:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end

    if IsTriumvirate() then
      local unlockBtn = _G["TriumvirateSpecActivateButton"]
      local nativeNumGroups = (GetNumTalentGroups and GetNumTalentGroups()) or 2
      local isLocked = (unlockBtn and unlockBtn:IsShown()) or ((T._viewGroup or 1) > nativeNumGroups)

      if isLocked then
        if unlockBtn and unlockBtn.Click then unlockBtn:Click() end
        return
      end
    end

    if SetActiveTalentGroup and T._viewGroup then pcall(SetActiveTalentGroup, T._viewGroup) end
  end)
  activate:Hide()
  f.activate = activate

  f._setSubButtonsEnabled = function(on)
    if apply.SetEnabled then apply:SetEnabled(on) else
      if on then apply:Enable() else apply:Disable() end
    end
    if reset.SetEnabled then reset:SetEnabled(on) else
      if on then reset:Enable() else reset:Disable() end
    end
  end
end

-- ----------------------------------------------------------------------------
-- VISUAL DECORATIONS & BACKGROUNDS
-- ----------------------------------------------------------------------------
local PET_BG_PATH = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\"
local PET_BG_FILE = {
  HunterPetFerocity = "Pet_Ferocity",
  HunterPetTenacity = "Pet_Tenacity",
  HunterPetCunning   = "Pet_Cunning",
}
local function applyPetBackground(f, bgName)
  if not f then return end
  if not f.petBg then
    local tx = f:CreateTexture(nil, "BORDER")
    tx:SetPoint("TOPLEFT",     f, "TOPLEFT",     (T.FRAME.CHROME_L or 0), -(T.FRAME.CHROME_T or 0))
    tx:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(T.FRAME.CHROME_R or 0), (T.FRAME.CHROME_B or 0) + (T.FRAME.BOTTOMBAR_H or 0))
    tx:SetTexCoord(0, 1, 0, 1)
    f.petBg = tx
  end
  local file = bgName and PET_BG_FILE[bgName]
  if file then f.petBg:SetTexture(PET_BG_PATH .. file) end
  if f.bg then f.bg:Hide() end
  f.petBg:Show()
end

local function refreshPetPortrait(f)
  local p = f and f.portrait
  if not (p and SetPortraitTexture) then return end
  if not (T.PetViewActive and T.PetViewActive()) then return end 
  if UnitExists and not UnitExists("pet") then return end
  p:SetTexCoord(0, 1, 0, 1)
  pcall(SetPortraitTexture, p, "pet")
end

local function ensurePetPortrait(f)
  refreshPetPortrait(f)
  if C_Timer and C_Timer.After then
    C_Timer.After(0,   function() refreshPetPortrait(f) end)
    C_Timer.After(0.3, function() refreshPetPortrait(f) end)
  end
  if not f._nePetPortraitWatcher then
    local w = CreateFrame("Frame", nil, f)
    w:RegisterEvent("UNIT_PORTRAIT_UPDATE")
    w:RegisterEvent("UNIT_PET")
    w:SetScript("OnEvent", function(_, _, unit)
      if unit == nil or unit == "pet" or unit == "player" then refreshPetPortrait(f) end
    end)
    f._nePetPortraitWatcher = w
  end
end
T._ApplyPetBackground = applyPetBackground

-- Deepest tier the PLAYER's own trees use. 11 on a stock 3.3.5a client, but a server running custom
-- talent tables can be shallower (Project Epoch ships the 2.4.3 trees at 9), and the window has to
-- shrink to match or the last tier floats two rows above the bottom bar. Read from the class trees
-- only — never the pet's, which is genuinely shallow and gets centred in the class depth instead.
-- Cached: the talent TABLES don't change during a session (only the points spent in them do).
local function playerTierDepth()
  if T._playerTiers then return T._playerTiers end
  local maxTier = 0
  local numTabs = (GetNumTalentTabs and GetNumTalentTabs(false, false)) or 0
  for tab = 1, numTabs do
    local n = (GetNumTalents and GetNumTalents(tab, false, false)) or 0
    for i = 1, n do
      local _, _, tier = GetTalentInfo(tab, i, false, false)
      if tier and tier > maxTier then maxTier = tier end
    end
  end
  if maxTier < 1 then return nil end   -- data not in yet; re-ask on the next Populate
  T._playerTiers = maxTier
  return maxTier
end

-- Size the window to that depth. Called at login (so the window is already the right size the first
-- time it is shown) and again from Populate (in case the talent API wasn't answering yet at login).
function T.ApplyTierDepth()
  if not T.SetTierDepth then return end
  local depth = playerTierDepth()
  if depth then T.SetTierDepth(depth) end
end

-- ----------------------------------------------------------------------------
-- MAIN DATA REFRESH MATRIX (T.Populate)
-- ----------------------------------------------------------------------------
function T.Populate()
  local f = T.frame
  if not f or not GetTalentInfo then return end
  buildBottomBar(f)
  ensureFlowDriver(f)

  T.ApplyTierDepth()   -- before anything is placed; a no-op at WotLK's 11 tiers

  if T._petView and not petHasTalents() then T._petView = false end
  local isPet   = T._petView and true or false
  local perTier = isPet and PET_PER_TIER or PER_TIER

  local inspect = inspecting()
  -- Deliberately still ARGLESS on the player path: GetActiveTalentGroup(false, isPet) is not quite
  -- the same call this made before (a pet has its own group), and the inspect work has no business
  -- changing what the pet view reads.
  local active = (GetActiveTalentGroup
                  and (inspect and GetActiveTalentGroup(true, isPet) or GetActiveTalentGroup())) or 1
  if T._viewGroup == nil or T._lastActive ~= active then T._viewGroup = active end
  T._activeGroup, T._lastActive = active, active
  local numGroups = (GetNumTalentGroups and (GetNumTalentGroups() or 1)) or 1
  if numGroups < 2 then T._viewGroup = active end
  
  local group    = (isPet or inspect) and active or T._viewGroup
  -- Never editable while inspecting: the preview API writes to YOUR talents whatever is on screen.
  local editable = (not inspect) and (isPet or (group == active))
  local viewChanged = (T._lastViewGroup ~= group) or (T._lastPetView ~= isPet)
  T._lastViewGroup, T._lastPetView = group, isPet
  T._group = group
  local preview = previewOn() and editable
  local numTabs = (GetNumTalentTabs and GetNumTalentTabs(inspect, isPet)) or 0

  for i = 1, 3 do
    local tf = f.trees[i]
    if tf and not tf._defPoint then tf._defPoint = { tf:GetPoint() } end
  end
  if isPet and numTabs <= 1 then
    local tf = f.trees[1]
    local dp = tf._defPoint
    local treeW = (T.LAYOUT and T.LAYOUT.TREE_W) or tf:GetWidth() or 0
    tf:ClearAllPoints()
    tf:SetPoint("TOPLEFT", f, "TOPLEFT", (T.FRAME.W - treeW) / 2, dp and dp[5] or -64)
  else
    for i = 1, 3 do
      local tf = f.trees[i]
      local dp = tf and tf._defPoint
      if dp then tf:ClearAllPoints(); tf:SetPoint(unpack(dp)) end
    end
  end

  T._nodeYShift = 0
  if isPet then
    local layTiers = (T.LAYOUT and T.LAYOUT.TIERS) or 11
    local pitchY   = (T.LAYOUT and T.LAYOUT.PITCH_Y) or 44
    local maxTier, nt = 1, (GetNumTalents and GetNumTalents(1, false, true)) or 0
    for i = 1, nt do
      local info = talentInfo(1, i, group, true)
      if info and info.tier and info.tier > maxTier then maxTier = info.tier end
    end
    T._nodeYShift = math.max(0, layTiers - maxTier) * pitchY / 2
  end

  local unspent       = unspentPoints(group, isPet)
  local previewSpentAll = preview and previewSpent(group, isPet) or 0
  local available     = unspent - previewSpentAll

  local domIcon, domSpent, domTab = nil, -1, 1
  local petBgName

  for tabIdx = 1, 3 do
    local tf = f.trees[tabIdx]
    tf:ResetEdges(); tf:ResetGates()
    tf._edgeList = {}
    tf._sheenList = {}
    tf._nodeRects, tf._nodeHalf = {}, {}   -- obstacles for the edge router; filled as nodes are placed
    local used = {}

    if tabIdx <= numTabs then
      local name, icon, spent, _bg, prevSpent = GetTalentTabInfo(tabIdx, inspect, isPet, group)
      if isPet and _bg then petBgName = _bg end
      local tabPointsSpent = (spent or 0) + (preview and (prevSpent or 0) or 0)
      tf.headerName:SetText(string.upper(name or ("Tree " .. tabIdx)))
      tf.headerPts:SetText(tostring(tabPointsSpent))
      tf.headerPts:SetTextColor((tabPointsSpent > 0) and 0.1 or 0.5, (tabPointsSpent > 0) and 1.0 or 0.5, (tabPointsSpent > 0) and 0.1 or 0.5)
      
      local nameW = (tf.headerName:GetStringWidth() or 0) * 0.9
      local ptsW  = tf.headerPts:GetStringWidth() or 0
      tf.headerName:ClearAllPoints()
      tf.headerName:SetPoint("LEFT", tf, "TOPLEFT", (tf:GetWidth() - (nameW + 8 + ptsW)) / 2, (T.LAYOUT and T.LAYOUT.HEADER_CENTER_Y) or -13)

      if (spent or 0) > domSpent then domSpent = (spent or 0); domIcon = icon; domTab = tabIdx end

      local numTalents = (GetNumTalents and GetNumTalents(tabIdx, inspect, isPet)) or 0
      local byCell, infos, prereqs = {}, {}, {}

      -- Prereqs are read here (not in the edge pass below) so the API is queried once per talent.
      local occupied = {}
      for i = 1, numTalents do
        local info = talentInfo(tabIdx, i, group, isPet)
        if info and info.tier and info.column then
          infos[i] = info
          occupied[#occupied + 1] = { tier = info.tier, column = info.column }
          if GetTalentPrereqs then
            prereqs[i] = { GetTalentPrereqs(tabIdx, i, inspect, isPet, group) }
          end
        end
      end
      if T.SetColumnLayout then T.SetColumnLayout(occupied) end

      for i = 1, numTalents do
        local info = infos[i]
        if info and info.tier and info.column then
          local shape = T.ResolveShape(info)
          local state, displayRank = computeState(info, tabPointsSpent, preview, (editable and available) or 0, perTier)
          local node = tf:AcquireNode(i); used[i] = true
          node._tab, node._index, node._talentID = tabIdx, i, nil
          node._isPet = isPet
          node._tipName = info.name
          local rankText = (info.maxRank and info.maxRank > 0) and (tostring(displayRank) .. "/" .. tostring(info.maxRank)) or ""
          node:SetVisual(shape, state, info.icon, rankText)
          
          if editable and not viewChanged and node._shownRank then
            if displayRank > node._shownRank then
              if node.PlaySpend then node:PlaySpend() end
              playSound("add")
            elseif displayRank < node._shownRank then
              playSound("remove")
            end
          end
          node._shownRank = displayRank
          
          -- Dimmed only for the OTHER-SPEC view, where the contrast against the active spec is the
          -- point. An inspected unit's tree is the only thing on screen, so it renders at full
          -- strength — read-only is not the same as secondary.
          local dimmed = (not editable) and (not inspect)
          node:SetAlpha(dimmed and 0.66 or 1)
          if dimmed and node.icon and node.icon.SetDesaturated then node.icon:SetDesaturated(true) end
          if not dimmed and node.icon and node.icon.SetDesaturated then node.icon:SetDesaturated(false) end
          local x, y = T.nodeCenter(info.tier, info.column)
          node:ClearAllPoints(); node:SetPoint("CENTER", tf, "TOPLEFT", x, y); node:Show()
          addNodeRect(tf, info.tier, info.column, x, y, node._visualSize)
          wireNode(node)
          
          if editable and (displayRank or 0) > 0 then
            tf._sheenList[#tf._sheenList + 1] = node
          else
            node._sheenStart = nil
            if node.sheen then node.sheen:Hide() end
          end
          byCell[info.tier * 10 + info.column] = info
        end
      end

      -- Edges for the editable view AND the inspected one; only the dimmed other-spec view skips
      -- them (there they would read as clutter behind the spec you are actually in).
      if editable or inspect then
        tf._gapY = buildGapY()   -- after SetRowLayout/_nodeYShift, so the corridors match the rows
        for i = 1, numTalents do
          local info = infos[i]
          local pre  = prereqs[i]
          if info and pre then
            for p = 1, #pre, 4 do
              local ptier, pcol = pre[p], pre[p + 1]
              local srcInfo = ptier and pcol and byCell[ptier * 10 + pcol]
              if srcInfo then
                local srcRank = (preview and srcInfo.previewRank) or srcInfo.rank or 0
                local meets   = (preview and info.meetsPreviewPrereq) or info.meetsPrereq
                local active  = meets and srcRank > 0
                local color   = active and EDGE_ACTIVE or EDGE_INACTIVE
                drawEdge(tf, ptier, pcol, info.tier, info.column, color)
              end
            end
          end
        end
      end
    else
      tf.headerName:SetText(""); tf.headerPts:SetText("")
    end

    tf:HideUnusedNodes(used)
    tf:HideUnusedEdges()
    tf:HideUnusedGates()
  end

  if f.portrait then
    if isPet then
      ensurePetPortrait(f)
    else
      -- WHOSE class: the inspected unit's when there is one. Hard-coding "player" here is what left
      -- an inspected Death Knight's talents wearing the viewer's own class icon.
      local _, classFile = UnitClass((inspect and T._inspectUnit) or "player")
      local c = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
      if c then
        f.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
        f.portrait:SetTexCoord(c[1], c[2], c[3], c[4])
      elseif domIcon then
        f.portrait:SetTexCoord(0, 1, 0, 1); f.portrait:SetTexture(domIcon)
      end
    end
  end

  if isPet then
    applyPetBackground(f, petBgName)
  else
    if f.petBg then f.petBg:Hide() end
    if f.bg then f.bg:Show() end
    if T.SetBackground then T.SetBackground(domTab) end
  end

  if f.pointsText then
    if inspect then
      -- "points available" is meaningless for someone else's talents; name whose these are and
      -- what they add up to instead.
      local unit  = T._inspectUnit
      local who   = (unit and GetUnitName and GetUnitName(unit, true)) or (unit and UnitName(unit)) or ""
      local total = 0
      for tabIdx = 1, numTabs do
        local _, _, spent = GetTalentTabInfo(tabIdx, true, isPet, group)
        total = total + (spent or 0)
      end
      local _, classFile = UnitClass(unit or "player")
      f.pointsText:SetText(NE.color.WrapClass(classFile, who)
        .. ("  |cffffffff%d|r "):format(total) .. L["points spent"])
    else
      f.pointsText:SetText(("|cffffffff%d|r points available"):format(math.max(0, available)))
    end
  end
  local hasStaged = previewSpentAll > 0
  if f.apply and GlowEmitterFactory and GlowEmitterMixin then
    if hasStaged then
      GlowEmitterFactory:Show(f.apply, GlowEmitterMixin.Anims.NPE_RedButton_GreenGlow)
    else
      GlowEmitterFactory:Hide(f.apply)
    end
  end

  -- Bottom bar: editable (active) spec shows Apply/Reset; a viewed INACTIVE spec shows Activate.
  if inspect then
    -- Nothing to commit, nothing to switch to: an inspected unit's window is a view, not an editor.
    if f.apply then f.apply:Hide() end
    if f.reset then f.reset:Hide() end
    if f.activate then f.activate:Hide() end
  elseif editable then
    if f.activate then f.activate:Hide() end
    if f.apply then f.apply:Show() end
    if f.reset then f.reset:Show() end
    if f._setSubButtonsEnabled then f._setSubButtonsEnabled(hasStaged) end
  else
    if f.apply then f.apply:Hide() end
    if f.reset then f.reset:Hide() end
    if f.activate then
      f.activate:Show()

      if IsTriumvirate() then
        -- ---- Triumvirate Gold & Lock Verification ---------------------------------------
        local unlockBtn = _G["TriumvirateSpecActivateButton"]
        local nativeNumGroups = (GetNumTalentGroups and GetNumTalentGroups()) or 2
        local isLocked = (unlockBtn and unlockBtn:IsShown()) or (group > nativeNumGroups)

        local goldCost = 0
        if group == 2 then goldCost = 1
        elseif group == 3 then goldCost = 2000
        elseif group == 4 then goldCost = 5000 end

        local unlockCost  = goldCost * 100 * 100
        local playerMoney = GetMoney() or 0

        if isLocked then
          if playerMoney < unlockCost then
            f.activate:SetText(L["Locked"])
            f.activate:Disable()
            if f.activate.SetAlpha then f.activate:SetAlpha(0.25) end
            local btnText = f.activate:GetFontString()
            if btnText then btnText:SetTextColor(0.4, 0.4, 0.4) end
          else
            f.activate:SetText(L["Unlock Spec"])
            f.activate:Enable()
            if f.activate.SetAlpha then f.activate:SetAlpha(1.0) end
            local btnText = f.activate:GetFontString()
            if btnText then btnText:SetTextColor(1, 0.82, 0) end
          end
        else
          f.activate:SetText(L["Activate"])
          f.activate:Enable()
          if f.activate.SetAlpha then f.activate:SetAlpha(1.0) end
          local btnText = f.activate:GetFontString()
          if btnText then btnText:SetTextColor(1, 1, 1) end
        end
        -- ---------------------------------------------------------------------------------
      else
        -- Non-Triumvirate realms: plain Activate, no gold-unlock system to check against.
        f.activate:SetText(L["Activate"])
        f.activate:Enable()
        if f.activate.SetAlpha then f.activate:SetAlpha(1.0) end
        local btnText = f.activate:GetFontString()
        if btnText then btnText:SetTextColor(1, 1, 1) end
      end
    end
  end

  if f._loBtn then if (isPet or inspect) then f._loBtn:Hide() else f._loBtn:Show() end end

  if T.RefreshSpecTabs then T.RefreshSpecTabs() end
  if T.GlyphsEnsureUI then pcall(T.GlyphsEnsureUI) end
  if T.GlyphsRefresh then pcall(T.GlyphsRefresh) end
  if T.GlyphsApplyPaneVisibility then pcall(T.GlyphsApplyPaneVisibility) end
end

function T.Refresh()
  local f = T.frame
  if not (f and f:IsShown()) then return end
  T.Populate()
end

-- ----------------------------------------------------------------------------
-- INITIALIZATION ROOT BOOT
-- ----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  local f = T.frame
  if not f then return end
  buildBottomBar(f)

  f:HookScript("OnShow", function()
    if GetCVar then pcall(function() T._savedPreviewCVar = GetCVar("previewTalents") end) end
    if SetCVar then pcall(SetCVar, "previewTalents", "1") end
    if T.Populate then T.Populate() end
  end)
  f:HookScript("OnHide", function()
    discardPreview(T._activeGroup or 1, false)
    if petHasTalents() then discardPreview(T._activeGroup or 1, true) end
    if SetCVar and T._savedPreviewCVar then pcall(SetCVar, "previewTalents", T._savedPreviewCVar) end
  end)

  local ev = CreateFrame("Frame")
  for _, e in ipairs({
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PREVIEW_TALENT_POINTS_CHANGED",
    "PLAYER_LEVEL_UP", "ACTIVE_TALENT_GROUP_CHANGED",
    "PET_TALENT_UPDATE", "PREVIEW_PET_TALENT_POINTS_CHANGED", "UNIT_PET",
  }) do pcall(function() ev:RegisterEvent(e) end) end
  ev:SetScript("OnEvent", function(_, event, arg1)
    if event == "UNIT_PET" and arg1 ~= "player" then return end
    if event == "ACTIVE_TALENT_GROUP_CHANGED" then playSound("spec") end
    T.Refresh()
  end)
end)