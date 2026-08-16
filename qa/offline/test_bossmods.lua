-- qa/offline/test_bossmods.lua — offline harness for the boss timers (modules/bossmods).
--
--   luajit qa/offline/test_bossmods.lua        (from the addon root)
--
-- This module cannot be exercised any other way without standing in front of a raid boss, and the
-- downport made several non-obvious deviations from the 1.15 source that a syntax check cannot see:
-- the DBM callback surface differs on the 3.3.5a fork, MaskTexture and Animation:SetTarget are both
-- absent, and the suppression mechanism was rewritten around the global DBT and its TWO unnamed bar
-- anchors. Each of those has an assertion here.
--
-- The fake DBM below is modelled on the INSTALLED core (AddOns/DBM-Core, AddOns/DBM-StatusBarTimers),
-- not on DBM master: it fires DBM_TimerStart (never DBM_TimerBegin), its payload stops at `guid`,
-- and its bars live on two anchors, one of which does not exist until a huge bar is created.

local ADDON = (arg and arg[0] or ""):match("^(.*)qa/offline/[^/]+$") or "./"

-- Reported through the REAL print, since the addon's own print is stubbed out below to capture
-- what the slash command emits.
local report = print

local failures, checks = 0, 0
local function check(label, ok, detail)
  checks = checks + 1
  if ok then
    report("  ok   " .. label)
  else
    failures = failures + 1
    report("  FAIL " .. label .. (detail and ("  -- " .. tostring(detail)) or ""))
  end
end
local function section(name) report("\n=== " .. name .. " ===") end

-- ── clock ───────────────────────────────────────────────────────────────────────────────────────
local NOW = 1000.0
function GetTime() return NOW end
local function advance(dt) NOW = NOW + (dt or 0.1) end

-- ── widget stubs ────────────────────────────────────────────────────────────────────────────────
--
-- Deliberately NOT stubbed: SetShown, CreateMaskTexture, AddMaskTexture and Animation:SetTarget.
-- All four are absent on 3.3.5a, so leaving them out means any regression that reintroduces one
-- fails here as a nil call rather than silently doing nothing in game.

