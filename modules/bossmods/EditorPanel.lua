-- DragonUI_NewEra/modules/bossmods/EditorPanel.lua — this frame's settings, on the frame, in edit mode.
--
-- The owner's ask, in their words: "the same as we do for the cooldown manager edit mode". So this is
-- deliberately NOT a new design — it is the Cooldown Manager's dialog (modules/cooldownviewer/
-- EditorPanel.lua) with this module's settings in it, reached the same way and built from the same
-- widgets, so the two behave identically when you click a handle.
--
-- WHAT IS SHARED, and why that is the whole point:
--   * The SEAM. NE.RegisterHUDFrame's `editorSettings` field — a callback, not a menu generator, so
--     integration/Register.lua's glue (the mouse handler, the edit-mode gate, the tooltip hint)
--     already works for us without a line of new host code. Either mouse button opens it, because
--     retail opens a system's dialog on SELECTION and left-click is what selects.
--   * The WIDGETS. NE.cooldownviewersettings.controls — the same checkbox / compact slider / dropdown
--     kit, with the same dialog theme. A second set would drift.
--   * The CHROME. Black at 0.8 inset 7 under the DiamondMetal "Dialog" nineslice, the same geometry
--     constants, drag-to-move, and the same "stop following the selection once you have placed it
--     yourself" behaviour.
--
-- WHAT IS DELIBERATELY SMALLER. The CDM dialog carries a modal confirm on its Reset button, because
-- Reset there discards a spell-by-spell setup that took real work to build and nothing can rebuild.
-- Reset here puts ten layout values back to a documented default, and Revert sits next to it for the
-- session. A modal for that is ceremony, so it is not ported; if this ever grows content-shaped
-- settings the CDM's ensureConfirm is the thing to lift.
--
-- Every page is one FRAME's settings — the timeline, or one of the three warning tiers — keyed by
-- the same frameID the settings store uses, so there is no second identity to keep in step.

local NE = DragonUI_NewEra
local BM = NE.bossmods
local L  = NE.L
if not BM then return end

-- Geometry, transcribed from retail's EditModeSystemSettingsDialog by way of the CDM dialog. Same
-- numbers on purpose: two dialogs opened from the same editor should not be different sizes.
local ROW_W, ROW_H = 343, 32
local LABEL_W   = 100
local CONTENT_X = 20
local PANEL_W   = ROW_W + (CONTENT_X * 2)
local BODY_TOP  = 43
local BTN_H     = 28
local BTN_GAP   = 3
local BTN_W     = math.floor((ROW_W - BTN_GAP) / 2)
local FOOTER_H  = 15 + BTN_H + 10
local SIDE_GAP  = 12

-- Left element of each pair is the STORED value and must stay English; only the right is shown.
local VIEW_TYPE   = { { "timeline", L["Timeline (rail)"] }, { "bars", L["Bars"] } }
-- "incombat" is retail's stored name for it; the label says what it actually keys on, which is
-- whether there are timers rather than the combat flag (see Register.lua).
local VISIBILITY  = { { "incombat", L["Only while timers are running"] }, { "always", L["Always"] } }
local ORIENTATION = { { "vertical", L["Vertical"] }, { "horizontal", L["Horizontal"] } }
local DIRECTION   = { { "right", L["Down / Right"] }, { "left", L["Up / Left"] } }
local TOOLTIPS    = { { "cursor", L["At the cursor"] }, { "default", L["Beside the frame"] },
                      { "hidden", L["Off"] } }

local function pct(v) return tostring(v) .. "%" end
local function px(v)  return tostring(v) .. "px" end

local panel                 -- the one dialog
local pages     = {}        -- frameID -> { body, col }
local current               -- frameID currently shown
local snapshots = {}        -- frameID -> values Revert goes back to, per editor session

-- Every key this dialog can write, per page type. Also what Revert snapshots — a fixed list rather
-- than "whatever is in the store", so a key that has never been written is still restored to what it
-- read when the editor opened.
local TIMELINE_KEYS = { "viewType", "orientation", "iconDirection", "visibility", "scale",
                        "iconSize", "opacity", "background", "length", "barWidth", "padding",
                        "flipHorizontal", "showTimer", "showSpellName", "showGlow", "tooltipAnchor" }
local WARNING_KEYS  = { "scale", "iconSize", "opacity", "showIcons" }

local function keysFor(frameID)
  return frameID == BM.TIMELINE_ID and TIMELINE_KEYS or WARNING_KEYS
end

local function labelFor(frameID)
  if frameID == BM.TIMELINE_ID then return L["Boss Abilities"] end
  for _, t in ipairs(BM.WARNING_TIERS or {}) do
    if t.id == frameID then return t.label end
  end
  return frameID
end

