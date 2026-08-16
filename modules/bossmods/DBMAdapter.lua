-- DragonUI_NewEra/modules/bossmods/DBMAdapter.lua — the DBM backend for the boss-timer renderers.
--
-- Downport of ReferenceAddons/NewEra/Alerts/BossMods/DBMAdapter.lua. It feeds the same internal bus
-- (BM.Bus*) the source did; Register.lua calls BM.RegisterWithDBM() at boot, gated on DBM being
-- installed at all.
--
-- ============================ CONTRACT (read off the INSTALLED DBM) ==========================
--
-- The source was written against DBM master (a 2026 retail/Classic core). This client runs the
-- WotLK 3.3.5a fork (AddOns/DBM-Core + AddOns/DBM-StatusBarTimers), which is compatible but
-- NARROWER, and differs in two ways that matter. Everything below was verified in that source,
-- not assumed from the upstream contract:
--
--   Mechanics — unchanged. DBM:RegisterCallback(event, fn) (DBM-Core.lua:1564), invoked
--   pcall(fn, event, ...) (:1540): the event name arrives FIRST, ahead of the payload.
--
--   DBM_TimerStart (DBM-Core.lua:10049)
--       id, msg, timer, icon, timerType, spellId, colorId, modId, keep, fade, name, guid
--     * The DBT bar is created FIRST, at :10007, and the callback only fires if that succeeded
--       (`if not bar then return false, "error" end`, :10008-10010). So the bar always exists by
--       the time we are told about the timer — which matters twice over: suppression can act
--       synchronously, and if DBT ever refuses to make a bar we hear nothing at all. See the
--       reaper below, which is what keeps DBT able to make one.
--     * DBM_TimerBegin — the modern rename the source registered FIRST — is never fired by this
--       fork. Registering both is still correct and free: one of them simply never arrives, and a
--       server running a newer core would send that one instead. Same id ⇒ the bus dedupes.
--     * The arg list STOPS at `guid`. timerCount / isPriority / fullType / hasVariance /
--       variancePeakTimer / isBarEnabled do not exist here, so they arrive nil — which is why both
--       guards below are written to degrade rather than assume: `isBarEnabled == false` is never
--       true (nothing is wrongly dropped) and `hasVariance` is never set (no bar is drawn as
--       approximate). Both stay, so a newer core is honoured the moment one appears.
--     * id is DBM's real timer id (unique per instance, target args appended) — our bus key.
--     * icon is a texture path or fileID; msg is pre-localized display text.
--   DBM_TimerStop (id[, guid]) · DBM_TimerPause (id) · DBM_TimerResume (id)
--   DBM_TimerUpdate (id, elapsed, totalTime) — re-baseline remaining/max.
--   DBM_Announce (message, icon, type, spellId, modId, isSpecial) — DBM-Core.lua:8183
--     (isSpecial=false, a regular announce) and :9259 (isSpecial=true, a special warning).
--   DBM_Wipe (mod) — DBM-Core.lua:5179. Belt-cancel any bars DBM did not stop itself.
--   DBM_Kill (mod) — DBM-Core.lua:5238. See the note on onKill: this addon has no boss banner.
--
-- ============================ SUPPRESSION (no double-draw) ===================================
--
-- DBM's own DontShow*/HideDBM* options CANNOT be used for this: every one of them early-returns
-- BEFORE the callback fires, which would starve our renderer of the very events it draws. So
-- suppress VISUALLY, session-only, with no SavedVariable writes — nothing to stash or restore.
--
-- DOWNPORT — the source's mechanism does not work on this fork, in two independent ways:
--   1. It reaches the bar anchor through `DBM.Bars`, which does not exist here. The bar library is
--      the GLOBAL `DBT` (DBM-StatusBarTimers/DBT.lua:43), with GetBarIterator at :605. Ported
--      verbatim, findDBTAnchor would return nil forever and every bar would be drawn twice.
--   2. It reaches the anchor through one live bar. Both anchors are unnamed locals created at
--      DBT.lua:179, so a bar IS the only handle — but every bar is created on smallBarsAnchor
--      (DBT.lua:249) and is never reparented; huge bars only re-POINT to the large anchor
--      (:663, :1120). Hiding the small anchor therefore hides every bar there is, and the
--      largeBarsAnchor this collects will in practice never have a child. It is collected anyway:
--      it costs one table entry, and a fork that did reparent would otherwise leak bars on screen.
-- The warning hosts DBMWarning (DBM-Core.lua:7812) and DBMSpecialWarning (:8849) do exist under
-- those exact global names, so those suppress exactly as the source wrote them.
--
-- Sounds and voice stay DBM's, deliberately: we replace what is DRAWN, not what is heard.

