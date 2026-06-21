-- DragonUI_NewEra/core/Texture.lua — the canonical atlas/texture API for the addon.
--
-- DOWNPORT: NewEra Core/Texture.lua → 3.3.5a. NewEra resolved retail atlas nicknames through a
-- GENERATED global table `NE_ATLAS` (built from wago.tools CSV) + per-FDID local BLP copies
-- (`NE.tex.localFiles`). On 3.3.5a we don't ship that whole generated table — instead, per the
-- ARCHITECT DECISION (CONTRACTS §2/§3): atlas COORDINATES come from coord tables that THIS Core
-- agent owns (registered here + seeded in NineSliceLayouts.lua), the Asset agent supplies the
-- fdid→BLP path map (Textures/Assets.lua via NE.tex.RegisterLocal), and we set texcoords
-- manually (the DragonUI Atlas.lua pattern). We do NOT use C_Texture.RegisterAtlas — the
-- C_Texture compat shim is only a fallback for direct atlas-name lookups NewEra makes.
--
-- TWO resolution registries:
--   NE.tex.localFiles[fdid]  = "Interface\\AddOns\\...blp"   (Asset agent: RegisterLocal)
--   NE.tex.atlases[name]     = { file=fdid, left,right,top,bottom, width, height }  (Core: RegisterAtlas)
--
-- PUBLIC §2 CONTRACT:
--   NE.tex.RegisterLocal(fdid, path)        -- fdid → BLP path
--   NE.tex.Set(texture, fdidOrName[, ...])  -- THE unified setter (fdid OR atlas name)
-- Plus NewEra's preserved surface: NE.tex.SetAtlas / GetAtlasRect / HasAtlas / AtlasMarkup / …

local NE = DragonUI_NewEra
NE.tex = NE.tex or {}

-- FDID -> addon-relative texture path. Populated by Textures/Assets.lua (Asset agent).
NE.tex.localFiles = NE.tex.localFiles or {}

-- Atlas-name -> coord entry { file=fdid, left,right,top,bottom, width, height }.
-- DOWNPORT: replaces NewEra's generated global NE_ATLAS. Owned by Core; seeded from the coord
-- tables in NineSliceLayouts.lua + Tabs.lua + ScrollbarReskin.lua via RegisterAtlas.
NE.tex.atlases = NE.tex.atlases or {}

function NE.tex.RegisterLocal(fdid, path)
  NE.tex.localFiles[fdid] = path
end

-- Local BLP path registered for an FDID (RegisterLocal), or nil.
function NE.tex.Local(fdid)
  return NE.tex.localFiles[fdid]
end

-- Register one atlas coord entry. `info` = { file=fdid, left,right,top,bottom[, width, height] }.
-- DOWNPORT: this is the seam the architect chose over C_Texture.RegisterAtlas.
function NE.tex.RegisterAtlas(name, info)
  if not (name and info) then return end
  NE.tex.atlases[name:lower()] = info
end

-- Bulk register: a table of { ["atlas-name"] = {file=,left=,...}, ... }. Used by the coord
-- tables in NineSliceLayouts.lua to load a whole family at once.
function NE.tex.RegisterAtlases(tbl)
  if type(tbl) ~= "table" then return end
  for name, info in pairs(tbl) do
    NE.tex.atlases[name:lower()] = info
  end
end

-- Resolve an atlas-name entry. Tries (1) our owned registry, (2) the generated global NE_ATLAS
-- if some other layer ever ships it, (3) the C_Texture compat shim (direct atlas-name lookup
-- fallback, per the architect decision). Returns the entry table or nil.
-- DOWNPORT: NewEra read NE_ATLAS directly; we layer our registry on top + add the shim fallback.
local function atlasEntry(name)
  if not name then return nil end
  local key = name:lower()
  local e = NE.tex.atlases[key]
  if e then return e end
  if _G.NE_ATLAS then
    e = _G.NE_ATLAS[key]
    if e then return e end
  end
  -- Fallback: the C_Texture compat shim (only answers atlases registered with it).
  if C_Texture and C_Texture.GetAtlasInfo then
    local info = C_Texture.GetAtlasInfo(name)
    if info then
      -- Normalize the C_Texture shape (leftTexCoord/...) → our entry shape.
      return {
        file   = info.file or info.fileDataID,
        left   = info.leftTexCoord   or 0,
        right  = info.rightTexCoord  or 1,
        top    = info.topTexCoord    or 0,
        bottom = info.bottomTexCoord or 1,
        width  = info.width,
        height = info.height,
      }
    end
  end
  return nil
end
NE.tex._atlasEntry = atlasEntry   -- exposed for diagnostics / sibling modules

