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

-- --- Common-currencybox — the rounded 3-piece pill border behind each watched-currency token in
--     the combined bag's bottom money band (modules/bags/CombinedBag.lua). One 32x64 sheet holds
--     left/right end caps + a stretched center (atlas coords registered by the bags module).
NE.tex.RegisterLocal(4701880, P .. "Common\\4701880-common-currencybox.blp")        -- 32x64 BGRA; common-currencybox-{left,right,center}

-- --- UI-Background-Rock — ButtonFrameTemplate rock fill (shared body art: Social, bags, and
--     every other chrome'd window).
NE.tex.RegisterLocal(374155,  P .. "Common\\374155-uibackground-rock.blp")          -- 1024x1024 DXT1

-- --- Slot chrome: the empty-slot recess (130766 UI-EmptySlot) and the slot RING (130841
--     UI-Quickslot2). Both are same-FDID-different-art between clients — 3.3.5a's own copies are
--     the classic wooden versions — so the retail BLPs ship here. Shared Core art, not a module's:
--     NewEra keeps them in its Core atlas file for the same reason (merchant rows, the repair /
--     sell-junk buttons and any future trade window all draw them, so disabling one module must
--     not take the recess away from the others).
NE.tex.RegisterLocal(130766, P .. "Common\\130766-ui-emptyslot-retail.blp")         -- 64x64 slot recess
NE.tex.RegisterLocal(130841, P .. "Common\\130841-ui-quickslot2-retail.blp")        -- 64x64 slot ring

-- --- InsetFrameTemplate inner-border (the thin gold inner-recess trim). Shared Core
--     layout (CONTRACTS §3) — its 3 sheets belong in Core, never a single module's
--     Assets (else disabling that module drops the inset border everywhere).
NE.tex.RegisterLocal(1723831, P .. "Common\\1723831-uiframe-inner.blp")             -- 128x128 DXT5; UI-Frame-Inner* corners (6x6)
NE.tex.RegisterLocal(1723832, P .. "Common\\1723832-uiframe-inner.blp")             -- 64x256  DXT5; !UI-Frame-Inner{Left,Right}Tile (3x256)
NE.tex.RegisterLocal(1723833, P .. "Common\\1723833-uiframe-inner.blp")             -- 256x128 DXT5; _UI-Frame-Inner{Top,Bot}Tile band

-- --- BigRedThreeSliceButton (1536801) — the red dialog button. core/ButtonSkin.lua has been written
--     against this sheet since Sprint 0 and, without it, fail-safed to native art on every call: the
--     LFG role buttons and the edit-mode dialog's Revert/Reset were all silently unskinned.
NE.tex.RegisterLocal(1536801, P .. "Common\\1536801-128redbutton.blp")              -- 512x2048; caps, tile, 3 states + highlight

-- --- DiamondMetal "Dialog" border — retail's clean thin dialog frame (the ESC menu and every
--     modern dialog wear it). Core art, not a module's: the Metal family above is panel chrome and
--     wrong on a small floating dialog, so anything dialog-shaped needs this instead.
NE.tex.RegisterLocal(3056750, P .. "Common\\3056750-diamondmetal-frame.blp")        -- corners + top/bottom edges
NE.tex.RegisterLocal(3056755, P .. "Common\\3056755-diamondmetal-edges.blp")        -- !-tile left/right edges

-- --- Modern dropdown trigger (5390329) — common-dropdown-textholder (the body) plus the
--     a-button arrow and its five states. 3.3.5a has no WowStyle1DropdownTemplate to carry these,
--     so the widget is assembled from them in SettingsControls.
NE.tex.RegisterLocal(5390329, P .. "Common\\5390329-common-dropdown-bg.blp")        -- 512x512; textholder + a-button states

-- --- RedButton close-button sheet (4698972) — the Dragonflight red "X". One sheet carries all
--     four states (exit / pressed / highlight / disabled) via texcoords in core/NineSliceLayouts.
--     Consumed by PanelChrome.ModernizeCloseButton; without it the close button falls back to the
--     native 3.3.5a art (which renders blank under our chrome), so it's shared Core art.
NE.tex.RegisterLocal(4698972, P .. "Common\\4698972-redbutton-exit-2x.blp")          -- 36x38 states grid

-- --- DF metal panel-tab sheet (4707839) — the modern bottom-tab look (uiframe-tab / -activetab),
--     used by core/Tabs.lua (NE.tabs.ReskinClassicTab) for every reskinned classic tab in the
--     addon. Coords live in core/NineSliceLayouts.lua; this ships the art.
NE.tex.RegisterLocal(4707839, P .. "Common\\4707839-uiframe-tab.blp")                -- 64x256 tab/activetab grid

-- --- Minimal-scrollbar art (the DF "MinimalScrollBar" look), consumed by core/ScrollbarReskin.lua
--     over the classic Slider-based UIPanelScrollBar. Coords live in core/NineSliceLayouts.lua;
--     these ship the four backing sheets so the reskin lights up (track + arrows + thumb caps +
--     thumb middle). Shared Core art — every FauxScrollFrame in the addon reskins through it.
NE.tex.RegisterLocal(4331838, P .. "Common\\4331838-minimal-scrollbar.blp")                       -- track top/bottom + arrows
NE.tex.RegisterLocal(4332072, P .. "Common\\4332072-minimal-scrollbar-track-middle.blp")          -- !track-middle 1px tile
NE.tex.RegisterLocal(5142784, P .. "Common\\5142784-minimal-scrollbar-small-thumb-middle.blp")    -- small thumb middle strip
NE.tex.RegisterLocal(5142787, P .. "Common\\5142787-minimal-scrollbar-small.blp")                 -- small thumb top/bottom caps

-- MinimalSliderWithSteppers (sheet 4567914) — the whole horizontal slider on one 32x128 sheet: both
-- rounded track caps, the 1px tiled run between them, the DIAMOND thumb, and both chevron steppers.
-- Supplied by the owner; it is not in the NewEra Art set, which is why NE.scrollbar.SkinSlider first
-- shipped built out of the vertical scrollbar's pieces turned on their side.
NE.tex.RegisterLocal(4567914, P .. "Common\\4567914-minimalsliderbar.blp")                        -- track caps + run + diamond + steppers
