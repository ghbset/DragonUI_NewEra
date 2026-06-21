-- DragonUI_NewEra/core/NineSlice.lua — reusable retail-style nineslice walker.
--
-- DOWNPORT: NewEra Core/NineSlice.lua → 3.3.5a. NewEra mirrored retail's NineSlice.lua walker
-- and routed each piece's atlas through NE.tex.SetAtlas (which reads the generated NE_ATLAS). We
-- keep the walker verbatim but route atlas-entry lookups through NE.tex._atlasEntry (our owned
-- coord registry, per the architect decision) instead of the raw NE_ATLAS global. The structure
-- (corners→edges→center, SetPoint anchoring, SetHorizTile/SetVertTile) is all 3.3.5a-legal.
--
-- The §2 contract exposes NE.nineslice.Apply(frame, layoutName[, opts]); NewEra's name is
-- ApplyLayout. We expose BOTH (Apply is the contract alias).
--
-- USAGE:
--   NE.nineslice.AddLayout("ButtonFrameTemplate", { ... })
--   NE.nineslice.Apply(frame, "PortraitFrameTemplate")

local NE = DragonUI_NewEra
NE.nineslice = NE.nineslice or {}
NE.nineslice.layouts = NE.nineslice.layouts or {}

function NE.nineslice.AddLayout(name, layout)
  NE.nineslice.layouts[name] = layout
end

-- Look up or create the piece texture on the container (retail GetNineSlicePiece).
-- DOWNPORT: 3.3.5a frames don't have GetNineSlicePiece (a retail method); the feature-gate falls
-- straight through to CreateTexture, which is exactly what we want for ported chrome.
local function getPiece(container, pieceName)
  local p = container[pieceName]
  if p then return p, true end
  if container.GetNineSlicePiece then
    p = container:GetNineSlicePiece(pieceName)
    if p then
      container[pieceName] = p
      return p, true
    end
  end
  p = container:CreateTexture()
  container[pieceName] = p
  return p, false
end

-- Tile flags from the WoW atlas naming convention: `_<name>` = horiz-tile, `!<name>` = vert-tile.
local function tileFlagsFromAtlasName(atlasName)
  if not atlasName or atlasName == "" then return false, false end
  local prefix = atlasName:sub(1, 1)
  return prefix == "_", prefix == "!"
end

-- After SetAtlas, optionally re-flip texcoord for mirrored pieces.
-- DOWNPORT: read the atlas entry through NE.tex._atlasEntry (our registry) not NE_ATLAS.
local function applyPostAtlasMirror(piece, setupInfo, pieceLayout, userLayout)
  local pieceMirrored = pieceLayout.mirrorLayout
  if pieceMirrored == nil then pieceMirrored = userLayout and userLayout.mirrorLayout end
  if not pieceMirrored then return end
  local entry = NE.tex._atlasEntry and NE.tex._atlasEntry(pieceLayout.atlas)
  if not entry then return end
  local L, R, T, B = entry.left, entry.right, entry.top, entry.bottom
  if setupInfo.mirrorHorizontal then L, R = R, L end
  if setupInfo.mirrorVertical   then T, B = B, T end
  piece:SetTexCoord(L, R, T, B)
end

local function setupCorner(container, piece, setupInfo, pieceLayout)
  piece:ClearAllPoints()
  piece:SetPoint(pieceLayout.point or setupInfo.point, container,
                 pieceLayout.relativePoint or setupInfo.point,
                 pieceLayout.x or 0, pieceLayout.y or 0)
end

local function setupEdge(container, piece, setupInfo, pieceLayout)
  piece:ClearAllPoints()
  local p1 = getPiece(container, setupInfo.relativePieces[1])
  local p2 = getPiece(container, setupInfo.relativePieces[2])
  piece:SetPoint(setupInfo.point, p1, setupInfo.relativePoint,
                 pieceLayout.x or 0, pieceLayout.y or 0)
  piece:SetPoint(setupInfo.relativePoint, p2, setupInfo.point,
                 pieceLayout.x1 or 0, pieceLayout.y1 or 0)
end

local function setupCenter(container, piece, setupInfo, pieceLayout)
  piece:ClearAllPoints()
  local tl = getPiece(container, "TopLeftCorner")
  local br = getPiece(container, "BottomRightCorner")
  piece:SetPoint("TOPLEFT",     tl, "BOTTOMRIGHT", pieceLayout.x  or 0, pieceLayout.y  or 0)
  piece:SetPoint("BOTTOMRIGHT", br, "TOPLEFT",     pieceLayout.x1 or 0, pieceLayout.y1 or 0)
end

