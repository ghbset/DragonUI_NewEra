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
-- CreateLine DO NOT EXIST on 3.3.5a (both Cata+). So edges here mirror Blizzard's stock 3.3.5a
-- TalentFrame.lua branch drawing: axis-aligned WHITE8X8 strips (vertical / horizontal segments) +
-- a directional arrowhead via SetTexCoord flips. L-routing (column AND tier differ) is drawn as a
-- vertical drop + horizontal run; see drawEdge.

local NE = DragonUI_NewEra
local T = NE.talents or {}
NE.talents = T

local PER_TIER = 5   -- tier t needs (t-1)*5 points spent in that tree (WotLK == vanilla rule)

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
local function talentInfo(tab, i, group)
  if not GetTalentInfo then return nil end
  local name, icon, tier, column, rank, maxRank, isExceptional,
        meetsPrereq, previewRank, meetsPreviewPrereq = GetTalentInfo(tab, i, false, false, group)
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
  -- 3.3.5a: missing CVars make GetCVarBool raise — pcall so a name mismatch never errors.
  local ok, v
  if GetCVarBool then ok, v = pcall(GetCVarBool, "previewTalents"); if ok then return v end end
  if GetCVar then ok, v = pcall(GetCVar, "previewTalents"); if ok then return v == "1" end end
  return false
end

-- VERIFY: arg lists for these preview accessors. The first form matches the NewEra/stock 3.3.5a
-- Blizzard_TalentUI.lua usage (isInspect=false, group). Fall back to UnitCharacterPoints if absent.
local function unspentPoints(group)
  if GetUnspentTalentPoints then
    local ok, v = pcall(GetUnspentTalentPoints, false, false, group)   -- VERIFY arg list
    if ok and v then return v end
  end
  if UnitCharacterPoints then return UnitCharacterPoints("player") or 0 end   -- FALLBACK
  return 0
end

local function previewSpent(group)
  if GetGroupPreviewTalentPointsSpent then
    local ok, v = pcall(GetGroupPreviewTalentPointsSpent, false, group)   -- VERIFY arg list
    if ok and v then return v end
  end
  return 0
end

local function discardPreview(group)
  if InCombatLockdown and InCombatLockdown() then return end
  -- Native clear first (3.3.5a is ResetPreviewTalentPoints(); the group variant is tried too, both
  -- guarded — whichever exists runs). These were the unreliable part, so we don't trust them alone.
  if ResetPreviewTalentPoints then pcall(ResetPreviewTalentPoints) end
  if ResetGroupPreviewTalentPoints then
    pcall(ResetGroupPreviewTalentPoints, group)
    pcall(ResetGroupPreviewTalentPoints, false, group)
  end
  -- Guaranteed fallback: walk every talent and subtract any STILL-staged points back to its live
  -- rank with the (now-verified) signed AddPreviewTalentPoints. Reverse order (deep tiers first) so
  -- a dependent is removed before its prerequisite; two passes settle any ordering rejections.
  if not (AddPreviewTalentPoints and GetTalentInfo and GetNumTalentTabs) then return end
  for _pass = 1, 2 do
    for t = 1, (GetNumTalentTabs(false, false) or 0) do
      local n = (GetNumTalents and GetNumTalents(t, false, false)) or 0
      for i = n, 1, -1 do
        local info = talentInfo(t, i, group)
        if info then
          local staged = (info.previewRank or 0) - (info.rank or 0)
          if staged > 0 then pcall(AddPreviewTalentPoints, t, i, -staged) end
        end
      end
    end
  end
end

-- ----------------------------------------------------------------------------
-- State machine. Map a talentInfo to (state, displayRank).
-- states: green (selectable, 0 ranks + points available) / yellow (has ranks) /
--         gray (prereq unmet OR no points to spend) / locked (tier not unlocked) /
--         red (preview removed below live rank — staged refund).
-- Mirrors NewEra computeState with retail node semantics, adapted to 3.3.5a fields.
-- ----------------------------------------------------------------------------
local function computeState(info, tabPointsSpent, preview, available)
  local liveRank    = info.rank or 0
  local displayRank = (preview and info.previewRank) or liveRank
  local meets       = (preview and info.meetsPreviewPrereq) or info.meetsPrereq
  local tierUnlocked= ((info.tier or 1) - 1) * PER_TIER <= tabPointsSpent
  local forceDesat  = (available <= 0) and (displayRank == 0)
  local colored     = meets and tierUnlocked and not forceDesat
  local state
  -- preview removed a point below the live rank -> red (staged refund)
  if preview and displayRank < liveRank then
    state = "red"
  elseif not colored then
    state = (not tierUnlocked and displayRank == 0) and "locked" or "gray"
  elseif displayRank == 0 then
    state = "green"     -- selectable (points available to spend here)
  elseif displayRank >= (info.maxRank or displayRank) then
    state = "yellow"    -- maxed
  else
    state = "yellow"    -- partial (yellow covers partial + maxed on this art set)
  end
  return state, displayRank
