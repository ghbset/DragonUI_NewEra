-- DragonUI_NewEra/modules/character/PetPaperDoll.lua — the Pet secondary tab.
--
-- Fills the EMPTY pane DragonUI_NewEra_CharacterPane_Pet (created by TabButtons.lua, parented to
-- NE.charpanel.frame.Inset). Pet MODEL + pet INFO (name / level+family / happiness / loyalty /
-- diet) + an XP bar + a scrollable pet-STATS list — the player-paperdoll idiom applied to the pet,
-- ported in spirit from NewEra/CharacterPanel/PetPaperDoll.lua.
--
-- DOWNPORT (CONTRACT_S1 §A0/§A.2/§B): NewEra reparented the stock PetModelFrame into a class-themed
-- 3D scene driven by the stock PetPaperDollFrame_Update, and used WowScrollBox for the right stats
-- sidebar. Our custom panel HIDES the stock CharacterFrame, so the stock pet-update path does NOT
-- run — we therefore DRIVE the model ourselves (model:SetUnit("pet")) and read pet data directly.
-- Stats render in a NAMED FauxScrollFrame (unnamed FauxScrollFrameTemplate ERRORS).
--
-- DATA (3.3.5a): UnitExists/UnitName/UnitLevel/UnitCreatureFamily("pet"), GetPetHappiness,
-- GetPetLoyalty, GetPetFoodTypes, GetPetExperience, GetPetTrainingPoints, UnitStat/UnitArmor/
-- UnitResistance/UnitDamage/UnitAttackPower/UnitAttackSpeed/UnitHealthMax/UnitPowerMax("pet").
-- Many are HUNTER-pet-only (happiness/loyalty/diet/training) and are nil for warlock minions —
-- every one is guarded.
--
-- GRACEFUL DEGRADATION (§A.5): NO pet → the pane shows a centered "You do not have a pet." line and
-- hides the model/stats; every getter is pcall-guarded — NEVER errors.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local function log(msg)
  if CP._log then CP._log("PET: " .. tostring(msg)); return end
  if NE.Log then NE.Log("PET", msg); return end
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffcc55DragonUI_NewEra|r [pet]: " .. tostring(msg))
  end
end

local function L(global, fallback)
  local v = _G[global]
  if type(v) == "string" and v ~= "" then return v end
  return fallback
end

local function setAtlas(tex, name, useAtlasSize)
  if tex and NE.tex and NE.tex.SetAtlas then return NE.tex.SetAtlas(tex, name, useAtlasSize) end
  return false
end

local function safe(fn, ...)
  if type(fn) ~= "function" then return end
  local r = { pcall(fn, ...) }
  if r[1] then return select(2, unpack(r)) end
end

-- Geometry. The pane covers the Inset (~330 wide collapsed). Model on top, info overlay, XP bar,
-- then a scrollable stats list filling the rest.
local MODEL_H   = 200
local XP_H      = 14
local STAT_ROW  = 16
local FILL_TEX  = "Interface\\PaperDollInfoFrame\\UI-Character-Skills-Bar"
local XP_COLOR  = { 0.58, 0, 0.55 }   -- stock pet-XP purple

-- UI-PetHappiness cells (PetFrame_SetHappiness): 1=unhappy 2=content 3=happy.
local HAPPINESS_TC = {
  [1] = { 0.375, 0.5625 }, [2] = { 0.1875, 0.375 }, [3] = { 0, 0.1875 },
}

-- ---------------------------------------------------------------------------
-- Pet stat definitions (label + a guarded compute() -> value, tooltipTitle, tooltipLines).
-- Resistance school indices: Fire=2 Nature=3 Frost=4 Shadow=5 Arcane=6.
-- ---------------------------------------------------------------------------
local function statPrimary(idx, labelText)
  return function()
    local _, effective = UnitStat("pet", idx)
    effective = effective or 0
    return tostring(effective), labelText .. " " .. effective
  end
end

local function statResist(schoolIdx, schoolLabel)
  return function()
    local base, resistance = UnitResistance("pet", schoolIdx)
    resistance = resistance or 0
    return tostring(resistance), schoolLabel .. " " .. L("RESISTANCE", "Resistance") .. ": " .. resistance,
      { "Reduces " .. schoolLabel:lower() .. " damage taken." }
  end
