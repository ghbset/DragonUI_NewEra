-- DragonUI_NewEra/core/Tabs.lua — reusable retail-style tab reskin for classic
-- CharacterFrameTabButtonTemplate-derived tabs.
--
-- DOWNPORT: NewEra Core/Tabs.lua → 3.3.5a. The 6-piece classic tab template
-- (Left/Middle/Right + *Disabled) and PanelTemplates_SelectTab semantics are IDENTICAL on 3.3.5a
-- (this is the same vanilla template Era inherited from), so the reskin logic ports directly.
-- Changes: (1) atlas-entry lookups route through NE.tex._atlasEntry (our coord registry) not the
-- NE_ATLAS global; (2) SetShown → Show/Hide in MakeSideTab:SetSelectedState (no SetShown on
-- 3.3.5a); (3) NE.tooltip.Wire is optional (provided by a sibling module, feature-gated).
--
-- §2 CONTRACT: NE.tabs.* surface preserved.

local NE = DragonUI_NewEra
NE.tabs = NE.tabs or {}

local ATLAS_BY_SUFFIX = {
  Left           = "uiframe-tab-left",
  Right          = "uiframe-tab-right",
  Middle         = "_uiframe-tab-center",
  LeftDisabled   = "uiframe-activetab-left",
  RightDisabled  = "uiframe-activetab-right",
  MiddleDisabled = "_uiframe-activetab-center",
}

local SIZE_BY_SUFFIX = {
  Left           = { w = 35, h = 36 },
  Right          = { w = 37, h = 36 },
  Middle         = { h = 36 },
  LeftDisabled   = { w = 35, h = 42 },
  RightDisabled  = { w = 37, h = 42 },
  MiddleDisabled = { h = 42 },
}

local function buildCustomHighlight(tab)
  if tab._neCustomHL then return end
  if not (NE.tex and NE.tex.SetAtlas) then return end

  local existing = tab.GetHighlightTexture and tab:GetHighlightTexture()
  if existing then
    existing:SetTexture(nil)   -- DOWNPORT: SetTexture("") is fine too; nil clears on 3.3.5a
    existing:Hide()
  end

  local left   = _G[tab:GetName() .. "Left"]
  local right  = _G[tab:GetName() .. "Right"]
  local middle = _G[tab:GetName() .. "Middle"]
  if not (left and right and middle) then return end

  local hlLeft = tab:CreateTexture(nil, "HIGHLIGHT")
  NE.tex.SetAtlas(hlLeft, "uiframe-tab-left", false)
  hlLeft:SetSize(35, 36)
  hlLeft:SetPoint("TOPLEFT", left, "TOPLEFT", 0, 0)
  hlLeft:SetBlendMode("ADD")
  hlLeft:SetAlpha(0.4)

  local hlRight = tab:CreateTexture(nil, "HIGHLIGHT")
  NE.tex.SetAtlas(hlRight, "uiframe-tab-right", false)
  hlRight:SetSize(37, 36)
  hlRight:SetPoint("TOPRIGHT", right, "TOPRIGHT", 0, 0)
  hlRight:SetBlendMode("ADD")
  hlRight:SetAlpha(0.4)

  local hlMiddle = tab:CreateTexture(nil, "HIGHLIGHT")
  NE.tex.SetAtlas(hlMiddle, "_uiframe-tab-center", false)
  hlMiddle:SetHorizTile(true)
  hlMiddle:SetHeight(36)
  hlMiddle:SetPoint("TOPLEFT",  hlLeft,  "TOPRIGHT", 0, 0)
  hlMiddle:SetPoint("TOPRIGHT", hlRight, "TOPLEFT",  0, 0)
  hlMiddle:SetBlendMode("ADD")
  hlMiddle:SetAlpha(0.4)

  tab._neCustomHL = { left = hlLeft, middle = hlMiddle, right = hlRight }
end

