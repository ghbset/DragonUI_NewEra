-- DragonUI_NewEra/modules/spellbook/Spellbook.lua — the spell-display SYSTEM (RENDERER).
--
-- DOWNPORT: NewEra/Spellbook/Spellbook.lua (Classic 1.15) -> 3.3.5a, adapted to the SHARED
-- CONTRACT. The window agent owns SB.frame / SB.Host() / the chrome constants / the boot +
-- ToggleSpellBook intercept + SB.minimized / SB.ApplyWidth / SB.SetMinimized / SB.RegisterSheen.
-- THIS file owns the render system: card pool, two-page grid, section headers, category tabs,
-- pagination, search, cog filters. It exposes SB.Build / SB.Refresh / SB.RenderCards /
-- SB.SetPage / SB.SelectCategory.
--
-- SCOPE (this sprint): LEARNED SPELLS ONLY. We use the Era-tab FALLBACK path — render learned
-- spells grouped by spell-tab section + a live pet category. The ClassSpells future-spell /
-- seed-driven path (greyed "Available at Level X" cards, SEED tables, emitFuture, petdata
-- catalog, rank flyout) is DROPPED here — it is vanilla-1.12 data, wrong for WotLK; Phase 2.
--
-- DATA driver = the legacy 3.3.5a globals (all present): GetNumSpellTabs, GetSpellTabInfo,
-- GetSpellBookItemName, GetSpellBookItemInfo, GetSpellBookItemTexture, IsPassiveSpell,
-- HasPetSpells, GetSpellAutocast, BOOKTYPE_SPELL/PET.
--
-- MASKS: 3.3.5a CreateMaskTexture may return nil. Every mask use is guarded and degrades.

local NE = DragonUI_NewEra
NE.spellbook = NE.spellbook or {}
local SB = NE.spellbook

-- Layout constants (retail nominal — same mapping NewEra used).
local CARD_W, CARD_H   = 216.667, 60
local CARD_XPAD        = 15
local CARD_YPAD        = 10
local GRID_COLS        = 3
local ICON             = 36
local ICON_BTN         = 40
local VIEW_W, VIEW_H   = 680, 620
local VIEW_TOP         = -122   -- shifted up 26 (with PAGES_TOP/BG_TOP) to close the old black band
local VIEW1_X          = 85
local VIEW2_X          = -50
local ROW_H            = CARD_H + CARD_YPAD
local SPAN_W           = GRID_COLS * CARD_W + (GRID_COLS - 1) * CARD_XPAD
local rows             = math.floor((VIEW_H + CARD_YPAD) / ROW_H)   -- ~9 rows/page

-- Book background placement (host-relative; stretched to fill each half). BG_TOP=0 seats the wooden
-- header flush under the title bar (host top == title-bar bottom) — removing the dead black band that
-- used to show between the title bar and the wood. PAGES_TOP follows it up so no gap opens below.
local PAGES_TOP        = -56
local PAGES_BOT        = 0
local BG_INSET_X       = 0
local BG_TOP           = 0
local HEADER_H         = 58

-- Category tabs — seated ON the wooden header, tops tucked just under the title bar (host top).
-- Dimensions match the Character panel's tabs (h 36 inactive / 42 active, min-w 70, +24 text pad,
-- 1px gap), applied in the Refresh chain loop + setTabArt.
local CAT_TAB_X        = 70
local CAT_TAB_TOP      = -2
local TAB_H_INACTIVE   = 36
local TAB_H_ACTIVE     = 42
local TAB_MIN_W        = 70
local TAB_TEXT_PAD     = 24
local TAB_GAP          = 1

-- SystemFont_Huge2 is a retail font object; fall back to a 3.3.5a-present huge font.
local SECTION_TITLE_FONT = (_G.SystemFont_Huge2 and "SystemFont_Huge2")
                        or (_G.GameFontNormalHuge and "GameFontNormalHuge")
                        or "GameFontNormalLarge"
local SECTION_TOP_GAP    = 18

-- Near-black spellbook ink (retail SPELLBOOK_FONT_COLOR hex 2e1b0f).
local function spellbookInk()
  if SPELLBOOK_FONT_COLOR and SPELLBOOK_FONT_COLOR.GetRGB then return SPELLBOOK_FONT_COLOR:GetRGB() end
  return 0.1804, 0.1059, 0.0588
end

local BOOKTYPE_SPELL_ = BOOKTYPE_SPELL or "spell"
local BOOKTYPE_PET_   = BOOKTYPE_PET or "pet"

-- State.
SB.cards     = SB.cards or {}
SB.headers   = SB.headers or {}
SB.catTabs   = SB.catTabs or {}
SB.bgParts   = SB.bgParts or {}
SB.page      = SB.page or 1
SB.selected  = SB.selected or 1
SB.elements  = SB.elements or {}
SB.search    = SB.search or ""
SB.hidePassives = SB.hidePassives or false
SB.showRanks    = SB.showRanks or false
SB.refreshQueued = SB.refreshQueued or false

-- The content root we parent everything to. Provided by the window agent as SB.Host().
local function host()
  if SB.Host then
    local ok, h = pcall(SB.Host)
    if ok and h then return h end
  end
  return SB.frame
end
local function frame() return SB.frame end

-- Cog options persist in DragonUI_NewEraDB.spellbook.
local function optsTable()
  local root = _G.DragonUI_NewEraDB
  if type(root) ~= "table" then return nil end
  return root.spellbook
end
local function loadFilterOpts()
  local o = optsTable()
  if type(o) == "table" then
    SB.hidePassives = o.hidePassives or false
    SB.showRanks    = o.showRanks or false
  end
end
local function saveOpts()
  _G.DragonUI_NewEraDB = _G.DragonUI_NewEraDB or {}
  local o = _G.DragonUI_NewEraDB.spellbook or {}
  o.hidePassives = SB.hidePassives
  o.showRanks    = SB.showRanks
  _G.DragonUI_NewEraDB.spellbook = o
end
SB._loadFilterOpts = loadFilterOpts

-- Shared sheen clock — register opted-in nodes with the window agent's driver.
local function registerSheen(node)
  node._wantSheen = true
  if SB.RegisterSheen then pcall(SB.RegisterSheen, node) end
end

