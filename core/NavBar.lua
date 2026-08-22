-- DragonUI_NewEra/core/NavBar.lua — NE.navbar: retail's breadcrumb bar, once, for everybody.
--
-- WHY THIS EXISTS. Era ships `NavBarTemplate` in FrameXML byte-identical to retail's, so NewEra's
-- own navbars are three lines of instantiation. 3.3.5a ships nothing, so it has to be rebuilt — and
-- it got rebuilt TWICE here: once for the Adventure Guide and again for the world map. The second
-- copy promptly re-introduced two faults the first had already fixed and documented thirty lines
-- away — the Home crumb sitting on top of the window's portrait, and crumbs invisible underneath
-- their own bar's regions — which is exactly the argument for not having two copies. This file is
-- the Encounter Journal's implementation, which was the better of the two, lifted into core with
-- the model handed in by the caller.
--
-- WHAT THE CALLER OWNS: the TRAIL. `opts.trailFunc` returns an ordered list of
--     { name = <label>, OnClick = <function>, listFunc = <function returning an EasyMenu list> }
-- with entry 1 as Home. Everything else — art, measurement, collapse, frame levels, interlocking —
-- is in here.
--
-- THREE THINGS THAT LOOK LIKE STYLE AND ARE NOT:
--
--   1. FRAME LEVELS DESCEND left to right. Each crumb's ">" endcap has to draw OVER the crumb that
--      follows it, or the chain shows a black seam at every joint. Retail does the same thing with
--      `SetFrameLevel(lastButton + 1)` on the left neighbour.
--   2. CRUMBS SIT ABOVE THE BAR'S OWN REGIONS. A child frame does not reliably outrank its parent
--      on this client, and the bar has a full-width sheen. Get this wrong and the bar draws as a
--      solid coloured band with every crumb present, shown, sized, textured — and invisible.
--   3. CRUMBS CHAIN FLUSH (`LEFT` to the previous crumb's `RIGHT`). The overhanging piece — Home's
--      built-in notch, or a regular crumb's 21px connector — lands on the NEXT crumb's left
--      padding, which is why that padding is bigger than Home's. Spacing them apart instead leaves
--      a gap the connector is drawn into thin air across.
--
-- ART. Three real retail sheets, already shipped for the Adventure Guide. The colour rule is faithful
-- to how the art is actually built (verified by decoding both sheets): ONLY the Home chevron piece
-- carries the pointed ">" notch, so only Home uses it, cropped to its label. The selection and hover
-- glows are FLAT bars with no notch, deliberately made to stretch — so a long label is fully covered
-- and never runs off the end of its own background.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.navbar = NE.navbar or {}
local NB = NE.navbar

if not (NE.tex and NE.tex.RegisterLocal) then return end

-- ---------------------------------------------------------------------------------------
-- Art
-- ---------------------------------------------------------------------------------------

local EJ_ART     = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\EncounterJournal\\"
local COMMON_ART = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Common\\"

local NAVBAR_FDID = 516763   -- CS_HelpTextures, 512x128 — chevron, glows, endcaps, overflow
local TILE_FDID   = 516764   -- CS_HelpTextures_Tile, 128x512 — the stretchable bars
local SQBTN_FDID  = 423808   -- SquareButtonTextures — retail's real dropdown-arrow glyph

-- The two CS_HelpTextures sheets live under Textures/EncounterJournal/ because that is the module
-- that first shipped them. They are shared retail art, not journal art; the path is history, not
-- ownership.
NE.tex.RegisterLocal(NAVBAR_FDID, EJ_ART     .. "516763-cs-helptextures.blp")
NE.tex.RegisterLocal(TILE_FDID,   EJ_ART     .. "516764-cs-helptextures-tile.blp")
NE.tex.RegisterLocal(SQBTN_FDID,  COMMON_ART .. "423808-squarebuttontextures.blp")

NE.tex.RegisterAtlases({
  ["navbar-button-tile"]     = { file = TILE_FDID, left = 0, right = 1, top = 0.06250000, bottom = 0.12109375, height = 30 },
  ["navbar-barbg-tile"]      = { file = TILE_FDID, left = 0, right = 1, top = 0.18750000, bottom = 0.25390625, height = 34 },
  ["navbar-baroverlay-tile"] = { file = TILE_FDID, left = 0, right = 1, top = 0.25781250, bottom = 0.32421875, height = 34 },
  -- The real grey connector: retail's `NavMenu-Arrow-up`/`-down`. NOT the dropdown ▾ (that is
  -- SquareButtonTextures below). In NavButtonTemplate these are anchored LEFT-to-RIGHT off each
  -- crumb, i.e. a 21x30 chevron sitting just outside its right edge, bridging into the next one.
  ["navbar-endcap-up"]       = { file = NAVBAR_FDID, left = 0.88867188, right = 0.92968750, top = 0.29687500, bottom = 0.53125000, width = 21, height = 30 },
  ["navbar-endcap-down"]     = { file = NAVBAR_FDID, left = 0.63281250, right = 0.67382813, top = 0.75781250, bottom = 0.99218750, width = 21, height = 30 },
  ["navbar-overflow-up"]     = { file = NAVBAR_FDID, left = 0.54296875, right = 0.62890625, top = 0.75781250, bottom = 0.99218750, width = 44, height = 30 },
  ["navbar-overflow-down"]   = { file = NAVBAR_FDID, left = 0.45312500, right = 0.53906250, top = 0.75781250, bottom = 0.99218750, width = 44, height = 30 },
  -- The ▾ glyph. The top/bottom values ARE swapped, and that is retail's own doing: the sheet
  -- stores an UPWARD triangle and the XML flips it vertically by reversing the two edges rather
  -- than shipping a second glyph. Copied verbatim; do not "fix" the ordering.
  ["navbar-dropdown-arrow"]  = { file = SQBTN_FDID, left = 0.45312500, right = 0.64062500, top = 0.20312500, bottom = 0.01562500, width = 12, height = 12 },
})