-- Reskin a single tab in-place. Returns true on success.
function NE.tabs.ReskinClassicTab(tabName, opts)
  opts = opts or {}
  local tab = _G[tabName]
  if not tab or tab._neTabReskinned then return false end

  for suffix, atlas in pairs(ATLAS_BY_SUFFIX) do
    local tex = _G[tabName .. suffix]
    if tex and NE.tex and NE.tex.SetAtlas then
      NE.tex.SetAtlas(tex, atlas, false)
      local sz = SIZE_BY_SUFFIX[suffix]
      if sz then
        if sz.w then tex:SetWidth(sz.w)  end
        if sz.h then tex:SetHeight(sz.h) end
      end
    end
  end

  local left           = _G[tabName .. "Left"]
  local right          = _G[tabName .. "Right"]
  local middle         = _G[tabName .. "Middle"]
  local leftDisabled   = _G[tabName .. "LeftDisabled"]
  local rightDisabled  = _G[tabName .. "RightDisabled"]
  local middleDisabled = _G[tabName .. "MiddleDisabled"]

  if left          then left:ClearAllPoints();          left:SetPoint("TOPLEFT",  tab, "TOPLEFT",  -3, 0) end
  if right         then right:ClearAllPoints();         right:SetPoint("TOPRIGHT", tab, "TOPRIGHT",  7, 0) end
  if leftDisabled  then leftDisabled:ClearAllPoints();  leftDisabled:SetPoint("TOPLEFT",  tab, "TOPLEFT",  -1, 0) end
  if rightDisabled then rightDisabled:ClearAllPoints(); rightDisabled:SetPoint("TOPRIGHT", tab, "TOPRIGHT",  8, 0) end

  if middle and left and right then
    middle:ClearAllPoints()
    middle:SetPoint("TOPLEFT",  left,  "TOPRIGHT", 0, 0)
    middle:SetPoint("TOPRIGHT", right, "TOPLEFT",  0, 0)
    middle:SetHorizTile(true)
  end
  if middleDisabled and leftDisabled and rightDisabled then
    middleDisabled:ClearAllPoints()
    middleDisabled:SetPoint("TOPLEFT",  leftDisabled,  "TOPRIGHT", 0, 0)
    middleDisabled:SetPoint("TOPRIGHT", rightDisabled, "TOPLEFT",  0, 0)
    middleDisabled:SetHorizTile(true)
  end

  buildCustomHighlight(tab)

  if not opts.skipTextY then
    tab.selectedTextY   = opts.selectedTextY   or -3
    tab.deselectedTextY = opts.deselectedTextY or  2
  end

  tab._neTabReskinned = true
  return true
end

-- Convert a reskinned tab into a TOP tab (points UP). Call AFTER ReskinClassicTab.
local TOP_TAB_PCT = 0.85
local function flipPiece(tex, atlas)
  -- DOWNPORT: read from NE.tex._atlasEntry (our registry) not NE_ATLAS.
  local entry = atlas and NE.tex._atlasEntry and NE.tex._atlasEntry(atlas)
  if not (tex and entry) then return end
  local cropBottom = entry.top + (entry.bottom - entry.top) * (1 - TOP_TAB_PCT)
  tex:SetTexCoord(entry.left, entry.right, entry.bottom, cropBottom)
  tex:SetHeight(tex:GetHeight() * TOP_TAB_PCT)
end

function NE.tabs.MakeTopTab(tabName)
  local tab = _G[tabName]
  if not tab or tab._neTopTab then return end
  tab._neTopTab = true

  for suffix, atlas in pairs(ATLAS_BY_SUFFIX) do flipPiece(_G[tabName .. suffix], atlas) end
  local hl = tab._neCustomHL
  if hl then flipPiece(hl.left, "uiframe-tab-left"); flipPiece(hl.middle, "_uiframe-tab-center"); flipPiece(hl.right, "uiframe-tab-right") end

  local function anchor(name, point, x)
    local t = _G[tabName .. name]
    if t then t:ClearAllPoints(); t:SetPoint(point, tab, point, x, 0) end
  end
  anchor("Left", "BOTTOMLEFT", -3); anchor("Right", "BOTTOMRIGHT", 7)
  anchor("LeftDisabled", "BOTTOMLEFT", -1); anchor("RightDisabled", "BOTTOMRIGHT", 8)
  local function span(mid, l, r)
    local m, lt, rt = _G[tabName .. mid], _G[tabName .. l], _G[tabName .. r]
    if m and lt and rt then
      m:ClearAllPoints()
      m:SetPoint("BOTTOMLEFT",  lt, "BOTTOMRIGHT", 0, 0)
      m:SetPoint("BOTTOMRIGHT", rt, "BOTTOMLEFT",  0, 0)
      m:SetHorizTile(true)
    end
  end
  span("Middle", "Left", "Right"); span("MiddleDisabled", "LeftDisabled", "RightDisabled")
  tab:SetHeight(math.floor((SIZE_BY_SUFFIX.Left.h or 36) * TOP_TAB_PCT + 0.5))
  local txt = _G[tabName .. "Text"]
  if txt then txt:ClearAllPoints(); txt:SetPoint("CENTER", tab, "CENTER", 0, -3) end
  tab.selectedTextY = -1
  tab.deselectedTextY = -3
  if hl and hl.left and hl.right and hl.middle then
    hl.left:ClearAllPoints();  hl.left:SetPoint("BOTTOMLEFT", _G[tabName .. "Left"], "BOTTOMLEFT", 0, 0)
    hl.right:ClearAllPoints(); hl.right:SetPoint("BOTTOMRIGHT", _G[tabName .. "Right"], "BOTTOMRIGHT", 0, 0)
    hl.middle:ClearAllPoints()
    hl.middle:SetPoint("BOTTOMLEFT", hl.left, "BOTTOMRIGHT", 0, 0)
    hl.middle:SetPoint("BOTTOMRIGHT", hl.right, "BOTTOMLEFT", 0, 0)
    hl.middle:SetHorizTile(true)
  end