-- ── Revert ──────────────────────────────────────────────────────────────────────────────────────
--
-- "Revert Changes" means back to how this frame was when the editor was OPENED, not back to
-- defaults — that is the button beside it. Conflating the two is how someone loses a setup by
-- reaching for undo. Snapshot on first open per editor session; dropped when the editor closes.

local function snapshotOf(frameID)
  local t = {}
  for _, key in ipairs(keysFor(frameID)) do t[key] = BM.GetOpt(frameID, key) end
  return t
end

local function ensureSnapshot(frameID)
  if not snapshots[frameID] then snapshots[frameID] = snapshotOf(frameID) end
  return snapshots[frameID]
end

local function isDirty(frameID)
  local snap = snapshots[frameID]
  if not snap then return false end
  for _, key in ipairs(keysFor(frameID)) do
    if BM.GetOpt(frameID, key) ~= snap[key] then return true end
  end
  return false
end

local function revert(frameID)
  local snap = snapshots[frameID]
  if not snap then return end
  for _, key in ipairs(keysFor(frameID)) do BM.SetOpt(frameID, key, snap[key]) end
end

-- ── The dialog shell ────────────────────────────────────────────────────────────────────────────

local function ensurePanel()
  if panel then return panel end

  local f = CreateFrame("Frame", "NE_BossModsEditorPanel", UIParent)
  f:SetSize(PANEL_W, 200)
  -- Above the editor's own handles, which CreateUIFrame puts at FULLSCREEN. A settings dialog that
  -- renders behind the frame it configures is not a settings dialog.
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self._moved = true   -- once you place it yourself, it stops jumping to each frame you select
  end)
  f:Hide()

  local bg = f:CreateTexture(nil, "BACKGROUND", nil, -5)
  bg:SetTexture(0, 0, 0, 0.8)
  bg:SetPoint("TOPLEFT", 7, -7)
  bg:SetPoint("BOTTOMRIGHT", -7, 7)
  f.Bg = bg
  if NE.nineslice and NE.nineslice.ApplyLayout then
    pcall(NE.nineslice.ApplyLayout, f, "Dialog")
  end

  f.TitleText = f:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  f.TitleText:SetPoint("TOP", 0, -15)

  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT")
  local PC = NE.chrome
  if PC and PC.ModernizeCloseButton then
    pcall(PC.ModernizeCloseButton, close, { anchor = false })
  end
  close:SetScript("OnClick", function() BM.HideEditorPanel() end)
  f.CloseButton = close

  local function footerButton(label, onClick)
    local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    b:SetSize(BTN_W, BTN_H)
    b:SetText(label)
    b:SetScript("OnClick", function() if current then onClick(current) end end)
    if NE.button and NE.button.Skin then pcall(NE.button.Skin, b) end
    return b
  end

  f.buttonsDivider = f:CreateTexture(nil, "ARTWORK")
  f.buttonsDivider:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-OnlineDivider")
  f.buttonsDivider:SetSize(330, 16)
  f.buttonsDivider:SetPoint("BOTTOM", 0, 15 + BTN_H + 1)

  f.revertButton = footerButton(L["Revert Changes"], function(frameID)
    revert(frameID)
    BM.RefreshEditorPanel()
  end)
  f.revertButton:SetPoint("BOTTOMLEFT", CONTENT_X, 15)

  f.resetButton = footerButton(L["Reset to Default"], function(frameID)
    BM.ResetOpts(frameID)
    BM.RefreshEditorPanel()
  end)
  f.resetButton:SetPoint("BOTTOMRIGHT", -CONTENT_X, 15)

  -- Revert stays disabled until there IS something to revert. A button that is always live and
  -- usually does nothing teaches you to ignore it, and this one is the undo.
  function f.UpdateRevert()
    local on = current and isDirty(current)
    if on then f.revertButton:Enable() else f.revertButton:Disable() end
  end

  panel = f
  return f
end

-- ── One frame's page ────────────────────────────────────────────────────────────────────────────

