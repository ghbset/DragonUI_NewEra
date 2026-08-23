-- DragonUI_NewEra/modules/cooldownviewer/ItemMixins.lua — the per-item layer of the Cooldown
-- Manager: one tile that binds a spell (or an on-use item) and renders its cooldown.
--
-- DOWNPORT of NewEra/CooldownViewer/ItemMixins.lua, Phase 1 scope: the COOLDOWN item mixin only
-- (Essential + Utility). The aura mixins (BuffIcon / BuffBar) are Phase 3 and are not ported here.
--
-- DEVIATIONS from the 1.15 source, all forced by the 3.3.5a widget/API surface:
--
--   * MaskTexture      — removed. Legion widget; unavailable, unpolyfillable, and an unknown XML
--                        node breaks the whole file's parse. CONTRACTS §0 lists SetMask as a hard
--                        rule. The rounded look now comes from CropIcon + the IconOverlay art.
--   * SetSwipeTexture  — removed (WoD+). We take the engine's built-in sweep.
--   * SetSwipeColor    — guarded (WoD+). The gold-aura vs black-cooldown distinction is therefore
--                        not colour-coded on this client; the aura path still drives the swipe.
--   * SetShown         — replaced with Show/Hide (CONTRACTS §0 hard rule).
--   * C_Spell.IsSpellUsable / IsSpellInRange — neither !!!ClassicAPI nor compat/C_Spell.lua provides
--                        these, so we go straight to the 3.3.5a globals IsUsableSpell / IsSpellInRange.
--                        The source already carried those as fallbacks.
--   * highestKnownRankID — REWRITTEN. The source uses `select(7, GetSpellInfo(name))`, which is the
--                        spellID on Era/TBC's modern engine but is **castTime** on 3.3.5a (the WotLK
--                        signature is name, rank, icon, cost, isFunnel, powerType, castTime, minRange,
--                        maxRange — see !!!ClassicAPI/Util/C_Spell.lua:39). Ported verbatim it would
--                        return e.g. 1500 for a 1.5s cast and use it as a spell ID. We resolve
--                        through NE.spellbook (core/SpellRanks.lua) instead.

local NE = DragonUI_NewEra
NE.cooldownviewer = NE.cooldownviewer or {}
local M = NE.cooldownviewer

local SB = NE.spellbook

-- Atlas wiring for one item tile. Era's engine atlas DB doesn't know retail nicknames; resolve via
-- NE.tex.SetAtlas. DOWNPORT: the IconMask branch is gone (see header). Every call is guarded so a
-- not-yet-shipped atlas degrades to a plain icon rather than erroring.
local function applyItemAtlases(item)
  local set = NE.tex and NE.tex.SetAtlas
  if not set then return end
  if item.IconOverlay then set(item.IconOverlay, "UI-HUD-CoolDownManager-IconOverlay", false) end
  -- The stacked copies that deepen the frame. Same atlas, same rect — see Frame strength.
  for _, t in ipairs(item.IconOverlayStack or {}) do
    set(t, "UI-HUD-CoolDownManager-IconOverlay", false)
  end
  if item.OutOfRange  then set(item.OutOfRange,  "UI-CooldownManager-OORshadow",       false) end

  -- The buff glow textures itself in M.BuildBuffGlow — it is a frame with a texture inside, not a
  -- region on the tile, so it has nothing to collect here.

  -- The ready-flash sprite. The retail GCD flipbook atlas is not registered on this client, so give
  -- the texture the fallback highlight the stepper pulses instead (see the Ready flash section).
  local flash = item.CooldownFlash
  if flash and flash.Flipbook then
    if NE.tex.HasAtlas and NE.tex.HasAtlas("UI-HUD-ActionBar-GCD-Flipbook") then
      set(flash.Flipbook, "UI-HUD-ActionBar-GCD-Flipbook", false)
    else
      flash.Flipbook:SetTexture(M.FLASH_FALLBACK_TEXTURE)
      flash.Flipbook:SetBlendMode("ADD")
      -- Warm gold reads as "ready" and stands clear of the icon art underneath.
      flash.Flipbook:SetVertexColor(1, 0.92, 0.55)
    end
    flash.Flipbook:SetAlpha(0)
  end
  -- Normalise the inconsistent baked borders on 3.3.5a icon art (8% zoom). This is also what stands
  -- in for the removed rounded mask.
  if NE.tex.CropIcon then
    NE.tex.CropIcon(item.Icon)
  elseif item.Icon and item.Icon.SetTexCoord then
    item.Icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
end

NE_CooldownViewerItemMixin = {}
local ItemMixin = NE_CooldownViewerItemMixin

function ItemMixin:OnLoad()
  applyItemAtlases(self)
  if self.OutOfRange then self.OutOfRange:Hide() end

  -- Countdown numbers. On 3.3.5a the Cooldown widget draws no text at all, so NE.cd owns a
  -- FontString + throttled OnUpdate (core/CooldownNumbers.lua). Same call shape as the source.
  NE.cd.ApplyNumbers(self.Cooldown, {
    font = self.cooldownFont or NE.cd.FONT.viewerEssential,
  })

  -- Retail renders drawSwipe=true, drawEdge=false, drawBling=true. 3.3.5a has none of these
  -- setters; guarded so this is a no-op here and correct if a future client gains them.
  if self.Cooldown then
    if self.Cooldown.SetDrawSwipe then self.Cooldown:SetDrawSwipe(true)  end
    if self.Cooldown.SetDrawEdge  then self.Cooldown:SetDrawEdge(false)  end
    if self.Cooldown.SetDrawBling then self.Cooldown:SetDrawBling(true)  end
  end
end

local BOOKTYPE_SPELL_ = BOOKTYPE_SPELL or "spell"

-- Every rank spellID of an ability, so the cooldown read can find whichever rank is actually
-- ticking. Our curated lists key each ability by its RANK 1 spellID (Devouring Plague = 2944,
-- Mind Blast = 8092), but the client tracks a cooldown on the EXACT rank cast — GetSpellCooldown
-- on the rank-1 id (or the bare name) reads 0 once you cast a higher rank, and players routinely
-- cast several ranks (down-ranking for mana). WotLK still has ranks, so this matters here exactly
-- as it did on 1.15.
--
-- DOWNPORT: primary source is now NE.spellbook (core/SpellRanks.lua), built by scanning the live
-- spellbook, rather than NewEra's generated db2 dump. The book-scan fallback below still covers
-- anything the table missed (racials, item use-spells).
local function knownRankIDs(spellID, name)
  local ids, seen, n = nil, {}, 0
  local function add(id)
    if id and not seen[id] then seen[id] = true; ids = ids or {}; n = n + 1; ids[n] = id end
  end
  add(spellID)

  local list = SB and SB.KnownRankIDs and name and SB.KnownRankIDs(name)
  if list then for _, id in ipairs(list) do add(id) end end

  if name and GetNumSpellTabs and GetSpellBookItemName and GetSpellBookItemInfo then
    for tab = 1, (GetNumSpellTabs() or 0) do
      local _, _, offset, numSlots = GetSpellTabInfo(tab)
      if offset and numSlots then
        for s = offset + 1, offset + numSlots do
          if GetSpellBookItemName(s, BOOKTYPE_SPELL_) == name then
            local _, sid = GetSpellBookItemInfo(s, BOOKTYPE_SPELL_)
            add(sid)
          end
        end
      end
    end
  end
  return ids
end

-- Highest rank of an ability the player has learned, so the tile shows the live rank's icon/name/
-- tooltip rather than the curated rank-1 seed.
--
-- DOWNPORT: see the header. `select(7, GetSpellInfo(name))` is castTime on this client, so that
-- approach is not merely unavailable — it silently returns a wrong-but-plausible number. All
-- resolution goes through the spellbook-derived rank table.
local function highestKnownRankID(spellID, name)
  if not (spellID and name) then return spellID end
  if SB and SB.HighestKnownRankID then return SB.HighestKnownRankID(spellID, name) end
  return spellID
end

-- Public wrapper so other surfaces (the settings catalog) can resolve a curated rank-1 id to the
-- player's highest learned rank for display.
function M.HighestKnownRank(spellID)
  if not spellID then return spellID end
  return highestKnownRankID(spellID, GetSpellInfo(spellID))
end

function ItemMixin:SetSpell(spellID)
  self._equipSlot = nil   -- spell-sourced: clear any prior trinket binding (pool slot reuse)
  local itemID, track = M.GetItemMeta(spellID)
  self._itemCDID = (track == "item") and itemID or nil

  local name = GetSpellInfo(spellID)
  -- A pure spell displays its highest learned rank; an on-use item entry keeps its own id (its
  -- "rank" is meaningless — icon and cooldown come from the item).
  local displayID = (not itemID) and highestKnownRankID(spellID, name) or spellID
  self.spellID = displayID

  -- The id the spell was LISTED under, kept alongside the displayed one. `spellID` is whatever rank
  -- the player currently knows, so it changes under the tile the moment they train the next rank —
  -- fine for reading a cooldown, wrong as a settings key. Per-spell preferences (alerts, ready
  -- sounds) hang off this stable id instead, or training a rank would silently orphan them.
  self._baseSpellID = spellID

  local icon
  name, _, icon = GetSpellInfo(displayID)
  self.spellName = name

  self._iconItemID = itemID or nil
  if itemID then
    local itemIcon = M.ResolveItemIcon(itemID)
    if itemIcon then icon = itemIcon end
  end

  self._rankCDIDs = (not self._itemCDID) and knownRankIDs(spellID, name) or nil
  if self.Icon then self.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
  self:RefreshCooldown()
end