-- Resolve the BLP source for an atlas entry: prefer the shipped local copy, else the raw FDID.
local function entrySource(entry)
  return NE.tex.localFiles[entry.file] or entry.file
end

-- Resolved atlas rect (texcoords) for a nickname → left,right,top,bottom, or the full 0,1,0,1
-- sheet if unknown.
function NE.tex.GetAtlasRect(name)
  local entry = atlasEntry(name)
  if not entry then return 0, 1, 0, 1 end
  return entry.left, entry.right, entry.top, entry.bottom
end

-- Convenience: true if the atlas is known.
function NE.tex.HasAtlas(name)
  return atlasEntry(name) ~= nil
end

-- Resolve a dotted key path ("a.b.c") to root.a.b.c, or nil if any hop is missing.
function NE.tex.ResolveKeyPath(root, path)
  local node = root
  for key in path:gmatch("[^.]+") do
    node = node and node[key]
    if not node then return nil end
  end
  return node
end

-- Apply an atlas nickname to a texture. Returns true on success, false otherwise.
-- DOWNPORT: NewEra forced filterMode "LINEAR"/"TRILINEAR" via a 4-arg SetTexture. 3.3.5a's
-- Texture:SetTexture does NOT accept a filterMode arg (4th arg is ignored / can error on some
-- builds), so we set the texture with the legal arg count and skip the filter hint. NewEra's
-- SetTextureSliceMargins / ClearTextureSlice (retail 9-slice) also don't exist on 3.3.5a —
-- guarded by feature-detect, so they simply no-op (plain SetTexCoord stretch, acceptable for v1).
function NE.tex.SetAtlas(tex, name, useAtlasSize, filterMode)
  if not (tex and name) then return false end
  local entry = atlasEntry(name)
  if not entry then
    if NE.Log then NE.Log("ATLAS", "MISS atlas " .. tostring(name)) end
    return false
  end
  local source = entrySource(entry)
  -- DOWNPORT: 3.3.5a's Texture:SetTexture CANNOT read a raw FileDataID integer (retail/Era-only).
  -- If the atlas's backing BLP wasn't shipped (no localFiles entry), `source` is the raw FDID —
  -- setting it yields a BLANK texture while reporting success, which silently replaces native art
  -- (e.g. blanked the stock close-button X). Report a miss so callers gracefully fall back.
  if type(source) ~= "string" then
    if NE.Log then NE.Log("ATLAS", "NO-LOCAL atlas " .. tostring(name) .. " (fdid " .. tostring(entry.file) .. " not shipped)") end
    return false
  end
  tex:SetTexture(source)                                  -- DOWNPORT: no filterMode arg on 3.3.5a
  tex:SetTexCoord(entry.left, entry.right, entry.top, entry.bottom)
  if useAtlasSize and entry.width and entry.height then
    tex:SetSize(entry.width, entry.height)
  end
  -- DOWNPORT: retail's per-atlas 9-slice (SetTextureSliceMargins) is absent on 3.3.5a; feature-
  -- gate it so the call no-ops there. NewEra's NE_ATLAS_SLICE table isn't shipped, so this never
  -- fires on 3.3.5a regardless; left in for forward-compat with the C_Texture shim.
  if tex.SetTextureSliceMargins and not (tex.GetObjectType and tex:GetObjectType() == "MaskTexture") then
    local slice = _G.NE_ATLAS_SLICE and _G.NE_ATLAS_SLICE[name:lower()]
    if slice then
      if tex.SetTextureSliceMode then tex:SetTextureSliceMode(slice.mode or 0) end
      tex:SetTextureSliceMargins(slice.l, slice.t, slice.r, slice.b)
      tex._neSliced = true
    elseif tex._neSliced then
      if tex.ClearTextureSlice then tex:ClearTextureSlice() else tex:SetTextureSliceMargins(0, 0, 0, 0) end
      tex._neSliced = nil
    end
  end
  return true
end

-- THE unified §2 setter. `key` is an FDID (number) OR an atlas nickname (string).
--   FDID:  Set(tex, 374155[, useAtlasSize])   → resolves local path (or raw fdid), full sheet.
--   name:  Set(tex, "ui-frame-metal-cornertopleft-2x"[, useAtlasSize]) → atlas coords.
-- DOWNPORT: this is the new contract entry-point NewEra didn't have (it only had SetAtlas);
-- panels in later sprints call NE.tex.Set. Returns true on success.
function NE.tex.Set(tex, key, useAtlasSize, ...)
  if not (tex and key ~= nil) then return false end
  if type(key) == "number" then
    local source = NE.tex.localFiles[key] or key
    tex:SetTexture(source)
    tex:SetTexCoord(0, 1, 0, 1)
    return true
  end
  return NE.tex.SetAtlas(tex, key, useAtlasSize, ...)
