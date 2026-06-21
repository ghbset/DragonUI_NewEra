-- DragonUI_NewEra/core/ItemButton.lua — shared item-rarity (quality) border coloring.
--
-- DOWNPORT: NewEra Core/ItemButton.lua → 3.3.5a. NewEra resurrected retail's neutered
-- SetItemButtonQuality via a post-hook re-coloring the IconBorder texture. On 3.3.5a:
--   * SetItemButtonQuality EXISTS as a global and (unlike Era) already colours item buttons that
--     have a named $parentIconBorder/.IconBorder — but many 3.3.5a item buttons predate IconBorder,
--     so the post-hook is still the robust way to guarantee a colored border everywhere.
--   * BAG_ITEM_QUALITY_COLORS / ITEM_QUALITY_COLORS exist on 3.3.5a (Constants), so the colour
--     policy ports unchanged.
--   * Enum.ItemQuality may not exist on 3.3.5a → the Poor constant is feature-gated to 0.
--   * The shipped WhiteIconFrame BLP path is repointed to DragonUI_NewEra's Textures dir; if the
--     Asset agent hasn't shipped it, we fall back to the 3.3.5a client path so the border still
--     paints.
--
-- §2 CONTRACT: exposed as NE.itembutton.* (and NE.itembtn.* kept for NewEra-name parity).

local NE = DragonUI_NewEra
NE.itembutton = NE.itembutton or {}
NE.itembtn = NE.itembutton           -- DOWNPORT: NewEra used NE.itembtn; alias to contract name
local M = NE.itembutton

-- DOWNPORT: prefer a shipped modern WhiteIconFrame; fall back to the 3.3.5a client asset.
local WHITE_FRAME = [[Interface\AddOns\DragonUI_NewEra\Textures\Common\651080-whiteiconframe.blp]]
local WHITE_FRAME_FALLBACK = [[Interface\Common\WhiteIconFrame]]

local function colorFor(quality)
  if not quality then return nil end
  return BAG_ITEM_QUALITY_COLORS and BAG_ITEM_QUALITY_COLORS[quality]
end

-- Resolve the IconBorder texture once and cache whether the shipped art is usable.
local function borderTex(button)
  local b = button.IconBorder
  if not b and button.GetName and button:GetName() then
    b = _G[button:GetName() .. "IconBorder"]
  end
  return b
end

-- Apply the quality border to one button's IconBorder.
function M.ApplyQuality(button, quality)
  if not button then return end
  local b = borderTex(button)
  if not b then return end

  local c = colorFor(quality)
  if c then
    -- DOWNPORT: try the shipped modern frame; SetTexture returns false on a missing path, so fall
    -- back to the 3.3.5a client WhiteIconFrame.
    if b:SetTexture(WHITE_FRAME) == false then b:SetTexture(WHITE_FRAME_FALLBACK) end
    b:SetVertexColor(c.r, c.g, c.b)
    b:Show()
  else
    b:Hide()
  end
end

-- Resurrect/augment the global. 3.3.5a's Blizzard FrameXML defines SetItemButtonQuality at parse
-- time, so it exists when this addon loads; the post-hook runs after the native body.
if SetItemButtonQuality then
  hooksecurefunc("SetItemButtonQuality", function(button, quality)
    M.ApplyQuality(button, quality)
  end)
end

-- Quality TEXT coloring — reads ITEM_QUALITY_COLORS (the brighter table with .hex).
function M.TextColor(quality)
  return quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] or nil
end

-- Wrap an item name in its quality's hex color escape.
function M.WrapTextByQuality(name, quality)
  local c = M.TextColor(quality)
  if c and c.hex then return c.hex .. (name or "") .. "|r" end
  return name or ""
end
