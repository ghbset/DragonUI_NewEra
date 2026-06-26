-- DragonUI_NewEra/modules/talents/NodeData.lua — authored node-shape layer ("we create the data").
--
-- DOWNPORT: NewEra/Talents/NodeData.lua (Classic 1.15) -> 3.3.5a (WotLK), adapted to the
-- SHARED CONTRACT. Pure logic, no NE.* deps. This file RESOLVES which retail node shape/atlas
-- a talent uses; it does NOT touch any mask API (no CreateMaskTexture/SetMask) — the renderer
-- (Talents.lua) owns mask handling. Resolution stays a pure function.
--
-- Retail renders talent nodes as circle (active ability) / square (passive) /
-- capstone (signature). On Classic, TalentInfoResult had no active-vs-passive field and
-- (per the /ne probe talents dump on 1.15.8) returned spellID = 0, so shape could NOT be
-- derived from the spell at runtime. Hence an authored shape layer.
--
-- WotLK 3.3.5a NOTE: GetTalentInfo natively returns isExceptional (the 7th return value),
-- so the isExceptional-based heuristic ports UNCHANGED — see T.ResolveShape below.
--
-- KEY FINDING from the (Classic) probe — isExceptional is load-bearing:
--   The "exceptional" talents (the ones that historically had the gold/diamond border) are
--   precisely the active-ability talents. Probe sample (Priest): exceptional = {Power
--   Infusion, Inner Focus, Divine Spirit, Holy Nova, Spirit of Redemption, Lightwell,
--   Vampiric Embrace, Mind Flay, Shadowform, Silence} — every one grants/*is* an active
--   ability. hasGoldBorder was unused on Classic (always false). So isExceptional ≈ "active",
--   and we derive the default shape from it, reserving the authored OVERRIDES table for the
--   handful of cases where that heuristic is wrong, and to promote the deepest signature
--   talents to the full capstone (apex) art.
--
-- Resolution order (most specific wins):
--   1. OVERRIDES[talentID]            — authored correction, the source of truth
--   2. capstone        if isExceptional and tier >= CAPSTONE_TIER (active deep talent → round apex)
--   3. capstonesquare  if tier >= CAPSTONE_TIER (passive deep talent → SQUARE art, capstone scale)
--   4. circle          if isExceptional   (active ability)
--   5. square          otherwise          (passive)
--
-- Both deepest-tier (capstone-tier) talents are SCALED UP so they read as prominent
-- finals; only the active one gets the round apex art. Previously a passive deep-tier
-- talent fell through to plain "square" — a normal-size square that looked unfinished
-- next to the enlarged round capstones.

local NE = DragonUI_NewEra
local T = NE.talents or {}
NE.talents = T

-- WotLK deepest tier. Vanilla used 7 (the 31-point signature talent sat at tier 7), but
-- WotLK trees are 11 tiers deep with the signature/bottom talent near tier 11.
T.CAPSTONE_TIER = 11

-- Authored corrections, keyed by talentID -> "square" | "circle" | "capstone".
-- Seed empty; add entries only when the heuristic visibly mis-shapes a node.
--   e.g. T.SHAPE_OVERRIDES[<talentID>] = "square"
-- VERIFY (WotLK): overrides sampled from vanilla; revisit per-class once live data is
-- rendered — WotLK class talents/trees differ from vanilla, so seeded entries may be wrong.
T.SHAPE_OVERRIDES = {}

-- Resolve the retail node shape for a TalentInfoResult (the table fed in by the renderer
-- from GetTalentInfo). Pure function — no side effects, no mask API.
function T.ResolveShape(info)
  if not info then return "square" end
  local override = info.talentID and T.SHAPE_OVERRIDES[info.talentID]
  if override then return override end
  local isCapstoneTier = (info.tier or 0) >= T.CAPSTONE_TIER
  if info.isExceptional then
    if isCapstoneTier then return "capstone" end   -- active signature → round apex
    return "circle"
  end
  if isCapstoneTier then return "capstonesquare" end  -- passive signature → big square
  return "square"
end

-- Atlas-set prefix for a resolved shape (the SetAtlas nickname stem). The state
-- suffix (-yellow/-green/-gray/-locked/-red/...) is appended by the render code.
--   square   -> "talents-node-square"
--   circle   -> "talents-node-circle"
--   capstone -> "talents-node-apex-large"   (active variant: apex-active-large)
T.SHAPE_ATLAS = {
  square         = "talents-node-square",
  circle         = "talents-node-square",   -- 3.3.5a: no round icon mask, so active talents use the SQUARE frame too
  capstone       = "talents-node-square",   -- squared (was the round apex); still scaled up by SetVisual
  capstonesquare = "talents-node-square",   -- passive deep-tier talent: square art, capstone scale
}