-- Spans cropped at runtime rather than registered as fixed atlases: Home's chevron is cropped to
-- its label's width (right edge fixed, crop eats into the left) and the glows stretch to any width.
local BANNER_W      = 128
local BANNER_RIGHT  = 0.70312500
local BANNER_UP_Y   = { 0.00781250, 0.24218750 }
local GLOW_LEFT     = 0.00195313
local GLOW_RIGHT    = 0.25195313
local GLOW_SELECT_Y = { 0.37500000, 0.64062500 }   -- red: this crumb is the current one
local GLOW_HOVER_Y  = { 0.65625000, 0.92187500 }   -- blue: transient mouseover
local ENDCAP_W, ENDCAP_H = 21, 30

local function sheet() return NE.tex.Local(NAVBAR_FDID) end

-- Stretch a horizontally-tiling atlas piece to an arbitrary width.
local function applyTiled(tex, atlasName, width, height)
  local entry = NE.tex._atlasEntry and NE.tex._atlasEntry(atlasName)
  local src = entry and NE.tex.localFiles[entry.file]
  if not (tex and entry and src) then if tex then tex:Hide() end; return end
  tex:SetTexture(src)
  tex:SetTexCoord(entry.left, entry.right, entry.top, entry.bottom)
  tex:SetHorizTile(true)
  tex:SetSize(math.max(width or 0, 1), height or entry.height or 30)
  tex:Show()
end
NB.ApplyTiled = applyTiled

-- Crop Home's chevron to `width`, keeping the notched RIGHT edge fixed — retail's own Home math.
local function cropChevron(tex, width)
  local src = sheet()
  if not (tex and src) then if tex then tex:Hide() end; return end
  width = math.min(width or 0, BANNER_W)
  if width <= 0 then tex:Hide(); return end
  tex:SetTexture(src)
  tex:SetHorizTile(false)   -- clear any stale tile flag from a previous applyTiled on this texture
  local offset = (width / BANNER_W) * 0.25
  tex:SetTexCoord(BANNER_RIGHT - offset, BANNER_RIGHT, BANNER_UP_Y[1], BANNER_UP_Y[2])
  tex:SetWidth(width)
  tex:Show()
end

-- Stretch a flat glow bar across the crumb. No crop cap — the glow art has no notch and is built
-- to scale, which is what keeps a long label fully covered.
local function applyGlow(tex, span)
  local src = sheet()
  if not (tex and src and span) then if tex then tex:Hide() end; return end
  tex:SetTexture(src)
  tex:SetHorizTile(false)
  tex:SetTexCoord(GLOW_LEFT, GLOW_RIGHT, span[1], span[2])
  tex:Show()
end