end

local DEF_HEALTH = { label = L("HEALTH", "Health"), compute = function()
  local v = UnitHealthMax("pet") or 0
  return tostring(v), L("HEALTH", "Health") .. " " .. v
end }
local DEF_POWER = { label = L("MANA", "Mana"),
  relabel = function() local _, t = UnitPowerType("pet"); return _G[t or ""] or L("MANA", "Mana") end,
  compute = function()
    local v = UnitPowerMax("pet") or 0
    local _, t = UnitPowerType("pet")
    return tostring(v), (_G[t or ""] or L("MANA", "Mana")) .. " " .. v
  end }
local DEF_TRAINING = { label = L("PET_TRAIN_BUTTON", "Training Points"), compute = function()
  local total, spent = GetPetTrainingPoints()
  total, spent = total or 0, spent or 0
  local unspent = total - spent
  return tostring(unspent), L("PET_TRAIN_BUTTON", "Training Points") .. ": " .. unspent,
    { string.format("Total: %d", total), string.format("Spent: %d", spent) }
end }
local DEF_DAMAGE = { label = L("DAMAGE", "Damage"), compute = function()
  local minDmg, maxDmg = UnitDamage("pet")
  local low  = math.max(math.floor(minDmg or 0), 1)
  local high = math.max(math.ceil(maxDmg or 0), 1)
  local value = low .. " - " .. high
  return value, L("DAMAGE", "Damage") .. " " .. value
end }
local DEF_AP = { label = L("ATTACK_POWER", "Attack Power"), compute = function()
  local base, pos, neg = UnitAttackPower("pet")
  local eff = (base or 0) + (pos or 0) + (neg or 0)
  return tostring(eff), L("ATTACK_POWER", "Attack Power") .. ": " .. eff
end }
local DEF_ATTACK_SPEED = { label = L("ATTACK_SPEED", "Attack Speed"), compute = function()
  local speed = UnitAttackSpeed("pet") or 0
  local value = string.format("%.2f", speed)
  return value, L("ATTACK_SPEED", "Attack Speed") .. " " .. value
end }
local DEF_ARMOR = { label = L("ARMOR", "Armor"), compute = function()
  local _, effective = UnitArmor("pet")
  effective = effective or 0
  return tostring(math.floor(effective)), L("ARMOR", "Armor") .. " " .. math.floor(effective)
end }

local DEF_RESISTS = {
  { label = L("DAMAGE_SCHOOL6", "Arcane"), compute = statResist(6, L("DAMAGE_SCHOOL6", "Arcane")) },
  { label = L("DAMAGE_SCHOOL2", "Fire"),   compute = statResist(2, L("DAMAGE_SCHOOL2", "Fire")) },
  { label = L("DAMAGE_SCHOOL4", "Frost"),  compute = statResist(4, L("DAMAGE_SCHOOL4", "Frost")) },
  { label = L("DAMAGE_SCHOOL3", "Nature"), compute = statResist(3, L("DAMAGE_SCHOOL3", "Nature")) },
  { label = L("DAMAGE_SCHOOL5", "Shadow"), compute = statResist(5, L("DAMAGE_SCHOOL5", "Shadow")) },
}

local function isHunter() return (select(2, UnitClass("player"))) == "HUNTER" end