local NE = DragonUI_NewEra
local BM = NE.bossmods
if not BM then return end

local OWNER = {}   -- bus owner key for every DBM-fed bar
BM.DBM_OWNER = OWNER

-- ============================ Suppression =====================================================

local suppressed = {}   -- frame → "hide" | "alpha", so restoring undoes the right thing

-- TWO INSTRUMENTS, and which one is right depends on what DBM does to the frame afterwards.
--
--   HIDE, for the bar anchors. A hidden parent hides its children, unambiguously, on every client —
--     where a parent's ALPHA reaching its child frames is exactly the thing this client is unreliable
--     about (PORT_PLAN §C.5d). DBT shows its two anchors once at load (DBT.lua:184, :189) and never
--     again, so hiding them sticks, and a bar created later is born a child of an already-hidden
--     anchor and is invisible from its first frame with no polling.
--   HIDE + AN OnShow HOOK, for the warning hosts. Alpha was tried there first, on the reasoning that
--     DBM re-Shows them on every announce so hiding would flicker. It does not work: DBM drives
--     `font:SetAlpha(1)` on a 0.05s ticker (DBM-Core.lua:8036, :8878) and re-Shows the host, so an
--     alpha we set on the parent is either composed away or simply outrun — and DBM's warning ICONS
--     are inline |T..|t escapes INSIDE those font strings (DBM-Core.lua:8121-8127), which is why they
--     kept appearing beside our own. Hooking OnShow to re-hide is instant, so there is no frame of
--     flicker to trade for it.
local function setSuppressed(frame, on, how)
  if not frame then return end
  how = how or "alpha"
  if on then
    if how == "hide" then
      if frame:IsShown() then frame:Hide() end
    elseif frame:GetAlpha() > 0 then
      frame:SetAlpha(0)
    end
    suppressed[frame] = how
  elseif suppressed[frame] then
    -- CLEAR THE FLAG FIRST. The OnShow guard below reads it, so showing while it is still set means
    -- the guard hides the frame again in the same call and suppression can never be turned off.
    local was = suppressed[frame]
    suppressed[frame] = nil
    if was == "hide" then frame:Show() else frame:SetAlpha(1) end
  end
end

-- Every distinct frame DBT parents its bars to. Both anchors are unnamed locals (DBT.lua:179), so a
-- bar is the only handle we get to either of them.
--
-- PRIMARY ROUTE: the bar FRAMES are named globals — `CreateFrame("Frame", "DBT_Bar_"..n, anchor)`
-- (DBT.lua:249) — and a released bar keeps both its name and its parent, sitting in DBT's reuse pool.
-- So this finds the anchors with nothing LIVE, which the iterator cannot — a login, or any moment
-- between pulls, where every bar has been released back to that pool.
--
-- Cached across calls (anchors are created once and never replaced) and re-walked each time, so the
-- large anchor is picked up the first time a huge bar exists.
local dbtAnchors = {}
local MAX_BAR_SCAN = 200   -- belt: DBT numbers bars from 1 with no gaps, so this stops at the end

local function collectDBTAnchors()
  for i = 1, MAX_BAR_SCAN do
    local f = _G["DBT_Bar_" .. i]
    if not f then break end
    local ok, parent = pcall(f.GetParent, f)
    if ok and parent then dbtAnchors[parent] = true end
  end

  -- Fallback: the live iterator, for any bar frame that is not one of those globals.
  local dbt = _G.DBT
  if not (dbt and dbt.GetBarIterator) then return dbtAnchors end
  local ok, iter, state = pcall(dbt.GetBarIterator, dbt)
  if not ok or not iter then return dbtAnchors end
  pcall(function()
    for bar in iter, state do
      local p = bar and bar.frame and bar.frame.GetParent and bar.frame:GetParent()
      if p then dbtAnchors[p] = true end
    end
  end)
  return dbtAnchors
end

local function wantSuppression()
  if not BM.DBMPresent() then return false end
  if BM.IsSuppressionEnabled and not BM.IsSuppressionEnabled() then return false end
  return true
end

