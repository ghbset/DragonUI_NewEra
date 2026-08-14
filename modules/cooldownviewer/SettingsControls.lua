-- DragonUI_NewEra/modules/cooldownviewer/SettingsControls.lua — the control kit behind the /cdm
-- Settings tab.
--
-- WHY A KIT, AND NOT DragonUI's PanelControls. The options-tab helpers (Controls:AddToggle /
-- AddSlider / AddDropdown in DragonUI_Options/panel/controls.lua) are AceGUI widgets: they only lay
-- themselves out inside an AceGUI container, and they call `parent:AddChild(...)`. Our panel body is
-- a plain ScrollFrame over a plain Frame, so there is no container to hand them — and DragonUI is
-- read-only to us (CONTRACTS §0), so teaching its controls to render into a raw frame is not on the
-- table. This is the three widgets the settings page actually needs, over the client's own
-- templates: UICheckButtonTemplate, OptionsSliderTemplate and a menu button through core/Menu.lua.
--
-- NO WowStyle1DropdownTemplate, for the same reason the footer has none (PORT_PLAN §G.11): it is
-- retail-only. A dropdown here is a plain button labelled with the current value that opens a radio
-- menu — the widget differs, the behaviour does not.
--
-- SHAPE. `Kit.New(parent, width)` returns a column with a y cursor. Every Add* appends a
-- fixed-height row and returns it; `col:Relayout()` stacks the visible rows and sizes `parent` so
-- the scrollbar learns the extent. Sections are collapsible, and a collapsed section's rows are
-- HIDDEN rather than destroyed — the same pooling contract the category grids use, and what makes
-- collapsing free of any rebuild.
--
-- EVERY CONTROL KEEPS A `refresh` CLOSURE that re-reads its own getter, and `col:Refresh()` runs all
-- of them. That is what keeps the page honest when a setting changes from somewhere that is not this
-- page: a layout apply, the master toggle in DragonUI's options, a reset. A page that only wrote
-- would drift silently, and a stale checkbox is indistinguishable from a setting that did not take.
--
-- Taint: plain frames and SavedVariables writes. Nothing here is secure or protected.

local NE = DragonUI_NewEra

NE.cooldownviewersettings = NE.cooldownviewersettings or {}
local CDS = NE.cooldownviewersettings

local Kit = {}
CDS.controls = Kit

local ROW_INDENT   = 6     -- rows inside a section sit in a little from the header
local HEADER_H     = 24
local CHECK_H      = 26
local SLIDER_H     = 46
local DROPDOWN_H   = 28
local BUTTON_H     = 30
local SECTION_GAP  = 10

-- OptionsSliderTemplate finds its Low/High/Text FontStrings through $parent name lookups, so every
-- slider needs a global name. UIPanelButtonTemplate does not, but naming both keeps /framestack
-- readable when something is mis-anchored.
local serial = 0
local function nextName(kind)
  serial = serial + 1
  return "NE_CDMSetting" .. kind .. serial
end

local function tip(frame, title, text)
  if not title then return end
  frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(title)
    if text then GameTooltip:AddLine(text, 1, 1, 1, true) end
    GameTooltip:Show()
  end)
  frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function labelFor(values, v)
  for _, e in ipairs(values) do
    if e[1] == v then return e[2] end
  end
  return tostring(v)
end

-- Slider values arrive continuous from a drag on this client — SetObeyStepOnDrag is retail-only, and
-- SetValueStep alone only governs the arrow keys. So the step is applied here, on the way in, which
-- is what Blizzard's own option sliders do.
local function snap(v, step, minV)
  if not step or step <= 0 then return v end
  return minV + math.floor((v - minV) / step + 0.5) * step
end

-- ── Column ──────────────────────────────────────────────────────────────────────────────────────

local Column = {}
Column.__index = Column