-- Build the flat stat list (headers + rows), hunter-only Training row included for hunters.
local function buildStatDefs()
  local sections = {
    { title = L("GENERAL", "General"), defs = (function()
        local t = { DEF_HEALTH, DEF_POWER }
        if isHunter() then t[#t + 1] = DEF_TRAINING end
        return t
      end)() },
    { title = L("STAT_CATEGORY_ATTRIBUTES", "Attributes"), defs = {
        { label = L("SPELL_STAT1_NAME", "Strength"),  compute = statPrimary(1, L("SPELL_STAT1_NAME", "Strength") .. ":") },
        { label = L("SPELL_STAT2_NAME", "Agility"),   compute = statPrimary(2, L("SPELL_STAT2_NAME", "Agility") .. ":") },
        { label = L("SPELL_STAT3_NAME", "Stamina"),   compute = statPrimary(3, L("SPELL_STAT3_NAME", "Stamina") .. ":") },
        { label = L("SPELL_STAT4_NAME", "Intellect"), compute = statPrimary(4, L("SPELL_STAT4_NAME", "Intellect") .. ":") },
        { label = L("SPELL_STAT5_NAME", "Spirit"),    compute = statPrimary(5, L("SPELL_STAT5_NAME", "Spirit") .. ":") },
      } },
    { title = L("MELEE", "Attack"), defs = { DEF_DAMAGE, DEF_AP, DEF_ATTACK_SPEED } },
    { title = L("DEFENSE", "Defense"), defs = { DEF_ARMOR } },
    { title = L("RESISTANCE", "Resistances"), defs = DEF_RESISTS },
  }
  return sections
end

-- ---------------------------------------------------------------------------
-- Pane state.
-- ---------------------------------------------------------------------------
local pane, scene, model, info, happy, xpBar
local nameText, levelText, loyaltyText, dietText
local statScroll, statContent
local statHeaders, statRows = {}, {}   -- recycled by index
local flat = {}                        -- { kind="header"/"row", ... }
local NUM_VISIBLE = 0
local noPetLabel

local function getPane()
  if pane then return pane end
  pane = _G.DragonUI_NewEra_CharacterPane_Pet or (CP.EnsurePane and CP.EnsurePane("Pet"))
  return pane
end

-- ---------------------------------------------------------------------------
-- Build the model scene + info overlay + XP bar (top half of the pane).
-- ---------------------------------------------------------------------------
local function buildScene(host)
  if scene then return end
  scene = CreateFrame("Frame", "DragonUI_NewEra_PetScene", host)
  -- DOWNPORT/REPORT: the PET STATS now live in the InsetRight sidebar (CP.ExpandPetSidebar), so the
  -- scene fills the WHOLE Inset pane (model + name/level/loyalty/diet + XP bar) instead of just the
  -- top MODEL_H band above an in-pane stats list. Anchor BOTTOMRIGHT to the pane.
  scene:SetPoint("TOPLEFT", host, "TOPLEFT", 4, -4)
  scene:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -4, 4)

  -- Class-themed backdrop (degrades silently if not shipped).
  local bg = scene:CreateTexture(nil, "BACKGROUND")
  local _, classFile = UnitClass("player")
  if not setAtlas(bg, "ui-character-info-" .. (classFile and classFile:lower() or "hunter") .. "-bg", false) then
    if bg.SetColorTexture then bg:SetColorTexture(0.06, 0.06, 0.08, 0.6) else bg:SetTexture(0.06, 0.06, 0.08, 0.6) end
  end
  bg:SetAllPoints(scene)

  -- The 3D pet model. Reparent the stock PetModelFrame if present (its global name keeps any stock
  -- driving intact); else create our own PlayerModel. We drive SetUnit("pet") ourselves on refresh.
  local m = _G.PetModelFrame
  if m and m.SetParent then
    m:SetParent(scene)
  else
    m = CreateFrame("PlayerModel", "DragonUI_NewEra_PetModel", scene)
  end
  m:ClearAllPoints()
  m:SetPoint("TOPLEFT", scene, "TOPLEFT", 6, -28)
  m:SetPoint("BOTTOMRIGHT", scene, "BOTTOMRIGHT", -6, 6)
  m:SetFrameLevel(scene:GetFrameLevel() + 1)
  model = m

  -- DOWNPORT/REPORT (Issue C): the stock 3.3.5a pet model frame ships wooden rotate buttons. When we
  -- reparent PetModelFrame they get orphaned / float at the screen origin. HIDE the stray vanilla
  -- rotate buttons (both the pet-model's and — belt-and-suspenders — the character-model's, since the
  -- player paperdoll is hidden on this tab). A hidden button is never PUSHED, so stock Model_OnUpdate
  -- no-ops on it. The pet model has NO controls (static display) — see below.
  for _, name in ipairs({
    "PetModelFrameRotateLeftButton", "PetModelFrameRotateRightButton",
    "PetModelRotateLeftButton", "PetModelRotateRightButton",
    "PetPaperDollFrameRotateLeftButton", "PetPaperDollFrameRotateRightButton",
    "CharacterModelFrameRotateLeftButton", "CharacterModelFrameRotateRightButton",
  }) do
    local b = _G[name]
    if b then pcall(function() b:Hide(); if b.SetAlpha then b:SetAlpha(0) end end) end
  end

  -- DOWNPORT/REPORT: the pet model is a STATIC display — no zoom, no rotate (per design). We do NOT
  -- attach CP.BuildModelControls, and we disable mouse + wheel on the model so there is no drag-rotate
  -- or wheel-zoom either.
  if m.EnableMouse then pcall(m.EnableMouse, m, false) end
  if m.EnableMouseWheel then pcall(m.EnableMouseWheel, m, false) end

  -- Info overlay (above the model): happiness face + pet name.
  info = CreateFrame("Frame", nil, scene)
  info:SetPoint("TOPLEFT", scene, "TOPLEFT", 8, -4)
  info:SetPoint("TOPRIGHT", scene, "TOPRIGHT", -8, -4)
  info:SetHeight(22)
  info:SetFrameLevel(scene:GetFrameLevel() + 4)

  happy = CreateFrame("Frame", nil, info)
  happy:SetSize(20, 19)
  happy:SetPoint("LEFT", info, "LEFT", 0, 0)
  happy:EnableMouse(true)
  local ht = happy:CreateTexture(nil, "ARTWORK")
  ht:SetAllPoints(happy)
  ht:SetTexture("Interface\\PetPaperDollFrame\\UI-PetHappiness")
  happy.tex = ht
  happy:SetScript("OnEnter", function(self)
    if not self.tooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.tooltip, 1, 1, 1)
    GameTooltip:Show()
  end)
  happy:SetScript("OnLeave", function() GameTooltip:Hide() end)
  happy:Hide()

  nameText = info:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  nameText:SetPoint("LEFT", info, "LEFT", 0, 0)
  nameText:SetJustifyH("LEFT")
  nameText:SetShadowColor(0, 0, 0, 1); nameText:SetShadowOffset(1, -1)

  levelText = scene:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  levelText:SetPoint("TOPLEFT", info, "BOTTOMLEFT", 0, -2)
  levelText:SetJustifyH("LEFT")
  levelText:SetShadowColor(0, 0, 0, 1); levelText:SetShadowOffset(1, -1)

  loyaltyText = scene:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  loyaltyText:SetPoint("TOPLEFT", levelText, "BOTTOMLEFT", 0, -2)
  loyaltyText:SetJustifyH("LEFT")
  loyaltyText:SetShadowColor(0, 0, 0, 1); loyaltyText:SetShadowOffset(1, -1)

  dietText = scene:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  dietText:SetPoint("BOTTOMLEFT", scene, "BOTTOMLEFT", 8, XP_H + 6)
  dietText:SetPoint("RIGHT", scene, "RIGHT", -8, 0)
  dietText:SetJustifyH("LEFT")
  dietText:SetWordWrap(true)
  dietText:SetShadowColor(0, 0, 0, 1); dietText:SetShadowOffset(1, -1)

  -- XP bar along the scene bottom.
  xpBar = CreateFrame("StatusBar", "DragonUI_NewEra_PetXPBar", scene)
  xpBar:SetHeight(XP_H)
  xpBar:SetPoint("BOTTOMLEFT", scene, "BOTTOMLEFT", 8, 4)
  xpBar:SetPoint("BOTTOMRIGHT", scene, "BOTTOMRIGHT", -8, 4)
  xpBar:SetFrameLevel(scene:GetFrameLevel() + 5)
  xpBar:SetStatusBarTexture(FILL_TEX)
  local xt = xpBar:GetStatusBarTexture()
  if xt then xt:SetDrawLayer("BORDER") end
  xpBar:SetStatusBarColor(XP_COLOR[1], XP_COLOR[2], XP_COLOR[3])
  xpBar:SetMinMaxValues(0, 1); xpBar:SetValue(0)
  local xbg = xpBar:CreateTexture(nil, "BACKGROUND")
  xbg:SetAllPoints(xpBar)
  if xbg.SetColorTexture then xbg:SetColorTexture(0, 0, 0, 0.8) else xbg:SetTexture(0, 0, 0, 0.8) end
  xpBar._text = xpBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  xpBar._text:SetPoint("CENTER", xpBar, "CENTER", 0, 0)