-- The grey connector. Ships grey — no desaturating or tinting — and the vertex colour is re-asserted
-- because these textures are pooled and a previous life may have left one on.
local function applyEndcap(tex)
  if not tex then return end
  if NE.tex.SetAtlas(tex, "navbar-endcap-up", false) then
    tex:SetSize(ENDCAP_W, ENDCAP_H)
    tex:SetHorizTile(false)
    if tex.SetDesaturated then tex:SetDesaturated(false) end
    tex:SetVertexColor(1, 1, 1)
    tex:Show()
  else
    tex:Hide()
  end
end

-- ---------------------------------------------------------------------------------------
-- Measurement
-- ---------------------------------------------------------------------------------------

local TEXT_LPAD_HOME = 12
local TEXT_LPAD_SUB  = 26   -- must clear the previous crumb's 21px connector overlapping this left
local HOME_PAD       = 25
local PLAIN_PAD      = 34
local ARROW_PAD      = 56   -- room for the ▾ inside the crumb
local WIDTH_BUFFER   = 20   -- retail's NAVBAR_WIDTHBUFFER
local OVERFLOW_W     = 44
local CRUMB_H        = 24

-- Padding is TWO independent decisions, not one three-way choice, and collapsing them into one is a
-- bug that only shows up on a crumb that is both. The Adventure Guide's Home never carries a
-- dropdown, so `isHome and HOME_PAD or (hasArrow and ARROW_PAD or PLAIN_PAD)` was correct there for
-- as long as it was the only caller. The world map's Home DOES carry one — its menu is the list of
-- continents — and the `isHome` branch won, so the crumb was sized with no room for the ▾ and the
-- glyph landed on top of the word "World".
local ARROW_EXTRA = ARROW_PAD - PLAIN_PAD   -- what a ▾ costs, whatever the base pad is

local function crumbWidth(isHome, hasArrow, textW)
  local pad = isHome and HOME_PAD or PLAIN_PAD
  if hasArrow then pad = pad + ARROW_EXTRA end
  return textW + pad
end

-- How much room the trail has. A bar pinned left and right into a parent has no explicit width, and
-- this client does not resolve an anchored rect until its next layout pass — so the first refresh,
-- which runs during the build, can legitimately measure 0. Returning there is how the world map's
-- breadcrumb shipped empty: a bar with a plate and nothing on it. `opts.fallbackWidth` lets the
-- caller name a frame that IS sized by then.
-- How much room the trail has.
--
-- `opts.widthFunc` WINS over measuring the frame, and that order matters. A bar pinned left and
-- right into a parent has no width of its own, and this client does not resolve an anchored rect
-- until its next layout pass -- so on the pass right after the window is resized, `bar:GetWidth()`
-- still reports the width it had BEFORE. Trusting it meant the backing plate kept the old window's
-- size: after minimising, a black band running out past the window's right edge; after maximising,
-- one stopping short of it. A caller that knows the width from its own model has no such lag, and
-- the world map does (WM.CurrentCanvasWidth is the single number its whole geometry is built on).
--
-- Measuring the frame stays as the fallback, for a caller with a fixed width and nothing to declare
-- -- which is the Adventure Guide, whose bar is SetWidth'd outright.
local function availableWidth(bar)
  local wf = bar._neOpts and bar._neOpts.widthFunc
  if wf then
    local ok, v = pcall(wf)
    if ok and type(v) == "number" and v > 0 then return v - WIDTH_BUFFER end
  end
  local w = bar:GetWidth() or 0
  if w > 0 then return w - WIDTH_BUFFER end
  return 0
end

-- ---------------------------------------------------------------------------------------
-- Widgets
-- ---------------------------------------------------------------------------------------

