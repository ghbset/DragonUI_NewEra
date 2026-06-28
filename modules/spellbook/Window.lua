-- DragonUI_NewEra/modules/spellbook/Window.lua — the STANDALONE Spellbook WINDOW HOST.
--
-- DECOUPLING: NewEra's Spellbook borrowed its window from the Talents module (a shared
-- NE_TalentFrame on tab 2). Here we give the spellbook its OWN window — NE_SpellBookFrame —
-- replicating ONLY the window shell + chrome + sheen + secure toggle. No talent tree, no War
-- Mode orb, no bottom bar, no loadouts. The RENDERER agent (Spellbook.lua) builds all content
-- under SB.Host() and provides SB.Build / SB.Refresh / SB.RenderCards (we call them, guarded).
--
-- SHARED INTERFACE CONTRACT (the renderer depends on this — provided EXACTLY):
--   SB.frame            standalone window Frame (global "NE_SpellBookFrame")
--   SB.Host()           content-root Frame (chrome-inset child); renderer parents everything here
--   SB.FRAME_W/.MIN_W/.FRAME_H/.CHROME_L/.CHROME_T/.CHROME_R/.CHROME_B   constants on the table
--   SB.minimized        boolean (loaded from DragonUI_NewEraDB.spellbook.minimized)
--   SB.ApplyWidth()     resize frame width to (minimized and MIN_W or FRAME_W)
--   SB.SetMinimized(b)  set+persist+ApplyWidth+Refresh
--   SB.Toggle()/.Open()/.SetShown(shown)   show/hide (SetShown(true) also Refreshes)
--   SB.RegisterSheen(node)   shared sheen-sweep driver (gated on SB.frame visibility)
--
-- RULES: no SetShown; no C_Container/C_Item; guard every global+helper; combat-guard size/show
-- changes (defer to PLAYER_REGEN_ENABLED); only // comments (no /* */).

local NE = DragonUI_NewEra
NE.spellbook = NE.spellbook or {}
local SB = NE.spellbook

-- ----------------------------------------------------------------------------
-- Geometry constants (ON the SB table per the contract). Inherited from the NewEra
-- shared window: full 1618 maximized, 809 minimized (single page), 883 tall. The chrome
-- inset here is the metal-border thickness the renderer must avoid (top band = 22px title).
-- ----------------------------------------------------------------------------
SB.FRAME_W  = 1618
SB.MIN_W    = 809
SB.FRAME_H  = 883

-- WINDOW SCALE. The book INHERITS UIParent's scale (so the in-game "Use UI Scale" slider controls
-- its size like any normal frame) times SB.UI_SCALE as a per-window fine-tune. We deliberately do NOT
-- lock it to a fixed fraction of the physical screen — that divided out UIParent's scale, so the UI
-- Scale slider had no effect and the book read as huge. Lower SB.UI_SCALE → smaller book; raise → bigger.
SB.UI_SCALE = 0.8   -- legacy fallback only; the live value lives in NE.scale (per-window setting)
local function applyWindowScale(f)
  if NE.scale and NE.scale.Apply then
    if f and NE.scale.SetFrame then NE.scale.SetFrame("spellbook", f) end
    NE.scale.Apply("spellbook")
  elseif f and f.SetScale then
    f:SetScale(SB.UI_SCALE or 1.0)
  end
end
SB.ApplyWindowScale = applyWindowScale
SB.CHROME_L = 0
SB.CHROME_T = 22
SB.CHROME_R = 0
SB.CHROME_B = 0

local FRAME_NAME = "NE_SpellBookFrame"
local MODULE     = "Spellbook"

-- Portrait: the circular CLASS icon, identical to the Character panel's portrait — the
-- baked-circular classicon-<classfile> atlas (FDID 1662186, registered by
-- modules/character/Assets.lua, which loads first) fills the metal ring cleanly. Degrades to the
-- native circular player portrait if the sheet isn't shipped.

