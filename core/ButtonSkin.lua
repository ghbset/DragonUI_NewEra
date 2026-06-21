-- DragonUI_NewEra/core/ButtonSkin.lua — shared modern button skin (NE.buttonskin.Skin).
--
-- DOWNPORT: NewEra Core/ButtonSkin.lua → 3.3.5a. Reskins a Button to retail's
-- BigRedThreeSliceButton (the red 3-slice ESC-menu/dialog button). NewEra called the NATIVE
-- Texture:SetAtlas (a retail/Era method) and read atlas dimensions via C_Texture.GetAtlasInfo.
-- On 3.3.5a there is no Texture:SetAtlas, so every piece-atlas swap routes through NE.tex.SetAtlas
-- (our coord registry), and dimensions come from NE.tex._atlasEntry. C_Texture.GetAtlasInfo is
-- the compat shim — present, but only answers for atlases the Asset agent registered, so the
-- whole reskin is FAIL-SAFE: missing 128-RedButton art → native button art kept (returns false).
--
-- §2 CONTRACT: exposed as NE.buttonskin.* (and NE.button.* kept for NewEra-name parity).
-- Taint-safe: adds BACKGROUND textures + hooks visual-state scripts only.

local NE = DragonUI_NewEra
NE.buttonskin = NE.buttonskin or {}
NE.button = NE.buttonskin            -- DOWNPORT: NewEra used NE.button; alias to the contract name

local ATLAS = "128-RedButton"

local function pieceNames(postfix)
  return ATLAS .. "-Left" .. postfix, "_" .. ATLAS .. "-Center" .. postfix, ATLAS .. "-Right" .. postfix
end

-- Faithful port of ThreeSliceButtonMixin:UpdateScale.
local function updateScale(btn)
  local d = btn._neThreeSlice
  if not d or not d.leftInfo or not d.rightInfo then return end
  local buttonH, buttonW = btn:GetHeight(), btn:GetWidth()
  if buttonH <= 0 or d.leftInfo.height <= 0 then return end
  local scale = buttonH / d.leftInfo.height
  d.Left:SetScale(scale); d.Right:SetScale(scale)

  local leftW, rightW = d.leftInfo.width * scale, d.rightInfo.width * scale
  local both = leftW + rightW
  if both > buttonW then
    local extra = both - buttonW
    local newLeftW, newRightW = leftW, rightW
    if (leftW - extra) > rightW then
      newLeftW = leftW - extra
    elseif (rightW - extra) > leftW then
      newRightW = rightW - extra
    else
      if leftW ~= rightW then
        local uneven = math.abs(leftW - rightW)
        extra = extra - uneven
        newLeftW = math.min(leftW, rightW); newRightW = newLeftW
      end
      local half = extra / 2
      newLeftW = newLeftW - half; newRightW = newRightW - half
    end
    -- DOWNPORT: the texcoord trim composes the atlas sub-rect AFTER NE.tex.SetAtlas has set it.
    -- We re-resolve the atlas entry to compose the trim within the element's own rect.
    local le = NE.tex._atlasEntry(pieceNames(d.postfix or ""))
    d.Left:SetWidth(newLeftW / scale)
    d.Right:SetWidth(newRightW / scale)
    if le then
      d.Left:SetTexCoord(le.left, le.left + (le.right - le.left) * (newLeftW / leftW), le.top, le.bottom)
    end
  else
    NE.tex.SetAtlas(d.Left, pieceNames(d.postfix or ""), false)
    d.Left:SetWidth(d.leftInfo.width)
    d.Right:SetWidth(d.rightInfo.width)
  end
end

-- Faithful port of ThreeSliceButtonMixin:UpdateButton — swap the 3 atlases per state.
local function updateButton(btn, state)
  local d = btn._neThreeSlice
  if not d then return end
  state = state or (btn.GetButtonState and btn:GetButtonState()) or "NORMAL"
  if btn.IsEnabled and not btn:IsEnabled() then state = "DISABLED" end
  local postfix = (state == "DISABLED" and "-Disabled") or (state == "PUSHED" and "-Pressed") or ""
  d.postfix = postfix
  local l, c, r = pieceNames(postfix)
  -- DOWNPORT: native SetAtlas → NE.tex.SetAtlas.
  NE.tex.SetAtlas(d.Left,   l, true)
  NE.tex.SetAtlas(d.Center, c)
  NE.tex.SetAtlas(d.Right,  r, true)
  updateScale(btn)
