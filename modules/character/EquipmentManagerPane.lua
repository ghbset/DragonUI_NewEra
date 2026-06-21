-- DragonUI_NewEra/modules/character/EquipmentManagerPane.lua — the Equipment
-- Manager sidebar pane (set list + add/edit/delete + icon picker), ported from
-- retail's PaperDollEquipmentManagerPane (and NewEra's port of it) to 3.3.5a.
--
-- Hosted in NE.charpanel.frame.InsetRight (the sidebar host that the stats pane
-- also uses). The Sidebar agent's Tab3 (equipment) calls NE.charpanel.ShowEquipManager()
-- to reveal this pane and HideEquipManager() to hide it; SelectSidebar(index) is also
-- supported for retail-index callers (3 = equipment, anything else = hide).
--
-- All set data / equip logic goes through NE.equipsets (EquipmentSets.lua), which
-- dispatches NATIVE vs CUSTOM — so this file is pure UI and never touches the backend
-- choice.
--
-- 3.3.5 DOWNPORTS vs the NewEra source (which used retail-only widgets):
--   * WowScrollBox / MinimalScrollBar / ScrollUtil  -> a NAMED FauxScrollFrame
--     (FauxScrollFrameTemplate REQUIRES a name on 3.3.5 or it errors) + a bounded
--     row pool. Set counts are tiny (<=10), so non-virtualised is fine.
--   * IconSelectorPopupFrameTemplate / IconDataProviderMixin (absent on 3.3.5)
--     -> our own icon-grid popup driven by GetNumMacroIcons()/GetMacroIconInfo()
--     (the 3.3.5-native gear-set icon source — same data PaperDollFrame uses).
--   * No SetShown (Show/Hide only); SetNormalTexture takes a PATH; child frame
--     levels raised so art isn't occluded; pcall around backend getters.
--   * host = CP.frame.InsetRight, not _G.CharacterFrame.InsetRight.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel
local M  = NE.equipsets

local BTN_H    = 40          -- gear-set row height
local ICON_NEW = "Interface\\PaperDollInfoFrame\\Character-Plus"
local ICON_QM  = "Interface\\Icons\\INV_Misc_QuestionMark"

local function log(msg) if CP._log then CP._log(msg) end end

-- Localised-string-or-fallback helper.
local function L(global, fallback)
  local v = _G[global]
  if type(v) == "string" and v ~= "" then return v end
  return fallback
end

local NORMAL = NORMAL_FONT_COLOR or { r = 1, g = 0.82, b = 0 }
local RED    = RED_FONT_COLOR    or { r = 1, g = 0.1, b = 0.1 }
local GREEN  = GREEN_FONT_COLOR  or { r = 0.1, g = 1, b = 0.1 }

-- ----------------------------------------------------------------------------
-- StaticPopups (delete confirm + save/overwrite confirm).
-- ----------------------------------------------------------------------------
StaticPopupDialogs = StaticPopupDialogs or {}
StaticPopupDialogs["NE_CONFIRM_DELETE_EQUIPMENT_SET"] = {
  text = L("CONFIRM_DELETE_EQUIPMENT_SET", "Delete the equipment set '%s'?"),
  button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function(_, data) if M then M.Delete(data) end; if CP.RefreshEquipPane then CP.RefreshEquipPane() end end,
  timeout = 0, hideOnEscape = 1, whileDead = 1, showAlert = 1,
}
StaticPopupDialogs["NE_CONFIRM_SAVE_EQUIPMENT_SET"] = {
  text = L("CONFIRM_SAVE_EQUIPMENT_SET", "Overwrite the equipment set '%s' with your currently equipped items?"),
  button1 = YES or "Yes", button2 = NO or "No",
  OnAccept = function(_, data)
    if M and data then M.Save(data.setID, data.icon) end
    if CP.RefreshEquipPane then CP.RefreshEquipPane() end
  end,
  timeout = 0, hideOnEscape = 1, whileDead = 1, showAlert = 1,
}