-- Icon resolution — slot texture first, spellID texture fallback.
local function slotIcon(slot, bookType, spellID)
  local icon = GetSpellBookItemTexture and GetSpellBookItemTexture(slot, bookType)
  if not icon and spellID and GetSpellTexture then icon = GetSpellTexture(spellID) end
  return icon
end

-- Card art sets — square (active) vs circle (passive). The border OVERHANGS the icon button
-- for the square set; the circle set rings it at button size.
local ART_SET = {
  square = {
    iconMask      = "spellbook-item-spellicon-mask",
    iconHighlight = "spellbook-item-iconframe-hover",
    border        = "spellbook-item-iconframe",
    borderTL = { -11, 1 }, borderBR = { 1, -7 },
    sheenMask     = "spellbook-item-iconframe-sheen-mask", sheenCentered = false,
  },
  -- PASSIVE set. 3.3.5a can't alpha-mask a square icon into a circle (CreateMaskTexture is dead), so
  -- the old circular ring left the square icon's corners poking out. Instead use the retail spellbook's
  -- dedicated SQUARE SILVER passive frame (distinct from the gold active frame) — the square icon fits
  -- it cleanly, and silver-vs-gold keeps the passive/active distinction. (User: "use the icon border
  -- in the action bar - since its silver that will suffice".)
  passive = {
    iconMask      = "spellbook-item-spellicon-mask",
    iconHighlight = "spellbook-item-iconframe-hover",
    border        = "talents-node-square-gray",   -- the dark SQUARE talent-node socket (NewEra talents)
    borderTL = { 0, 0 }, borderBR = { 0, 0 },      -- sized to the icon slot (matches the active frame's main square)
    sheenMask     = "spellbook-item-iconframe-sheen-mask", sheenCentered = false,
  },
}


-- ============================================================================
-- MASK helpers — guarded; degrade if CreateMaskTexture or the atlas isn't available.
-- ============================================================================

-- Try to create + apply a mask to a region. Returns the mask on success, nil on failure.
local function tryMask(parent, target, atlasName)
  if not (parent and target and parent.CreateMaskTexture) then return nil end
  local ok, mask = pcall(parent.CreateMaskTexture, parent)
  if not ok or not mask then return nil end
  local applied = false
  if NE.tex and NE.tex.SetAtlasMask then applied = NE.tex.SetAtlasMask(mask, atlasName) end
  if not applied then return nil end
  if not target.AddMaskTexture then return nil end
  local ok2 = pcall(target.AddMaskTexture, target, mask)
  if not ok2 then return nil end
  return mask
end

-- ============================================================================
-- CARD FACTORY. One spell = one card (backplate + 40x40 secure icon button + name/subname).
-- ============================================================================
local function createCard(i)
  local h = host()
  local card = CreateFrame("Frame", "NE_SpellBookCard" .. i, h)
  card:SetSize(CARD_W, CARD_H)

  card.Backplate = card:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(card.Backplate, "spellbook-item-backplate", true)
  card.Backplate:SetPoint("CENTER", 5, -5)
  card.Backplate:SetAlpha(0.25)

  -- icon button (secure cast)
  local b = CreateFrame("Button", "NE_SpellBookCard" .. i .. "Btn", card, "SecureActionButtonTemplate")
  b:SetAllPoints(card)   -- the WHOLE cell is the secure cast button — click anywhere on it to cast
  -- UP-only: the secure cast fires on RELEASE, so a drag cancels the click and never casts.
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  b:RegisterForDrag("LeftButton")
  card.Button = b

  -- 40x40 icon SLOT pinned to the cell's LEFT. b fills the WHOLE cell (for cell-wide click/hover),
  -- so every icon visual (Icon, Border, mask, highlight, sheen) + the name anchors to this slot, NOT
  -- to b — otherwise applyCardVisual's b-relative border anchoring stretches the frame across the cell.
  b.IconSlot = CreateFrame("Frame", nil, b)
  b.IconSlot:SetSize(ICON_BTN, ICON_BTN)
  b.IconSlot:SetPoint("LEFT", b, "LEFT", 0, 0)

  b.Icon = b:CreateTexture(nil, "ARTWORK", nil, -1)
  b.Icon:SetSize(ICON, ICON)
  b.Icon:SetPoint("CENTER", b.IconSlot, "CENTER")
  -- mask is (re)applied per-visual in applyCardVisual (square vs circle); default inset fallback.
  b.Icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)

  b.Border = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.Border:SetAllPoints(b.IconSlot)

  -- Pet auto-cast overlay: corners when autocast allowed, spinning ants when enabled.
  local ov = CreateFrame("Frame", nil, b)
  ov:SetPoint("TOPLEFT", b.Icon, "TOPLEFT", 0, -1.5)
  ov:SetPoint("BOTTOMRIGHT", b.Icon, "BOTTOMRIGHT", -1.5, 1)
  ov:Hide()
  local ants = ov:CreateTexture(nil, "OVERLAY", nil, 0)
  local antsOk = NE.tex.SetAtlas(ants, "ui-hud-actionbar-petautocast-ants-2x", false)
  ants:SetPoint("TOPLEFT",     ov, "TOPLEFT",     -10,  10)
  ants:SetPoint("BOTTOMRIGHT", ov, "BOTTOMRIGHT",  10, -10)
  ants:Hide()
  if antsOk then tryMask(ov, ants, "spellbook-item-petautocast-mask") end
  local acAnim, acRot
  if ants.CreateAnimationGroup then
    acAnim = ants:CreateAnimationGroup()
    acAnim:SetLooping("REPEAT")
    acRot = acAnim:CreateAnimation("Rotation")
    if acRot then acRot:SetDegrees(-360); acRot:SetDuration(4); acRot:SetOrigin("CENTER", 0, 0) end
  end
  local acCorners = ov:CreateTexture(nil, "OVERLAY", nil, 1)
  NE.tex.SetAtlas(acCorners, "spellbook-item-petautocast-corners", false)
  acCorners:SetAllPoints(ov)
  ov.Shine, ov.ShineAnim, ov.Corners, ov.antsOk = ants, acAnim, acCorners, antsOk and true or false
  function ov:ShowAutoCastEnabled(isEnabled)
    self.autoCastEnabled = isEnabled
    self:UpdateShineAnim()
  end
  function ov:UpdateShineAnim()
    local shouldPlay = self.autoCastEnabled and self:IsShown() and self.antsOk
    if not self.ShineAnim then
      if self.Shine then if shouldPlay then self.Shine:Show() else self.Shine:Hide() end end
      return
    end
    local playing = self.ShineAnim:IsPlaying()
    if shouldPlay and not playing then self.ShineAnim:Play()
    elseif not shouldPlay and playing then self.ShineAnim:Stop() end
    if self.Shine then if shouldPlay then self.Shine:Show() else self.Shine:Hide() end end
  end
  ov:SetScript("OnShow", ov.UpdateShineAnim)
  ov:SetScript("OnHide", ov.UpdateShineAnim)
  b.AutoCastOverlay = ov

  b.IconHighlight = b:CreateTexture(nil, "OVERLAY", nil, 2)
  NE.tex.SetAtlas(b.IconHighlight, "spellbook-item-iconframe-hover", false)
  b.IconHighlight:SetAllPoints(b.Border)
  b.IconHighlight:SetBlendMode("ADD")
  b.IconHighlight:SetAlpha(0.35)
  b.IconHighlight:Hide()

  -- swept sheen (guarded — skipped entirely if its mask can't be built).
  b.sheen = b:CreateTexture(nil, "OVERLAY", nil, 3)
  local sheenOk = NE.tex.SetAtlas(b.sheen, "talents-sheen-node", true)
  if sheenOk then
    b.sheen:SetBlendMode("ADD")
    b.sheen:SetAlpha(0.5)
    b.sheen:SetPoint("RIGHT", b.Border, "LEFT")
    b.sheenMask = tryMask(b, b.sheen, "spellbook-item-iconframe-sheen-mask")
    if b.sheenMask then
      b.sheenMask:SetPoint("TOPLEFT", b.Border)
      b.sheenMask:SetPoint("BOTTOMRIGHT", b.Border)
      b.sheenHome = b
      registerSheen(b)
    else
      b.sheen:Hide()   -- no mask → skip the sheen (cosmetic)
      b.sheen = nil
    end
  else
    b.sheen = nil
  end


  -- name / subname
  card.Name = card:CreateFontString(nil, "ARTWORK", "GameFontHighlightLarge")
  card.Name:SetJustifyH("LEFT")
  card.Name:SetPoint("TOPLEFT", b.Border, "TOPRIGHT", 10, -1)
  card.Name:SetPoint("RIGHT", card, "RIGHT", -4, 0)
  if card.Name.SetWordWrap then card.Name:SetWordWrap(true) end
  if card.Name.SetMaxLines then card.Name:SetMaxLines(2) end
  card.Name:SetShadowColor(0, 0, 0, 0)

  card.SubName = card:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  card.SubName:SetJustifyH("LEFT")
  card.SubName:SetPoint("TOPLEFT", card.Name, "BOTTOMLEFT", 0, -2)
  card.SubName:SetPoint("RIGHT", card.Name, "RIGHT")
  card.SubName:SetTextColor(0.82, 0.74, 0.55)
  card.SubName:SetShadowColor(0, 0, 0, 0)

  -- tooltip + drag + hover. The hover (tooltip + cell highlight) covers the WHOLE cell, not just the
  -- 40x40 icon: the same handlers sit on both the card frame and the icon button. OnLeave guards on
  -- card:IsMouseOver() so crossing the icon/text seam (focus passing card<->button) never flickers
  -- the tooltip — it only clears when the cursor actually leaves the cell. Anchored to the card so
  -- the tooltip is positioned off the whole cell.
  local function cardEnter()
    if not card.unlearned then
      card.Button.IconHighlight:SetAlpha(0.35)
      card.Button.IconHighlight:Show()
      card.Backplate:SetAlpha(1)
    end
    GameTooltip:SetOwner(card, "ANCHOR_RIGHT")
    if card.slot and GameTooltip.SetSpellBookItem then
      GameTooltip:SetSpellBookItem(card.slot, card.bookType)
      GameTooltip:Show()
    elseif card.spellID and GameTooltip.SetSpellByID then
      GameTooltip:SetSpellByID(card.spellID)
      GameTooltip:Show()
    elseif card.tipName then
      GameTooltip:SetText(card.tipName, 1, 1, 1, 1, true)
      if card.tipSub and card.tipSub ~= "" then GameTooltip:AddLine(card.tipSub, 0.6, 0.6, 0.6, true) end
      GameTooltip:Show()
    end
  end
  local function cardLeave()
    if card:IsMouseOver() then return end   -- moved onto the icon button (still in-cell) → keep hover
    card.Button.IconHighlight:Hide()
    card.Button.IconHighlight:SetAlpha(0.35)
    card.Backplate:SetAlpha(0.25)
    GameTooltip:Hide()
  end
  card:EnableMouse(true)
  card:SetScript("OnEnter", cardEnter)
  card:SetScript("OnLeave", cardLeave)
  b:SetScript("OnEnter", cardEnter)
  b:SetScript("OnLeave", cardLeave)
  b:HookScript("OnMouseDown", function()
    if not card.unlearned then card.Button.IconHighlight:SetAlpha(0.65) end
  end)
  b:HookScript("OnMouseUp", function()
    if not card.unlearned then card.Button.IconHighlight:SetAlpha(0.35) end
  end)
  b:SetScript("OnDragStart", function()
    if card.passive then return end   -- passives are click/drag-inert (still hover for tooltip)
    if card.slot and not InCombatLockdown() and PickupSpellBookItem then
      PickupSpellBookItem(card.slot, card.bookType)
    end
  end)

  -- Modified clicks: shift=link, ctrl=pickup. Blank the secure action under those modifiers so
  -- the cast doesn't swallow them. (Right-click does NOTHING — pet autocast-toggle is disallowed.)
  b:SetAttribute("shift-type*", "")
  b:SetAttribute("ctrl-type*", "")
  b:HookScript("OnClick", function(self, btn, down)
    if down or card.passive then return end   -- passives: no link / pickup / any click action
    if IsModifiedClick and IsModifiedClick("CHATLINK") then
      if card.slot and GetSpellLink and ChatEdit_InsertLink then
        local link = GetSpellLink(card.slot, card.bookType)
        if link then ChatEdit_InsertLink(link) end
      elseif card.spellID and GetSpellLink and ChatEdit_InsertLink then
        local link = GetSpellLink(card.spellID)
        if link then ChatEdit_InsertLink(link) end
      end
    elseif IsModifiedClick and IsModifiedClick("PICKUPACTION") then
      if card.slot and not InCombatLockdown() and PickupSpellBookItem then
        PickupSpellBookItem(card.slot, card.bookType)
      end
    end
  end)

  SB.cards[i] = card
  return card
end

-- ============================================================================
-- BOOK BACKGROUND — evergreen panels stretched to fill the host halves.
-- ============================================================================
local function buildBackground()
  local h = host()
  if SB.bgFill or not h then return end
  local function track(t) SB.bgParts[#SB.bgParts + 1] = t; return t end

  SB.bgFill = track(h:CreateTexture(nil, "BACKGROUND", nil, -3))
  if SB.bgFill.SetColorTexture then SB.bgFill:SetColorTexture(0.03, 0.04, 0.03, 1)
  else SB.bgFill:SetTexture(0.03, 0.04, 0.03, 1) end
  SB.bgFill:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
  SB.bgFill:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 0)

  SB.bgLeft = track(h:CreateTexture(nil, "BACKGROUND", nil, -2))
  NE.tex.SetAtlas(SB.bgLeft, "spellbook-background-evergreen-left", false)
  SB.bgLeft:SetPoint("TOPLEFT", h, "TOPLEFT", BG_INSET_X, PAGES_TOP)
  SB.bgLeft:SetPoint("BOTTOMRIGHT", h, "BOTTOM", -1, PAGES_BOT)

  SB.bgRight = track(h:CreateTexture(nil, "BACKGROUND", nil, -2))
  NE.tex.SetAtlas(SB.bgRight, "spellbook-background-evergreen-right", false)
  SB.bgRight:SetPoint("TOPLEFT", h, "TOP", 1, PAGES_TOP)
  SB.bgRight:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -BG_INSET_X, PAGES_BOT)

  SB.bgRibbon = track(h:CreateTexture(nil, "BACKGROUND", nil, -1))
  NE.tex.SetAtlas(SB.bgRibbon, "spellbook-background-evergreen-ribbon", false)
  SB.bgRibbon:SetWidth(102)
  SB.bgRibbon:SetPoint("TOP", h, "TOP", 0, PAGES_TOP)
  SB.bgRibbon:SetPoint("BOTTOM", h, "BOTTOM", 0, PAGES_BOT)

  SB.bgHeader = track(h:CreateTexture(nil, "BORDER", nil, 0))
  NE.tex.SetAtlas(SB.bgHeader, "spellbook-background-evergreen-header", false)
  SB.bgHeader:SetHeight(HEADER_H)
  SB.bgHeader:SetPoint("TOPLEFT", h, "TOPLEFT", 8, BG_TOP)
  SB.bgHeader:SetPoint("TOPRIGHT", h, "TOPRIGHT", -8, BG_TOP)
end

-- Sync the bg halves to the minimized state.
local function applyBgWidth()
  local h = host()
  if not (h and SB.bgLeft) then return end
  if SB.bgRight  then if SB.minimized then SB.bgRight:Hide()  else SB.bgRight:Show()  end end
  if SB.bgRibbon then if SB.minimized then SB.bgRibbon:Hide() else SB.bgRibbon:Show() end end
  NE.tex.SetAtlas(SB.bgLeft,
    SB.minimized and "spellbook-background-evergreen-right" or "spellbook-background-evergreen-left", false)
  SB.bgLeft:ClearAllPoints()
  SB.bgLeft:SetPoint("TOPLEFT", h, "TOPLEFT", BG_INSET_X, PAGES_TOP)
  if SB.minimized then
    SB.bgLeft:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, PAGES_BOT)
  else
    SB.bgLeft:SetPoint("BOTTOMRIGHT", h, "BOTTOM", -1, PAGES_BOT)
  end
