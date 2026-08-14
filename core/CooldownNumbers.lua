-- DragonUI_NewEra/core/CooldownNumbers.lua — countdown text on Cooldown frames (NE.cd).
--
-- DOWNPORT: NewEra's Core/Cooldown.lua drives retail's BUILT-IN cooldown numbers — the engine draws
-- them and `NE.cd.ApplyNumbers` just configures font / abbreviation threshold / minimum duration via
-- Cooldown:SetCountdownFont / SetHideCountdownNumbers. 3.3.5a's Cooldown widget has none of that and
-- draws no text at all, so this file OWNS the text: a FontString parented to the cooldown plus a
-- throttled OnUpdate. Same public surface, so ported call sites are unchanged.
--
-- PUBLIC:
--   NE.cd.FONT                          -- named font objects per surface
--   NE.cd.ApplyNumbers(cooldown, opts)  -- opts = { font = <fontObjectName>, show = <bool> }
--
-- opts fields are INDEPENDENT and sticky: ApplyNumbers{font=...} at OnLoad then ApplyNumbers{show=...}
-- from SetTimerShown must not clear the font. Only keys present in `opts` are applied.

local NE = DragonUI_NewEra
NE.cd = NE.cd or {}

-- Retail uses GameFontHighlightHugeOutline / ...Outline for the viewer surfaces. 3.3.5a has no
-- "Huge" outlined game font, but the NumberFont family is outlined and is what Blizzard uses for
-- action-button cooldown text, so it is the closest match.
--
-- Each entry is a FALLBACK CHAIN, not a single name: NumberFontNormalHuge is present in some 3.3.5a
-- builds and not others (unlike NumberFontNormalLarge/Normal/Small, which are used by shipped
-- addons in this install and are therefore known-good). Resolution walks the chain and takes the
-- first font object that actually exists, so a missing name costs nothing and logs nothing.
NE.cd.FONT = {
  viewerEssential = { "NumberFontNormalHuge", "NumberFontNormalLarge", "NumberFontNormal" },
  viewerUtility   = { "NumberFontNormalLarge", "NumberFontNormal" },
  viewerAura      = { "NumberFontNormal" },
  viewerBar       = { "NumberFontNormalSmall", "NumberFontNormal" },
}

-- Resolve a font spec (a name, or a chain of names) to a live font object.
local function resolveFont(spec)
  if type(spec) == "string" then
    return _G[spec], spec
  end
  if type(spec) == "table" then
    for _, name in ipairs(spec) do
      local obj = _G[name]
      if obj then return obj, name end
    end
    return nil, table.concat(spec, "/")
  end
  return nil, tostring(spec)
end

-- Retail constants (Blizzard_CooldownViewer): abbreviate to minutes at 120s, and suppress the
-- countdown entirely for cooldowns shorter than 2s (GCD-length noise).
local ABBREV_THRESHOLD = 120
local MIN_DURATION     = 2.0
local UPDATE_INTERVAL   = 0.1

local function formatTime(t)
  if t >= 3600 then
    return math.ceil(t / 3600) .. "h"
  elseif t >= ABBREV_THRESHOLD then
    return math.ceil(t / 60) .. "m"
  elseif t >= 1 then
    return tostring(math.floor(t))
  end
  return string.format("%.1f", t)
end