-- ============================================================================
-- Icon-picker popup. 3.3.5-native data: GetNumMacroIcons()/GetMacroIconInfo(i)
-- give the same icon list PaperDollFrame's GearManagerDialogPopup uses. We render
-- a named FauxScrollFrame grid (5 per row), an edit box for the set name, and
-- Okay/Cancel. mode = "new" (create) or "edit" (rename existing setID).
-- ============================================================================
local ICONS_PER_ROW   = 5
local ICON_ROWS       = 4
local ICON_BTN        = 36
local ICON_PAD        = 6
local popup

local function numMacroIcons()
  if type(GetNumMacroIcons) == "function" then return GetNumMacroIcons() or 0 end
  return 0
end
local function macroIcon(i)
  if type(GetMacroIconInfo) == "function" then return GetMacroIconInfo(i) end
  return ICON_QM
end

local function popupSelect(self, texture)
  self.selectedTexture = texture
  if self.selPreview then self.selPreview:SetTexture(texture or ICON_QM) end
  -- DOWNPORT/REPORT: light the selected icon's border immediately (don't wait for the next scroll).
  if self.iconBtns then
    for _, b in ipairs(self.iconBtns) do
      if b.sel then
        if b._tex and b._tex == texture then b.sel:Show() else b.sel:Hide() end
      end
    end
  end
end

local function popupUpdate()
  local self = popup
  if not self then return end
  local total = numMacroIcons()
  local offset = FauxScrollFrame_GetOffset(self.scroll) or 0
  for i = 1, ICONS_PER_ROW * ICON_ROWS do
    local btn = self.iconBtns[i]
    local realIndex = (offset * ICONS_PER_ROW) + i
    if realIndex <= total then
      local tex = macroIcon(realIndex)
      btn.icon:SetTexture(tex)
      btn._tex = tex
      btn:Show()
      if self.selectedTexture and tex == self.selectedTexture then
        btn.sel:Show()
      else
        btn.sel:Hide()
      end
    else
      btn:Hide()
    end
  end
  FauxScrollFrame_Update(self.scroll, math.ceil(total / ICONS_PER_ROW), ICON_ROWS, ICON_BTN + 4)
end