end

-- Hide the button's native art so the 3-slice shows through.
local function hideNativeArt(btn)
  local name = btn.GetName and btn:GetName()
  for _, key in ipairs({ "Left", "Middle", "Right" }) do
    local t = btn[key] or (name and _G[name .. key])
    if t and t.SetTexture then t:SetTexture(nil); if t.Hide then t:Hide() end end
  end
  for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
    local t = btn[getter] and btn[getter](btn)
    if t and t.SetTexture then t:SetTexture(nil); if t.Hide then t:Hide() end end
  end
  local h = btn.GetHighlightTexture and btn:GetHighlightTexture()
  if h and h.SetTexture then h:SetTexture(nil) end
end

-- Reskin `btn`. Idempotent. opts.atlas overrides the family. Returns true on success.
function NE.buttonskin.Skin(btn, opts)
  if not btn or btn._neThreeSlice then return btn and btn._neThreeSlice ~= nil end
  -- DOWNPORT: prefer our registry (NE.tex._atlasEntry) for dimensions; fall back to the
  -- C_Texture shim. If neither knows the atlas, fail-safe (native art kept).
  local leftInfo  = NE.tex._atlasEntry(ATLAS .. "-Left")
  local rightInfo = NE.tex._atlasEntry(ATLAS .. "-Right")
  if not (leftInfo and rightInfo) and C_Texture and C_Texture.GetAtlasInfo then
    leftInfo  = leftInfo  or C_Texture.GetAtlasInfo(ATLAS .. "-Left")
    rightInfo = rightInfo or C_Texture.GetAtlasInfo(ATLAS .. "-Right")
  end
  if not (leftInfo and rightInfo and leftInfo.width and rightInfo.width) then return false end

  hideNativeArt(btn)

  local d = { leftInfo = leftInfo, rightInfo = rightInfo }
  d.Left = btn:CreateTexture(nil, "BACKGROUND")
  d.Left:SetPoint("TOPLEFT")
  d.Right = btn:CreateTexture(nil, "BACKGROUND")
  d.Right:SetPoint("TOPRIGHT")
  d.Center = btn:CreateTexture(nil, "BACKGROUND")
  d.Center:SetHorizTile(true)
  d.Center:SetPoint("TOPLEFT",     d.Left,  "TOPRIGHT")
  d.Center:SetPoint("BOTTOMRIGHT", d.Right, "BOTTOMLEFT")
  btn._neThreeSlice = d

  -- Highlight: a 3-slice matching the body, shown on hover.
  local hi = NE.tex._atlasEntry(ATLAS .. "-Highlight")
  if hi and hi.file then
    local hiFile = NE.tex.localFiles[hi.file] or hi.file
    local L, R = hi.left or 0, hi.right or 1
    local T, B = hi.top or 0, hi.bottom or 1
    local span  = R - L
    local lFrac = (leftInfo.width  / (hi.width or 441)) * span
    local rFrac = (rightInfo.width / (hi.width or 441)) * span
    local function hlPiece(over, x0, x1)
      local t = btn:CreateTexture(nil, "ARTWORK", nil, 2)
      t:SetTexture(hiFile)
      t:SetTexCoord(x0, x1, T, B)
      t:SetAllPoints(over)
      t:SetBlendMode("ADD")
      t:Hide()
      return t
    end
    d.hl = {
      hlPiece(d.Left,   L,         L + lFrac),
      hlPiece(d.Center, L + lFrac, R - rFrac),
      hlPiece(d.Right,  R - rFrac, R),
    }
    btn:HookScript("OnEnter", function() for _, t in ipairs(d.hl) do t:Show() end end)
    btn:HookScript("OnLeave", function() for _, t in ipairs(d.hl) do t:Hide() end end)
  end

  updateButton(btn, "NORMAL")

  btn:HookScript("OnMouseDown",   function(self) updateButton(self, "PUSHED") end)
  btn:HookScript("OnMouseUp",     function(self) updateButton(self, "NORMAL") end)
  btn:HookScript("OnEnable",      function(self) updateButton(self) end)
  btn:HookScript("OnDisable",     function(self) updateButton(self) end)
  btn:HookScript("OnSizeChanged", function(self) updateScale(self) end)
  return true
end