end

local function sizeTabToText(tab, minWidth, textPadding)
  if not tab then return end
  local text = _G[tab:GetName() .. "Text"]
  local textW = (text and text:GetWidth()) or 0
  tab:SetWidth(math.max(minWidth or 70, math.floor(textW + (textPadding or 24))))
end

-- Anchor a chain of reskinned tabs along the parent frame's BOTTOMLEFT.
function NE.tabs.SizeAndAnchorTabs(parent, tabNames, opts)
  opts = opts or {}
  local startX = opts.startX or 11
  local startY = opts.startY or 2
  local gap    = opts.gap or 1
  local minW   = opts.minWidth or 70
  local pad    = opts.textPadding or 24
  local pPoint = opts.parentPoint or "BOTTOMLEFT"

  local prev = nil
  for _, name in ipairs(tabNames) do
    local tab = _G[name]
    if tab then
      sizeTabToText(tab, minW, pad)
      tab:ClearAllPoints()
      if prev then
        tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", gap, 0)
      else
        tab:SetPoint("TOPLEFT", parent, pPoint, startX, startY)
      end
      if not tab._neSizeHooked then
        tab._neSizeHooked = true
        tab:HookScript("OnShow", function(self)
          sizeTabToText(self, minW, pad)
        end)
      end
      prev = tab
    end
  end
end

-- SIDE TAB — retail's LargeSideTabButtonTemplate: a 43×55 button hanging off a panel's RIGHT edge.
-- DOWNPORT: SetShown → Show/Hide in SetSelectedState. The questlog side-tab atlases are not in the
-- Sprint-0 sheet set, so the side tab degrades (transparent textures) until §3 ships sheet 5684744.
function NE.tabs.MakeSideTab(parent, opts)
  opts = opts or {}
  local active   = opts.activeAtlas
  local inactive = opts.inactiveAtlas or active
  local iconSize = opts.iconSize or 29

  local b = CreateFrame("Button", nil, parent)
  b:SetSize(43, 55)

  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetPoint("CENTER")
  NE.tex.SetAtlas(bg, "questlog-tab-side", true)

  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("CENTER", b, "CENTER", -2, 0)
  icon:SetSize(iconSize, iconSize)
  NE.tex.SetAtlas(icon, inactive, false)
  b.Icon, b._active, b._inactive, b._iconSize = icon, active, inactive, iconSize

  local sel = b:CreateTexture(nil, "OVERLAY")
  sel:SetPoint("CENTER")
  NE.tex.SetAtlas(sel, "questlog-tab-side-glow-select", true)
  sel:Hide()
  b.Selected = sel

  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetPoint("CENTER")
  NE.tex.SetAtlas(hl, "questlog-tab-side-glow-hover", true)

  if opts.onClick then
    b:RegisterForClicks("LeftButtonUp")
    b:SetScript("OnClick", opts.onClick)
  end
  if opts.tooltip and NE.tooltip and NE.tooltip.Wire then
    NE.tooltip.Wire(b, opts.tooltip, { anchor = "ANCHOR_RIGHT" })
  end

  function b:SetSelectedState(on)
    -- DOWNPORT: SetShown → Show/Hide.
    if on then self.Selected:Show() else self.Selected:Hide() end
    NE.tex.SetAtlas(self.Icon, on and self._active or self._inactive, false)
    self.Icon:SetSize(self._iconSize, self._iconSize)
  end
  return b
end