-- Ordered piece list. Corners first so edges can anchor to them; center last.
local nineSliceSetup = {
  { pieceName = "TopLeftCorner",     point = "TOPLEFT",     fn = setupCorner },
  { pieceName = "TopRightCorner",    point = "TOPRIGHT",    mirrorHorizontal = true, fn = setupCorner },
  { pieceName = "BottomLeftCorner",  point = "BOTTOMLEFT",  mirrorVertical   = true, fn = setupCorner },
  { pieceName = "BottomRightCorner", point = "BOTTOMRIGHT", mirrorHorizontal = true, mirrorVertical = true, fn = setupCorner },
  { pieceName = "TopEdge",    point = "TOPLEFT",    relativePoint = "TOPRIGHT",
    relativePieces = { "TopLeftCorner",    "TopRightCorner"    },                          fn = setupEdge },
  { pieceName = "BottomEdge", point = "BOTTOMLEFT", relativePoint = "BOTTOMRIGHT",
    relativePieces = { "BottomLeftCorner", "BottomRightCorner" }, mirrorVertical = true,   fn = setupEdge },
  { pieceName = "LeftEdge",   point = "TOPLEFT",    relativePoint = "BOTTOMLEFT",
    relativePieces = { "TopLeftCorner",    "BottomLeftCorner"  },                          fn = setupEdge },
  { pieceName = "RightEdge",  point = "TOPRIGHT",   relativePoint = "BOTTOMRIGHT",
    relativePieces = { "TopRightCorner",   "BottomRightCorner" }, mirrorHorizontal = true, fn = setupEdge },
  { pieceName = "Center",     fn = setupCenter },
}

function NE.nineslice.ApplyLayout(container, layoutName)
  if not container then return false end
  local layout = NE.nineslice.layouts[layoutName]
  if not layout then
    if NE.Log then NE.Log("NINESLICE", "MISS layout " .. tostring(layoutName)) end
    return false
  end

  local anyApplied = false
  for _, setup in ipairs(nineSliceSetup) do
    local pieceLayout = layout[setup.pieceName]
    if pieceLayout then
      local piece, existed = getPiece(container, setup.pieceName)
      if not existed then
        local layer    = container.layoutTextureLayer    or pieceLayout.layer or "BORDER"
        local subLevel = container.layoutTextureSubLevel or pieceLayout.subLevel
        piece:SetDrawLayer(layer, subLevel)
      end
      setup.fn(container, piece, setup, pieceLayout)
      if NE.tex.SetAtlas(piece, pieceLayout.atlas, false) then anyApplied = true end
      -- Tile flags and mirror must run POST-atlas (SetAtlas resets wrap + overwrites texcoord).
      local h, v = tileFlagsFromAtlasName(pieceLayout.atlas)
      piece:SetHorizTile(h)
      piece:SetVertTile(v)
      applyPostAtlasMirror(piece, setup, pieceLayout, layout)
      if pieceLayout.w then piece:SetWidth(pieceLayout.w)  end
      if pieceLayout.h then piece:SetHeight(pieceLayout.h) end
      piece:Show()
    end
  end

  -- DOWNPORT: disableSharpening drove SetTexelSnappingBias/SetSnapToPixelGrid (retail-only) —
  -- feature-gated so it no-ops on 3.3.5a.
  if layout.disableSharpening then
    for _, setup in ipairs(nineSliceSetup) do
      local piece = container[setup.pieceName]
      if piece and piece.SetTexelSnappingBias then
        piece:SetTexelSnappingBias(0)
        if piece.SetSnapToPixelGrid then piece:SetSnapToPixelGrid(false) end
      end
    end
  end
  return anyApplied
end

-- §2 CONTRACT alias. opts is accepted for forward-compat (unused in v1 layouts).
function NE.nineslice.Apply(frame, layoutName, opts)
  return NE.nineslice.ApplyLayout(frame, layoutName, opts)
end

function NE.nineslice.HideLayout(container)
  if not container then return end
  for _, setup in ipairs(nineSliceSetup) do
    local p = container[setup.pieceName]
    if p then p:Hide() end
  end
end

-- TopTileStreaks — the horizontally-tiled decorative streak band under the title bar.
-- DOWNPORT: SetShown → Show/Hide; reads our atlas registry via NE.tex._atlasEntry.
function NE.nineslice.ApplyTopTileStreaks(frame, opts)
  if not frame then return end
  opts = opts or {}
  local host = opts.parent or frame
  local t = frame._neTopTileStreaks
  if not t then
    t = host:CreateTexture(nil, opts.layer or "BORDER", nil, opts.subLevel)
    frame._neTopTileStreaks = t
  end
  t:ClearAllPoints()
  t:SetPoint("TOPLEFT",  host, "TOPLEFT",  opts.xL or 6,  opts.y or -21)
  t:SetPoint("TOPRIGHT", host, "TOPRIGHT", opts.xR or -2, opts.y or -21)
  if not (NE.tex and NE.tex.SetAtlas and NE.tex.SetAtlas(t, "_ui-frame-toptilestreaks", false)) then
    t:Hide()
    return t
  end
  t:SetHorizTile(true)
  local entry = NE.tex._atlasEntry and NE.tex._atlasEntry("_ui-frame-toptilestreaks")
  t:SetHeight(opts.h or (entry and entry.height) or 43)
  t:Show()
  return t
end

-- Hide any pre-existing nineslice pieces (a frame's .NineSlice child + direct pieces).
function NE.nineslice.HideClassicChrome(frame)
  if not frame then return end
  local nineSlice = frame.NineSlice
  if nineSlice then NE.nineslice.HideLayout(nineSlice) end
  NE.nineslice.HideLayout(frame)
end