local menuHost
local function openMenu(anchor, list)
  if not (list and #list > 0 and _G.EasyMenu) then return end
  if not menuHost then
    menuHost = CreateFrame("Frame", "NE_NavBarMenu", UIParent, "UIDropDownMenuTemplate")
  end
  _G.EasyMenu(list, menuHost, anchor, 0, 0, "MENU")
end
NB.OpenMenu = openMenu

-- The ▾ button. Retail's Normal/Pushed art is a deliberately invisible ghost square, which this
-- client renders as a solid BLACK box instead of leaving transparent — so it is dropped entirely
-- and the stock mouse highlight carries the hover feedback on its own.
local function buildArrow(parent)
  local a = CreateFrame("Button", nil, parent)
  a:SetSize(27, 31)
  a:SetFrameLevel((parent:GetFrameLevel() or 1) + 1)
  local hl = a:CreateTexture(nil, "HIGHLIGHT")
  hl:SetSize(32, 32)
  hl:SetPoint("CENTER")
  hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
  hl:SetBlendMode("ADD")
  a.art = a:CreateTexture(nil, "OVERLAY")
  a.art:SetSize(12, 12)
  a.art:SetPoint("CENTER", a, "CENTER", 0, -1)
  NE.tex.SetAtlas(a.art, "navbar-dropdown-arrow", true)
  a:SetScript("OnMouseDown", function(self) self.art:SetPoint("CENTER", -1, -2) end)
  a:SetScript("OnMouseUp",   function(self) self.art:SetPoint("CENTER",  0, -1) end)
  a:SetScript("OnClick", function(self)
    if self._listFunc then openMenu(self, self._listFunc()) end
  end)
  return a
end

local function acquireCrumb(bar, i)
  local c = bar.crumbs[i]
  if c then return c end

  c = CreateFrame("Button", nil, bar)
  c:SetHeight(CRUMB_H)
  c._isHome = (i == 1)

  c.bg = c:CreateTexture(nil, "BACKGROUND")
  c.bg:SetHeight(30)

  -- The red "you are here" glow and the blue hover glow above it. Both fill the crumb body; the
  -- connector lives outside its right edge, so the red tapers off as the body ends rather than
  -- stopping on a hard line or bleeding around the point.
  c.selectedGlow = c:CreateTexture(nil, "ARTWORK", nil, 0)
  c.selectedGlow:SetPoint("TOPLEFT",     c, "TOPLEFT",    -2,  4)
  c.selectedGlow:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -4)
  c.selectedGlow:Hide()

  c.glow = c:CreateTexture(nil, "ARTWORK", nil, 1)
  c.glow:SetPoint("TOPLEFT",     c, "TOPLEFT",    -2,  4)
  c.glow:SetPoint("BOTTOMRIGHT", c, "BOTTOMRIGHT", 0, -4)
  c.glow:SetBlendMode("ADD")
  c.glow:Hide()

  -- Sublevel 2 keeps the connector above both glows.
  c.endcap = c:CreateTexture(nil, "ARTWORK", nil, 2)
  c.endcap:SetSize(ENDCAP_W, ENDCAP_H)
  c.endcap:SetPoint("LEFT", c, "RIGHT", 0, 0)
  c.endcap:Hide()

  c.text = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")

  c:SetScript("OnEnter", function(self)
    self.text:SetTextColor(1, 1, 0.6)
    applyGlow(self.glow, GLOW_HOVER_Y)
  end)
  c:SetScript("OnLeave", function(self)
    if self._isLast then self.text:SetTextColor(1, 1, 1) else self.text:SetTextColor(1, 0.82, 0) end
    self.glow:Hide()
  end)

  c.arrow = buildArrow(bar)

  bar.crumbs[i] = c
  return c
end

-- The "…" badge standing in for however many oldest crumbs did not fit. Its click lists just those,
-- oldest first — retail's NavBar_ListOverFlowButtons — and picking one jumps there exactly as
-- clicking the real crumb would have.
local function acquireOverflow(bar)
  if bar.overflow then return bar.overflow end
  local c = CreateFrame("Button", nil, bar)
  c:SetSize(OVERFLOW_W, 30)
  c.idle = c:CreateTexture(nil, "ARTWORK")
  c.idle:SetAllPoints(c)
  NE.tex.SetAtlas(c.idle, "navbar-overflow-up", true)
  c.press = c:CreateTexture(nil, "ARTWORK")
  c.press:SetAllPoints(c)
  NE.tex.SetAtlas(c.press, "navbar-overflow-down", true)
  c.press:Hide()
  c:SetScript("OnMouseDown", function(self) self.idle:Hide(); self.press:Show() end)
  c:SetScript("OnMouseUp",   function(self) self.press:Hide(); self.idle:Show() end)
  c:SetScript("OnClick", function(self)
    local list = {}
    for _, e in ipairs(self._hidden or {}) do
      list[#list + 1] = { text = e.name, notCheckable = true,
                          func = function() if e.OnClick then e.OnClick() end end }
    end
    openMenu(self, list)
  end)
  bar.overflow = c
  return c
end

-- ---------------------------------------------------------------------------------------
-- Layout
-- ---------------------------------------------------------------------------------------