-- ============================ Keeping DBT's books while its bars are hidden ==================
--
-- Hiding the anchors is what makes DBM's bars invisible, and it also FREEZES them. A frame that is
-- not VISIBLE gets no OnUpdate, and every DBT bar's countdown IS its own OnUpdate — DBT.lua:251
-- installs it, and `barPrototype:Update` is where a bar both ticks down and dies:
--
--     self.timer = self.timer - (paused and 0 or elapsed)          -- DBT.lua (Update)
--     if timerValue <= 0 and not (barOptions.KeepBars and self.keep) then return self:Cancel() end
--
-- Nothing else ever expires a bar. There is no CancelAllBars anywhere in DBT, and DBM prunes an
-- expired timer from `startedTimers` on a schedule (DBM-Core.lua:10059-10061), so a mod's
-- combat-end Stop() does not reclaim it either. With the anchors hidden the consequences compound:
--
--     * DBT.numBars is decremented ONLY in Cancel (DBT.lua:969), so it never falls;
--     * DBT:CreateBar hard-returns once numBars >= 15 (DBT.lua:294);
--     * and DBM's Timer:Start bails on that BEFORE it fires anything —
--       `if not bar then return false, "error" end` (DBM-Core.lua:10008-10010), with the
--       fireEvent at :10049.
--
-- So after fifteen expired-but-unreaped timers DBM stops telling us about ANY timer and our own
-- rail goes blank for the session — with DBM's own timers broken alongside it. Suppressing DBM's
-- drawing must not stop DBM working.
--
-- What runs below is the accounting half of DBT's own update and nothing else: the elapsed
-- subtraction and the expiry test, against the same `lastUpdate` clock DBT itself uses, so DBT
-- picks up mid-stride the moment suppression is switched off. Everything skipped — the colour
-- lerp, SetStatusBarColor, SetValue, the timer text, the enlarge animation — is drawing work for a
-- frame nobody can see, which is also why this is CHEAPER than the alternative of parking the
-- anchors off screen and leaving DBT running: five arithmetic operations per bar at REAP_INTERVAL,
-- against DBT's full redraw at frame rate.
--
-- A VISIBLE bar is skipped outright. DBT is driving that one itself, and decrementing it here as
-- well would run it down at double speed.

local REAP_INTERVAL = 0.2
local reaper

local function reapFrozenDBTBars()
  local dbt = _G.DBT
  if not (dbt and dbt.GetBarIterator) then return end
  local ok, iter, state = pcall(dbt.GetBarIterator, dbt)
  if not ok or not iter then return end

  -- Snapshot first: Cancel() writes to DBT.bars, which is what we are iterating.
  local frozen, now = {}, GetTime()
  pcall(function()
    for bar in iter, state do
      local f = bar and bar.frame
      if f and f.IsVisible and not f:IsVisible() and not bar.dead
         and type(bar.timer) == "number" and type(bar.lastUpdate) == "number" then
        frozen[#frozen + 1] = bar
      end
    end
  end)

  local keepBars = dbt.Options and dbt.Options.KeepBars
  for _, bar in ipairs(frozen) do
    local elapsed = now - bar.lastUpdate
    if elapsed > 0 then
      bar.lastUpdate = now
      if not bar.paused then
        bar.timer = bar.timer - elapsed
        -- DBT's own condition, verbatim. `keep` bars are meant to sit at zero until an explicit
        -- stop, so reaping one would take a bar off DBM that DBM still thinks it has.
        if bar.timer <= 0 and not (keepBars and bar.keep) and bar.Cancel then
          pcall(bar.Cancel, bar)
        end
      end
    end
  end
end
BM.ReapFrozenDBTBars = reapFrozenDBTBars

-- The reaper's own driver. It cannot ride the module's OnUpdate: that lives on the timeline anchor,
-- which hides itself whenever there is nothing on the rail — precisely when DBT's leftovers need
-- clearing. One shown 1x1 frame, throttled, running only while we are actually suppressing.
local function setReaperRunning(on)
  if not on then
    if reaper then reaper:Hide() end
    return
  end
  if not reaper then
    reaper = CreateFrame("Frame", nil, UIParent)
    reaper:SetSize(1, 1)
    reaper:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 0, 0)
    reaper._acc = 0
    reaper:SetScript("OnUpdate", function(self, elapsed)
      self._acc = self._acc + (elapsed or 0)
      if self._acc < REAP_INTERVAL then return end
      self._acc = 0
      reapFrozenDBTBars()
    end)
  end
  reaper:Show()
