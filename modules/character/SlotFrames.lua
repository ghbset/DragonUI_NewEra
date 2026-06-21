-- DragonUI_NewEra/modules/character/SlotFrames.lua — decorative metal frame borders around each of
-- the 19 PaperDoll equipment slot buttons. Ported faithfully from NewEra/CharacterPanel/SlotFrames.lua.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): the slot buttons have ALREADY been reparented into
-- NE.charpanel.Inset and positioned at the vanilla anchors by CharacterPanel.lua/InsetFrames.lua.
-- This file ONLY adds the decorative Char-Paperdoll-Parts metal frame texture around each slot — it
-- does NOT (re)position the slots; that is the foundation's job. (NewEra's applySlotColumnAnchors did
-- the anchoring too because it owned both; here the foundation owns anchoring, so we drop it.)
--
-- Each frame is a BACKGROUND/-1 texture drawn behind the slot's icon, so it borders the icon without
-- occluding it (the icon + IconBorder live at higher sublevels). Three slices from Char-Paperdoll-
-- Parts (FDID 410248): LEFT 49x44 (left column), RIGHT 50x44 (right column), BOTTOM 42x53 (weapon
-- row). Plus the two small gap-fillers that flank MainHand/SecondaryHand.
--
-- GRACEFUL DEGRADATION (CONTRACT §B): every step pcall-guarded; if the art FDID isn't shipped the
-- frame simply renders blank (the slot still works). Never errors out of boot.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE = "character"

local function log(msg) if CP._log then CP._log(msg) elseif NE.Log then NE.Log("CHARPANEL", msg) end end

-- ----------------------------------------------------------------------------
-- Art source. Prefer the shipped local BLP (Assets.lua registered FDID 410248); fall back to the
-- canonical 3.3.5a client path so the metal frame still renders if the local copy is missing.
-- DOWNPORT: NE.tex.SetAtlas can't help here — these are raw texcoord slices, not registered atlases.
-- ----------------------------------------------------------------------------
local CHAR_PARTS_BLP = (NE.tex and NE.tex.localFiles and NE.tex.localFiles[410248])
                       or "Interface\\CharacterFrame\\Char-Paperdoll-Parts"

-- Verbatim slices from retail/NewEra CharacterFrame.xml (see NewEra/CharacterPanel/SlotFrames.lua).
local LEFT_SLICE   = { w = 49, h = 44, left = 0.20703125, right = 0.39843750, top = 0.59375, bottom = 0.93750 }
local RIGHT_SLICE  = { w = 50, h = 44, left = 0.00390625, right = 0.19921875, top = 0.59375, bottom = 0.93750 }
local BOTTOM_SLICE = { w = 42, h = 53, left = 0.67187500, right = 0.83593750, top = 0.00781, bottom = 0.42188 }

-- Char-Slot-Bottom-Left / Char-Slot-Bottom-Right — decorative gap-fillers flanking the weapon row.
local BOTTOM_LEFT_GAP  = { w = 6, h = 54, left = 0.70703125, right = 0.73046875, top = 0.43750, bottom = 0.85938 }
local BOTTOM_RIGHT_GAP = { w = 7, h = 54, left = 0.67187500, right = 0.69921875, top = 0.43750, bottom = 0.85938 }

-- Slot -> { slice, anchorPoint, x, y } matching retail's PaperDollItemSlotButton{Left,Right,Bottom}
-- Template inheritance. Left frame offset TOPLEFT(-4,0); right TOPRIGHT(+4,0); bottom TOPLEFT(-4,+8).
local SLOT_SIDES = {
  -- Left column
  CharacterHeadSlot     = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  CharacterNeckSlot     = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  CharacterShoulderSlot = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  CharacterBackSlot     = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  CharacterChestSlot    = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  CharacterShirtSlot    = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  CharacterTabardSlot   = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  CharacterWristSlot    = { slice = LEFT_SLICE,   anchorPoint = "TOPLEFT",  x = -4, y = 0 },
  -- Right column
  CharacterHandsSlot    = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  CharacterWaistSlot    = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  CharacterLegsSlot     = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  CharacterFeetSlot     = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  CharacterFinger0Slot  = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  CharacterFinger1Slot  = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  CharacterTrinket0Slot = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  CharacterTrinket1Slot = { slice = RIGHT_SLICE,  anchorPoint = "TOPRIGHT", x =  4, y = 0 },
  -- Bottom weapon row
  CharacterMainHandSlot      = { slice = BOTTOM_SLICE, anchorPoint = "TOPLEFT", x = -4, y = 8 },
  CharacterSecondaryHandSlot = { slice = BOTTOM_SLICE, anchorPoint = "TOPLEFT", x = -4, y = 8 },
  CharacterRangedSlot        = { slice = BOTTOM_SLICE, anchorPoint = "TOPLEFT", x = -4, y = 8 },
}

