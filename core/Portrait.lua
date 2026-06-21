-- DragonUI_NewEra/core/Portrait.lua — shared masked portrait cutout for PortraitFrameTemplate
-- panels. Drops a square portrait texture into the nineslice corner cutout.
--
-- DOWNPORT: NewEra Core/Portrait.lua → 3.3.5a. NewEra circular-clipped the portrait with
-- Frame:CreateMaskTexture + Texture:AddMaskTexture (retail/Era API). Neither exists on 3.3.5a
-- (and SetMask doesn't exist either — see project memory). So the circular mask is FEATURE-GATED
-- and simply no-ops on 3.3.5a: the portrait renders as a square cutout framed by the metal
-- corner's own circular ring (which already reads as round). For player/unit portraits, callers
-- should use the global SetPortraitTexture(tex, unit) — natively circular on 3.3.5a (memory:
-- reference_3355_circular_portrait) — and NOT SetTexCoord-zoom it.
--
-- §2 CONTRACT: NE.portrait.* surface preserved.
--
-- USAGE
--   NE.portrait.ApplyCutout(CharacterFramePortrait, CharacterFrame)
--
-- opts (all optional): size(62), anchor({"TOPLEFT",-5,7}), layer("ARTWORK"), sublevel,
--   mask(true — no-op on 3.3.5a), maskInset({2,0,-2,4}).
-- Idempotent (tex._neCutout). The mask, if created, is exposed as tex._neMask.

local NE = DragonUI_NewEra
NE.portrait = NE.portrait or {}

local MASK_TEX = "Interface\\CharacterFrame\\TempPortraitAlphaMask"

function NE.portrait.ApplyCutout(tex, parent, opts)
  if not tex or not parent then return end
  if tex._neCutout then return end
  opts = opts or {}

  -- DOWNPORT: NewEra's size 62 / y 7 assumed a circular MASK clipping the portrait to the ring.
  -- On 3.3.5a the mask is feature-gated off, so the raw (natively-circular) portrait was a touch
  -- large and low — the chin poked below the metal ring. Shrink 2px and lift 3px to seat it inside.
  local size   = opts.size  or 60
  local layer  = opts.layer or "ARTWORK"
  local anchor = opts.anchor or { "TOPLEFT", -5, 8 }
  local point  = anchor[1]
  local mi     = opts.maskInset or { 2, 0, -2, 4 }

  tex:ClearAllPoints()
  tex:SetPoint(point, parent, point, anchor[2], anchor[3])
  tex:SetSize(size, size)
  tex:SetDrawLayer(layer, opts.sublevel)

  -- DOWNPORT: circular mask via CreateMaskTexture/AddMaskTexture is retail-only. Feature-gate it
  -- so it lights up IF a compat shim ever provides those methods; otherwise the portrait is a
  -- square cutout inside the metal ring (acceptable on 3.3.5a — the ring reads as round).
  -- DOWNPORT: the method-existence guard is NOT enough — this 3.3.5a client EXPOSES
  -- CreateMaskTexture but it RETURNS NIL (masks are non-functional here). Indexing that nil
  -- aborted the whole chrome Apply (Portrait.lua:50). Guard the actual return value: if the mask
  -- didn't materialise, skip it (the native-circular portrait + metal ring already read as round).
  if opts.mask ~= false and tex.AddMaskTexture and parent.CreateMaskTexture and not tex._neMask then
    local ok, mask = pcall(parent.CreateMaskTexture, parent)
    if ok and mask and mask.SetTexture then
      mask:SetTexture(MASK_TEX, "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
      mask:SetPoint("TOPLEFT",     tex, "TOPLEFT",     mi[1], mi[2])
      mask:SetPoint("BOTTOMRIGHT", tex, "BOTTOMRIGHT", mi[3], mi[4])
      tex:AddMaskTexture(mask)
      tex._neMask = mask
    end
  end

  tex._neCutout = true
end

-- Convenience: set a unit portrait into the cutout the 3.3.5a-native (circular) way.
-- DOWNPORT: new helper — wraps the global SetPortraitTexture (natively circular on 3.3.5a) so
-- panels don't reach for the missing mask API. Falls back to a plain texture path/FDID.
function NE.portrait.SetUnit(tex, parent, unit, opts)
  if not (tex and parent) then return end
  NE.portrait.ApplyCutout(tex, parent, opts)
  if unit and SetPortraitTexture then
    pcall(SetPortraitTexture, tex, unit)
  end
end