-- ----------------------------------------------------------------------------
-- Local logger + guard (NE.Log may be absent on a standalone load).
-- ----------------------------------------------------------------------------
local function log(msg)
  if NE.Log then NE.Log("SPELLBOOK", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [spellbook]: " .. tostring(msg))
  end
end
SB._log = log

local function guard(label, fn)
  local ok, err = pcall(fn)
  if not ok then log(label .. " failed: " .. tostring(err)) end
  return ok
end

-- ----------------------------------------------------------------------------
-- SavedVariables helpers. DragonUI_NewEraDB.spellbook.minimized is the persisted state
-- (NE.db is the live mirror — see bootstrap.lua). Read defensively (DB may not be ready).
-- ----------------------------------------------------------------------------
local function sbDB(create)
  local db = NE.db or _G.DragonUI_NewEraDB
  if not db then return nil end
  if not db.spellbook then
    if not create then return nil end
    db.spellbook = {}
  end
  return db.spellbook
end

local function loadOpts()
  local t = sbDB(false)
  if t and t.minimized ~= nil then
    SB.minimized = t.minimized and true or false
  else
    SB.minimized = SB.minimized and true or false
  end
end
SB._loadOpts = loadOpts

local function saveOpts()
  local t = sbDB(true)
  if t then t.minimized = SB.minimized and true or false end
end

-- Default before any load (overwritten by loadOpts at PLAYER_LOGIN).
if SB.minimized == nil then SB.minimized = false end

-- ----------------------------------------------------------------------------
-- Sheen sweep driver (ported from NewEra Talents.lua ~170-211). ONE shared GetTime()
-- clock drives EVERY registered node's `.sheen` texture in unison (no per-node anim
-- drift), gated on SB.frame visibility (NOT the talent frame). Each node opts in via a
-- `.sheen` texture + SB.RegisterSheen(node). Self-contained.
-- ----------------------------------------------------------------------------
local SHEEN_CYCLE, SHEEN_DELAY, SHEEN_DUR = 22.0, 5.0, 6.5
local SHEEN_TRAVEL = 150
local sheenList = {}