end

-- ----------------------------------------------------------------------------
-- Node click / right-click / tooltip. Nodes are reused across refreshes — wire once.
-- ----------------------------------------------------------------------------
local function nodeLeftClick(self)
  if not AddPreviewTalentPoints then return end
  -- 3.3.5a: AddPreviewTalentPoints(tabIndex, talentIndex, points) — the 3rd arg is the SIGNED point
  -- delta, NOT the talent group. (Passing the group here was the "+2 on spec 2" bug.)
  pcall(AddPreviewTalentPoints, self._tab, self._index, 1)   -- +1
  -- PREVIEW_TALENT_POINTS_CHANGED fires -> T.Refresh re-renders.
end

local function nodeRightClick(self)
  if not AddPreviewTalentPoints then return end
  -- 3.3.5a has a NATIVE decrement: a negative delta removes one staged point. The core refuses if
  -- it would orphan a dependent talent (correct behavior), so no manual rebuild is needed.
  pcall(AddPreviewTalentPoints, self._tab, self._index, -1)   -- -1
  -- PREVIEW_TALENT_POINTS_CHANGED fires -> T.Refresh re-renders.
end

local function nodeTooltip(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  -- 3.3.5a GameTooltip:SetTalent keys on (tab, index, isInspect, isPet, group), NOT talentID.
  if self._tab and self._index and GameTooltip.SetTalent then
    local ok = pcall(GameTooltip.SetTalent, GameTooltip, self._tab, self._index, false, false, T._viewGroup or T._activeGroup or 1)
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
    -- Only the ACTIVE spec is editable; the other spec is view-only (must Activate to change it).
    if (T._viewGroup or 1) ~= (T._activeGroup or 1) then return end
    if btn == "LeftButton" then nodeLeftClick(self)
    elseif btn == "RightButton" then nodeRightClick(self) end
  end)
  -- Preserve the scaffold's hover-ring behaviour (ShowHover/HideHover) AND layer the tooltip on.
  n:SetScript("OnEnter", function(self)
    if self.ShowHover then self:ShowHover() end
    nodeTooltip(self)
  end)
  n:SetScript("OnLeave", function(self)
    if self.HideHover then self:HideHover() end
    GameTooltip:Hide()
  end)
end
T._WireNode = wireNode   -- exposed (parity with NewEra; editor reuse if added later)

-- ----------------------------------------------------------------------------
-- EDGE DRAWING — DIRECT prereq->dependent connector.
-- 3.3.5a has no CreateLine and no Texture:SetRotation, and the 8-arg SetTexCoord "rotate" trick
-- warps texture SAMPLING inside an axis-aligned quad (a solid texture just fills the box, not a
-- diagonal line) — it needs a calibrated wrap line texture. Rather than that, we draw the straight
-- X->Y line as evenly-spaced small square pips along the segment: works at ANY angle, no rotation,
-- and reads clearly as "A connects to B" (the dependent end gets a larger pip as the head).
-- Coordinates are tree-local TOPLEFT offsets (matching T.nodeCenter), so anchor CENTER->TOPLEFT.
-- ----------------------------------------------------------------------------
local sqrt = math.sqrt
local DOT_SIZE, DOT_GAP, HEAD_SIZE, FLOW_SPEED = 4, 9, 7, 16   -- pip size / target spacing / head / px-per-sec

