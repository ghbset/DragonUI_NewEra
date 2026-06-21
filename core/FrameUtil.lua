-- DragonUI_NewEra/core/FrameUtil.lua — shared frame utilities. The canonical pixel-perfect pin.
--
-- DOWNPORT: NewEra Core/FrameUtil.lua → 3.3.5a. Body is mostly raw WoW API and ports almost
-- verbatim. Adaptations are marked `-- DOWNPORT:` inline. Top changed from `local NE = NE` to
-- `local NE = DragonUI_NewEra` per the addon convention (CONTRACTS §0).
--
-- ONE PinPixelPerfect for the whole addon. Pins a frame to the 768/physicalHeight pixel
-- scale (same crispness as every other UI frame). `userScale` is the per-frame multiplier
-- (default 1.0). NewEra also exposes this on NE.frameutil (the §2 public surface) — we alias
-- both NE.FrameUtil (NewEra's internal name) and NE.frameutil (the contract name).

local NE = DragonUI_NewEra

NE.FrameUtil = NE.FrameUtil or {}
NE.frameutil = NE.FrameUtil   -- DOWNPORT: §2 contract exposes NE.frameutil.*; alias to the same table

-- THE shared "do it when combat ends" deferral. Runs fn immediately when not in
-- lockdown; otherwise queues it for the next PLAYER_REGEN_ENABLED (one shared watcher
-- frame for the whole addon).
local regenJobs, regenWatcher
function NE.FrameUtil.AfterCombat(fn)
  if not (InCombatLockdown and InCombatLockdown()) then
    fn()
    return
  end
  regenJobs = regenJobs or {}
  regenJobs[#regenJobs + 1] = fn
  if not regenWatcher then
    regenWatcher = CreateFrame("Frame")
    regenWatcher:RegisterEvent("PLAYER_REGEN_ENABLED")
    regenWatcher:SetScript("OnEvent", function()
      local jobs = regenJobs
      regenJobs = nil
      if jobs then
        for _, job in ipairs(jobs) do job() end
      end
    end)
  end
end

-- SetScale on a PROTECTED frame raises in combat — defer those pins to PLAYER_REGEN_ENABLED.
-- Pins coalesce by frame (only the last requested userScale applies).
local deferredPins
local function flushDeferredPins()
  local pins = deferredPins
  deferredPins = nil
  if not pins then return end
  for frame, userScale in pairs(pins) do
    NE.FrameUtil.PinPixelPerfect(frame, userScale)
  end
end

-- The canonical pixel base: (768/physicalHeight) × the automatic integer multiplier — or NIL
-- when the user ticked Blizzard's UI Scale (useUiScale CVar).
-- DOWNPORT: 3.3.5a has GetPhysicalScreenSize + GetCVarBool, so this ports unchanged.
function NE.FrameUtil.PixelBaseScale()
  if GetCVarBool and GetCVarBool("useUiScale") then return nil end
  local _, ph = GetPhysicalScreenSize()
  if not ph or ph <= 0 then return nil end
  return (768 / ph) * math.max(1, math.floor(ph / 1080 + 0.5))
end

-- Registry of every pinned frame → its last userScale, so a UI-scale / resolution change re-pins
-- ALL of them live.
local pinnedFrames = setmetatable({}, { __mode = "k" })   -- weak keys: don't keep dead frames alive

function NE.FrameUtil.PinPixelPerfect(frame, userScale)
  if not frame then return end
  pinnedFrames[frame] = userScale or 1.0
  if InCombatLockdown and InCombatLockdown() and frame.IsProtected and frame:IsProtected() then
    local schedule = deferredPins == nil
    deferredPins = deferredPins or {}
    deferredPins[frame] = userScale or 1.0
    if schedule then NE.FrameUtil.AfterCombat(flushDeferredPins) end
    return
  end
  if GetCVarBool and GetCVarBool("useUiScale") then
    frame:SetScale(userScale or 1.0)
    return
  end
  local _, ph = GetPhysicalScreenSize()
  if not ph or ph <= 0 then return end
  local m = math.max(1, math.floor(ph / 1080 + 0.5))
  local target = (768 / ph) * m * (userScale or 1.0)
  local parent = frame:GetParent() or UIParent
  local parentScale = parent:GetEffectiveScale()
  if parentScale and parentScale > 0 then
    frame:SetScale(target / parentScale)
  end
end

-- Central re-pin: when the user changes UI scale / resolution, re-pin every registered frame.
local function repinAllFrames()
  for frame, us in pairs(pinnedFrames) do
    if frame.GetObjectType then NE.FrameUtil.PinPixelPerfect(frame, us) end
  end
end

-- Re-pin DEFERRED one frame, coalesced.
local repinPending
local function scheduleRepin()
  if repinPending then return end
  repinPending = true
  local function run() repinPending = nil; repinAllFrames() end
  if C_Timer and C_Timer.After then C_Timer.After(0, run) else run() end
end

-- DOWNPORT: 3.3.5a has UI_SCALE_CHANGED + CVAR_UPDATE; DISPLAY_SIZE_CHANGED also exists.
-- The CVar-cache flip detection (un-ticking "UI Scale" without a scale event) ports as-is.
local lastUseUi   = GetCVarBool and GetCVarBool("useUiScale")
local lastUiScale = GetCVar and GetCVar("uiScale")

local pinScaleWatcher = CreateFrame("Frame")
pinScaleWatcher:RegisterEvent("UI_SCALE_CHANGED")
pinScaleWatcher:RegisterEvent("DISPLAY_SIZE_CHANGED")
pinScaleWatcher:RegisterEvent("CVAR_UPDATE")
pinScaleWatcher:SetScript("OnEvent", function(_, event)
  if event == "CVAR_UPDATE" then
    local function check()
      local u = GetCVarBool and GetCVarBool("useUiScale")
      local s = GetCVar and GetCVar("uiScale")
      if u ~= lastUseUi or s ~= lastUiScale then
        lastUseUi, lastUiScale = u, s
        repinAllFrames()
      end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0, check) else check() end
    return
  end
  lastUseUi   = GetCVarBool and GetCVarBool("useUiScale")
  lastUiScale = GetCVar and GetCVar("uiScale")
  scheduleRepin()
end)

-- Font constants + setter. One home for the client font paths.
-- DOWNPORT: NewEra hardcoded "Fonts\\FRIZQT__.TTF"; on 3.3.5a we prefer DragonUI's locale-aware
-- font (NE.dragon.Fonts.PRIMARY) so CJK/Cyrillic clients don't render "???". Falls back to the
-- literal path if DragonUI's font table isn't present.
NE.font = NE.font or {}
NE.font.FRIZ     = (NE.dragon and NE.dragon.Fonts and NE.dragon.Fonts.PRIMARY) or "Fonts\\FRIZQT__.TTF"
NE.font.MORPHEUS = "Fonts\\MORPHEUS.ttf"
function NE.font.Set(fs, path, size, flags, fallbackObject)
  if not fs:SetFont(path, size, flags or "") and fallbackObject then
    fs:SetFontObject(fallbackObject)
  end
end

-- ESC-close registration: add the frame (by global name) to UISpecialFrames, once.
function NE.FrameUtil.EscClose(frame)
  local name = type(frame) == "string" and frame
    or (frame and frame.GetName and frame:GetName())
  if not name then return end
  for _, n in ipairs(UISpecialFrames) do
    if n == name then return end
  end
  tinsert(UISpecialFrames, name)
end

-- Keep a frame on screen after its SIZE changes.
function NE.FrameUtil.KeepOnScreen(frame)
  if not (frame and frame.SetClampedToScreen) then return end
  frame:SetClampedToScreen(true)
  local p1, rel, p2, x, y = frame:GetPoint(1)
  if p1 then frame:SetPoint(p1, rel, p2, x or 0, y or 0) end
end

-- Disable-path fallback for XML-built frames: at PLAYER_LOGIN, if the module did NOT boot,
-- unhook any unit watch and hide each named frame (combat-deferred).
function NE.FrameUtil.HideWhenModuleOff(moduleName, ...)
  local names = { ... }
  local w = CreateFrame("Frame")
  w:RegisterEvent("PLAYER_LOGIN")
  w:SetScript("OnEvent", function()
    if not NE.modules or NE.modules.IsBooted(moduleName) then return end
    NE.FrameUtil.AfterCombat(function()
      for _, n in ipairs(names) do
        local f = _G[n]
        if f then
          if UnregisterUnitWatch then pcall(UnregisterUnitWatch, f) end
          f:Hide()
        end
      end
    end)
  end)
end

-- Panel open/close sounds via an invisible CHILD frame (never HookScript on protected windows).
-- DOWNPORT: 3.3.5a PlaySound returns (willPlay, soundHandle) for known kits; for unknown kit
-- IDs it can hard-error, so wrap in pcall and fall back to the vanilla-native kit.
function NE.FrameUtil.WirePanelSounds(frame, openKit, closeKit, fallbackOpen, fallbackClose)
  if not frame or frame._neSoundWatcher then return end
  local function play(kit, fallback)
    if not kit then return end
    local ok, willPlay = pcall(PlaySound, kit)
    if not (ok and willPlay) and fallback then pcall(PlaySound, fallback) end
  end
  local w = CreateFrame("Frame", nil, frame)
  w:SetScript("OnShow", function() play(openKit,  fallbackOpen)  end)
  w:SetScript("OnHide", function() play(closeKit, fallbackClose) end)
  frame._neSoundWatcher = w
end

-- Money text — the gold/silver/copper coin-icon string for a copper amount.
NE.money = NE.money or {}
function NE.money.Text(copper, empty)
  if copper and copper > 0 then
    return (GetCoinTextureString and GetCoinTextureString(copper)) or tostring(copper)
  end
  return empty or "—"
end

-- Shared 5-tier difficulty ladder (creature/quest level vs the player).
function NE.difficultyTier(level)
  local diff = (level or 0) - (UnitLevel("player") or 0)
  if diff >= 5 then return "impossible"
  elseif diff >= 3 then return "verydifficult"
  elseif diff >= -2 then return "difficult"
  elseif GetQuestGreenRange and (-diff) <= (GetQuestGreenRange("player") or 0) then return "standard"
  else return "trivial" end
end

NE.color = NE.color or {}
-- "ffrrggbb" hex (floor rounding) for a {r,g,b} colour table (0-1). No "|c" prefix.
function NE.color.ToHex(color)
  color = color or { r = 1, g = 1, b = 1 }
  return string.format("ff%02x%02x%02x",
    math.floor((color.r or 1) * 255), math.floor((color.g or 1) * 255), math.floor((color.b or 1) * 255))
end
-- Wrap `text` in a class colour code: |cffRRGGBB<text>|r.
function NE.color.WrapClass(classFile, text)
  local c = (classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]) or { r = 1, g = 1, b = 1 }
  return "|c" .. NE.color.ToHex(c) .. (text or "") .. "|r"