local function buildPopup()
  if popup then return popup end
  local parent = CP.frame or UIParent
  local p = CreateFrame("Frame", "NE_GearManagerPopup", parent)
  p:SetSize(ICONS_PER_ROW * (ICON_BTN + 4) + 40, ICON_ROWS * (ICON_BTN + 4) + 110)
  p:SetFrameStrata("DIALOG")
  p:SetToplevel(true)
  p:ClearAllPoints()
  -- DOWNPORT/REPORT: anchor the picker vertically CENTERED beside the panel (was hung off the top-right
  -- corner, so it spilled downward past the frame — looked detached/messy).
  p:SetPoint("LEFT", parent, "RIGHT", 8, 0)
  p:EnableMouse(true)
  p:Hide()

  -- Backdrop (use a simple dialog backdrop available on 3.3.5).
  if p.SetBackdrop then
    p:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32,
      insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end

  local header = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  header:SetPoint("TOP", p, "TOP", 0, -14)
  header:SetText(L("GEARSETS_POPUP_TEXT", "Set Name:"))

  -- Name edit box.
  local eb = CreateFrame("EditBox", "NE_GearManagerPopupEditBox", p, "InputBoxTemplate")
  eb:SetSize(p:GetWidth() - 60, 20)
  eb:SetPoint("TOP", header, "BOTTOM", 0, -6)
  eb:SetAutoFocus(false)
  eb:SetMaxLetters(16)   -- match the "(Max 16 Characters)" header
  eb:SetScript("OnEscapePressed", function(self) self:GetParent():Hide() end)
  p.editBox = eb

  -- Named FauxScrollFrame for the icon grid (NAME REQUIRED on 3.3.5). DOWNPORT/REPORT: anchored cleanly
  -- BELOW the edit box. The old anchor hung the grid off a separate preview icon's BOTTOMRIGHT with a
  -- +40 nudge, which shoved a column past the popup edge (detached column) and left a gap under the
  -- editbox. The in-grid selection border (btn.sel) shows the chosen icon, so no preview swatch needed.
  local scroll = CreateFrame("ScrollFrame", "NE_GearManagerPopupScroll", p, "FauxScrollFrameTemplate")
  scroll:SetSize(ICONS_PER_ROW * (ICON_BTN + 4), ICON_ROWS * (ICON_BTN + 4))
  scroll:SetPoint("TOPLEFT", p, "TOPLEFT", 20, -70)
  scroll:SetScript("OnVerticalScroll", function(self, off)
    FauxScrollFrame_OnVerticalScroll(self, off, ICON_BTN + 4, popupUpdate)
  end)
  -- DOWNPORT: hand-built minimal scrollbar (Reskin's stock-slider re-skin didn't render).
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll) end
  p.scroll = scroll

  -- DOWNPORT/REPORT: wheel scrolling for the icon grid (BuildCustom wires no wheel; the custom thumb
  -- alone left it unscrollable). Nudge the hidden Faux slider value; it auto-clamps + fires the scroll.
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local sb = _G[(self:GetName() or "") .. "ScrollBar"]
    if not sb then return end
    local mn, mx = sb:GetMinMaxValues()
    local v = sb:GetValue() - delta * (ICON_BTN + 4)
    if v < mn then v = mn elseif v > mx then v = mx end
    sb:SetValue(v)
  end)

  -- Icon buttons (fixed pool of ICONS_PER_ROW*ICON_ROWS). DOWNPORT/REPORT: parented to the SCROLL (not
  -- the popup) so they sit ABOVE the mouse-enabled faux-scroll frame and actually receive clicks — as
  -- children of `p` they were occluded by the scroll frame and clicks did nothing.
  p.iconBtns = {}
  for i = 1, ICONS_PER_ROW * ICON_ROWS do
    local b = CreateFrame("Button", "NE_GearManagerPopupIcon" .. i, scroll)
    b:SetSize(ICON_BTN, ICON_BTN)
    local col = (i - 1) % ICONS_PER_ROW
    local row = math.floor((i - 1) / ICONS_PER_ROW)
    b:SetPoint("TOPLEFT", scroll, "TOPLEFT", col * (ICON_BTN + 4), -(row * (ICON_BTN + 4)))
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints(b)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.sel = b:CreateTexture(nil, "OVERLAY")
    b.sel:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.sel:SetBlendMode("ADD")
    b.sel:SetSize(ICON_BTN + 32, ICON_BTN + 32)
    b.sel:SetPoint("CENTER")
    b.sel:Hide()
    b:SetScript("OnClick", function(self) popupSelect(p, self._tex) end)
    -- Hover highlight = button-sized (ButtonHilight-Square is near-solid, so scaling it up like the
    -- transparent-margined selection border made it far too big). Auto-sized to the button.
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    p.iconBtns[i] = b
  end

  -- Okay / Cancel.
  local okay = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  okay:SetSize(78, 22)
  okay:SetText(L("OKAY", "Okay"))
  okay:SetPoint("BOTTOMRIGHT", p, "BOTTOM", -2, 12)
  okay:SetScript("OnClick", function()
    local text = p.editBox:GetText()
    if not text or text == "" then return end
    local icon = p.selectedTexture
    local existingID = M and M.GetSetID(text)

    if p.mode == "edit" then
      if existingID and text ~= p.origName then
        if UIErrorsFrame then UIErrorsFrame:AddMessage(L("EQUIPMENT_SETS_CANT_RENAME", "A set with that name already exists."), 1, 0.1, 0.1, 1) end
        return
      end
      M.Modify(p.setID, text, icon)
      CP._equipPane.selectedSetID = p.setID
    else
      if existingID then
        -- overwrite path (same name) — save into the existing set
        M.Save(existingID, icon)
        CP._equipPane.selectedSetID = existingID
      else
        if M.GetNumSets() >= M.MAX_SETS then
          if UIErrorsFrame then UIErrorsFrame:AddMessage(L("EQUIPMENT_SETS_TOO_MANY", "You have too many equipment sets."), 1, 0.1, 0.1, 1) end
          return
        end
        M.Create(text, icon)
        CP._equipPane.selectedSetID = M.GetSetID(text)
      end
    end
    p:Hide()
    if CP.RefreshEquipPane then CP.RefreshEquipPane() end
  end)

  local cancel = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  cancel:SetSize(78, 22)
  cancel:SetText(L("CANCEL", "Cancel"))
  cancel:SetPoint("BOTTOMLEFT", p, "BOTTOM", 2, 12)
  cancel:SetScript("OnClick", function() p:Hide() end)

  -- ESC closes.
  if NE.FrameUtil and NE.FrameUtil.EscClose then
    NE.FrameUtil.EscClose("NE_GearManagerPopup")
  else
    tinsert(UISpecialFrames, "NE_GearManagerPopup")
  end

  popup = p
  return p