end

-- ---------------------------------------------------------------------------
-- Build the stats list (bottom half, named FauxScrollFrame).
-- ---------------------------------------------------------------------------
local function buildStatRow(parent)
  local row = CreateFrame("Frame", nil, parent)
  row:SetHeight(STAT_ROW)
  local zebra = row:CreateTexture(nil, "BACKGROUND")
  zebra:SetAllPoints(row)
  if zebra.SetColorTexture then zebra:SetColorTexture(1, 1, 1, 0.04) else zebra:SetTexture(1, 1, 1, 0.04) end
  row._zebra = zebra
  row._label = row:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
  row._label:SetPoint("LEFT", row, "LEFT", 10, 0)
  row._value = row:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  row._value:SetPoint("RIGHT", row, "RIGHT", -8, 0)
  row:EnableMouse(true)
  row:SetScript("OnEnter", function(self)
    if not self._tipTitle then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self._tipTitle, 1, 1, 1, 1, true)
    if self._tipLines then
      for _, ln in ipairs(self._tipLines) do
        if ln and ln ~= "" then GameTooltip:AddLine(ln, 1, 0.82, 0.1, true) end
      end
    end
    GameTooltip:Show()
  end)
  row:SetScript("OnLeave", function() GameTooltip:Hide() end)
  return row