end

-- Re-evaluate the whole suppression state (boot + option toggle + per-event re-assert).
function BM.ApplyDBMSuppression()
  local Mods = NE.modules
  local booted = Mods and Mods.IsBooted
  local barsOn     = wantSuppression() and booted and Mods.IsBooted("bossmods") or false
  local warningsOn = wantSuppression() and booted and Mods.IsBooted("bossmods_warnings") or false

  for frame in pairs(collectDBTAnchors()) do
    setSuppressed(frame, barsOn, "hide")
  end
  -- DBM builds its warning hosts lazily, so the hook is (re)tried here rather than only at boot.
  BM.HookDBMWarningHost(_G.DBMWarning)
  BM.HookDBMWarningHost(_G.DBMSpecialWarning)
  setSuppressed(_G.DBMWarning, warningsOn, "hide")
  setSuppressed(_G.DBMSpecialWarning, warningsOn, "hide")

  -- Hidden bars do not expire themselves; while we are hiding them, we do it for them. The ticker
  -- is the whole mechanism — there is deliberately no extra pass here. Reaping from inside a
  -- callback would only ever run AFTER DBM had already tried to make its bar (DBM-Core.lua:10007),
  -- so it could not free the slot that call needed; the point is to have the slots free already.
  setReaperRunning(barsOn)
end

-- DBM shows its warning hosts itself on every announce, so hiding one is only half the job: without
-- this it would reappear and stay up until the next DBM event. The hook re-hides it in the same
-- frame it is shown, and is installed once per frame object.
--
-- HookScript, never SetScript: DBM owns these frames and may have its own OnShow. Hooking adds ours
-- after theirs and takes nothing away.
local hooked = {}
function BM.HookDBMWarningHost(frame)
  if not frame or hooked[frame] or not frame.HookScript then return end
  hooked[frame] = true
  frame:HookScript("OnShow", function(self)
    if suppressed[self] then self:Hide() end
  end)
end

-- Hand every suppressed frame back before we stop asserting (module turned off mid-session).
function BM.ClearDBMSuppression()
  -- Nothing is frozen once the anchors are back, so DBT drives its own bars again.
  setReaperRunning(false)
  -- Snapshot and clear BEFORE restoring, for the reason setSuppressed records: the OnShow guard
  -- reads `suppressed`, so a Show() with the flag still set is undone the instant it happens.
  local pending = {}
  for frame, how in pairs(suppressed) do pending[frame] = how end
  wipe(suppressed)
  for frame, how in pairs(pending) do
    if how == "hide" then frame:Show() else frame:SetAlpha(1) end
  end
end

-- ============================ Callback handlers ===============================================

local function onTimerStart(_, id, msg, timer, icon, _timerType, spellId, _colorId, _modId,
                            _keep, _fade, name, _guid, _timerCount, _isPriority, _fullType,
                            hasVariance, variancePeakTimer, isBarEnabled)
  if id == nil or type(timer) ~= "number" or timer <= 0 then return end
  if isBarEnabled == false then return end   -- user disabled this timer in DBM (modern cores only)
  BM.BusStartBar(OWNER, id, msg or name or tostring(id), timer, icon,
                 hasVariance and true or false,
                 hasVariance and tonumber(variancePeakTimer) or nil,
                 -- spellId feeds the hover tooltip. DBM raises plenty of timers that are not a spell
                 -- at all (pull timers, phase timers), so it is frequently nil and the tooltip falls
                 -- back to the ability's own label.
                 tonumber(spellId))
end

local function onTimerStop(_, id)   BM.BusStopBar(OWNER, id) end
local function onTimerPause(_, id)  BM.BusPauseBar(OWNER, id) end
local function onTimerResume(_, id) BM.BusResumeBar(OWNER, id) end
local function onTimerUpdate(_, id, elapsed, totalTime) BM.BusUpdateBar(OWNER, id, elapsed, totalTime) end

local function onAnnounce(_, message, icon, announceType, _spellId, _modId, isSpecial)
  if not message then return end
  if BM.ShowWarningFromDBM then BM.ShowWarningFromDBM(isSpecial, message, icon, announceType) end
end