-- Equipped on-use trinket. Cooldown is read live from the inventory slot; the use-spell drives the
-- usable tint and aura precedence, while the icon prefers the equipped item texture.
function ItemMixin:SetEquipSlot(slot, itemID, useSpellID)
  self._equipSlot   = slot
  self._equipItemID = itemID
  self._itemCDID    = nil
  self._rankCDIDs   = nil
  self.spellID      = useSpellID
  self._baseSpellID = useSpellID   -- item use-spells have no ranks, so this is already stable
  self.spellName    = useSpellID and GetSpellInfo(useSpellID) or nil
  self._iconItemID  = itemID or nil
  local icon = (GetInventoryItemTexture and GetInventoryItemTexture("player", slot))
    or M.ResolveItemIcon(itemID)
    or (useSpellID and select(3, GetSpellInfo(useSpellID)))
  if self.Icon then self.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
  self:RefreshCooldown()
end

-- Bag consumable (potion / healthstone). Cooldown comes from the ITEM, not the use-spell.
function ItemMixin:SetBagItem(itemID, useSpellID)
  self._equipSlot   = nil
  self._equipItemID = nil
  self._bagItemID   = itemID
  self._itemCDID    = itemID
  self._rankCDIDs   = nil
  self.spellID      = useSpellID
  self._baseSpellID = useSpellID
  self.spellName    = useSpellID and GetSpellInfo(useSpellID) or nil
  self._iconItemID  = itemID or nil
  local icon = M.ResolveItemIcon(itemID)
  if self.Icon then self.Icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark") end
  self:RefreshCooldown()
end

-- Re-resolve the icon for an item-backed entry once the server delivers its data.
function ItemMixin:RefreshIcon()
  if not (self.Icon and self._iconItemID) then return end
  local icon
  if self._equipSlot then
    icon = (GetInventoryItemTexture and GetInventoryItemTexture("player", self._equipSlot))
      or M.ResolveItemIcon(self._iconItemID)
  else
    icon = M.ResolveItemIcon(self._iconItemID)
  end
  if icon then self.Icon:SetTexture(icon) end
end

function ItemMixin:SetTimerShown(shown)
  self.timerShown = shown
  NE.cd.ApplyNumbers(self.Cooldown, { show = shown })
end

function ItemMixin:SetTooltipsShown(shown)
  self.tooltipsShown = shown
end

function ItemMixin:SetHideWhenInactive(hide)
  self.hideWhenInactive = hide
  self:UpdateShownState()
end

-- Retail swipe colours. DOWNPORT: 3.3.5a Cooldown has no SetSwipeColor, so these are applied only
-- when the setter exists (i.e. never on this client). Kept so the aura/cooldown distinction is
-- still expressed in code and lights up automatically if the surface ever gains it.
M.COLOR_COOLDOWN = { 0,   0,    0,    0.7 }
M.COLOR_AURA     = { 1,   0.95, 0.57, 0.7 }
M.COLOR_WHITE    = { 1,   1,    1,    1   }

local function setSwipeColor(cooldown, c)
  if cooldown and cooldown.SetSwipeColor then
    cooldown:SetSwipeColor(c[1], c[2], c[3], c[4])
  end
end

-- ── The buffed-spell glow (§H.2 8c) ─────────────────────────────────────────────────────────────
-- The guide's second headline feature: "puts glow effects around buffed spells". Retail expresses it
-- as COLOR_AURA on the swipe — which, per the note above, this client cannot set. So we substitute
-- the signal rather than the colour: a static gold halo on the tile while the spell's buff is up.
--
-- Not LibCustomGlow, which §H.2 nominated. Every glow that library renders MOVES (marching ants,
-- pulsing button glow, orbiting sparkles), and motion on this addon already means something else —
-- it is the alert vocabulary (Alerts.lua), fired when something needs attention NOW. A buff being up
-- is a steady state, and retail draws it as one.
--
-- The FIRST attempt drew a gold additive copy of the tile's own IconOverlay art, on the reasoning
-- that lighting the existing frame would align perfectly and cost nothing. It rendered as absolutely
-- nothing in game, and the art says why: 6704514's overlay cell is pure black — every texel (0,0,0)
-- carrying only an alpha ramp, peaking at a=104 on the border line. It is a SHADOW, not a metal
-- frame. ADD blending adds src.rgb x alpha, so black source emits zero light no matter what vertex
-- colour is multiplied over it. The atlas resolved, the region was shown, and the maths produced an
-- invisible texture — a different route to 8a's exact failure mode.
--
-- So: the stock soft-glow ring, which is what this repo already uses for the bag rarity glow, the
-- auction detail ring and the profession reagent slots (modules/bags/BagSkin.lua:29). It is present
-- on every 3.3.5a client, it is pale rather than black, and it is built to be tinted.
M.BUFF_GLOW_TEXTURE = "Interface\\Buttons\\UI-ActionButton-Border"

-- Oversize, as a fraction of the tile edge; 35% is the figure the call sites above converged on, and
-- for the reason documented there: the texture keeps its glow INSET within a transparent margin, so
-- at the tile's own rect the visible ring falls inside the icon rather than on its edge.
--
-- That is what "icon glow effect inside frame" was — the ring landing too far in. I read it as a
-- FILLED texture veiling the art and moved the region behind the icon for two passes, where the frame
-- shadow then suppressed it. It draws on top now (Viewers.lua), which is how every other use of this
-- texture in the addon draws it.
M.BUFF_GLOW_OVERSIZE = 0.35
M.BUFF_GLOW_MIN_OVER = 6

function M.BuffGlowInset(size)
  local over = math.floor((size or 0) * M.BUFF_GLOW_OVERSIZE + 0.5)
  if over < M.BUFF_GLOW_MIN_OVER then over = M.BUFF_GLOW_MIN_OVER end
  return over
end

-- The halo, in its OWN FRAME. This is the part no draw layer could have fixed, and it is why moving
-- the region from BACKGROUND to OVERLAY 7 changed nothing the owner could see.
--
-- `Cooldown` is a CHILD FRAME of the tile, and a child frame draws above EVERY layer of its parent —
-- BACKGROUND and OVERLAY 7 alike. The halo was therefore under the sweep no matter which layer it was
-- given, and the sweep is a rotating wedge, so which part of the halo survived depended on where the
-- sweep happened to be. That is every symptom reported against this glow, in one mechanism: "doesn't
-- align to the top or right hand sides", "the swipe covers the glow on the right but not the left",
-- and a snapped-to-pixel inset that "didn't fix anything" — because pixels were never the problem
-- on this one.
--
-- A sibling frame with a higher frame level is the only thing that outranks a child frame. The
-- texture inside it is unchanged: same art, same ADD, same rect.
function M.BuildBuffGlow(parent, size)
  if not parent then return nil end
  local go = M.BuffGlowInset(size)
  local f = CreateFrame("Frame", nil, parent)
  -- Anchored to the ICON, not the tile, so the two are concentric by construction and the halo
  -- follows the inset slider without being told about it.
  f:SetPoint("TOPLEFT", parent.Icon, "TOPLEFT", -go, go)
  f:SetPoint("BOTTOMRIGHT", parent.Icon, "BOTTOMRIGHT", go, -go)
  local base = (parent.Cooldown and parent.Cooldown.GetFrameLevel and parent.Cooldown:GetFrameLevel())
               or (parent.GetFrameLevel and parent:GetFrameLevel()) or 1
  f:SetFrameLevel(base + 3)

  f.Texture = f:CreateTexture(nil, "OVERLAY")
  f.Texture:SetAllPoints(f)
  f.Texture:SetTexture(M.BUFF_GLOW_TEXTURE)
  f.Texture:SetBlendMode("ADD")
  f.Texture:SetVertexColor(M.COLOR_BUFF_GLOW[1], M.COLOR_BUFF_GLOW[2], M.COLOR_BUFF_GLOW[3],
                           M.COLOR_BUFF_GLOW[4])
  f:Hide()
  return f
end

-- Tunable: warm gold, the colour retail gives the swipe it will not let us tint here.
M.COLOR_BUFF_GLOW = { 1, 0.82, 0.30, 0.9 }

function ItemMixin:SetBuffGlow(on)
  local glow = self.BuffGlow
  if not glow then return end
  on = on and true or false
  if on and not M.IsBuffGlowEnabled() then on = false end
  if self._buffGlow == on then return end
  self._buffGlow = on
  if on then glow:Show() else glow:Hide() end
end

-- ── Stack count ─────────────────────────────────────────────────────────────────────────────────
--
-- The aura viewers have always drawn one; a SPELL tile never did, because a cooldown does not have
-- stacks. Its aura does. Issue #52: "I'd like to see the stack count when active... Most Shaman WAs
-- have a way to track the shield stacks because it's very important to maintain their uptime" — and
-- the shields are spells, not buffs, precisely because they are up all the time and belong on a
-- tile you press rather than in a list of things that happened to you.
--
-- Bottom-right, matching the BuffIcon tile's Applications label.
--
-- IN ITS OWN CHILD FRAME, for the reason M.BuildBuffGlow spells out at length: `Cooldown` is a child
-- frame, a child frame draws above every LAYER of its parent, and so a fontstring created on the
-- tile at OVERLAY would sit under the sweep and be eaten by it a wedge at a time. Only a sibling
-- frame with a higher level outranks it. BuffViewers reaches the same arrangement for its own count.
--
-- Not parented to CooldownFlash either, which was the first attempt: that frame ships Hidden and is
-- only shown for the length of the ready burst, so the count would have been invisible except during
-- a flash — a failure that looks exactly like "stack counts don't work".
function M.BuildCount(parent)
  if not parent then return nil end
  local base = (parent.Cooldown and parent.Cooldown.GetFrameLevel and parent.Cooldown:GetFrameLevel())
               or (parent.GetFrameLevel and parent:GetFrameLevel()) or 1
  local f = CreateFrame("Frame", nil, parent)
  f:SetAllPoints(parent)
  f:SetFrameLevel(base + 4)
  f.Text = f:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  f.Text:SetPoint("BOTTOMRIGHT", parent.Icon or parent, "BOTTOMRIGHT", -2, 2)
  f.Text:SetJustifyH("RIGHT")
  f.Text:Hide()
  return f