local function buildPage(frameID)
  local Kit = NE.cooldownviewersettings and NE.cooldownviewersettings.controls
  if not (Kit and Kit.New) then return nil end

  local body = CreateFrame("Frame", nil, panel)
  body:SetPoint("TOPLEFT", panel, "TOPLEFT", CONTENT_X, -BODY_TOP)
  body:SetWidth(ROW_W)
  body:Hide()

  local col = Kit.New(body, ROW_W, {
    labelFont   = "GameFontHighlightMedium",
    checkSize   = 32,
    checkH      = ROW_H,
    sliderH     = ROW_H,
    dropH       = ROW_H,
    labelW      = LABEL_W,
    dropdownArt = true,
    buttonH     = BTN_H + 4,
    buttonArtH  = BTN_H,
  })

  local function getter(key) return function() return BM.GetOpt(frameID, key) end end
  -- Every write goes through here: store (which re-applies to the live frame), then this dialog's
  -- own Revert state.
  local function set(key)
    return function(v)
      BM.SetOpt(frameID, key, v)
      if panel and panel.UpdateRevert then panel.UpdateRevert() end
    end
  end
  -- The two view predicates, shared by every setting that only applies to one of them.
  local function timelineView() return BM.GetOpt(frameID, "viewType") ~= "bars" end
  local function barsView()     return BM.GetOpt(frameID, "viewType") == "bars" end

  local function boolGetter(key, default)
    return function()
      local v = BM.GetOpt(frameID, key)
      if v == nil then return default end
      return v and true or false
    end
  end

  if frameID == BM.TIMELINE_ID then
    col:AddDropdown({
      label = L["View"], values = VIEW_TYPE,
      -- Refreshes the whole page, not just itself: every `disabled` predicate below reads this
      -- value, and they are only re-evaluated on a Refresh.
      get = getter("viewType"),
      set = function(v) set("viewType")(v); BM.RefreshEditorPanel() end,
    })
    -- Both of these only mean anything on the rail, so they grey out in Bars view rather than
    -- vanishing — the page would otherwise reflow under the cursor as the View dropdown changes.
    -- The predicate is the kit's new `disabled` (SettingsControls.lua), which is this addon's
    -- equivalent of NewEra's `showWhen`.
    col:AddDropdown({
      label = L["Orientation"], values = ORIENTATION,
      desc  = L["Timeline view only. Which way the rail runs; the icons travel along it either way."],
      get = getter("orientation"), set = set("orientation"), disabled = barsView,
    })
    col:AddDropdown({
      label = L["Icon direction"], values = DIRECTION,
      desc  = L["Timeline view only. Which end of the rail is |cffffcc55now|r — the end abilities "
              .. "travel toward and go off at."],
      get = getter("iconDirection"), set = set("iconDirection"), disabled = barsView,
    })
    col:AddDropdown({
      label = L["Show the frame"], values = VISIBILITY,
      desc  = L["DBM raises a timer a little before a pull and for a few things outside combat — a "
              .. "queue, a break, a raid leader's own timer — so this follows the timers rather "
              .. "than your combat flag."],
      get = getter("visibility"), set = set("visibility"),
    })
    -- Ranges match NewEra's own popup (EditModeRegister.lua buildTimelineOptions) so a player who
    -- knows one knows the other. `Size` is retail's OverallSize, which that popup carried as its
    -- built-in Scale slider rather than an option row.
    col:AddCompactSlider({
      label = L["Size"], min = 50, max = 200, step = 5, format = pct,
      desc  = L["Scales the whole frame — the rail, the icons and the text together. Icon Size below "
              .. "scales only the icons."],
      get = getter("scale"), set = set("scale"),
    })
    col:AddCompactSlider({
      label = L["Icon size"], min = 50, max = 200, step = 10, format = pct,
      get = getter("iconSize"), set = set("iconSize"),
    })
    col:AddCompactSlider({
      label = L["Opacity"], min = 50, max = 100, step = 5, format = pct,
      get = getter("opacity"), set = set("opacity"),
    })
    col:AddCompactSlider({
      label = L["Background"], min = 0, max = 100, step = 5, format = pct,
      desc  = L["The plate behind the frame. Retail ships it invisible."],
      get = getter("background"), set = set("background"),
    })
    col:AddCompactSlider({
      label = L["Rail length"], min = 200, max = 800, step = 10, format = px,
      desc  = L["Timeline view only. How far out the rail reaches — the icons space themselves along it."],
      get = getter("length"), set = set("length"), disabled = barsView,
    })
    col:AddCompactSlider({
      label = L["Bar width"], min = 50, max = 200, step = 5, format = pct,
      desc  = L["Bars view only."],
      get = getter("barWidth"), set = set("barWidth"), disabled = timelineView,
    })
    col:AddCompactSlider({
      label = L["Space between bars"], min = 0, max = 20, step = 1, format = px,
      desc  = L["Bars view only."],
      get = getter("padding"), set = set("padding"), disabled = timelineView,
    })
    col:AddCheckbox({
      label = L["Flip horizontally"],
      desc  = L["Bars view only. Mirrors each row — the icon moves to the right and the bar drains "
              .. "the other way."],
      get = boolGetter("flipHorizontal", false), set = set("flipHorizontal"),
      disabled = timelineView,
    })
    col:AddCheckbox({
      label = L["Show the countdown"],
      get = boolGetter("showTimer", true), set = set("showTimer"),
    })
    col:AddCheckbox({
      label = L["Show the ability name"],
      desc  = L["Timeline view only — the bar list always names its abilities."],
      get = boolGetter("showSpellName", false), set = set("showSpellName"),
    })
    col:AddCheckbox({
      label = L["Glow when an ability is imminent"],
      desc  = L["On by default. The action-button proc glow, held for the last five seconds "
              .. "before an ability lands. It stands in for a retail effect this client cannot "
              .. "draw; with it off you get only the brief border flash, which is easy to miss."],
      get = boolGetter("showGlow", true), set = set("showGlow"),
    })
    col:AddDropdown({
      label = L["Tooltips"], values = TOOLTIPS,
      desc  = L["Hovering an ability shows its spell tooltip. DBM raises some timers that are not a "
              .. "spell at all — a pull timer, a phase change — and those show their own name instead."],
      get = getter("tooltipAnchor"), set = set("tooltipAnchor"),
    })
  else
    -- A warning tier carries the two settings that render (PORT_PLAN §C.1). This dialog is opened
    -- FROM a tier and so edits exactly that one — which is why it is the only place these live: the
    -- options page could address the tiers only as a group (PORT_PLAN §G.5).
    col:AddCompactSlider({
      label = L["Size"], min = 50, max = 200, step = 5, format = pct,
      desc  = L["Scales the whole warning — text and both flanking icons together."],
      get = getter("scale"), set = set("scale"),
    })
    col:AddCheckbox({
      label = L["Show the ability icons"],
      desc  = L["The two copies of the ability's own icon either side of the text — what retail "
              .. "draws. The text already names the ability, so this is decoration; turn it off for "
              .. "a plain line of text."],
      get = boolGetter("showIcons", true), set = set("showIcons"),
    })
    col:AddCompactSlider({
      label = L["Icon size"], min = 50, max = 200, step = 10, format = pct,
      desc  = L["The two spell icons either side of the text."],
      get = getter("iconSize"), set = set("iconSize"),
      disabled = function() return BM.GetOpt(frameID, "showIcons") == false end,
    })
    col:AddCompactSlider({
      label = L["Opacity"], min = 50, max = 100, step = 5, format = pct,
      get = getter("opacity"), set = set("opacity"),
    })
  end

  local page = { body = body, col = col }
  pages[frameID] = page
  return page
