-- DragonUI_NewEra/core/PanelChrome.lua — shared "modern portrait-frame chrome".
--
-- DOWNPORT: NewEra Core/PanelChrome.lua → 3.3.5a. NewEra's PC.Apply RESKINNED an existing Era
-- ButtonFrameTemplate frame (hide classic border → modern NineSlice on f.NineSlice + rock Bg +
-- TopTileStreaks + modern CloseButton). On 3.3.5a our panels are frequently BUILT FROM SCRATCH
-- (the Hello demo, and Sprint-1 NE_ frames), so this version BUILDS the chrome pieces it needs
-- (NineSlice child, Bg, portrait, title, close button) when they're absent, then reskins. It
-- still reskins in-place when the pieces already exist.
--
-- §2 CONTRACT: NE.chrome.Apply(frame, opts) — nineslice + portrait + title + close-button reskin.
-- We expose BOTH NE.chrome (the contract name) and NE.panelchrome (NewEra's name) on one table.
--
-- All ops are texture Show/Hide + SetTexture/SetAtlas + SetFrameLevel — never protected — so
-- callers may re-assert in combat. DEGRADES GRACEFULLY: if an atlas/art isn't registered yet, the
-- nineslice pieces hide themselves and we fall back to a solid-colour backdrop (Hello-demo proof).

local NE = DragonUI_NewEra
NE.panelchrome = NE.panelchrome or {}
NE.chrome = NE.panelchrome              -- DOWNPORT: §2 contract name; same table as NewEra's
local PC = NE.panelchrome

local ROCK_FDID = 374155  -- UI-Background-Rock (retail ButtonFrameTemplate default fill)

-- ButtonFrameTemplate / PortraitFrameTemplate border pieces to hide so our modern NineSlice
-- shows through (only relevant when reskinning an existing Blizzard/Era frame).
local BORDER_KEYS = {
  "PortraitFrame", "TopRightCorner", "TopBorder", "TopLeftCorner",
  "BotLeftCorner", "BotRightCorner", "BottomBorder", "LeftBorder",
  "RightBorder", "TitleBg",
}

-- Register a frame-owned BACKGROUND texture to preserve it from HideClassicChrome's walk.
function PC.Keep(f, tex)
  if not f or not tex then return end
  f._nePanelKeep = f._nePanelKeep or {}
  f._nePanelKeep[tex] = true
end

-- Thin alias to the canonical helper (FrameUtil.lua).
function PC.PinPixelPerfect(f, userScale)
  NE.FrameUtil.PinPixelPerfect(f, userScale)
end

-- Canonical panel title TEXT styling (GameFontNormal gold, centered, no wrap).
function PC.SetTitle(frame, text, fs, anchorTo)
  if not frame then return end
  local tc = frame.TitleContainer
  fs = fs or (tc and tc.TitleText) or frame.Title
  if not fs then return end
  fs:SetFontObject(GameFontNormal)
  if fs.SetWordWrap then fs:SetWordWrap(false) end
  fs:SetJustifyH("CENTER")
  anchorTo = anchorTo or tc or frame
  fs:ClearAllPoints()
  fs:SetPoint("TOP",   anchorTo, "TOP", 0, -5)
  fs:SetPoint("LEFT",  anchorTo, "LEFT")
  fs:SetPoint("RIGHT", anchorTo, "RIGHT")
  if text ~= nil then fs:SetText(text) end
  frame._neTitle = fs
  return fs
end

-- The retail title BAND for rehosted titles. Idempotent per frame.
function PC.TitleBand(f)
  if f._neTitleBand then return f._neTitleBand end
  local tc = CreateFrame("Frame", nil, f)
  tc:SetPoint("TOPLEFT",  f, "TOPLEFT",  58, -1)
  tc:SetPoint("TOPRIGHT", f, "TOPRIGHT", -24, -1)
  tc:SetHeight(20)
  tc:EnableMouse(false)
  local nsLevel = (f.NineSlice and f.NineSlice.GetFrameLevel and f.NineSlice:GetFrameLevel())
    or f:GetFrameLevel() or 1
  tc:SetFrameLevel(nsLevel + 10)
  f._neTitleBand = tc
  return tc
end

-- Hide the classic chrome (only when reskinning a frame that already carries Blizzard/Era chrome).
function PC.HideClassicChrome(f)
  if not f then return end
  for _, key in ipairs(BORDER_KEYS) do
    local r = f[key]
    if r and r.Hide then r:Hide() end
  end
  local keep = f._nePanelKeep
  NE.FrameUtil.ForEachRegion(f, "Texture", "BACKGROUND", function(r)
    if r ~= f.Bg and not (keep and keep[r]) then r:Hide() end
  end)
end

-- DOWNPORT: ensure the structural pieces a portrait-frame needs exist. NewEra assumed the Era
-- template already provided f.NineSlice / f.Bg / f.CloseButton / portrait; on a bare 3.3.5a
-- CreateFrame they don't, so build them. Each is idempotent.
local function ensureBg(f)
  if f.Bg then return f.Bg end
  local bg = f:CreateTexture(nil, "BACKGROUND")
  -- DOWNPORT: the metal border's inner edge sits closer to the frame edge than a 4px inset, so a
  -- 4px inset left a see-through gap (≈3-4px L/R, ≈2px bottom). Tighten the fill to meet the border.
  bg:SetPoint("TOPLEFT", 1, -4)
  bg:SetPoint("BOTTOMRIGHT", -1, 2)
  f.Bg = bg
  return bg
end

local function ensureNineSlice(f)
  if f.NineSlice then return f.NineSlice end
  local ns = CreateFrame("Frame", nil, f)
  ns:SetAllPoints(f)
  ns:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
  f.NineSlice = ns
  return ns
end

local function ensureCloseButton(f)
  if f.CloseButton then return f.CloseButton end
  local cb = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  cb:SetPoint("TOPRIGHT", 1, 0)
  -- DOWNPORT: the chrome stack paints over this spot — the nineslice top-right metal corner
  -- (f:level+1) AND the title band (f:level+11) both sit at higher frame levels than a default
  -- child button, occluding the button's Normal (X) texture while the HIGHLIGHT layer bleeds
  -- through on hover. Lift the button clearly above the entire chrome stack so the X is visible.
  local baseLvl = (f.GetFrameLevel and f:GetFrameLevel()) or 1
  cb:SetFrameLevel(baseLvl + 20)
  f.CloseButton = cb
  return cb
end

local function ensureTitle(f, text)
  if f.TitleContainer and f.TitleContainer.TitleText then return f.TitleContainer.TitleText end
  if f.Title then return f.Title end
  local band = PC.TitleBand(f)
  local fs = band:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.Title = fs
  PC.SetTitle(f, text, fs, band)
  return fs
end

local function ensurePortrait(f)
  if f.portrait then return f.portrait end
  if f.PortraitTexture then return f.PortraitTexture end
  local p = f:CreateTexture(nil, "ARTWORK")
  f.portrait = p
  return p
end

-- DOWNPORT: solid-colour fallback backdrop so a chrome'd frame is never invisible/hard-erroring
-- when the metal atlas art isn't registered yet (the Hello-demo graceful-degrade requirement).
local function applyFallbackBackdrop(f)
  if not f.Bg then ensureBg(f) end
  f.Bg:SetTexture(0.07, 0.07, 0.09, 0.95)   -- 3.3.5a accepts colour args to SetTexture
  f.Bg:Show()
  if not f._neFallbackBorder and f.SetBackdrop then
    f:SetBackdrop({
      edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
      edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    f:SetBackdropBorderColor(0.6, 0.5, 0.3, 1)
    f._neFallbackBorder = true
  end
end

-- layout (optional): which registered NineSlice layout to apply. Default "PortraitFrameTemplate".
function PC.ApplyModernChrome(f, layout)
  if not f then return end
  layout = layout or "PortraitFrameTemplate"

  -- Bg → tiled UI-Background-Rock (retail default), if the art is shipped; else a solid fill.
  ensureBg(f)
  do
    local localPath = NE.tex.localFiles and NE.tex.localFiles[ROCK_FDID]
    if localPath then
      f.Bg:SetTexture(localPath, "REPEAT", "REPEAT")
      f.Bg:SetHorizTile(true)
      f.Bg:SetVertTile(true)
      -- DOWNPORT: the raw UI-Background-Rock sheet renders mid-brown on first paint (retail darkens
      -- it via panel composition). Apply an explicit dark tint so the content area reads dark
      -- immediately, instead of only after a /reload settles it. (Tunable.)
      f.Bg:SetVertexColor(0.32, 0.32, 0.32)
      f.Bg:Show()
    else
      -- DOWNPORT: rock sheet not registered → solid fill (graceful degrade).
      f.Bg:SetTexture(0.07, 0.07, 0.09, 0.95)
      f.Bg:Show()
    end
  end

  -- Modern nineslice on f.NineSlice. If NONE of the pieces resolve, fall back to a flat border.
  local ns = ensureNineSlice(f)
  ns:Show()
  local applied = NE.nineslice and NE.nineslice.ApplyLayout and NE.nineslice.ApplyLayout(ns, layout)
  if not applied then
    applyFallbackBackdrop(f)
    if NE.Log then NE.Log("CHROME", "nineslice art missing for "..tostring(layout)..", used fallback") end
  end

  -- TopTileStreaks under the title.
  if NE.nineslice and NE.nineslice.ApplyTopTileStreaks then
    NE.nineslice.ApplyTopTileStreaks(f)
  end

  -- Uniform title styling (no-op if the frame has no title region).
  PC.SetTitle(f)
end

-- Modernize a close button to retail's RedButton-Exit family. Idempotent. Degrades to the native
-- UIPanelCloseButton art if the atlas isn't registered.
function PC.ModernizeCloseButton(target, opts)
  local cb = target
  if cb and not cb.SetNormalTexture and cb.CloseButton then cb = cb.CloseButton end
  if not cb or not cb.SetNormalTexture or cb._neCloseModernized then return end
  if not (NE.tex and NE.tex.SetAtlas) then return end
  opts = opts or {}

  local size = opts.size or 24
  cb:SetSize(size, size)

  if opts.anchor ~= false then
    local a = opts.anchor or { "TOPRIGHT", "TOPRIGHT", 1, 0 }
    cb:ClearAllPoints()
    cb:SetPoint(a[1], cb:GetParent(), a[2] or a[1], a[3] or 0, a[4] or 0)
  end
  if opts.frameLevelBump then
    local parent = cb:GetParent()
    local base = (parent and parent.GetFrameLevel and parent:GetFrameLevel()) or 0
    cb:SetFrameLevel(base + opts.frameLevelBump)
  end

  -- DOWNPORT: NewEra set state textures by passing a CreateTexture OBJECT to SetNormalTexture.
  -- On 3.3.5a, Button:SetNormalTexture/SetPushedTexture/etc. take a FILE-PATH STRING, not a texture
  -- object (passing an object silently no-ops → blank button — the bug we chased). Use the canonical
  -- 3.3.5a pattern: SetXTexture(path) then SetTexCoord on the returned GetXTexture(). Art comes from
  -- the shipped local BLP (NE.tex.Local(fdid)); if it isn't shipped, keep the native button art.
  local function applyState(setter, getter, atlas, blend)
    local entry = NE.tex._atlasEntry and NE.tex._atlasEntry(atlas)
    local path  = entry and NE.tex.Local and NE.tex.Local(entry.file)
    if not (entry and path) then return false end
    cb[setter](cb, path)
    local t = cb[getter] and cb[getter](cb)
    if t then
      t:SetTexCoord(entry.left, entry.right, entry.top, entry.bottom)
      if blend then t:SetBlendMode(blend) end
    end
    return true
  end

  local okN = applyState("SetNormalTexture",    "GetNormalTexture",    "redbutton-exit-2x")
              applyState("SetPushedTexture",    "GetPushedTexture",    "redbutton-exit-pressed-2x")
              applyState("SetHighlightTexture", "GetHighlightTexture", "redbutton-highlight-2x", "ADD")
  if opts.disabled ~= false then
              applyState("SetDisabledTexture",  "GetDisabledTexture",  "redbutton-exit-disabled-2x")
  end

  -- Only mark "modernized" if the normal state took; else leave native art (never blank).
  if okN then cb._neCloseModernized = true end
end

-- §2 CONTRACT entry. opts (all optional):
--   layout        registered nineslice layout name (default "PortraitFrameTemplate")
--   title         title text
--   portrait      texture path / FDID for the portrait cutout
--   noPortrait    true → skip the portrait
--   noCloseButton true → skip building/reskinning a close button
--   pixelPerfect  true → PinPixelPerfect the frame
-- DOWNPORT: NewEra's Apply only did HideClassicChrome + ApplyModernChrome (reskin path). Ours
-- additionally BUILDS portrait/title/close-button on bare frames and wires the §2 opts.
function PC.Apply(f, opts)
  if not f then return end
  opts = opts or {}

  PC.HideClassicChrome(f)
  PC.ApplyModernChrome(f, opts.layout)

  -- Title.
  if opts.title ~= nil then
    local fs = ensureTitle(f, opts.title)
    if fs then fs:SetText(opts.title) end
  end

  -- Portrait cutout.
  if not opts.noPortrait then
    local p = ensurePortrait(f)
    if p then
      if opts.portrait then
        NE.tex.Set(p, opts.portrait)
      elseif SetPortraitTexture then
        -- Default: the player portrait. DOWNPORT: SetPortraitTexture yields an EMPTY portrait when
        -- the player model isn't ready yet (first open after login — populated only after a /reload
        -- caches the model). Re-apply on the next frame, on every Show, and on portrait-update events
        -- so it fills in without needing a reload.
        local function refreshPortrait() pcall(SetPortraitTexture, p, "player") end
        refreshPortrait()
        if C_Timer and C_Timer.After then C_Timer.After(0, refreshPortrait) end
        f:HookScript("OnShow", refreshPortrait)
        if not f._nePortraitWatcher then
          local w = CreateFrame("Frame", nil, f)
          w:RegisterEvent("UNIT_PORTRAIT_UPDATE")
          w:RegisterEvent("PLAYER_ENTERING_WORLD")
          w:SetScript("OnEvent", function(_, _, unit)
            if (not unit) or unit == "player" then refreshPortrait() end
          end)
          f._nePortraitWatcher = w
        end
      else
        NE.tex.Set(p, 134400)   -- INV_Misc_QuestionMark fallback FDID-ish path id
      end
      if NE.portrait and NE.portrait.ApplyCutout then
        NE.portrait.ApplyCutout(p, f, opts.portraitOpts)
      end
    end
  end

  -- Close button.
  if not opts.noCloseButton then
    local cb = ensureCloseButton(f)
    PC.ModernizeCloseButton(cb)
  end

  if opts.pixelPerfect then PC.PinPixelPerfect(f, opts.userScale) end
  return f
end