-- A THEME, not a second kit. The Settings tab is a scrolling page of sections; the edit-mode dialog
-- is a fixed panel of 32px rows transcribed from retail's EditModeSystemSettingsDialog. Same widgets,
-- different metrics and fonts — so the differences live in one table the caller passes, and every
-- default here is exactly what the tab already had.
local DEFAULT_THEME = {
  labelFont  = "GameFontHighlightSmall",
  checkSize  = 24,
  checkH     = CHECK_H,
  sliderH    = DROPDOWN_H,
  dropH      = DROPDOWN_H,
  labelW     = 96,          -- the control column's left edge (compact slider + art dropdown)
  controlW   = nil,         -- fixed control width; nil = fill the control column
  dropdownArt = false,      -- true = the modern textholder + arrow, instead of a red panel button
  -- The BigRedThreeSlice is the addon's standard button (core/ButtonSkin.lua), so this is ON by
  -- default and the flag exists to opt a row OUT, not in.
  buttonArt   = true,
  buttonH     = nil,        -- row height for AddButton; nil = BUTTON_H
  buttonArtH  = nil,        -- the button's own height inside that row; nil = 22
}

function Kit.New(parent, width, theme)
  local t = {}
  for k, v in pairs(DEFAULT_THEME) do t[k] = v end
  for k, v in pairs(theme or {}) do t[k] = v end
  local col = setmetatable({
    frame    = parent,
    width    = width or 330,
    theme    = t,
    entries  = {},          -- ordered rows: { frame =, h =, section =, gap =, indent = }
    sections = {},
    refreshers = {},
  }, Column)
  return col
end

