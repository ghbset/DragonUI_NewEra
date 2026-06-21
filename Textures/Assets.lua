-- DragonUI_NewEra/Textures/Assets.lua — SHARED / CORE sheet registration (Sprint 0).
--
-- Owner: Asset Pipeline Engineer (CONTRACTS.md §3). This file ONLY maps
-- FileDataID -> shipped local BLP path via NE.tex.RegisterLocal. The API itself
-- (NE.tex.RegisterLocal / NE.tex.Set) is provided by the Core agent's
-- core/Texture.lua; we only CALL it. Loads after core/Texture.lua, after
-- core/NineSliceLayouts.lua's own RegisterLocal calls were removed/owned here,
-- and before any consumer (PanelChrome, _HelloDemo).
--
-- ============================================================================
-- ARCHITECT DECISION (atlas mechanism) — coordinated with Core agent (§2/§3):
--
--   Atlas COORDINATES come from the Core NineSlice coord tables
--   (core/NineSliceLayouts.lua, transcribed from retail's NineSliceLayouts +
--   the NE_ATLAS coord data), resolved at draw time by NE.nineslice.Apply /
--   NE.tex.Set. We DO NOT use C_Texture.RegisterAtlas to carry the slice
--   geometry: the 3.3.5a client has no native atlas DB, and the ClassicAPI
--   shim's C_Texture only answers existence/info queries — it does not feed
--   real slice metadata to the render path (retail nicknames would stretch as
--   flat strips, exactly the failure mode NineSliceLayouts.lua documents).
--
--   THIS FILE is therefore a pure fdid -> file-path index. The atlas-name ->
--   (fdid + texcoord rect) mapping lives in the Core coord tables; this file
--   answers "given the fdid that coord table named, where is the BLP on disk".
--   That split keeps art (here) and geometry (Core) independently editable.
-- ============================================================================

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\"

-- --- UI-Frame-Metal nineslice sheets (PortraitFrameTemplate / ButtonFrameTemplate
--     family). Three sheets: corners, vertical-tile edges, horizontal-tile edges.
--     Consumed by core/NineSliceLayouts.lua layouts + the /dnehello demo.
NE.tex.RegisterLocal(2406979, P .. "Common\\2406979-uiframe-metal-corners.blp")     -- 512x512 BGRA; all metal corners (incl. PortraitMetal/Double)
NE.tex.RegisterLocal(2406984, P .. "Common\\2406984-uiframe-metal-edges-vert.blp")  -- 512x32  BGRA; !-tile L/R edges
NE.tex.RegisterLocal(2406987, P .. "Common\\2406987-uiframe-metal-edges-horiz.blp") -- 64x256  BGRA; _-tile Top/Bottom edges

-- --- UI-Background-Rock — ButtonFrameTemplate rock fill (shared: CharacterPanel + Social).
NE.tex.RegisterLocal(374155,  P .. "Common\\374155-uibackground-rock.blp")          -- 1024x1024 DXT1

-- --- InsetFrameTemplate inner-border (the thin gold inner-recess trim). Shared Core
--     layout (CONTRACTS §3) — its 3 sheets belong in Core, never a single module's
--     Assets (else disabling that module drops the inset border everywhere).
NE.tex.RegisterLocal(1723831, P .. "Common\\1723831-uiframe-inner.blp")             -- 128x128 DXT5; UI-Frame-Inner* corners (6x6)
NE.tex.RegisterLocal(1723832, P .. "Common\\1723832-uiframe-inner.blp")             -- 64x256  DXT5; !UI-Frame-Inner{Left,Right}Tile (3x256)
NE.tex.RegisterLocal(1723833, P .. "Common\\1723833-uiframe-inner.blp")             -- 256x128 DXT5; _UI-Frame-Inner{Top,Bot}Tile band

-- --- RedButton close-button sheet (4698972) — the Dragonflight red "X". One sheet carries all
--     four states (exit / pressed / highlight / disabled) via texcoords in core/NineSliceLayouts.
--     Consumed by PanelChrome.ModernizeCloseButton; without it the close button falls back to the
--     native 3.3.5a art (which renders blank under our chrome), so it's shared Core art.
NE.tex.RegisterLocal(4698972, P .. "Common\\4698972-redbutton-exit-2x.blp")          -- 36x38 states grid

-- --- DF metal panel-tab sheet (4707839) — the modern bottom-tab look (uiframe-tab / -activetab),
--     used by core/Tabs.lua (NE.tabs.ReskinClassicTab) for the CharacterPanel tabs and any other
--     reskinned classic tabs. Coords live in core/NineSliceLayouts.lua; this ships the art.
NE.tex.RegisterLocal(4707839, P .. "Common\\4707839-uiframe-tab.blp")                -- 64x256 tab/activetab grid

-- --- Minimal-scrollbar art (the DF "MinimalScrollBar" look), consumed by core/ScrollbarReskin.lua
--     over the classic Slider-based UIPanelScrollBar. Coords live in core/NineSliceLayouts.lua;
--     these ship the four backing sheets so the reskin lights up (track + arrows + thumb caps +
--     thumb middle). Shared Core art — every character panel's FauxScrollFrame reskins through it.
NE.tex.RegisterLocal(4331838, P .. "Common\\4331838-minimal-scrollbar.blp")                       -- track top/bottom + arrows
NE.tex.RegisterLocal(4332072, P .. "Common\\4332072-minimal-scrollbar-track-middle.blp")          -- !track-middle 1px tile
NE.tex.RegisterLocal(5142784, P .. "Common\\5142784-minimal-scrollbar-small-thumb-middle.blp")    -- small thumb middle strip
NE.tex.RegisterLocal(5142787, P .. "Common\\5142787-minimal-scrollbar-small.blp")                 -- small thumb top/bottom caps