local function refresh(bar)
  if not (bar and bar:IsShown()) then return end
  local opts = bar._neOpts or {}
  local entries = {}
  if opts.trailFunc then
    local ok, list = pcall(opts.trailFunc)
    if ok and type(list) == "table" then entries = list end
  end
  if #entries == 0 then
    for i = 1, #bar.crumbs do
      bar.crumbs[i]:Hide(); bar.crumbs[i].arrow:Hide(); bar.crumbs[i].endcap:Hide()
    end
    if bar.overflow then bar.overflow:Hide() end
    bar._trailDepth = 0
    return
  end

  local maxWidth = availableWidth(bar)
  if maxWidth <= 0 then
    -- Nothing to measure against yet. Come back on the next frame, once — a permanently
    -- zero-width bar retries and then stops rather than spinning.
    if not bar._retried and C_Timer and C_Timer.After then
      bar._retried = true
      C_Timer.After(0, function() refresh(bar) end)
    end
    return
  end
  bar._retried = nil

  -- Measure every crumb's own footprint. The text is set here so GetStringWidth sees the real label.
  local widths = {}
  for i, e in ipairs(entries) do
    local c = acquireCrumb(bar, i)
    c.text:SetWidth(0)
    c.text:SetText(e.name or "?")
    widths[i] = crumbWidth(i == 1, e.listFunc ~= nil, c.text:GetStringWidth() or 0)
  end

  -- COLLAPSE. Home never folds, and neither does the crumb you are actually on; only the MIDDLE
  -- ones do, into a badge that sits right after Home. Budget from the deepest crumb backwards —
  -- whatever no longer fits stays collapsed.
  local total = 0
  for i = 1, #entries do total = total + widths[i] end
  local needOverflow = (total > maxWidth) and (#entries > 2)
  local budget = maxWidth - widths[1] - (needOverflow and OVERFLOW_W or 0)
  local firstMid, run = #entries, 0
  for i = #entries, 2, -1 do
    run = run + widths[i]
    if run > budget then break end
    firstMid = i
  end
  needOverflow = firstMid > 2   -- refine: only if a middle crumb actually got hidden

  -- Clamp to 2 so a lone Home is not re-rendered onto itself — that self-anchor blanked the bar on
  -- first load and detached it after going back Home.
  local trailStart = math.max(firstMid, 2)
  local trailCount = (#entries >= trailStart) and (#entries - trailStart + 1) or 0

  -- DESCENDING levels, leftmost highest, so each crumb's endcap draws over the next one and the
  -- chain interlocks with no seam. `+ 2` clears the bar's own regions — see the header.
  local nVisible  = 1 + (needOverflow and 1 or 0) + trailCount
  local baseLevel = (bar:GetFrameLevel() or 1) + 2
  local visualPos = 0
  local function nextLevel()
    local lvl = baseLevel + (nVisible - visualPos)
    visualPos = visualPos + 1
    return lvl
  end

  local function renderCrumb(i, prevWidget)
    local e = entries[i]
    local c = bar.crumbs[i]
    c._isLast = (i == #entries)
    c:SetFrameLevel(nextLevel())
    c.text:ClearAllPoints()
    c.text:SetPoint("LEFT", c, "LEFT", c._isHome and TEXT_LPAD_HOME or TEXT_LPAD_SUB, 0)
    if c._isLast then c.text:SetTextColor(1, 1, 1) else c.text:SetTextColor(1, 0.82, 0) end
    c:SetScript("OnClick", function()
      if PlaySound and SOUNDKIT then pcall(PlaySound, SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON) end
      if e.OnClick then e.OnClick() end
    end)
    c:ClearAllPoints()
    if prevWidget then
      c:SetPoint("LEFT", prevWidget, "RIGHT", 0, 0)
    else
      c:SetPoint("LEFT", bar, "LEFT", 0, 0)
    end
    local w = widths[i]
    c:SetWidth(w)
    c.bg:ClearAllPoints()
    if c._isHome then
      -- Home carries the whole pointed chevron, body plus its built-in notch, and OVERHANGS its
      -- right edge by ENDCAP_W so the notch lands exactly where every other crumb's connector
      -- sits. Sizing it to the bare crumb width lets the notch eat into the label instead.
      c.bg:SetPoint("RIGHT", c, "RIGHT", ENDCAP_W, 0)
      cropChevron(c.bg, w + ENDCAP_W)
      c.endcap:Hide()
    else
      c.bg:SetPoint("CENTER", c, "CENTER", 0, 0)
      applyTiled(c.bg, "navbar-button-tile", w, 30)
      applyEndcap(c.endcap)
    end
    -- Home already reads as active via its red chevron, so it needs no selection glow.
    if c._isLast and not c._isHome then
      applyGlow(c.selectedGlow, GLOW_SELECT_Y)
    else
      c.selectedGlow:Hide()
    end
    if e.listFunc then
      c.arrow._listFunc = e.listFunc
      c.arrow:ClearAllPoints()
      c.arrow:SetPoint("RIGHT", c, "RIGHT", -6, 1)   -- inside the crumb, left of the endcap point
      c.arrow:SetFrameLevel(c:GetFrameLevel() + 1)
      c.arrow:Show()
    else
      c.arrow._listFunc = nil
      c.arrow:Hide()
    end
    c.glow:Hide()
    c:Show()
    return c
  end

  local prev = renderCrumb(1, nil)

  if needOverflow then
    local ov = acquireOverflow(bar)
    ov._hidden = {}
    for k = 2, firstMid - 1 do ov._hidden[#ov._hidden + 1] = entries[k] end
    ov:SetFrameLevel(nextLevel())
    ov:ClearAllPoints()
    ov:SetPoint("LEFT", prev, "RIGHT", 0, 0)
    ov:Show()
    prev = ov
  elseif bar.overflow then
    bar.overflow:Hide()
  end

  for i = trailStart, #entries do
    prev = renderCrumb(i, prev)
  end

  -- Retire the collapsed middles and anything pooled from a previously deeper trail.
  for i = 1, #bar.crumbs do
    if (i > 1 and i < trailStart) or i > #entries then
      local c = bar.crumbs[i]
      c:Hide(); c.arrow:Hide(); c.endcap:Hide()
    end
  end

  bar._trailDepth = #entries
end

-- ---------------------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------------------

-- opts:
--   name           global frame name
--   trailFunc      () -> { { name, OnClick, listFunc }, ... }, entry 1 = Home
--   frameLevel     absolute level for the bar (its crumbs go above it)
--   plate          draw the tiled backing plate + sheen (default true)
--   inset          draw the recessed nineslice border around the bar (default true)
--   widthFunc      () -> number, the bar's width from the caller's own model. Preferred over
--                  measuring the frame, which lags a resize by a layout pass (see availableWidth).
--
-- The caller anchors and sizes the frame itself — a fixed width (the Adventure Guide) and a
-- left-and-right pin (the world map) are both fine.
function NB.Create(parent, opts)
  if not parent then return nil end
  opts = opts or {}

  local bar = CreateFrame("Frame", opts.name, parent)
  bar:SetHeight(opts.height or 34)
  if opts.frameLevel then bar:SetFrameLevel(opts.frameLevel) end
  bar.crumbs = {}
  bar._neOpts = opts

  if opts.plate ~= false then
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
    -- BORDER, not OVERLAY: the sheen only has to sit above the plate, and leaving it on the bar's
    -- topmost layer is a second way for the crumbs to end up underneath it.
    bar.sheen = bar:CreateTexture(nil, "BORDER")
    bar.sheen:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  end

  -- The recessed border, raised ABOVE the crumbs so the bar reads as one strip with the trail
  -- inside it rather than crumbs spilling over its edge. AttachInset builds it mouse-transparent.
  if opts.inset ~= false and NE.nineslice and NE.nineslice.AttachInset then
    bar.NineSlice = NE.nineslice.AttachInset(bar, 0, 0, 0, 0)
    if bar.NineSlice then bar.NineSlice:SetFrameLevel((bar:GetFrameLevel() or 1) + 40) end
  end

  function bar:Refresh() refresh(self) end

  -- Re-tile the plate to whatever width the bar ended up, then lay the trail out on it.
  function bar:Relayout()
    local w = availableWidth(self)
    if w > 0 and self.bg then
      applyTiled(self.bg,    "navbar-barbg-tile",      w + WIDTH_BUFFER, opts.height or 34)
      applyTiled(self.sheen, "navbar-baroverlay-tile", w + WIDTH_BUFFER, opts.height or 34)
    end
    refresh(self)
  end

  bar:SetScript("OnShow", function(self) refresh(self) end)
  return bar
end

-- Exposed for callers that want the same numbers (the Adventure Guide sizes its bar around its
-- search box) and for the offline harness.
NB.WIDTH_BUFFER = WIDTH_BUFFER
NB.OVERFLOW_W   = OVERFLOW_W
NB.ENDCAP_W     = ENDCAP_W
NB.CrumbWidth   = crumbWidth
