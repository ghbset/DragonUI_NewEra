-- DragonUI_NewEra/modules/talents/Glyphs.lua — glyph tab renderer for 3.3.5a.
--
-- This file owns the reusable glyph view that lives inside NE_TalentFrame. The talents tab
-- strip toggles the view on/off; Behavior.lua keeps it refreshed from live glyph/spec events.

local NE = DragonUI_NewEra
local L = NE.L
local T  = NE.talents or {}
NE.talents = T

local SOCKET_COUNT = 6
local GLYPH_DOT_SIZE = 4
local GLYPH_DOT_GAP = 9
local GLYPH_FLOW_SPEED = 16
local GLYPH_NAME_PREFIX = "Glyph of "
-- Socket ring: the gold circle from the talents sheet (talents-node-circle-yellow), isolated from a
-- 2x upscale for a crisper edge and shipped as a 128 TGA. White tint on the active spec (true gold),
-- dimmed when locked/inactive/off-spec.
local GLYPH_RING_TEXTURE = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\glyph-ring-gold.tga"
-- Greyscale copy of the ring for LEVEL-LOCKED sockets (desaturated). A separate texture, not
-- SetDesaturated(), because on 3.3.5a SetDesaturated OVERRIDES the vertex tint we use to dim it.
local GLYPH_RING_DESAT_TEXTURE = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\glyph-ring-desat.tga"
-- The visible ring fills only this fraction of its (transparent-margined) texture box; the marching
-- ants use it so their endpoints land on the ring edge instead of out in the empty margin.
local RING_ART_FRAC = 0.66

-- Diablo-style animated globes behind each socket (HoradricSpheres idle sprite, downsized to 512):
-- health (red) on MAJOR sockets, mana (blue) on MINOR. Full-colour + animated for a live glyph,
-- desaturated when the socket is unused. One shared 30fps ticker cycles the 67-frame flipbook across
-- every socket globe (texcoords are normalised to the original 4096 sheet, so they hold at any size).
local GLOBE_HEALTH = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\glyph-globe-health.tga"
local GLOBE_MANA   = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\glyph-globe-mana.tga"
local GLOBE_FRAMES, GLOBE_COLS, GLOBE_FW, GLOBE_STRIDE, GLOBE_SHEET = 67, 11, 350, 352, 4096
local function globeCoord(i)
  local col = (i - 1) % GLOBE_COLS
  local row = math.floor((i - 1) / GLOBE_COLS)
  local x, y = col * GLOBE_STRIDE, 1 + row * GLOBE_STRIDE
  return x / GLOBE_SHEET, (x + GLOBE_FW) / GLOBE_SHEET, y / GLOBE_SHEET, (y + GLOBE_FW) / GLOBE_SHEET
end
local glyphGlobes = {}
local globeFrameIndex = 1
local globeTicker
local function ensureGlobeTicker()
  if globeTicker or not (C_Timer and C_Timer.NewTicker) then return end
  globeTicker = C_Timer.NewTicker(1 / 30, function()
    if not (T.GlyphsIsActive and T.GlyphsIsActive()) then return end   -- only animate while visible
    globeFrameIndex = globeFrameIndex % GLOBE_FRAMES + 1
    local l, r, t, b = globeCoord(globeFrameIndex)
    for i = 1, #glyphGlobes do
      local g = glyphGlobes[i]
      if g:IsShown() then g:SetTexCoord(l, r, t, b) end
    end
  end)
end
-- Glass gloss/shine overlaid on TOP of everything (over the rune) so the socket reads as a glass orb.
local GLYPH_GLOSS_TEXTURE = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\glyph-orbgloss.tga"
-- Soft round drop-shadow behind the globe (lifted from the reference sheet). Baked dark.
local GLYPH_SHADOW_TEXTURE = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\glyph-shadow.tga"
-- Multipliers on the socket's base size. The animated sphere and the gloss over it are grown so the
-- orb reads big; the gold ring is pushed out to sit at the sphere's rim; the shadow haloes just beyond.
local GLOBE_SCALE = 1.00  -- animated sphere (and the gloss over it) — fills the orb
local RING_SCALE  = 1.8  -- gold ring — sits at the sphere's outer rim
-- Point a socket's globe at health/mana; full colour + lit when `lit`.
local function configGlobe(button, isMajor, lit, size)
  local g = button and button.Globe
  if not g then return end
  g:SetTexture(isMajor and GLOBE_HEALTH or GLOBE_MANA)
  local d = size * GLOBE_SCALE
  g:SetSize(d, d)
  if g.SetDesaturated then g:SetDesaturated(not lit) end
  g:SetAlpha(lit and 1 or 0.45)
  g:Show()
  -- Glass gloss on top (over the rune), sized to the orb, for the glass-sphere look.
  local gs = button.Gloss
  if gs then
    gs:SetTexture(GLYPH_GLOSS_TEXTURE)
    gs:SetSize(d * 1.2, d * 1.2)
    gs:SetAlpha(lit and 0.8 or 0.5)
    gs:Show()
  end
end

local root
local panes = {}
local refreshDriver
local glyphEdgePhase = 0
local glyphOptionsMenu

T._glyphActive = (T._glyphActive ~= nil) and T._glyphActive or false

local function glyphLabelNamesEnabled()
  return (NE.db and NE.db.talentGlyphSlotNames) and true or false
end

local function setGlyphLabelNamesEnabled(enabled)
  if not NE.db then return end
  NE.db.talentGlyphSlotNames = enabled and true or false
end

-- Gearbox option: show the "ACTIVE EFFECTS" description list alongside the glyph sockets, or hide
-- it and let the sockets use the full width (just the glyphs, no effect text). Defaults to shown,
-- matching the original behavior before this option existed.
local function glyphShowEffectsEnabled()
  if not NE.db or NE.db.talentGlyphShowEffects == nil then return true end
  return NE.db.talentGlyphShowEffects and true or false
end
local function setGlyphShowEffectsEnabled(enabled)
  if not NE.db then return end
  NE.db.talentGlyphShowEffects = enabled and true or false
end