end

local function buildStatHeader(parent)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(STAT_ROW + 4)
  local hb = h:CreateTexture(nil, "BACKGROUND")
  hb:SetAllPoints(h)
  if not setAtlas(hb, "UI-Character-Info-Title", false) then
    if hb.SetColorTexture then hb:SetColorTexture(0.2, 0.16, 0.1, 0.5) else hb:SetTexture(0.2, 0.16, 0.1, 0.5) end
  end
  h._name = h:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  h._name:SetPoint("CENTER", h, "CENTER", 0, 0)
  return h
end

local function acquireHeader(i)
  if not statHeaders[i] then statHeaders[i] = buildStatHeader(statContent) end
  return statHeaders[i]
end
local function acquireRow(i)
  if not statRows[i] then statRows[i] = buildStatRow(statContent) end
  return statRows[i]
end

local function hideAllStatWidgets()
  for _, h in ipairs(statHeaders) do h:Hide() end
  for _, r in ipairs(statRows) do r:Hide() end
end

-- Rebuild the flat list from the stat sections, computing each value (guarded).
local function rebuildStatFlat()
  flat = {}
  if not UnitExists("pet") then return end
  for _, sec in ipairs(buildStatDefs()) do
    flat[#flat + 1] = { kind = "header", title = sec.title }
    local n = 0
    for _, def in ipairs(sec.defs) do
      n = n + 1
      local label = def.label
      if def.relabel then label = safe(def.relabel) or label end
      local value, tipTitle, tipLines = "--", nil, nil
      local ok, v, t, lines = pcall(def.compute)
      if ok then value, tipTitle, tipLines = v or "--", t, lines end
      flat[#flat + 1] = { kind = "row", label = label, value = value, even = (n % 2 == 0),
                          tipTitle = tipTitle, tipLines = tipLines }
    end
  end
end

local function updateStatScroll()
  if not (statScroll and statContent) then return end
  hideAllStatWidgets()
  local total = #flat
  local nRows = NUM_VISIBLE > 0 and NUM_VISIBLE or 1
  if FauxScrollFrame_Update then FauxScrollFrame_Update(statScroll, total, nRows, STAT_ROW) end
  local offset = (FauxScrollFrame_GetOffset and FauxScrollFrame_GetOffset(statScroll)) or 0

  local rowW = statContent:GetWidth() or 200
  if rowW <= 0 then rowW = 200 end

  local hUsed, rUsed = 0, 0
  for i = 1, nRows do
    local data = flat[offset + i]
    if data then
      local w
      if data.kind == "header" then
        hUsed = hUsed + 1
        w = acquireHeader(hUsed)
        w._name:SetText(data.title)
      else
        rUsed = rUsed + 1
        w = acquireRow(rUsed)
        w._label:SetText(data.label)
        w._value:SetText(data.value or "--")
        if data.even then w._zebra:Show() else w._zebra:Hide() end
        w._tipTitle = data.tipTitle
        w._tipLines = data.tipLines
      end
      w:ClearAllPoints()
      w:SetWidth(rowW)
      w:SetPoint("TOPLEFT", statContent, "TOPLEFT", 0, -(i - 1) * STAT_ROW)
    end
  end
end

local function recomputeVisible()
  if not statScroll then return end
  local h = statScroll:GetHeight() or 0
  NUM_VISIBLE = math.max(1, math.floor(h / STAT_ROW))
end

local function buildStatsList(host)
  if statScroll then return end
  statScroll = CreateFrame("ScrollFrame", "DragonUI_NewEra_PetStatsScroll", host, "FauxScrollFrameTemplate")
  statScroll:SetPoint("TOPLEFT", host, "TOPLEFT", 6, -(MODEL_H + 12))
  statScroll:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -26, 6)
  statScroll:SetScript("OnVerticalScroll", function(self, offset)
    FauxScrollFrame_OnVerticalScroll(self, offset, STAT_ROW, updateStatScroll)
  end)
  statScroll:HookScript("OnSizeChanged", function() recomputeVisible(); updateStatScroll() end)
  -- DOWNPORT: hand-built minimal scrollbar (Reskin's stock-slider re-skin didn't render).
  if NE.scrollbar and NE.scrollbar.BuildCustom then pcall(NE.scrollbar.BuildCustom, statScroll, { x = 6 }) end

  statContent = CreateFrame("Frame", nil, statScroll)
  statContent:SetPoint("TOPLEFT", statScroll, "TOPLEFT", 0, 0)
  statContent:SetPoint("RIGHT", statScroll, "RIGHT", 0, 0)
  statContent:SetHeight(1)
  recomputeVisible()