end

-- 1 is not a stack. A single-application aura showing a "1" is noise on every DoT in the game, and
-- the client's own buff frames have always suppressed it.
function ItemMixin:SetAuraCount(count)
  local fs = self.Count and self.Count.Text
  if not fs then return end
  count = tonumber(count) or 0
  if self._auraCountShown == count then return end
  self._auraCountShown = count
  if count > 1 then
    fs:SetText(count)
    fs:Show()
  else
    fs:Hide()
  end
end

-- GCD detection. Retail reads C_Spell.GetSpellCooldown(spellID).isOnGCD; we replicate the manual
-- probe: query the sentinel "Global Cooldown" spell and compare start+duration.
local GCD_PROBE_SPELL = 61304

local function isSpellOnGCD(spellID, start, duration)
  if not (start and start > 0 and duration and duration > 0) then return false end
  local gcdStart, gcdDuration = GetSpellCooldown(GCD_PROBE_SPELL)
  if not (gcdStart and gcdDuration and gcdDuration > 0) then return false end
  return math.abs(start - gcdStart) < 0.05 and math.abs(duration - gcdDuration) < 0.05
end

-- Start/end milliseconds out of UnitCastingInfo/UnitChannelInfo.
--
-- 3.3.5a keeps a `nameSubtext` return that retail dropped, so this client lays the pair out as
-- (name, nameSubtext, text, texture, startTime, endTime, ...) — positions 5 and 6 — while the
-- retail signature the upstream NewEra code was written against puts them at 4 and 5. Reading the
-- retail positions here handed back the texture PATH as the start time, and the divide below threw
-- "attempt to perform arithmetic on local 'csMS' (a string value)" on every refresh mid-cast.
-- Pick the layout by type rather than by client, so either signature works: slot 4 is a number on
-- retail and the texture string here.
local function castTimesMS(info, unit)
  if not info then return nil end
  local a, b, c = select(4, info(unit))
  if type(a) == "number" and type(b) == "number" then return a, b end
  if type(b) == "number" and type(c) == "number" then return b, c end
  return nil
end

-- Cast-lockout: mid-cast/channel, GetSpellCooldown reports the cast duration as the "cooldown" of
-- the locked spells.
local function isCastLockoutCooldown(start, duration)
  if not (start and duration) then return false end
  local csMS, ceMS = castTimesMS(UnitCastingInfo, "player")
  if csMS and ceMS then
    local castStart = csMS / 1000
    local castDur   = (ceMS - csMS) / 1000
    if math.abs(start - castStart) < 0.05 and math.abs(duration - castDur) < 0.1 then return true end
  end
  local hsMS, heMS = castTimesMS(UnitChannelInfo, "player")
  if hsMS and heMS then
    local chStart = hsMS / 1000
    local chDur   = (heMS - hsMS) / 1000
    if math.abs(start - chStart) < 0.05 and math.abs(duration - chDur) < 0.1 then return true end
  end
  return false
end

-- A player buff/debuff matching this spell name. DOWNPORT: backed by NE.aura (core/AuraSnapshot.lua)
-- so the player's aura list is walked once per frame addon-wide. The returned entry keeps this
-- module's legacy field names (.expirationTime / .debuffType / .isHarmful).
local adaptedPool = {}

local function adaptRow(row, harmful)
  local e = adaptedPool[row.name]
  if not e then e = {}; adaptedPool[row.name] = e end
  e.name           = row.name
  e.count          = row.count or 0
  e.duration       = row.duration or 0
  e.expirationTime = row.expiration or 0
  e.isHarmful      = harmful or nil
  e.debuffType     = harmful and row.dispelType or nil
  e.caster         = row.caster
  return e
end

function M.findPlayerAuraDataByName(name)
  if not (name and NE.aura and NE.aura.FindByName) then return nil end
  local row, harmful = NE.aura.FindByName("player", name)
  if not row then return nil end
  local e = adaptedPool[name]
  if not e then e = {}; adaptedPool[name] = e end
  e.name           = row.name
  e.count          = row.count or 0
  e.duration       = row.duration or 0
  e.expirationTime = row.expiration or 0
  e.isHarmful      = harmful or nil
  e.debuffType     = harmful and row.dispelType or nil
  return e
end

