-- DragonUI_NewEra/modules/bossmods/Register.lua — DragonUI wiring for the boss timers.
--
-- Replaces ReferenceAddons/NewEra/Alerts/BossMods/EditModeRegister.lua and the Edit Mode half of
-- Warnings.lua, both written against `NE.editmode` — a 6,441-line reimplementation of retail Edit
-- Mode this addon does not have and will not port. The two things those files delivered are
-- re-homed exactly as the Cooldown Manager port re-homed them:
--
--   position  -> DragonUI's editor, reached through NE.RegisterHUDFrame
--   settings  -> the New Era options tab, via NE.RegisterOptionSection
--
-- It also owns what the source kept at the bottom of BossMods.lua and Warnings.lua: the two
-- NE.modules.Register entries and their boot functions. They live here because booting is now
-- inseparable from registering the frames with DragonUI, which must happen at PLAYER_LOGIN.
--
-- THE DBM REQUIREMENT, mechanically: `requiresAddOn` on both registrations. core/Modules.lua's
-- dispatcher checks it before every boot (:180) and records the label in Mods.missingAddOn, so with
-- DBM absent neither module ever boots, no frame is built, nothing registers with the editor, and
-- the options section says why. This is existing addon machinery, not new gating.

local NE = DragonUI_NewEra
local BM = NE.bossmods
local L  = NE.L
if not (NE and BM) or NE.disabled then return end

local TIMELINE_ID = BM.TIMELINE_ID