local function newRegion(kind, layer, sublevel)
  local r = { _kind = kind, _shown = true, _alpha = 1, _layer = layer, _sublevel = sublevel or 0,
              _points = {}, _animGroups = {} }
  function r:SetTexture(t) self._tex = t; self._coords = nil end
  function r:GetTexture() return self._tex end
  function r:SetTexCoord(...) self._coords = { ... } end
  function r:GetTexCoord() local c = self._coords; if not c then return nil end return unpack(c) end
  function r:SetColorTexture(...) self._color = { ... }; self._tex = "COLOR" end
  function r:SetVertexColor(...) self._vertex = { ... } end
  function r:GetVertexColor() local c = self._vertex or {1,1,1,1}; return c[1], c[2], c[3], c[4] end
  function r:SetBlendMode(m) self._blend = m end
  function r:GetBlendMode() return self._blend or "BLEND" end
  function r:SetDrawLayer(l, s) self._layer, self._sublevel = l, s end
  function r:GetDrawLayer() return self._layer, self._sublevel end
  function r:Show() self._shown = true end
  function r:Hide() self._shown = false end
  function r:IsShown() return self._shown end
  function r:SetAlpha(a) self._alpha = a end
  function r:GetAlpha() return self._alpha end
  function r:SetSize(w, h) self._w, self._h = w, h end
  function r:SetWidth(w) self._w = w end
  function r:SetHeight(h) self._h = h end
  function r:GetWidth() return self._w or 0 end
  function r:GetHeight() return self._h or 0 end
  function r:SetPoint(p, rel, relP, x, y) self._points[#self._points+1] = { p, rel, relP, x, y } end
  function r:SetAllPoints(rel) self._points[#self._points+1] = { "ALL", rel } end
  function r:ClearAllPoints() self._points = {} end
  function r:GetNumPoints() return #self._points end
  function r:GetPoint(i) local pt = self._points[i or 1]; if not pt then return nil end
    return pt[1], pt[2], pt[3], pt[4], pt[5] end
  -- FontString surface.
  function r:SetText(t) self._text = t end
  function r:GetText() return self._text end
  function r:SetFont(path, size, flags) self._font = { path, size, flags }; return true end
  function r:SetFontObject(o) self._fontObject = o end
  function r:SetTextColor(...) self._textColor = { ... } end
  function r:SetShadowColor(...) self._shadowColor = { ... } end
  function r:SetShadowOffset(x, y) self._shadowOffset = { x, y } end
  function r:SetJustifyH(v) self._jh = v end
  function r:SetJustifyV(v) self._jv = v end
  function r:SetWordWrap(v) self._wrap = v end
  function r:GetObjectType() return kind end
  -- Textures own AnimationGroups on this client, which is the whole substitution for SetTarget.
  function r:CreateAnimationGroup() return newAnimGroup(self) end
  return r
end

function newAnimGroup(owner)
  local ag = { _anims = {}, _playing = false, _owner = owner, _scripts = {} }
  function ag:SetLooping(m) self._loop = m end
  function ag:GetLooping() return self._loop end
  function ag:SetToFinalAlpha(v) self._toFinal = v end
  function ag:Play() self._playing = true end
  -- MODELS A REAL CLIENT CRASH. Calling Stop() on an AnimationGroup from inside that group's own
  -- OnFinished is an ACCESS_VIOLATION on 3.3.5a — ERROR #132, 0xC0000005 reading 0x00000034,
  -- reported as `Current Addon function: <unnamed>:Stop`. The 1.15 source does exactly that on its
  -- release path, so the downport walked into it and the client died on the first finished bar.
  -- Raising here is what makes that a test failure instead of a crash report.
  function ag:Stop()
    if self._inFinished then
      error("AnimationGroup:Stop() from inside its own OnFinished — ACCESS_VIOLATION on 3.3.5a", 2)
    end
    self._playing = false
  end
  function ag:IsPlaying() return self._playing end
  function ag:SetScript(name, fn) self._scripts[name] = fn end
  function ag:GetScript(name) return self._scripts[name] end
  -- Test-only: run the group to completion, as the client would — including the state that makes
  -- a re-entrant Stop detectable.
  --
  -- MODELS THE SECOND REAL FAULT. On 3.3.5a an alpha animation does NOT leave its region at the
  -- `to` value, and SetToFinalAlpha (which would say otherwise) does not exist — confirmed live by
  -- a `/nebossmods debug` dump reporting every faded-in region as `alpha=0.00` while shown,
  -- textured and correctly anchored. Reproduced here by dropping the region back to the
  -- animation's `from` BEFORE OnFinished runs, so only code that sets its own end state survives.
  -- Anything that trusts the animation ends invisible, exactly as it did in game.
  --
  -- It also writes that alpha DOWN INTO CHILD FRAMES and leaves them there. On 3.3.5a alpha is not
  -- inherited at render time — each frame owns its own — so restoring the parent restores only the
  -- parent. Confirmed live after the first fix: `track: alpha=1.00` with `cont: alpha=0.00` and
  -- `cdHost: alpha=0.00`, which is why a texture on the track drew while its child frames did not.
  function ag:Finish()
    self._playing = false
    if self._owner and self._owner.SetAlpha then
      for _, a in ipairs(self._anims) do
        if a._kind == "Alpha" and a._from then
          self._owner:SetAlpha(a._from)
          for _, kid in ipairs(self._owner._children or {}) do kid:SetAlpha(a._from) end
        end
      end
    end
    local fn = self._scripts.OnFinished
    if not fn then return end
    self._inFinished = true
    local ok, err = pcall(fn, self)
    self._inFinished = false
    if not ok then error(err, 0) end
  end
  function ag:CreateAnimation(kind)
    local a = { _kind = kind }
    function a:SetDuration(d)   self._dur = d end
    function a:SetOrder(o)      self._order = o end
    function a:SetSmoothing(s)  self._smooth = s end
    function a:SetStartDelay(d) self._delay = d end
    function a:SetEndDelay(d)   self._endDelay = d end
    function a:SetFromAlpha(v)  self._from = v end
    function a:SetToAlpha(v)    self._to = v end
    function a:SetOffset(x, y)  self._offset = { x, y } end
    function a:SetDegrees(d)    self._degrees = d end
    function a:SetOrigin(p, x, y) self._origin = { p, x, y } end
    -- The NATIVE 3.3.5a scale setter, and the only one stubbed: SetScaleFrom/SetScaleTo are
    -- ClassicAPI polyfills that forward (to - from) into this, which would turn retail's 1 -> 1.1
    -- pop into a 90% shrink. BM.ScaleAnim is written to call this directly; if it ever goes back
    -- to the polyfill pair, this harness fails on a nil call.
    function a:SetScale(x, y)   self._scale = { x, y } end
    self._anims[#self._anims+1] = a
    return a
  end
  if owner then owner._animGroups[#owner._animGroups+1] = ag end
  return ag
end

local frameMeta = {}
frameMeta.__index = frameMeta
local allFrames = {}

function CreateFrame(kind, name, parent)
  local f = setmetatable({
    _kind = kind, _name = name, _parent = parent, _shown = true, _scale = 1,
    _w = 0, _h = 0, _children = {}, _scripts = {}, _events = {}, _points = {},
    _regions = {}, _animGroups = {}, _alpha = 1,
  }, frameMeta)
  if parent and parent._children then parent._children[#parent._children+1] = f end
  if name then _G[name] = f end
  allFrames[#allFrames+1] = f
  return f
end

function frameMeta:CreateTexture(_, layer, _, sublevel)
  local t = newRegion("Texture", layer, sublevel)
  self._regions[#self._regions+1] = t
  return t
end
function frameMeta:CreateFontString(_, layer)
  local t = newRegion("FontString", layer)
  self._regions[#self._regions+1] = t
  return t
end
function frameMeta:CreateAnimationGroup() return newAnimGroup(self) end
function frameMeta:SetSize(w, h)
  local ow, oh = self._w, self._h
  self._w, self._h = w, h
  if (ow ~= w or oh ~= h) and self._scripts.OnSizeChanged then self._scripts.OnSizeChanged(self, w, h) end
end
function frameMeta:SetWidth(w) self:SetSize(w, self._h) end
function frameMeta:SetHeight(h) self:SetSize(self._w, h) end
function frameMeta:GetWidth() return self._w end
function frameMeta:GetHeight() return self._h end
function frameMeta:GetSize() return self._w, self._h end
function frameMeta:Show()
  local was = self._shown
  self._shown = true
  -- OnShow fires on a hidden -> shown transition, as the client does. Without it the OnShow guard
  -- that re-hides DBM's warning hosts could never be exercised.
  if not was and self._scripts.OnShow then self._scripts.OnShow(self) end
end
function frameMeta:Hide() self._shown = false end
function frameMeta:IsShown() return self._shown end
function frameMeta:SetAlpha(a) self._alpha = a end
function frameMeta:GetAlpha() return self._alpha end
function frameMeta:SetScale(s) self._scale = s end
function frameMeta:GetScale() return self._scale end
function frameMeta:GetEffectiveScale() return self._scale end
function frameMeta:SetPoint(p, rel, relP, x, y) self._points[#self._points+1] = { p, rel, relP, x, y } end
function frameMeta:SetAllPoints(rel) self._points[#self._points+1] = { "ALL", rel } end
function frameMeta:ClearAllPoints() self._points = {} end
function frameMeta:GetNumPoints() return #self._points end
function frameMeta:GetPoint(i)
  local pt = self._points[i or 1]
  if not pt then return nil end
  return pt[1], pt[2], pt[3], pt[4], pt[5]
end
function frameMeta:SetScript(n, fn) self._scripts[n] = fn end
function frameMeta:GetScript(n) return self._scripts[n] end
-- HookScript CHAINS, where SetScript replaces. The suppression's OnShow guard rides on that: DBM
-- owns the warning hosts and may have its own handler, and a stub that quietly replaced it would
-- test something the game does not do.
function frameMeta:HookScript(n, fn)
  local prev = self._scripts[n]
  self._scripts[n] = function(...) if prev then prev(...) end return fn(...) end
end
function frameMeta:RegisterEvent(e) self._events[e] = true end
function frameMeta:UnregisterAllEvents() self._events = {} end
function frameMeta:SetFrameStrata(s) self._strata = s end
function frameMeta:GetFrameStrata() return self._strata or "MEDIUM" end
function frameMeta:SetFrameLevel(v) self._level = v end
function frameMeta:GetFrameLevel() return self._level or 1 end
function frameMeta:GetParent() return self._parent end
function frameMeta:GetRegions() return unpack(self._regions) end
-- IsVisible walks the parent chain, unlike IsShown. The diagnostic reports both because the
-- difference is precisely what "shown but not drawn" looks like.
function frameMeta:IsVisible()
  local f = self
  while f do
    if not f._shown then return false end
    f = f._parent
  end
  return true
end
function frameMeta:SetParent(p) self._parent = p end
function frameMeta:GetName() return self._name end
function frameMeta:GetObjectType() return self._kind end
function frameMeta:EnableMouse() end
function frameMeta:SetMovable() end
function frameMeta:RegisterForDrag() end
-- The edit-mode dialog's surface: a movable, screen-clamped window with template buttons.
function frameMeta:SetClampedToScreen() end
function frameMeta:StartMoving() end
function frameMeta:StopMovingOrSizing() end
function frameMeta:SetToplevel() end
function frameMeta:SetText(t) self._text = t end
function frameMeta:GetText() return self._text end
function frameMeta:Enable()  self._enabled = true end
function frameMeta:Disable() self._enabled = false end
function frameMeta:IsEnabled() return self._enabled ~= false end
function frameMeta:SetNormalTexture() end
function frameMeta:SetDisabledTexture() end
function frameMeta:SetHighlightTexture() end
function frameMeta:SetPushedTexture() end
-- StatusBar surface.
function frameMeta:SetMinMaxValues(lo, hi) self._min, self._max = lo, hi end
function frameMeta:GetMinMaxValues() return self._min or 0, self._max or 1 end
function frameMeta:SetValue(v) self._value = v end
function frameMeta:GetValue() return self._value or 0 end
function frameMeta:SetStatusBarTexture(t)
  self._sbTex = self._sbTex or newRegion("Texture", "ARTWORK")
  self._sbTex:SetTexture(t)
end
function frameMeta:GetStatusBarTexture() return self._sbTex end
function frameMeta:SetStatusBarColor(...) self._sbColor = { ... } end
function frameMeta:GetStatusBarColor()
  local c = self._sbColor or {1,1,1}; return c[1], c[2], c[3]
end

-- Drive every live frame's OnUpdate, as the client does each frame.
-- OnUpdate runs on VISIBLE frames, not merely shown ones — the whole parent chain has to be up, as
-- on the client. That distinction is not pedantry here: it is why hiding DBM's bar anchors freezes
-- every bar underneath them, which is the fault the DBT reaper exists to answer. A driver that
-- ticked `_shown` frames would model a client where that could not happen.
local function frame(dt)
  advance(dt)
  for _, f in ipairs(allFrames) do
    if f._scripts.OnUpdate and f:IsVisible() then f._scripts.OnUpdate(f, dt or 0.1) end
  end
end

UIParent = CreateFrame("Frame", "UIParent")
UIParent:SetSize(1024, 768)

-- ── other client globals ────────────────────────────────────────────────────────────────────────
function wipe(t) for k in pairs(t) do t[k] = nil end return t end

-- C_Timer.After, drained explicitly by the harness. Nothing in the module should be queueing on it
-- any more — the suppression pass that once did was answering an event ordering that turned out to
-- be backwards — so the queue being EMPTY is itself asserted below.
local deferred = {}
C_Timer = { After = function(_, fn) deferred[#deferred+1] = fn end }
local function runDeferred()
  local queue = deferred
  deferred = {}
  for _, fn in ipairs(queue) do fn() end
end
tinsert, tremove = table.insert, table.remove
-- The real thing, not a stub: a POST-hook that leaves the original in place and passes it the same
-- arguments. The adapter puts one on DBT's own CreateBar to notice the bars DBM draws without
-- firing anything, so a hooksecurefunc that quietly did nothing would make that untestable.
function hooksecurefunc(tbl, name, fn)
  local orig = tbl[name]
  tbl[name] = function(...)
    local returned = { orig(...) }
    fn(...)
    return unpack(returned)
  end
end
local printed = {}

function print(...) printed[#printed+1] = table.concat({ ... }, " ") end
SlashCmdList = {}

-- ── the addon namespace ─────────────────────────────────────────────────────────────────────────
DragonUI_NewEra = {}
local NE = DragonUI_NewEra
NE.L = setmetatable({}, { __index = function(_, k) return k end })
NE.qa = { modules = {} }
NE.FrameUtil = { PinPixelPerfect = function() end }
-- BM.OnFinished pcalls each handler and reports faults through NE.Log rather than raising inside an
-- animation callback. Without this the harness would swallow exactly the failures it exists to
-- catch, so the log is captured and asserted empty.
local logged = {}
function NE.Log(tag, msg) logged[#logged+1] = tostring(tag) .. ": " .. tostring(msg) end
local function drainLog()
  local s = table.concat(logged, " | ")
  logged = {}
  return s
end
NE.font = { FRIZ = "Fonts\\FRIZQT__.TTF" }

-- The profile store the settings chokepoint writes into.
local profile = { newera = { enabled = true, modules = {} } }
function NE.Config() return profile.newera end

-- NE.tex, reduced to what this module calls. Atlas registration is REAL (Assets.lua is loaded
-- below), so an atlas the renderer asks for and nobody registered shows up as a recorded miss.
local atlasMisses = {}
NE.tex = { localFiles = {}, atlases = {} }
function NE.tex.RegisterLocal(fdid, path) NE.tex.localFiles[fdid] = path end
function NE.tex.RegisterAtlases(t) for k, v in pairs(t) do NE.tex.atlases[k:lower()] = v end end
local function atlasEntry(name) return name and NE.tex.atlases[name:lower()] end
function NE.tex.SetAtlas(tex, name)
  local e = atlasEntry(name)
  if not e then atlasMisses[name] = (atlasMisses[name] or 0) + 1; return false end
  tex:SetTexture(NE.tex.localFiles[e.file] or e.file)
  tex:SetTexCoord(e.left, e.right, e.top, e.bottom)
  tex._atlas = name
  return true
end
NE.tex._atlasEntry = atlasEntry
function NE.tex.Local(fdid) return NE.tex.localFiles[fdid] end
function NE.tex.GetAtlasRect(name)
  local e = atlasEntry(name)
  if not e then return 0, 1, 0, 1 end
  return e.left, e.right, e.top, e.bottom
end
function NE.tex.SetAtlasOnStatusBar(bar, name)
  local e = atlasEntry(name)
  if not e then atlasMisses[name] = (atlasMisses[name] or 0) + 1; return false end
  bar:SetStatusBarTexture(NE.tex.localFiles[e.file] or e.file)
  bar._neOverlay = bar._neOverlay or newRegion("Texture", "ARTWORK")
  bar._neAtlasName = name
  return true
end
-- The CDM atlases modules/cooldownviewer/Assets.lua registers; the TOC loads it first, so from
-- this module's point of view they simply exist.
NE.tex.RegisterAtlases({
  ["UI-HUD-CoolDownManager-IconOverlay"] = { file = 6704514, left = 0, right = 1, top = 0, bottom = 1 },
  ["UI-HUD-CoolDownManager-Bar"]         = { file = 6704514, left = 0, right = 1, top = 0, bottom = 1 },
  ["UI-HUD-CoolDownManager-Bar-BG"]      = { file = 6704514, left = 0, right = 1, top = 0, bottom = 1 },
  ["UI-HUD-CoolDownManager-Bar-Pip"]     = { file = 6704514, left = 0, right = 1, top = 0, bottom = 1 },
})
NE.tex.localFiles[6704514] = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\CooldownViewer\\cdm.blp"

-- The real formatter (core/CooldownNumbers.lua is pure Lua at load time).
dofile(ADDON .. "core/CooldownNumbers.lua")

-- core/Modules.lua, for real: the requiresAddOn gate under test is its code, not a stand-in.
dofile(ADDON .. "core/Modules.lua")
NE.dragon = { db = { profile = profile } }

-- The editor seam. Records what each module hands over instead of building DragonUI's handle.
local hudFrames, optionSections = {}, {}
function NE.RegisterHUDFrame(spec) hudFrames[spec.name] = spec; return spec.frame end
function NE.RegisterOptionSection(spec) optionSections[#optionSections+1] = spec end

-- ── fake GameTooltip ────────────────────────────────────────────────────────────────────────────
--
-- Records what it was asked to show. SetHyperlink is the 3.3.5a way to render a spell tooltip —
-- SetSpellByID does not exist here — so the stub answers it and the harness can tell a real spell
-- tooltip from the name-only fallback DBM's non-spell timers get.
GameTooltip = {
  _shown = false,
  SetOwner = function(self, owner, anchorType) self._owner, self._anchor = owner, anchorType end,
  SetHyperlink = function(self, link)
    if not link:match("^spell:%d+$") then error("bad link " .. tostring(link)) end
    self._link, self._text = link, nil
    return true
  end,
  SetText = function(self, t) self._text, self._link = t, nil end,
  Show = function(self) self._shown = true end,
  Hide = function(self) self._shown = false; self._link, self._text, self._anchor = nil, nil, nil end,
  IsShown = function(self) return self._shown end,
}

-- ── fake SettingsControls kit ───────────────────────────────────────────────────────────────────
--
-- The dialog is built from the Cooldown Manager's widget kit. Stubbing it keeps this harness about
-- the boss-timer half — which settings a page exposes, what they write, and whether Revert and Reset
-- do what they say — rather than re-testing sliders that have their own coverage.
local kitRows = {}
local Column = {}
Column.__index = Column
local function addRow(self, kind, o)
  local row = { kind = kind, label = o.label, get = o.get, set = o.set, min = o.min, max = o.max,
                disabled = o.disabled }
  -- The real kit re-evaluates o.disabled on every Refresh; mirroring that here is what makes the
  -- view-specific gating assertable at all.
  row.IsGatedOff = function() return o.disabled and o.disabled() and true or false end
  self.rows[#self.rows+1] = row
  kitRows[#kitRows+1] = row
  return row
end
function Column:AddCheckbox(o)      return addRow(self, "checkbox", o) end
function Column:AddCompactSlider(o) return addRow(self, "slider",   o) end
function Column:AddSlider(o)        return addRow(self, "slider",   o) end
function Column:AddDropdown(o)      return addRow(self, "dropdown", o) end
function Column:AddButton(o)        return addRow(self, "button",   o) end
function Column:AddSpacer() end
function Column:AddText() end
function Column:Refresh() self.refreshed = (self.refreshed or 0) + 1 end
function Column:Relayout() return #self.rows * 34 end
DragonUI_NewEra.cooldownviewersettings = {
  controls = { New = function(parent, width, theme)
    return setmetatable({ frame = parent, width = width, theme = theme, rows = {} }, Column)
  end },
}
local function pageRows(label)
  for _, r in ipairs(kitRows) do if r.label == label then return r end end
end

-- ── fake LibCustomGlow ──────────────────────────────────────────────────────────────────────────
--
-- The real library is embedded and driven by the Cooldown Manager too; what matters here is the
-- LIFECYCLE, not the art. A track frame is POOLED, so a glow that is started and never stopped is
-- inherited by the next event to reuse it — an ability lit up as imminent while 40s out.
-- `_ButtonGlow` is modelled because the last-second blink writes that frame's alpha: it is the
-- library's own handle on the frame it lends out (LibCustomGlow-1.0.lua:793), and the pool's
-- resetter clears the field on release (:583-585), which is what makes its presence a safe test.
-- The glow frames themselves are POOLED, and the pool's resetter clears the owner's field and the
-- frame's points but does NOT touch its alpha (:580-588). So a glow handed back mid-blink comes
-- back out dimmed on whatever borrows it next — modelled here, because that is the whole reason the
-- module restores alpha before it stops one.
local FakeLCG, glowPool = {}, {}
function FakeLCG.ButtonGlow_Start(r, _color, freq)
  r._glowing, r._glowFreq = true, freq
  r._glowStarts = (r._glowStarts or 0) + 1
  r._ButtonGlow = r._ButtonGlow or table.remove(glowPool) or CreateFrame("Frame", nil, r)
end
function FakeLCG.ButtonGlow_Stop(r)
  r._glowing = false
  if r._ButtonGlow then
    glowPool[#glowPool + 1] = r._ButtonGlow
    r._ButtonGlow = nil     -- ButtonGlowResetter, LibCustomGlow-1.0.lua:583-585
  end
end
function LibStub(name, silent)
  if name == "LibCustomGlow-1.0" then return FakeLCG end
  return nil
end

local function glowing()
  local n = 0
  for _, f in ipairs(allFrames) do if f._glowing then n = n + 1 end end
  return n
end

-- ── the fake DBM (modelled on the INSTALLED 3.3.5a fork) ────────────────────────────────────────

local dbmCallbacks = {}
local DBM = {}
function DBM:RegisterCallback(event, fn)
  dbmCallbacks[event] = dbmCallbacks[event] or {}
  table.insert(dbmCallbacks[event], fn)
end
-- DBM-Core.lua:1540 — the event name is passed FIRST, ahead of the payload.
local function fireDBM(event, ...)
  for _, fn in ipairs(dbmCallbacks[event] or {}) do fn(event, ...) end
end

-- DBT: the global bar library (DBM-StatusBarTimers/DBT.lua:43). Modelled with the details that
-- turned out to matter:
--   * the two anchors are UNNAMED locals created at load (DBT.lua:179), the small one anchored
--     TOPRIGHT — the corner DBM's un-suppressed bars were showing up in;
--   * EVERY bar frame is a NAMED global, DBT_Bar_1.., created on the SMALL anchor (DBT.lua:249)
--     and never reparented; a huge bar is only re-POINTED to the large one (:663, :1120). It keeps
--     both name and parent after release, sitting in DBT's reuse pool;
--   * a bar's countdown IS its own OnUpdate (DBT.lua:251), and that handler is the ONLY thing that
--     ever expires one — `timer <= 0 -> self:Cancel()` — which is also the only place numBars is
--     decremented (:969);
--   * CreateBar REFUSES once numBars reaches 15 (DBT.lua:294). That cap plus the line above is the
--     whole reason the reaper exists: freeze the bars and DBM eventually stops making them.
local smallBarsAnchor = CreateFrame("Frame", nil, UIParent)
smallBarsAnchor:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", 223, -260)
local largeBarsAnchor = CreateFrame("Frame", nil, UIParent)
largeBarsAnchor:SetPoint("CENTER", UIParent, "CENTER", 0, -120)
local dbtBars, dbtBarCount = {}, 0
local DBT = { bars = {}, numBars = 0, Options = { KeepBars = false } }
function DBT:GetBarIterator()
  local i = 0
  return function() i = i + 1; return dbtBars[i] end
end

local function dbtCancel(bar)
  if bar.dead then return end
  bar.frame:Hide()
  bar.dead = true
  DBT.numBars = DBT.numBars - 1
  for i = #dbtBars, 1, -1 do
    if dbtBars[i] == bar then table.remove(dbtBars, i) break end
  end
end

local function addDBTBar(huge, dur, keep, id, icon)
  if DBT.numBars >= 15 then return nil end          -- DBT.lua:294
  dbtBarCount = dbtBarCount + 1
  local bar = { timer = dur or 20, totalTime = dur or 20, lastUpdate = GetTime(), keep = keep,
                id = id, icon = icon }
  bar.frame = CreateFrame("Frame", "DBT_Bar_" .. dbtBarCount, smallBarsAnchor)
  if huge then bar.frame:SetPoint("TOP", largeBarsAnchor, "TOP", 0, 0) end   -- re-point, not reparent
  bar.Cancel = dbtCancel
  bar.frame:SetScript("OnUpdate", function(_, elapsed)
    bar.lastUpdate = GetTime()
    if bar.paused then return end
    bar.timer = bar.timer - (elapsed or 0)
    if bar.timer <= 0 and not (DBT.Options.KeepBars and bar.keep) then dbtCancel(bar) end
  end)
  dbtBars[#dbtBars + 1] = bar
  DBT.numBars = DBT.numBars + 1
  return bar
end

-- The public entry points, in DBT's own argument order (DBT.lua CreateBar / CancelBar). Everything
-- that draws a DBM bar goes through CreateBar — timers with a callback behind them and the handful
-- of things DBM draws directly with none — so it is the one place the adapter can see both.
function DBT:CreateBar(timer, id, icon, huge)
  return addDBTBar(huge, timer, nil, id, icon)
end
function DBT:CancelBar(id)
  for i = #dbtBars, 1, -1 do
    if dbtBars[i].id == id then dbtCancel(dbtBars[i]) return end
  end
end

-- What DBM actually does on a timer: create the bar FIRST (DBM-Core.lua:10007), give up entirely if
-- DBT refuses — `if not bar then return false, "error" end` (:10008-10010) — and only then fire the
-- callback (:10049). An earlier version of this harness had it the other way round, which is what
-- made a deferred suppression pass look load-bearing when the bar had in fact been there all along.
local function fireDBMTimer(id, msg, dur, icon, spellId, huge)
  local bar = DBT:CreateBar(dur, id, icon, huge)
  if not bar then return nil end
  fireDBM("DBM_TimerStart", id, msg, dur, icon or "Interface\\Icons\\Spell_Fire_Fireball02",
          "cast", spellId, 1, "TestMod")
  return bar
end

_G.DBMWarning        = CreateFrame("Frame", "DBMWarning", UIParent)
_G.DBMSpecialWarning = CreateFrame("Frame", "DBMSpecialWarning", UIParent)

-- ── load the module, in TOC order ───────────────────────────────────────────────────────────────

section("LOAD")
local FILES = {
  "modules/bossmods/Assets.lua",
  "modules/bossmods/BossMods.lua",
  "modules/bossmods/EventIcon.lua",
  "modules/bossmods/Warnings.lua",
  "modules/bossmods/DBMAdapter.lua",
  "modules/bossmods/EditorPanel.lua",
  "modules/bossmods/Register.lua",
}
for _, rel in ipairs(FILES) do
  local ok, err = pcall(dofile, ADDON .. rel)
  check("loads " .. rel, ok, err)
end

local BM = NE.bossmods
check("the module namespace exists", BM ~= nil)

-- ── the DBM requirement ─────────────────────────────────────────────────────────────────────────

section("THE DBM REQUIREMENT")
check("with no DBM loaded, DBMPresent() is false", BM.DBMPresent() == false)
check("…so the addon gate reports the timers unsatisfied",
  NE.modules.AddOnSatisfied("bossmods") == false)
check("…and the warnings too", NE.modules.AddOnSatisfied("bossmods_warnings") == false)
check("…and the dependency is labelled DBM, so the options row can say so",
  NE.modules.Get("bossmods").requiresAddOn.label == "DBM")
check("both modules ship OFF by default",
  NE.modules.Get("bossmods").default == false
  and NE.modules.Get("bossmods_warnings").default == false)
check("the warnings declare the timers as a prerequisite",
  NE.modules.Get("bossmods_warnings").requires[1] == "bossmods")

_G.DBM = DBM
_G.DBT = DBT
check("with DBM present, DBMPresent() flips", BM.DBMPresent() == true)
check("…and the gate is satisfied", NE.modules.AddOnSatisfied("bossmods") == true)

-- ── settings store ──────────────────────────────────────────────────────────────────────────────

section("SETTINGS STORE")
local TL = BM.TIMELINE_ID
check("an unset option falls through to the retail-preset default",
  BM.GetOpt(TL, "viewType") == "timeline" and BM.GetOpt(TL, "opacity") == 100)
check("…including the NE-only rail length", BM.GetOpt(TL, "length") == 426)
BM.SetOpt(TL, "iconSize", 120)
check("a write round-trips", BM.GetOpt(TL, "iconSize") == 120)
check("…into DragonUI's profile, not a private table",
  profile.newera.bossmods.frames[TL].iconSize == 120)
BM.ResetOpts(TL)
check("reset drops back to the default", BM.GetOpt(TL, "iconSize") == 100)
check("the warning tiers carry their own defaults",
  BM.GetOpt("BossWarningCritical", "iconSize") == 100
  and BM.GetOpt("BossWarningMinor", "opacity") == 100)

-- ── boot ────────────────────────────────────────────────────────────────────────────────────────

section("BOOT")
NE.modules.SetEnabled("bossmods", true)
NE.modules.SetEnabled("bossmods_warnings", true)
-- core/Modules.lua's own dispatcher owns the gate, so drive the event rather than calling boot.
for _, f in ipairs(allFrames) do
  if f._events and f._events.PLAYER_LOGIN and f._scripts.OnEvent then
    f._scripts.OnEvent(f, "PLAYER_LOGIN")
  end
end
check("the timers booted", NE.modules.IsBooted("bossmods"))
check("the warnings booted", NE.modules.IsBooted("bossmods_warnings"))
check("the timeline anchor registered with the editor", hudFrames["NE_BossModsAnchor"] ~= nil)
check("…at retail's preset position", (function()
  local d = hudFrames["NE_BossModsAnchor"].defaultPoint
  return d.point == "BOTTOMRIGHT" and d.relativePoint == "BOTTOM" and d.x == -457 and d.y == 336
end)())
check("all three warning tiers registered too",
  hudFrames["NE_CriticalEncounterWarnings"] ~= nil
  and hudFrames["NE_MediumEncounterWarnings"] ~= nil
  and hudFrames["NE_MinorEncounterWarnings"] ~= nil)
check("DBM callbacks are registered", dbmCallbacks["DBM_TimerStart"] ~= nil)
check("…including the modern DBM_TimerBegin name, which this fork never fires",
  dbmCallbacks["DBM_TimerBegin"] ~= nil)
check("…and the pause/resume verbs BigWigs has no equivalent for",
  dbmCallbacks["DBM_TimerPause"] ~= nil and dbmCallbacks["DBM_TimerResume"] ~= nil)
check("an options section registered", #optionSections == 1 and optionSections[1].id == "bossmods")

-- Shared helpers, defined here because every section below uses them.
local anchor = BM.GetAnchor()

-- Run every playing group to completion, as the client does at the end of a fade. This is the path
-- that releases a bar, and the one that crashed the client — see the note on ag:Stop above.
local function finishAnimations()
  for _, f in ipairs(allFrames) do
    for _, ag in ipairs(f._animGroups or {}) do
      if ag._playing then ag:Finish() end
    end
    for _, r in ipairs(f._regions or {}) do
      for _, ag in ipairs(r._animGroups or {}) do
        if ag._playing then ag:Finish() end
      end
    end
  end
end

-- ── suppression (the rewritten half) ────────────────────────────────────────────────────────────

section("SUPPRESSION")
-- DBM's bars are HIDDEN, not dimmed. A hidden parent hides its children on every client, where a
-- parent's alpha reaching child frames is the thing this one is unreliable about (§C.5d) — and the
-- bars are children of these anchors. Dimming them is what left DBM's own bars on screen for
-- `/dbm test`, in the top-right corner where DBT anchors them.
check("nothing of DBM's is suppressed before a single bar has existed",
  smallBarsAnchor:IsShown(), "no bar has been created, so there is no anchor to find yet")

-- The ordering that matters, and it is the opposite of what an earlier build assumed: DBM creates
-- the bar first and only then fires the callback, so the anchor is reachable from inside the
-- callback and ONE synchronous pass does it.
fireDBMTimer("Sup1", "First of the pull", 20)
check("the first timer of the session hides the anchor synchronously", not smallBarsAnchor:IsShown())
-- Synchronously is the whole claim: suppression must be settled by the time this callback returns,
-- with nothing owed to a later frame. (The deferred queue is not empty — the adoption pass below
-- uses it, for a question that genuinely cannot be answered until the frame ends — so the honest
-- test is that draining it changes nothing here.)
runDeferred()
check("…and running whatever the frame deferred changes nothing about it", not smallBarsAnchor:IsShown())
-- DBM's warning ICONS are inline |T..|t escapes inside its own font strings (DBM-Core.lua:8121-27),
-- not textures — so nothing about them can be suppressed except by taking the host off screen. It
-- re-Shows the host on every announce and drives font alpha on a ticker, so alpha lost that race:
-- the hosts are hidden, and an OnShow hook re-hides them in the same frame DBM shows them.
check("DBM's warning hosts are hidden, not dimmed",
  not _G.DBMWarning:IsShown() and not _G.DBMSpecialWarning:IsShown())
check("…and DBM showing one again is undone in the same frame", (function()
  _G.DBMWarning:Show()
  return not _G.DBMWarning:IsShown()
end)(), "DBM's warning host stayed up after it re-showed it")

-- A huge bar is only re-POINTED to the large anchor (DBT.lua:663, :1120); it stays a CHILD of the
-- small one (:249), so hiding that one takes it with it. Worth an assertion because the adapter
-- collects both anchors and it would be easy to conclude the second one is load-bearing here.
local huge = fireDBMTimer("Sup2", "A huge one", 12, nil, nil, true)
check("a huge bar is hidden too, being a child of the small anchor after all",
  huge ~= nil and not huge.frame:IsVisible())

BM.SetSuppressionEnabled(false)
check("turning suppression off hands every frame back",
  smallBarsAnchor:IsShown() and _G.DBMWarning:IsShown())
check("…and DBM can show its own warnings again", (function()
  _G.DBMWarning:Hide(); _G.DBMWarning:Show()
  return _G.DBMWarning:IsShown()
end)(), "the OnShow guard kept firing after suppression was turned off")
BM.SetSuppressionEnabled(true)
check("…and turning it back on re-hides them", not smallBarsAnchor:IsShown())

-- A bar created while the anchor is already hidden is invisible from its first frame — which is the
-- reason for hiding the anchor rather than chasing individual bars.
local born = addDBTBar(false)
check("a bar born under a hidden anchor is invisible with no further work",
  not born.frame:IsVisible())

-- DBT RELEASES bars to a reuse pool rather than destroying them, so the live iterator yields nothing
-- between pulls while the frames still exist as globals under the anchor. Suppression has to survive
-- that. NOTE this does not isolate the DBT_Bar_N scan from the iterator — the anchor cache is warm by
-- now, so either route would pass it. That scan is belt for a COLD cache (a login after a previous
-- fight, where bars exist but none are live); the load-bearing fix is Hide-not-alpha.
BM.ClearDBMSuppression()
local liveBars = dbtBars
dbtBars = {}                       -- everything released to the pool; globals remain
BM.ApplyDBMSuppression()
check("the anchor is still found with no LIVE bars, via the pooled frames' names",
  not smallBarsAnchor:IsShown())
dbtBars = liveBars

-- This section starts real timers to exercise DBM's ordering, so it clears them again: the sections
-- below count what is live on the rail, and a stray bar from up here would fail them for a reason
-- that has nothing to do with what they test.
fireDBM("DBM_TimerStop", "Sup1")
fireDBM("DBM_TimerStop", "Sup2")
for _, f in ipairs(allFrames) do
  for _, ag in ipairs(f._animGroups or {}) do if ag._playing then ag:Finish() end end
end
frame(0.1)
for i = #dbtBars, 1, -1 do dbtCancel(dbtBars[i]) end

-- ── DBT's book-keeping, while its bars are frozen ───────────────────────────────────────────────

section("DBT BOOK-KEEPING (the 15-bar cap)")
-- Hiding the anchors is what makes DBM's bars invisible. It also FREEZES them — no OnUpdate on a
-- frame that is not visible, and a DBT bar's countdown IS its own OnUpdate — and that turns a
-- drawing decision into a functional one:
--
--     no bar expires -> numBars never falls (DBT.lua:969)
--       -> CreateBar refuses everything past fifteen (:294)
--         -> DBM's Timer:Start returns before it fires anything (DBM-Core.lua:10008-10010)
--           -> we are never told about another timer, and the rail is blank for the session.
--
-- Nothing else reclaims a slot: there is no CancelAllBars in DBT, and an expired timer is pruned
-- from startedTimers on a schedule (DBM-Core.lua:10059-10061), so a mod's combat-end Stop() misses
-- it. The reaper runs the accounting half of DBT's own update on the frozen bars instead.
check("suppression is on and DBT starts this section empty",
  not smallBarsAnchor:IsShown() and DBT.numBars == 0, "numBars = " .. DBT.numBars)

-- First, the modelling this all rests on, asserted rather than assumed: OnUpdate follows
-- VISIBILITY, not a frame's own shown flag. If this harness ticked hidden frames it would be a
-- client on which the fault below cannot happen, and every check under it would be theatre.
do
  local parent = CreateFrame("Frame", nil, UIParent)
  local child, ticks = CreateFrame("Frame", nil, parent), 0
  child:SetScript("OnUpdate", function() ticks = ticks + 1 end)
  frame(0.1)
  check("a frame under a shown parent gets OnUpdate", ticks == 1, ticks)
  parent:Hide()
  frame(0.1)
  check("…and stops dead when an ancestor is hidden, though it is still Shown itself",
    ticks == 1 and child:IsShown(), ticks)
end

-- Fill DBT to its limit, then let those bars run out with NO further DBM traffic at all. Nothing
-- calls the adapter in that stretch, so the per-event re-assert cannot help: the reaper's own
-- ticker is the only thing running. This is the quiet gap between two pulls, and without it the
-- first timer of the next pull is the one DBM cannot make a bar for — and so never reports.
local filled = 0
for i = 1, 15 do
  if fireDBMTimer("Fill" .. i, "Ability " .. i, 1) then filled = filled + 1 end
end
check("fifteen bars fills DBT exactly", filled == 15 and DBT.numBars == 15, "numBars = " .. DBT.numBars)
frame(0.4); frame(0.4); frame(0.4); frame(0.4)
check("frozen bars expire on the reaper's own ticker, with no DBM event to prompt it",
  DBT.numBars == 0, "numBars = " .. DBT.numBars)
check("…so the first timer of the next pull still reaches us",
  fireDBMTimer("AfterFill", "Next pull", 1) ~= nil)
frame(0.4); frame(0.4); frame(0.4)

local delivered = 0
for i = 1, 20 do
  if fireDBMTimer("Reap" .. i, "Ability " .. i, 1) then delivered = delivered + 1 end
  frame(0.4); frame(0.4); frame(0.4)   -- each bar is 1s long; the reaper ticks every 0.2s
end
check("twenty consecutive timers all reach us, not just the first fifteen", delivered == 20,
  delivered .. " of 20 — DBT stopped making bars, so DBM stopped firing the callback")
check("…because the frozen bars were reaped as they expired", DBT.numBars <= 1,
  "numBars = " .. DBT.numBars)

-- The reaper touches FROZEN bars only. A VISIBLE bar is DBT's own to drive, and taking time off it
-- here as well would run every DBM bar down at double speed. Driven straight at the reaper, since
-- the ticker stops when suppression does and would otherwise hide the omission.
BM.SetSuppressionEnabled(false)
local ownDriven = addDBTBar(false, 4)
frame(0.5); frame(0.5)
check("with suppression off DBT drives its own bar down by exactly the elapsed time",
  math.abs(ownDriven.timer - 3) < 0.05, "timer = " .. tostring(ownDriven.timer))
advance(1.0)
BM.ReapFrozenDBTBars()
check("…and the reaper leaves a bar DBT can still see for itself alone",
  math.abs(ownDriven.timer - 3) < 0.05, "timer = " .. tostring(ownDriven.timer))
dbtCancel(ownDriven)
BM.SetSuppressionEnabled(true)

-- A `keep` bar sits at zero until DBM explicitly stops it (DBT's own expiry test excludes it), so
-- reaping one would take a bar off DBM that DBM still believes it has.
DBT.Options.KeepBars = true
local kept = addDBTBar(false, 1, true)
frame(0.5); frame(0.5); frame(0.5)
check("a `keep` bar is left alone at zero, exactly as DBT leaves it", not kept.dead)
DBT.Options.KeepBars = false
dbtCancel(kept)

BM.BusStopAll(BM.DBM_OWNER)
for _, f in ipairs(allFrames) do
  for _, ag in ipairs(f._animGroups or {}) do if ag._playing then ag:Finish() end end
end
frame(0.1)

-- ── the bars DBM draws without telling anyone ───────────────────────────────────────────────────

section("ORPHAN DBT BARS")
-- Several of DBM's own bars go straight to DBT:CreateBar and fire no callback: the pizza timer
-- (DBM-Core.lua:1806 — `/dbm timer`, and every custom timer a raid leader broadcasts that is not a
-- pull or a break) and the world-buff alert (:4217). With DBM's bars hidden and no event to hear,
-- they simply disappeared. Taking over DBM's bar display means taking over all of it.
local function shownText(s)
  for _, f in ipairs(allFrames) do
    if f.IsVisible and f:IsVisible() then
      for _, r in ipairs(f._regions or {}) do
        if r:IsShown() and r._text == s then return true end
      end
    end
  end
  return false
end

DBT:CreateBar(30, "Loot in 5", "Interface\\Icons\\Spell_Holy_BorrowedTime")
check("a bar DBM drew with no callback is not adopted before the frame is out",
  not BM.BusHasBar(BM.DBM_OWNER, "Loot in 5"),
  "adopted synchronously, which cannot tell an orphan from an ordinary timer")
runDeferred()
check("…and is adopted once the frame ends with no callback having claimed it",
  BM.BusHasBar(BM.DBM_OWNER, "Loot in 5"))

-- The other half: an ordinary timer goes through the SAME CreateBar, so the pass has to leave it
-- alone. Adopting it would overwrite its label with DBM's internal timer id.
BM.SetOpt(TL, "viewType", "bars")
fireDBMTimer("Timer_cd12345", "Shadow Bolt Volley", 20)
runDeferred()
frame(0.1)
check("an ordinary timer keeps the text DBM sent, not the id its bar was named with",
  shownText("Shadow Bolt Volley") and not shownText("Timer_cd12345"))

DBT:CancelBar("Loot in 5")
check("DBM cancelling an adopted bar stops ours with it",
  not BM.BusHasBar(BM.DBM_OWNER, "Loot in 5"))

-- Adoption is suppression's job, not a feature of its own: with DBM drawing its own bars again,
-- adopting one IS the double-draw.
BM.SetSuppressionEnabled(false)
DBT:CreateBar(30, "DBM draws this one", "icon")
runDeferred()
check("with suppression off nothing is adopted — DBM has it",
  not BM.BusHasBar(BM.DBM_OWNER, "DBM draws this one"))
BM.SetSuppressionEnabled(true)

DBT:CreateBar(30, "Handback", "icon")
runDeferred()
check("…and one adopted while it was on is handed back when it goes off", (function()
  if not BM.BusHasBar(BM.DBM_OWNER, "Handback") then return false end
  BM.SetSuppressionEnabled(false)
  local gone = not BM.BusHasBar(BM.DBM_OWNER, "Handback")
  BM.SetSuppressionEnabled(true)
  return gone
end)())

BM.BusStopAll(BM.DBM_OWNER)
for _, f in ipairs(allFrames) do
  for _, ag in ipairs(f._animGroups or {}) do if ag._playing then ag:Finish() end end
end
frame(0.1)
for i = #dbtBars, 1, -1 do dbtCancel(dbtBars[i]) end

-- ── the Bars view's backing plate ───────────────────────────────────────────────────────────────

section("BARS-VIEW BACKGROUND")
-- The source shipped `damagemeters-background` and described it as exactly this, then never drew
-- it: Background moved the rail's shadow plate and did nothing at all in Bars view.
BM.SetOpt(TL, "background", 60)
fireDBM("DBM_TimerStart", "Plate1", "One", 20, "icon", "cast", 1, 1, "TestMod")
fireDBM("DBM_TimerStart", "Plate2", "Two", 25, "icon", "cast", 1, 1, "TestMod")
frame(0.1)
local plate = anchor.barsPlate
check("the bars view draws a backing plate", plate ~= nil and plate:IsShown())
check("…from the sheet that was shipped for it and never used",
  plate._atlas == "damagemeters-background", tostring(plate._atlas))
check("…at the Background slider's alpha, so the slider means something in this view too",
  math.abs((plate:GetAlpha() or 0) - 0.6) < 0.001, tostring(plate:GetAlpha()))
check("…and covers BOTH rows, which stack below the anchor and out of it",
  (plate:GetHeight() or 0) > 2 * 28, tostring(plate:GetHeight()))

BM.SetOpt(TL, "viewType", "timeline")
frame(0.1)
check("…and goes away with the view", not plate:IsShown())

fireDBM("DBM_TimerStop", "Plate1")
fireDBM("DBM_TimerStop", "Plate2")
finishAnimations()
frame(0.1)
check("…as it does when the last row goes", not plate:IsShown())
BM.SetOpt(TL, "background", BM.DEFAULTS[TL].background)

-- ── the timer feed ──────────────────────────────────────────────────────────────────────────────

section("TIMER FEED (DBM_TimerStart)")
-- The installed fork's exact payload: id, msg, timer, icon, timerType, spellId, colorId, modId,
-- keep, fade, name, guid — and NOTHING after it.
fireDBM("DBM_TimerStart", "Timer1", "Shadow Bolt Volley", 10, "Interface\\Icons\\Spell_Shadow_ShadowBolt",
        "cast", 12345, 1, "TestMod", nil, nil, "Shadow Bolt Volley", nil)
check("a timer produces one live bar", BM._testCount ~= nil or anchor:IsShown())

-- Reach the live list through the bus rather than an internal: stopping a key that exists is the
-- only externally visible proof it was tracked.
local before = anchor:IsShown()
fireDBM("DBM_TimerStart", "Timer2", "Cleave", 30, "Interface\\Icons\\Ability_Warrior_Cleave",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("the anchor is showing with work on it", before and anchor:IsShown())

-- What is actually ON the frame. "the bar renders but nothing is on it" is the failure mode these
-- exist to catch: the anchor and rail can be perfectly correct while every event is invisible.
local function anyRegion(pred)
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if pred(r, f) then return r, f end
    end
  end
end

check("the rail is showing", (function()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-line-right" then return f:IsShown() end
    end
  end
  return false
end)())
check("an event icon carries the texture DBM sent", anyRegion(function(r)
  return r._tex == "Interface\\Icons\\Spell_Shadow_ShadowBolt" and r:IsShown()
end) ~= nil)
check("…on a track frame that is shown and anchored to the rail", (function()
  local _, host = anyRegion(function(r) return r._tex == "Interface\\Icons\\Ability_Warrior_Cleave" end)
  if not host then return false end
  local track = host:GetParent()                    -- IconContainer -> track
  return track and track:IsShown() and track:GetNumPoints() > 0
end)())
check("…and the countdown text is painted, not blank", anyRegion(function(r)
  return r._kind == "FontString" and r._text and r._text:match("^~?%d") and r:IsShown()
end) ~= nil)

-- THE SECOND IN-GAME FAULT. Shown, textured, anchored and countdown-correct is exactly what the
-- crash-fix build reported — and every one of them was invisible, because the intro fade left the
-- track at alpha 0. Visibility is a separate assertion from existence, and always was.
local function tracksOf()
  local out = {}
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      -- Plain find, not a pattern: `\` is a literal in Lua patterns, so an escaped one here would
      -- look for TWO backslashes and match no real texture path.
      if r._tex and r._tex:find("Interface\\Icons", 1, true) then
        local track = f:GetParent()               -- IconContainer -> track
        if track then out[#out+1] = track end
      end
    end
  end
  return out
end
-- Visibility is the WHOLE tree: the track, the icon container and the countdown host each carry
-- their own alpha, and the icon and the number live on the latter two. Asserting the track alone is
-- what let the second build ship looking fixed while every icon was still invisible.
local function invisiblePart(t)
  if t:GetAlpha() < 1 then return "track" end
  for _, kid in ipairs(t._children or {}) do
    if kid:GetAlpha() < 1 then return "a child frame (icon container / countdown host)" end
  end
end
check("a rail event is actually VISIBLE once its intro fade ends", (function()
  local tracks = tracksOf()
  if #tracks == 0 then return false, "no tracks" end
  -- Run every intro to completion, which is where the client drops the alpha back.
  for _, f in ipairs(allFrames) do
    for _, ag in ipairs(f._animGroups or {}) do
      if ag._playing then ag:Finish() end
    end
  end
  for _, t in ipairs(tracks) do
    local bad = invisiblePart(t)
    if bad then return false, bad end
  end
  return true
end)(), "finished its fade with part of the track still at alpha 0")

-- The queued track never enters the railed branch, so it never met the belt that lived there.
check("a QUEUED event is visible too, not just a railed one", (function()
  frame(0.1)
  for _, t in ipairs(tracksOf()) do
    if t:IsShown() and invisiblePart(t) then return false end
  end
  return true
end)(), "a queued event sat at alpha 0 — it never reaches the railed branch")

check("a short timer sits on the linear rail, a long one queues", (function()
  -- TL_WINDOW is 12s: Timer1 (10s) is on the rail, Timer2 (30s) is queued.
  -- The queued state is the icon assembly's `queued` overlay.
  local queued, railed = 0, 0
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-fx-queued" and r:IsShown() then queued = queued + 1 end
      if r._atlas == "UI-HUD-CoolDownManager-IconOverlay" and r:IsShown() then railed = railed + 1 end
    end
  end
  return queued == 1 and railed >= 1
end)(), "queued/railed icon states")

section("PAUSE / RESUME")
-- Every countdown on screen, as a sorted snapshot. Both live timers are paused together so the
-- assertion is unambiguous: with one paused and one running, "some fontstring changed" proves
-- nothing about which one.
local function countdowns()
  local out = {}
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._kind == "FontString" and r._text and r._text:match("^~?%d+[sm]") then out[#out+1] = r._text end
    end
  end
  table.sort(out)
  return table.concat(out, "|")
end

fireDBM("DBM_TimerPause", "Timer1")
fireDBM("DBM_TimerPause", "Timer2")
frame(0.1)
local pausedBefore = countdowns()
check("both timers are showing a countdown to freeze", pausedBefore ~= "", pausedBefore)
frame(2.0)
check("a paused timer's countdown does not move", countdowns() == pausedBefore,
  pausedBefore .. " -> " .. countdowns())
check("…and the rail icon wears the paused badge", (function()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-fx-pause-icon" and r:IsShown() then return true end
    end
  end
  return false
end)())

fireDBM("DBM_TimerResume", "Timer1")
fireDBM("DBM_TimerResume", "Timer2")
frame(1.0)
check("…and resuming lets them run again", countdowns() ~= pausedBefore,
  pausedBefore .. " -> " .. countdowns())


section("STOP AND EXPIRY")
drainLog()
fireDBM("DBM_TimerStop", "Timer1")
fireDBM("DBM_TimerStop", "Timer2")
finishAnimations()
frame(0.1)
check("releasing a bar from its own OnFinished does not re-enter the animation API", drainLog() == "")
check("stopping every timer empties the frame again", not anchor:IsShown())

fireDBM("DBM_Wipe", { combatInfo = { name = "Test Boss" } })
check("a wipe with nothing running is harmless", true)

-- ── the last bar of a fight ─────────────────────────────────────────────────────────────────────
--
-- finishBar detaches its bar at once, so the LAST event of a fight drops the live count to zero
-- while its finish pop is still playing. Under "In combat only" — the default — refreshDriver used
-- to hide the anchor in that same tick, and an animation on a hidden frame does not advance: the
-- OnFinished never arrived, the bar never went back to the pool, and the ability vanished instead
-- of popping. One leaked frame per fight, invisible from the outside. The 1.15 source has it too.
BM.SetOpt(TL, "visibility", "incombat")
fireDBM("DBM_TimerStart", "Last", "The last one", 2, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("the frame is up with one timer on it", anchor:IsShown())
frame(2.2)   -- it lands: detached, nothing live, fade playing
check("the frame stays up while the last event plays its finish", anchor:IsShown(),
  "hidden mid-fade, so the animation can never finish and the bar never returns to the pool")
finishAnimations()
frame(0.1)
check("…and comes down once that fade has actually finished", not anchor:IsShown())

-- The belt. A fade that never reports back must not pin the frame up for ever, nor keep its bar out
-- of the pool: after FINISH_TIMEOUT the release is forced.
fireDBM("DBM_TimerStart", "Stuck", "Fade goes missing", 2, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 1, 1, "TestMod")
frame(0.1)
frame(2.2)
check("a stranded fade still holds the frame up a moment later", anchor:IsShown())
frame(1.2)   -- past FINISH_TIMEOUT, with no animation ever completing
check("…but is force-released once it is plainly not coming back", not anchor:IsShown())
-- releaseBar stops the fade on its way out, so in practice no late OnFinished should arrive at all
-- — endFinish still refuses a second pass, because a bar released twice is a bar pooled twice, and
-- the next two events would then be handed the SAME track to draw on. Two live timers, two visible
-- tracks, whichever route got us here.
drainLog()
finishAnimations()
frame(0.1)
check("a late OnFinished after a forced release is a no-op", drainLog() == "" and not anchor:IsShown())
do
  local rail
  for _, c in ipairs(anchor._children or {}) do
    for _, r in ipairs(c._regions or {}) do
      if r._atlas == "combattimeline-line-right" then rail = c end
    end
  end
  fireDBM("DBM_TimerStart", "TwoA", "First", 20, "icon", "cast", 1, 1, "TestMod")
  fireDBM("DBM_TimerStart", "TwoB", "Second", 25, "icon", "cast", 1, 1, "TestMod")
  frame(0.1)
  local shown = 0
  for _, t in ipairs(rail and rail._children or {}) do if t:IsShown() then shown = shown + 1 end end
  check("…so the next two events get a track each, not one frame between them", shown == 2, shown)
  fireDBM("DBM_TimerStop", "TwoA")
  fireDBM("DBM_TimerStop", "TwoB")
  finishAnimations()
  frame(0.1)
end
BM.SetOpt(TL, "visibility", BM.DEFAULTS[TL].visibility)

-- Both renderers reach release through a different group (the rail track's vs the bar row's), so
-- both are driven. This is the exact sequence that produced ERROR #132 in game.
section("ANIMATION RE-ENTRY (the #132 crash)")
for _, view in ipairs({ "timeline", "bars" }) do
  BM.SetOpt(TL, "viewType", view)
  drainLog()
  -- Expiry: the bar reaches "now" and plays the finish pop.
  fireDBM("DBM_TimerStart", "Expire", "Ends now", 2, "icon", "cast", 1, 1, "TestMod")
  frame(3.0)
  finishAnimations()
  check(view .. " view: a timer running out releases cleanly", drainLog() == "")
  -- Cancel: the mod pulls the bar early.
  fireDBM("DBM_TimerStart", "Cancelled", "Pulled early", 30, "icon", "cast", 1, 1, "TestMod")
  frame(0.1)
  fireDBM("DBM_TimerStop", "Cancelled")
  finishAnimations()
  check(view .. " view: a timer cancelled early releases cleanly", drainLog() == "")
  -- And a bulk stop, which is what a wipe does.
  fireDBM("DBM_TimerStart", "Bulk1", "One", 20, "icon", "cast", 1, 1, "TestMod")
  fireDBM("DBM_TimerStart", "Bulk2", "Two", 25, "icon", "cast", 1, 1, "TestMod")
  frame(0.1)
  fireDBM("DBM_Wipe", { combatInfo = { name = "Test Boss" } })
  finishAnimations()
  check(view .. " view: a wipe clears every bar cleanly", drainLog() == "")
  check(view .. " view: …and the frame is empty afterwards", not anchor:IsShown())
end
BM.ResetOpts(TL)

-- ── warnings ────────────────────────────────────────────────────────────────────────────────────

section("WARNINGS (DBM_Announce)")
local function tierShown()
  local out = {}
  for _, t in ipairs(BM.WARNING_TIERS) do
    local f = BM.WarningFrame(t.key)
    if f and f:IsShown() then out[#out+1] = t.key end
  end
  return table.concat(out, ",")
end
local function hideAll()
  for _, t in ipairs(BM.WARNING_TIERS) do BM.WarningFrame(t.key):Hide() end
end

hideAll()
fireDBM("DBM_Announce", "MOVE OUT OF THE FIRE", "icon", "spell", 1, "TestMod", true)
check("a SPECIAL warning lands on the Critical tier", tierShown() == "Critical")

hideAll()
fireDBM("DBM_Announce", "Shadow Bolt on you", "icon", "you", 1, "TestMod", false)
check("a personal announce lands on Medium", tierShown() == "Medium")

hideAll()
fireDBM("DBM_Announce", "Adds incoming", "icon", "spell", 1, "TestMod", false)
check("everything else lands on Minor", tierShown() == "Minor")

check("the warning text is what DBM sent", (function()
  local f = BM.WarningFrame("Minor")
  return f.View.Text:GetText() == "Adds incoming"
end)())

-- The "warnings flash briefly" fault: the swing fades the VIEW in over 0.2s, and on this client the
-- animation drops it straight back to 0 on completion. The frame stays shown for its full duration
-- with nothing visible inside it, which reads as a flash.
-- The whole TREE, not just the view. The flanking icons are child FRAMES of the view, so a fade
-- that restores the view alone leaves them wherever the animation dropped them — text and icons in
-- different states, which is what shipped: icons adrift with no text beside them.
check("a warning is still VISIBLE once its swing ends", (function()
  local f = BM.WarningFrame("Minor")
  finishAnimations()
  if not f:IsShown() then return false, "hidden" end
  if f.View:GetAlpha() < 1 then return false, "view at " .. f.View:GetAlpha() end
  for _, side in ipairs({ "LeftIcon", "RightIcon" }) do
    if f.View[side]:GetAlpha() < 1 then
      return false, side .. " at " .. f.View[side]:GetAlpha()
    end
  end
  return true
end)(), "the swing finished with part of the warning invisible")

-- The flanking icons are retail's, and pure decoration next to text that already names the ability.
-- They are therefore optional, per tier, like every other warning setting.
check("the flanking icons can be turned off", (function()
  local tier = BM.WARNING_TIERS[3]              -- Minor, the one showing above
  local f = BM.WarningFrame(tier.key)
  BM.SetOpt(tier.id, "showIcons", false)
  BM.ShowWarning(tier.key, "No icons please", nil, "Interface\\Icons\\Spell_Fire_Fireball02")
  local hidden = not f.View.LeftIcon:IsShown() and not f.View.RightIcon:IsShown()
  BM.SetOpt(tier.id, "showIcons", true)
  BM.ShowWarning(tier.key, "Icons back", nil, "Interface\\Icons\\Spell_Fire_Fireball02")
  return hidden and f.View.LeftIcon:IsShown() and f.View.RightIcon:IsShown()
end)())
check("…per tier, not all three at once", (function()
  local a, b = BM.WARNING_TIERS[1], BM.WARNING_TIERS[2]
  BM.SetOpt(a.id, "showIcons", false)
  local ok = BM.GetOpt(a.id, "showIcons") == false and BM.GetOpt(b.id, "showIcons") ~= false
  BM.SetOpt(a.id, "showIcons", true)
  return ok
end)())

-- The orphan-tier case: a warning whose hide swing never completed, leaving the frame up with an
-- invisible view and two visible flanking icons and no text between them.
check("a tier whose hide swing never finished does not linger with orphan icons", (function()
  local f = BM.WarningFrame("Medium")
  BM.ShowWarning("Medium", "Will be orphaned", nil, "Interface\\Icons\\Spell_Fire_Fireball02")
  finishAnimations()
  -- Force the state the fault produces: expiry gone, hide swing not running, frame still shown.
  f._expires = nil
  BM.StopAnim(f.HideAnim)
  f:Show()
  f.View.LeftIcon:Show(); f.View.RightIcon:Show()
  frame(0.1)                                   -- one tick of the frame's own OnUpdate
  return not f:IsShown()
     and not f.View.LeftIcon:IsShown()
     and not f.View.RightIcon:IsShown()
end)(), "the tier stayed up with its icons showing and no text")

check("…and its icons flank the text, not float free of it", (function()
  local f = BM.WarningFrame("Minor")
  local function anchoredToText(ic)
    local _, rel = ic:GetPoint(1)
    return rel == f.View.Text
  end
  return anchoredToText(f.View.LeftIcon) and anchoredToText(f.View.RightIcon)
end)(), "a flanking icon is not anchored to the warning text")

hideAll()
local minor = BM.WarningFrame("Minor")
fireDBM("DBM_Announce", "Adds incoming", "icon", "spell", 1, "TestMod", false)
frame(0.1)
check("…and it is still up a second later", minor:IsShown())
frame(4.0)
check("…then times out on its own (no C_Timer needed)",
  not minor:IsShown() or minor.HideAnim:IsPlaying())


-- ── the imminent glow ───────────────────────────────────────────────────────────────────────────
--
-- Replaces retail's mask-clipped swirl (PORT_PLAN §C.5e). The ring flash remains the entry cue; the
-- glow is what carries at a 0.53 effective scale.

section("IMMINENT GLOW")
check("nothing glows while every timer is far out", glowing() == 0, glowing())
-- The start counter is cumulative and the track frames are POOLED, so it carries whatever earlier
-- sections did with the same frame. Zero it: the question below is how many starts THIS episode
-- costs, not how many the frame has seen in its life.
for _, f in ipairs(allFrames) do f._glowStarts = nil end
fireDBM("DBM_TimerStart", "Soon", "About to land", 3, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("an event inside the 5s window glows", glowing() == 1, glowing())
check("…and it is the icon container that carries it, where the art is", (function()
  for _, f in ipairs(allFrames) do
    if f._glowing then
      for _, r in ipairs(f._regions or {}) do
        if r._tex and r._tex:find("Fireball02", 1, true) then return true end
      end
    end
  end
  return false
end)())
check("…started once, not once per frame", (function()
  for _, f in ipairs(allFrames) do
    if f._glowing and (f._glowStarts or 0) > 1 then return false end
  end
  return true
end)(), "ButtonGlow_Start was re-run on a tick, restarting its intro every frame")

-- A timer that gets pushed back out of the window must give the glow up again.
fireDBM("DBM_TimerUpdate", "Soon", 0, 30)
frame(0.1)
check("an event pushed back out of the window stops glowing", glowing() == 0, glowing())
fireDBM("DBM_TimerStop", "Soon")
finishAnimations()
frame(0.1)

-- The pooling trap: start a short timer, let it glow, release it, and reuse the frame.
fireDBM("DBM_TimerStart", "Short", "Lands now", 3, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("a fresh short timer glows", glowing() == 1, glowing())
fireDBM("DBM_TimerStop", "Short")
finishAnimations()
frame(0.1)
check("releasing it clears the glow", glowing() == 0, glowing())
fireDBM("DBM_TimerStart", "Long", "Ages away", 45, "Interface\\Icons\\Ability_Warrior_Cleave",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("…so the pooled frame does not hand it to a 45s event", glowing() == 0, glowing())
fireDBM("DBM_TimerStop", "Long")
finishAnimations()

-- ── the last second ─────────────────────────────────────────────────────────────────────────────
--
-- The swell is a smooth ramp, so no moment in it says NOW. The last second is that moment, and it
-- is THE SAME GLOW that says it — blinking, not replaced, not joined by a second effect. So the
-- assertion is on the glow frame's own alpha.
local function glowAlpha()
  for _, f in ipairs(allFrames) do
    if f._glowing and f._ButtonGlow then return f._ButtonGlow:GetAlpha() end
  end
end

for _, f in ipairs(allFrames) do f._glowStarts = nil end
fireDBM("DBM_TimerStart", "Landing", "Lands in a moment", 3.5, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("at three seconds out the glow is up and at full strength", glowAlpha() == 1, tostring(glowAlpha()))

frame(2.6)   -- ~0.8s to go: inside the last second
-- Sampling across the wave has to catch it both lit and dimmed, or it is not blinking. Eight
-- samples spanning about half a second cover more than one full cycle at any sane FLASH_HZ.
check("inside the last second that same glow blinks", (function()
  local lit, dim = false, false
  for _ = 1, 8 do
    frame(0.06)
    local a = glowAlpha() or 1
    if a > 0.9 then lit = true elseif a < 0.5 then dim = true end
  end
  return lit and dim
end)())
check("…and it is still the ONE glow, never stopped and restarted to do it", (function()
  for _, f in ipairs(allFrames) do
    if f._glowing and (f._glowStarts or 0) > 1 then return false end
  end
  return true
end)(), "the blink was drawn by re-running ButtonGlow_Start, which replays its intro every time")
check("…and nothing else was lit beside it — no second effect for the same job", (function()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-fx-highlight" and (r:GetAlpha() or 0) > 0 then return false end
    end
  end
  return true
end)())
-- Release it at a DIM moment of the blink: the library pools these frames and its resetter does not
-- touch alpha, so a glow handed back half-dark is a glow the next event borrows half-dark.
for _ = 1, 10 do
  if (glowAlpha() or 1) < 0.5 then break end
  frame(0.02)
end
check("…caught mid-blink, at a dim moment", (glowAlpha() or 1) < 0.5, tostring(glowAlpha()))
fireDBM("DBM_TimerStop", "Landing")
finishAnimations()
frame(0.1)
-- Asserted on the POOL, not on the next borrower. That pool is shared with everything in this UI
-- that uses LibCustomGlow — the Cooldown Manager's alerts most of all — and none of those write
-- alpha per tick to paper over what we left behind. Our own next event would never notice.
check("the glow goes back to that shared pool at full alpha, not at the blink's",
  #glowPool > 0 and glowPool[#glowPool]:GetAlpha() == 1,
  #glowPool > 0 and tostring(glowPool[#glowPool]:GetAlpha()) or "nothing was pooled")
fireDBM("DBM_TimerStart", "Next", "Also imminent", 3, "Interface\\Icons\\Ability_Warrior_Cleave",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("the next imminent event glows at full strength, not at the alpha the last blink left",
  glowAlpha() == 1, tostring(glowAlpha()))
fireDBM("DBM_TimerStop", "Next")
finishAnimations()
frame(0.1)

-- And the setting genuinely turns it off.
BM.SetOpt(TL, "showGlow", false)
fireDBM("DBM_TimerStart", "Soon2", "About to land", 3, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 1, 1, "TestMod")
frame(0.1)
check("with the setting off, nothing glows", glowing() == 0, glowing())
frame(2.5)
check("…so there is nothing to blink in the last second either", glowing() == 0, glowing())
BM.SetOpt(TL, "showGlow", true)
fireDBM("DBM_TimerStop", "Soon2")
finishAnimations()
frame(0.1)

-- ── views ───────────────────────────────────────────────────────────────────────────────────────

section("VIEWS")
-- The editor handle BOUNDS THE RAIL, and nothing more. It used to add the queued track's full
-- reserve (208px, five slots) so the handle would wrap queued icons; in game that made the box a
-- third taller and half again wider than anything drawn in it. Queued icons overhang instead.
check("the rail view sizes the anchor to the rail itself, with no empty reserve",
  anchor:GetHeight() == BM.GetOpt(TL, "length"), anchor:GetHeight())
check("…and to the width of an icon, not retail's 55px track lane",
  anchor:GetWidth() == 35, anchor:GetWidth())
check("…so Icon Size moves the handle with the icons", (function()
  BM.SetOpt(TL, "iconSize", 150)
  local w = anchor:GetWidth()
  BM.SetOpt(TL, "iconSize", 100)
  return w == 35 * 1.5, w
end)())
BM.SetOpt(TL, "viewType", "bars")
check("switching to bars swaps the renderer", BM.viewMode == "bars")
check("…and the anchor becomes a bar row", anchor:GetHeight() == 28)
check("…sized to the row the sliders actually produce", (function()
  BM.SetOpt(TL, "barWidth", 50)
  local w = anchor:GetWidth()
  BM.SetOpt(TL, "barWidth", 100)
  -- icon(28) + gap(4) + half of the 208px bar portion
  return w == 28 + 4 + 104, w
end)())
BM.SetOpt(TL, "length", 300)
BM.SetOpt(TL, "viewType", "timeline")
check("the rail Length slider resizes the anchor",
  anchor:GetHeight() == 300, anchor:GetHeight())
BM.ResetOpts(TL)

-- ── editor preview ──────────────────────────────────────────────────────────────────────────────

section("EDITOR PREVIEW")
hudFrames["NE_BossModsAnchor"].showTest()
check("the editor preview populates the frame", anchor:IsShown())
check("…with both a railed and a queued event, so the whole footprint is visible", (function()
  frame(0.1)
  local queued = 0
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-fx-queued" and r:IsShown() then queued = queued + 1 end
    end
  end
  return queued >= 1
end)())
hudFrames["NE_BossModsAnchor"].hideTest()
for _, f in ipairs(allFrames) do
  for _, ag in ipairs(f._animGroups or {}) do
    if ag._playing and ag._scripts.OnFinished then ag:Finish() end
  end
end
frame(0.1)
check("…and leaving the editor clears it", not anchor:IsShown())

hudFrames["NE_CriticalEncounterWarnings"].showTest()
check("a warning tier's preview shows its own name", (function()
  local f = BM.WarningFrame("Critical")
  return f:IsShown() and f.View.Text:GetText() == "Boss Warning - Critical"
end)())
hudFrames["NE_CriticalEncounterWarnings"].hideTest()
check("…and hides again on exit", not BM.WarningFrame("Critical"):IsShown())

-- ── art ─────────────────────────────────────────────────────────────────────────────────────────

section("ART")
check("every atlas the renderer asked for was registered", next(atlasMisses) == nil,
  (function() local s = {} for k in pairs(atlasMisses) do s[#s+1] = k end return table.concat(s, ", ") end)())
-- The highlight swirl is a FILLED 107x107 quad (centre alpha 211) that retail clips to a 35px icon
-- with a MaskTexture. There is no clip on 3.3.5a, so drawing it puts a solid additive disc three
-- times the icon's width over the spell art — which is exactly what shipped once. Deliberately not
-- ported (EventIcon.lua); this is the guard that keeps it that way.
check("the unclippable highlight swirl is not drawn on any icon", (function()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-fx-highlight-fx" then return false end
    end
  end
  return true
end)(), "a filled quad meant to be mask-clipped is on screen unclipped")
check("…while the glow RING, which needs no clip, still is", (function()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-fx-highlight" then return true end
    end
  end
  return false
end)())

check("the rail line is rotated with the 8-arg texcoord form, not the 4-arg one", (function()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-line-right" and r._coords and #r._coords == 8 then return true end
    end
  end
  return false
end)())

-- ── the diagnostic ──────────────────────────────────────────────────────────────────────────────
--
-- A debug dump that errors is worse than no debug dump: it is reached exactly when something is
-- already wrong. Driven in both views, with live bars and warnings up.

section("DIAGNOSTIC DUMP")
for _, view in ipairs({ "timeline", "bars" }) do
  BM.SetOpt(TL, "viewType", view)
  fireDBM("DBM_TimerStart", "Dump1", "Dumped", 9, "Interface\\Icons\\Spell_Fire_Fireball02",
          "cast", 1, 1, "TestMod")
  fireDBM("DBM_Announce", "Dumped warning", "icon", "spell", 1, "TestMod", true)
  frame(0.1)
  local ok, err = pcall(BM.Dump)
  check(view .. " view: /nebossmods debug runs clean", ok, err)
  fireDBM("DBM_TimerStop", "Dump1")
  finishAnimations()
end
BM.ResetOpts(TL)
check("…and with nothing running at all", pcall(BM.Dump))

-- ── the four settings the 1.15 source left as SHELL ─────────────────────────────────────────────
--
-- Orientation, Icon Direction, Flip Horizontally and Tooltips are all persisted-and-ignored upstream.
-- The owner asked for them, so they are implemented — and a setting that claims to do something has
-- to be shown doing it, or it is the shell it was supposed to stop being.

section("ORIENTATION AND ICON DIRECTION")
BM.ResetOpts(TL)
BM.SetOpt(TL, "viewType", "timeline")
fireDBM("DBM_TimerStart", "Axis", "Axis test", 6, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 4321, 1, "TestMod")
frame(0.1)

-- The LIVE track for an icon. Tracks are pooled and several earlier sections used the same art, so
-- matching on texture alone finds a released frame still holding its last position — which is how
-- this helper first reported a horizontal rail as vertical.
local function trackOf(texMatch)
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._tex and r._tex:find(texMatch, 1, true) then
        local track = f:GetParent()
        if track and track:IsShown() and f:IsShown() then return track end
      end
    end
  end
end
local function trackPoint()
  local t = trackOf("Fireball02")
  if not t then return nil end
  local pt, _, rel, x, y = t:GetPoint(1)
  return pt, rel, x, y
end

check("vertical is the default, with now at the BOTTOM", (function()
  local _, rel = trackPoint()
  return rel == "BOTTOM"
end)(), select(2, trackPoint()))
check("…and the anchor is taller than it is wide", anchor:GetHeight() > anchor:GetWidth())
check("…and an event sits ABOVE now, by its share of the rail", (function()
  local _, _, x, y = trackPoint()
  return x == 0 and y > 0
end)())

BM.SetOpt(TL, "iconDirection", "left")
frame(0.1)
check("Icon Direction moves now to the TOP", (function()
  local _, rel, _, y = trackPoint()
  return rel == "TOP" and y < 0
end)(), select(2, trackPoint()))

BM.SetOpt(TL, "orientation", "horizontal")
BM.SetOpt(TL, "iconDirection", "right")
frame(0.1)
check("Orientation turns the rail horizontal, now at the RIGHT", (function()
  local _, rel, x, y = trackPoint()
  return rel == "RIGHT" and x < 0 and y == 0
end)(), select(2, trackPoint()))
check("…and the anchor is wider than it is tall", anchor:GetWidth() > anchor:GetHeight())
check("…and the rail line is drawn with the PLAIN rect, not the vertical rotation", (function()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._atlas == "combattimeline-line-right" then return r._coords and #r._coords == 4 end
    end
  end
  return false
end)())

BM.SetOpt(TL, "iconDirection", "left")
frame(0.1)
check("…and Icon Direction moves now to the LEFT", (function()
  local _, rel, x = trackPoint()
  return rel == "LEFT" and x > 0
end)(), select(2, trackPoint()))

BM.ResetOpts(TL)
frame(0.1)
check("resetting puts the rail back to vertical, now at the bottom", (function()
  local _, rel = trackPoint()
  return rel == "BOTTOM"
end)())

section("IMMINENT GROW")
-- The owner's ask: an ability about to go off grows a little larger. It replaces retail's looping
-- pulse, which oscillates around its base size and so grows by nothing on average.
local function iconScaleOf()
  local t = trackOf("Fireball02")
  return t and t.IconContainer and t.IconContainer:GetScale()
end
fireDBM("DBM_TimerUpdate", "Axis", 0, 10)   -- 10s left: outside the 5s window
frame(0.1)
check("an event well out from now is at its rest size", iconScaleOf() == 1, iconScaleOf())
fireDBM("DBM_TimerUpdate", "Axis", 7.5, 10) -- 2.5s left: halfway through the window
frame(0.1)
local halfway = iconScaleOf()
check("…grows once it is imminent", halfway > 1, halfway)
fireDBM("DBM_TimerUpdate", "Axis", 9.5, 10) -- 0.5s left
frame(0.1)
check("…and keeps growing as it closes on now", iconScaleOf() > halfway, iconScaleOf())
check("…without ever exceeding the cap", iconScaleOf() <= 1.35 + 0.001, iconScaleOf())
check("…and Icon Size still multiplies it", (function()
  BM.SetOpt(TL, "iconSize", 200)
  frame(0.1)
  local s2 = iconScaleOf()
  BM.SetOpt(TL, "iconSize", 100)
  frame(0.1)
  return s2 > 2   -- 2.0 icon size times a swell greater than 1
end)())
fireDBM("DBM_TimerStop", "Axis")
finishAnimations()
frame(0.1)

section("TOOLTIPS")
fireDBM("DBM_TimerStart", "Tip", "Tipped ability", 20, "Interface\\Icons\\Spell_Fire_Fireball02",
        "cast", 4321, 1, "TestMod")
frame(0.1)
local tipTrack = trackOf("Fireball02")
check("the track is a hover target", type(tipTrack:GetScript("OnEnter")) == "function")
tipTrack:GetScript("OnEnter")(tipTrack)
check("hovering shows the spell tooltip DBM named", GameTooltip._link == "spell:4321", GameTooltip._link)
check("…at the cursor by default", GameTooltip._anchor == "ANCHOR_CURSOR", GameTooltip._anchor)
tipTrack:GetScript("OnLeave")(tipTrack)
check("…and it goes away", not GameTooltip:IsShown())

BM.SetOpt(TL, "tooltipAnchor", "default")
tipTrack:GetScript("OnEnter")(tipTrack)
check("Tooltips can anchor beside the frame instead", GameTooltip._anchor == "ANCHOR_RIGHT")
tipTrack:GetScript("OnLeave")(tipTrack)

BM.SetOpt(TL, "tooltipAnchor", "hidden")
tipTrack:GetScript("OnEnter")(tipTrack)
check("…or be turned off entirely", not GameTooltip:IsShown())
BM.SetOpt(TL, "tooltipAnchor", "cursor")
fireDBM("DBM_TimerStop", "Tip")
finishAnimations()

-- DBM raises plenty of timers that are not a spell; those must still say something.
fireDBM("DBM_TimerStart", "Pull", "Pull in", 15, "Interface\\Icons\\Spell_Fire_Fireball02",
        "pull", nil, 1, "TestMod")
frame(0.1)
local pullTrack = trackOf("Fireball02")
pullTrack:GetScript("OnEnter")(pullTrack)
check("a timer with no spell falls back to its own name",
  GameTooltip._text == "Pull in" and GameTooltip._link == nil, GameTooltip._text)
pullTrack:GetScript("OnLeave")(pullTrack)
fireDBM("DBM_TimerStop", "Pull")
finishAnimations()
frame(0.1)

section("FLIP HORIZONTALLY")
BM.SetOpt(TL, "viewType", "bars")
fireDBM("DBM_TimerStart", "Flip", "Flipped", 20, "Interface\\Icons\\Ability_Warrior_Cleave",
        "cast", 1, 1, "TestMod")
frame(0.1)
local function barIconEdge()
  for _, f in ipairs(allFrames) do
    for _, r in ipairs(f._regions or {}) do
      if r._tex and r._tex:find("Ability_Warrior_Cleave", 1, true) and #r._points > 0 then
        return r._points[#r._points][1]
      end
    end
  end
end
check("a bar row puts its icon on the LEFT by default", barIconEdge() == "LEFT", barIconEdge())
BM.SetOpt(TL, "flipHorizontal", true)
frame(0.1)
check("Flip Horizontally moves it to the RIGHT", barIconEdge() == "RIGHT", barIconEdge())
BM.SetOpt(TL, "flipHorizontal", false)
fireDBM("DBM_TimerStop", "Flip")
finishAnimations()
BM.ResetOpts(TL)
frame(0.1)

-- ── the edit-mode dialog ────────────────────────────────────────────────────────────────────────
--
-- The owner asked for "the same as we do for the cooldown manager edit mode", so what matters is
-- that it opens from the same seam, edits the right frame, and that Revert and Reset mean different
-- things — not the widget rendering, which is the CDM kit's own coverage.

section("EDIT-MODE DIALOG")
check("the timeline handle carries an editorSettings opener",
  type(hudFrames["NE_BossModsAnchor"].editorSettings) == "function")
check("…and so does every warning tier", (function()
  for _, t in ipairs(BM.WARNING_TIERS) do
    local spec = hudFrames["NE_" .. t.key .. "EncounterWarnings"]
    if type(spec.editorSettings) ~= "function" then return false end
  end
  return true
end)())

hudFrames["NE_BossModsAnchor"].editorSettings(anchor)
check("opening it shows the dialog", BM.IsEditorPanelShown())
check("…titled for the frame it edits", (function()
  local p = BM._editorPanel()
  return p and p.TitleText:GetText() == "Boss Abilities"
end)())
check("…exposing the timeline's settings, not a warning tier's", (function()
  local _, pages = BM._editorPanel()
  local page = pages[TL]
  if not page then return false end
  local seen = {}
  for _, r in ipairs(page.col.rows) do seen[r.label] = r end
  return seen["View"] and seen["Rail length"] and seen["Glow when an ability is imminent"] and true or false
end)())

-- The owner's steer: NewEra's own edit-mode popup carried more than size and scale, so what it
-- exposed is the yardstick. Every setting its buildTimelineOptions offers that this client can
-- actually RENDER must be here; the ones it marks SHELL (Orientation, Icon Direction, Flip
-- Horizontally, Tooltips — a vertical-only renderer with no hover targets) are deliberately absent.
check("the page covers every renderable setting NewEra's own popup had", (function()
  local _, pages = BM._editorPanel()
  local seen = {}
  for _, r in ipairs(pages[TL].col.rows) do seen[r.label] = true end
  for _, label in ipairs({ "View", "Show the frame", "Size", "Icon size", "Opacity", "Background",
                           "Rail length", "Bar width", "Space between bars", "Show the countdown",
                           "Show the ability name" }) do
    if not seen[label] then return false, label end
  end
  return true
end)(), "a setting NewEra's popup had is missing from ours")

-- The owner's follow-up: these four must be INCLUDED. They are, and each drives something.
check("the page carries all four of the settings the source left as shell", (function()
  local _, pages = BM._editorPanel()
  local seen = {}
  for _, r in ipairs(pages[TL].col.rows) do seen[r.label] = r end
  for _, label in ipairs({ "Orientation", "Icon direction", "Flip horizontally", "Tooltips" }) do
    if not seen[label] then return false, label end
  end
  return true
end)(), "one of the four is missing")

-- The kit's new `disabled` predicate, which is this addon's answer to NewEra's `showWhen`: a setting
-- that does not apply to the current view greys out instead of vanishing, so the page does not
-- reflow under the cursor.
local RAIL_ONLY = { "Orientation", "Icon direction", "Rail length" }
local BARS_ONLY = { "Bar width", "Space between bars", "Flip horizontally" }
check("view-specific settings grey out rather than disappear", (function()
  local _, pages = BM._editorPanel()
  local row = {}
  for _, r in ipairs(pages[TL].col.rows) do row[r.label] = r end

  local function expect(view, off, on)
    BM.SetOpt(TL, "viewType", view)
    for _, label in ipairs(off) do
      if not row[label].IsGatedOff() then return false, label .. " live in " .. view .. " view" end
    end
    for _, label in ipairs(on) do
      if row[label].IsGatedOff() then return false, label .. " greyed in " .. view .. " view" end
    end
    return true
  end

  local ok, why = expect("timeline", BARS_ONLY, RAIL_ONLY)
  if not ok then return false, why end
  ok, why = expect("bars", RAIL_ONLY, BARS_ONLY)
  if not ok then return false, why end
  -- ...and back, since the gate has to track the setting in both directions.
  ok, why = expect("timeline", BARS_ONLY, RAIL_ONLY)
  BM.SetOpt(TL, "viewType", "timeline")
  return ok, why
end)())

check("a control writes straight through to the store", (function()
  local _, pages = BM._editorPanel()
  for _, r in ipairs(pages[TL].col.rows) do
    if r.label == "Icon size" then r.set(125); return BM.GetOpt(TL, "iconSize") == 125 end
  end
  return false
end)())

-- Revert is session undo; Reset is defaults. Conflating them is how someone loses a setup reaching
-- for undo, so they are asserted apart.
check("Revert goes back to how the frame was when the editor opened", (function()
  local p = BM._editorPanel()
  p.revertButton:GetScript("OnClick")()
  return BM.GetOpt(TL, "iconSize") == 100
end)())
check("Reset goes back to the shipped default, not the session start", (function()
  BM.SetOpt(TL, "length", 700)
  local p = BM._editorPanel()
  p.resetButton:GetScript("OnClick")()
  return BM.GetOpt(TL, "length") == 426 and BM.GetOpt(TL, "iconSize") == 100
end)())

-- Size is retail's OverallSize, which NewEra's popup carried as its built-in Scale slider. It was
-- missing from the first cut of this dialog; it scales the whole frame, where Icon Size scales only
-- the icons, and the two are not interchangeable.
check("Size scales the frame, through the pixel-perfect pin", (function()
  local _, pages = BM._editorPanel()
  for _, r in ipairs(pages[TL].col.rows) do
    if r.label == "Size" then r.set(150); break end
  end
  local ok = BM.GetOpt(TL, "scale") == 150
  BM.SetOpt(TL, "scale", 100)
  return ok
end)())

check("selecting a warning tier swaps the page", (function()
  local tier = BM.WARNING_TIERS[1]
  hudFrames["NE_" .. tier.key .. "EncounterWarnings"].editorSettings(nil)
  local p, pages = BM._editorPanel()
  local page = pages[tier.id]
  if not (page and p.TitleText:GetText() == tier.label) then return false end
  -- A tier carries only the settings that render for it — Size, Icon size, Opacity — and none of
  -- the timeline's. Asserted by content rather than a count, so adding a setting does not fail this
  -- for the wrong reason.
  local seen = {}
  for _, r in ipairs(page.col.rows) do seen[r.label] = true end
  return seen["Size"] and seen["Icon size"] and seen["Opacity"]
     and not seen["View"] and not seen["Rail length"]
end)())
check("…and edits THAT tier, not all three at once", (function()
  local tier = BM.WARNING_TIERS[1]
  local _, pages = BM._editorPanel()
  for _, r in ipairs(pages[tier.id].col.rows) do
    if r.label == "Opacity" then r.set(75) end
  end
  return BM.GetOpt(tier.id, "opacity") == 75
     and BM.GetOpt(BM.WARNING_TIERS[2].id, "opacity") == 100
end)())
BM.SetOpt(BM.WARNING_TIERS[1].id, "opacity", 100)

hudFrames["NE_BossModsAnchor"].onHide()
check("leaving edit mode closes the dialog", not BM.IsEditorPanelShown())

-- ── slash command ───────────────────────────────────────────────────────────────────────────────

section("SLASH COMMAND")
check("/nebossmods is registered", type(SlashCmdList["NEBOSSMODS"]) == "function")
SlashCmdList["NEBOSSMODS"]("bars")
check("…and switches views", BM.GetOpt(TL, "viewType") == "bars")
SlashCmdList["NEBOSSMODS"]("timeline")
check("…and back", BM.GetOpt(TL, "viewType") == "timeline")
SlashCmdList["NEBOSSMODS"]("status")
check("…and reports status without erroring", #printed > 0)
SlashCmdList["NEBOSSMODS"]("test")
check("…and the test feed runs through the live bus", anchor:IsShown())

-- ── result ──────────────────────────────────────────────────────────────────────────────────────

print = report
print("")
if failures == 0 then
  print(("ALL BOSS TIMER CHECKS PASSED (%d)"):format(checks))
else
  print(("%d of %d BOSS TIMER CHECKS FAILED"):format(failures, checks))
  os.exit(1)
end