end

local function openPopupNew()
  local p = buildPopup()
  if not p then return end
  p.mode = "new"
  p.setID, p.origName = nil, nil
  p.selectedTexture = nil
  p.editBox:SetText("")
  -- pre-select the first icon for a non-blank preview
  popupSelect(p, macroIcon(1))
  p:Show()
  popupUpdate()
  p.editBox:SetFocus()
end

local function openPopupEdit(setID, name)
  local p = buildPopup()
  if not p then return end
  p.mode = "edit"
  p.setID = setID
  p.origName = name
  local _, icon = M.GetSetInfo(setID)
  p.selectedTexture = icon
  p.editBox:SetText(name or "")
  popupSelect(p, icon or macroIcon(1))
  p:Show()
  popupUpdate()
  p.editBox:SetFocus()
  p.editBox:HighlightText()
end

-- ============================================================================
-- Gear-set list row (port of GearSetButtonTemplate, simplified for 3.3.5).
-- ============================================================================
local function makeGearButton(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(BTN_H)
  b:RegisterForClicks("LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self) if self.setID and M then M.Pickup(self.setID) end end)

  -- Alternating stripe (BACKGROUND).
  local stripe = b:CreateTexture(nil, "BACKGROUND")
  stripe:SetPoint("TOPLEFT", 1, 0)
  stripe:SetPoint("BOTTOMRIGHT", 0, 0)
  stripe:Hide()
  b.Stripe = stripe

  -- Icon.
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetSize(34, 34)
  icon:SetPoint("LEFT", 4, 0)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.icon = icon

  -- Name.
  local text = b:CreateFontString(nil, "ARTWORK", "GameFontNormalLeft")
  text:SetPoint("LEFT", 42, 0)
  -- DOWNPORT/REPORT: the narrow sidebar truncated "New Equipment Set" ("New Equipmen..."). Use the full
  -- width (the hover-only edit/delete icons sit over the far-right end of a long name, which is fine).
  text:SetPoint("RIGHT", -6, 0)
  text:SetJustifyH("LEFT")
  b.text = text

  -- Equipped check (BORDER).
  local check = b:CreateTexture(nil, "BORDER")
  check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
  check:SetSize(18, 18)
  check:SetPoint("RIGHT", -4, 0)
  check:Hide()
  b.Check = check

  -- Hover highlight.
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  hl:SetBlendMode("ADD")
  hl:SetAlpha(0.4)
  hl:SetAllPoints(b)

  -- Selected bar (OVERLAY).
  local selbar = b:CreateTexture(nil, "OVERLAY")
  selbar:SetTexture("Interface\\FriendsFrame\\UI-FriendsFrame-HighlightBar")
  selbar:SetTexCoord(0.2, 0.8, 0, 1)
  selbar:SetAlpha(0.4)
  selbar:SetBlendMode("ADD")
  selbar:SetAllPoints(b)
  selbar:Hide()
  b.SelectedBar = selbar

  -- Delete (X) — shown on hover.
  local del = CreateFrame("Button", nil, b)
  del:SetSize(14, 14)
  del:SetPoint("BOTTOMRIGHT", -2, 2)
  local delTex = del:CreateTexture(nil, "ARTWORK")
  delTex:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
  delTex:SetAllPoints(del)
  delTex:SetAlpha(0.6)
  del:SetScript("OnEnter", function(self) delTex:SetAlpha(1); GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(DELETE or "Delete"); GameTooltip:Show() end)
  del:SetScript("OnLeave", function() delTex:SetAlpha(0.6); GameTooltip:Hide() end)
  del:SetScript("OnClick", function(self)
    local pb = self:GetParent()
    if pb.setID then StaticPopup_Show("NE_CONFIRM_DELETE_EQUIPMENT_SET", pb.text:GetText(), nil, pb.setID) end
  end)
  del:Hide()
  b.DeleteButton = del

  -- Edit (gear) — left of delete, opens rename/icon popup.
  local edit = CreateFrame("Button", nil, b)
  edit:SetSize(16, 16)
  edit:SetPoint("RIGHT", del, "LEFT", -1, 0)
  local editTex = edit:CreateTexture(nil, "ARTWORK")
  editTex:SetTexture("Interface\\WorldMap\\Gear_64Grey")
  editTex:SetAllPoints(edit)
  editTex:SetAlpha(0.6)
  edit:SetScript("OnEnter", function(self) editTex:SetAlpha(1); GameTooltip:SetOwner(self, "ANCHOR_RIGHT"); GameTooltip:SetText(L("EQUIPMENT_SET_SETTINGS", "Edit")); GameTooltip:Show() end)
  edit:SetScript("OnLeave", function() editTex:SetAlpha(0.6); GameTooltip:Hide() end)
  edit:SetScript("OnClick", function(self)
    local pb = self:GetParent()
    if pb.setID then openPopupEdit(pb.setID, pb.text:GetText()) end
  end)
  edit:Hide()
  b.EditButton = edit

  -- Click / double-click / tooltip.
  b:SetScript("OnClick", function(self)
    if self.setID then
      CP._equipPane.selectedSetID = self.setID
      if M then M.LoadIgnoredFromSet(self.setID) end
      CP.RefreshEquipPane()
    else
      CP._equipPane.selectedSetID = nil
      openPopupNew()
      CP.RefreshEquipPane()
    end
  end)
  b:SetScript("OnDoubleClick", function(self)
    if self.setID and M then M.Use(self.setID) end
  end)
  b:SetScript("OnEnter", function(self)
    if not self.setID or not M then return end
    local name, _, _, _, numItems, numEquipped, _, numLost = M.GetSetInfo(self.setID)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(name or "", 1, 1, 1)
    GameTooltip:AddLine(string.format("%d / %d %s", numEquipped or 0, numItems or 0,
      L("EQUIPMENT_SETS_EQUIPPED", "equipped")), 0.8, 0.8, 0.8)
    if (numLost or 0) > 0 then
      GameTooltip:AddLine(string.format("%d %s", numLost, L("EQUIPMENT_SETS_MISSING", "items missing")), 1, 0.1, 0.1)
    end
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)

  return b
end

-- ============================================================================
-- Pane construction (named FauxScrollFrame). Hosted in CP.frame.InsetRight.
-- ============================================================================
local function host()
  return CP.frame and CP.frame.InsetRight
end

local function buildEquipPane()
  if CP._equipPane then return CP._equipPane end
  local ir = host()
  if not ir then log("buildEquipPane: InsetRight not ready"); return nil end

  local pane = CreateFrame("Frame", "NE_EquipmentManagerPane", ir)
  pane:SetPoint("TOPLEFT",     ir, "TOPLEFT",      3, -3)
  pane:SetPoint("BOTTOMRIGHT", ir, "BOTTOMRIGHT", -3,  2)
  pane:Hide()

  -- Equip + Save buttons flush at the top.
  -- DOWNPORT/REPORT: force a consistent font across enabled/disabled. The base DragonUI addon reskins
  -- UIPanelButtonTemplate (red) and changes the enabled font, so enabled vs greyed looked different —
  -- pin both states to the clean small fonts (the greyed look the user preferred).
  local function pinBtnFont(btn)
    if btn.SetNormalFontObject   then pcall(btn.SetNormalFontObject,   btn, "GameFontNormalSmall") end
    if btn.SetDisabledFontObject then pcall(btn.SetDisabledFontObject, btn, "GameFontDisableSmall") end
    if btn.SetHighlightFontObject then pcall(btn.SetHighlightFontObject, btn, "GameFontHighlightSmall") end
  end

  local equipBtn = CreateFrame("Button", "$parentEquipSet", pane, "UIPanelButtonTemplate")
  equipBtn:SetSize(96, 22)
  equipBtn:SetText(L("EQUIPSET_EQUIP", "Equip"))
  equipBtn:SetPoint("TOPLEFT", pane, "TOPLEFT", 0, 0)
  pinBtnFont(equipBtn)
  equipBtn:SetScript("OnClick", function()
    local id = pane.selectedSetID
    if id and M then M.Use(id) end
  end)
  pane.EquipSet = equipBtn

  local saveBtn = CreateFrame("Button", "$parentSaveSet", pane, "UIPanelButtonTemplate")
  saveBtn:SetSize(96, 22)
  saveBtn:SetText(L("SAVE", "Save"))
  saveBtn:SetPoint("LEFT", equipBtn, "RIGHT", 4, 0)
  pinBtnFont(saveBtn)
  saveBtn:SetScript("OnClick", function()
    local id = pane.selectedSetID
    if not id or not M then return end
    local name, icon = M.GetSetInfo(id)
    StaticPopup_Show("NE_CONFIRM_SAVE_EQUIPMENT_SET", name, nil, { setID = id, icon = icon })
  end)
  pane.SaveSet = saveBtn

  -- Named FauxScrollFrame list (NAME REQUIRED on 3.3.5).
  local scroll = CreateFrame("ScrollFrame", "NE_EquipManagerScroll", pane, "FauxScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT",     pane, "TOPLEFT",      0, -26)
  scroll:SetPoint("BOTTOMRIGHT", pane, "BOTTOMRIGHT", -22,  2)
  scroll:SetScript("OnVerticalScroll", function(self, off)
    FauxScrollFrame_OnVerticalScroll(self, off, BTN_H, function() CP.RefreshEquipPane() end)
  end)
  -- DOWNPORT: hand-built minimal scrollbar (Reskin's stock-slider re-skin didn't render).
  -- DOWNPORT/REPORT: push the bar FLUSH to the pane's right edge (x=-10) like the character panel —
  -- the default inset put it over the (now full-width) rows, covering their equipped checkmarks.
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, scroll, { x = -10 }) end
  pane._scroll = scroll

  pane._btnPool = {}

  -- Hover reveal of Delete/Edit.
  pane:SetScript("OnUpdate", function(self)
    if not self:IsVisible() then return end
    for _, btn in ipairs(self._btnPool) do
      if btn:IsShown() then
        local over = btn:IsMouseOver() and btn.setID ~= nil
        if over then btn.DeleteButton:Show(); btn.EditButton:Show()
        else btn.DeleteButton:Hide(); btn.EditButton:Hide() end
      end
    end
  end)

  CP._equipPane = pane
  return pane
end

-- ----------------------------------------------------------------------------
-- Populate the list + drive Equip/Save enable state. Non-virtualised: we keep a
-- pool sized to the visible rows and page it via FauxScrollFrame offset.
-- ----------------------------------------------------------------------------
local STRIPE = { r = 0.9, g = 0.9, b = 1 }

local function refreshEquipPane()
  local pane = CP._equipPane
  if not pane or not M then return end
  local scroll = pane._scroll

  -- Validate selection + drive Equip/Save enable.
  local selID = pane.selectedSetID
  local isEquipped
  if selID then
    local _, _, sid, eq = M.GetSetInfo(selID)
    if sid then isEquipped = eq else selID = nil; pane.selectedSetID = nil end
  end
  if selID and not isEquipped then
    pane.EquipSet:Enable(); pane.SaveSet:Enable()
  else
    pane.EquipSet:Disable(); pane.SaveSet:Disable()
  end

  -- Row data: every set, then the "New Set" row (under cap).
  local ids = M.GetSetIDs()
  local rows = {}
  for _, id in ipairs(ids) do rows[#rows + 1] = { setID = id } end
  if #ids < M.MAX_SETS then rows[#rows + 1] = { addSetButton = true } end

  local visible = math.max(1, math.floor((scroll:GetHeight() or (BTN_H * 6)) / BTN_H))
  -- Grow the pool to the visible count. DOWNPORT/REPORT (the empty-list bug): parent the gear buttons
  -- to the PANE, not the faux ScrollFrame. FauxScrollFrame_Update HIDES the scroll frame when the rows
  -- fit (numItems <= numToDisplay) — with only the "New Set" row that's always true, so the buttons
  -- (incl. the New-Set button) vanished and there was no way to create a set. Anchored to the scroll
  -- rect below (which keeps its position even while hidden), raised above it so they stay clickable.
  for i = #pane._btnPool + 1, visible do
    local b = makeGearButton(pane)
    if b.SetFrameLevel then b:SetFrameLevel((scroll:GetFrameLevel() or 1) + 5) end
    pane._btnPool[i] = b
  end

  FauxScrollFrame_Update(scroll, #rows, visible, BTN_H)
  local offset = FauxScrollFrame_GetOffset(scroll) or 0

  for i = 1, #pane._btnPool do
    local b = pane._btnPool[i]
    local row = rows[offset + i]
    if i <= visible and row then
      b:ClearAllPoints()
      -- DOWNPORT/REPORT: row spans to the PANE's right edge (not the scroll's), so the stripe/selection
      -- background reaches the window edge / under where the scrollbar sits, instead of stopping short.
      b:SetPoint("TOPLEFT", scroll, "TOPLEFT", 2, -((i - 1) * BTN_H))
      b:SetPoint("RIGHT", pane, "RIGHT", -14, 0)
      b:Show()

      if row.addSetButton then
        b.setID = nil
        b.text:SetText(L("PAPERDOLL_NEWEQUIPMENTSET", "New Equipment Set"))
        b.text:SetTextColor(GREEN.r, GREEN.g, GREEN.b)
        -- DOWNPORT/REPORT: the "New Equipment Set" row has NO icon. ICON_NEW (Character-Plus) doesn't
        -- exist on 3.3.5, so SetTexture left the pooled button showing the DELETED set's icon — clear +
        -- hide it explicitly so a reused button never inherits a stale icon.
        b.icon:SetTexture(nil); b.icon:Hide()
        b.Check:Hide(); b.SelectedBar:Hide(); b.Stripe:Hide()
      else
        local name, texture, sid, equipped, _, _, _, numLost = M.GetSetInfo(row.setID)
        b.setID = sid
        b.text:SetText(name or "")
        if (numLost or 0) > 0 then b.text:SetTextColor(RED.r, RED.g, RED.b)
        else b.text:SetTextColor(NORMAL.r, NORMAL.g, NORMAL.b) end
        b.icon:Show()
        b.icon:SetTexture(texture or ICON_QM); b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if equipped then b.Check:Show() else b.Check:Hide() end
        if pane.selectedSetID ~= nil and sid == pane.selectedSetID then b.SelectedBar:Show() else b.SelectedBar:Hide() end
        if ((offset + i) % 2) == 0 then
          b.Stripe:SetTexture(STRIPE.r, STRIPE.g, STRIPE.b, 0.1); b.Stripe:Show()
        else
          b.Stripe:Hide()
        end
      end
    else
      b:Hide()
    end
  end
end
CP.RefreshEquipPane = refreshEquipPane

-- ----------------------------------------------------------------------------
-- Show / hide the pane. The Sidebar agent's Tab3 (equipment) calls these.
-- ----------------------------------------------------------------------------
function CP.ShowEquipManager()
  local pane = buildEquipPane()
  if not pane then return end
  -- Hide the stats pane if the sidebar agent exposed it.
  if CP._sidebar and CP._sidebar.Hide then CP._sidebar:Hide() end
  pane:Show()
  refreshEquipPane()
  CP._activeSidebar = 3
  -- Equip-swap flyout arrows live on the equipment page only.
  if CP.ShowEquipmentFlyoutArrows then CP.ShowEquipmentFlyoutArrows() end
end

function CP.HideEquipManager()
  if CP._equipPane then CP._equipPane:Hide() end
  if CP.HideEquipmentFlyoutArrows then CP.HideEquipmentFlyoutArrows() end
end

-- Retail-index compatibility (index 3 = equipment). Keeps NewEra callers working;
-- the canonical entry points are ShowEquipManager/HideEquipManager.
local _prevSelectSidebar = CP.SelectSidebar
function CP.SelectSidebar(index)
  CP._activeSidebar = index
  if index == 3 then
    CP.ShowEquipManager()
  else
    CP.HideEquipManager()
    if CP._sidebar and CP._sidebar.Show then CP._sidebar:Show() end
    if CP.RefreshSidebar then CP.RefreshSidebar() end
    -- Defer to a previously-installed sidebar selector (stats sub-tabs) if any.
    if _prevSelectSidebar and _prevSelectSidebar ~= CP.SelectSidebar then pcall(_prevSelectSidebar, index) end
  end
  if CP.SetSidebarTabSelected then pcall(CP.SetSidebarTabSelected, index) end
end

-- ----------------------------------------------------------------------------
-- React to backend changes (set created/deleted/equipped, gear/bag changes).
-- ----------------------------------------------------------------------------
local function onBackendChanged()
  if CP._equipPane and CP._equipPane:IsVisible() then refreshEquipPane() end
end
local function onSwapFinished(result, setID)
  if result and CP._equipPane and CP._equipPane:IsVisible() then
    if setID then CP._equipPane.selectedSetID = setID end
    refreshEquipPane()
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsBooted and not NE.modules.IsBooted("character") then return end
  if M then
    M.RegisterChanged(onBackendChanged)
    M.RegisterSwapFinished(onSwapFinished)
  end
end)

-- ----------------------------------------------------------------------------
-- /dnequip "Set Name"  (alias /gearset) — equip a saved equipment set by name.
-- The name may be quoted ("Bicc Set") or bare; matching is case-insensitive. If no set matches it
-- errors and lists the sets you do have. Uses the same client-side backend (M.Use → physical swap).
-- ----------------------------------------------------------------------------
local function equipByName(msg)
  msg = msg or ""
  local name = msg:match('"(.-)"') or msg:match("'(.-)'")
  if not name then name = msg:gsub("^%s+", ""):gsub("%s+$", "") end
  local chat = DEFAULT_CHAT_FRAME
  if name == "" then
    chat:AddMessage('|cffffcc55DragonUI|r Usage: /dnequip "Set Name"')
    return
  end
  if not M then chat:AddMessage("|cffff5555DragonUI|r Equipment manager not ready."); return end

  local target = name:lower()
  local found, names = nil, {}
  for _, id in ipairs(M.GetSetIDs() or {}) do
    local sname = M.GetSetInfo(id)
    if sname then
      names[#names + 1] = sname
      if sname:lower() == target then found = id; break end
    end
  end

  if found then
    -- Already wearing it? GetSetInfo's 4th return is isEquipped (all of the set's items currently worn).
    local sname, _, _, equipped = M.GetSetInfo(found)
    if equipped then
      chat:AddMessage(string.format('|cffffcc55DragonUI|r You already have "%s" equipped.', sname or name))
      return
    end
    M.Use(found)
    chat:AddMessage(string.format('|cff55ff55DragonUI|r Equipping set "%s".', sname or name))
  else
    local list = (#names > 0) and (" Your sets: " .. table.concat(names, ", ") .. ".")
                                or " You have no saved sets."
    chat:AddMessage(string.format('|cffff5555DragonUI|r No equipment set named "%s".%s', name, list))
  end
end
-- DOWNPORT/REPORT: NOT "/equip" or "/equipset" — BOTH are built-in WotLK secure macro commands
-- (equip an item / equip a NATIVE set), processed by the secure command system before a SlashCmdList
-- handler runs, so they never reach us (and look up native sets we don't have). Use unique names.
SLASH_NEEQUIPSET1 = "/dnequip"
SLASH_NEEQUIPSET2 = "/gearset"
SlashCmdList["NEEQUIPSET"] = equipByName