end

-- Inline-text markup for an atlas element — our CreateAtlasMarkup. Returns nil when unknown.
function NE.tex.AtlasMarkup(name, width, height)
  local entry = atlasEntry(name)
  if not entry then return nil end
  local path = NE.tex.localFiles[entry.file]
  if not path then return nil end                 -- markup can't express a bare FDID reliably
  local B = 1024
  return ("|T%s:%d:%d:0:0:%d:%d:%d:%d:%d:%d|t"):format(
    path, height or entry.height or 16, width or entry.width or 16, B, B,
    math.floor(entry.left * B + 0.5), math.floor(entry.right * B + 0.5),
    math.floor(entry.top * B + 0.5),  math.floor(entry.bottom * B + 0.5))
end

-- Same as SetAtlas but for MaskTexture — CLAMPTOBLACKADDITIVE wrap so the mask's alpha is 0
-- outside its drawn bounds.
-- DOWNPORT: 3.3.5a Texture:SetTexture supports the (file, hWrap, vWrap) 3-arg form, so the
-- wrap-mode args port; only the trailing filterMode is dropped.
function NE.tex.SetAtlasMask(maskTex, name)
  if not (maskTex and name) then return false end
  local entry = atlasEntry(name)
  if not entry then
    if NE.Log then NE.Log("ATLAS", "MISS mask atlas " .. tostring(name)) end
    return false
  end
  maskTex:SetTexture(entrySource(entry), "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
  maskTex:SetTexCoord(entry.left, entry.right, entry.top, entry.bottom)
  return true
end

-- Apply an ATLAS_MAP { [keypath] = { name=, target=, useAtlasSize= } } to resolved widgets.
function NE.tex.ApplyAtlasMap(self, map, label)
  for path, entry in pairs(map) do
    local widget = NE.tex.ResolveKeyPath(self, path)
    if widget then
      if entry.target == "bar" and widget.SetStatusBarTexture then
        NE.tex.SetAtlasOnStatusBar(widget, entry.name)
      elseif widget.GetObjectType and widget:GetObjectType() == "MaskTexture" then
        NE.tex.SetAtlasMask(widget, entry.name)
      else
        NE.tex.SetAtlas(widget, entry.name, entry.useAtlasSize)
      end
    elseif label and NE.Log then
      NE.Log("ATLAS", "MISS path " .. label .. "." .. path)
    end
  end
end

-- DOWNPORT: NewEra's SmoothBarTex used SetSnapToPixelGrid/SetTexelSnappingBias — retail-only
-- crispness tuning absent on 3.3.5a. Feature-gate each call so this is a safe no-op here.
function NE.tex.SmoothBarTex(tex)
  if not tex then return end
  if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(true) end
  if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0.3) end
end

-- StatusBar atlas overlay (NewEra fights the engine's per-SetValue texcoord recompute with a
-- custom overlay it controls). 3.3.5a StatusBars recompute texcoord the same way, so the overlay
-- approach still applies. We keep it but drop the retail-only filterMode arg on SetTexture.
local function updateAtlasOverlay(bar)
  local a = bar._neAtlas
  local overlay = bar._neOverlay
  if not (a and overlay) then return end
  local minV, maxV = bar:GetMinMaxValues()
  minV, maxV = minV or 0, maxV or 1
  local denom = (maxV ~= minV) and (maxV - minV) or 1
  local v = bar:GetValue() or minV
  local f = (v - minV) / denom
  if not f or f ~= f then f = 0 end
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  local barW = bar:GetWidth() or 0
  local barH = bar:GetHeight() or 0
  if barW <= 0 or barH <= 0 or f <= 0 then
    overlay:Hide()
  else
    overlay:Show()
    overlay:SetSize(barW * f, barH)
    local atlasW = a.right - a.left
    overlay:SetTexCoord(a.left, a.left + atlasW * f, a.top, a.bottom)
  end
  local engineTex = bar:GetStatusBarTexture()
  if engineTex then engineTex:SetAlpha(0) end
  local ovR, ovG, ovB = overlay:GetVertexColor()
  if ovR then overlay:SetVertexColor(ovR, ovG, ovB, 1) end
end
NE.tex._updateAtlasOverlay = updateAtlasOverlay

NE.tex.atlasBars = NE.tex.atlasBars or {}

local atlasUpdater
local function ensureAtlasUpdater()
  if atlasUpdater then return end
  atlasUpdater = CreateFrame("Frame")
  atlasUpdater:SetScript("OnUpdate", function()
    for bar in pairs(NE.tex.atlasBars) do
      updateAtlasOverlay(bar)
    end
  end)
end

