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
-- and the module simply is not booted next reload. It ships OFF — this feature puts a new element
-- on screen mid-raid and depends on a third-party addon, so it waits to be asked, the same call the
-- Cooldown Manager made.
--
-- ONE SWITCH, TWO MODULES. The registry keeps `bossmods` and `bossmods_warnings` separate because
-- they are separate boot units with their own frames and their own `requires` edge, but the player
-- gets one control: the timers and the warnings are two halves of one feature, and two reload-gated
-- toggles for it is two reloads to turn it on. So SetEnabled writes both ids, and IsEnabled reads
-- the timers' — which is also the one `requires` makes authoritative, since the warnings cannot
-- boot without it either way.

function BM.IsEnabled() return NE.modules.IsEnabled("bossmods") and true or false end

function BM.SetEnabled(v)
  v = v and true or false
  NE.modules.SetEnabled("bossmods", v)
  NE.modules.SetEnabled("bossmods_warnings", v)
end

-- Hiding DBM's own display is NOT a setting. It follows whether our version is running: with the
-- rail up, DBM drawing the same timers beside it is the one outcome nobody wants, and with the rail
-- gone there is nothing to hide for. DBMAdapter's wantSuppression() reads IsBooted directly, so
-- there is no flag here to fall out of step with it.
--
-- Deliberately IsBooted and not IsEnabled: turning the switch off writes the flag but leaves this
-- session's frames drawing until the reload, so handing DBM its bars back at that moment would put
-- both on screen for the rest of the session. They come back together with our own going away.

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
--
-- LAYOUT SETTINGS ARE NOT HERE. Every appearance setting lives on the frame's own edit-mode dialog
-- (EditorPanel.lua), which is retail's arrangement and the Cooldown Manager's: you change the thing
-- while looking at it, next to the handle you just dragged. Duplicating them onto this page meant
-- two controls writing one value, one of which showed its effect on a frame you could not see —
-- and the warning tiers were worse still, since the page could only write all three at once while
-- the dialog edits the tier you opened it from.
--
-- What stays is what the editor cannot say: whether the module runs at all, and what it does to
-- DBM. Those are session/profile switches, not layout.

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
        .. "use it; the switches below are saved either way."])
    else
      C:AddDescription(scroll,
        L["Retail's boss ability timeline, drawn from |cffffcc55DBM's|r timers. Shows as a vertical "
        .. "rail of ability icons sliding toward now, or as a list of depleting bars. |cffffcc55Off "
        .. "by default.|r"])
    end

    C:AddToggle(scroll, {
      label   = L["Enable Boss Timers"],
      desc    = L["The timeline and the three warning lines together. While it is on, DBM's own "
                .. "bars and warnings are hidden so the same timers are not drawn twice — its "
                .. "sounds and voice packs are left alone. Off by default. Reload (/reload) to apply."],
      getFunc = function() return BM.IsEnabled() end,
      setFunc = function(v) BM.SetEnabled(v) end,
      requiresReload = true,
    })

    C:AddDescription(scroll,
      L["|cffffcc55Everything else is on the frames themselves.|r Open |cffffcc55/dragonui edit|r, "
      .. "click a Boss Timers handle, and its own dialog carries the view, size, length, opacity, "
      .. "tooltips and the rest — each warning tier included, edited from the tier you clicked."])

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
      -- Read from the adapter, not from a setting: there isn't one any more, and what this is for
      -- is telling you what is ACTUALLY happening to DBM's frames.
      .. ", hiding DBM's own " .. (BM.SuppressionActive and BM.SuppressionActive() and "yes" or "no") .. ".")
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