function Column:_add(frame, h, opts)
  opts = opts or {}
  self.entries[#self.entries + 1] = {
    frame  = frame,
    h      = h,
    -- A row belongs to whatever section was opened last. Rows added before the first AddSection
    -- (the page's intro text) have no section and are therefore never collapsible.
    section = opts.standalone and nil or self._section,
    gap    = opts.gap or 0,
    indent = opts.indent or (self._section and ROW_INDENT or 0),
  }
  return frame
end

function Column:_row(kind, h, opts)
  local f = CreateFrame(kind or "Frame", nil, self.frame)
  f:SetHeight(h)
  f:SetWidth(self.width - ((opts and opts.indent) or (self._section and ROW_INDENT or 0)))
  self:_add(f, h, opts)
  return f
end

function Column:Relayout()
  local y = 0
  for _, e in ipairs(self.entries) do
    local visible = (not e.section) or e.section.expanded
    if visible then
      y = y + e.gap
      e.frame:ClearAllPoints()
      e.frame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", e.indent, -y)
      e.frame:Show()
      y = y + e.h
    else
      e.frame:Hide()
    end
  end
  -- The trailing pad stops the last row butting against the footer.
  self.frame:SetHeight(math.max(1, y + 10))
  self._height = y
  return y
end

function Column:Refresh()
  for _, fn in ipairs(self.refreshers) do fn() end
end

-- ── Conditional enable (`o.disabled`) ───────────────────────────────────────────────────────────
--
-- A predicate, re-evaluated on every Refresh: a setting that does not apply right now greys out
-- rather than vanishing, so the page does not reflow under the cursor as a neighbouring dropdown
-- changes. Retail does the same for its per-view settings, and NewEra's own edit-mode popup did it
-- with `showWhen` predicates (ReferenceAddons/NewEra/Alerts/BossMods/EditModeRegister.lua) — this is
-- that idea, kept in one place so every control gets it instead of each caller reinventing it.
--
-- Every existing caller is unaffected: with no `o.disabled` the gate is never installed.
--
-- Dimming is applied to the row AND its child frames explicitly. On 3.3.5a a parent's alpha is not
-- dependably inherited by child frames (see modules/bossmods/PORT_PLAN.md §C.5d), so dimming the row
-- alone can leave a slider or a dropdown trigger at full brightness inside a greyed-out row.
local DISABLED_ALPHA = 0.4

local function dim(row, on)
  local a = on and DISABLED_ALPHA or 1
  row:SetAlpha(a)
  if row.GetChildren then
    for _, kid in ipairs({ row:GetChildren() }) do
      if kid.SetAlpha then kid:SetAlpha(a) end
    end
  end
end

-- `interactives` are the widgets that must stop responding — the slider, the nudge arrows, the
-- dropdown trigger, the checkbox. Disabling them is what makes this more than a visual hint.
function Column:_gate(o, row, interactives)
  if type(o.disabled) ~= "function" then return end
  local function gate()
    local off = o.disabled() and true or false
    if row._neDisabled == off then return end   -- idempotent: Refresh runs on every open
    row._neDisabled = off
    dim(row, off)
    for _, w in ipairs(interactives) do
      if w then
        if off then
          if w.Disable then w:Disable() end
        elseif w.Enable then
          w:Enable()
        end
      end
    end
  end
  gate()
  self.refreshers[#self.refreshers + 1] = gate
  row.IsGatedOff = function() return row._neDisabled and true or false end
end

-- ── Section header ──────────────────────────────────────────────────────────────────────────────
-- Same look as the category headers next door (a faint bar with the client's own +/- glyph), because
-- the two tabs are the same window and a settings section that styled itself differently would read
-- as belonging to a different addon.

function Column:AddSection(title, expanded)
  local section = { expanded = expanded and true or false, title = title }
  self.sections[#self.sections + 1] = section

  self._section = nil          -- the header itself is never inside the section it opens
  local h = self:_row("Button", HEADER_H, { gap = SECTION_GAP, indent = 0 })
  self._section = section
  section.header = h

  local bg = h:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetTexture(1, 1, 1, 0.06)

  h.Toggle = h:CreateTexture(nil, "ARTWORK")
  h.Toggle:SetSize(16, 16)
  h.Toggle:SetPoint("LEFT", h, "LEFT", 4, 0)

  h.Text = h:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h.Text:SetPoint("LEFT", h.Toggle, "RIGHT", 4, 0)
  h.Text:SetText(title)

  local function paint()
    h.Toggle:SetTexture(section.expanded and "Interface\\Buttons\\UI-MinusButton-Up"
                                          or "Interface\\Buttons\\UI-PlusButton-Up")
  end
  paint()

  h:SetScript("OnClick", function()
    section.expanded = not section.expanded
    paint()
    self:Relayout()
  end)

  section.SetExpanded = function(_, on)
    section.expanded = on and true or false
    paint()
  end
  return section
end

-- Ends the current section, so a following row is top-level again.
function Column:EndSection()
  self._section = nil
end

-- ── Description text ────────────────────────────────────────────────────────────────────────────

function Column:AddText(text, opts)
  opts = opts or {}
  local indent = opts.indent or (self._section and ROW_INDENT or 0)
  local f = CreateFrame("Frame", nil, self.frame)
  f:SetWidth(self.width - indent)

  local fs = f:CreateFontString(nil, "ARTWORK", opts.font or "GameFontDisableSmall")
  fs:SetPoint("TOPLEFT")
  fs:SetWidth(self.width - indent - 4)
  fs:SetJustifyH("LEFT")
  fs:SetText(text)

  -- GetStringHeight is only meaningful once the text and width are set; the floor covers the offline
  -- harness, whose FontString stub cannot measure.
  local h = math.max(14, (fs.GetStringHeight and fs:GetStringHeight() or 0) + 2)
  f:SetHeight(h)
  f.Text = fs
  self:_add(f, h, { gap = opts.gap or 2, indent = indent })
  return f
end

-- ── Checkbox ────────────────────────────────────────────────────────────────────────────────────
-- o = { label, desc, get, set, onChanged }

function Column:AddCheckbox(o)
  local th = self.theme
  local row = self:_row("Button", th.checkH)

  local cb = CreateFrame("CheckButton", nextName("Check"), row, "UICheckButtonTemplate")
  cb:SetSize(th.checkSize, th.checkSize)
  cb:SetPoint("LEFT", row, "LEFT", 0, 0)

  local label = row:CreateFontString(nil, "ARTWORK", th.labelFont)
  label:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  label:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  label:SetJustifyH("LEFT")
  label:SetText(o.label or "")

  local function refresh()
    cb:SetChecked(o.get and o.get() and true or false)
  end

  local function apply(on)
    cb:SetChecked(on)
    if o.set then o.set(on) end
    if PlaySound then
      PlaySound(on and "igMainMenuOptionCheckBoxOn" or "igMainMenuOptionCheckBoxOff")
    end
    if o.onChanged then o.onChanged(on) end
  end

  -- UICheckButtonTemplate has already flipped its own state by the time OnClick runs, so the box
  -- reports the NEW value; the row has not, so it flips the current one. Both land in `apply`, which
  -- is the only thing that writes.
  cb:SetScript("OnClick", function(self) apply(self:GetChecked() and true or false) end)
  row:SetScript("OnClick", function() apply(not (cb:GetChecked() and true or false)) end)

  tip(cb, o.label, o.desc)
  refresh()
  self.refreshers[#self.refreshers + 1] = refresh
  self:_gate(o, row, { cb, row })
  row.Check, row.Label, row.Refresh = cb, label, refresh
  return row
end

-- ── Slider ──────────────────────────────────────────────────────────────────────────────────────
-- o = { label, desc, min, max, step, get, set, format }

function Column:AddSlider(o)
  local row = self:_row("Frame", SLIDER_H)
  local minV, maxV, step = o.min or 0, o.max or 100, o.step or 1

  local label = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  label:SetPoint("TOPLEFT", row, "TOPLEFT", 2, -2)
  label:SetJustifyH("LEFT")
  label:SetText(o.label or "")

  local value = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  value:SetPoint("TOPRIGHT", row, "TOPRIGHT", -4, -2)
  value:SetJustifyH("RIGHT")

  local name = nextName("Slider")
  local sl = CreateFrame("Slider", name, row, "OptionsSliderTemplate")
  sl:SetPoint("TOPLEFT", row, "TOPLEFT", 6, -20)
  sl:SetWidth(self.width - (self._section and ROW_INDENT or 0) - 24)
  sl:SetMinMaxValues(minV, maxV)
  sl:SetValueStep(step)
  if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end

  -- The template's own three FontStrings: $parentText sits centred ABOVE the bar, which would
  -- duplicate our label, so it is blanked. Low/High carry the range.
  local function templateText(suffix, text)
    local fs = _G[name .. suffix]
    if fs and fs.SetText then fs:SetText(text) end
  end
  templateText("Text", "")
  templateText("Low",  tostring(minV))
  templateText("High", tostring(maxV))

  local function fmt(v)
    if o.format then return o.format(v) end
    return tostring(v)
  end

  local function refresh()
    local cur = snap(o.get and o.get() or minV, step, minV)
    sl._neSuppress = true
    sl:SetValue(cur)
    sl._neSuppress = false
    sl._neVal = cur
    value:SetText(fmt(cur))
  end

  sl:SetScript("OnValueChanged", function(self, raw)
    if self._neSuppress then return end
    local v = snap(raw or minV, step, minV)
    if v < minV then v = minV elseif v > maxV then v = maxV end
    -- Re-seat the thumb on the snapped value. Guarded, or this SetValue re-enters us.
    if v ~= raw then
      self._neSuppress = true
      self:SetValue(v)
      self._neSuppress = false
    end
    value:SetText(fmt(v))
    -- Only WRITE on a real change. A drag fires this continuously, and every write re-runs the
    -- viewer's RefreshLayout — which relays out every icon.
    if self._neVal ~= v then
      self._neVal = v
      if o.set then o.set(v) end
      if o.onChanged then o.onChanged(v) end
    end
  end)

  -- The minimal bar: retail's MinimalSliderWithSteppers art, rebuilt piece by piece in
  -- core/ScrollbarReskin.lua. Scripts are none of its business — it swaps textures and sizes the
  -- frame — so it can sit here rather than dodging tip()'s SetScript below.
  if NE.scrollbar and NE.scrollbar.SkinSlider then pcall(NE.scrollbar.SkinSlider, sl) end

  tip(sl, o.label, o.desc)
  refresh()
  self.refreshers[#self.refreshers + 1] = refresh
  self:_gate(o, row, { sl, row.Left, row.Right })
  row.Slider, row.Label, row.Value, row.Refresh = sl, label, value, refresh
  return row
end

-- ── Compact slider ──────────────────────────────────────────────────────────────────────────────
-- o = { label, desc, min, max, step, get, set, format, labelWidth }
--
-- One line: label, a nudge arrow, the bar, the other arrow, the value. The tab's tall two-line slider
-- is right for a page you scroll; it is wrong for the edit-mode dialog, which sits ON the screen next
-- to the frame it edits and has to stay small enough to see past.
--
-- THE ARROWS ARE NOT DECORATION. A drag on this client reports continuous values (SetObeyStepOnDrag is
-- retail-only), so landing on an exact 65% by hand is luck. The arrows step by exactly `step`, which is
-- the only precise way to set one of these — retail's edit-mode sliders have them for the same reason.

local ARROW_W, VALUE_W, LABEL_W = 18, 44, 96

function Column:AddCompactSlider(o)
  local th = self.theme
  local row = self:_row("Frame", th.sliderH)
  local minV, maxV, step = o.min or 0, o.max or 100, o.step or 1
  local labelW = o.labelWidth or th.labelW or LABEL_W
  local rowW = self.width - (self._section and ROW_INDENT or 0)

  local label = row:CreateFontString(nil, "ARTWORK", th.labelFont)
  label:SetPoint("LEFT", row, "LEFT", 2, 0)
  label:SetWidth(labelW)
  label:SetJustifyH("LEFT")
  label:SetText(o.label or "")

  local value = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  value:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  value:SetWidth(VALUE_W)
  value:SetJustifyH("RIGHT")

  local name = nextName("CSlider")
  local sl = CreateFrame("Slider", name, row, "OptionsSliderTemplate")
  sl:SetPoint("LEFT", row, "LEFT", labelW + ARROW_W + 6, 0)
  sl:SetWidth(math.max(40, rowW - labelW - VALUE_W - (ARROW_W * 2) - 14))
  sl:SetMinMaxValues(minV, maxV)
  sl:SetValueStep(step)
  if sl.SetObeyStepOnDrag then sl:SetObeyStepOnDrag(true) end

  -- All three of the template's own FontStrings are blanked here: Low/High would collide with the
  -- label and the value at this width, and Text sits centred above the bar with nowhere to go.
  for _, suffix in ipairs({ "Text", "Low", "High" }) do
    local fs = _G[name .. suffix]
    if fs and fs.SetText then fs:SetText("") end
  end

  local function fmt(v)
    if o.format then return o.format(v) end
    return tostring(v)
  end

  local function refresh()
    local cur = snap(o.get and o.get() or minV, step, minV)
    sl._neSuppress = true
    sl:SetValue(cur)
    sl._neSuppress = false
    sl._neVal = cur
    value:SetText(fmt(cur))
  end

  local function commit(v)
    if v < minV then v = minV elseif v > maxV then v = maxV end
    value:SetText(fmt(v))
    if sl._neVal ~= v then
      sl._neVal = v
      if o.set then o.set(v) end
      if o.onChanged then o.onChanged(v) end
    end
  end

  sl:SetScript("OnValueChanged", function(self, raw)
    if self._neSuppress then return end
    local v = snap(raw or minV, step, minV)
    if v < minV then v = minV elseif v > maxV then v = maxV end
    if v ~= raw then
      self._neSuppress = true
      self:SetValue(v)
      self._neSuppress = false
    end
    commit(v)
  end)

  local function arrow(point, xOff, dir, up, down, dis, atlas)
    local b = CreateFrame("Button", nil, row)
    b:SetSize(ARROW_W, ARROW_W)
    b:SetPoint(point, row, point, xOff, 0)
    b:SetNormalTexture(up)
    b:SetPushedTexture(down)
    b:SetDisabledTexture(dis)

    -- The bar's own steppers, off the same sheet as the bar (NE.scrollbar.SkinSlider): retail's
    -- MinimalSliderWithSteppers ships the chevrons alongside the track and the diamond, and a
    -- spellbook page-turn glyph six pixels from that bar is the mismatch this pass is about.
    --
    -- Set on TOP of the page-turn paths rather than instead of them: SetNormalTexture is what creates
    -- the texture object in the first place, and a miss here leaves that original art in place rather
    -- than a blank button. The BUTTON stays 18x18 — the row's arithmetic is written against ARROW_W
    -- and the hit area wants to be square — so only the glyph takes the atlas's own size.
    if atlas and NE.tex and NE.tex.SetAtlas then
      local n = b:GetNormalTexture()
      if n and NE.tex.SetAtlas(n, atlas, true) then
        local p, dt = b:GetPushedTexture(), b:GetDisabledTexture()
        NE.tex.SetAtlas(p, atlas, true)
        if NE.tex.SetAtlas(dt, atlas, true) and dt.SetDesaturated then dt:SetDesaturated(true) end
        local h = b:CreateTexture(nil, "HIGHLIGHT")
        NE.tex.SetAtlas(h, atlas, true)
        h:SetBlendMode("ADD")
        h:SetAlpha(0.35)
        -- Pressed is the glyph nudged a pixel down-right, which is what the client's own buttons do
        -- and what this sheet leaves us — it carries one chevron per direction, no state variants.
        for _, t in ipairs({ n, p, dt, h }) do
          if t then
            t:ClearAllPoints()
            t:SetPoint("CENTER", b, "CENTER", (t == p) and 1 or 0, (t == p) and -1 or 0)
          end
        end
      end
    end

    b:SetScript("OnClick", function()
      -- Drive the slider rather than the store: SetValue fires OnValueChanged, which is the one
      -- place that snaps, clamps and writes. Two paths into one setting is how they drift.
      local cur = sl._neVal or minV
      sl:SetValue(cur + dir * step)
      if PlaySound then PlaySound("igMainMenuOptionCheckBoxOn") end
    end)
    return b
  end

  row.Left  = arrow("LEFT",  labelW + 2, -1,
                    "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up",
                    "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Down",
                    "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Disabled",
                    "minimal_sliderbar_button_left")
  row.Right = arrow("RIGHT", -(VALUE_W + 4), 1,
                    "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up",
                    "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Down",
                    "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Disabled",
                    "minimal_sliderbar_button_right")

  -- The minimal bar — see AddSlider.
  if NE.scrollbar and NE.scrollbar.SkinSlider then pcall(NE.scrollbar.SkinSlider, sl) end

  tip(sl, o.label, o.desc)
  refresh()
  self.refreshers[#self.refreshers + 1] = refresh
  self:_gate(o, row, { sl, row.Left, row.Right })
  row.Slider, row.Label, row.Value, row.Refresh = sl, label, value, refresh
  return row
end

-- ── Dropdown ────────────────────────────────────────────────────────────────────────────────────
-- o = { label, desc, values = { {value, label}, ... }, get, set }
--
-- `values` is an ORDERED array, not the value->label map the options tab takes: that map is fed to
-- AceGUI, which sorts it for you, and a radio menu has to decide its own order. "Always / In Combat
-- / Hidden" reads as a progression; alphabetised it does not.

-- The modern trigger, assembled by hand. 3.3.5a has no WowStyle1DropdownTemplate, and retail's own
-- version paints the body with a STATIC atlas and puts the gradient on the ARROW — so the states
-- below are arrow art, and the body has none. Built from a bare Button rather than reskinning
-- UIPanelButtonTemplate: fighting a template's own art for a look this different is more code than
-- the four textures it takes to draw it.
-- The body is THREE textures, not one. See the atlas note in core/NineSliceLayouts.lua: the source is
-- a 54x41 rounded rect with a 12px bevel, and stretching that to a 200x26 row smeared the corners
-- sideways and squashed the bevel — which is exactly what "the dropdowns are formatted very weirdly"
-- was looking at. The caps keep the corner aspect (their width follows the row height), and only the
-- flat middle stretches, which is a plain vertical border run and so stretches invisibly.
local BODY_CAP_W, BODY_CAP_H = 18, 41   -- native size of one cap in the atlas

local function bodyPieces(btn, h)
  local capW = BODY_CAP_W * (h / BODY_CAP_H)
  btn._bodyLeft:SetWidth(capW)
  btn._bodyRight:SetWidth(capW)
end

local function buildModernTrigger(row, name, w, h)
  local btn = CreateFrame("Button", name, row)
  btn:SetSize(w, h)

  local left = btn:CreateTexture(nil, "BACKGROUND")
  left:SetPoint("TOPLEFT")
  left:SetPoint("BOTTOMLEFT")
  NE.tex.SetAtlas(left, "common-dropdown-textholder-left", false)

  local right = btn:CreateTexture(nil, "BACKGROUND")
  right:SetPoint("TOPRIGHT")
  right:SetPoint("BOTTOMRIGHT")
  NE.tex.SetAtlas(right, "common-dropdown-textholder-right", false)

  local body = btn:CreateTexture(nil, "BACKGROUND")
  body:SetPoint("TOPLEFT",     left,  "TOPRIGHT")
  body:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
  NE.tex.SetAtlas(body, "common-dropdown-textholder-center", false)

  btn._bodyLeft, btn._bodyRight = left, right
  bodyPieces(btn, h)
  -- The caps are sized from the height, so they have to follow it. Dialog rows are fixed today, but a
  -- theme that changed dropH would otherwise silently keep the old cap width.
  btn:HookScript("OnSizeChanged", function(self) bodyPieces(self, self:GetHeight()) end)

  -- Square, and inset far enough to sit INSIDE the field rather than straddling the right cap's
  -- bevel. The atlas is 27x27; anything non-square here skews the chevron.
  local arrow = btn:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(h - 6, h - 6)
  arrow:SetPoint("RIGHT", btn, "RIGHT", -4, 0)
  NE.tex.SetAtlas(arrow, "common-dropdown-a-button", false)

  local text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", btn, "LEFT", 8, 0)
  text:SetPoint("RIGHT", arrow, "LEFT", -2, 0)
  text:SetJustifyH("LEFT")
  btn.Text = text
  -- A bare Button has no SetText/GetText of its own; the callers below (and every refresh) expect
  -- the template's, so provide them rather than teaching each call site which kind it holds.
  btn.SetText = function(self, s) self.Text:SetText(s) end
  btn.GetText = function(self) return self.Text:GetText() end

  btn._body, btn._arrow = body, arrow
  btn.RefreshArt = function(self)
    local suffix = ""
    if self._neDown and self._neOver then suffix = "-pressedhover"
    elseif self._neOver then suffix = "-hover"
    elseif self._neDown then suffix = "-pressed" end
    -- Recorded as well as applied: every state comes off ONE sheet, so the file path cannot say
    -- which one is showing and a test would have nothing to read.
    self._arrowAtlas = "common-dropdown-a-button" .. suffix
    NE.tex.SetAtlas(self._arrow, self._arrowAtlas, false)
  end
  return btn
end

function Column:AddDropdown(o)
  local th = self.theme
  local row = self:_row("Frame", th.dropH)
  local values = o.values or {}

  local label = row:CreateFontString(nil, "ARTWORK", th.labelFont)
  label:SetPoint("LEFT", row, "LEFT", 2, 0)
  label:SetJustifyH("LEFT")
  label:SetText(o.label or "")

  local btn
  if th.dropdownArt then
    -- FILL THE CONTROL COLUMN. It used to be a fixed 200 anchored at labelW+6, which put a dropdown's
    -- left edge 4px right of the compact slider's nudge arrow and its right edge 37px short of the
    -- slider's value text — so in a stack of alternating rows nothing lined up with anything. The
    -- column is defined once, by the slider: it starts where the slider's left arrow starts
    -- (labelW + 2) and ends where the slider's value ends (the row, less 4).
    local rowW = self.width - (self._section and ROW_INDENT or 0)
    local w = th.controlW or o.width or (rowW - th.labelW - 6)
    btn = buildModernTrigger(row, nextName("Drop"), w, th.dropH - 6)
    btn:SetPoint("LEFT", row, "LEFT", th.labelW + 2, 0)
  else
    btn = CreateFrame("Button", nextName("Drop"), row, "UIPanelButtonTemplate")
    btn:SetSize(o.width or 130, 22)
    btn:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  end

  local function refresh()
    btn:SetText(labelFor(values, o.get and o.get()))
  end

  local function generator(_, root)
    for _, entry in ipairs(values) do
      local v, text = entry[1], entry[2]
      root:CreateRadio(text,
        function() return (o.get and o.get()) == v end,
        function()
          if o.set then o.set(v) end
          refresh()
          if o.onChanged then o.onChanged(v) end
        end)
    end
  end
  row.MenuGenerator = generator   -- test seam: the tree is assertable without opening a menu

  btn:SetScript("OnClick", function(self)
    if NE.menu and NE.menu.ToggleAnchored then
      NE.menu.ToggleAnchored(generator, self,
        { point = "TOPRIGHT", relativePoint = "BOTTOMRIGHT", x = 0, y = -2 })
    end
  end)

  tip(btn, o.label, o.desc)
  -- AFTER tip, and hooked rather than set: tip owns OnEnter/OnLeave with SetScript, which would
  -- discard a hook installed before it. The arrow's hover and pressed art is the only state this
  -- trigger has, so losing it would leave a button that never acknowledges the mouse.
  if btn.RefreshArt then
    btn:HookScript("OnEnter",     function(s) s._neOver = true;  s:RefreshArt() end)
    btn:HookScript("OnLeave",     function(s) s._neOver = false; s:RefreshArt() end)
    btn:HookScript("OnMouseDown", function(s) s._neDown = true;  s:RefreshArt() end)
    btn:HookScript("OnMouseUp",   function(s) s._neDown = false; s:RefreshArt() end)
  end
  refresh()
  self.refreshers[#self.refreshers + 1] = refresh
  self:_gate(o, row, { btn })
  row.Button, row.Label, row.Refresh = btn, label, refresh
  return row
end

-- ── Action button ───────────────────────────────────────────────────────────────────────────────
-- o = { label, desc, onClick, width }

function Column:AddButton(o)
  local th = self.theme
  local row = self:_row("Frame", th.buttonH or BUTTON_H)

  local btn = CreateFrame("Button", nextName("Button"), row, "UIPanelButtonTemplate")
  btn:SetSize(o.width or 200, th.buttonArtH or 22)
  btn:SetPoint("LEFT", row, "LEFT", 2, 0)
  btn:SetText(o.label or "")
  btn:SetScript("OnClick", function()
    if o.onClick then o.onClick() end
  end)

  -- The red 3-slice, where the theme asks for it. A button built by this kit sits next to buttons the
  -- edit-mode dialog builds itself and skins, and one unskinned row among them is more obviously wrong
  -- than none of them being skinned would be.
  if th.buttonArt and NE.button and NE.button.Skin then pcall(NE.button.Skin, btn) end

  tip(btn, o.label, o.desc)
  row.Button = btn
  return row
end

function Column:AddSpacer(h)
  local f = CreateFrame("Frame", nil, self.frame)
  f:SetSize(1, h or 8)
  self:_add(f, h or 8, {})
  return f
end