-- Boss kill. DOWNPORT: the source routed this to NE.alerts.BossBanner_Play — retail's kill banner,
-- which lives in NewEra's Alerts module. This addon has no Alerts module and no NE_BossBanner
-- frame, and DBM ships its own banner toast (DBM-BossBannerToast.lua) regardless. The routing is
-- kept, guarded on the frame existing, so porting a banner later needs no change here.
local function onKill(_, mod)
  local A = NE.alerts
  if not (A and A.BossBanner_Play and _G.NE_BossBanner) then return end
  if A.IsBossBannerEnabled and not A.IsBossBannerEnabled() then return end
  local name = (mod and mod.combatInfo and mod.combatInfo.name) or "Boss"
  A.BossBanner_Play(_G.NE_BossBanner, { name = name })
end

-- Wipe → belt: cancel anything DBM did not stop per-timer. mod:Stop() usually fires DBM_TimerStop
-- for each started timer, but the belt keeps us clean if one is missed.
local function onWipe(_, _mod)
  BM.BusStopAll(OWNER)
end

-- ============================ Registration ====================================================

function BM.RegisterWithDBM()
  local dbm = _G.DBM
  if not (dbm and type(dbm.RegisterCallback) == "function") or BM._dbmRegistered then return end
  BM._dbmRegistered = true

  -- `heard` doubles as the suppression re-assert tick: DBM never recreates its warning hosts, and
  -- DBT creates its anchors once at load (DBT.lua:179), so a cheap re-apply per event self-heals
  -- the moment either becomes reachable.
  --
  -- ONE PASS, synchronously, is enough — and this is a correction. An earlier build ran a second,
  -- zero-delay pass on the belief that our callback runs before DBM creates the bar, so the first
  -- timer of a session had nothing to find. The order is the other way round: DBT:CreateBar is at
  -- DBM-Core.lua:10007 and the fireEvent that reaches us is at :10049, with an early return in
  -- between if the bar could not be made. The bar — and therefore its anchor, and therefore the
  -- DBT_Bar_N global we discover it through — always exists by the time we are called.
  local function heard(fn)
    return function(...)
      BM._lastBusActivity = GetTime()
      if wantSuppression() then BM.ApplyDBMSuppression() end
      return fn(...)
    end
  end

  -- Install the OnShow guards before the first announce can arrive.
  BM.HookDBMWarningHost(_G.DBMWarning)
  BM.HookDBMWarningHost(_G.DBMSpecialWarning)

  dbm:RegisterCallback("DBM_TimerStart",  heard(onTimerStart))
  dbm:RegisterCallback("DBM_TimerBegin",  heard(onTimerStart))   -- newer cores fire this name instead
  dbm:RegisterCallback("DBM_TimerStop",   heard(onTimerStop))
  dbm:RegisterCallback("DBM_TimerPause",  heard(onTimerPause))
  dbm:RegisterCallback("DBM_TimerResume", heard(onTimerResume))
  dbm:RegisterCallback("DBM_TimerUpdate", heard(onTimerUpdate))
  dbm:RegisterCallback("DBM_Announce",    heard(onAnnounce))
  dbm:RegisterCallback("DBM_Kill",        heard(onKill))
  dbm:RegisterCallback("DBM_Wipe",        heard(onWipe))

  if NE.Log then NE.Log("BOSSMODS", "DBM backend registered (timers/warnings feed the New Era frames).") end
end

-- Test feed for /nebossmods test — drives the real render path with the real bus, so what it shows
-- is exactly what a DBM timer would show. Register.lua owns the slash command.
function BM.RunTestFeed()
  local TEST = {
    { "Shadow Bolt Volley",  8, "Interface\\Icons\\Spell_Shadow_ShadowBolt" },
    { "Cleave",             14, "Interface\\Icons\\Ability_Warrior_Cleave" },
    { "Enrage",             22, "Interface\\Icons\\Ability_Warrior_Charge" },
    { "Berserk",            40, "Interface\\Icons\\Spell_Shadow_UnholyFrenzy" },
  }
  local owner = BM._testOwner or {}
  BM._testOwner = owner
  BM.BusStopAll(owner)
  for i, e in ipairs(TEST) do
    BM.BusStartBar(owner, i, e[1], e[2], e[3], false, nil)
  end
  if BM.ShowWarningFromDBM then
    BM.ShowWarningFromDBM(true, "Shadow Bolt Volley incoming!", "Interface\\Icons\\Spell_Shadow_ShadowBolt", nil)
  end
end