-- ── Enable state ────────────────────────────────────────────────────────────────────────────────
--
-- Reload-gated, via the module registry (see core/Modules.lua's header): disabling writes the flag
-- and the module simply is not booted next reload. Both ship OFF — this feature puts a new element
-- on screen mid-raid and depends on a third-party addon, so it waits to be asked, the same call the
-- Cooldown Manager made.

function BM.IsEnabled()  return NE.modules.IsEnabled("bossmods") and true or false end
function BM.SetEnabled(v) NE.modules.SetEnabled("bossmods", v) end
function BM.AreWarningsEnabled()  return NE.modules.IsEnabled("bossmods_warnings") and true or false end
function BM.SetWarningsEnabled(v) NE.modules.SetEnabled("bossmods_warnings", v) end

-- Whether to hide DBM's own bars and warnings. Live, not reload-gated: it is one alpha write per
-- frame in either direction (DBMAdapter.lua), so there is nothing to defer.
function BM.IsSuppressionEnabled()
  local bm = BM.Store(false)
  if bm and bm.suppress ~= nil then return bm.suppress and true or false end
  return true   -- default ON: drawing both ours and DBM's is the one outcome nobody wants
end

function BM.SetSuppressionEnabled(v)
  local bm = BM.Store(true)
  if not bm then return end
  bm.suppress = v and true or false
  if v then
    if BM.ApplyDBMSuppression then BM.ApplyDBMSuppression() end
  elseif BM.ClearDBMSuppression then
    BM.ClearDBMSuppression()
  end
end

-- ── Boot: the timeline ──────────────────────────────────────────────────────────────────────────

local function bootTimeline(event)
  -- Re-pin on resolution / UI-scale change. core/Modules.lua re-invokes onBoot for every event a
  -- module registers, so this function is called for all three and must branch on which fired.
  if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    BM.Repin()
    return
  end
  if BM._timelineBooted then return end
  BM._timelineBooted = true

  local anchor = BM.GetAnchor()
  if not anchor then return end

  NE.RegisterHUDFrame({
    name  = "NE_BossModsAnchor",
    label = L["Boss Abilities"],
    frame = anchor,
    key   = "bossmods",
    -- Retail's EncounterTimeline preset position: BOTTOMRIGHT → UIParent.BOTTOM(-457, 336), which
    -- puts the rail slightly left of centre and clear of the action bars.
    defaultPoint = { point = "BOTTOMRIGHT", relativePoint = "BOTTOM", x = -457, y = 336 },
    -- The frame is empty outside an encounter, so the editor gets the same looping sample events
    -- retail's own Edit Mode shows (BM.SetEditActive → the EDIT_PREVIEW table).
    showTest = function() BM.SetEditActive(true) end,
    hideTest = function() BM.SetEditActive(false) end,
    -- Retail keeps a system's settings ON the frame in edit mode, not in a separate window, and the
    -- Cooldown Manager already works this way here. EditorPanel.lua builds the dialog; this hands it
    -- one opener. Either mouse button on the handle opens it (integration/Register.lua owns that).
    editorSettings = function(editorAnchor)
      if BM.ShowEditorPanel then BM.ShowEditorPanel(TIMELINE_ID, editorAnchor) end
    end,
    -- Leaving edit mode takes the dialog with it. HideAllEditableFrames calls this for every
    -- registered frame, so it fires whichever one was selected — and it is idempotent.
    onHide = function()
      if BM.HideEditorPanel then BM.HideEditorPanel() end
    end,
  })

  if BM.RegisterWithDBM then BM.RegisterWithDBM() end
  BM.ApplyConfig()
  if BM.ApplyDBMSuppression then BM.ApplyDBMSuppression() end
end

-- ── Boot: the warning tiers ─────────────────────────────────────────────────────────────────────

local function bootWarnings(event)
  if event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    BM.RepinWarnings()
    return
  end
  if BM._warningsBooted then return end
  BM._warningsBooted = true

  BM.EnsureWarningFrames()
  for _, t in ipairs(BM.WARNING_TIERS) do
    local f = BM.WarningFrame(t.key)
    if f then
      local key = t.key
      NE.RegisterHUDFrame({
        name  = "NE_" .. t.key .. "EncounterWarnings",
        label = t.label,
        frame = f,
        key   = "bossmods_warning_" .. t.key:lower(),
        defaultPoint = { point = "TOP", relativePoint = "TOP", x = 0, y = t.y },
        -- Warning frames are hidden until something fires, so without a preview their drag handles
        -- would sit over nothing. The preview also blocks live warnings from stomping the editor.
        showTest = function() BM.SetWarningEditActive(key, true) end,
        hideTest = function() BM.SetWarningEditActive(key, false) end,
        -- Per TIER, unlike the options page, which writes all three at once so one slider can mean
        -- "the warnings". Opened from a tier's own handle, it edits that tier.
        editorSettings = function(editorAnchor)
          if BM.ShowEditorPanel then BM.ShowEditorPanel(t.id, editorAnchor) end
        end,
        onHide = function()
          if BM.HideEditorPanel then BM.HideEditorPanel() end
        end,
      })
    end
  end

  BM.ApplyWarningConfig()
  -- The tiers' suppression flag is separate from the bars' (DBMAdapter reads IsBooted per module),
  -- so re-assert now that this one has booted.
  if BM.ApplyDBMSuppression then BM.ApplyDBMSuppression() end
end

-- ── Module registrations ────────────────────────────────────────────────────────────────────────

NE.modules.Register("bossmods", {
  default = false, label = L["Boss Timers"], category = "HUD",
  desc = L["Boss ability timers as a retail-style timeline or bar list. Reads its encounter data "
        .. "from DBM; without DBM installed there is nothing to show."],
  requiresAddOn = { label = "DBM", present = function() return BM.DBMPresent() end },
  events = { "PLAYER_LOGIN", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" },
  onBoot = bootTimeline,
})

NE.modules.Register("bossmods_warnings", {
  default = false, label = L["Boss Warnings"], category = "HUD",
  desc = L["Large on-screen warnings for important boss abilities. Needs DBM and the Boss Timers module."],
  requiresAddOn = { label = "DBM", present = function() return BM.DBMPresent() end },
  events = { "PLAYER_LOGIN", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" },
  onBoot = bootWarnings,
  requires = { "bossmods" },
})

-- ── Options ─────────────────────────────────────────────────────────────────────────────────────

-- Read/write one timeline setting.
local function get(key) return function() return BM.GetOpt(TIMELINE_ID, key) end end
local function set(key) return function(v) BM.SetOpt(TIMELINE_ID, key, v) end end

-- The warning tiers share one editor per setting rather than three. DOWNPORT: retail gives each
-- tier its own Edit Mode dialog, which is where the source's per-tier options lived. On a single
-- options page three identical sliders labelled Critical/Medium/Minor is a worse trade than one
-- that means "the warnings", so this writes all three.
local function getWarning(key)
  return function() return BM.GetOpt(BM.WARNING_TIERS[1].id, key) end
end
local function setWarning(key)
  return function(v)
    for _, t in ipairs(BM.WARNING_TIERS) do BM.SetOpt(t.id, key, v) end
  end
end

NE.RegisterOptionSection({
  id    = "bossmods",
  order = 46,
  build = function(scroll, C)
    if C.AddSpacer then C:AddSpacer(scroll) end
    C:AddHeading(scroll, L["Boss Timers"])

    if not BM.DBMPresent() then
      C:AddDescription(scroll,
        L["|cffff5555DBM is not installed.|r This module renders boss ability timers, it does not "
        .. "detect them — the encounter data comes from Deadly Boss Mods. Install DBM and reload to "
        .. "use it; the settings below are saved either way."])
    else
      C:AddDescription(scroll,
        L["Retail's boss ability timeline, drawn from |cffffcc55DBM's|r timers. Shows as a vertical "
        .. "rail of ability icons sliding toward now, or as a list of depleting bars. |cffffcc55Off "
        .. "by default.|r Drag it with DragonUI's editor mode to reposition it."])
    end

    C:AddToggle(scroll, {
      label   = L["Enable Boss Timers"],
      desc    = L["Off by default. Reload (/reload) to apply."],
      getFunc = function() return BM.IsEnabled() end,
      setFunc = function(v) BM.SetEnabled(v) end,
      requiresReload = true,
    })

    C:AddToggle(scroll, {
      label   = L["Enable Boss Warnings"],
      desc    = L["The three large on-screen warning lines. Needs Boss Timers on. Reload (/reload) to apply."],
      getFunc = function() return BM.AreWarningsEnabled() end,
      setFunc = function(v) BM.SetWarningsEnabled(v) end,
      requiresReload = true,
    })

    C:AddToggle(scroll, {
      label   = L["Hide DBM's own bars and warnings"],
      desc    = L["On by default, and the reason this does not simply double up on screen. DBM's "
                .. "sounds and voice packs are left alone either way — only what it DRAWS is hidden."],
      getFunc = function() return BM.IsSuppressionEnabled() end,
      setFunc = function(v) BM.SetSuppressionEnabled(v) end,
    })

    if not (C.AddSlider and C.AddDropdown) then
      C:AddDescription(scroll, L["The layout settings need a newer DragonUI options panel (AddSlider/AddDropdown)."])
      return
    end

    if C.AddSpacer then C:AddSpacer(scroll) end
    C:AddHeading(scroll, L["Appearance"])

    C:AddDropdown(scroll, {
      label   = L["View"],
      values  = { timeline = L["Timeline (rail)"], bars = L["Bars"] },
      getFunc = get("viewType"), setFunc = set("viewType"),
    })

    C:AddDropdown(scroll, {
      label   = L["Orientation"],
      values  = { vertical = L["Vertical"], horizontal = L["Horizontal"] },
      getFunc = get("orientation"), setFunc = set("orientation"),
    })

    C:AddDropdown(scroll, {
      label   = L["Icon direction"],
      values  = { right = L["Down / Right"], left = L["Up / Left"] },
      getFunc = get("iconDirection"), setFunc = set("iconDirection"),
    })

    -- The stored value is still "incombat" (retail's "In Encounter"), but the LABEL now says what
    -- the code does: the frame follows whether there is anything to show, not UnitAffectingCombat.
    -- That is the right behaviour and not worth "fixing" into a literal combat check — a pull timer
    -- runs before combat starts, which is exactly when you want to see it.
    C:AddDropdown(scroll, {
      label   = L["Show the frame"],
      desc    = L["DBM raises a timer a little before a pull and for a few things outside combat — a "
                .. "queue, a break, a raid leader's own timer — so this follows the timers rather "
                .. "than your combat flag."],
      values  = { incombat = L["Only while timers are running"], always = L["Always"] },
      getFunc = get("visibility"), setFunc = set("visibility"),
    })

    C:AddDropdown(scroll, {
      label   = L["Tooltips"],
      values  = { cursor = L["At the cursor"], default = L["Beside the frame"], hidden = L["Off"] },
      getFunc = get("tooltipAnchor"), setFunc = set("tooltipAnchor"),
    })

    C:AddSlider(scroll, {
      label   = L["Icon size"], min = 50, max = 150, step = 5,
      getFunc = get("iconSize"), setFunc = set("iconSize"),
    })

    C:AddSlider(scroll, {
      label   = L["Opacity"], min = 50, max = 100, step = 5,
      getFunc = get("opacity"), setFunc = set("opacity"),
    })

    C:AddSlider(scroll, {
      -- The rail's shadow plate / the bars' backing plate. Retail ships this invisible.
      label   = L["Background"], min = 0, max = 100, step = 5,
      getFunc = get("background"), setFunc = set("background"),
    })

    C:AddSlider(scroll, {
      label    = L["Rail length"], min = 200, max = 800, step = 10,
      getFunc  = get("length"), setFunc = set("length"),
      disabled = function() return BM.GetOpt(TIMELINE_ID, "viewType") == "bars" end,
    })

    C:AddSlider(scroll, {
      label    = L["Bar width"], min = 50, max = 150, step = 5,
      getFunc  = get("barWidth"), setFunc = set("barWidth"),
      disabled = function() return BM.GetOpt(TIMELINE_ID, "viewType") ~= "bars" end,
    })

    C:AddSlider(scroll, {
      label    = L["Space between bars"], min = 0, max = 20, step = 1,
      getFunc  = get("padding"), setFunc = set("padding"),
      disabled = function() return BM.GetOpt(TIMELINE_ID, "viewType") ~= "bars" end,
    })

    C:AddToggle(scroll, {
      label   = L["Flip horizontally"],
      desc    = L["Bars view only. Mirrors each row — the icon moves to the right and the bar drains "
                .. "the other way."],
      getFunc = function() return BM.GetOpt(TIMELINE_ID, "flipHorizontal") == true end,
      setFunc = set("flipHorizontal"),
    })

    C:AddToggle(scroll, {
      label   = L["Show the countdown"],
      getFunc = function() return BM.GetOpt(TIMELINE_ID, "showTimer") ~= false end,
      setFunc = set("showTimer"),
    })

    C:AddToggle(scroll, {
      label   = L["Show the ability name"],
      desc    = L["Timeline view only — the bar list always names its abilities."],
      getFunc = function() return BM.GetOpt(TIMELINE_ID, "showSpellName") == true end,
      setFunc = set("showSpellName"),
    })

    C:AddToggle(scroll, {
      label   = L["Glow when an ability is imminent"],
      desc    = L["On by default. The action-button proc glow, held for the last five seconds "
                .. "before an ability lands. It stands in for a retail effect this client cannot "
                .. "draw; with it off you get only the brief border flash, which is easy to miss."],
      getFunc = function() return BM.GetOpt(TIMELINE_ID, "showGlow") ~= false end,
      setFunc = set("showGlow"),
    })

    if C.AddSpacer then C:AddSpacer(scroll) end
    C:AddHeading(scroll, L["Boss Warnings"])

    C:AddToggle(scroll, {
      label   = L["Show the ability icons"],
      desc    = L["The two copies of the ability's own icon either side of the text — what retail "
                .. "draws. The text already names the ability, so this is decoration; turn it off for "
                .. "a plain line of text."],
      getFunc = function() return BM.GetOpt(BM.WARNING_TIERS[1].id, "showIcons") ~= false end,
      setFunc = setWarning("showIcons"),
    })

    C:AddSlider(scroll, {
      label   = L["Warning icon size"], min = 50, max = 200, step = 5,
      getFunc = getWarning("iconSize"), setFunc = setWarning("iconSize"),
    })

    C:AddSlider(scroll, {
      label   = L["Warning opacity"], min = 50, max = 100, step = 5,
      getFunc = getWarning("opacity"), setFunc = setWarning("opacity"),
    })

    if C.AddButton then
      C:AddButton(scroll, {
        label    = L["Show a test timer"],
        desc     = L["Runs four sample timers and one warning through the same path a real DBM "
                   .. "timer takes, so what you see is what an encounter will look like."],
        callback = function() BM.RunTestFeed() end,
      })
    end
  end,
})

-- ── Slash command ───────────────────────────────────────────────────────────────────────────────
--
-- Sitting through a boss pull to check a layout change is not a workable loop, and the test feed
-- deliberately ignores the enable flag: running it is an explicit request.

SLASH_NEBOSSMODS1 = "/nebossmods"
SlashCmdList["NEBOSSMODS"] = function(msg)
  msg = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if msg == "test" then
    BM.RunTestFeed()
    return
  end

  if msg == "bars" or msg == "timeline" then
    BM.SetOpt(TIMELINE_ID, "viewType", msg)
    print("|cff1784d1BossTimers|r view: " .. msg)
    return
  end

  if msg == "debug" then
    BM.Dump()
    return
  end

  -- Show one warning per tier and leave them up long enough to look at. The tiers are transient by
  -- design (3s), which makes "it flashed" and "it rendered wrong" hard to tell apart at speed.
  if msg == "warn" then
    for _, t in ipairs(BM.WARNING_TIERS) do
      BM.ShowWarning(t.key, t.label .. " — sample text", nil, "Interface\\Icons\\Spell_Shadow_ShadowBolt", 30)
    end
    print("|cff1784d1BossTimers|r all three tiers up for 30s — run |cffffcc55/nebossmods debug|r while they show.")
    return
  end

  if msg == "status" then
    print("|cff1784d1BossTimers|r DBM " .. (BM.DBMPresent() and "|cff55ff55found|r" or "|cffff5555not installed|r")
      .. ", timers " .. (NE.modules.IsBooted("bossmods") and "on" or "off")
      .. ", warnings " .. (NE.modules.IsBooted("bossmods_warnings") and "on" or "off")
      .. ", view " .. tostring(BM.GetOpt(TIMELINE_ID, "viewType"))
      .. ", hiding DBM's own " .. (BM.IsSuppressionEnabled() and "yes" or "no") .. ".")
    return
  end

  print("|cff1784d1BossTimers|r usage:")
  print("  /nebossmods test      run four sample timers and a warning through the live path")
  print("  /nebossmods warn      hold all three warning tiers on screen for 30s")
  print("  /nebossmods timeline  switch to the rail view")
  print("  /nebossmods bars      switch to the bar list view")
  print("  /nebossmods status    what is installed, booted and configured")
  print("  /nebossmods debug     dump live frame state (run it while something is showing)")
end

-- ── QA harness ──────────────────────────────────────────────────────────────────────────────────

if NE.qa then
  NE.qa.modules = NE.qa.modules or {}
  table.insert(NE.qa.modules, {
    name  = "Boss Timers",
    frame = nil,   -- built at boot; the harness reads open/close rather than the frame here
    open  = function() BM.RunTestFeed() end,
    close = function()
      if BM._testOwner then BM.BusStopAll(BM._testOwner) end
    end,
  })
end