end

-- ---------------------------------------------------------------------------
-- Refresh: drive the model + fill info + XP + stats. NO pet → degrade.
-- ---------------------------------------------------------------------------
local function refresh()
  if not getPane() then return end
  if not scene then return end

  local hasPet = UnitExists("pet")
  if not hasPet then
    if scene then scene:Hide() end
    if statScroll then statScroll:Hide() end
    flat = {}
    hideAllStatWidgets()
    if noPetLabel then noPetLabel:Show() end
    -- DOWNPORT/REPORT: keep the sidebar pet stats in sync (they read "--" with no pet).
    if CP._sidebarPetMode and CP.RefreshSidebar then pcall(CP.RefreshSidebar) end
    return
  end
  if noPetLabel then noPetLabel:Hide() end
  scene:Show()
  if statScroll then statScroll:Hide() end   -- DOWNPORT/REPORT: in-pane stats retired; sidebar owns them

  -- Model. Re-frame only when the pet actually changes (refresh fires often for happiness/xp; a
  -- per-refresh SetUnit would reset any manual zoom every tick).
  if model then
    local guid = UnitGUID and UnitGUID("pet")
    if model._nePetGUID ~= guid then
      model._nePetGUID = guid
      if model.SetUnit then pcall(model.SetUnit, model, "pet") end
      -- DOWNPORT/REPORT: do NOT call SetCamera(0) — camera index 0 is the creature's PORTRAIT camera
      -- (zoomed to the head), which made the pet "far too zoomed in". SetUnit alone gives the full-body
      -- fit; clear any leftover portrait-zoom / depth so the resting framing is the whole pet.
      if model.SetPortraitZoom then pcall(model.SetPortraitZoom, model, 0) end
      if model.SetPosition then pcall(model.SetPosition, model, 0, 0, 0) end
      if model.SetCamDistanceScale then pcall(model.SetCamDistanceScale, model, 1) end
    end
  end

  -- Name.
  local name = UnitName("pet")
  if name and name ~= (UNKNOWNOBJECT or "Unknown") then nameText:SetText(name) end

  -- Happiness (hunter pets only).
  local h = safe(GetPetHappiness)
  if h and HAPPINESS_TC[h] then
    happy.tex:SetTexCoord(HAPPINESS_TC[h][1], HAPPINESS_TC[h][2], 0, 0.359375)
    happy.tooltip = _G["PET_HAPPINESS" .. h] or L("HAPPINESS", "Happiness")
    happy:Show()
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", happy, "RIGHT", 6, 0)
  else
    happy:Hide()
    nameText:ClearAllPoints()
    nameText:SetPoint("LEFT", info, "LEFT", 0, 0)
  end

  -- Level + family.
  local family = safe(UnitCreatureFamily, "pet")
  local lvl = UnitLevel("pet") or 0
  if family then
    levelText:SetText(string.format(L("UNIT_LEVEL_TEMPLATE", "Level %d"), lvl) .. " " .. family)
  else
    levelText:SetText(string.format(L("UNIT_LEVEL_TEMPLATE", "Level %d"), lvl))
  end

  -- Loyalty / diet (hunter only).
  local loyalty = safe(GetPetLoyalty)
  loyaltyText:SetText(loyalty or "")
  local foods = { safe(GetPetFoodTypes) }
  if foods[1] and BuildListString then
    dietText:SetText((L("PET_DIET_TEMPLATE", "Diet: %s")):format(BuildListString(unpack(foods))))
  else
    dietText:SetText("")
  end

  -- XP bar (warlock minions report 0/0 → hide).
  local cur, nextXP = safe(GetPetExperience)
  cur, nextXP = cur or 0, nextXP or 0
  if nextXP > 0 then
    xpBar:Show()
    xpBar:SetMinMaxValues(0, nextXP)
    xpBar:SetValue(cur)
    xpBar._text:SetText(string.format("%s %d / %d (%d%%)", L("XP", "XP"), cur, nextXP,
      math.floor(cur / nextXP * 100)))
  else
    xpBar:Hide()
  end

  -- Stats now render in the InsetRight sidebar (CP.ExpandPetSidebar). Refresh it when in pet mode.
  if CP._sidebarPetMode and CP.RefreshSidebar then pcall(CP.RefreshSidebar) end