end
SB._applyBgWidth = applyBgWidth

-- ============================================================================
-- CATEGORY TABS — General / class / Pet along the top, using this addon's reskin.
-- ============================================================================
local function categoryTab(i)
  local t = SB.catTabs[i]
  if t then return t end
  local h = host()
  t = CreateFrame("Button", "NE_SpellBookPageTab" .. i, h, "CharacterFrameTabButtonTemplate")
  t:SetID(i)
  t:SetHeight(TAB_H_INACTIVE)
  t:SetScript("OnClick", function(self)
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    elseif PlaySound then PlaySound("igCharacterInfoTab") end
    SB.SelectCategory(self:GetID())
  end)
  if NE.tabs and NE.tabs.ReskinClassicTab then NE.tabs.ReskinClassicTab(t:GetName()) end
  -- NOTE: MakeTopTab (vertical-flip polish) anchored the tab body rising UP into the chrome
  -- title band, where it was clipped/covered → tabs looked invisible. Dropped: plain
  -- bottom-anchored tabs read normally and stay on the header band (correctness over polish).
  -- Raise the tabs above the book-background textures so they're not painted over.
  local h2 = host()
  if h2 and t.SetFrameLevel then t:SetFrameLevel((h2:GetFrameLevel() or 1) + 6) end
  SB.catTabs[i] = t
  return t