-- ── The spell -> aura edge ──────────────────────────────────────────────────────────────────────
--
-- Everything that asks "is this spell's effect up right now" used to ask it as "is there an aura on
-- the PLAYER with the SAME NAME as this spell". Two whole families of ability answer no to that
-- forever, and both were reported:
--
--   * the aura is named differently. Bloodsurge turns Slam into `Slam!`; Brain Freeze turns Fireball
--     into `Fireball!`. One character, and the match never succeeds (issue #57, warrior "Embate").
--   * the aura is not on the player. Faerie Fire, Moonfire and every DoT land on the TARGET; Earth
--     Shield lands on a PARTY MEMBER (issues #57 druid Balance, and #52 shaman shields).
--
-- CdmSpellAuras.lua carries the edge, generated from the client's own Spell.dbc. This resolves it.
--
-- The plain same-name-on-player lookup stays FIRST, and the generated table is deliberately missing
-- every row it would answer: it is cheaper, it is rank-proof without any table at all, and it is
-- right for the large majority of tiles. The links are the fallback for the cases it cannot see.

-- Where a `friend` link is looked for.
--
-- Earth Shield is the only ability that reaches this, by construction: CdmSpellAuras.lua's FRIEND_OK
-- refuses a friend link to anything that can be out on several allies at once, because a tile shows
-- ONE aura and "which of your twenty shields is this" has no answer. So the set below only has to be
-- good enough to find a shaman's single shield.
--
-- Your own party, plus the raid's MAIN TANKS. The party units are where it lands when five-manning;
-- the tank assignment is where it lands in a raid, which is the whole point of the spell and is
-- otherwise outside party1-4 entirely. Everything else in a forty-man roster is not swept: that is
-- forty aura scans a frame to find one buff, and the tanks are where it actually is.
--
-- Still a REACHABLE SET, not a complete one. Shield an unflagged raider in another subgroup and the
-- tile stays dark. Documented rather than papered over.
--
-- COST, because this is the one lookup here that is not O(1). Measured in the offline harness
-- (NE.aura._scans), per frame, over Earth Shield tiles:
--
--   solo, nothing out                            2 scans   (the player pass, which happens anyway)
--   full party, nothing out                      8
--   full party, shield out, steady state         3
--   25-man raid, two main tanks, nothing out    10   <- the worst case, and it is the idle one
--
-- The count is PER FRAME, not per tile: NE.aura caches one scan per (unit, filter) per frame, so
-- five shield tiles cost exactly what one does — and a scan is a loop that breaks at the unit's
-- first empty slot, not a fixed forty. Solo players pay nothing, because UnitExists gates every
-- party slot before a scan is requested. The roster walk that finds the tanks is event-driven, so a
-- 25-man roster is 25 GetRaidRosterInfo calls when the roster CHANGES and none in between.
--
-- Only a shaman with a shield tile pays any of it. FRIEND_OK is most of the saving: this used to run
-- for every HoT, Blessing and Power Word: Shield in the game, at 14 scans a frame, to produce an
-- answer that was wrong anyway. qa/offline/test_boot.lua holds all of these to a budget.
local FRIEND_UNITS = { "player", "target", "focus", "party1", "party2", "party3", "party4" }

-- A buff you cast on an ally is HELPFUL. Walking seven units' debuff lists as well was half the cost
-- of this lookup and could never have found anything.
local FRIEND_FILTER = "HELPFUL"

-- The raid's main tanks, appended to the sweep when there is a raid.
--
-- CACHED AND EVENT-DRIVEN, because building it is a walk of the whole roster: GetRaidRosterInfo is
-- one call per member, so recomputing it inside a 5Hz lookup would cost forty calls a frame to save
-- forty aura scans. The roster only changes when the roster changes, so it is rebuilt on the two
-- events that say so and read from a table in between.
--
-- 3.3.5a has no UnitGroupRolesAssigned (Cata+). The MAIN TANK assignment from the raid UI is the
-- role signal this client has, and it is returned as the 10th value of GetRaidRosterInfo.
local tankUnits, tanksDirty = {}, true

local function rebuildTanks()
  tanksDirty = false
  for i = #tankUnits, 1, -1 do tankUnits[i] = nil end
  local n = (GetNumRaidMembers and GetNumRaidMembers()) or 0
  if n <= 0 or not GetRaidRosterInfo then return end
  for i = 1, n do
    local _, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
    -- MAINASSIST included: plenty of raids flag their off-tank that way, and the cost of one extra
    -- unit is one cached scan.
    if role == "MAINTANK" or role == "MAINASSIST" then
      tankUnits[#tankUnits + 1] = "raid" .. i
    end
  end
end

local rosterWatcher = CreateFrame("Frame")
rosterWatcher:RegisterEvent("RAID_ROSTER_UPDATE")
rosterWatcher:RegisterEvent("PARTY_MEMBERS_CHANGED")
rosterWatcher:SetScript("OnEvent", function() tanksDirty = true end)

-- Test seam, and the diagnostic answer to "why is my Earth Shield tile dark".
function M.FriendTankUnits()
  if tanksDirty then rebuildTanks() end
  return tankUnits
end

-- The localized name of a linked aura, memoised onto the link row.
--
-- GetSpellInfo FIRST and the generated `name` only as a fallback. The generated string is enUS and
-- the player who reported this runs esES, where `Slam!` is `¡Embate!` — a name this addon could
-- never have derived and must therefore ask the client for. Memoised because a locale cannot change
-- inside a session, and this is read from a 5Hz ticker.
local function linkName(link)
  local n = link._name
  if n ~= nil then return n or nil end
  n = (link.id and GetSpellInfo(link.id)) or link.name
  link._name = n or false
  return n
end

-- The link rows for a tile, at whichever rank it happens to hold.
--
-- `_baseSpellID` first: that is the id the spell was LISTED under, which is what the generated table
-- keys rank 1 of. `spellID` is the highest rank the player knows and moves under the tile as they
-- train. Both are covered, plus every learned rank, so a custom list holding any rank resolves.
local function auraLinksFor(item)
  local T = M.SPELL_AURA_LINKS
  if not (T and item) then return nil end
  local rows = (item._baseSpellID and T[item._baseSpellID]) or (item.spellID and T[item.spellID])
  if rows then return rows end
  local ranks = item._rankCDIDs
  if ranks then
    for i = 1, #ranks do
      if T[ranks[i]] then return T[ranks[i]] end
    end
  end
  return nil
end
M.AuraLinksFor = auraLinksFor

-- Does this tile have ANY way of showing an aura? Used by the alert menu to stop offering `Refresh`
-- on a spell that provably cannot trigger it (Starfire applies nothing at all — issue #57's first
-- report was an alert assigned to exactly that, waiting for something that could never happen).
function M.SpellCanShowAura(item)
  if not item then return false end
  if auraLinksFor(item) then return true end
  -- No link table row does NOT mean no aura: the generated table omits every same-name-on-player
  -- case precisely because the plain lookup already finds it. So "is one up right now" remains the
  -- only honest answer available for those, and a live sighting is proof enough.
  return item.spellName ~= nil and M.findPlayerAuraDataByName(item.spellName) ~= nil
end

-- The aura this tile should be reporting, and the unit it was found on.
--
-- Returns (entry, unitToken) or nil. The entry is the same pooled shape findPlayerAuraDataByName
-- hands back, so every existing consumer reads it unchanged.
function M.FindSpellAura(item)
  if not (item and NE.aura and NE.aura.FindByName) then return nil end
  local now = GetTime()

  -- 1. This spell's own name, on the player.
  --
  -- MINE FIRST, then a caster-less aura. The plain byName index answers "an aura of this name is on
  -- you", which for anything another player can also cast on you — Renew, Fortitude, Power Word:
  -- Shield — lit the tile for someone else's work. HoTs from two casters coexist as separate auras,
  -- so a post-hoc caster test on the first match would also have rejected yours while theirs sat two
  -- slots down; asking the mine index directly is what gets this right.
  --
  -- The caster-less fallback is not tidiness: several 3.3.5a proc auras report no caster at all, and
  -- demanding one would lose exactly the links this resolver was built to add. A nil caster is
  -- accepted, a DIFFERENT caster is not.
  local name = item.spellName
  if name then
    local row, harmful = NE.aura.FindByName("player", name, true)
    if not (row and row.duration > 0 and row.expiration > now) then
      row = nil
      local any, h2 = NE.aura.FindByName("player", name)
      if any and any.caster == nil and any.duration > 0 and any.expiration > now then
        row, harmful = any, h2
      end
    end
    if row then return adaptRow(row, harmful), "player" end
  end

  -- 2. The generated links.
  local links = auraLinksFor(item)
  if not links then return nil end
  for i = 1, #links do
    local link = links[i]
    local name = linkName(link)
    if name then
      if link.unit == "friend" then
        -- mineOnly: a raid with two shamans has two Earth Shields, and only one of them is the
        -- answer to "is MY Earth Shield out".
        local function try(unit)
          if not (unit and UnitExists(unit)) then return nil end
          local row, harmful = NE.aura.FindByName(unit, name, true, FRIEND_FILTER)
          if row and row.duration > 0 and row.expiration > now then
            return adaptRow(row, harmful), unit
          end
          return nil
        end
        -- The unit it was on last time, first. A shield stays on the same tank for its whole
        -- duration, so the steady state is one cached scan rather than a sweep per frame; the sweep
        -- is then only paid on the frame it moves, or while it is not out at all.
        local aura, unit = try(item._friendUnit)
        if aura then return aura, unit end
        for u = 1, #FRIEND_UNITS do
          aura, unit = try(FRIEND_UNITS[u])
          if aura then item._friendUnit = unit; return aura, unit end
        end
        -- Then the raid's main tanks, who are where a shaman's Earth Shield actually is and who are
        -- outside party1-4 in every raid where the shaman is not in the tank's subgroup.
        local tanks = M.FriendTankUnits()
        for u = 1, #tanks do
          aura, unit = try(tanks[u])
          if aura then item._friendUnit = unit; return aura, unit end
        end
        item._friendUnit = nil
      else
        local unit = link.unit or "player"
        -- Only the player's own frame is exempt from the caster test. A debuff on the target is
        -- shared ground — another druid's Moonfire must not light this tile — whereas a buff on
        -- YOU from a proc is yours by construction, and some 3.3.5a procs report no caster at all,
        -- so demanding one there would lose the very links this table exists to add.
        local row, harmful = NE.aura.FindByName(unit, name, unit ~= "player")
        if row and row.duration > 0 and row.expiration > now then
          return adaptRow(row, harmful), unit
        end
      end
    end
  end
  return nil
end

-- Live totem lookup (Shaman): a tracked totem spell sources its swipe from the real totem timer.
-- 3.3.5a exposes GetTotemInfo(slot) -> haveTotem, name, startTime, duration, icon and fires
-- PLAYER_TOTEM_UPDATE, same as the source assumed.
function M.FindTotemByName(name)
  if not name then return nil end
  if not GetTotemInfo then return nil end
  local slots = (GetNumTotemSlots and GetNumTotemSlots()) or MAX_TOTEMS or 4
  for slot = 1, slots do
    local haveTotem, totemName, startTime, duration = GetTotemInfo(slot)
    if haveTotem and totemName and totemName ~= "" and duration and duration > 0 then
      if totemName == name or totemName:find(name, 1, true) or name:find(totemName, 1, true) then
        return startTime, duration
      end
    end
  end
  return nil
end

-- Duration-based GCD threshold, used when the 61304 probe is unavailable.
M.GCD_MAX = 1.51

-- Rank-safe cooldown read. Try the keyed id, then every known rank (returning the one with the
-- longest remaining cooldown — the rank actually cast, regardless of up/down-ranking), then name.
function M.SpellCD(spellID, spellName, rankIDs)
  local start, duration, enabled = GetSpellCooldown(spellID)
  if start and start > 0 then return start, duration, enabled end
  if rankIDs then
    local bestStart, bestDur, bestEnab, bestEnd = nil, nil, nil, 0
    for i = 1, #rankIDs do
      local s, d, e = GetSpellCooldown(rankIDs[i])
      if s and s > 0 and d and d > 0 and (s + d) > bestEnd then
        bestStart, bestDur, bestEnab, bestEnd = s, d, e, s + d
      end
    end
    if bestStart then return bestStart, bestDur, bestEnab end
  end
  if spellName then
    local s2, d2, e2 = GetSpellCooldown(spellName)
    if s2 and s2 > 0 then return s2, d2, e2 end
  end
  return start, duration, enabled
end

-- Read this item's cooldown, returning ALL THREE values.
--
-- MUST stay an explicit branch. The tempting one-liner
--   local start, duration, enabled = self._itemCDID and M.ItemCooldown(...) or M.SpellCD(...)
-- is the multi-return truncation trap: Lua adjusts an `or` operand to ONE value, so duration and
-- enabled arrive nil and every refresh computes cooldownIsActive=false. That was the whole
-- "doesn't show cooldowns on cooldown" bug upstream.
function ItemMixin:ReadCooldown()
  if self._equipSlot then return GetInventoryItemCooldown("player", self._equipSlot) end
  if self._itemCDID then return M.ItemCooldown(self._itemCDID) end
  return M.SpellCD(self.spellID, self.spellName, self._rankCDIDs)
end

function ItemMixin:UpdateShownState()
  if not (self.spellID or self._bagItemID) then self:Hide(); return end
  -- Retail's ShouldBeShown: items whose template doesn't set allowHideWhenInactive ALWAYS show.
  -- Essential and Utility both fall in that category — they show every configured cooldown the
  -- player knows, on or off cooldown. Only BuffIcon/BuffBar honour hideWhenInactive.
  if not self.allowHideWhenInactive then self:Show(); return end
  if not self.hideWhenInactive then self:Show(); return end

  -- Same widened lookup as RefreshCooldown: a tile set to hide when inactive is not inactive while
  -- its DoT is ticking on the target.
  local aura = M.FindSpellAura(self)
  if aura and aura.duration > 0 and aura.expirationTime > GetTime() then
    self:Show()
    return
  end
  local start, duration = self:ReadCooldown()
  local hasCooldown = start and start > 0 and duration and duration > 0
  if hasCooldown
     and not isSpellOnGCD(self.spellID, start, duration)
     and not isCastLockoutCooldown(start, duration)
     and duration > M.GCD_MAX then
    self:Show()
  else
    self:Hide()
  end
end

-- ── Ready flash ─────────────────────────────────────────────────────────────────────────────────
-- The cue that an ability has just come off cooldown. Retail plays a 22-frame flipbook sprite; the
-- source steps it by hand (the animation system was unavailable to it too), and that stepper ports.
--
-- TWO FAULTS FIXED HERE, both of which made the flash silently never appear:
--
--  1. `NE.tex.GetAtlasRect` returns FOUR NUMBERS (left, right, top, bottom), not a table. The
--     stepper indexed the result as `atlas.right`, so `atlas` was the number `left` and every
--     access errored inside an OnUpdate.
--  2. The "art not shipped, degrade quietly" guard was `if not getFlashAtlas()`. GetAtlasRect
--     returns `0, 1, 0, 1` for an UNKNOWN atlas, and `0` is truthy in Lua — so the guard passed
--     precisely when the art was missing. `NE.tex.HasAtlas` is the correct test.
--
-- The retail flipbook art is not registered on this client, so the flipbook path is dormant. Rather
-- than leave the feature invisible, an undecorated fallback pulses the square button highlight —
-- a base-client texture DragonUI itself uses, so it cannot fail to load. If the flipbook atlas is
-- ever registered, the sprite path takes over with no further change.
local FLASH_DURATION = 0.75
local FLASH_FRAMES   = 22
local FLASH_ROWS     = 11
local FLASH_COLS     = 2

-- A base-client texture DragonUI itself uses (modules/bagsort.lua et al), so it cannot fail to load.
M.FLASH_FALLBACK_TEXTURE = "Interface\\Buttons\\ButtonHilight-Square"

local function hasFlipbook()
  return NE.tex and NE.tex.HasAtlas and NE.tex.HasAtlas("UI-HUD-ActionBar-GCD-Flipbook")
end

-- left, right, top, bottom as a table, or nil when the atlas is unknown.
local function getFlashAtlas()
  if not hasFlipbook() then return nil end
  local l, r, t, b = NE.tex.GetAtlasRect("UI-HUD-ActionBar-GCD-Flipbook")
  return { left = l, right = r, top = t, bottom = b }
end

local function flashOnUpdate(flash)
  local now = GetTime()
  local start = flash._flashStartTime
  if not start then flash:SetScript("OnUpdate", nil); flash:Hide(); return end
  if now < start then return end
  local progress = (now - start) / FLASH_DURATION
  if progress >= 1 then
    flash:SetScript("OnUpdate", nil)
    flash:Hide()
    if flash.Flipbook then flash.Flipbook:SetAlpha(0) end
    flash._flashStartTime = nil
    return
  end
  if not flash.Flipbook then return end

  local atlas = getFlashAtlas()
  if not atlas then
    -- Fallback burst: snap to full brightness, then expand outward past the icon while fading.
    -- A pure alpha blink on an icon-sized quad is nearly invisible against the art underneath —
    -- the outward growth is what makes it read at a glance, which was the reported problem.
    local tex = flash.Flipbook
    local alpha
    if progress < 0.15 then
      alpha = progress / 0.15                  -- fast ramp in
    else
      alpha = 1 - (progress - 0.15) / 0.85     -- long fade out
    end
    if alpha < 0 then alpha = 0 elseif alpha > 1 then alpha = 1 end
    tex:SetAlpha(alpha)

    -- Grow from the icon's own bounds to ~1.7x across the burst.
    local w = flash:GetWidth() or 30
    local pad = w * 0.35 * progress
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT",     flash, "TOPLEFT",     -pad,  pad)
    tex:SetPoint("BOTTOMRIGHT", flash, "BOTTOMRIGHT",  pad, -pad)
    return
  end

  flash.Flipbook:SetAlpha(1)
  local frame = math.floor(progress * FLASH_FRAMES)
  if frame >= FLASH_FRAMES then frame = FLASH_FRAMES - 1 end
  local col = frame % FLASH_COLS
  local row = math.floor(frame / FLASH_COLS)
  local frameW = (atlas.right - atlas.left) / FLASH_COLS
  local frameH = (atlas.bottom - atlas.top) / FLASH_ROWS
  local l = atlas.left + col * frameW
  local t = atlas.top  + row * frameH
  flash.Flipbook:SetTexCoord(l, l + frameW, t, t + frameH)
end

function ItemMixin:ScheduleFlash(start, duration)
  local flash = self.CooldownFlash
  if not (flash and flash.Flipbook) then return end
  -- No atlas gate here any more: the fallback pulse needs no art, so the flash is always available.
  -- The old guard could not detect a missing atlas anyway (see the note above).
  if self._flashScheduledFor == start and self._flashScheduledDur == duration then return end
  self._flashScheduledFor = start
  self._flashScheduledDur = duration
  local playStart = (start + duration) - FLASH_DURATION
  if playStart <= GetTime() then
    flash:Hide()
    flash:SetScript("OnUpdate", nil)
    return
  end
  flash._flashStartTime = playStart
  if flash.Flipbook then flash.Flipbook:SetAlpha(0) end
  flash:Show()
  flash:SetScript("OnUpdate", flashOnUpdate)
end

function ItemMixin:ClearFlash()
  self._flashScheduledFor = nil
  self._flashScheduledDur = nil
  local flash = self.CooldownFlash
  if flash then
    flash:SetScript("OnUpdate", nil)
    flash:Hide()
    flash._flashStartTime = nil
    if flash.Flipbook then
      flash.Flipbook:SetAlpha(0)
      -- The burst grows the texture past the frame; put it back or the next play starts oversized.
      flash.Flipbook:ClearAllPoints()
      flash.Flipbook:SetAllPoints(flash)
    end
  end
end

-- ── Icon tint ───────────────────────────────────────────────────────────────────────────────────
-- Priority: out-of-range red > usable white > not-enough-mana blue > not-usable grey, plus the OOR
-- shadow overlay. Composes with SetDesaturated (orthogonal).
M.ICON_USABLE     = { 1.0,  1.0,  1.0  }
M.ICON_OOM        = { 0.5,  0.5,  1.0  }
M.ICON_UNUSABLE   = { 0.4,  0.4,  0.4  }
M.ICON_OUTOFRANGE = { 0.64, 0.15, 0.15 }

-- DOWNPORT: SetShown does not exist on 3.3.5a (CONTRACTS §0).
local function setShown(region, shown)
  if not region then return end
  if shown then region:Show() else region:Hide() end
end

function ItemMixin:RefreshIconColor()
  if not self.Icon then return end

  -- Equipped trinket / bag consumable: tint from ITEM usability. IsUsableSpell on a use-spell
  -- returns false (it isn't a known player spell), which would wrongly grey a usable trinket.
  local itemForUsability = self._equipSlot and self._equipItemID or self._bagItemID
  if itemForUsability or self._equipSlot then
    local usable = true
    if IsUsableItem and itemForUsability then usable = IsUsableItem(itemForUsability) and true or false end
    local c = usable and M.ICON_USABLE or M.ICON_UNUSABLE
    self.Icon:SetVertexColor(c[1], c[2], c[3])
    setShown(self.OutOfRange, false)
    return
  end

  if not self.spellID then return end

  -- DOWNPORT: C_Spell.IsSpellUsable is absent on this client (neither ClassicAPI nor compat provides
  -- it), so we use the 3.3.5a global directly — and it must be given the spell NAME.
  --
  -- 3.3.5a's IsUsableSpell takes a name, or a spellbook INDEX with a bookType. It does not take a
  -- spellID. Passing one is read as an index far past the end of the book, so it returns nil rather
  -- than erroring — and nil is neither usable nor out-of-mana, so every icon fell through to
  -- ICON_UNUSABLE and the whole viewer rendered permanently grey. DragonUI's own action bars pass a
  -- name for this reason (modules/actionbars/extrabar.lua:1049). The id is kept as a fallback for a
  -- nameless entry only.
  local usable, oom
  if IsUsableSpell then usable, oom = IsUsableSpell(self.spellName or self.spellID) end

  -- Range only matters with a live target and a spell that actually range-checks. 3.3.5a's
  -- IsSpellInRange takes a NAME and returns 1/0/nil (nil = no range check applies).
  local outOfRange = false
  if UnitExists("target") and IsSpellInRange and self.spellName then
    local r = IsSpellInRange(self.spellName, "target")
    if r ~= nil then outOfRange = (r == 0) end
  end

  local c = outOfRange and M.ICON_OUTOFRANGE
    or usable and M.ICON_USABLE
    or oom and M.ICON_OOM
    or M.ICON_UNUSABLE
  self.Icon:SetVertexColor(c[1], c[2], c[3])
  setShown(self.OutOfRange, outOfRange)
end

-- ── The refresh ─────────────────────────────────────────────────────────────────────────────────
-- Retail contract:
--   isOnActualCooldown  = not isOnGCD and cooldownIsActive
--   cooldownDesaturated = isOnActualCooldown   -- bright on GCD, grey on a real CD
--   cooldownPlayFlash   = isOnActualCooldown
-- Aura precedence: an active self-aura overrides with the (retail: golden) swipe and no desaturation.
function ItemMixin:RefreshCooldown()
  if not self.spellID or not self.Cooldown then return end

  self:RefreshIconColor()

  -- 1. Aura precedence.
  --
  -- Retail shows the AURA's remaining time here, because its only way to say "this spell's buff is
  -- up" is to tint that swipe gold. Reported as wrong on Prayer of Mending: the tile showed the 30s
  -- buff while the player wanted the cooldown, and the two numbers counting down over the same icon
  -- are indistinguishable. Since 8c the glow says "buffed" on its own, so the swipe no longer has to,
  -- and the timer can be whichever the player finds useful. Default: the cooldown.
  --
  -- The glow is set from `aura` either way — the SIGNAL is not the setting, only the number is.
  --
  -- M.FindSpellAura, not the bare name-on-player lookup it replaced: a DoT on the target and a proc
  -- under another name are both "this tile's effect is up", and neither was ever visible here. The
  -- return is the same pooled shape, so everything below reads unchanged.
  local aura = M.FindSpellAura(self)
  local auraUp = aura and aura.duration > 0 and aura.expirationTime > GetTime()
  self:SetBuffGlow(auraUp and true or false)
  self:SetAuraCount(auraUp and aura.count or 0)

  if auraUp then
    -- The setting picks between two numbers when there ARE two. When the spell has no real cooldown
    -- — a DoT, a shield, a shout — there is only ever one, and the tile used to show nothing at all
    -- rather than show it. So the setting decides, and "no cooldown to compete with" overrides it.
    local showAuraTime = M.BuffShowsAuraTime()
    if not showAuraTime then
      local s, d, en = self:ReadCooldown()
      showAuraTime = not (s and s > 0 and d and d > M.GCD_MAX and en == 1
                          and not isCastLockoutCooldown(s, d))
    end
    if showAuraTime then
      local auraStart = aura.expirationTime - aura.duration
      setSwipeColor(self.Cooldown, M.COLOR_AURA)
      if self.Cooldown.SetDrawSwipe then self.Cooldown:SetDrawSwipe(true) end
      CooldownFrame_Set(self.Cooldown, auraStart, aura.duration, 1)
      if self.Icon then self.Icon:SetDesaturated(false) end
      self:ClearFlash()
      if self.hideWhenInactive then self:Show() end
      return
    end
  end

  -- 1b. Totem precedence (Shaman): source the swipe from the live totem timer; falls through to the
  -- normal cooldown path once the totem is gone, so the cast CD still shows.
  local totemStart, totemDur = M.FindTotemByName(self.spellName)
  if totemStart and totemDur and totemDur > 0 then
    setSwipeColor(self.Cooldown, M.COLOR_AURA)
    if self.Cooldown.SetDrawSwipe then self.Cooldown:SetDrawSwipe(true) end
    CooldownFrame_Set(self.Cooldown, totemStart, totemDur, 1)
    if self.Icon then self.Icon:SetDesaturated(false) end
    -- A live totem is not an aura, but it is the same STATE — this tile's effect is currently up —
    -- and the branch above already gives it COLOR_AURA for that reason. Glowing one and not the
    -- other would make a shaman's totem tiles the only active tiles on screen that look inactive.
    self:SetBuffGlow(true)
    self:ClearFlash()
    if self.hideWhenInactive then self:Show() end
    return
  end

  -- No glow clear here. It USED to sit on this line, on the reasoning that everything below is "no
  -- effect of ours is up" — which stopped being true the moment the aura timer became optional: with
  -- the cooldown preferred, a genuinely buffed spell falls straight through to the cooldown path and
  -- would have its glow wiped on the way past. The one call above covers both readings.

  -- 2. Spell cooldown.
  local start, duration, enabled = self:ReadCooldown()
  local cooldownIsActive = start and start > 0 and duration and duration > 0 and enabled == 1

  if cooldownIsActive then
    -- No isOnGCD flag on this client. Use the duration heuristic, then catch cast/channel lockout
    -- (while mid-cast, all OTHER spells report a "cooldown" matching the cast duration).
    local isOnGCD = duration <= M.GCD_MAX
    if not isOnGCD then isOnGCD = isCastLockoutCooldown(start, duration) end
    local isOnActualCooldown = not isOnGCD

    -- Arm the ready-transition flag. ARM-ONLY here — never clear on this path — so a frequent
    -- refresh can't wipe a pending transition before the detector observes it.
    if isOnActualCooldown then self._wasOnRealCD = true end

    -- Re-run ourselves the moment the cooldown ends.
    --
    -- 3.3.5a fires NO event when a cooldown expires — every event the viewer listens for
    -- (SPELL_UPDATE_COOLDOWN, UNIT_SPELLCAST_*, BAG_UPDATE_COOLDOWN) marks a cooldown STARTING or
    -- changing. The swipe still finishes, because the Cooldown widget animates itself in C, but no
    -- Lua re-runs, so the desaturation set below stayed on until some unrelated event happened to
    -- refresh the tile — usually the player's next cast. That is the reported "icons stay grey
    -- after coming off cooldown".
    --
    -- One timer per cooldown, keyed on its end time so repeated refreshes during the same cooldown
    -- don't stack. The small margin keeps us just past the boundary, where GetSpellCooldown has
    -- certainly cleared.
    if isOnActualCooldown then
      local endsAt = start + duration
      if self._cdRefreshFor ~= endsAt then
        self._cdRefreshFor = endsAt
        local remaining = endsAt - GetTime()
        if remaining > 0 and C_Timer and C_Timer.After then
          C_Timer.After(remaining + 0.05, function()
            -- Only act if this is still the cooldown we scheduled for; a recast supersedes us.
            if self._cdRefreshFor == endsAt then
              self._cdRefreshFor = nil
              self:RefreshCooldown()
            end
          end)
        end
      end
    end

    if self.Cooldown.SetDrawSwipe then self.Cooldown:SetDrawSwipe(true) end
    setSwipeColor(self.Cooldown, M.COLOR_COOLDOWN)
    CooldownFrame_Set(self.Cooldown, start, duration, enabled)

    if self.Icon then self.Icon:SetDesaturated(isOnActualCooldown) end

    if isOnActualCooldown then
      self:ScheduleFlash(start, duration)
    else
      self:ClearFlash()
    end
  else
    CooldownFrame_Clear(self.Cooldown)
    if self.Icon then self.Icon:SetDesaturated(false) end
    self:ClearFlash()
  end

  if self.hideWhenInactive then self:UpdateShownState() end
end

-- Is this item on a REAL cooldown right now — not the GCD, not a cast/channel lockout?
function ItemMixin:IsOnRealCooldown()
  if not self.spellID then return false end
  local start, duration, enabled = self:ReadCooldown()
  if not (start and start > 0 and duration and duration > 0 and enabled == 1) then return false end
  if duration <= M.GCD_MAX then return false end
  if isSpellOnGCD(self.spellID, start, duration) then return false end
  if isCastLockoutCooldown(start, duration) then return false end
  return true
end

-- True EXACTLY ONCE per real-cooldown -> ready transition. Alerts.lua's ticker consumes this.
function ItemMixin:ConsumeReadyTransition()
  if self:IsOnRealCooldown() then
    self._wasOnRealCD = true
    return false
  end
  if self._wasOnRealCD then
    self._wasOnRealCD = false
    return true
  end
  return false
end

-- Fire everything assigned to this spell's "ability is ready" event: the visual alert flash and the
-- ready sound. Called once per transition by the alert ticker, which owns the edge detection.
--
-- Self-gating: both halves no-op unless the player assigned something, so an unconfigured spell
-- costs two table lookups and makes no sound.
function ItemMixin:FireReadyAlerts()
  local key = self:GetSettingsKey()
  if not key then return end
  if M.alerts and M.alerts.OnAvailable then
    M.alerts.OnAvailable(self)
  end
  if M.GetReadySoundKit and M.PlayReadySound then
    local kit = M.GetReadySoundKit(key)
    if kit then M.PlayReadySound(kit) end
  end
end

-- The id every per-spell PREFERENCE is stored under. See the note in SetSpell: never use
-- `spellID` for this, it tracks the learned rank and moves.
function ItemMixin:GetSettingsKey()
  return self._baseSpellID or self.spellID
end

-- ── Tooltip ─────────────────────────────────────────────────────────────────────────────────────
-- DOWNPORT: 3.3.5a GameTooltip has no SetSpellByID. !!!ClassicAPI adds SetItemByID (WidgetAPI.lua)
-- but not the spell equivalent, so we fall back to the spell hyperlink, which 3.3.5a does support.
local function tooltipSetSpell(tip, spellID)
  if tip.SetSpellByID then
    local ok = pcall(tip.SetSpellByID, tip, spellID)
    if ok then return true end
  end
  return pcall(tip.SetHyperlink, tip, "spell:" .. spellID)
end
M.TooltipSetSpell = tooltipSetSpell   -- reused by the aura item mixins (AuraItemMixins.lua)

-- The same thing, with the row's own name as a floor.
--
-- `SetHyperlink` on an id this client cannot resolve does not error — it SUCCEEDS and leaves the
-- tooltip empty, so the pcall above returning true is not evidence that anything was drawn. Aura
-- rows hit that constantly: the catalog stores rank-1 ids straight from Spell.dbc and plenty of
-- aura-only ids have no linkable spell behind them. The result is a tile whose tooltip reads
-- "Lasts 30 sec" under no name at all, which on a 38px icon grid leaves nothing to identify it by.
--
-- The caller always knows a name — the catalog and the seen registry both store one, precisely
-- because GetSpellInfo cannot be relied on here — so it becomes the title when the client has
-- nothing. NumLines is the test rather than the pcall's word for it, and ClearLines is what makes
-- that number mean "this hover", not "whatever was up last".
function M.TooltipSetSpellNamed(tip, spellID, name)
  if tip.ClearLines then tip:ClearLines() end
  if spellID then tooltipSetSpell(tip, spellID) end
  if tip.NumLines and tip:NumLines() > 0 then return true end
  if name and name ~= "" then
    tip:AddLine(name, 1, 1, 1)
    return true
  end
  return false
end

-- Shared icon-crop helper: what stands in for the removed rounded MaskTexture.
function M.CropIcon(tex)
  if not tex then return end
  if NE.tex and NE.tex.CropIcon then
    NE.tex.CropIcon(tex)
  elseif tex.SetTexCoord then
    tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  end
end

-- The other half of what the removed MaskTexture did, and the half that was missed.
--
-- Retail anchors the Icon with setAllPoints and masks it with 6707800. That mask is easy to think of
-- as "rounds the corners", but decoding it shows it does TWO things: its outer 3px of 64 are FULLY
-- TRANSPARENT, so it also insets the icon by 3/64 = 4.7% on every side, and only then rounds what is
-- left with a corner radius of 4/64.
--
-- Dropping the mask therefore dropped the inset, and the inset is the part that matters here. The
-- numbers, for a 50px Essential tile:
--
--   IconOverlay's crisp border line falls at item x 4.05 .. 45.56 (the art's line is at 14-19 and
--     67-71 of an 86px cell, mapped through the -9/+8 outward anchor)
--   a MASKED icon spans 2.34 .. 47.66, so the frame overlaps its edge by ~1.7px — a frame sitting on
--     the icon, which is what retail looks like
--   an UNMASKED icon spans 0 .. 50, so it overshoots the border line by ~4px on every side and lands
--     out in the soft halo instead
--
-- Four pixels does not sound like much, but it is the whole difference between "framed" and "too big
-- for its frame", which is how it was reported. The corner rounding we still cannot reproduce, and it
-- turns out not to matter much: at radius 4/64 a square corner overshoots the arc by only
-- 4*(1-1/sqrt2) = 1.17px of 64, under a pixel on a real tile.
--
-- iconSize is applied with SetScale (Viewers.lua), not SetSize, so a fixed pixel inset computed from
-- the tile's authored size stays correct at every size setting.
--
-- The mask's edge is HARD, incidentally: texels 3..60 of 64 at alpha 255, the rest at 0, no
-- antialiasing. So 3/64 is exact rather than a reading off a ramp.
M.ICON_MASK_INSET = 3 / 64

-- One further pixel, and this one is a JUDGEMENT rather than a derivation — kept separate so the two
-- are not confused.
--
-- The mask inset alone is faithful, and still reads a pixel too big, for two compounding reasons.
-- First, the overlay is anchored +-9 horizontally but +-8 vertically, so its border line falls at a
-- different tile offset per axis; the mask is square, so on the VERTICAL axis the icon's edge lands
-- just outside the border band on Essential, Utility and the bar's icon (2.34 against a band of
-- 2.74..6.58 on Essential). Second, our icon has square corners where retail's is rounded, so its
-- edge reads harder against the same soft border.
--
-- FRACTIONAL, not flat pixels: the frame art scales with the tile, so a flat budget generous enough
-- for a 50px Essential tile pushes a 30px Utility icon clean through its own opening.
--
-- And it defaults to ZERO, which is the correction that matters, because the relationship runs the
-- OPPOSITE way to how three rounds of this assumed. Rendering the overlay cell shows what it actually
-- is: an INNER SHADOW, black, peaking at alpha 108/255 — 42% — with its dark core on a line at art
-- x=14 of 86 and a corner radius of about 4 art px.
--
-- An inner shadow has to fall ON something to be seen. Inset the icon and the shadow's core slides
-- off it onto empty space, where black-at-42%-over-the-world is nothing at all. So every step of
-- "make the icon smaller so it fits its frame" was quietly DELETING the frame, which is exactly how
-- the last pass ended: at +4% the whole dark core sat off the icon, and the report came back as "it
-- looks like the icon border is missing".
--
--   essential (50px, -9/+8): shadow core at item x 2.07;  mask inset alone puts the icon edge at 2.34
--   utility   (30px, -6/+5): core at 0.84;  mask inset 1.41
--
-- Retail's masked icon sits at 2.34 with the band running out to 6.02, so almost all of the shadow
-- lands on the icon. That is the look, and 0 extra reproduces it. The slider still exists — "too
-- large" was reported three times and a square corner does read bigger than a rounded one — but it
-- now carries a real cost, and MAX is the point past which the dark core leaves the icon entirely.
--
-- The rounding itself is answered by FRAME STRENGTH below, not by this.
M.ICON_INSET_EXTRA     = 0   -- percent of the tile edge, on top of the derived mask inset
M.ICON_INSET_EXTRA_MAX = 4   -- past this the shadow's core slides off the icon and the frame fades

function M.GetIconInsetExtra()
  local cd = M._store and M._store(false)
  local v = cd and cd.iconInset
  if type(v) ~= "number" then return M.ICON_INSET_EXTRA end
  if v < 0 then return 0 end
  if v > M.ICON_INSET_EXTRA_MAX then return M.ICON_INSET_EXTRA_MAX end
  return v
end

-- ── Frame strength ──────────────────────────────────────────────────────────────────────────────
-- The other half of "the border is missing", and the half that answers "no rounded edges" too.
--
-- The frame art tops out at 42% black. On a bright icon over a dark world that is a soft bevel, not a
-- border, and its rounded corners are far too faint to make a square icon read as a rounded one. We
-- cannot raise a texture's alpha — SetAlpha only scales down — but we CAN draw it more than once:
-- stacking N copies gives 1-(1-a)^N, so 42% becomes 66% at two and 80% at three. Same art, same rect,
-- same corner radius, just deeper. The corners darken with it, which is what makes the square icon
-- underneath stop announcing itself.
--
-- Two by default: enough to read as a frame at a glance, short of the heavy vignette three gives.
M.FRAME_STRENGTH     = 2
M.FRAME_STRENGTH_MAX = 3

function M.GetFrameStrength()
  local cd = M._store and M._store(false)
  local v = cd and cd.frameStrength
  if type(v) ~= "number" then return M.FRAME_STRENGTH end
  if v < 1 then return 1 end
  if v > M.FRAME_STRENGTH_MAX then return M.FRAME_STRENGTH_MAX end
  return math.floor(v)
end

-- Build the extra copies for one tile. Registered so the setting can be applied live, the same way
-- the inset is — and for the same reason: these are created once, at tile construction.
function M.BuildFrameStack(parent, ox, oy)
  if not (parent and parent.IconOverlay) then return end
  local stack = {}
  for i = 1, M.FRAME_STRENGTH_MAX - 1 do
    local t = parent:CreateTexture(nil, "OVERLAY")
    t:SetPoint("TOPLEFT", parent, "TOPLEFT", -ox, oy)
    t:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", ox, -oy)
    t:SetDrawLayer("OVERLAY", i)
    t:Hide()
    stack[i] = t
  end
  parent.IconOverlayStack = stack
  M._frameStacks = M._frameStacks or {}
  M._frameStacks[#M._frameStacks + 1] = parent
  M.ApplyFrameStrength(parent)
  return stack
end

function M.ApplyFrameStrength(parent)
  local stack = parent and parent.IconOverlayStack
  if not stack then return end
  local extra = M.GetFrameStrength() - 1
  for i = 1, #stack do
    if i <= extra then stack[i]:Show() else stack[i]:Hide() end
  end
end

function M.RefreshFrameStrength()
  for _, parent in ipairs(M._frameStacks or {}) do M.ApplyFrameStrength(parent) end
end

function M.SetFrameStrength(v)
  local cd = M._store and M._store(true)
  if cd then cd.frameStrength = tonumber(v) or M.FRAME_STRENGTH end
  M.RefreshFrameStrength()
end

function M.SetIconInsetExtra(v)
  local cd = M._store and M._store(true)
  if cd then cd.iconInset = tonumber(v) or M.ICON_INSET_EXTRA end
  M.ReanchorIcons()
end

-- SNAPPED TO WHOLE PIXELS, and this is not tidiness — it is the fix for a real, asymmetric artefact.
--
-- The derived inset is fractional: 50 x 3/64 = 2.34375 on an Essential tile. Anchored at that, the
-- icon's left edge lands at 2.34 and its right edge at 50 - 2.34 = 47.66, and the renderer resolves
-- each to a whole pixel independently — 2 on one side, 48 on the other. The two margins then differ
-- by a pixel, against a frame whose own anchors (+-9/+-8) are integers. That is what shows as a
-- sliver of icon art escaping on one side and not the other, and as the cooldown sweep covering the
-- glow on the right but not the left: the sweep shares the icon's rect exactly, so it inherits the
-- same split, and half a pixel is the whole difference between "covers" and "doesn't".
--
-- It reads like a mask artefact and it is not. Retail's mask does not centre anything; it clips an
-- icon that was already anchored on whole pixels. Snapping here is what we lost, not the rounding.
--
-- Deliberately whole pixels rather than "whole pixels at the current UI scale": iconSize is applied
-- with SetScale, so a tile can sit at a fractional scale anyway, and chasing that would need the
-- effective scale at anchor time and a re-anchor on every scale change. At scale 1 — the default, and
-- where this was reported — integer offsets land on integer pixels on both sides.
function M.IconInset(size)
  local px = (size or 0) * (M.ICON_MASK_INSET + M.GetIconInsetExtra() / 100)
  return math.floor(px + 0.5)
end

-- The frame's opening, in tile pixels, on the axis whose outward overhang is `o`. The ceiling for any
-- inset: past this the icon no longer touches the frame at all.
function M.IconAperture(size, o)
  local ext = (size or 0) + 2 * (o or 0)
  return -o + 20 * ext / 86
end

-- Anchor a region to the visible ICON's rect. Used for the icon itself and for everything drawn over
-- it: on this client the cooldown sweep, the out-of-range shade and the ready flash are all
-- unshaped substitutes, so any of them anchored to the TILE would sit proud of the icon by the inset
-- above and betray the old, larger footprint. Retail can anchor them to the tile because its swipe
-- and shadow are themselves rounded art.
function M.AnchorMaskedIcon(region, parent, size)
  if not (region and parent) then return end
  local pad = M.IconInset(size)
  region:ClearAllPoints()
  region:SetPoint("TOPLEFT", parent, "TOPLEFT", pad, -pad)
  region:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", -pad, pad)
  -- Remember every anchoring, so the inset can be re-applied live. These anchors are set ONCE at tile
  -- construction; without this, moving the slider would change nothing until the next login, which is
  -- not a slider anyone can use.
  --
  -- A flat list rather than a field on the parent, because the parent is not always a pooled tile:
  -- the BuffBar row anchors its icon to a NESTED frame (BuffViewers.lua:84), which walking
  -- viewer.items would never reach. Tiles are pooled and never destroyed, so this only ever grows to
  -- the size of the pool.
  M._insetAnchors = M._insetAnchors or {}
  local list = M._insetAnchors
  for i = 1, #list do
    if list[i][1] == region then return pad end   -- re-anchoring an already-tracked region
  end
  list[#list + 1] = { region, parent, size }
  return pad
end

-- Re-apply the inset to every region already anchored, in all four viewers.
function M.ReanchorIcons()
  for _, a in ipairs(M._insetAnchors or {}) do
    M.AnchorMaskedIcon(a[1], a[2], a[3])
  end
end

-- ── BuffBar background: a horizontal 3-slice ────────────────────────────────────────────────────
--
-- Bar-BG is 132x19 and gets anchored to a region 6px wider than the bar (retail's own -2/+4), so at
-- the 100% bar width it stretches 1.47x horizontally and at the 200% end of the width slider it
-- stretches 3.1x. Its interior survives that — cols 8..120 are dead uniform, black at alpha 173 —
-- but the two 1px light edge lines at x=1 and x=126 do not: they smear to 3px and the bar loses its
-- edge. Reading the cell's columns gives the cut points, and they are unambiguous:
--
--   x=0..7    alpha 96, 253, 235, 220, 188, 179, 174, 173 — the left cap, with its edge line at x=1
--   x=8..120  alpha 173 flat, luminance 0 — uniform, safe to stretch by any factor
--   x=121..131 alpha 179..253 (edge line at x=126) then 172, 90, 35, 11, 5 — cap plus drop shadow
--
-- The right cap is wider than the left because the art carries a shadow down and to the right; that
-- asymmetry is also why the anchors are -2/+2 and +4/-7 rather than symmetric.
--
-- HORIZONTAL ONLY. There is no flat band vertically — rows 3..11 run 209, 185, 165, 153, 153, 160,
-- 173, 194, 228, a continuous bevel — so the vertical axis has nothing to slice and every piece
-- stretches down the same 1.47x it always has. A nine-slice here would be inventing a seam.
M.BARBG_NATIVE_W  = 132
M.BARBG_NATIVE_H  = 19
M.BARBG_CAP_LEFT  = 8
M.BARBG_CAP_RIGHT = 11

-- The region's inset from the bar, retail's own numbers (CooldownViewer.xml:307-311). Asymmetric
-- because the shadow falls down and to the right.
M.BARBG_PAD_L, M.BARBG_PAD_T = -2,  2
M.BARBG_PAD_R, M.BARBG_PAD_B =  4, -7

-- THREE TEXTURES ON THE BAR, not a child frame holding them. A child frame draws above EVERY layer
-- of its parent, so a Frame-based group would put the background over the fill, the pip and the
-- name — the same rule that hid the buff glow under the cooldown sweep in §H.2.8. Textures on the
-- bar itself sit at BACKGROUND and stay there.
--
-- Caps scale with the region's HEIGHT, not its width. The vertical stretch is a constant 28/19
-- whatever the bar width, so scaling the caps by it keeps the corner bevel uniformly scaled instead
-- of squashing it into an ellipse — the flat middle absorbs all the extra width, which is the whole
-- point of slicing.
local function barBGCapScale(bg)
  local bar = bg and bg.bar
  local h = bar and bar:GetHeight() or 0
  if h <= 0 then return 1 end
  return (h + M.BARBG_PAD_T - M.BARBG_PAD_B) / M.BARBG_NATIVE_H
end

local function barBGWidth(bg)
  local bar = bg and bg.bar
  local w = bar and bar:GetWidth() or 0
  return w - M.BARBG_PAD_L + M.BARBG_PAD_R
end

-- The registry entry, or nil if 8a's registration ever goes missing (in which case the caller
-- leaves the pieces untextured rather than drawing three copies of the whole sheet).
local function barBGEntry()
  return NE.tex and NE.tex._atlasEntry and NE.tex._atlasEntry("UI-HUD-CoolDownManager-Bar-BG")
end

function M.ApplyBarBGAtlas(bg)
  if not (bg and bg.Left and bg.Middle and bg.Right and bg.bar) then return false end
  local rect = barBGEntry()
  if not rect then return false end
  local bar = bg.bar

  local u = function(x) return rect.left + (rect.right - rect.left) * (x / M.BARBG_NATIVE_W) end
  local l, r = M.BARBG_CAP_LEFT, M.BARBG_NATIVE_W - M.BARBG_CAP_RIGHT

  local scale = barBGCapScale(bg)
  local leftW, rightW = M.BARBG_CAP_LEFT * scale, M.BARBG_CAP_RIGHT * scale

  bg.Left:ClearAllPoints()
  bg.Left:SetPoint("TOPLEFT",    bar, "TOPLEFT",    M.BARBG_PAD_L, M.BARBG_PAD_T)
  bg.Left:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", M.BARBG_PAD_L, M.BARBG_PAD_B)

  -- A bar narrow enough that the caps would overlap has no middle to speak of; fall back to the
  -- plain single stretch rather than drawing the two caps over each other.
  --
  -- A width of ZERO is not that case. The bar takes its width from its anchors, which the client has
  -- not resolved when the row is built, so the first call here reads 0 — and treating that as "too
  -- narrow" would collapse every row to a single stretch and leave it there until something happened
  -- to resize it. Unresolved is not narrow; slice, and let the first real OnSizeChanged re-measure.
  --
  -- The test is the BAR's own width, not the padded region's: the padding is +6, so an unresolved
  -- bar still reports a 6px region and would sail past a `regionW > 0` guard into the fallback.
  local barW = bar:GetWidth() or 0
  if barW > 0 and leftW + rightW >= barBGWidth(bg) then
    bg.Left:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    M.BARBG_PAD_R, M.BARBG_PAD_T)
    bg.Left:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", M.BARBG_PAD_R, M.BARBG_PAD_B)
    bg.Left:SetTexCoord(rect.left, rect.right, rect.top, rect.bottom)
    bg.Middle:Hide(); bg.Right:Hide()
    return true
  end

  bg.Left:SetWidth(leftW)
  bg.Left:SetTexCoord(u(0), u(l), rect.top, rect.bottom)

  bg.Right:ClearAllPoints()
  bg.Right:SetPoint("TOPRIGHT",    bar, "TOPRIGHT",    M.BARBG_PAD_R, M.BARBG_PAD_T)
  bg.Right:SetPoint("BOTTOMRIGHT", bar, "BOTTOMRIGHT", M.BARBG_PAD_R, M.BARBG_PAD_B)
  bg.Right:SetWidth(rightW)
  bg.Right:SetTexCoord(u(r), u(M.BARBG_NATIVE_W), rect.top, rect.bottom)

  bg.Middle:ClearAllPoints()
  bg.Middle:SetPoint("TOPLEFT",     bg.Left,  "TOPRIGHT",   0, 0)
  bg.Middle:SetPoint("BOTTOMRIGHT", bg.Right, "BOTTOMLEFT", 0, 0)
  bg.Middle:SetTexCoord(u(l), u(r), rect.top, rect.bottom)

  bg.Middle:Show(); bg.Right:Show()
  return true
end

-- Build the three pieces on the bar. Returns a plain table, not a frame — see above. It carries the
-- same key the single texture did, so AuraItemMixins keeps addressing it as `bar.BarBG`.
function M.BuildBarBG(bar)
  if not bar then return end
  local bg = { bar = bar }

  -- Prefer the shipped BLP over the raw FDID, the same order entrySource uses in core/Texture.lua.
  local rect   = barBGEntry()
  local source = rect and ((NE.tex.Local and NE.tex.Local(rect.file)) or rect.file)
  local function piece()
    local t = bar:CreateTexture(nil, "BACKGROUND")
    if source then t:SetTexture(source) end
    return t
  end

  bg.Left, bg.Middle, bg.Right = piece(), piece(), piece()

  M.ApplyBarBGAtlas(bg)
  -- The width slider re-sizes the row long after construction, and the caps are sized off the bar.
  -- HookScript chains, so this coexists with the fill overlay's own OnSizeChanged hook.
  bar:HookScript("OnSizeChanged", function() M.ApplyBarBGAtlas(bg) end)
  return bg
end

function ItemMixin:OnEnter()
  if self.tooltipsShown == false then return end
  if self._equipSlot then
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetInventoryItem("player", self._equipSlot)
    GameTooltip:Show()
    return
  end
  if self._bagItemID then
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    if GameTooltip.SetItemByID then
      GameTooltip:SetItemByID(self._bagItemID)
    else
      GameTooltip:SetHyperlink("item:" .. self._bagItemID)
    end
    GameTooltip:Show()
    return
  end
  if not self.spellID then return end
  GameTooltip:SetOwner(self, "ANCHOR_TOP")
  if M.TooltipSetSpellNamed(GameTooltip, self.spellID, self.spellName) then GameTooltip:Show() end
end

function ItemMixin:OnLeave()
  GameTooltip:Hide()
end