function SB.RegisterSheen(node)
  if not node or node._sheenRegistered then return end
  node._sheenRegistered = true
  sheenList[#sheenList + 1] = node
end

local sheenDriver = CreateFrame("Frame")
local sheenWasSweeping = false
sheenDriver:SetScript("OnUpdate", function()
  -- Idle when the window is closed (nodes aren't visible anyway).
  if not (SB.frame and SB.frame:IsShown()) then
    if sheenWasSweeping then
      for _, n in ipairs(sheenList) do if n.sheen then n.sheen:Hide() end end
      sheenWasSweeping = false
    end
    return
  end
  local t = (GetTime() % SHEEN_CYCLE) - SHEEN_DELAY
  if t < 0 or t > SHEEN_DUR then
    if sheenWasSweeping then   -- one-shot hide-all on leaving the sweep window
      for _, n in ipairs(sheenList) do if n.sheen then n.sheen:Hide() end end
      sheenWasSweeping = false
    end
    return
  end
  sheenWasSweeping = true
  local offset = (t / SHEEN_DUR) * SHEEN_TRAVEL
  for _, n in ipairs(sheenList) do
    local tex = n.sheen
    if tex and n._wantSheen ~= false and n.IsVisible and n:IsVisible() then
      tex:ClearAllPoints()
      tex:SetPoint("RIGHT", n, "LEFT", offset, 0)
      tex:Show()
    elseif tex and tex:IsShown() then
      tex:Hide()
    end
  end
end)

-- ----------------------------------------------------------------------------
-- The portrait. Texture path (a book icon), seated in the metal corner via the cutout helper.
-- ----------------------------------------------------------------------------
local function applyPortrait(f)
  local p = f and (f.portrait or f.PortraitTexture)
  if not p then return end
  local _, classFile = UnitClass("player")
  classFile = classFile and classFile:lower() or "warrior"
  local atlas = "classicon-" .. classFile
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(p, atlas, false)) then
    if SetPortraitTexture then pcall(SetPortraitTexture, p, "player") end
  end
end
SB._applyPortrait = applyPortrait

-- ----------------------------------------------------------------------------
-- The minimize / maximize button (top-right, near the close). No NE.maxmin in this addon's
-- core, so build a simple functional [-]/[+] toggle that flips SB.SetMinimized. Idempotent.
-- ----------------------------------------------------------------------------
local function buildMinimize(f)
  if f.minBtn then return f.minBtn end
  local b = CreateFrame("Button", "NE_SpellBookMinimizeButton", f)
  b:SetSize(24, 24)   -- match the close button (PanelChrome default 24)
  -- Sit just left of the close button, same size + vertical alignment.
  if f.CloseButton then
    b:SetPoint("RIGHT", f.CloseButton, "LEFT", -2, 0)
  else
    b:SetPoint("TOPRIGHT", f, "TOPRIGHT", -27, 0)
  end
  local baseLvl = (f.GetFrameLevel and f:GetFrameLevel()) or 1
  b:SetFrameLevel(baseLvl + 21)   -- above the chrome stack like the close button
  -- Reskin with the NewEra RedButton Condense/Expand glyphs (same 4698972 sheet as the X close
  -- button). Normal + pushed textures swap per state in syncIcon; red-glow highlight matches close.
  local nt = b:CreateTexture(nil, "ARTWORK"); nt:SetAllPoints(b); b:SetNormalTexture(nt)
  local pt = b:CreateTexture(nil, "ARTWORK"); pt:SetAllPoints(b); b:SetPushedTexture(pt)
  local ht = b:CreateTexture(nil, "HIGHLIGHT"); ht:SetAllPoints(b); b:SetHighlightTexture(ht)
  NE.tex.SetAtlas(ht, "redbutton-highlight-2x", false)
  local function syncIcon()
    -- ONE page now (minimized) -> show EXPAND (the ↗ arrow) to open the 2nd page; TWO pages now
    -- (maximized) -> show CONDENSE (the ↙ arrow) to collapse to one. Pushed = the -pressed variant.
    if SB.minimized then
      NE.tex.SetAtlas(nt, "redbutton-expand-2x", false)
      NE.tex.SetAtlas(pt, "redbutton-expand-pressed-2x", false)
    else
      NE.tex.SetAtlas(nt, "redbutton-condense-2x", false)
      NE.tex.SetAtlas(pt, "redbutton-condense-pressed-2x", false)
    end
  end
  b._syncIcon = syncIcon
  syncIcon()
  b:SetScript("OnClick", function()
    SB.SetMinimized(not SB.minimized)
  end)
  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(SB.minimized and "Show second page" or "Show single page")
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  f.minBtn = b
  SB.maxmin = b
  return b
end

-- ----------------------------------------------------------------------------
-- Build the window shell ONCE. Modern portrait-frame chrome (via NE.chrome.Apply — the
-- character panel's proven path on a bare CreateFrame), a content-root Host child, the
-- minimize button, ESC-close, and open/close sounds. Hidden by default.
-- ----------------------------------------------------------------------------
local function buildWindow()
  if SB.frame then return SB.frame end

  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  f:SetSize(SB.minimized and SB.MIN_W or SB.FRAME_W, SB.FRAME_H)
  f:SetPoint("TOP", UIParent, "TOP", 0, -55)
  -- HIGH + toplevel so an enlarged window stays above the action/spell bars (which sit in MEDIUM);
  -- toplevel raises the clicked window within its strata.
  f:SetFrameStrata("HIGH")
  f:SetToplevel(true)
  -- Drag-to-move WITH saved position (persists account-wide across /reload + sessions).
  if NE.FrameUtil and NE.FrameUtil.PersistWindowPosition then
    NE.FrameUtil.PersistWindowPosition(f, "spellbook",
      { point = "TOP", relPoint = "TOP", x = 0, y = -55 })
  else
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(self) self:StartMoving() end)
    f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  end
  f:Hide()
  SB.frame = f

  -- Open/close sounds (igCharacterInfoOpen/Close), via a child watcher (never on the frame).
  guard("sounds", function()
    if NE.FrameUtil and NE.FrameUtil.WirePanelSounds then
      NE.FrameUtil.WirePanelSounds(f, "igCharacterInfoOpen", "igCharacterInfoClose")
    end
  end)

  -- ESC closes it OUT OF COMBAT (the secure wrap below handles the combat path).
  guard("escClose", function()
    if NE.FrameUtil and NE.FrameUtil.EscClose then
      NE.FrameUtil.EscClose(FRAME_NAME)
    else
      tinsert(UISpecialFrames, FRAME_NAME)
    end
  end)

  -- Modern DF chrome (nineslice + Rock bg + title). noPortrait=true: PanelChrome's default
  -- portrait fill is the PLAYER portrait + a watcher; we own the portrait as a BOOK icon below.
  guard("chrome.Apply", function()
    if NE.chrome and NE.chrome.Apply then
      NE.chrome.Apply(f, {
        layout     = "PortraitFrameTemplate",
        title      = SPELLBOOK or "Spellbook",
        noPortrait = true,
      })
    end
  end)

  -- Own the portrait region: build the cutout texture, seat it in the metal corner, fill with
  -- the book icon. Re-assert on Show (the corner can be repainted by chrome re-application).
  guard("portrait", function()
    -- The icon fill must sit ABOVE the host wood but BELOW the gold ring. The ring (metal corner) is
    -- a BORDER-layer texture on f.NineSlice, which renders above the host (a same-level sibling). So
    -- host the portrait on f.NineSlice too, at ARTWORK (< BORDER): that puts it over the wood yet
    -- under the ring. (A separate high-level holder drew it OVER the ring.)
    local ringFrame = f.NineSlice or f
    if not f.portrait then f.portrait = ringFrame:CreateTexture(nil, "ARTWORK") end
    if NE.portrait and NE.portrait.ApplyCutout then
      NE.portrait.ApplyCutout(f.portrait, f)   -- anchored to f's corner; draws at the ring frame's level
    end
    applyPortrait(f)
    f:HookScript("OnShow", function() applyPortrait(f) end)
  end)

  -- Render-on-show. The KEY open path (TOGGLESPELLBOOK override binding) fires the SECURE toggle's
  -- frame:Show() snippet, which never calls SB.Refresh — so the book showed stale/empty until the
  -- user typed in search (OnTextChanged re-renders). Refresh on EVERY show so the cards/tabs/bg are
  -- drawn no matter which path opened the window. RenderCards self-guards in combat (queues), so an
  -- in-combat secure Show just defers the reflow to PLAYER_REGEN_ENABLED.
  f:HookScript("OnShow", function() if SB.Refresh then guard("refresh", SB.Refresh) end end)

  -- DF modern close button (NE.chrome.Apply already built+modernized f.CloseButton). Belt here.
  guard("closeButton", function()
    if NE.panelchrome and NE.panelchrome.ModernizeCloseButton and f.CloseButton then
      NE.panelchrome.ModernizeCloseButton(f.CloseButton, { frameLevelBump = 20 })
    end
  end)

  -- A dark fill behind the content so no transparent backdrop shows between content and chrome.
  do
    local tint = f:CreateTexture(nil, "BACKGROUND")
    if tint.SetColorTexture then
      tint:SetColorTexture(0.04, 0.04, 0.05, 1)
    else
      tint:SetTexture(0.04, 0.04, 0.05, 1)
    end
    tint:SetPoint("TOPLEFT", SB.CHROME_L, -SB.CHROME_T)
    tint:SetPoint("BOTTOMRIGHT", -SB.CHROME_R, SB.CHROME_B)
    f.bgTint = tint
  end

  -- The minimize/maximize button.
  guard("minimize", function() buildMinimize(f) end)

  -- Window scale: fit the book to a fraction of the physical screen (see applyWindowScale). Best-
  -- effort now, then re-applied on every open (the resolution query is reliable by then). Bypasses
  -- PinPixelPerfect — for this big book a readable screen-fraction beats true pixel-perfect.
  guard("windowScale", function() applyWindowScale(f) end)
  f:HookScript("OnShow", function(self) applyWindowScale(self) end)

  -- Re-assert the background path on every open: the renderer hardcodes the BLP path (to dodge the
  -- Assets.lua registration race that caused black pages); this keeps it set as the GPU upload lands.
  f:HookScript("OnShow", function() if SB._reapplyBg then SB._reapplyBg() end end)

  return f
end
SB.BuildWindow = buildWindow

-- ----------------------------------------------------------------------------
-- SB.Host() — the content-root Frame the renderer parents everything to. Inset by the chrome
-- constants: TOPLEFT (CHROME_L, -CHROME_T) -> BOTTOMRIGHT (-CHROME_R, CHROME_B). Created once.
-- ----------------------------------------------------------------------------
function SB.Host()
  if SB.host then return SB.host end
  local f = SB.frame or buildWindow()
  if not f then return nil end
  local host = CreateFrame("Frame", "NE_SpellBookHost", f)
  host:ClearAllPoints()
  host:SetPoint("TOPLEFT", f, "TOPLEFT", SB.CHROME_L, -SB.CHROME_T)
  host:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -SB.CHROME_R, SB.CHROME_B)
  -- Above the bg tint; below the chrome nineslice/title/close (the renderer's cards sit here).
  host:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
  SB.host = host
  return host
end

-- ----------------------------------------------------------------------------
-- SB.ApplyWidth() — resize the window to (minimized and MIN_W or FRAME_W). Combat-guarded:
-- the renderer's spell cards are secure, so the window can become protected → SetWidth raises
-- in combat. Queue and re-apply at PLAYER_REGEN_ENABLED. Also syncs the minimize icon.
-- ----------------------------------------------------------------------------
function SB.ApplyWidth()
  local f = SB.frame
  if not f then return end
  if InCombatLockdown() then SB.refreshQueued = true; return end
  f:SetWidth(SB.minimized and SB.MIN_W or SB.FRAME_W)
  -- Keep the frame on screen after a width change.
  if NE.FrameUtil and NE.FrameUtil.KeepOnScreen then NE.FrameUtil.KeepOnScreen(f) end
  if f.minBtn and f.minBtn._syncIcon then f.minBtn._syncIcon() end
end

-- ----------------------------------------------------------------------------
-- SB.SetMinimized(bool) — set state, persist, ApplyWidth, then let the renderer reflow.
-- ----------------------------------------------------------------------------
function SB.SetMinimized(min)
  SB.minimized = min and true or false
  saveOpts()
  SB.ApplyWidth()
  if SB.Refresh then guard("refresh", SB.Refresh) end
end

-- ----------------------------------------------------------------------------
-- Show / hide. SetShown(true) also Refreshes (renderer reflows pages).
-- ----------------------------------------------------------------------------
function SB.SetShown(shown)
  local f = SB.frame or buildWindow()
  if not f then return end
  if shown then
    if InCombatLockdown() and f.IsProtected and f:IsProtected() then
      -- Insecure :Show() is swallowed on a protected frame in combat; the secure toggle path
      -- handles the key-driven open. Queue a refresh for when combat ends.
      SB.refreshQueued = true
    else
      f:Show()
      SB.ApplyWidth()
    end
    if SB.Refresh then guard("refresh", SB.Refresh) end
  else
    if InCombatLockdown() and f.IsProtected and f:IsProtected() then
      SB.refreshQueued = true
    else
      f:Hide()
    end
  end
end

function SB.Open()
  SB.SetShown(true)
end

function SB.Toggle()
  local f = SB.frame or buildWindow()
  if not f then return end
  if f:IsShown() then
    SB.SetShown(false)
  else
    SB.SetShown(true)
  end
end

-- ----------------------------------------------------------------------------
-- SECURE TOGGLE. The renderer's spell cards are SecureActionButtonTemplate, so the window can
-- become protected → an insecure :Show()/:Hide() is swallowed in combat. A SecureHandlerClick
-- snippet does the Show/Hide in the trusted environment; we override-bind TOGGLESPELLBOOK +
-- TOGGLEPETBOOK to click it (combat-deferred, refreshed on UPDATE_BINDINGS). ESC-close in
-- combat is driven off the frame's own OnShow/OnHide via a SecureHandlerWrapScript.
-- ----------------------------------------------------------------------------
local function ensureSecureToggle()
  if SB._secureToggle then return SB._secureToggle end
  local f = SB.frame or buildWindow()
  if not f then return nil end
  if not CreateFrame then return nil end
  local b = CreateFrame("Button", "NE_SpellBookSecureToggle", UIParent, "SecureHandlerClickTemplate")
  b:SetFrameRef("frame", f)
  b:SetAttribute("_onclick", [=[
    local frame = self:GetFrameRef("frame")
    if frame:IsShown() then
      frame:Hide()
    else
      frame:Show()
    end
  ]=])
  if b.RegisterForClicks then b:RegisterForClicks("AnyUp") end
  SB._secureToggle = b
  return b
end
SB.EnsureSecureToggle = ensureSecureToggle

-- Secure ESC-close: capture ESCAPE while shown (combat path), release on hide.
local function ensureSecureClose()
  if SB._secureClose then return SB._secureClose end
  local f = SB.frame or buildWindow()
  if not f then return nil end
  local c = CreateFrame("Button", "NE_SpellBookSecureClose", UIParent, "SecureHandlerClickTemplate")
  c:SetFrameRef("frame", f)
  c:SetAttribute("_onclick", [=[ self:GetFrameRef("frame"):Hide() ]=])
  if c.RegisterForClicks then c:RegisterForClicks("AnyUp") end
  if SecureHandlerWrapScript then
    SecureHandlerWrapScript(f, "OnShow", c, [=[
      control:SetBindingClick(true, "ESCAPE", "NE_SpellBookSecureClose")
    ]=])
    SecureHandlerWrapScript(f, "OnHide", c, [=[
      control:ClearBindings()
    ]=])
  end
  SB._secureClose = c
  return c
end
SB.EnsureSecureClose = ensureSecureClose

-- Override-bind the spellbook/pet-book keys to the secure toggle. Protected in combat → queue
-- for PLAYER_REGEN_ENABLED. Refreshed on UPDATE_BINDINGS.
local function applyKeyOverride()
  local b = ensureSecureToggle()
  if not (b and GetBindingKey and SetOverrideBindingClick) then return end
  if InCombatLockdown() then SB._rebindQueued = true; return end
  SB._rebindQueued = nil
  if ClearOverrideBindings then ClearOverrideBindings(b) end
  local function bind(binding)
    for _, k in ipairs({ GetBindingKey(binding) }) do
      if k then SetOverrideBindingClick(b, true, k, "NE_SpellBookSecureToggle", "LeftButton") end
    end
  end
  bind("TOGGLESPELLBOOK")
  bind("TOGGLEPETBOOK")
end
SB.ApplyKeyOverride = applyKeyOverride

-- ----------------------------------------------------------------------------
-- Intercept the Blizzard open: save SB._origToggle, reroute ToggleSpellBook to ours (the
-- OUT-OF-COMBAT path; the secure override binding shadows the KEY path in combat). Keep the
-- stock SpellBookFrame hidden if it tries to show out of combat.
-- ----------------------------------------------------------------------------
local function interceptBlizzard()
  if SB._intercepted then return end
  SB._intercepted = true

  if type(ToggleSpellBook) == "function" and not SB._origToggle then
    SB._origToggle = ToggleSpellBook
    -- TAINT: ToggleSpellBook is an INSECURE FrameXML toggle; the secure override binding shadows
    -- the key path so the tainted global is never on a combat path.
    ToggleSpellBook = function(bookType)
      SB.Toggle()
    end
  end

  local sbf = _G.SpellBookFrame
  if sbf and sbf.HookScript then
    sbf:HookScript("OnShow", function(self)
      if not InCombatLockdown() then self:Hide() end
    end)
  end
end
SB.InterceptBlizzard = interceptBlizzard

-- ----------------------------------------------------------------------------
-- Boot. PLAYER_LOGIN builds the window + Host, sets up the secure toggle + ToggleSpellBook
-- intercept + key overrides, then asks the renderer to build content (guarded — the renderer
-- file may load after this one). Live events refresh while shown; PLAYER_REGEN_ENABLED flushes
-- the queued refresh + re-applies width.
-- ----------------------------------------------------------------------------
local function boot(event)
  if event == "PLAYER_LOGIN" then
    loadOpts()                          -- restore persisted minimized state before first render
    buildWindow()
    SB.Host()                           -- create the content root the renderer parents to
    guard("secureToggle",  ensureSecureToggle)
    guard("secureClose",   ensureSecureClose)
    guard("intercept",     interceptBlizzard)
    guard("keyOverride",   applyKeyOverride)
    SB.ApplyWidth()                     -- size to the restored state
    if SB.Build then guard("build", SB.Build) end   -- renderer builds content (guarded)
    return
  end

  if event == "UPDATE_BINDINGS" then
    guard("keyOverride", applyKeyOverride)
    return
  end

  if event == "PLAYER_REGEN_ENABLED" then
    -- Combat ended: flush queued binding refresh, queued window refresh, re-apply width.
    if SB._rebindQueued then guard("keyOverride", applyKeyOverride) end
    if SB.refreshQueued then
      SB.refreshQueued = false
      SB.ApplyWidth()
      if SB.frame and SB.frame:IsShown() and SB.Refresh then guard("refresh", SB.Refresh) end
    end
    return
  end

  -- Live spell/bar/pet updates: refresh only while the window is shown.
  if SB.frame and SB.frame:IsShown() then
    if InCombatLockdown() then SB.refreshQueued = true; return end
    if SB.RenderCards and (event == "ACTIONBAR_SLOT_CHANGED" or event == "PET_BAR_UPDATE") then
      guard("renderCards", SB.RenderCards)   -- only glow/autocast state changed
      return
    end
    if SB.Refresh then guard("refresh", SB.Refresh) end
  end
end
SB.Boot = boot

if NE.modules and NE.modules.Register then
  NE.modules.Register(MODULE, {
    default  = true,
    label    = "Spellbook",
    category = "Windows",
    desc     = "The modern Dragonflight spellbook window. Disable to keep the stock Blizzard spellbook.",
    events   = {
      "PLAYER_LOGIN", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB", "ACTIONBAR_SLOT_CHANGED",
      "PET_BAR_UPDATE", "UNIT_PET", "PLAYER_LEVEL_UP", "PLAYER_REGEN_ENABLED", "UPDATE_BINDINGS",
    },
    onBoot = function(event) boot(event) end,
  })
else
  log("NE.modules.Register absent; spellbook window not booted")
end