end

-- Drive a reskinned tab's selected/deselected ART manually (same as the Character panel's
-- TabButtons.setTabArt). ReskinClassicTab paints the ACTIVE/gold atlas onto the *Disabled pieces,
-- so SELECTED → show the *Disabled (gold) pieces + hide the regular ones; DESELECTED → reverse.
-- (PanelTemplates_SetTab doesn't honour the reskin, which is why every tab read as active.) Also
-- mute the custom hover highlight on the selected tab so it doesn't bleed over the gold art.
local function setTabArt(tab, selected)
  if not tab then return end
  local n = tab:GetName()
  local function set(suffix, show)
    local t = _G[n .. suffix]
    if t then if show then t:Show() else t:Hide() end end
  end
  set("Left",  not selected); set("Middle",  not selected); set("Right",  not selected)
  set("LeftDisabled", selected); set("MiddleDisabled", selected); set("RightDisabled", selected)
  if tab.SetHeight then tab:SetHeight(selected and TAB_H_ACTIVE or TAB_H_INACTIVE) end
  local hl = tab._neCustomHL
  if hl then
    local a = selected and 0 or 0.4
    if hl.left   and hl.left.SetAlpha   then hl.left:SetAlpha(a)   end
    if hl.middle and hl.middle.SetAlpha then hl.middle:SetAlpha(a) end
    if hl.right  and hl.right.SetAlpha  then hl.right:SetAlpha(a)  end
  end
end

-- ============================================================================
-- CATEGORIES — General (tab 1) + the class (tabs 2..N as sections) + a live pet category.
-- LEARNED-ONLY: no ClassSpells seed / petdata catalog.
-- ============================================================================
local function buildCategories()
  local cats = {}
  local numTabs = (GetNumSpellTabs and GetNumSpellTabs()) or 0
  -- FLAT "General" (spell tab 1) FIRST: on 3.3.5a it reliably holds most learned spells, so this
  -- is the category that yields a populated default view. The sectioned class category (spec tabs
  -- 2..N) follows — those tabs are often sparse/empty at low/mid level.
  local generalIdx
  if numTabs >= 1 then
    local name, _, offset, numSlots = GetSpellTabInfo(1)
    cats[#cats + 1] = { kind = "flat", label = name or (GENERAL or "General"),
                        sections = { { offset = offset or 0, numSlots = numSlots or 0 } } }
    generalIdx = #cats
  end
  if numTabs >= 2 then
    local className = UnitClass and UnitClass("player") or "Class"
    local sections = {}
    for i = 2, numTabs do
      local sName, _, offset, numSlots = GetSpellTabInfo(i)
      if numSlots and numSlots > 0 then
        sections[#sections + 1] = { title = sName, offset = offset, numSlots = numSlots }
      end
    end
    cats[#cats + 1] = { kind = "sectioned", label = className, sections = sections }
  end
  local numPet = (HasPetSpells and HasPetSpells()) or 0
  if numPet and numPet > 0 then
    cats[#cats + 1] = { kind = "pet", label = PET or "Pet", numSlots = numPet }
  end
  SB.categories = cats
  SB.generalIdx = generalIdx
  return cats
end

-- Total raw slot count a category covers (used to pick a non-empty default category).
local function catSlotCount(cat)
  if not cat then return 0 end
  if cat.kind == "pet" then return cat.numSlots or 0 end
  local total = 0
  for _, sec in ipairs(cat.sections or {}) do total = total + (sec.numSlots or 0) end
  return total
end

-- Pick the default selected category: first one that actually has slots (General reliably does).
local function pickDefaultSelected(cats)
  -- Prefer General if it has spells.
  if SB.generalIdx and cats[SB.generalIdx] and catSlotCount(cats[SB.generalIdx]) > 0 then
    return SB.generalIdx
  end
  for i, cat in ipairs(cats) do
    if catSlotCount(cat) > 0 then return i end
  end
  return 1
end
SB._pickDefaultSelected = pickDefaultSelected

function SB.SelectCategory(index)
  SB.selected = index
  SB.userPickedCategory = true
  SB.page = 1
  SB.Refresh()
end

-- ============================================================================
-- PAGING controls (bottom-right): prev / next + "Page N/M".
-- ============================================================================
local function buildPaging()
  if SB.paging then return SB.paging end
  local h = host()
  if not h then return nil end
  local p = CreateFrame("Frame", "NE_SpellBookPaging", h)
  p:SetSize(146, 32)
  p:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -75, 40)

  p.label = p:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  p.label:SetJustifyH("LEFT")
  p.label:SetPoint("LEFT", 0, 0)
  p.label:SetTextColor(0, 0, 0)
  p.label:SetShadowColor(0, 0, 0, 0)

  local function pageButton(prefix, onClick)
    local b = CreateFrame("Button", nil, p)
    b:SetSize(32, 32)
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. prefix .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. prefix .. "Page-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. prefix .. "Page-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", onClick)
    return b
  end
  p.prev = pageButton("Prev", function() SB.SetPage(SB.page - 1) end)
  p.next = pageButton("Next", function() SB.SetPage(SB.page + 1) end)
  p.next:SetPoint("RIGHT", 0, 0)
  p.prev:SetPoint("RIGHT", p.next, "LEFT", -8, 0)

  SB.paging = p
  return p
end

function SB.SetPage(n)
  local total = SB.totalPages or 1
  if n < 1 then n = 1 elseif n > total then n = total end
  SB.page = n
  SB.RenderCards()
end

-- ============================================================================
-- DATA — build the flat render-element list (section headers + spell cards).
-- ============================================================================
local function matchesSearch(name)
  if SB.search == "" then return true end
  return name ~= nil and name:lower():find(SB.search, 1, true) ~= nil
end

local function makeCardEntry(slot, bookType)
  local name, subName = GetSpellBookItemName(slot, bookType)
  if not name then return nil end
  local slotType, spellID = GetSpellBookItemInfo(slot, bookType)
  return {
    kind = "card", slot = slot, bookType = bookType, name = name, subName = subName,
    spellID = spellID, passive = IsPassiveSpell and IsPassiveSpell(slot, bookType) or false,
    icon = slotIcon(slot, bookType, spellID),
  }
end

-- Rank collapse: when "Show All Ranks" is OFF, keep only the highest rank of each spell (parsed
-- from the "Rank N" subtext). Entries with no parseable rank (passives w/o ranks, summons, etc.)
-- are kept as-is. Order is preserved by the position of each spell's FIRST-seen card.
local function collapseRanks(list)
  local out, idxByName = {}, {}
  for _, e in ipairs(list) do
    local rank = tonumber((e.subName or ""):match("(%d+)"))
    local prev = rank and idxByName[e.name]
    if prev then
      if rank > (out[prev]._rank or 0) then e._rank = rank; out[prev] = e end
    else
      e._rank = rank
      out[#out + 1] = e
      if rank then idxByName[e.name] = #out end
    end
  end
  return out
end

-- learned-spell slot scanner → emit cards (honours search + Hide Passives + Show All Ranks).
local function addCards(els, offset, count, bookType)
  local list = {}
  for s = offset + 1, offset + count do
    local e = makeCardEntry(s, bookType)
    if e and matchesSearch(e.name) and not (SB.hidePassives and e.passive) then
      list[#list + 1] = e
    end
  end
  if not SB.showRanks then list = collapseRanks(list) end
  for _, e in ipairs(list) do els[#els + 1] = e end
  return #list
end

local function buildElements()
  local cats = SB.categories or buildCategories()
  if SB.selected > #cats then SB.selected = 1 end
  local cat = cats[SB.selected]
  local els = {}

  if cat then
    if cat.kind == "pet" then
      addCards(els, 0, cat.numSlots, BOOKTYPE_PET_)
    elseif cat.kind == "sectioned" then
      for _, sec in ipairs(cat.sections) do
        local headerIdx = #els + 1
        els[#els + 1] = { kind = "header", label = sec.title }
        if addCards(els, sec.offset, sec.numSlots, BOOKTYPE_SPELL_) == 0 then
          table.remove(els, headerIdx)
        end
      end
    else  -- flat (General)
      local sec = cat.sections[1]
      if sec then addCards(els, sec.offset, sec.numSlots, BOOKTYPE_SPELL_) end
    end
  end
  SB.elements = els
  return els
end
SB._buildElements = buildElements

-- FLOW layout: 3 cards per row; a header spans the full page width and forces a fresh row.
local function flowLayout(els)
  local R, p, r, c = rows, 0, 0, 0
  local function advance() r = r + 1; if r >= R then r = 0; p = p + 1 end end
  for _, e in ipairs(els) do
    if e.kind == "header" then
      if c > 0 then c = 0; advance() end
      e.p, e.r = p, r
      advance(); c = 0
    else
      e.p, e.r, e.c = p, r, c
      c = c + 1
      if c >= GRID_COLS then c = 0; advance() end
    end
  end
  local maxP = 0
  for _, e in ipairs(els) do if e.p and e.p > maxP then maxP = e.p end end
  SB.totalPages = math.max(1, math.ceil((maxP + 1) / (SB.minimized and 1 or 2)))
end

-- Cell → (point, relPoint, x, y). Left page from host LEFT; right page from host RIGHT.
local function pagePoint(p, r, c)
  local y = VIEW_TOP - r * ROW_H
  if SB.minimized or (p % 2) == 0 then
    return "TOPLEFT", "TOPLEFT", VIEW1_X + (c or 0) * (CARD_W + CARD_XPAD), y
  else
    return "TOPLEFT", "TOPRIGHT", (VIEW2_X - VIEW_W) + (c or 0) * (CARD_W + CARD_XPAD), y
  end
end

-- ============================================================================
-- SECTION HEADER — list-backplate plate + SystemFont_Huge2 title + divider.
-- ============================================================================
local function createHeader(i)
  local h = CreateFrame("Frame", nil, host())
  h:SetSize(SPAN_W, 51)
  h.Plate = h:CreateTexture(nil, "BACKGROUND")
  NE.tex.SetAtlas(h.Plate, "spellbook-list-backplate", false)
  h.Plate:SetSize(416, 106)
  h.Plate:SetPoint("LEFT", h, "LEFT", -85, 10)
  h.Plate:SetAlpha(0.65)
  h.Text = h:CreateFontString(nil, "ARTWORK", SECTION_TITLE_FONT)
  h.Text:SetJustifyH("LEFT")
  h.Text:SetPoint("TOPLEFT", -8, 0)
  h.Text:SetPoint("BOTTOMRIGHT", -60, 0)
  h.Text:SetTextColor(spellbookInk())
  h.Border = h:CreateTexture(nil, "ARTWORK")
  NE.tex.SetAtlas(h.Border, "spellbook-divider", false)
  h.Border:SetHeight(11)
  h.Border:SetPoint("BOTTOMLEFT", -32, 0)
  h.Border:SetPoint("BOTTOMRIGHT", -60, 0)
  SB.headers[i] = h
  return h
end

-- Pet autocast overlay state → reads legacy GetSpellAutocast.
function SB.UpdateAutoCast(card)
  local ov = card.Button and card.Button.AutoCastOverlay
  if not ov then return end
  local allowed, enabled = false, false
  if card.slot and card.bookType == BOOKTYPE_PET_ and GetSpellAutocast then
    allowed, enabled = GetSpellAutocast(card.slot, card.bookType)
  end
  if allowed then ov:Show() else ov:Hide() end
  ov:ShowAutoCastEnabled(enabled and true or false)
end

-- ============================================================================
-- APPLY a card's visual — square (active) vs circle (passive) art + mask fallbacks.
-- ============================================================================
local function applyCardVisual(card, e)
  card.slot, card.bookType, card.spellID = e.slot, e.bookType, e.spellID
  card.passive = e.passive and true or false   -- passive cells are click/drag-inert
  card.unlearned = false
  local b = card.Button
  b.Icon:SetTexture(e.icon or 134400)
  card.Name:SetText(e.name or "")
  card.SubName:SetText(e.subName or "")

  card.tipName = (not e.slot and not e.spellID) and e.name or nil
  card.tipSub  = e.subName

  local ir, ig, ib = spellbookInk()
  card.Name:SetTextColor(ir, ig, ib)
  card.SubName:SetTextColor(ir, ig, ib)
  card.Name:SetAlpha(1); card.SubName:SetAlpha(1)
  b.Icon:SetDesaturated(false)
  b.Icon:SetAlpha(1)

  -- art set: square (active) vs circle (passive).
  local art = e.passive and ART_SET.passive or ART_SET.square

  -- border. SetAtlas fails gracefully (returns false, leaves prior); for the circle ring this
  -- is the degrade path — the grey ring may or may not exist, but the icon still shows.
  NE.tex.SetAtlas(b.Border, art.border, false)
  -- Passives reuse the gold frame, desaturated to silver/grey (reset to colour for actives so a
  -- reused card never stays grey).
  if b.Border.SetDesaturated then b.Border:SetDesaturated(art.desaturate and true or false) end
  local tl, br = art.borderTL, art.borderBR
  b.Border:ClearAllPoints()
  b.Border:SetPoint("TOPLEFT",     b.IconSlot, "TOPLEFT",     tl[1], tl[2])
  b.Border:SetPoint("BOTTOMRIGHT", b.IconSlot, "BOTTOMRIGHT", br[1], br[2])

  -- icon mask: rebuild per shape. If the mask can't be made, inset the square icon via texcoord
  -- (square-in-ring for passive — accepted), else show the masked icon.
  if b._iconMask then
    if b.Icon.RemoveMaskTexture then pcall(b.Icon.RemoveMaskTexture, b.Icon, b._iconMask) end
    b._iconMask:Hide()
    b._iconMask = nil
  end
  b.Icon:SetTexCoord(0, 1, 0, 1)
  local m = tryMask(b, b.Icon, art.iconMask)
  if m then
    b._iconMask = m
    m:ClearAllPoints()
    m:SetPoint("TOPLEFT", b.Icon, "TOPLEFT")
    m:SetPoint("BOTTOMRIGHT", b.Icon, "BOTTOMRIGHT")
  else
    -- DEGRADE: no working mask → inset the icon under the frame.
    b.Icon:SetTexCoord(0.06, 0.94, 0.06, 0.94)
  end

  NE.tex.SetAtlas(b.IconHighlight, art.iconHighlight, false)

  -- sheen (only present when its mask built at create time).
  b._wantSheen = true
  if b.sheen and b.sheenMask then
    b.sheenMask:ClearAllPoints()
    if art.sheenCentered then
      b.sheenMask:SetPoint("CENTER", b.Border, "CENTER")
      local w = (b.Border:GetWidth() ~= 0 and b.Border:GetWidth()) or ICON_BTN
      local hgt = (b.Border:GetHeight() ~= 0 and b.Border:GetHeight()) or ICON_BTN
      b.sheenMask:SetSize(w, hgt)
    else
      b.sheenMask:SetPoint("TOPLEFT", b.Border)
      b.sheenMask:SetPoint("BOTTOMRIGHT", b.Border)
    end
  end

  -- secure cast attribute. Passive spells aren't castable; pet right-click toggles autocast.
  local isPetSlot = (e.bookType == BOOKTYPE_PET_) and e.slot ~= nil
  if not InCombatLockdown() then
    if e.passive then
      b:SetAttribute("type", nil); b:SetAttribute("spell", nil)
    else
      b:SetAttribute("type", "spell"); b:SetAttribute("spell", e.name)
    end
    b:SetAttribute("type2", isPetSlot and "" or nil)
  end

  SB.UpdateAutoCast(card)
end

-- ============================================================================
-- RENDER the current spread.
-- ============================================================================
function SB.RenderCards()
  -- The card icon buttons are secure; reflowing in combat is forbidden. Defer to regen.
  if InCombatLockdown() then SB.refreshQueued = true; return end

  local els = SB.elements or {}
  flowLayout(els)
  if SB.page > (SB.totalPages or 1) then SB.page = SB.totalPages or 1 end

  local curSpread = SB.page - 1
  local h = host()
  local ci, hi = 0, 0
  for _, e in ipairs(els) do
    local onSpread = (math.floor((e.p or 0) / (SB.minimized and 1 or 2)) == curSpread)
    if e.kind == "card" then
      ci = ci + 1
      local card = SB.cards[ci] or createCard(ci)
      if onSpread then
        local pt, rp, x, y = pagePoint(e.p, e.r, e.c)
        card:ClearAllPoints(); card:SetPoint(pt, h, rp, x, y)
        applyCardVisual(card, e)
        card:Show()
      else
        card:Hide()
      end
    else  -- section header
      hi = hi + 1
      local hd = SB.headers[hi] or createHeader(hi)
      if onSpread then
        local pt, rp, x, y = pagePoint(e.p, e.r, 0)
        if (e.r or 0) > 0 then y = y - SECTION_TOP_GAP end
        hd:ClearAllPoints(); hd:SetPoint(pt, h, rp, x, y)
        hd.Text:SetText(e.label or "")
        hd:Show()
      else
        hd:Hide()
      end
    end
  end
  for i = ci + 1, #SB.cards   do SB.cards[i]:Hide()   end
  for i = hi + 1, #SB.headers do SB.headers[i]:Hide() end

  if SB.paging then
    SB.paging.label:SetText(("Page %d/%d"):format(SB.page, SB.totalPages or 1))
    if SB.paging.prev.SetEnabled then SB.paging.prev:SetEnabled(SB.page > 1)
    elseif SB.page > 1 then SB.paging.prev:Enable() else SB.paging.prev:Disable() end
    if SB.paging.next.SetEnabled then SB.paging.next:SetEnabled(SB.page < (SB.totalPages or 1))
    elseif SB.page < (SB.totalPages or 1) then SB.paging.next:Enable() else SB.paging.next:Disable() end
    SB.paging:Show()
  end
end

-- ============================================================================
-- SEARCH box — filters cards by name.
-- ============================================================================
local function buildSearch()
  if SB.searchBox then return SB.searchBox end
  local h = host()
  if not h then return nil end
  -- SELF-CONTAINED search box: a bare EditBox, NOT the shared "SearchBoxTemplate". Other addons
  -- (e.g. ezCollections) ship their own Interface\SharedXML that redefines SearchBoxTemplate plus a
  -- broken InputBoxInstructions_OnLoad; templates are global-by-name, so whichever loads last wins —
  -- and CreateFrame would then run their faulty OnLoad and error. We build the border / magnifier /
  -- placeholder ourselves so the search box is immune to any other addon's template redefinitions.
  local sb = CreateFrame("EditBox", "NE_SpellBookSearchBox", h)
  sb:SetSize(200, 28)
  sb:SetPoint("TOPRIGHT", h, "TOPRIGHT", -42, -10)
  sb:SetAutoFocus(false)
  sb:SetFontObject(_G.ChatFontNormal or _G.GameFontHighlightSmall)   -- font OBJECT, not a string
  sb:SetTextInsets(24, 8, 0, 0)   -- leave room for the magnifier icon at the left
  sb:SetMaxLetters(40)
  sb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  sb:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)

  -- Border — manual backdrop using guaranteed 3.3.5a art (SetBackdrop is guarded).
  if sb.SetBackdrop then
    sb:SetBackdrop({
      bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      tile = true, tileSize = 16, edgeSize = 12,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    sb:SetBackdropColor(0, 0, 0, 0.6)
    sb:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
  end

  -- Magnifier icon (guarded path: blank if the file is absent, never errors).
  local icon = sb:CreateTexture(nil, "OVERLAY")
  icon:SetSize(14, 14)
  icon:SetPoint("LEFT", sb, "LEFT", 6, 0)
  icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
  sb.searchIcon = icon

  -- Placeholder ("Search") — a SEPARATE FontString shown only when empty+unfocused, so GetText() is
  -- genuinely "" when empty (the old SearchBoxTemplate reported its placeholder AS the text).
  local ph = sb:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
  ph:SetPoint("LEFT", sb, "LEFT", 24, 0)
  ph:SetText(_G.SEARCH or "Search")
  sb.placeholder = ph

  local function applyFilter()
    local q = (sb:GetText() or ""):lower()
    if q ~= SB.search then
      SB.search = q
      SB.page = 1
      buildElements()
      SB.RenderCards()
    end
  end
  sb:SetScript("OnTextChanged", function(self)
    if sb.placeholder then
      if (self:GetText() or "") == "" then sb.placeholder:Show() else sb.placeholder:Hide() end
    end
    applyFilter()
  end)
  sb:SetScript("OnEditFocusGained", function() if sb.placeholder then sb.placeholder:Hide() end end)
  sb:SetScript("OnEditFocusLost", function(self)
    if sb.placeholder and (self:GetText() or "") == "" then sb.placeholder:Show() end
  end)

  SB.searchBox = sb
  return sb
end

-- ============================================================================
-- COG — settings popup with Hide Passives + Show All Ranks. 3.3.5a has no MenuUtil, so we
-- build a small custom popup of checkbuttons (no taint risk — purely insecure UI).
-- ============================================================================
local function buildCogMenu(cog)
  if SB.cogMenu then return SB.cogMenu end
  local menu = CreateFrame("Frame", "NE_SpellBookCogMenu", cog)
  menu:SetSize(180, 88)
  menu:SetFrameStrata("DIALOG")
  menu:SetPoint("TOPRIGHT", cog, "BOTTOMRIGHT", 0, -2)
  if menu.SetBackdrop then
    menu:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 16, edgeSize = 16,
      insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
  end
  menu:Hide()
  menu:EnableMouse(true)

  local title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText(SPELLBOOK or "Spellbook")

  local function checkRow(label, getfn, setfn, y)
    local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
    cb:SetSize(20, 20)
    cb:SetPoint("TOPLEFT", 10, y)
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
    cb:SetChecked(getfn())
    cb:SetScript("OnClick", function(self)
      setfn(self:GetChecked() and true or false)
    end)
    cb._sync = function() cb:SetChecked(getfn()) end
    return cb
  end

  menu.cbPassives = checkRow(SPELLBOOK_FILTER_PASSIVES or "Hide Passives",
    function() return SB.hidePassives end,
    function(v) SB.hidePassives = v; saveOpts(); SB.page = 1; buildElements(); SB.RenderCards() end, -30)
  menu.cbRanks = checkRow("Show All Ranks",
    function() return SB.showRanks end,
    function(v) SB.showRanks = v; saveOpts(); SB.page = 1; buildElements(); SB.RenderCards() end, -54)

  menu:SetScript("OnShow", function(self)
    if self.cbPassives and self.cbPassives._sync then self.cbPassives._sync() end
    if self.cbRanks and self.cbRanks._sync then self.cbRanks._sync() end
  end)
  SB.cogMenu = menu
  return menu
end

local function buildCog()
  if SB.cog then return SB.cog end
  local h = host()
  if not h then return nil end
  local cog = CreateFrame("Button", "NE_SpellBookCog", h)
  cog:SetSize(16, 18)
  cog:SetPoint("TOPRIGHT", h, "TOPRIGHT", -14, -16)   -- on the wood header, aligned with the tab row
  cog.Icon = cog:CreateTexture(nil, "ARTWORK")
  if not NE.tex.SetAtlas(cog.Icon, "questlog-icon-setting", true) then
    cog.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog.Icon:SetSize(16, 16)
  end
  cog.Icon:SetPoint("CENTER")
  cog.Hi = cog:CreateTexture(nil, "HIGHLIGHT")
  if not NE.tex.SetAtlas(cog.Hi, "questlog-icon-setting", true) then
    cog.Hi:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog.Hi:SetSize(16, 16)
  end
  cog.Hi:SetPoint("CENTER")
  cog.Hi:SetBlendMode("ADD")
  cog.Hi:SetAlpha(0.4)
  cog:SetScript("OnClick", function(self)
    local menu = buildCogMenu(self)
    if menu:IsShown() then menu:Hide() else menu:Show() end
  end)
  -- seat the search box immediately to the cog's left.
  if SB.searchBox then
    SB.searchBox:ClearAllPoints()
    SB.searchBox:SetPoint("RIGHT", cog, "LEFT", -6, 0)
  end
  SB.cog = cog
  return cog
end

-- ============================================================================
-- BUILD / REFRESH — the renderer-side entry points (the window agent calls these).
-- ============================================================================
function SB.Build()
  if SB._built then return end
  local h = host()
  if not h then return end
  SB._built = true
  loadFilterOpts()   -- restore persisted Hide Passives / Show All Ranks (SV ready at PLAYER_LOGIN)
  buildBackground()
  buildPaging()
  buildSearch()
  buildCog()
end

function SB.Refresh()
  if not SB._built then SB.Build() end
  if not host() then return end
  if InCombatLockdown() then SB.refreshQueued = true end

  buildSearch()
  buildCog()
  applyBgWidth()

  local cats = buildCategories()
  if SB.selected > #cats then SB.selected = 1 end
  -- Default view = first category that actually has learned spells (General on 3.3.5a). Only
  -- auto-pick until the user manually clicks a tab; thereafter honour their choice.
  if not SB.userPickedCategory then
    SB.selected = pickDefaultSelected(cats)
  end

  -- build + chain the category tabs along the header line.
  local h = host()
  local prev
  for i, cat in ipairs(cats) do
    local t = categoryTab(i)
    t:SetText(cat.label)
    -- Width to text, same as the Character panel's resizeTab (reset → measure → max(min, w+pad)).
    local txt = _G[t:GetName() .. "Text"]
    local tw = 0
    if txt then txt:SetWidth(0); tw = txt:GetWidth() or 0 end
    t:SetWidth(math.max(TAB_MIN_W, math.floor(tw + TAB_TEXT_PAD)))
    t:ClearAllPoints()
    if prev then
      t:SetPoint("TOPLEFT", prev, "TOPRIGHT", TAB_GAP, 0)
    else
      t:SetPoint("TOPLEFT", h, "TOPLEFT", CAT_TAB_X, CAT_TAB_TOP)
    end
    t:Show()
    setTabArt(t, i == SB.selected)   -- selected → gold/active art (taller); others → dark/inactive
    prev = t
  end
  for i = #cats + 1, #SB.catTabs do SB.catTabs[i]:Hide() end

  buildElements()
  SB.RenderCards()
end

-- Load persisted filter options if the SV is already available at parse time (nil-safe;
-- SB.Build also calls loadFilterOpts at PLAYER_LOGIN when the SV is guaranteed loaded).
if optsTable() then loadFilterOpts() end