end
-- Class colour as raw r,g,b (0-1). Honours CUSTOM_CLASS_COLORS, then RAID_CLASS_COLORS, then white.
function NE.color.ClassRGB(classFile)
  local pool = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local c = classFile and pool and pool[classFile]
  if not c then return 1, 1, 1 end
  return c.r, c.g, c.b
end
-- Debuff-type (dispel) colour as raw r,g,b (0-1) from the global DebuffTypeColor table.
function NE.color.DispelRGB(dtype)
  local pool = _G.DebuffTypeColor
  local c = pool and (pool[dtype or "none"] or pool.none)
  if not c then return 1, 1, 1 end
  return c.r, c.g, c.b
end

-- Region walking — call fn(region) for each child region whose object type == `kind` and draw
-- layer == `layer`. Returns the count visited.
function NE.FrameUtil.ForEachRegion(frame, kind, layer, fn)
  if not (frame and frame.GetRegions and fn) then return 0 end
  local regions = { frame:GetRegions() }
  local visited = 0
  for i = 1, #regions do
    local r = regions[i]
    if r and (not kind or (r.GetObjectType and r:GetObjectType() == kind))
         and (not layer or (r.GetDrawLayer and (r:GetDrawLayer()) == layer)) then
      fn(r)
      visited = visited + 1
    end
  end
  return visited