-- Reposition an edge's pips for the current flow phase (called every frame by the driver). The pips
-- march from prereq -> dependent; each wraps (modulo the span) back to the start so the stream is
-- seamless. edge.gap is span/count (an EXACT divisor of the loop period) — that's what keeps the
-- spacing uniform all the way around, including across the wrap (a fixed gap left a short seam).
local function positionEdge(edge, phase)
  local dots, span, gap = edge.dots, edge.span, edge.gap
  for i = 1, #dots do
    local dist = ((i - 1) * gap + phase) % span
    local d = dots[i]
    d:ClearAllPoints()
    d:SetPoint("CENTER", edge.tf, "TOPLEFT", edge.x0 + edge.ux * dist, edge.y0 + edge.uy * dist)
  end
end

-- One OnUpdate driver on the talent frame advances a shared phase and re-flows every live edge.
-- Only the ACTIVE spec records edges (Populate gates it), so a viewed-inactive spec has none ->
-- its connectors are invisible AND don't animate, per design. OnUpdate only fires while shown.
-- Sheen glint: subtle diagonal shine that periodically sweeps across an OWNED talent. The texcoord
-- stays on the atlas sub-rect; we slide the soft sheen across (alpha envelope ~0 at the extremes so
-- the overflow into the node gap is invisible) and re-glint every SHEEN_CYCLE, staggered per node.
local SHEEN_SWEEP, SHEEN_PEAK = 0.7, 0.40          -- glint sweep duration / peak ADD alpha
local GLINT_MIN, GLINT_MAX    = 0.25, 0.95         -- random secs between glints (before the few-talents mult); each picks a random owned talent
local sin, pi, random = math.sin, math.pi, math.random
-- Animate ONE glinting node. node._sheenStart is the clock time the glint began (nil = not glinting,
-- so the sheen stays hidden). The scheduler in the driver sets it on a randomly chosen owned talent.
local function updateSheen(node, clock)
  local s = node.sheen
  if not s then return end
  local st = node._sheenStart
  if not st then if s:IsShown() then s:Hide() end return end
  local t = (clock - st) / SHEEN_SWEEP
  if t < 0 or t >= 1 then node._sheenStart = nil; s:Hide(); return end
  local env  = sin(pi * t)               -- size envelope: 0 -> 1 -> 0 over the sweep
  local full = node._sheenSpan or 28     -- peak size == the spell-icon size (full at the midpoint)
  local sz = full * env
  if sz < 1 then sz = 1 end
  s:SetSize(sz, sz)                       -- grow to full icon size halfway, then shrink to nothing
  -- travel TOP-LEFT -> BOTTOM-RIGHT (node-local; y is up, so +y = up). 0-size at both corners.
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
    -- advance edges + animate any glinting nodes
    for i = 1, 3 do
      local tf = trees[i]
      if tf then
        local el = tf._edgeList
        if el then for j = 1, #el do positionEdge(el[j], T._edgePhase) end end
        local sl = tf._sheenList
        if sl then for j = 1, #sl do updateSheen(sl[j], clock) end end
      end
    end
    -- scheduler: at random intervals, glint ONE randomly chosen owned talent (across all trees)
    if clock >= (T._nextGlint or 0) then
      local cand = {}
      for i = 1, 3 do
        local sl = trees[i] and trees[i]._sheenList
        if sl then for j = 1, #sl do cand[#cand + 1] = sl[j] end end
      end
      local n = #cand
      if n > 0 then
        -- avoid glinting the SAME talent twice in a row (unless it's the only owned one): drop the
        -- last-glinted node from the candidate list before picking.
        if n > 1 and T._lastGlint then
          for k = n, 1, -1 do if cand[k] == T._lastGlint then table.remove(cand, k); break end end
        end
        local pick = cand[random(#cand)]
        pick._sheenStart = clock
        T._lastGlint = pick
      end
      -- Rate scales with how many talents are owned: few talents -> slower, so a small set (or a lone
      -- talent) isn't glinting constantly — each ends up glinting at a calmer, roughly steady rate.
      -- mult tapers 5x (1 owned) .. 1x (5+ owned). NOTE: integer random(m,n) only — random() with NO
      -- args does NOT return [0,1) on this client (it returned huge values -> scheduler stalled).
      local mult = math.max(1, 6 - n)
      T._nextGlint = clock + (GLINT_MIN + random(0, math.floor((GLINT_MAX - GLINT_MIN) * 1000)) / 1000) * mult
    end
  end)
end

-- src (prereq) -> dst (dependent). Captures geometry + acquires the pips; the driver flows them.
local function drawEdge(tf, sTier, sCol, dTier, dCol, color)
  local sx, sy = T.nodeCenter(sTier, sCol)
  local ex, ey = T.nodeCenter(dTier, dCol)
  local dx, dy = ex - sx, ey - sy
  local dist = sqrt(dx * dx + dy * dy)
  if dist < 1 then return end
  local ux, uy = dx / dist, dy / dist
  local half = T.LAYOUT.NODE / 2
  local x0, y0 = sx + ux * half, sy + uy * half      -- start at the prereq's edge
  local span = dist - 2 * half                        -- run to the dependent's edge
  if span <= 0 then return end
  -- count chosen so the spacing is CLOSEST to DOT_GAP, then the exact gap = span/count divides the
  -- loop period evenly -> no short seam dot at the wrap.
  local count = math.floor(span / DOT_GAP + 0.5)
  if count < 1 then count = 1 end
  local gap = span / count
  local dots = {}
  for _ = 1, count do
    local d = tf:AcquireDot()
    d:SetSize(DOT_SIZE, DOT_SIZE)
    d:SetVertexColor(color[1], color[2], color[3], color[4])
    dots[#dots + 1] = d
  end
  -- static "head" pip just inside the dependent node (marks the target / direction of travel)
  local head = tf:AcquireDot()
  head:SetSize(HEAD_SIZE, HEAD_SIZE)
  head:SetVertexColor(color[1], color[2], color[3], color[4])
  head:ClearAllPoints()
  head:SetPoint("CENTER", tf, "TOPLEFT", sx + ux * (dist - half), sy + uy * (dist - half))
  local edge = { tf = tf, x0 = x0, y0 = y0, ux = ux, uy = uy, span = span, gap = gap, dots = dots }
  tf._edgeList[#tf._edgeList + 1] = edge
  positionEdge(edge, T._edgePhase or 0)   -- initial placement (driver takes over next frame)
end

-- ----------------------------------------------------------------------------
-- Bottom-bar controls. The scaffold laid the strip texture (f.bottomBar); we add the buttons +
-- points readout + handlers here, ONCE.
-- ----------------------------------------------------------------------------
StaticPopupDialogs["NE_TALENTS_LEARN"] = {
  text = CONFIRM_LEARN_PREVIEW_TALENTS or "Learn the selected talents? Spent points cannot be refunded without a respec.",
  button1 = YES, button2 = NO,
  OnAccept = function()
    if LearnPreviewTalents then pcall(LearnPreviewTalents) end   -- 3.3.5a: NO arg
    playSound("apply")
  end,
  hideOnEscape = 1, timeout = 0, exclusive = 1, whileDead = 1,
}

local function buildBottomBar(f)
  if f._barBuilt then return end
  f._barBuilt = true

  -- points-available readout (left of the buttons)
  f.pointsText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.pointsText:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT",
    (T.FRAME.CHROME_L or 0) + 24, (T.FRAME.CHROME_B or 0) + 30)
  f.pointsText:SetText("")

  -- Apply (commit, behind a confirm popup)
  local apply = CreateFrame("Button", "NE_TalentApplyButton", f, "UIPanelButtonTemplate")
  apply:SetSize(120, 26)
  apply:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",
    -((T.FRAME.CHROME_R or 0) + 24), (T.FRAME.CHROME_B or 0) + 27)
  apply:SetText(APPLY or "Apply")
  apply:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    StaticPopup_Show("NE_TALENTS_LEARN")
  end)
  f.apply = apply

  -- Reset (discard all staged preview)
  local reset = CreateFrame("Button", "NE_TalentResetButton", f, "UIPanelButtonTemplate")
  reset:SetSize(120, 26)
  reset:SetPoint("RIGHT", apply, "LEFT", -8, 0)
  reset:SetText(RESET or "Reset")
  reset:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    discardPreview(T._activeGroup or 1)
    if T.Refresh then T.Refresh() end
  end)
  f.reset = reset

  -- Activate (dual-spec): shown ONLY when viewing the inactive spec; switches the active group.
  -- Occupies the same corner as Apply (which is hidden while a non-active spec is viewed).
  local activate = CreateFrame("Button", "NE_TalentActivateButton", f, "UIPanelButtonTemplate")
  activate:SetSize(160, 26)
  activate:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT",
    -((T.FRAME.CHROME_R or 0) + 24), (T.FRAME.CHROME_B or 0) + 27)
  activate:SetText("Activate")
  activate:SetScript("OnClick", function()
    if InCombatLockdown and InCombatLockdown() then return end
    -- 3.3.5a: SetActiveTalentGroup(group) switches the active spec. ACTIVE_TALENT_GROUP_CHANGED
    -- then fires -> T.Refresh snaps the view to the new active group.  -- VERIFY: arg + not protected
    if SetActiveTalentGroup and T._viewGroup then pcall(SetActiveTalentGroup, T._viewGroup) end
  end)
  activate:Hide()
  f.activate = activate

  -- helper: enable/disable the staged-change buttons
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
-- T.Populate — FULL (re)build of all three trees from live data. The active OnShow path the
-- scaffold calls (`if T.Populate then T.Populate() end`).
-- ----------------------------------------------------------------------------
function T.Populate()
  local f = T.frame
  if not f or not GetTalentInfo then return end
  buildBottomBar(f)
  ensureFlowDriver(f)   -- marching-pip animation for the dependency connectors

  -- Dual-spec: _activeGroup = the live spec; _viewGroup = the spec being DISPLAYED (the user can
  -- view the other spec via the side tabs). Snap the view to active on first open and whenever the
  -- active group actually changes (a real spec switch); otherwise preserve the user's chosen view.
  local active = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  if T._viewGroup == nil or T._lastActive ~= active then T._viewGroup = active end
  T._activeGroup, T._lastActive = active, active
  local numGroups = (GetNumTalentGroups and (GetNumTalentGroups() or 1)) or 1   -- VERIFY: GetNumTalentGroups on 3.3.5a
  if numGroups < 2 then T._viewGroup = active end
  local group    = T._viewGroup
  local editable = (group == active)            -- only the active spec can be edited
  local viewChanged = (T._lastViewGroup ~= group)   -- suppress spend-flash on a view/spec switch
  T._lastViewGroup = group
  T._group = group                              -- back-compat alias (some helpers still read it)
  local preview = previewOn() and editable      -- preview math only applies to the editable spec
  local numTabs = (GetNumTalentTabs and GetNumTalentTabs(false, false)) or 0

  -- points available to spend (drives forceDesaturated). previewSpent counted across the group.
  local unspent       = unspentPoints(group)
  local previewSpentAll = preview and previewSpent(group) or 0
  local available     = unspent - previewSpentAll

  local domIcon, domSpent, domTab = nil, -1, 1   -- dominant spec (most points) -> portrait + bg

  for tabIdx = 1, 3 do
    local tf = f.trees[tabIdx]
    tf:ResetEdges(); tf:ResetGates()
    tf._edgeList = {}    -- live edges this pass (flowed by the OnUpdate driver)
    tf._sheenList = {}   -- owned nodes this pass (glinted by the OnUpdate driver, active spec only)
    local used = {}

    if tabIdx <= numTabs then
      -- GetTalentTabInfo -> name, iconTexture, pointsSpent, background, previewPointsSpent.
      -- Pass the VIEWED group so header counts match the spec on screen (not always the active one).
      local name, icon, spent, _bg, prevSpent = GetTalentTabInfo(tabIdx, false, false, group)
      local tabPointsSpent = (spent or 0) + (preview and (prevSpent or 0) or 0)
      tf.headerName:SetText(string.upper(name or ("Tree " .. tabIdx)))   -- retail CAPS
      tf.headerPts:SetText(tostring(tabPointsSpent))
      tf.headerPts:SetTextColor((tabPointsSpent > 0) and 0.1 or 0.5,
                                (tabPointsSpent > 0) and 1.0 or 0.5,
                                (tabPointsSpent > 0) and 0.1 or 0.5)   -- green / gray
      -- centre [name + gap + points] horizontally; vertical centre = HEADER_CENTER_Y (chrome band)
      local nameW = (tf.headerName:GetStringWidth() or 0) * 0.9   -- x SetTextScale(0.9)
      local ptsW  = tf.headerPts:GetStringWidth() or 0
      tf.headerName:ClearAllPoints()
      tf.headerName:SetPoint("LEFT", tf, "TOPLEFT",
        (tf:GetWidth() - (nameW + 8 + ptsW)) / 2,
        (T.LAYOUT and T.LAYOUT.HEADER_CENTER_Y) or -13)

      if (spent or 0) > domSpent then domSpent = (spent or 0); domIcon = icon; domTab = tabIdx end

      local numTalents = (GetNumTalents and GetNumTalents(tabIdx, false, false)) or 0
      local byCell, infos = {}, {}

      -- pass 0: collect every talent's info + occupied cells, then build this tab's per-tier CENTERED
      -- column layout (T.SetCenteredLayout) BEFORE placing — nodeCenter reads it during placement so
      -- tiers with <COLS talents are packed and centered.
      local occupied = {}
      for i = 1, numTalents do
        local info = talentInfo(tabIdx, i, group)
        if info and info.tier and info.column then
          infos[i] = info
          occupied[#occupied + 1] = { tier = info.tier, column = info.column }
        end
      end
      if T.SetCenteredLayout then T.SetCenteredLayout(occupied) end

      -- pass 1: nodes
      for i = 1, numTalents do
        local info = infos[i]
        if info and info.tier and info.column then
          local shape = T.ResolveShape(info)
          -- Inactive spec: pass available=0 so computeState's forceDesat path suppresses the GREEN
          -- "selectable" state — you can't spend into a non-active spec, so no green prompts there.
          local state, displayRank = computeState(info, tabPointsSpent, preview, (editable and available) or 0)
          local node = tf:AcquireNode(i); used[i] = true
          node._tab, node._index, node._talentID = tabIdx, i, nil
          node._tipName = info.name
          local rankText = (info.maxRank and info.maxRank > 0)
            and (tostring(displayRank) .. "/" .. tostring(info.maxRank)) or ""
          node:SetVisual(shape, state, info.icon, rankText)
          -- Spend flash: a gold pop when this node's rank just increased during an edit (not on the
          -- first render, not on a spec/view switch). editable-only — only the active spec is edited.
          if editable and not viewChanged and node._shownRank then
            if displayRank > node._shownRank then
              if node.PlaySpend then node:PlaySpend() end
              playSound("add")
            elseif displayRank < node._shownRank then
              playSound("remove")
            end
          end
          node._shownRank = displayRank
          -- Inactive (viewed-but-not-active) spec reads as "not the live window": dim the whole node
          -- (icon + ring + rank + highlights, via cascade) to 66% and desaturate the ability icon.
          node:SetAlpha(editable and 1 or 0.66)
          if not editable and node.icon and node.icon.SetDesaturated then node.icon:SetDesaturated(true) end
          local x, y = T.nodeCenter(info.tier, info.column)
          node:ClearAllPoints(); node:SetPoint("CENTER", tf, "TOPLEFT", x, y); node:Show()
          wireNode(node)
          -- Sheen pool: OWNED talents (rank > 0) on the ACTIVE spec are glint candidates; the driver's
          -- scheduler randomly picks one to glint at a time. Non-owned / inactive-spec nodes hide it.
          if editable and (displayRank or 0) > 0 then
            tf._sheenList[#tf._sheenList + 1] = node
          else
            node._sheenStart = nil
            if node.sheen then node.sheen:Hide() end
          end
          byCell[info.tier * 10 + info.column] = info
        end
      end

      -- pass 2: dependency edges — ACTIVE spec only. A viewed-inactive spec records no edges, so its
      -- connectors are both invisible AND unanimated (per design). Edges go into tf._edgeList for the
      -- flow driver. Color is yellow when the prereq is actually invested, tan otherwise.
      if editable then
      for i = 1, numTalents do
        local info = infos[i]
        if info and GetTalentPrereqs then
          -- 3.3.5a: tier, column, isLearnable, isPreviewLearnable (AT MOST ONE prereq -> loop runs once)
          local pre = { GetTalentPrereqs(tabIdx, i, false, false, group) }
          for p = 1, #pre, 4 do
            local ptier, pcol = pre[p], pre[p + 1]
            local srcInfo = ptier and pcol and byCell[ptier * 10 + pcol]
            if srcInfo then
              -- edge is "active" (yellow) only when the PREREQUISITE is actually invested
              -- (source rank > 0) AND the dependent's prereq is satisfied.
              local srcRank = (preview and srcInfo.previewRank) or srcInfo.rank or 0
              local meets   = (preview and info.meetsPreviewPrereq) or info.meetsPrereq
              local active  = meets and srcRank > 0
              local color   = active and EDGE_ACTIVE or EDGE_INACTIVE
              drawEdge(tf, ptier, pcol, info.tier, info.column, color)
            end
          end
        end
      end
      end   -- if editable (active-spec connectors only)

      -- (No "Requires N points" gate graphic — locked tiers read as locked-state nodes and the
      --  tooltip states the requirement on hover. Gate pool reset above keeps it tidy.)
    else
      tf.headerName:SetText(""); tf.headerPts:SetText("")
    end

    tf:HideUnusedNodes(used)
    tf:HideUnusedEdges()
    tf:HideUnusedGates()
  end

  -- portrait = player CLASS icon (UI-Classes-Circles + CLASS_ICON_TCOORDS); spec icon fallback.
  if f.portrait then
    local _, classFile = UnitClass("player")
    local c = classFile and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[classFile]
    if c then
      f.portrait:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
      f.portrait:SetTexCoord(c[1], c[2], c[3], c[4])
    elseif domIcon then
      f.portrait:SetTexCoord(0, 1, 0, 1); f.portrait:SetTexture(domIcon)
    end
  end

  -- window background = dominant spec's themed art (lowest tab wins ties)
  if T.SetBackground then T.SetBackground(domTab) end

  -- points readout + bottom-bar enable state
  if f.pointsText then
    f.pointsText:SetText(("|cffffffff%d|r points available"):format(math.max(0, available)))
  end
  local hasStaged = previewSpentAll > 0
  -- Apply-button glow: GlowEmitterFactory is ABSENT on 3.3.5a; the guard no-ops safely.
  if f.apply and GlowEmitterFactory and GlowEmitterMixin then
    if hasStaged then
      GlowEmitterFactory:Show(f.apply, GlowEmitterMixin.Anims.NPE_RedButton_GreenGlow)   -- VERIFY (dead on 3.3.5a)
    else
      GlowEmitterFactory:Hide(f.apply)
    end
  end
  -- Bottom bar: editable (active) spec shows Apply/Reset; a viewed INACTIVE spec shows Activate.
  if editable then
    if f.activate then f.activate:Hide() end
    if f.apply then f.apply:Show() end
    if f.reset then f.reset:Show() end
    if f._setSubButtonsEnabled then f._setSubButtonsEnabled(hasStaged) end
  else
    if f.apply then f.apply:Hide() end
    if f.reset then f.reset:Hide() end
    if f.activate then
      f.activate:SetText("Activate")
      f.activate:Show()
    end
  end

  -- Refresh the dual-spec side tabs (no-op if <2 specs or the module isn't loaded).
  if T.RefreshSpecTabs then T.RefreshSpecTabs() end
end

function T.Refresh()
  local f = T.frame
  if not (f and f:IsShown()) then return end
  T.Populate()
end

-- ----------------------------------------------------------------------------
-- Boot — runs after Talents.lua's PLAYER_LOGIN (TOC order), so T.frame exists. Wires the preview
-- session (force CVar on OnShow / restore + discard on OnHide) and the live-refresh events.
-- ----------------------------------------------------------------------------
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  local f = T.frame
  if not f then return end
  buildBottomBar(f)

  -- Preview session: force previewTalents on while open; restore + discard staged on close.
  f:HookScript("OnShow", function()
    if GetCVar then pcall(function() T._savedPreviewCVar = GetCVar("previewTalents") end) end
    if SetCVar then pcall(SetCVar, "previewTalents", "1") end
    -- T.Populate also runs from the scaffold's OnShow; calling here is harmless (idempotent).
    if T.Populate then T.Populate() end
  end)
  f:HookScript("OnHide", function()
    discardPreview(T._activeGroup or 1)
    if SetCVar and T._savedPreviewCVar then pcall(SetCVar, "previewTalents", T._savedPreviewCVar) end
  end)

  -- Live refresh. All these events exist on 3.3.5a.
  local ev = CreateFrame("Frame")
  for _, e in ipairs({
    "PLAYER_TALENT_UPDATE", "CHARACTER_POINTS_CHANGED", "PREVIEW_TALENT_POINTS_CHANGED",
    "PLAYER_LEVEL_UP", "ACTIVE_TALENT_GROUP_CHANGED",
  }) do pcall(function() ev:RegisterEvent(e) end) end
  ev:SetScript("OnEvent", function(_, event)
    if event == "ACTIVE_TALENT_GROUP_CHANGED" then playSound("spec") end   -- successful spec switch
    T.Refresh()
  end)
end)