local function applyFrameToSlot(slotName, spec)
  local slot = _G[slotName]
  if not slot or slot._neSlotFrameDone then return end

  -- BACKGROUND/-1: behind the slot's icon + IconBorder so the metal frame surrounds the icon but
  -- never hides it. DOWNPORT: the reparented slot inherits OUR Inset frame level; the texture is a
  -- CHILD of the slot so it follows the slot's level — no extra level juggling needed.
  local frame = slot:CreateTexture(nil, "BACKGROUND", nil, -1)
  frame:SetTexture(CHAR_PARTS_BLP)
  frame:SetTexCoord(spec.slice.left, spec.slice.right, spec.slice.top, spec.slice.bottom)
  frame:SetSize(spec.slice.w, spec.slice.h)
  frame:SetPoint(spec.anchorPoint, slot, spec.anchorPoint, spec.x, spec.y)
  slot._neSlotFrame = frame
  slot._neSlotFrameDone = true
  -- DOWNPORT/REPORT: register into the shared paperdoll-decor list so CP.ShowPaperDoll can hide the
  -- metal frame on non-Character tabs. (It IS a child of the slot button, so it follows the slot's
  -- Hide too — registering it here is belt-and-suspenders + keeps the contract explicit.)
  CP._paperdollDecor = CP._paperdollDecor or {}
  table.insert(CP._paperdollDecor, frame)
end

local function applyAll()
  for name, spec in pairs(SLOT_SIDES) do
    local ok, err = pcall(applyFrameToSlot, name, spec)
    if not ok then log("slotframe " .. name .. " failed: " .. tostring(err)) end
  end
end

-- The two weapon-row gap-fillers. Anchored to the bottom slots' frame textures (built above), so this
-- must run AFTER applyAll. Idempotent.
local function applyGapFillers()
  local mh = _G.CharacterMainHandSlot
  if mh and mh._neSlotFrame and not mh._neBottomLeftGap then
    local gap = mh:CreateTexture(nil, "BACKGROUND", nil, -1)
    gap:SetTexture(CHAR_PARTS_BLP)
    gap:SetTexCoord(BOTTOM_LEFT_GAP.left, BOTTOM_LEFT_GAP.right, BOTTOM_LEFT_GAP.top, BOTTOM_LEFT_GAP.bottom)
    gap:SetSize(BOTTOM_LEFT_GAP.w, BOTTOM_LEFT_GAP.h)
    gap:SetPoint("TOPRIGHT", mh._neSlotFrame, "TOPLEFT", 0, 0)
    mh._neBottomLeftGap = gap
    -- DOWNPORT/REPORT: register the gap-filler into the paperdoll-decor list.
    CP._paperdollDecor = CP._paperdollDecor or {}
    table.insert(CP._paperdollDecor, gap)
  end

  local sh = _G.CharacterSecondaryHandSlot
  if sh and sh._neSlotFrame and not sh._neBottomRightGap then
    local gap = sh:CreateTexture(nil, "BACKGROUND", nil, -1)
    gap:SetTexture(CHAR_PARTS_BLP)
    gap:SetTexCoord(BOTTOM_RIGHT_GAP.left, BOTTOM_RIGHT_GAP.right, BOTTOM_RIGHT_GAP.top, BOTTOM_RIGHT_GAP.bottom)
    gap:SetSize(BOTTOM_RIGHT_GAP.w, BOTTOM_RIGHT_GAP.h)
    gap:SetPoint("TOPLEFT", sh._neSlotFrame, "TOPRIGHT", 0, 0)
    sh._neBottomRightGap = gap
    -- DOWNPORT/REPORT: register the gap-filler into the paperdoll-decor list.
    CP._paperdollDecor = CP._paperdollDecor or {}
    table.insert(CP._paperdollDecor, gap)
  end
end

local function applySlotFrames()
  applyAll()
  pcall(applyGapFillers)
end

CP.ApplySlotFrames = applySlotFrames

-- Boot. DOWNPORT: family gate is NE.modules.IsEnabled("character") (the foundation's module id), not
-- NewEra's IsBooted("CharacterPanel"). Run on login + entering-world (re-asserts after late loads).
local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled(MODULE) then return end
  local ok, err = pcall(applySlotFrames)
  if not ok then log("SlotFrames boot failed: " .. tostring(err)) end
end)