end

-- FindRegion(frame, kind, predicate): the first matching child region, else nil.
function NE.FrameUtil.FindRegion(frame, kind, predicate)
  if not (frame and frame.GetRegions and predicate) then return nil end
  local regions = { frame:GetRegions() }
  for i = 1, #regions do
    local r = regions[i]
    if r and (not kind or (r.GetObjectType and r:GetObjectType() == kind)) and predicate(r) then
      return r
    end
  end
  return nil
end

-- Copyable dump dialog — a movable DIALOG-strata frame with a selectable multiline EditBox.
-- DOWNPORT: 3.3.5a has no BackdropTemplate (it's a Cata+ template). CreateFrame with that
-- template name silently returns a plain frame whose :SetBackdrop still exists natively on
-- 3.3.5a frames, so we call SetBackdrop directly and drop the template argument.
function NE.FrameUtil.CopyBox(opts)
  opts = opts or {}
  local w, h = opts.w or 760, opts.h or 500
  local f = CreateFrame("Frame", opts.name, UIParent)   -- DOWNPORT: no "BackdropTemplate" on 3.3.5a
  f:SetSize(w, h)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -10)
  title:SetText(opts.title or "Copy — Ctrl+A then Ctrl+C")

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 12, -34)
  scroll:SetPoint("BOTTOMRIGHT", -30, 38)

  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject(ChatFontNormal)
  edit:SetWidth(w - 50)
  edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  scroll:SetScrollChild(edit)

  local selectAll = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  selectAll:SetSize(90, 20)
  selectAll:SetPoint("BOTTOMLEFT", 12, 10)
  selectAll:SetText("Select All")
  selectAll:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)

  f.edit = edit
  function f:SetText(t) edit:SetText(t or "") end
  function f:ShowText(t) edit:SetText(t or ""); self:Show(); edit:SetFocus(); edit:HighlightText() end
  return f
end

-- IsAddOnLoaded shim. DOWNPORT: 3.3.5a has the GLOBAL IsAddOnLoaded (no C_AddOns namespace),
-- so this prefers the compat C_AddOns if present, else the global. Returns a plain bool.
function NE.IsAddOnLoaded(name)
  local fn = (C_AddOns and C_AddOns.IsAddOnLoaded) or _G.IsAddOnLoaded
  if not fn then return false end
  local ok, loaded = pcall(fn, name)
  return (ok and loaded) and true or false
end