-- Paint the current remaining time. Returns false once the cooldown is over (or shouldn't show),
-- so callers can tear the ticker down.
local function paint(cd)
  local text = cd._neText
  if not text then return false end

  local start, duration = cd._neStart, cd._neDuration
  if not (cd._neShow and start and duration and duration >= MIN_DURATION) then
    text:SetText("")
    return false
  end

  local remaining = (start + duration) - GetTime()
  if remaining <= 0 then
    text:SetText("")
    return false
  end
  text:SetText(formatTime(remaining))
  return true
end

local function tick(cd, elapsed)
  cd._neAccum = (cd._neAccum or 0) + elapsed
  if cd._neAccum < UPDATE_INTERVAL then return end
  cd._neAccum = 0
  if not paint(cd) then cd:SetScript("OnUpdate", nil) end
end

-- Begin/stop the ticker based on the current stashed cooldown + show flag.
local function refresh(cd)
  local start, duration = cd._neStart, cd._neDuration
  local active = cd._neShow
    and start and start > 0
    and duration and duration >= MIN_DURATION
    and (start + duration) > GetTime()

  if active then
    -- Paint NOW rather than waiting for the first OnUpdate — otherwise the number is blank for up
    -- to UPDATE_INTERVAL at the exact moment the cooldown starts, which reads as a flicker.
    paint(cd)
    cd._neAccum = 0
    cd:SetScript("OnUpdate", tick)
  else
    cd:SetScript("OnUpdate", nil)
    if cd._neText then cd._neText:SetText("") end
  end
end

-- Intercept SetCooldown/Hide so we learn start+duration without the caller changing.
-- 3.3.5a's Cooldown has SetCooldown and Hide but NOT Clear (added in a later expansion); we add a
-- Clear that matches ClassicAPI's CooldownFrame_Clear semantics (hide + forget) so ported call
-- sites can use either.
local function instrument(cd)
  if cd._neInstrumented then return end
  cd._neInstrumented = true

  local rawSetCooldown = cd.SetCooldown
  cd.SetCooldown = function(self, start, duration, ...)
    self._neStart, self._neDuration = start, duration
    refresh(self)
    return rawSetCooldown(self, start, duration, ...)
  end

  local rawHide = cd.Hide
  cd.Hide = function(self, ...)
    self._neStart, self._neDuration = nil, nil
    refresh(self)
    return rawHide(self, ...)
  end

  if not cd.Clear then
    cd.Clear = function(self)
      self._neStart, self._neDuration = nil, nil
      refresh(self)
      self:Hide()
    end
  end
end

-- opts = { font = <global font object name>, show = <bool> }. Only keys present are applied.
function NE.cd.ApplyNumbers(cooldown, opts)
  if not cooldown then return end
  opts = opts or {}
  instrument(cooldown)

  if not cooldown._neText then
    -- OVERLAY so the number sits above the swipe. Parented to the cooldown itself so it inherits
    -- the cooldown's show/hide and frame level.
    local fs = cooldown:CreateFontString(nil, "OVERLAY")
    fs:SetPoint("CENTER", cooldown, "CENTER", 0, 0)
    cooldown._neText = fs
    cooldown._neShow = true
  end

  if opts.font then
    local fontObject, tried = resolveFont(opts.font)
    if fontObject then
      cooldown._neText:SetFontObject(fontObject)
    elseif NE.Log and not NE.cd._warnedFont then
      -- Once per session, not once per icon: the whole chain missing is a single fact about the
      -- client, and the text still renders in the FontString's inherited default.
      NE.cd._warnedFont = true
      NE.Log("CD", "no font object resolved from " .. tostring(tried))
    end
  end

  if opts.show ~= nil then
    cooldown._neShow = opts.show and true or false
  end

  refresh(cooldown)
end

-- Expose the formatter — the BuffBar duration label wants the same abbreviation rules.
NE.cd.FormatTime = formatTime

-- The OTHER timer string, for bars rather than swipes. Retail draws countdown BARS with
-- SecondsFormatter OneLetter, 2 desired units, minimum Seconds (EncounterTimelineConstants.lua:216)
-- — "45s", "1m30s", "1h2m" — where a cooldown SWIPE is bare ("45", "2m"). They are not
-- interchangeable, so both live here rather than one call site inventing its own.
--
-- Added for modules/bossmods (the boss-timer downport), which is what NewEra's source called
-- NE.cd.FormatBarTime; the Cooldown Manager's own bars keep FormatTime, which is what they use today.
function NE.cd.FormatBarTime(t)
  t = tonumber(t) or 0
  if t < 1 then return string.format("%.1f", t) end
  if t < 60 then return string.format("%ds", t) end
  if t < 3600 then
    local m, s = math.floor(t / 60), math.floor(t % 60)
    return s > 0 and string.format("%dm%ds", m, s) or string.format("%dm", m)
  end
  local h, m = math.floor(t / 3600), math.floor((t % 3600) / 60)
  return m > 0 and string.format("%dh%dm", h, m) or string.format("%dh", h)
end