end

-- Place beside the frame being edited, on whichever side has room. Skipped once the player has
-- dragged the dialog somewhere themselves.
--
-- ANCHORED TO UIParent, NOT TO THE FRAME, for the reason the CDM dialog records: a relative point
-- keeps the dialog glued to the frame's edge, so dragging Icon Size or Rail Length resizes the frame
-- and slides the dialog sideways under the cursor mid-drag. Resolved once into screen coordinates.
local function place(f, anchor)
  if f._moved then return end
  f:ClearAllPoints()
  local sw = (UIParent and UIParent:GetWidth()) or 1024
  local cx    = anchor and anchor.GetCenter and select(1, anchor:GetCenter())
  local left  = anchor and anchor.GetLeft  and anchor:GetLeft()
  local right = anchor and anchor.GetRight and anchor:GetRight()
  local top   = anchor and anchor.GetTop   and anchor:GetTop()
  if not (cx and left and right and top) then
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  elseif cx > sw / 2 then
    f:SetPoint("TOPRIGHT", UIParent, "BOTTOMLEFT", left - SIDE_GAP, top)
  else
    f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", right + SIDE_GAP, top)
  end
end

-- ── API ─────────────────────────────────────────────────────────────────────────────────────────

function BM.ShowEditorPanel(frameID, anchor)
  if not frameID then return false end
  local f = ensurePanel()
  if not f then return false end

  local page = pages[frameID] or buildPage(frameID)
  if not page then return false end

  for id, p in pairs(pages) do
    if id ~= frameID then p.body:Hide() end
  end
  page.body:Show()
  current = frameID

  -- Re-read every control before showing: the options tab, a reset, or the other view can have moved
  -- these underneath us, and a dialog that opens on stale values is indistinguishable from one whose
  -- settings did not take.
  page.col:Refresh()
  local h = page.col:Relayout()

  f.TitleText:SetText(labelFor(frameID))
  f:SetHeight(BODY_TOP + h + 10 + FOOTER_H)

  ensureSnapshot(frameID)
  f.UpdateRevert()
  place(f, anchor)
  f:Show()
  return true
end

-- Re-read the open page. Used by the footer buttons, which change values without going through a
-- control's own setter.
function BM.RefreshEditorPanel()
  local page = current and pages[current]
  if not page then return end
  page.col:Refresh()
  if panel and panel.UpdateRevert then panel.UpdateRevert() end
end

-- Leaving the editor drops the Revert snapshots: "revert" means "back to how this was when I started
-- editing", and once you have left, that session is over. Keeping them would silently arm the button
-- with a state from an hour ago.
function BM.HideEditorPanel()
  snapshots = {}
  current = nil
  if panel then panel:Hide() end
end

BM.IsEditorPanelShown = function() return (panel and panel:IsShown()) and true or false end
BM._editorPanel = function() return panel, pages end   -- test seam