local function trimGlyphPrefix(name)
  if type(name) ~= "string" then return nil end
  local trimmed = name:gsub("^Glyph%s+[Oo]f%s+", "")
  if trimmed == "" then
    return name
  end
  if trimmed ~= name then
    return trimmed
  end
  if name:sub(1, #GLYPH_NAME_PREFIX) == GLYPH_NAME_PREFIX then
    return name:sub(#GLYPH_NAME_PREFIX + 1)
  end
  return name
end

local function glyphDisplayName(info, fallbackSpellName)
  if not info then return nil end
  local itemName
  if info.link and GetItemInfo then
    itemName = GetItemInfo(info.link)
  end
  if (not itemName) and type(info.link) == "string" then
    itemName = info.link:match("%[(.-)%]")
  end
  return trimGlyphPrefix(itemName or fallbackSpellName)
end

local function queueGlyphRefresh(passes)
  passes = tonumber(passes) or 1
  if passes < 1 then return end
  if not refreshDriver then
    refreshDriver = CreateFrame("Frame")
    refreshDriver:Hide()
  end
  refreshDriver._remaining = math.max(refreshDriver._remaining or 0, passes)
  refreshDriver:SetScript("OnUpdate", function(self)
    self._remaining = (self._remaining or 1) - 1
    if T.GlyphsRefresh then pcall(T.GlyphsRefresh) end
    if T.GlyphsApplyPaneVisibility then pcall(T.GlyphsApplyPaneVisibility) end
    if self._remaining <= 0 then
      self:SetScript("OnUpdate", nil)
      self:Hide()
    end
  end)
  refreshDriver:Show()
end

do
  local ev = CreateFrame("Frame")
  for _, e in ipairs({ "GLYPH_ADDED", "GLYPH_REMOVED", "GLYPH_UPDATED", "USE_GLYPH", "ACTIVE_TALENT_GROUP_CHANGED" }) do
    pcall(function() ev:RegisterEvent(e) end)
  end
  ev:SetScript("OnEvent", function()
    if T.GlyphsIsActive and T.GlyphsIsActive() then queueGlyphRefresh(2) end
  end)
end

if not StaticPopupDialogs["NE_GLYPH_REMOVE_CONFIRM"] then
  StaticPopupDialogs["NE_GLYPH_REMOVE_CONFIRM"] = {
    text = L["Remove this glyph?"],
    button1 = ACCEPT,
    button2 = CANCEL,
    OnAccept = function(self, data)
      local button = data and data.button
      local info = button and button._glyphInfo
      if not (info and info.socket) then return end
      if type(_G.RemoveGlyphFromSocket) == "function" then
        local ok = pcall(_G.RemoveGlyphFromSocket, info.socket)
        if ok then
          button._hasGlyph = nil
          if button.Icon then button.Icon:SetTexture(nil) end
          if button.IconTint then button.IconTint:Hide() end
          if button.Glow then button.Glow:Hide() end
          local socket, group = info.socket, info.group
          local tries = 0
          local function poll()
            tries = tries + 1
            -- Presence only, read layout-agnostically: 3.3.5a returns
            -- (enabled, glyphType, glyphTooltipIndex, glyphSpellID, icon) while the retail shape
            -- getSocketInfo also handles drops the tooltip index, so the spell ID sits at 4 here
            -- and 3 there. Both slots are nil on an empty socket, so testing the pair is correct
            -- either way.
            local _, _, r3, r4 = GetGlyphSocketInfo(socket, group)
            local cleared = not ((type(r3) == "number" and r3 > 0)
                              or (type(r4) == "number" and r4 > 0))
            if cleared or tries >= 25 then
              if T.GlyphsRefresh then pcall(T.GlyphsRefresh) end
            elseif C_Timer and C_Timer.After then
              C_Timer.After(0.15, poll)
            end
          end
          if C_Timer and C_Timer.After then C_Timer.After(0.15, poll) else queueGlyphRefresh(60) end
        end
      end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = STATICPOPUP_NUMDIALOGS,
  }
end

local function setAtlas(tex, atlas, fallbackTexture)
  if tex and NE.tex and NE.tex.SetAtlas and atlas then
    if NE.tex.SetAtlas(tex, atlas, true) then return true end
  end
  if tex and fallbackTexture and tex.SetTexture then
    tex:SetTexture(fallbackTexture)
  end
  return false
end

local function positionGlyphEdge(edge, phase)
  local dots, span, gap = edge.dots, edge.span, edge.gap
  for i = 1, #dots do
    local dist = ((i - 1) * gap + phase) % span
    local d = dots[i]
    d:ClearAllPoints()
    d:SetPoint("CENTER", edge.parent, "CENTER", edge.x0 + edge.ux * dist, edge.y0 + edge.uy * dist)
  end
end

local function ensureGlyphFlowDriver(host)
  if not (host and host.HookScript) or host._glyphEdgeFlow then return end
  host._glyphEdgeFlow = true
  host:HookScript("OnUpdate", function(self, dt)
    if not T._glyphActive then return end
    dt = dt or 0
    glyphEdgePhase = glyphEdgePhase + dt * GLYPH_FLOW_SPEED
    if glyphEdgePhase > 1e6 then glyphEdgePhase = 0 end
    for _, pane in pairs(panes) do
      if pane and pane:IsShown() and pane._glyphEdges then
        for i = 1, #pane._glyphEdges do
          positionGlyphEdge(pane._glyphEdges[i], glyphEdgePhase)
        end
      end
    end
  end)
end

local function resetPaneEdges(pane)
  if not pane then return end
  pane._edgeN = 0
  pane._glyphEdges = pane._glyphEdges or {}
  for i = 1, #pane._glyphEdges do pane._glyphEdges[i] = nil end
end

local function acquirePaneDot(pane)
  pane._edgeN = (pane._edgeN or 0) + 1
  pane.edgePool = pane.edgePool or {}
  local d = pane.edgePool[pane._edgeN]
  if not d then
    d = pane:CreateTexture(nil, "ARTWORK", nil, -2)
    d:SetTexture("Interface\\Buttons\\WHITE8X8")
    pane.edgePool[pane._edgeN] = d
  end
  d:Show()
  return d
end

local function hideUnusedPaneDots(pane)
  if not (pane and pane.edgePool) then return end
  for i = (pane._edgeN or 0) + 1, #pane.edgePool do
    pane.edgePool[i]:Hide()
  end
end

local function drawPaneEdge(pane, startButton, endButton, color)
  if not (pane and startButton and endButton) then return end
  local sx, sy = startButton:GetCenter()
  local ex, ey = endButton:GetCenter()
  local px, py = pane:GetCenter()
  if not (sx and sy and ex and ey and px and py) then return end
  sx, sy = sx - px, sy - py
  ex, ey = ex - px, ey - py
  local dx, dy = ex - sx, ey - sy
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < 1 then return end
  local ux, uy = dx / dist, dy / dist
  local startRadius = (startButton.Border and startButton.Border:GetWidth() or startButton:GetWidth() or 0) * 0.5 * RING_ART_FRAC
  local endRadius = (endButton.Border and endButton.Border:GetWidth() or endButton:GetWidth() or 0) * 0.5 * RING_ART_FRAC
  local x0, y0 = sx + ux * startRadius, sy + uy * startRadius
  local span = dist - startRadius - endRadius
  if span <= 0 then return end
  local count = math.floor(span / GLYPH_DOT_GAP + 0.5)
  if count < 1 then count = 1 end
  local gap = span / count
  local dots = {}
  for _ = 1, count do
    local d = acquirePaneDot(pane)
    d:SetSize(GLYPH_DOT_SIZE, GLYPH_DOT_SIZE)
    d:SetVertexColor(color[1], color[2], color[3], color[4])
    dots[#dots + 1] = d
  end
  local edge = { parent = pane, x0 = x0, y0 = y0, ux = ux, uy = uy, span = span, gap = gap, dots = dots }
  pane._glyphEdges[#pane._glyphEdges + 1] = edge
  positionGlyphEdge(edge, glyphEdgePhase)
end

local function updatePaneEdges(pane, activePane)
  if not pane then return end
  resetPaneEdges(pane)
  if not T._glyphActive then
    hideUnusedPaneDots(pane)
    return
  end

  local majorColor = activePane and { 1.0, 0.84, 0.18, 0.95 } or { 0.62, 0.49, 0.24, 0.45 }
  local minorColor = activePane and { 1.0, 0.84, 0.18, 0.72 } or { 0.62, 0.49, 0.24, 0.32 }
  local sockets = pane.sockets
  drawPaneEdge(pane, sockets[1], sockets[3], majorColor)
  drawPaneEdge(pane, sockets[3], sockets[5], majorColor)
  drawPaneEdge(pane, sockets[5], sockets[1], majorColor)
  drawPaneEdge(pane, sockets[2], sockets[4], minorColor)
  drawPaneEdge(pane, sockets[4], sockets[6], minorColor)
  drawPaneEdge(pane, sockets[6], sockets[2], minorColor)
  hideUnusedPaneDots(pane)
end

local function applyPaneBackground(pane)
  if not (pane and pane.bg and pane._bgNick) then return end

  local nick = pane._bgNick
  local a = NE.tex and NE.tex.atlases and NE.tex.atlases[nick:lower()]
  if not a then
    if NE.tex and NE.tex.SetAtlas then
      NE.tex.SetAtlas(pane.bg, nick, false)
    end
    pane.bg:SetTexCoord(0, 1, 0, 1)
    return
  end

  if NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(pane.bg, nick, false)
  end

  local paneW = pane:GetWidth() or 0
  local paneH = pane:GetHeight() or 0
  if paneW <= 0 or paneH <= 0 then return end

  local destA, srcA = paneW / paneH, a.width / a.height
  local left, right, top, bottom = a.left, a.right, a.top, a.bottom
  if destA > srcA then
    bottom = top + (bottom - top) * (srcA / destA)
  else
    left = right - (right - left) * (destA / srcA)
  end
  if pane._bgFlip then
    left, right = right, left
  end
  pane.bg:SetTexCoord(left, right, top, bottom)
end

local function specBackgroundNick(group)
  local bestTab, bestSpent = 1, -1
  local tabCount = (GetNumTalentTabs and GetNumTalentTabs(false, false)) or 0
  for tab = 1, tabCount do
    local spent = 0
    local numTalents = (GetNumTalents and GetNumTalents(tab, false, false)) or 0
    if GetTalentInfo then
      for i = 1, numTalents do
        local _, _, _, _, rank, _, _, _, previewRank = GetTalentInfo(tab, i, false, false, group)
        spent = spent + (previewRank or rank or 0)
      end
    else
      local _, _, tabSpent = GetTalentTabInfo and GetTalentTabInfo(tab, false, false, group)
      spent = tabSpent or 0
    end
    if spent > bestSpent then
      bestSpent = spent
      bestTab = tab
    end
  end
  return T.BackgroundNick and T.BackgroundNick(bestTab) or nil
end

local function specTabLabel(group)
  local text = _G["NE_TalentSpecTab" .. tostring(group) .. "Text"]
  if text and text.GetText then
    local label = text:GetText()
    if label and label ~= "" then return label end
  end
  local tab = _G["NE_TalentSpecTab" .. tostring(group)]
  if tab and tab.GetText then
    local label = tab:GetText()
    if label and label ~= "" then return label end
  end
  return (group == 2) and "Secondary" or "Primary"
end

local function groupStatus(group)
  return specTabLabel(group)
end

local function getGlyphLink(socket, group)
  if not GetGlyphLink then return nil end
  local ok, link = pcall(GetGlyphLink, socket, group)
  if ok and link and link ~= "" then return link end
  ok, link = pcall(GetGlyphLink, socket)
  if ok and link and link ~= "" then return link end
  return nil
end

local function getSocketInfo(socket, group)
  if not GetGlyphSocketInfo then return nil end
  local enabled, glyphType, r3, r4, r5 = GetGlyphSocketInfo(socket, group)

  local glyphSpellID, icon
  if (type(r4) == "string" or type(r4) == "number") and r5 == nil then
    glyphSpellID = r3
    icon = r4
  else
    glyphSpellID = r4
    icon = r5
  end

  return {
    socket = socket,
    enabled = enabled and true or false,
    glyphType = glyphType,
    glyphSpellID = glyphSpellID,
    icon = icon,
    link = getGlyphLink(socket, group),
  }
end

local function emptyGlyphIcon(glyphType)
  if glyphType == 2 then
    return "Interface\\Icons\\INV_Glyph_MinorGlyph"
  end
  return "Interface\\Icons\\INV_Glyph_MajorGlyph"
end

local function getStockGlyphSocket(button)
  local info = button and button._glyphInfo
  if not (info and info.socket) then return nil end

  if not ((NE.IsAddOnLoaded and NE.IsAddOnLoaded("Blizzard_GlyphUI")) or _G.GlyphFrame) then
    if type(_G.LoadAddOn) == "function" then
      pcall(_G.LoadAddOn, "Blizzard_GlyphUI")
    end
  end

  return _G["GlyphFrameGlyph" .. tostring(info.socket)]
end

local function copyTooltipToButton(button)
  if not (button and GameTooltip and GameTooltip:IsShown()) then return false end

  local lines = {}
  local numLines = GameTooltip:NumLines() or 0
  for i = 1, numLines do
    local left = _G["GameTooltipTextLeft" .. i]
    if left and left.GetText then
      local text = left:GetText()
      if text and text ~= "" then
        local r, g, b = left:GetTextColor()
        lines[#lines + 1] = { text = text, r = r or 1, g = g or 1, b = b or 1 }
      end
    end
  end
  if #lines == 0 then return false end

  GameTooltip:Hide()
  GameTooltip:SetOwner(button, "ANCHOR_NONE")
  GameTooltip:SetPoint("BOTTOMLEFT", button, "TOPRIGHT", 3, 2)
  GameTooltip:SetText(lines[1].text, lines[1].r, lines[1].g, lines[1].b)
  for i = 2, #lines do
    local line = lines[i]
    GameTooltip:AddLine(line.text, line.r, line.g, line.b, true)
  end
  GameTooltip:Show()
  return true
end

local function tooltipForSocket(button)
  local info = button._glyphInfo
  if not info then return end

  local stock = getStockGlyphSocket(button)
  if stock and stock.GetScript then
    local onEnter = stock:GetScript("OnEnter")
    if type(onEnter) == "function" then
      local ok = pcall(onEnter, stock)
      if ok and GameTooltip and GameTooltip:IsShown() then
        if copyTooltipToButton(button) then return end
      end
    end
  end

  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  local shown = false
  if GameTooltip.SetGlyph and info.socket then
    local ok = pcall(GameTooltip.SetGlyph, GameTooltip, info.socket, button._group or 1)
    shown = ok and true or false
  end
  if (not shown) and info.link and GameTooltip.SetHyperlink then
    local ok = pcall(GameTooltip.SetHyperlink, GameTooltip, info.link)
    shown = ok and true or false
  end
  if not shown then
    GameTooltip:SetText(button._fallbackName or "Glyph Socket", 1, 1, 1)
    if button._fallbackState then
      GameTooltip:AddLine(button._fallbackState, 0.8, 0.8, 0.8, true)
    end
  end
  GameTooltip:Show()
end

local function clickStockGlyphSocket(button, mouseButton)
  local info = button and button._glyphInfo
  if not (info and info.socket and button._activePane) then return end

  -- 1. GESTURE: Shift-Right-Click to remove an equipped glyph
  if mouseButton == "RightButton" and type(_G.IsShiftKeyDown) == "function" and _G.IsShiftKeyDown() then
    if button._hasGlyph and type(_G.StaticPopup_Show) == "function" then
      _G.StaticPopup_Show("NE_GLYPH_REMOVE_CONFIRM", nil, nil, { button = button })
    end
    return
  end

  -- 2. GESTURE: Left-Click with a glyph on the cursor to apply it directly
  if mouseButton == "LeftButton" and CursorHasGlyph and CursorHasGlyph() then
    if PlaceGlyphInSocket then
      -- Bypasses the secure frame click layer entirely
      pcall(PlaceGlyphInSocket, info.socket)
    end
    return
  end

  -- 3. FALLBACK: Normal click interactions route safely through a pcall guard
  local stock = getStockGlyphSocket(button)
  if not stock then return end

  if stock.Click then
    pcall(stock.Click, stock, mouseButton or "LeftButton")
    return
  end

  local onClick = stock.GetScript and stock:GetScript("OnClick")
  if type(onClick) == "function" then
    pcall(onClick, stock, mouseButton or "LeftButton")
    return
  end
end

local function applyBorderTint(button, hovered)
  if not (button and button.Border) then return end
  local tint = (hovered and button._hoverTint) or button._borderTint
  if not tint then return end
  button.Border:SetVertexColor(tint[1], tint[2], tint[3], tint[4] or 1)
end

local function applyIconHover(button, hovered)
  if not (button and button.Icon) then return end
  if not button._hasGlyph then
    button.Icon:SetAlpha(button._iconAlpha or 1)
    if button.IconTint then button.IconTint:SetAlpha(button._iconTintAlpha or 0) end
    return
  end

  local iconAlpha = button._iconAlpha or 1
  button.Icon:SetAlpha(hovered and math.min(1, iconAlpha + 0.45) or iconAlpha)
  if button.IconTint and button._iconTintShown then
    local tintAlpha = button._iconTintAlpha or 0
    button.IconTint:SetAlpha(hovered and math.min(1, tintAlpha + 0.40) or tintAlpha)
  end
end

local function setSocketHitRect(button, frameSize, hitSize)
  if not (button and button.SetHitRectInsets) then return end
  local inset = math.max(0, math.floor(((frameSize or 0) - (hitSize or 0)) / 2))
  button:SetHitRectInsets(inset, inset, inset, inset)
end

local function buildSocket(parent, index)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(64, 64)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  b.GlowUnder = b:CreateTexture(nil, "BACKGROUND", nil, -2)
  b.GlowUnder:SetPoint("CENTER")
  
  b.Globe = b:CreateTexture(nil, "BACKGROUND", nil, -1)
  b.Globe:SetPoint("CENTER")
  b.Globe:SetTexCoord(globeCoord(1))
  glyphGlobes[#glyphGlobes + 1] = b.Globe
  ensureGlobeTicker()

  b.Gloss = b:CreateTexture(nil, "ARTWORK", nil, 3)
  b.Gloss:SetPoint("CENTER")

  b.Border = b:CreateTexture(nil, "OVERLAY", nil, 1)
  b.Border:SetSize(64, 64)
  b.Border:SetPoint("CENTER")

  b.Glow = b:CreateTexture(nil, "ARTWORK", nil, -1)
  b.Glow:SetSize(82, 82)
  b.Glow:SetPoint("CENTER")
  b.Glow:SetBlendMode("ADD")
  b.Glow:Hide()

  b.Icon = b:CreateTexture(nil, "ARTWORK", nil, 1)
  b.Icon:SetSize(34, 34)
  b.Icon:SetPoint("CENTER")
  b.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  if b.Icon.SetVertexColor then b.Icon:SetVertexColor(1, 1, 1, 1) end

  b.IconTint = b:CreateTexture(nil, "ARTWORK", nil, 2)
  b.IconTint:SetSize(34, 34)
  b.IconTint:SetPoint("CENTER")
  b.IconTint:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.IconTint:SetBlendMode("ADD")
  b.IconTint:SetVertexColor(1.0, 0.84, 0.28)
  b.IconTint:SetAlpha(0.55)
  b.IconTint:Hide()

  b.Plus = b:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  b.Plus:SetPoint("CENTER", 0, 0)
  b.Plus:SetText("+")
  b.Plus:SetTextColor(0.95, 0.88, 0.55)

  b.Name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if _G.SystemFont_Shadow_Med1 then b.Name:SetFontObject(_G.SystemFont_Shadow_Med1) end
  b.Name:SetTextColor(0.95, 0.90, 0.75)
  b.Name:SetWidth(160)
  b.Name:SetWordWrap(true)
  b.Name:Hide()

  if index == 1 then
    b.Name:SetPoint("BOTTOM", b, "TOP", 0, 8)
    b.Name:SetJustifyH("CENTER")
  elseif index == 4 then
    b.Name:SetPoint("TOP", b, "BOTTOM", 0, -10)
    b.Name:SetJustifyH("CENTER")
  elseif index == 2 or index == 3 then
    b.Name:SetPoint("LEFT", b, "RIGHT", 10, 0)
    b.Name:SetJustifyH("LEFT")
  else
    b.Name:SetPoint("RIGHT", b, "LEFT", -10, 0)
    b.Name:SetJustifyH("RIGHT")
  end

  b:SetScript("OnEnter", function(self)
    self._hovered = true
    if self._hoverBorder then applyBorderTint(self, true) end
    applyIconHover(self, true)
    tooltipForSocket(self)
  end)
  b:SetScript("OnLeave", function(self)
    self._hovered = nil
    applyBorderTint(self, false)
    applyIconHover(self, false)
    if self.Glow then self.Glow:Hide() end
    GameTooltip:Hide()
  end)
  b:SetScript("OnClick", function(self, mouseButton)
    clickStockGlyphSocket(self, mouseButton)
  end)

  b._index = index
  return b
end

local function ensureGlyphOptionsMenu(anchor)
  if glyphOptionsMenu or not anchor then return glyphOptionsMenu end
  if not UIDropDownMenu_Initialize then return nil end
  local ok, menu = pcall(CreateFrame, "Frame", "NE_TalentGlyphOptionsMenu", anchor, "UIDropDownMenuTemplate")
  if not ok then return nil end
  menu.displayMode = "MENU"
  UIDropDownMenu_Initialize(menu, function(self, level)
    if level ~= 1 then return end

    local info = UIDropDownMenu_CreateInfo()
    info.text = L["Show glyph names"]
    info.checked = glyphLabelNamesEnabled()
    info.keepShownOnClick = true
    info.isNotRadio = true
    info.func = function()
      setGlyphLabelNamesEnabled(not glyphLabelNamesEnabled())
      if T.GlyphsRefresh then T.GlyphsRefresh() end
    end
    UIDropDownMenu_AddButton(info, level)

    local infoEffects = UIDropDownMenu_CreateInfo()
    infoEffects.text = L["Show glyph effects"]
    infoEffects.checked = glyphShowEffectsEnabled()
    infoEffects.keepShownOnClick = true
    infoEffects.isNotRadio = true
    infoEffects.func = function()
      setGlyphShowEffectsEnabled(not glyphShowEffectsEnabled())
      if T.GlyphsApplyPaneVisibility then T.GlyphsApplyPaneVisibility() end
      if T.GlyphsRefresh then T.GlyphsRefresh() end
    end
    UIDropDownMenu_AddButton(infoEffects, level)
  end)
  glyphOptionsMenu = menu
  return glyphOptionsMenu
end

local function buildGlyphCog(parent)
  if parent and parent.cog then return parent.cog end

  local cog = CreateFrame("Button", "NE_TalentGlyphCog", parent)
  cog:SetSize(18, 18)
  cog.Icon = cog:CreateTexture(nil, "ARTWORK")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Icon, "questlog-icon-setting", true)) then
    cog.Icon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog.Icon:SetSize(16, 16)
  end
  cog.Icon:SetPoint("CENTER")
  cog.Hi = cog:CreateTexture(nil, "HIGHLIGHT")
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(cog.Hi, "questlog-icon-setting", true)) then
    cog.Hi:SetTexture("Interface\\Buttons\\UI-OptionsButton")
    cog.Hi:SetSize(16, 16)
  end
  cog.Hi:SetPoint("CENTER")
  cog.Hi:SetBlendMode("ADD")
  cog.Hi:SetAlpha(0.4)
  cog:SetFrameLevel((parent:GetFrameLevel() or 1) + 10)
  cog:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -10, -10)
  cog:SetScript("OnClick", function(self)
    local menu = ensureGlyphOptionsMenu(parent)
    if menu and ToggleDropDownMenu then
      ToggleDropDownMenu(1, nil, menu, self, 6, 2)
      return
    end
    setGlyphLabelNamesEnabled(not glyphLabelNamesEnabled())
    if T.GlyphsRefresh then T.GlyphsRefresh() end
  end)
  cog:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(L["Glyph options"], 1, 1, 1)
    GameTooltip:AddLine(L["Toggle slot name labels and the active-effects list."], 0.85, 0.85, 0.85, true)
    GameTooltip:Show()
  end)
  cog:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  parent.cog = cog
  return cog
end

local function layoutRoot()
  local h = T.Host and T.Host() or T.frame
  if not h then return nil end
  ensureGlyphFlowDriver(h)

  if root and root:GetParent() ~= h then
    root:SetParent(h)
  end

  if not root then
    root = CreateFrame("Frame", "NE_TalentGlyphRoot", h)
    root:SetFrameLevel((h:GetFrameLevel() or 1))
    root.title = root:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    if _G.SystemFont_Shadow_Large2 then root.title:SetFontObject(_G.SystemFont_Shadow_Large2) end
    if root.title.SetTextScale then root.title:SetTextScale(1.1) end
    root.title:SetJustifyH("CENTER")
    root.title:SetPoint("TOP", root, "TOP", 0, -28)
    root.title:SetText(GLYPHS or L["GLYPHS"])
    root.title:SetTextColor(1, 1, 1)
    buildGlyphCog(root)
  end

  -- ---- NEW: Build the Expanded Glyph Summary List Panel on the Right Side -----------
  if root and not root.listFrame then
    local lf = CreateFrame("Frame", "NE_TalentGlyphListFrame", root)

    -- Framed "detail card" behind the text — the SAME dark panel our professions window uses
    -- for its item-details box: the "quality pane" 3-slice (charcoal fill, silver ornate
    -- top/bottom flourishes) off the shipped chrome sheet, registered by professions/Assets.lua.
    -- It sits BELOW the text layer so glyph text/icons always read on top; cap heights + overall
    -- size are (re)assigned each refresh in T.GlyphsRefresh.
    lf.card = CreateFrame("Frame", "NE_TalentGlyphCard", lf)
    lf.card:SetFrameLevel((lf:GetFrameLevel() or 1) + 1)
    -- Exactly the professions build: three slices, no separate base fill (the top/bottom caps
    -- carry the charcoal fill + rounded flourishes; the 1px middle stretches between them), so
    -- the rounded corners read clean against the class-art background.
    lf.card.PaneTop = lf.card:CreateTexture(nil, "BACKGROUND")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(lf.card.PaneTop, "professions-qualitypane-bg-top", false) end
    lf.card.PaneTop:SetPoint("TOPLEFT",  lf.card, "TOPLEFT",  0, 0)
    lf.card.PaneTop:SetPoint("TOPRIGHT", lf.card, "TOPRIGHT", 0, 0)
    lf.card.PaneBottom = lf.card:CreateTexture(nil, "BACKGROUND")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(lf.card.PaneBottom, "professions-qualitypane-bg-bottom", false) end
    lf.card.PaneBottom:SetPoint("BOTTOMLEFT",  lf.card, "BOTTOMLEFT",  0, 0)
    lf.card.PaneBottom:SetPoint("BOTTOMRIGHT", lf.card, "BOTTOMRIGHT", 0, 0)
    lf.card.PaneMid = lf.card:CreateTexture(nil, "BACKGROUND")
    if NE.tex and NE.tex.SetAtlas then NE.tex.SetAtlas(lf.card.PaneMid, "professions-qualitypane-bg-middle", false) end
    lf.card.PaneMid:SetPoint("TOPLEFT",     lf.card.PaneTop, "BOTTOMLEFT", 0, 0)
    lf.card.PaneMid:SetPoint("BOTTOMRIGHT", lf.card.PaneBottom, "TOPRIGHT", 0, 0)
    lf.card:Hide()

    -- Text layer above the card. Title, lines, and icons are all children of this frame so
    -- they draw over the card backdrop, while everything still toggles/hides with `lf`.
    lf.textLayer = CreateFrame("Frame", nil, lf)
    lf.textLayer:SetAllPoints(lf)
    lf.textLayer:SetFrameLevel((lf:GetFrameLevel() or 1) + 2)

    lf.title = lf.textLayer:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
    if _G.SystemFont_Shadow_Large2 then lf.title:SetFontObject(_G.SystemFont_Shadow_Large2) end
    if lf.title.SetTextScale then lf.title:SetTextScale(0.72) end -- Matches left side spec header scaling
    lf.title:SetText(L["ACTIVE EFFECTS"])
    lf.title:SetPoint("TOPLEFT", lf, "TOPLEFT", 40, -66)
    lf.title:SetTextColor(1, 1, 1)

    lf.lines = {}
    -- Lines are pooled; their width, scale, and anchor are (re)assigned every refresh in
    -- T.GlyphsRefresh so a real hanging indent can be applied (wrapped lines align to the
    -- FontString's left edge, so the indent lives in the anchor X, never in leading spaces).
    lf.GetOrCreateLine = function(self, index)
      if self.lines[index] then return self.lines[index] end
      local line = self.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      if _G.SystemFont_Shadow_Med1 then line:SetFontObject(_G.SystemFont_Shadow_Med1) end
      line:SetWordWrap(true)
      line:SetJustifyH("LEFT")
      self.lines[index] = line
      return line
    end

    -- Pooled glyph icons, one per name line (professions-panel style). The border is trimmed
    -- via texcoords; each is centred vertically over its name+description block.
    lf.icons = {}
    lf.GetOrCreateIcon = function(self, index)
      if self.icons[index] then return self.icons[index] end
      local tex = self.textLayer:CreateTexture(nil, "OVERLAY")
      tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      self.icons[index] = tex
      return tex
    end

    lf.scratchTip = CreateFrame("GameTooltip", "NE_GlyphScratchTooltip", nil, "GameTooltipTemplate")
    lf.scratchTip:SetOwner(WorldFrame, "ANCHOR_NONE")

    root.listFrame = lf
  end

  root:ClearAllPoints()
  root:SetPoint("TOPLEFT", h, "TOPLEFT", 0, 0)
  root:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, (T.FRAME and T.FRAME.BOTTOMBAR_H) or 80)
  return root
end

local function buildPane(group)
  if panes[group] then return panes[group] end

  local h = T.Host and T.Host() or T.frame
  if not h then return nil end

  local pane = CreateFrame("Frame", "NE_TalentGlyphPane" .. group, h)
  pane:SetFrameLevel((h:GetFrameLevel() or 1))

  pane.bg = pane:CreateTexture(nil, "BACKGROUND", nil, -1)
  pane.bg:SetAllPoints(pane)
  pane._bgNick = specBackgroundNick(group)
  pane._bgFlip = (group == 1)
  pane.bg:Hide()

  pane.spec = pane:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
  if _G.SystemFont_Shadow_Large2 then pane.spec:SetFontObject(_G.SystemFont_Shadow_Large2) end
  if pane.spec.SetTextScale then pane.spec:SetTextScale(0.72) end
  pane.spec:SetJustifyH("CENTER")
  pane.spec:SetPoint("TOP", pane, "TOP", 0, -66)
  pane.spec:SetText("")

  pane.core = pane:CreateTexture(nil, "ARTWORK")
  pane.core:SetSize(84, 84)
  pane.core:SetPoint("CENTER", 0, 0)
  pane.core:Hide()

  pane.coreIcon = pane:CreateTexture(nil, "OVERLAY", nil, 1)
  pane.coreIcon:SetSize(20, 20)
  pane.coreIcon:SetPoint("CENTER", 0, 0)
  if not setAtlas(pane.coreIcon, "questlog-icon-setting", "Interface\\Buttons\\UI-OptionsButton") then
    pane.coreIcon:SetSize(18, 18)
  end
  pane.coreIcon:Hide()

  pane.sockets = {}
  local positions = {
    [1] = { 0, 118 },
    [2] = { 102, 60 },
    [3] = { 102, -60 },
    [4] = { 0, -118 },
    [5] = { -102, -60 },
    [6] = { -102, 60 },
  }
  for displayIndex = 1, SOCKET_COUNT do
    local socket = buildSocket(pane, displayIndex)
    socket:SetPoint("CENTER", pane, "CENTER", positions[displayIndex][1], positions[displayIndex][2])
    pane.sockets[displayIndex] = socket
  end

  panes[group] = pane
  return pane
end

local function applyPaneStyle(pane, active)
  if not pane then return end
  local totalGroups = (GetNumTalentGroups and (GetNumTalentGroups() or 1)) or 1
  if totalGroups >= 2 then
    pane.spec:SetText(string.upper(groupStatus(pane._group or 1) or ""))
    pane.spec:Show()
  else
    pane.spec:SetText("")
    pane.spec:Hide()
  end
  pane.spec:SetTextColor(1, 1, 1)
end

local function updateSocket(button, info, activePane, wantMajor)
  button._glyphInfo = info
  button._group = info and info.group or button._group
  local slotIsMajor = (wantMajor == true) or (info and info.glyphType ~= 2) or false
  local slotButtonSize = slotIsMajor and 104 or 92
  local lockedMajorBorderSize = 74
  local emptyMajorBorderSize = 78
  local filledMajorBorderSize = 84
  local lockedMinorBorderSize = 57
  local emptyMinorBorderSize = 57
  local filledMinorBorderSize = 65

  if not info then
    button:SetSize(slotButtonSize, slotButtonSize)
    if button.Globe then button.Globe:Hide() end
    if button.GlowUnder then button.GlowUnder:Hide() end
    if button.Gloss then button.Gloss:Hide() end
    button.Border:SetTexture(GLYPH_RING_TEXTURE)
    local lockedBorderSize = slotIsMajor and lockedMajorBorderSize or lockedMinorBorderSize
    button.Border:SetSize(lockedBorderSize * RING_SCALE, lockedBorderSize * RING_SCALE)
    setSocketHitRect(button, slotButtonSize, lockedBorderSize)
    button._borderTint = { 0.55, 0.55, 0.55, 1 }
    button._hoverTint = nil
    button._hoverBorder = nil
    applyBorderTint(button, false)
    button.Icon:SetSize(34, 34)
    button.Icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    button._hasGlyph = nil
    button._iconAlpha = 1
    button._iconTintAlpha = 0
    button._iconTintShown = nil
    if button.Icon.SetDesaturated then button.Icon:SetDesaturated(true) end
    if button.IconTint then button.IconTint:Hide() end
    button.Glow:Hide()
    button.Plus:SetText("")
    button._fallbackName = "Glyph Socket"
    button._fallbackState = "Unavailable"
    if button.Name then
      button.Name:SetText("")
      button.Name:Hide()
    end
    button:EnableMouse(false)
    button._activePane = nil
    button:SetAlpha(0.45)
    return
  end

  button._activePane = activePane and true or nil
  button:EnableMouse(activePane and true or false)
  button:SetSize(slotButtonSize, slotButtonSize)
  button:SetAlpha(activePane and 1 or 0.55)

  if not info.enabled then
    button:SetSize(slotButtonSize, slotButtonSize)
    button.Border:SetTexture(GLYPH_RING_DESAT_TEXTURE)
    local lockedBorderSize = slotIsMajor and lockedMajorBorderSize or lockedMinorBorderSize
    button.Border:SetSize(lockedBorderSize * RING_SCALE, lockedBorderSize * RING_SCALE)
    configGlobe(button, slotIsMajor, false, lockedBorderSize)
    setSocketHitRect(button, slotButtonSize, lockedBorderSize)
    button._borderTint = { 0.55, 0.55, 0.55, 1 }
    button._hoverTint = nil
    button._hoverBorder = nil
    applyBorderTint(button, false)
    button.Icon:SetSize(34, 34)
    button.Icon:SetTexture(emptyGlyphIcon(info.glyphType))
    button._hasGlyph = nil
    button._iconAlpha = 1
    button._iconTintAlpha = 0
    button._iconTintShown = nil
    if button.Icon.SetDesaturated then button.Icon:SetDesaturated(true) end
    if button.IconTint then button.IconTint:Hide() end
    button.Glow:Hide()
    button.Plus:SetText("")
    button._fallbackName = "Locked socket"
    button._fallbackState = "Requires higher level"
    if button.Name then
      button.Name:SetText("")
      button.Name:Hide()
    end
    return
  end

  local spellName, _, spellIcon = nil, nil, nil
  if info.glyphSpellID and info.glyphSpellID > 0 and GetSpellInfo then
    spellName, _, spellIcon = GetSpellInfo(info.glyphSpellID)
  end

  local isMajor = slotIsMajor
  local hasGlyph = (type(info.glyphSpellID) == "number" and info.glyphSpellID > 0)
  local borderSize = isMajor and ((hasGlyph and filledMajorBorderSize) or emptyMajorBorderSize)
                     or ((hasGlyph and filledMinorBorderSize) or emptyMinorBorderSize)
  button.Border:SetTexture(GLYPH_RING_TEXTURE)
  button.Border:SetSize(borderSize * RING_SCALE, borderSize * RING_SCALE)
  configGlobe(button, isMajor, hasGlyph and activePane, borderSize)
  setSocketHitRect(button, slotButtonSize, borderSize)
  button._borderTint = activePane and { 1.0, 1.0, 1.0, 1 } or { 0.70, 0.70, 0.70, 1 }
  button._hoverTint = { 1.0, 1.0, 1.0, 1 }
  button._hoverBorder = true
  applyBorderTint(button, button._hovered)

  local iconSize
  if isMajor then
    iconSize = hasGlyph and 52 or 47
  else
    iconSize = hasGlyph and 34 or 30
  end
  if not activePane then iconSize = iconSize - 2 end
  if hasGlyph then iconSize = iconSize * 0.9 end
  button.Icon:SetSize(iconSize, iconSize)
  local iconTex = hasGlyph and (info.icon or spellIcon) or emptyGlyphIcon(info.glyphType)
  if not hasGlyph then button.Icon:SetTexture(nil) end
  button.Icon:SetTexture(iconTex)
  if button.Icon.SetVertexColor then button.Icon:SetVertexColor(1, 1, 1, 1) end
  button._hasGlyph = hasGlyph and true or nil
  button._iconAlpha = hasGlyph and (activePane and 0.75 or 0.6) or (activePane and 1 or 0.75)
  button.Icon:SetAlpha(button._iconAlpha)
  if button.Icon.SetDesaturated then
    if hasGlyph and activePane then
      button.Icon:SetDesaturated(false)
    else
      button.Icon:SetDesaturated(not activePane)
    end
  end

  if button.IconTint then
    if hasGlyph and activePane then
      button.IconTint:SetSize(iconSize, iconSize)
      button.IconTint:SetTexture(iconTex)
      button._iconTintAlpha = isMajor and 0.7 or 0.5
      button._iconTintShown = true
      button.IconTint:SetAlpha(button._iconTintAlpha)
      button.IconTint:Show()
    else
      button._iconTintAlpha = 0
      button._iconTintShown = nil
      button.IconTint:Hide()
    end
  end

  button.Glow:Hide()
  applyIconHover(button, button._hovered)

  button.Plus:SetText("")
  local displayName = hasGlyph and glyphDisplayName(info, spellName) or nil
  button._fallbackName = displayName or spellName or "Glyph"
  button._fallbackState = hasGlyph and "Equipped" or "Empty socket"
  if button.Name then
    if glyphLabelNamesEnabled() and hasGlyph and displayName then
      button.Name:SetText(displayName)
      button.Name:SetAlpha(activePane and 1 or 0.8)
      button.Name:Show()
    else
      button.Name:SetText("")
      button.Name:Hide()
    end
  end
end

local function layoutPane(pane, index, total, rootWidth, rootHeight)
  if not pane then return end

  local gap = 0
  local paneW, paneH

  if total >= 2 then
    paneW = math.floor((rootWidth - gap) / 2)
    paneH = math.floor(rootHeight)
    pane:SetSize(paneW, paneH)
    pane:ClearAllPoints()
    if index == 1 then
      pane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    else
      pane:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    end
  else
    paneW = math.floor(rootWidth)
    paneH = math.floor(rootHeight)
    pane:SetSize(paneW, paneH)
    pane:ClearAllPoints()
    pane:SetPoint("TOPLEFT", root, "TOPLEFT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", 0, 0)
  end

  applyPaneBackground(pane)
end

local function updatePane(pane, group, activeGroup)
  if not pane then return end
  pane._group = group
  local activePane = (group == activeGroup)
  applyPaneStyle(pane, activePane)
  pane:SetAlpha(activePane and 1 or 0.62)

  local numSockets = (GetNumGlyphSockets and GetNumGlyphSockets()) or 0
  local majors, minors, other = {}, {}, {}
  for socketIndex = 1, numSockets do
    local info = getSocketInfo(socketIndex, group)
    if info then
      info.group = group
      if info.glyphType == 2 then
        minors[#minors + 1] = info
      elseif info.glyphType == 1 then
        majors[#majors + 1] = info
      else
        other[#other + 1] = info
      end
    end
  end

  local function popFirst(tbl)
    if #tbl == 0 then return nil end
    return table.remove(tbl, 1)
  end

  for displayIndex = 1, SOCKET_COUNT do
    local button = pane.sockets[displayIndex]
    local wantMajor = (displayIndex % 2) == 1
    local info
    if wantMajor then
      info = popFirst(majors) or popFirst(other) or popFirst(minors)
    else
      info = popFirst(minors) or popFirst(other) or popFirst(majors)
    end
    updateSocket(button, info, activePane, wantMajor)
  end

  updatePaneEdges(pane, activePane)

  if T._glyphActive then pane:Show() else pane:Hide() end
end

local function ensurePanes()
  if not layoutRoot() then return nil end
  
  -- Force calculation to strictly use the currently active spec group
  local currentGroup = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  buildPane(currentGroup)
  
  return root
end

function T.GlyphsSetActive(on)
  T._glyphActive = on and true or false
  if T.GlyphsApplyPaneVisibility then
    T.GlyphsApplyPaneVisibility()
  end
end

function T.GlyphsIsActive()
  return T._glyphActive and true or false
end

local GLYPH_BG_PATH = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Talents\\Artifact\\"
local GLYPH_BG_FILE = {
  WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
  DEATHKNIGHT = "DeathKnight", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid",
}
local function applyGlyphBackground(f)
  if not f then return false end
  local _, classFile = UnitClass("player")
  local file = classFile and GLYPH_BG_FILE[classFile]
  if not file then return false end
  if not f.glyphBg then
    local FR = T.FRAME or {}
    local tx = f:CreateTexture(nil, "BORDER")
    tx:SetPoint("TOPLEFT",     f, "TOPLEFT",     (FR.CHROME_L or 0), -(FR.CHROME_T or 0))
    tx:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -(FR.CHROME_R or 0), (FR.CHROME_B or 0) + (FR.BOTTOMBAR_H or 0))
    tx:SetTexCoord(0, 1, 0, 1)
    f.glyphBg = tx
  end
  f.glyphBg:SetTexture(GLYPH_BG_PATH .. file)
  return true
end

function T.GlyphsApplyPaneVisibility()
  local f = T.frame
  local r = root or layoutRoot()
  if not r then return end

  if T._glyphActive then
    if root.listFrame then
      if glyphShowEffectsEnabled() then root.listFrame:Show() else root.listFrame:Hide() end
    end
    if f then
      if f.bg then f.bg:Hide() end
      if f.petBg then f.petBg:Hide() end
      
      local hasArt = applyGlyphBackground(f)
      if f.glyphBg then if hasArt then f.glyphBg:Show() else f.glyphBg:Hide() end end
      if hasArt then
        for _, pane in pairs(panes) do if pane and pane.bg then pane.bg:Hide() end end
      end
      if f.trees then
        for _, tree in ipairs(f.trees) do
          if tree then tree:Hide() end
        end
      end
      if f.bottomBar then f.bottomBar:Show() end
      if f.pointsText then f.pointsText:Hide() end
      if f._loBtn then f._loBtn:Hide() end
      if f.apply then f.apply:Hide() end
      if f.reset then f.reset:Hide() end
      if f.activate then f.activate:Hide() end
    end

    -- Force the visibility allocation to match the currently active spec group
    local currentGroup = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
    for g, pane in pairs(panes) do
      if pane then
        if g == currentGroup then
          pane:Show()
        else
          pane:Hide()
        end
      end
    end
    r:Show()
  else
    if root.listFrame then root.listFrame:Hide() end
    for _, pane in pairs(panes) do
      if pane then pane:Hide() end
    end
    r:Hide()
    if f then
      if f.glyphBg then f.glyphBg:Hide() end
      local petView = T.PetViewActive and T.PetViewActive()
      if f.bg then if petView then f.bg:Hide() else f.bg:Show() end end
      if f.petBg then if petView then f.petBg:Show() else f.petBg:Hide() end end
      if f._loBtn and not petView then f._loBtn:Show() end
      if f.trees then
        for _, tree in ipairs(f.trees) do
          if tree then tree:Show() end
        end
      end
      if f.bottomBar then f.bottomBar:Show() end
      if f.pointsText then f.pointsText:Show() end
    end
  end
end

function T.GlyphsEnsureUI()
  if not ensurePanes() then return end
  T.GlyphsRefresh()
  T.GlyphsApplyPaneVisibility()
end

function T.GlyphsRefresh()
  if not ensurePanes() then return end

  local h = T.Host and T.Host() or T.frame
  if not h then return end

  local rootWidth = (root and root:GetWidth()) or (h.GetWidth and h:GetWidth()) or 0
  local rootHeight = (root and root:GetHeight()) or (h.GetHeight and h:GetHeight()) or 0
  if rootWidth <= 0 or rootHeight <= 0 then return end

  local activeGroup = (GetActiveTalentGroup and GetActiveTalentGroup()) or 1
  local currentGroup = activeGroup -- Locks text scanning and ring display directly to active spec

  local showEffects = glyphShowEffectsEnabled()

  local pane = panes[currentGroup]
  if pane then
    layoutPane(pane, 1, showEffects and 2 or 1, rootWidth, rootHeight)
    updatePane(pane, currentGroup, activeGroup)
  end

  if root.listFrame then
    if not showEffects then
      root.listFrame:Hide()
      for _, line in pairs(root.listFrame.lines) do line:SetText(""); line:Hide() end
    else
    root.listFrame:Show()
    local paneW = math.floor(rootWidth / 2)
    root.listFrame:SetSize(paneW, rootHeight)
    root.listFrame:ClearAllPoints()
    root.listFrame:SetPoint("TOPRIGHT", root, "TOPRIGHT", 0, 0)
    
    local numSockets = (GetNumGlyphSockets and GetNumGlyphSockets()) or 0
    local majors, minors = {}, {}

    local function getSpellDesc(spellID)
      if not spellID or spellID <= 0 then return "" end
      local tip = root.listFrame.scratchTip
      tip:ClearLines()
      tip:SetHyperlink("spell:" .. spellID)
      
      for k = 2, tip:NumLines() do
        local textObj = _G["NE_GlyphScratchTooltipTextLeft" .. k]
        if textObj and textObj.GetText then
          local txt = textObj:GetText()
          if txt and txt ~= "" and not txt:find("^%s*Requires") then
            return txt
          end
        end
      end
      return ""
    end

    for i = 1, numSockets do
      local info = getSocketInfo(i, currentGroup)
      if info and info.enabled and type(info.glyphSpellID) == "number" and info.glyphSpellID > 0 then
        local spellName, _, spellIcon = GetSpellInfo(info.glyphSpellID)
        if spellName then
          local data = { name = trimGlyphPrefix(spellName), desc = getSpellDesc(info.glyphSpellID),
                         icon = info.icon or spellIcon }
          if info.glyphType == 2 then
            table.insert(minors, data)
          else
            table.insert(majors, data)
          end
        end
      end
    end

    -- Build a flat, ordered list of entries to render. Rather than chain-anchoring each
    -- line to the previous line's BOTTOMLEFT (which relies on a word-wrapped + text-scaled
    -- FontString reporting an accurate auto-height — it does NOT on 3.3.5a, which is what
    -- lets a 2-line description overlap its neighbour), we lay lines out with explicit Y
    -- offsets computed from GetStringHeight(), which measures the true wrapped height.
    --
    -- Indentation is a REAL hanging indent: each entry carries an `indent` in pixels that is
    -- applied to its anchor X, so word-wrapped continuation lines align to the same left edge
    -- as the first line (leading spaces would only indent the first line — that was the
    -- Trueshot-Aura misalignment).
    local SECTION_SCALE, NAME_SCALE, DESC_SCALE = 1.15, 1.08, 1.02

    -- ---- Card + column geometry (a professions-detail-box-sized panel, centred in the pane) --
    -- The card is a fixed, moderate width (like the professions item-details box) rather than
    -- the whole half-pane; all X offsets below are measured from the CARD's left edge.
    local CARD_W = math.max(320, math.min(440, math.floor(paneW - 80)))
    local cardX = math.floor((paneW - CARD_W) / 2)   -- card left, within the (right-half) pane
    local TEXT_PAD = 26                              -- inset from card edge to headers/text/right
    local ICON_X, ICON_SIZE, ICON_PAD = TEXT_PAD, 26, 8
    -- Name AND description share this left edge; the icon lives in the gutter to the left of it.
    local TEXT_INDENT = ICON_X + ICON_SIZE + ICON_PAD

    local entries = {}
    -- indent   = X offset of the TEXT from the card's left edge (the real hanging indent).
    -- icon     = texture path for a glyph icon (set on the NAME entry only), placed in the gutter.
    -- blockEnd = for a name entry, the entry index of the last line of its glyph block (the
    --            description if present, else itself) so the icon can centre over name+desc.
    local function addEntry(text, scale, gap, indent, icon)
      entries[#entries + 1] = { text = text, scale = scale, gap = gap, indent = indent or 0, icon = icon }
      return #entries
    end
    local function addSection(headerText, list)
      addEntry("|cffffcc55" .. headerText .. "|r", SECTION_SCALE, (#entries > 0) and 28 or 0, TEXT_PAD)
      if #list == 0 then
        addEntry("|cff808080None active.|r", NAME_SCALE, 8, TEXT_INDENT)
      else
        for _, glyph in ipairs(list) do
          -- Name and description both sit at TEXT_INDENT; the icon spans the two of them.
          local nameIdx = addEntry("|cffffd100" .. glyph.name .. "|r", NAME_SCALE, 10, TEXT_INDENT, glyph.icon)
          local lastIdx = nameIdx
          if glyph.desc ~= "" then
            lastIdx = addEntry("|cffb3b3b3" .. glyph.desc .. "|r", DESC_SCALE, 4, TEXT_INDENT)
          end
          entries[nameIdx].blockEnd = lastIdx
        end
      end
    end

    -- With glyphs equipped the panel is just the MAJOR/MINOR GLYPHS lists (no title). With
    -- none, the whole panel reads "NO ACTIVE EFFECTS", centred. The two are mutually exclusive.
    local hasAny = (#majors > 0) or (#minors > 0)
    if hasAny then
      root.listFrame.title:SetText("")
      root.listFrame.title:Hide()
      addSection(L["MAJOR GLYPHS"], majors)
      addSection(L["MINOR GLYPHS"], minors)
    else
      root.listFrame.title:SetText(L["NO ACTIVE EFFECTS"])
      root.listFrame.title:Show()
    end

    -- Reset every pooled line + icon, then materialise text + scale + width so heights measure.
    -- Each line's width is the card width minus its indent and the right inset.
    for _, line in pairs(root.listFrame.lines) do line:SetText(""); line:Hide() end
    for _, ic in pairs(root.listFrame.icons) do ic:Hide() end
    local rendered = {}
    for idx, e in ipairs(entries) do
      local line = root.listFrame:GetOrCreateLine(idx)
      line:SetWidth(math.max(80, CARD_W - e.indent - TEXT_PAD))
      line:SetText(e.text)
      if line.SetTextScale then line:SetTextScale(e.scale) end
      rendered[idx] = line
    end

    -- Measure the full block so we can centre it on the Y axis. The title only exists in the
    -- empty state; when glyphs are present it's hidden and contributes no height/gap.
    local TITLE_GAP = 22
    local titleH = hasAny and 0
                   or ((root.listFrame.title.GetStringHeight and root.listFrame.title:GetStringHeight()) or 0)
    local blockH = titleH
    if titleH > 0 and #entries > 0 then blockH = blockH + TITLE_GAP end
    for idx, e in ipairs(entries) do
      blockH = blockH + e.gap + ((rendered[idx].GetStringHeight and rendered[idx]:GetStringHeight()) or 0)
    end

    -- Centre the block vertically within the content pane (clamped so it never rides up into
    -- the GLYPHS header). The (empty-state) title is centred horizontally over the card;
    -- entries stay left-aligned to the card's text column.
    local topOffset = math.max(24, math.floor((rootHeight - blockH) / 2))
    root.listFrame.title:ClearAllPoints()
    root.listFrame.title:SetJustifyH("CENTER")
    root.listFrame.title:SetPoint("TOP", root.listFrame, "TOPLEFT", cardX + CARD_W / 2, -topOffset)

    -- Stack entries with explicit, measured offsets from the card's top-left — no overlap
    -- possible, and each line's hanging indent lives in the anchor X so wrapped lines align.
    -- Record each line's top and height so glyph icons can centre over the name+desc block.
    local lineTop, lineH = {}, {}
    local y = topOffset + titleH + ((titleH > 0 and #entries > 0) and TITLE_GAP or 0)
    for idx, e in ipairs(entries) do
      local line = rendered[idx]
      y = y + e.gap
      line:ClearAllPoints()
      line:SetPoint("TOPLEFT", root.listFrame, "TOPLEFT", cardX + e.indent, -y)
      line:Show()
      lineTop[idx] = y
      lineH[idx] = (line.GetStringHeight and line:GetStringHeight()) or 0
      y = y + lineH[idx]
    end

    -- Second pass: place each glyph icon in the left gutter, vertically centred between the
    -- top of its name and the bottom of its description.
    for idx, e in ipairs(entries) do
      if e.icon then
        local last = e.blockEnd or idx
        local blockTop = lineTop[idx]
        local blockBottom = (lineTop[last] or lineTop[idx]) + (lineH[last] or lineH[idx] or 0)
        local iconCenter = (blockTop + blockBottom) / 2
        local ic = root.listFrame:GetOrCreateIcon(idx)
        ic:SetTexture(e.icon)
        ic:SetSize(ICON_SIZE, ICON_SIZE)
        ic:ClearAllPoints()
        ic:SetPoint("TOPLEFT", root.listFrame, "TOPLEFT", cardX + ICON_X, -(iconCenter - ICON_SIZE / 2))
        ic:Show()
      end
    end

    -- Detail card: fixed width, wrapping the content block with padding. Cap heights preserve
    -- the flourish aspect (as the professions box does); the card is grown to at least twice
    -- the cap height so the top/bottom flourishes never overlap on a short list.
    if root.listFrame.card then
      local card = root.listFrame.card
      local contentBottom = (#entries > 0) and y or (topOffset + titleH)
      local CARD_PAD_TOP, CARD_PAD_BOTTOM = 40, 40
      local cardTop = topOffset - CARD_PAD_TOP
      local cardBottom = contentBottom + CARD_PAD_BOTTOM
      local capH = math.floor(100 * CARD_W / 260 + 0.5)
      local minH = capH * 2
      if (cardBottom - cardTop) < minH then
        local c = (cardTop + cardBottom) / 2
        cardTop, cardBottom = c - minH / 2, c + minH / 2
      end
      card.PaneTop:SetHeight(capH)
      card.PaneBottom:SetHeight(capH)
      card:ClearAllPoints()
      card:SetPoint("TOPLEFT", root.listFrame, "TOPLEFT", cardX, -cardTop)
      card:SetPoint("BOTTOMRIGHT", root.listFrame, "TOPLEFT", cardX + CARD_W, -cardBottom)
      card:Show()
    end
  end
  end

  for g, p in pairs(panes) do
    if p and g ~= currentGroup then
      p:Hide()
    end
  end
end