function NE.tex.SetAtlasOnStatusBar(bar, name)
  if not (bar and name) then return false end
  local entry = atlasEntry(name)
  if not entry then
    if NE.Log then NE.Log("ATLAS", "MISS atlas " .. tostring(name)) end
    return false
  end
  local source = entrySource(entry)

  bar:SetStatusBarTexture(source)
  local engineTex = bar:GetStatusBarTexture()
  if engineTex then
    engineTex:SetAlpha(0)
    if engineTex.SetTexture then engineTex:SetTexture(source) end   -- DOWNPORT: no filterMode arg
  end

  if not bar._neOverlay then
    bar._neOverlay = bar:CreateTexture(nil, "ARTWORK", nil, 0)
  end
  bar._neOverlay:ClearAllPoints()
  bar._neOverlay:SetPoint("TOPLEFT", bar, "TOPLEFT", 0, 0)
  bar._neOverlay:SetTexture(source)                                  -- DOWNPORT: no filterMode arg
  NE.tex.SmoothBarTex(bar._neOverlay)
  bar._neAtlas = { left = entry.left, right = entry.right, top = entry.top, bottom = entry.bottom }
  bar._neOverlayAtlasName = name
  NE.tex.atlasBars[bar] = true
  ensureAtlasUpdater()

  if not bar._neAtlasValueHooked then
    bar._neAtlasValueHooked = true
    bar:HookScript("OnValueChanged",  updateAtlasOverlay)
    bar:HookScript("OnMinMaxChanged", updateAtlasOverlay)
    bar:HookScript("OnSizeChanged",   updateAtlasOverlay)
    hooksecurefunc(bar, "SetValue",        function(self) updateAtlasOverlay(self) end)
    hooksecurefunc(bar, "SetMinMaxValues", function(self) updateAtlasOverlay(self) end)
    hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b)
      if self._neOverlay then self._neOverlay:SetVertexColor(r or 1, g or 1, b or 1, 1) end
    end)
    local cr, cg, cb = bar:GetStatusBarColor()
    if cr then bar._neOverlay:SetVertexColor(cr, cg, cb, 1) end
  end
  updateAtlasOverlay(bar)
  return true
end

-- The retail aura debuff-border crop (UI-Debuff-Overlays). Vanilla-era asset → ports as-is.
function NE.tex.DebuffBorder(tex)
  if not tex then return end
  tex:SetTexture("Interface\\Buttons\\UI-Debuff-Overlays")
  tex:SetTexCoord(0.296875, 0.5703125, 0, 0.515625)
end

-- Modern per-dispel-type debuff border (atlas). Degrades to the legacy DebuffBorder if the
-- modern atlas art isn't registered yet.
NE.tex.DISPEL_BORDER = {
  Magic   = { basic = "ui-debuff-border-magic-noicon-2x",   dispel = "ui-debuff-border-magic-icon-2x" },
  Curse   = { basic = "ui-debuff-border-curse-noicon-2x",   dispel = "ui-debuff-border-curse-icon-2x" },
  Disease = { basic = "ui-debuff-border-disease-noicon-2x", dispel = "ui-debuff-border-disease-icon-2x" },
  Poison  = { basic = "ui-debuff-border-poison-noicon-2x",  dispel = "ui-debuff-border-poison-icon-2x" },
  Bleed   = { basic = "ui-debuff-border-bleed-noicon-2x",   dispel = "ui-debuff-border-bleed-icon-2x" },
}
local DISPEL_BORDER_NONE = "ui-debuff-border-default-noicon-2x"
function NE.tex.DispelBorder(border, debuffType, showDispel)
  if not border then return false end
  local info  = NE.tex.DISPEL_BORDER[debuffType or ""]
  local atlas = info and ((showDispel and info.dispel) or info.basic) or DISPEL_BORDER_NONE
  border:SetVertexColor(1, 1, 1)
  if NE.tex.SetAtlas(border, atlas, false) then border:Show(); return true end
  -- DOWNPORT: fail-safe to the legacy vanilla debuff border if the modern atlas isn't shipped.
  NE.tex.DebuffBorder(border)
  border:Show()
  return false
end

-- The bags auto-sort button face. Degrades silently if the atlas isn't registered.
function NE.tex.AutoSortButton(btn)
  if not btn then return end
  local n = btn:CreateTexture(nil, "ARTWORK")
  NE.tex.SetAtlas(n, "bags-button-autosort-up", false); n:SetAllPoints(btn); btn:SetNormalTexture(n)
  local p = btn:CreateTexture(nil, "ARTWORK")
  NE.tex.SetAtlas(p, "bags-button-autosort-down", false); p:SetAllPoints(btn); btn:SetPushedTexture(p)
end