end
CP.RefreshPet = function() pcall(refresh) end

local function build()
  local host = getPane()
  if not host then log("Pet pane host missing — cannot build"); return false end
  if scene then return true end

  buildScene(host)
  -- DOWNPORT/REPORT: pet stats moved to the InsetRight sidebar (CP.ExpandPetSidebar). The in-pane
  -- FauxScrollFrame stats list is no longer built here (it would duplicate the sidebar's pet stats).
  -- buildStatsList(host) intentionally not called.

  noPetLabel = host:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  noPetLabel:SetPoint("CENTER", host, "CENTER", 0, 0)
  noPetLabel:SetText(L("NO_PET", "You do not have a pet."))
  noPetLabel:Hide()
  return true
end

local function init()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  if not build() then return end
  pcall(refresh)
  local host = getPane()
  if host and not host._nePetShowHooked then
    host._nePetShowHooked = true
    host:HookScript("OnShow", function() recomputeVisible(); pcall(refresh) end)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("UNIT_PET")
boot:RegisterEvent("PET_BAR_UPDATE")
boot:RegisterEvent("UNIT_HAPPINESS")
boot:RegisterEvent("UNIT_NAME_UPDATE")
boot:RegisterEvent("UNIT_PET_EXPERIENCE")
boot:SetScript("OnEvent", function(_, event, arg1)
  if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
    if C_Timer and C_Timer.After then C_Timer.After(0, init) else init() end
  else
    -- Unit events: only react to player/pet.
    if event == "UNIT_PET" or event == "UNIT_HAPPINESS" or event == "UNIT_NAME_UPDATE"
       or event == "UNIT_PET_EXPERIENCE" then
      if arg1 and arg1 ~= "player" and arg1 ~= "pet" then return end
    end
    CP.RefreshPet()
  end
end)
