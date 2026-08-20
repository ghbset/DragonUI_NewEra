-- DragonUI_NewEra/modules/merchant/BuybackUndo.lua — retail's buyback undo arrow.
--
-- DOWNPORT of NewEra/MerchantFrame/BuybackUndo.lua, unchanged in substance. Retail nests an
-- UndoFrame inside the merchant tab's buyback slot with a `common-icon-undo` arrow at CENTER,
-- desaturated while GetNumBuybackItems() == 0. It is the "undo your last sale" affordance, and the
-- only cue that the slot beside the vendor grid is clickable at all.
--
-- The one 3.3.5a change is where the art comes from: modules/merchant/Assets.lua points the
-- common-buttons-icons sheet at DragonUI's shipped copy rather than duplicating an 8 MB BLP. If that
-- resolve ever fails, NE.tex.SetAtlas reports the miss and this file leaves the slot alone rather
-- than drawing a blank square over it.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.merchant = NE.merchant or {}
local Merch = NE.merchant

local arrowTex

local function refreshDesaturation()
  if not arrowTex then return end
  SetDesaturation(arrowTex, ((GetNumBuybackItems and GetNumBuybackItems()) or 0) == 0)
end

function Merch.BuildBuybackUndo()
  local itemBtn = _G.MerchantBuyBackItemItemButton
  if not itemBtn or itemBtn._neUndoBuilt then return end

  local undo = CreateFrame("Frame", nil, itemBtn)
  undo:SetAllPoints(itemBtn)
  undo:SetFrameLevel((itemBtn:GetFrameLevel() or 0) + 2)

  local tex = undo:CreateTexture(nil, "ARTWORK")
  if not NE.tex.SetAtlas(tex, "common-icon-undo", false) then
    undo:Hide()
    return
  end
  tex:SetSize(20, 20)
  tex:SetPoint("CENTER", 0, -1)

  arrowTex = tex
  undo.Arrow = tex
  itemBtn.UndoFrame = undo
  itemBtn._neUndoBuilt = true

  refreshDesaturation()

  -- Refresh on every merchant update — the same trigger retail uses (its buyback ItemButton's
  -- OnEvent handles MERCHANT_UPDATE).
  if _G.MerchantFrame_Update then
    hooksecurefunc("MerchantFrame_Update", refreshDesaturation)
  end
end
