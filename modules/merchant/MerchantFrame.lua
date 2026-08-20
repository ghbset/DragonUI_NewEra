-- DragonUI_NewEra/modules/merchant/MerchantFrame.lua — modern (Dragonflight) chrome on the
-- client's own vendor window.
--
-- DOWNPORT of NewEra/MerchantFrame/MerchantFrame.lua (Classic 1.15). Like the 1.15 source this is a
-- RESKIN, not a replacement: FrameXML keeps MerchantFrame_Update / _UpdateMerchantInfo /
-- _UpdateBuybackInfo and all of the buy/sell/repair behaviour; we re-dress the frame it paints on
-- and hook the updater to keep our pieces in sync. What changed from the 1.15 source, and why:
--
--   * The frame is a different animal here. Era's MerchantFrame inherits ButtonFrameTemplate, so
--     the source could hide `f.NineSlice`'s template pieces and re-texture them, write the NPC name
--     into `f.TitleContainer.TitleText`, and paint `f.PortraitContainer.portrait`. On 3.3.5a
--     MerchantFrame is a 384x512 classic wooden panel: four corner quadrants, a `MerchantNameText`
--     FontString for the title, `MerchantFramePortrait` for the face, and none of the modern
--     subframes. So the chrome is BUILT (PanelChrome's ensure* path) rather than re-textured, the
--     title is rehosted into PanelChrome's title band, and MerchantFramePortrait IS the portrait —
--     kept, not hidden.
--   * The quadrants are UNNAMED and sit on the BORDER layer, with the buyback tab's own wooden
--     backdrop a layer above that on ARTWORK — so PanelChrome's BACKGROUND-layer walk (all a
--     ButtonFrameTemplate frame needs) does not reach any of it. hideClassicChrome walks those two
--     layers itself, matching on texture PATH, and re-runs after every update because FrameXML
--     re-shows the per-tab pieces.
--   * The client's layout is built around that wooden art's transparent margins, which our border
--     does not have — see the Layout block below for what gets re-anchored and why.
--   * MERCHANT_ITEMS_PER_PAGE is 10 here, not 12 — rows 11/12 exist but only the buyback tab uses
--     them. Every loop runs to BUYBACK_ITEMS_PER_PAGE with an existence guard.
--   * MerchantFrameItem_UpdateQuality does not exist on this client (it is an Era addition), so the
--     name-colouring and quest-bang pass hangs off _UpdateMerchantInfo / _UpdateBuybackInfo
--     instead. The rarity BORDER is deliberately not ours: DragonUI's itemquality module already
--     paints merchant buttons, and two overlays on one icon read as a double border.
--   * SetShown does not exist on 3.3.5a (hard rule) — Show/Hide throughout.
--
-- See PORT_NOTES.md for the pieces of the 1.15 source that have no counterpart here.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.merchant = NE.merchant or {}
local Merch = NE.merchant
local PC = NE.panelchrome

-- 10 on 3.3.5a; the buyback tab reuses the same rows and shows 12.
-- How many times each post-hook has actually run, and the tab it last saw. Read back by
-- /nemerchant: "the window kept the other tab's dressing" has two very different causes -- our sync
-- ran and got something wrong, or it never ran at all -- and these tell them apart at a glance.
Merch.stats = Merch.stats or { update = 0, merchantInfo = 0, buybackInfo = 0, repair = 0, tabClick = 0,
                               onShow = 0, onHide = 0, evShow = 0, evClosed = 0, tabTrace = {} }
local stats = Merch.stats

-- Record a tab change with what caused it. Buying back from the Buyback tab reportedly lands you on
-- the Merchant tab, and there are two very different explanations: something re-runs
-- MerchantFrame_OnShow (which calls PanelTemplates_SetTab(MerchantFrame, 1) unconditionally, so ANY
-- re-show snaps you back to Merchant), or the tab never changed and the pane merely looks wrong.
-- Nothing here alters behaviour; it only makes the sequence readable after the fact.
local function trace(what)
  local f = _G.MerchantFrame
  local t = stats.tabTrace
  t[#t + 1] = what .. "=" .. tostring(f and f.selectedTab)
  while #t > 12 do table.remove(t, 1) end
end
Merch.Trace = trace

local ITEMS_PER_PAGE   = MERCHANT_ITEMS_PER_PAGE or 10
local BUYBACK_PER_PAGE = BUYBACK_ITEMS_PER_PAGE or 12

local EMPTY_SLOT_FDID  = 130766   -- UI-EmptySlot           (the dark recess behind an icon)
local SLOT_RING_FDID   = 130841   -- UI-Quickslot2          (the ring around an icon)
local LABEL_PLATE_FDID = 136423   -- UI-Merchant-LabelSlots (the wide row name/price plate)

-- ----------------------------------------------------------------------------
-- Layout
--
-- The client's own numbers are built around its wooden art: a 384x512 frame whose 2x5 grid of
-- 153x44 rows starts at (24,-80), i.e. 11px from the left edge and 65 from the right, with ~50px of
-- dead air above it and another ~90 between the grid and the buyback slot. Under a border that no
-- longer has those margins painted into it, the grid reads as jammed against the left edge with a
-- hole in the middle. So the frame is re-sized and the pieces re-anchored — everything here is a
-- plain SetPoint/SetSize on an unprotected frame, and nothing in FrameXML re-anchors any of it, so
-- one pass at login holds for the session.
--
-- Row geometry that the numbers below are derived from (MerchantItemTemplate, verified against the
-- 3.3.5a MerchantFrame.xml): row 153x44; SlotTexture 64x64 at TOPLEFT(-13,13), so a row's visible
-- left edge is rowX-13; NameFrame 128 wide anchored LEFT of SlotTexture.RIGHT-9, whose right ~40px
-- is transparent tail, so a row's visible right edge is about rowX+130.
local PANEL_W, PANEL_H = 368, 494
local GRID_X, GRID_Y   = 26, -76     -- MerchantItem1 TOPLEFT; rows 2-12 all chain off it
-- col1 rowX = 26, col2 rowX = 26+153+12 = 191. A row's NameFrame TEXTURE runs to rowX+170, but its
-- right end is a soft fade; measured on screen the plate stops reading at about rowX+165, so the
-- right column wants 191+165 = 356 of frame. 368 leaves 13 at the left and 12 at the right.
-- If the right column still overhangs, this is the constant to raise (the fade means erring wide
-- only costs a little air on the right; erring narrow clips the plate over the border).

-- How far in from the screen edge the panel manager places the window. Left-area panels sit flush
-- against the edge on this client (UIParent's LEFT_OFFSET is 0) — fine for a wooden frame whose art
-- carried its own transparent margin, not for a modern one that is opaque to its edge. 6 is what
-- DragonUI gives the character panel and what modules/inspect uses, so the set lines up.
local PANEL_X_NUDGE = 6

-- Everything below is measured off retail's own merchant window, which is the target.
--
-- INSET. Retail sinks the item grid AND the pagination row into one recessed panel, with the button
-- bar outside it at the bottom. That panel is most of what makes the window read as retail's rather
-- than as a grid floating on a slab, and this client has nothing like it — it is built here.
-- The top edge clears the PORTRAIT RING. PortraitFrameTemplate's top-left metal corner is a 75x75
-- circle centred at (24.5,-21.5) with radius 37, and at -44 the inset's own top-left corner sat 27.9
-- from that centre — i.e. inside the ring, drawing across the portrait. The first row's slot was
-- inside it too, at 35.4. Both clear at -60 / grid -76 (41.9 and 43.1). Retail has the same gap here
-- and fills it with its filter dropdown, which this client has no API for, so ours is bare stone.
local INSET_TL_X, INSET_TL_Y = 8, -60    -- TOPLEFT into the frame
local INSET_BR_X, INSET_BR_Y = -8, 101   -- BOTTOMRIGHT into the frame (y measured from the bottom)
-- The buyback tab has no button bar under the grid, so retail lets the grid HAVE that room: six rows
-- spread to fill a taller inset, with the money box tucked against its bottom edge. Keeping the
-- merchant tab's inset there instead left a third of the tab as bare stone.
local INSET_BR_Y_BUYBACK = 30
-- Row pitch is the client's own on the merchant tab (-8) and ours on buyback. FrameXML uses -15
-- there, stretching its six rows into the dead space ITS layout had at the bottom; ours has a
-- different amount of room, so it gets a value measured for it.
local ROW_GAP_MERCHANT, ROW_GAP_BUYBACK = -8, -22

-- PAGINATION. Retail spreads it across the full inset width: the back arrow with its "Prev" caption
-- at the left, "Page 1 of 2" centred, the "Next" caption and forward arrow at the right. The client
-- ships those captions and anchors them on exactly retail's side of each arrow already, so they are
-- kept — only the two buttons move out to the edges.
local PAGENAV_Y  = 145               -- centre line of the arrow row, from the frame bottom
local PAGENAV_X  = 34                -- back arrow's centre; the forward arrow mirrors it

-- BOTTOM BAR. The band art, the repair/sell cluster on its left, the buyback slot after them (retail
-- keeps it in the bar, not floating above it), and the player's money in its own recess at the right.
-- Retail runs TWO rows down here: the button strip, and BELOW it the player's money in its own
-- recess at the right. Ours had both on one line, which is what pushed the money hard against the
-- buyback tile and left the bar reading as one crowded row instead of retail's two. The frame is 486
-- tall rather than 468 to make room -- that is retail's own proportion, 1.31 tall per unit wide,
-- measured off the reference shot (ours was 1.27).
local BAND_Y     = 36                -- bottom decoration band (61 tall, so it runs 36..97)
local BAND_INSET = 6                 -- how far the band is held off each side
-- The band art's recess is NOT centred within its 61px atlas slice: measured off the screenshots it
-- runs 41..85 from the frame bottom, 44 tall against the slice's 61. Centring the buttons on the
-- BAND's midpoint therefore leaves them high in the box you can actually see. 45 puts a 36px button
-- dead centre of 41..85.
local BUTTON_Y   = 45                -- the button row, centred in the band's VISIBLE recess
local BUTTON_GAP = 6                 -- between button tiles. Retail's spacing: the four sit tight
local TILE_BLEED = 4                 -- how far a button's recess bleeds past the button itself
local BAR_X      = 20                -- left edge of the first tile, in the band's LEFT compartment
-- The UI-Merchant-BotFrame art is not one strip: it is two recessed compartments, a wide one at the
-- left for the repair/sell cluster and a narrower one at the right, and retail puts the buyback tile
-- in the RIGHT one. Chaining it off the end of the cluster left it inside the left compartment with
-- the right one standing empty. Measured off the reference shot, retail's buyback tile starts at
-- 0.591 of the frame's width — just inside the right compartment, with the same ~5px padding
-- from its edge that BAR_X gives the cluster from the left one's.
-- Left-ish in the band's right compartment (213..352): 10 further in than the 218 that had the ring
-- overlapping the divider between the two compartments. That offset is the whole fix for "the slot
-- is sitting on the frame" — the collision was horizontal, not vertical.
--
-- The ring's BOUNDING BOX still starts a shade inside the divider (228 - 13.5 = 214.5 against 213),
-- and that is fine: the outer 13.5 is the frame art's transparent margin. What you see is the gold
-- border hugging the 37px opening, which clears the divider by about 11. Confusing the box for the
-- border is what made this look unfixable for several passes.
local BUYBACK_X  = 228               -- left edge of the buyback BUTTON, in the RIGHT compartment
local MONEY_Y    = 9                 -- player money, on its own row under the band

local function localTex(fdid)
  return (NE.tex.localFiles and NE.tex.localFiles[fdid]) or nil
end

-- ----------------------------------------------------------------------------
-- Outer chrome
-- ----------------------------------------------------------------------------

-- The classic art, by draw layer (verified against the 3.3.5a MerchantFrame.xml):
--   BACKGROUND  MerchantFramePortrait — KEPT, it is the only portrait this frame has
--   BORDER      four UNNAMED wooden quadrants (UI-Merchant-TopLeft/TopRight/BotLeft/BotRight),
--               plus MerchantNameText / MerchantPageText / MerchantRepairText
--   ARTWORK     BuybackFrameTopLeft/TopRight/BotLeft/BotRight — the buyback tab's own wooden
--               backdrop, re-shown by MerchantFrame_UpdateBuybackInfo
--   OVERLAY     MerchantFrameBottomLeftBorder / …RightBorder, re-shown by _UpdateMerchantInfo
-- The quadrants carry no names, so they are matched by texture PATH — the technique
-- modules/inspect uses on the unnamed inspect-pane art.
local CLASSIC_PATHS = { "ui%-merchant%-top", "ui%-merchant%-bot", "ui%-buyback%-" }

local function isClassicArt(r)
  local p = r.GetTexture and r:GetTexture()
  if type(p) ~= "string" then return false end
  p = p:lower()
  for _, pat in ipairs(CLASSIC_PATHS) do
    if p:find(pat) then return true end
  end
  return false
end

-- Hide the client's classic panel art. Cheap enough (a few dozen regions) to re-run on every
-- update, which is what keeps FrameXML's per-tab re-shows from putting the wood back.
local function hideClassicChrome()
  local f = _G.MerchantFrame
  if not f then return end

  -- MerchantFramePortrait is a BACKGROUND texture, and PC.HideClassicChrome's walk would take it
  -- with anything else on that layer. We KEEP it: buildModernChrome seats it in the metal ring.
  if _G.MerchantFramePortrait then PC.Keep(f, _G.MerchantFramePortrait) end

  PC.HideClassicChrome(f)

  -- The BORDER and ARTWORK quadrants. PanelChrome's walk only covers BACKGROUND (which is all a
  -- ButtonFrameTemplate frame needs) — this client paints its whole panel a layer up, which is why
  -- the wood survived the first pass. Match on path so our own BORDER-layer TopTileStreaks band,
  -- which lives on this same frame, is never caught by it.
  for _, layer in ipairs({ "BORDER", "ARTWORK" }) do
    NE.FrameUtil.ForEachRegion(f, "Texture", layer, function(r)
      if r ~= f._neTopTileStreaks and isClassicArt(r) then r:Hide() end
    end)
  end

  -- The classic title FontString. Its text is the value we mirror into the modern title band, so
  -- it stays populated by FrameXML — it just stops drawing.
  if _G.MerchantNameText then _G.MerchantNameText:Hide() end

  -- Named leftovers. All optional: any this client does not define simply skips.
  for _, name in ipairs({
    "MerchantRepairText",                 -- "Repair" caption; retail's modern layout has none
    "MerchantFrameBottomLeftBorder",      -- 2-piece classic bottom band, replaced by _neBotFrame
    "MerchantFrameBottomRightBorder",
    -- The buyback tab's wooden backdrop, by name as well as by the path walk above: these four are
    -- Shown again by every _UpdateBuybackInfo, so the belt is worth the braces.
    "BuybackFrameTopLeft", "BuybackFrameTopRight",
    "BuybackFrameBotLeft", "BuybackFrameBotRight",
  }) do
    local t = _G[name]
    if t and t.Hide then t:Hide() end
  end
end

-- The window's stone body — the same three lines every other window in this set paints for itself
-- (modules/inspect/InspectFrame.lua paintBody, modules/guild/Window.lua buildChrome,
-- modules/auctionhouse/Window.lua, modules/encounterjournal). PanelChrome's ApplyBodyFill does build
-- an f.Bg, but on its own default rect — TOPLEFT(1,-4) to BOTTOMRIGHT(-1,2), which reaches up behind
-- the title bar and stops short of the bottom edge. Every window that reads as stone rather than as
-- a slab re-anchors it to start just under the title and run flush to the frame's bottom-right, so
-- the merchant does the same rather than being the one window with its own geometry.
--
-- Flush on the left (0), not guild's 4px inset: that inset is for a border whose opaque coverage
-- falls inside the frame's nominal edge, and this window wears the same PortraitFrameTemplate metal
-- the inspect window does, where a 4 left a visible strip of bare frame down the left side.
local ROCK_FDID = 374155

local function paintBody(f)
  local bg = f.Bg
  if not bg then
    bg = f:CreateTexture(nil, "BACKGROUND")
    f.Bg = bg
  end
  local rockPath = NE.tex and NE.tex.localFiles and NE.tex.localFiles[ROCK_FDID]
  bg:SetTexture(rockPath or ROCK_FDID, "REPEAT", "REPEAT")
  bg:SetHorizTile(true)
  bg:SetVertTile(true)
  bg:SetTexCoord(0, 1, 0, 1)
  bg:SetVertexColor(1, 1, 1)
  bg:ClearAllPoints()
  bg:SetPoint("TOPLEFT",     f, "TOPLEFT",     0, -21)
  bg:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0,   0)
  bg:Show()
end

local function applyModernChrome()
  local f = _G.MerchantFrame
  if not f then return end
  -- Rock body fill + the metal nineslice + the TopTileStreaks band under the title.
  -- PanelChrome BUILDS f.Bg / f.NineSlice here (the 3.3.5a frame carries neither).
  PC.ApplyModernChrome(f)
  paintBody(f)   -- over the top of ApplyBodyFill's rect; see paintBody's header
end

-- Retail's single UI-Merchant-BotFrame band (332x61 at BOTTOMLEFT(1,26)), in place of the classic
-- 2-piece bottom border hidden above. Merchant tab only — see postMerchantUpdate.
local function buildBottomBand()
  local f = _G.MerchantFrame
  if not f or f._neBotFrame then return end
  local t = f:CreateTexture(nil, "OVERLAY")
  if not NE.tex.SetAtlas(t, "ui-merchant-botframe", false) then return end
  t:SetHeight(61)
  t:SetPoint("BOTTOMLEFT",  f, "BOTTOMLEFT",   BAND_INSET, BAND_Y)
  t:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -BAND_INSET, BAND_Y)
  f._neBotFrame = t
end

-- ----------------------------------------------------------------------------
-- Rows
-- ----------------------------------------------------------------------------

-- Find a row texture by NAME first and by texture PATH as a fallback, so a client that names the
-- regions differently still gets reskinned instead of silently keeping the wood. (Path matching is
-- the same technique modules/inspect uses on the unnamed inspect-pane quadrants.)
local function rowTexture(row, prefix, suffix, pathPattern)
  local t = _G[prefix .. suffix]
  if t then return t end
  if not row then return nil end
  return NE.FrameUtil.FindRegion(row, "Texture", function(r)
    local p = r.GetTexture and r:GetTexture()
    return type(p) == "string" and p:lower():find(pathPattern) ~= nil
  end)
end

-- One row's slot art. Retail's stack, all three pieces re-pointed at our shipped retail BLPs (the
-- file paths are the same on both clients; the art behind them is not):
--   SlotTexture (UI-EmptySlot)               64x64 TOPLEFT(-13,13) — the recess
--   ItemButton NormalTexture (UI-Quickslot2) 64x64 CENTER(0,-1)    — the ring
--   NameFrame (UI-Merchant-LabelSlots)       tinted 50% grey       — the label plate
local function reskinSlot(prefix, showLabel)
  local row = _G[prefix]

  local slot = rowTexture(row, prefix, "SlotTexture", "ui%-emptyslot")
  local recess = localTex(EMPTY_SLOT_FDID)
  if slot then
    if recess then slot:SetTexture(recess) end
    slot:Show()
  end

  local ib   = _G[prefix .. "ItemButton"]
  local nrm  = (ib and ib.GetNormalTexture and ib:GetNormalTexture())
               or _G[prefix .. "ItemButtonNormalTexture"]
  local ring = localTex(SLOT_RING_FDID)
  if nrm and ring then
    nrm:SetTexture(ring)
    nrm:ClearAllPoints()
    nrm:SetSize(64, 64)
    nrm:SetPoint("CENTER", ib, "CENTER", 0, -1)
  end

  -- The single buyback slot (showLabel=false) keeps its plate HIDDEN, as retail does; ours clipped
  -- the frame bottom there.
  local nameFrame = rowTexture(row, prefix, "NameFrame", "ui%-merchant%-labelslots")
  if nameFrame then
    if showLabel then
      local plate = localTex(LABEL_PLATE_FDID)
      if plate then nameFrame:SetTexture(plate) end
      nameFrame:SetVertexColor(0.5, 0.5, 0.5, 1)
      nameFrame:Show()
    else
      nameFrame:Hide()
    end
  end
end

-- The buyback slot sits in the button bar now, so it wears the bar's proportions: reskinSlot gives
-- every row the grid's 64px recess and ring, which beside a row of 44px tiles reads as a mistake.
-- The buyback tile is an ITEM SLOT and wears the item frame: UI-EmptySlot behind the icon and the
-- UI-Quickslot2 ring around it, both at their native 64 against a 37px button, exactly as every grid
-- row wears them. reskinSlot already dresses it that way; nothing here undoes that.
--
-- The 64 is a BOUNDING BOX, not the visible extent — most of it is the frame art's transparent
-- margin, and the gold border hugs the 37px opening. Reading 64 as the visible size is what sent the
-- earlier attempts wrong: it looked like the ring could not fit the band's 44-tall recess, so the
-- ring got shrunk (its opening then landed ON the icon), then the whole tile got scaled down with it
-- (the icon went to 25 and read small), then the frame was dropped altogether. None of that was
-- needed. Vertically the visible ring sits inside the recess; the only real collision was
-- HORIZONTAL, against the divider between the band's two compartments, and moving the tile right
-- clears it.
local BUYBACK_BTN = 37               -- native ItemButton, which is what the 64px ring is drawn for
local BUYBACK_Y   = 44               -- centres it in the band's 41..85 visible recess

local function fitBuybackIcon()
  local ib = _G.MerchantBuyBackItemItemButton
  if not ib then return end
  local icon = _G.MerchantBuyBackItemItemButtonIconTexture or ib.icon
  if not icon then return end
  -- SetAllPoints(button) -- the identical call reskinRepairIcon makes, so the tile's contents are
  -- the same size as every other tile's by construction rather than by arithmetic.
  icon:ClearAllPoints()
  icon:SetAllPoints(ib)
end

local function fitBuybackQualityGlow()
  local ib = _G.MerchantBuyBackItemItemButton
  local glow = ib and ib.__DragonUI_QualityOverlay
  if not glow then return end
  -- DragonUI's OWN ratio, 1.7x the button. Not a smaller number: this texture is
  -- UI-ActionButton-Border in ADD blend, a soft halo whose visible energy is in its outer portion,
  -- so shrinking it to just past the tile edge (1.25x was tried) does not make a tidy frame — it
  -- clips off the part you can actually see and the rarity cue vanishes. The only thing that needs
  -- fixing here is the RATIO being computed from the wrong width: DragonUI sizes the overlay once,
  -- from whatever the button measured at creation, and this tile is resized after that.
  local n = (ib:GetWidth() or 37) * 1.7
  if math.abs((glow:GetWidth() or 0) - n) < 0.5 then return end
  glow:SetSize(n, n)
end

local function fitBuybackToBar()
  local ib = _G.MerchantBuyBackItemItemButton
  if not ib then return end

  ib:SetSize(BUYBACK_BTN, BUYBACK_BTN)
  -- The ROW is 153 wide for a name and price this tile does not show, and that width otherwise
  -- reaches across the band and under the money recess.
  local row = _G.MerchantBuyBackItem
  if row then row:SetSize(BUYBACK_BTN, BUYBACK_BTN) end

  fitBuybackIcon()

  -- The recess and ring are reskinSlot's, at their native 64, untouched. See the header.
  local slot = _G.MerchantBuyBackItemSlotTexture
  if slot then slot:Show() end
  local nrm = ib.GetNormalTexture and ib:GetNormalTexture()
  if nrm then nrm:Show() end
end

local function reskinAllSlots()
  for i = 1, BUYBACK_PER_PAGE do
    if _G["MerchantItem" .. i] then reskinSlot("MerchantItem" .. i, true) end
  end
  if _G.MerchantBuyBackItem then reskinSlot("MerchantBuyBackItem", false) end
end

-- The quest-starter "!" bang. 3.3.5a's plain ItemButtonTemplate ships no IconQuestTexture (unlike
-- the bag/bank ContainerFrameItemButtonTemplate), so we add retail's region: OVERLAY, 37x38,
-- anchored TOP. Vendor rows only — retail never bangs the buyback slot.
local QUEST_BANG_TEX = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\QuestBang"
local function addQuestBang(prefix)
  local ib = _G[prefix .. "ItemButton"]
  if not ib or ib.IconQuestTexture then return end
  local t = ib:CreateTexture(nil, "OVERLAY")
  t:SetTexture(QUEST_BANG_TEX)
  t:SetSize(37, 38)
  t:SetPoint("TOP", ib, "TOP", 0, 0)
  t:Hide()
  ib.IconQuestTexture = t
end

local function addQuestBangs()
  for i = 1, BUYBACK_PER_PAGE do
    if _G["MerchantItem" .. i] then addQuestBang("MerchantItem" .. i) end
  end
end

-- Single-line row names. The Name FontStrings default to wordwrap=true, so a long item name wraps
-- to a second line that spills past the 30px row — worst on the buyback tab, whose 12 reused rows
-- are vertically compressed. SetWordWrap(false) on a width-clamped FontString gives engine tail
-- truncation with "..." instead.
local function clampName(nm, width)
  if not nm then return end
  if nm.SetWordWrap then nm:SetWordWrap(false) end
  if nm.SetMaxLines then nm:SetMaxLines(1) end
  if width then nm:SetWidth(width) end
end

-- ----------------------------------------------------------------------------
-- Bottom button cluster
-- ----------------------------------------------------------------------------

-- Repair icons: this client draws every repair state off one classic sheet; retail uses three
-- distinct 256x256 spell-icon atlases. Replace each button's icon texture.
-- Each repair button's icon region. NOT `buttonName .. "Icon"` — that guess is wrong for two of the
-- three: the XML names them MerchantRepairAllIcon (not …ButtonIcon) and MerchantGuildBankRepair
-- ButtonIcon, and MerchantRepairItemButton's is anonymous. A draw-layer fallback is not safe either,
-- because a Button's own Normal/Pushed textures are regions of the same button and can share the
-- layer — retexturing one of those instead leaves the real icon untouched, which is exactly the
-- "icons not showing properly" failure. So: the real global where there is one, and otherwise the
-- region carrying the classic sheet's path, which is exact.
local REPAIR_ICONS = {
  { button = "MerchantRepairAllButton",       icon = "MerchantRepairAllIcon",            atlas = "spellicon-256x256-repairall"      },
  { button = "MerchantRepairItemButton",      icon = nil,                                atlas = "spellicon-256x256-repair"         },
  { button = "MerchantGuildBankRepairButton", icon = "MerchantGuildBankRepairButtonIcon", atlas = "spellicon-256x256-repairallguild", size = 36 },
}

local function repairIconRegion(btn, globalName)
  if globalName and _G[globalName] then return _G[globalName] end
  return NE.FrameUtil.FindRegion(btn, "Texture", function(r)
    local p = r.GetTexture and r:GetTexture()
    return type(p) == "string" and p:lower():find("ui%-merchant%-repairicons") ~= nil
  end)
end

local function reskinRepairIcons()
  for _, spec in ipairs(REPAIR_ICONS) do
    local btn = _G[spec.button]
    -- The guild-bank repair button is 32x32 in the XML where the other two are 36x36, which reads as
    -- a dent in the row whenever it IS shown. Retail's four tiles are uniform.
    if btn and spec.size then btn:SetSize(spec.size, spec.size) end
    local icon = btn and repairIconRegion(btn, spec.icon)
    if icon and NE.tex.SetAtlas(icon, spec.atlas, false) then
      -- Retail's XML gives these no size and no anchor, i.e. fill the parent (36x36). The recess BG
      -- added by addRetailSlotBgs masks the chrome behind the icon's feathered alpha edges.
      icon:ClearAllPoints()
      icon:SetAllPoints(btn)
      btn._neIcon = icon
    end
  end
end

-- Retail gives each repair/sell button a 64x64 UI-EmptySlot recess behind the icon.
local function addRetailSlotBg(buttonName)
  local btn = _G[buttonName]
  if not btn or btn._neSlotBg then return end
  local path = localTex(EMPTY_SLOT_FDID)
  if not path then return end
  local bg = btn:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture(path)
  -- Sized to the BUTTON, not to the sheet's native 64. Retail's bar is a row of tiles barely wider
  -- than their icons; a fixed 64 recess behind a 36 button spills 28px past it, so at any sane
  -- spacing the neighbouring recesses merge into one smear instead of reading as separate tiles.
  bg:SetPoint("TOPLEFT",     btn, "TOPLEFT",     -TILE_BLEED,  TILE_BLEED)
  bg:SetPoint("BOTTOMRIGHT", btn, "BOTTOMRIGHT",  TILE_BLEED, -TILE_BLEED)
  btn._neSlotBg = bg
end

local function addRetailSlotBgs()
  addRetailSlotBg("MerchantRepairAllButton")
  addRetailSlotBg("MerchantRepairItemButton")
  addRetailSlotBg("MerchantGuildBankRepairButton")
  addRetailSlotBg("NE_MerchantSellAllJunkButton")
end

-- Retail's MerchantFrame_UpdateRepairButtons is the authority on where the bottom buttons sit, and
-- it repositions the sell-junk button in EVERY branch (never the static XML default) — so ours has
-- to follow the same logic or it lands on top of a repair button. Retail's numbers, on a frame that
-- is 336 wide on both clients:
--   can repair + guild bank : RepairAll BR(96,33),  RepairItem L(-9), SellJunk RIGHT of RepairAll.LEFT(128,0)
--   can repair, no guild    : RepairAll BR(118,33), RepairItem L(-8), SellJunk RIGHT of RepairAll.LEFT(80,0)
--   cannot repair           : SellJunk BOTTOMRIGHT -> MerchantFrame BOTTOMRIGHT(-148,33)
local function postRepairButtons()
  local f = _G.MerchantFrame
  if not f or f.selectedTab ~= 1 then return end
  stats.repair = stats.repair + 1
  local sell    = _G.NE_MerchantSellAllJunkButton
  local buyback = _G.MerchantBuyBackItem

  -- The buyback slot goes in the band's RIGHT compartment, at a fixed offset from the frame — NOT
  -- chained off the end of the repair/sell cluster, which is what kept it inside the left compartment
  -- and left the right one standing empty. Placed FIRST, before the branch below can bail out, since
  -- its position no longer depends on how many repair buttons the vendor happens to offer — which is
  -- also how retail behaves.
  if buyback then
    buyback:ClearAllPoints()
    buyback:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", BUYBACK_X, BUYBACK_Y)
  end

  -- `last` is whatever the rightmost button of the repair/sell cluster ended up being.
  local last

  if CanMerchantRepair and CanMerchantRepair() then
    local repAll  = _G.MerchantRepairAllButton
    local repItem = _G.MerchantRepairItemButton
    if not (repAll and repItem) then return end
    local guild = CanGuildBankRepair and CanGuildBankRepair()

    -- Left to right: repair-one, repair-all, (guild-bank repair), sell-junk. Retail's own order.
    --
    -- THE ANCHOR DIRECTION HERE IS LOAD-BEARING. MerchantFrame_UpdateRepairButtons re-asserts
    --     MerchantRepairItemButton:SetPoint("RIGHT", MerchantRepairAllButton, "LEFT", ...)
    -- on every single update, so repair-one depends on repair-all and never the reverse. Anchoring
    -- repAll off repItem to walk the row left-to-right makes that line a CIRCULAR anchor, and it
    -- throws -- which aborts _UpdateMerchantInfo, and with it every post-hook registered after the
    -- point it died, silently stranding this module's whole chrome sync. So repair-all carries the
    -- absolute position and repair-one hangs off it, the client's way round; the row is still laid
    -- out left to right, just measured from the second tile instead of the first.
    local w = (repItem:GetWidth() or 36) + BUTTON_GAP
    repAll:ClearAllPoints()
    repAll:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", BAR_X + w, BUTTON_Y)
    repItem:ClearAllPoints()
    repItem:SetPoint("RIGHT", repAll, "LEFT", -BUTTON_GAP, 0)
    last = repAll

    if guild then
      local gb = _G.MerchantGuildBankRepairButton
      if gb then
        -- Also the client's own direction (guild-bank repair hangs off repair-all), so it is safe
        -- to restate.
        gb:ClearAllPoints()
        gb:SetPoint("LEFT", repAll, "RIGHT", BUTTON_GAP, 0)
        last = gb
      end
    end

    if sell then
      sell:ClearAllPoints()
      sell:SetPoint("LEFT", last, "RIGHT", BUTTON_GAP, 0)
      last = sell
    end
  elseif sell then
    -- No repairs here, so sell-junk leads the bar. Nothing in FrameXML anchors to our own buttons,
    -- so their direction is free.
    sell:ClearAllPoints()
    sell:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", BAR_X, BUTTON_Y)
    last = sell
  end

end

-- ----------------------------------------------------------------------------
-- Insets, page nav, close button
-- ----------------------------------------------------------------------------

-- Retail's recessed panel behind the item grid and the pagination row. The client has nothing like
-- it — its wooden art implied the recess — so it is built. It has to sit BELOW the rows: a child
-- frame defaults to its parent's level + 1, which is where the row frames already are, and same-level
-- siblings draw in creation order, so a panel built after them would cover them. applyLayout lifts
-- the rows clear of it.
-- The dark recess fill. An InsetFrameTemplate nineslice is BORDER pieces ONLY — it draws the thin
-- gold trim and nothing inside it — so on its own it outlines a recess without sinking one, which
-- is why the grid read as the same stone as the frame instead of retail's darker panel.
--
-- Colour and placement are the addon's existing ones (modules/cooldownviewer/SettingsPanel.lua): a
-- BACKGROUND texture at subLevel 1. THE SUBLEVEL IS THE POINT — f.Bg spans the whole frame at
-- subLevel 0, so a fill at the default or below draws underneath the body stone and is never once
-- visible. PC.Keep guards it from hideClassicChrome's BACKGROUND walk, which hides everything but
-- f.Bg on every update.
--
-- The recess is the ROCK SHEET, TINTED — not a colour swatch. A flat SetTexture(r,g,b,a) was what
-- made the panel read as dead grey: at 0.92 alpha the stone underneath contributes 8%, and its grain
-- is compressed along with it to a fraction of a percent, i.e. invisible. Painting the same tiled
-- 374155 the body uses and setting the TONE through SetVertexColor keeps the grain, because then the
-- grain IS the texture rather than something trying to show through it.
--
-- These are vertex multipliers on that sheet, so they read directly against PC.BODY_TINT's 0.32 for
-- the body: below it is a recess, above it is a lit panel. The merchant tab sits well under (its grid
-- covers most of it anyway); the buyback tab sits above, which is where retail's mid-grey buyback
-- panel is, and where the merchant tab's value looked far too heavy.
local INSET_TONE          = { 0.22, 0.22, 0.23 }   -- merchant tab: just under the body's 0.32
local INSET_TONE_BUYBACK  = { 0.85, 0.85, 0.87 }   -- buyback tab: the sheet near its own brightness

local function setInsetTone(t, tone)
  if t and t._neTone ~= tone then
    t._neTone = tone
    t:SetVertexColor(tone[1], tone[2], tone[3])
  end
end

local function insetFill(f, key, rect, tone)
  if f[key] then return f[key] end
  local t = f:CreateTexture(nil, "BACKGROUND", nil, 1)
  t:SetPoint("TOPLEFT",     rect, "TOPLEFT",     0, 0)
  t:SetPoint("BOTTOMRIGHT", rect, "BOTTOMRIGHT", 0, 0)
  local rockPath = NE.tex.localFiles and NE.tex.localFiles[ROCK_FDID]
  if rockPath then
    t:SetTexture(rockPath, "REPEAT", "REPEAT")
    t:SetHorizTile(true)
    t:SetVertTile(true)
    setInsetTone(t, tone or INSET_TONE)
  else
    t:SetTexture(0.05, 0.05, 0.06, 0.92)   -- degrade: sheet not shipped, so a flat recess
  end
  if PC.Keep then PC.Keep(f, t) end
  f[key] = t
  return t
end

local function buildGridInset()
  local f = _G.MerchantFrame
  if not f or f._neGridInset then return end
  local inset = NE.nineslice.AttachInset(f, INSET_TL_X, INSET_TL_Y, INSET_BR_X, INSET_BR_Y)
  if not inset then return end
  inset:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
  f._neGridInset = inset
  insetFill(f, "_neGridInsetBg", inset)
end

-- DOWNPORT: there is no MerchantMoneyInset on this client (that is an Era/retail frame) — the
-- player's money simply floats on the classic bottom art. Build retail's recess for it instead.
local function buildMoneyInset()
  local f = _G.MerchantFrame
  local money = _G.MerchantMoneyFrame
  if not (f and money) or f._neMoneyInset then return end
  local inset = CreateFrame("Frame", nil, f)
  inset:SetPoint("TOPLEFT",     money, "TOPLEFT",     -8, 6)
  inset:SetPoint("BOTTOMRIGHT", money, "BOTTOMRIGHT",   6, -6)
  inset:EnableMouse(false)
  inset:SetFrameLevel((f:GetFrameLevel() or 1) + 1)
  NE.nineslice.ApplyLayout(inset, "InsetFrameTemplate")
  f._neMoneyInset = inset
  insetFill(f, "_neMoneyInsetBg", inset)
end

-- Re-anchor the frame's furniture onto the geometry at the top of this file. Pure SetPoint/SetSize
-- on an unprotected frame, and nothing in FrameXML re-anchors any of it, so this runs once at login
-- — early enough that the first ShowUIPanel measures the final width.
-- Nudge the window off the screen edge. On the FRAME's attributes, not in UIPanelWindows —
-- tainting that table blocks the first panel open in combat (DragonUI
-- modules/characterpanel/chrome.lua:126). That has a catch of its own: GetUIPanelWindowInfo copies
-- the whole UIPanelWindows row onto the frame the first time it is asked and only then treats
-- attributes as authoritative, so setting xoffset alone would just be overwritten by that copy —
-- restate the row's other fields here and mark it defined, which is the documented way to opt a
-- frame out of the table. pushable stays 0, the client's own value: a vendor window is the one you
-- just opened, so it should keep the left slot.
local function applyPanelLayout(f)
  if not f.SetAttribute then return end
  if f:GetAttribute("UIPanelLayout-xoffset") == PANEL_X_NUDGE then return end
  f:SetAttribute("UIPanelLayout-area",     "left")
  f:SetAttribute("UIPanelLayout-pushable", 0)
  f:SetAttribute("UIPanelLayout-xoffset",  PANEL_X_NUDGE)
  f:SetAttribute("UIPanelLayout-enabled",  true)
  f:SetAttribute("UIPanelLayout-defined",  true)   -- last: it seals the row above
  if f:IsShown() and UpdateUIPanelPositions then UpdateUIPanelPositions(f) end
end

local function applyLayout()
  local f = _G.MerchantFrame
  if not f then return end

  f:SetSize(PANEL_W, PANEL_H)
  applyPanelLayout(f)
  -- The client insets the drag region by (0,35,0,61) to skip its wooden art's transparent margins.
  -- Our chrome fills the frame, so the whole panel is draggable again.
  if f.SetHitRectInsets then f:SetHitRectInsets(0, 0, 0, 0) end

  -- The whole 2x5 grid hangs off row 1; rows 3/5/7/9 chain down from it and the even rows sit to
  -- their right, so this one anchor places all twelve.
  local row1 = _G.MerchantItem1
  if row1 then
    row1:ClearAllPoints()
    row1:SetPoint("TOPLEFT", f, "TOPLEFT", GRID_X, GRID_Y)
  end

  -- Pagination, spread across the inset the way retail does it: back arrow and its "Prev" caption at
  -- the left, the page count centred, "Next" and the forward arrow at the right.
  local prev, nxt = _G.MerchantPrevPageButton, _G.MerchantNextPageButton
  if prev then
    prev:ClearAllPoints()
    prev:SetPoint("CENTER", f, "BOTTOMLEFT", PAGENAV_X, PAGENAV_Y)
  end
  if nxt then
    nxt:ClearAllPoints()
    nxt:SetPoint("CENTER", f, "BOTTOMRIGHT", -PAGENAV_X, PAGENAV_Y)
  end
  local pageText = _G.MerchantPageText
  if pageText then
    pageText:ClearAllPoints()
    pageText:SetPoint("CENTER", f, "BOTTOMLEFT", PANEL_W / 2, PAGENAV_Y)
    pageText:SetWidth(140)
    pageText:SetJustifyH("CENTER")
  end

  -- Player money, bottom-right inside the decoration band.
  local money = _G.MerchantMoneyFrame
  if money then
    money:ClearAllPoints()
    money:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -16, MONEY_Y)
  end

  -- Lift everything that lives inside the recessed panel above it. The panel is a child frame at
  -- parent+1, which is exactly where these already sit, and same-level siblings draw in creation
  -- order — so without this the panel (built later) would paint straight over the grid.
  local above = (f:GetFrameLevel() or 1) + 4
  for i = 1, BUYBACK_PER_PAGE do
    local row = _G["MerchantItem" .. i]
    if row then row:SetFrameLevel(above) end
  end
  if _G.MerchantBuyBackItem then _G.MerchantBuyBackItem:SetFrameLevel(above) end
  if prev then prev:SetFrameLevel(above) end
  if nxt  then nxt:SetFrameLevel(above)  end
  if money then money:SetFrameLevel(above) end
end

-- Page nav (32x32). The geometry is already retail-correct here (the same vanilla XML); only the
-- ART differs, since this client's data serves the classic/low-res versions of those file paths.
-- So keep the native layout and retexture each piece from our shipped retail BLPs.
local PAGE_BTN_TEX = {
  MerchantPrevPageButton = { up = 130869, down = 130868, disabled = 130867 },
  MerchantNextPageButton = { up = 130866, down = 130865, disabled = 130864 },
}
local PAGE_BG_FDID     = 130822
local PAGE_HILITE_FDID = 130757

local function reskinPageNav(btnName)
  local btn = _G[btnName]
  local set = PAGE_BTN_TEX[btnName]
  if not (btn and set) then return end

  local function retexture(getter, fdid, blend)
    local path = localTex(fdid)
    local t = path and btn[getter] and btn[getter](btn)
    if not t then return end
    t:SetTexture(path)
    if blend then t:SetBlendMode(blend) end
  end

  retexture("GetNormalTexture",    set.up)
  retexture("GetPushedTexture",    set.down)
  retexture("GetDisabledTexture",  set.disabled)
  retexture("GetHighlightTexture", PAGE_HILITE_FDID, "ADD")

  -- The anonymous BACKGROUND plate (UI-PageButton-Background, 32x32 CENTER(0,1)).
  local bgPath = localTex(PAGE_BG_FDID)
  if bgPath then
    NE.FrameUtil.ForEachRegion(btn, "Texture", "BACKGROUND", function(r)
      r:SetTexture(bgPath)
      r:Show()
    end)
  end

  -- The "Prev"/"Next" captions beside each arrow are KEPT: retail labels its arrows the same way,
  -- and the client already anchors each caption on retail's side of its button (Prev to the right of
  -- the back arrow, Next to the left of the forward one). They only looked wrong while the two
  -- buttons were still huddled under column 1.
end

local function reskinPageNavButtons()
  reskinPageNav("MerchantPrevPageButton")
  reskinPageNav("MerchantNextPageButton")
end

-- The frame's UIPanelCloseButton, by name and then structurally. The structural pass matches the
-- template's own Normal texture, so it finds the button whatever the client called it — a native
-- classic X sitting on modern chrome is exactly the mismatch this reskin exists to remove.
local function findCloseButton(f)
  if _G.MerchantFrameCloseButton then return _G.MerchantFrameCloseButton end
  for _, child in ipairs({ f:GetChildren() }) do
    if child.GetObjectType and child:GetObjectType() == "Button" and child.GetNormalTexture then
      local t = child:GetNormalTexture()
      local p = t and t.GetTexture and t:GetTexture()
      if type(p) == "string" and p:lower():find("ui%-panel%-minimizebutton") then return child end
    end
  end
  return nil
end

local function modernizeCloseButton()
  local f = _G.MerchantFrame
  if not f then return end
  -- DOWNPORT: the 3.3.5a frame has no `f.CloseButton` field — the button is a named/anonymous child.
  -- Adopt it onto the field so PanelChrome reskins the REAL button instead of leaving it native
  -- beside our chrome.
  f.CloseButton = f.CloseButton or findCloseButton(f)
  if not f.CloseButton then return end
  -- frameLevelBump is not optional here: PanelChrome only lifts a close button it BUILT, and the
  -- nineslice (frame+1) and title band (frame+11) both outrank a plain child button, so an adopted
  -- one renders with its X hidden under the chrome and only its highlight bleeding through.
  PC.ModernizeCloseButton(f, { frameLevelBump = 20 })
end

-- ----------------------------------------------------------------------------
-- Per-update sync
-- ----------------------------------------------------------------------------

-- NOTE: these two live ABOVE their callers deliberately. A `local function` declared after a call
-- site is not in scope there -- the name resolves to a nil global and throws at call time, and
-- inside a hooksecurefunc post-hook that kills the rest of the chain. luac and luaparse both
-- accept it; qa/staticcheck.sh now greps for it.

-- Rows 3/5/7/9 are re-anchored to a -15 pitch by _UpdateBuybackInfo (and back to -8 by
-- _UpdateMerchantInfo) -- the client stretching its six-row buyback grid down into the dead space
-- its own layout had at the bottom. We do not have that space: the grid sits in a recessed panel
-- sized for the merchant tab, and at -15 the last row hangs about 20px out through the bottom of it.
-- Retail's buyback grid is evenly spaced with its merchant grid, so put the pitch back.
local function setRowPitch(gap)
  local prev = _G.MerchantItem1
  for _, i in ipairs({ 3, 5, 7, 9 }) do
    local row = _G["MerchantItem" .. i]
    if not (row and prev) then return end
    row:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, gap)
    prev = row
  end
  -- Row 11 chains off row 9 and is the buyback tab's last pair, so it takes the same gap.
  local row11, row9 = _G.MerchantItem11, _G.MerchantItem9
  if row11 and row9 then
    row11:ClearAllPoints()
    row11:SetPoint("TOPLEFT", row9, "BOTTOMLEFT", 0, gap)
  end
end

-- The recess follows the tab: taller on buyback, where nothing sits under the grid.
local function setInsetForTab(f)
  local inset = f._neGridInset
  if not inset then return end
  local buyback = (f.selectedTab == 2)
  local y = buyback and INSET_BR_Y_BUYBACK or INSET_BR_Y
  if inset._neBottom == y then return end
  inset._neBottom = y
  inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", INSET_BR_X, y)
  -- ...and the tone with it. The two tabs want different values, not one compromise: the merchant
  -- grid is full of item plates so its recess barely shows and wants to stay dark, while the buyback
  -- grid is mostly empty slots, so the recess IS what you see and reads far too heavy at the same
  -- value. Retail colours them separately for the same reason.
  setInsetTone(f._neGridInsetBg, buyback and INSET_TONE_BUYBACK or INSET_TONE)
end

-- FrameXML's updaters actively re-show and re-write elements we replaced: the NPC name goes to
-- MerchantNameText, the face to MerchantFramePortrait, the classic bottom borders come back on the
-- merchant tab, and the repair caption toggles. This runs after every update and puts our version
-- back. Idempotent — safe to call from more than one hook.
local function postMerchantUpdate()
  local f = _G.MerchantFrame
  if not f or not f._neBuilt then return end
  stats.update = stats.update + 1
  stats.tab = f.selectedTab

  -- Re-clear the classic art (name-independent walk + the named leftovers).
  hideClassicChrome()
  setInsetForTab(f)
  -- ...and re-assert the body. hideClassicChrome walks the BACKGROUND layer hiding everything but
  -- f.Bg, so the body is the one texture on that layer whose survival is load-bearing; re-painting
  -- it here costs nothing and means no future change to that walk can leave the window bare.
  if f.Bg then f.Bg:Show() end

  -- Mirror FrameXML's NPC-name write into our title band. MerchantNameText already holds the value
  -- the update just set: the vendor's name on the merchant tab, MERCHANT_BUYBACK on the buyback tab.
  if f.Title and _G.MerchantNameText then
    f.Title:SetText(_G.MerchantNameText:GetText() or "")
  end

  -- Portrait. FrameXML swaps in the buyback icon on tab 2 and the NPC face on tab 1; our cutout is
  -- already applied to the same texture, so only the content is re-driven here.
  local p = _G.MerchantFramePortrait
  if p then
    p:Show()   -- kept via PC.Keep, but re-assert: an update can hide it
    if f.selectedTab == 2 then
      p:SetTexture("Interface\\MerchantFrame\\UI-BuyBack-Icon")
      p:SetTexCoord(0, 1, 0, 1)
    elseif SetPortraitTexture then
      -- "NPC" uppercase, which is what FrameXML itself passes. The token is case-sensitive here
      -- (the 1.15 source carries the same warning), and a miss leaves the buyback purse in place.
      SetPortraitTexture(p, "NPC")
    end
  end

  local onMerchant = (f.selectedTab == 1)

  -- Our bottom band and button cluster are MERCHANT-tab only: the buyback grid reflows down into
  -- that region, and FrameXML clears the whole bottom there.
  if f._neBotFrame then
    if onMerchant then f._neBotFrame:Show() else f._neBotFrame:Hide() end
  end
  local sell = _G.NE_MerchantSellAllJunkButton
  if sell then
    if onMerchant then sell:Show() else sell:Hide() end
  end

  -- The buyback slot. _UpdateBuybackInfo hides it, and _UpdateMerchantInfo only re-Shows it inside
  -- `if (buybackName)` -- never in the else -- so coming back from the buyback tab with nothing to
  -- buy back leaves the slot hidden for the rest of the session. Retail always keeps it on the
  -- merchant tab and just desaturates its undo arrow when it is empty, which is what BuybackUndo
  -- already does, so show it unconditionally here.
  local buyback = _G.MerchantBuyBackItem
  if buyback then
    if onMerchant then buyback:Show() else buyback:Hide() end
  end
  if not onMerchant then
    -- On the merchant tab FrameXML owns the repair buttons' CanMerchantRepair gate; only force them
    -- down on buyback, where it hides the ones it knows about but not the guild-bank one.
    for _, name in ipairs({
      "MerchantGuildBankRepairButton", "MerchantRepairAllButton", "MerchantRepairItemButton",
    }) do
      local b = _G[name]
      if b then b:Hide() end
    end
  end

  -- Re-assert single-line truncation every update: FrameXML re-sets the row name fonts, which
  -- undoes the login-time SetWordWrap(false). 84px cuts a long name cleanly ("Chipped Boar...")
  -- where the native 100px box leaves a dangling partial word before the ellipsis.
  for i = 1, BUYBACK_PER_PAGE do
    clampName(_G["MerchantItem" .. i .. "Name"], 84)
  end
  -- The buyback slot is a bare tile in the button bar now, the way retail draws it -- no name and no
  -- price beside it (both are still in its tooltip). _UpdateMerchantInfo writes the name and Shows
  -- the money frame on every update, so this has to be re-asserted here rather than done once.
  if _G.MerchantBuyBackItemName then _G.MerchantBuyBackItemName:Hide() end
  if _G.MerchantBuyBackItemMoneyFrame then _G.MerchantBuyBackItemMoneyFrame:Hide() end
  fitBuybackIcon()
  fitBuybackToBar()   -- re-asserts the tile's row size, icon, recess and ring; idempotent
  fitBuybackQualityGlow()

  postRepairButtons()
end

-- Per-row name colour + quest bang, driven off the link the row is showing.
--
-- DOWNPORT: the 1.15 source hooked MerchantFrameItem_UpdateQuality, an Era function that does not
-- exist here, so the two tabs' updaters are hooked directly and the row-index -> link math is
-- FrameXML's own. The rarity BORDER is left to DragonUI's itemquality module (see the file header).
local function colourRow(prefix, link)
  if not _G[prefix] then return end

  local quality = link and select(3, GetItemInfo(link)) or nil

  local nm = _G[prefix .. "Name"]
  if nm then
    local c = NE.itembtn.TextColor(quality)
    if c then
      nm:SetTextColor(c.r, c.g, c.b)
    else
      nm:SetTextColor(NORMAL_FONT_COLOR.r, NORMAL_FONT_COLOR.g, NORMAL_FONT_COLOR.b)
    end
  end

  local ib = _G[prefix .. "ItemButton"]
  local bang = ib and ib.IconQuestTexture
  if bang then
    if link and NE.itemgrid.ItemStartsQuestByLink(link) then bang:Show() else bang:Hide() end
  end
end

local function postUpdateMerchantInfo()
  local f = _G.MerchantFrame
  if not f or not f._neBuilt then return end
  stats.merchantInfo = stats.merchantInfo + 1
  stats.tab = f.selectedTab
  setRowPitch(ROW_GAP_MERCHANT)
  local page = f.page or 1
  for i = 1, ITEMS_PER_PAGE do
    local index = ((page - 1) * ITEMS_PER_PAGE) + i
    colourRow("MerchantItem" .. i, GetMerchantItemLink and GetMerchantItemLink(index))
  end
  -- The merchant tab's single buyback slot shows the most recent sale.
  local n = (GetNumBuybackItems and GetNumBuybackItems()) or 0
  colourRow("MerchantBuyBackItem",
            (n > 0 and GetBuybackItemLink) and GetBuybackItemLink(n) or nil)
end



local function postUpdateBuybackInfo()
  local f = _G.MerchantFrame
  if not f or not f._neBuilt then return end
  stats.buybackInfo = stats.buybackInfo + 1
  stats.tab = f.selectedTab
  setRowPitch(ROW_GAP_BUYBACK)
  for i = 1, BUYBACK_PER_PAGE do
    colourRow("MerchantItem" .. i, GetBuybackItemLink and GetBuybackItemLink(i))
    -- Retail bangs vendor items only, and these are the merchant tab's rows reused — clear any bang
    -- the merchant pass left on them.
    local ib = _G["MerchantItem" .. i .. "ItemButton"]
    if ib and ib.IconQuestTexture then ib.IconQuestTexture:Hide() end
  end
end

-- A full sync, on the NEXT frame rather than inline.
--
-- Everything above hangs off hooksecurefunc on FrameXML's updaters, which is the right seam right up
-- until one of those updaters throws: a post-hook does not run when the original errors, so a single
-- fault inside MerchantFrame_UpdateMerchantInfo silently strands the title, the portrait, the bottom
-- band and its buttons in whatever state the previous tab left them -- and survives a close and
-- reopen, because the next call throws in the same place. A timer cannot be aborted by an error in
-- the call that scheduled it, so this path always completes.
--
-- It is a coalesced single shot: several triggers can fire for one tab click and only one pass runs.
local syncPending
local function syncSoon()
  local f = _G.MerchantFrame
  if not f or not f._neBuilt or syncPending then return end
  syncPending = true
  C_Timer.After(0, function()
    syncPending = false
    local frame = _G.MerchantFrame
    if not (frame and frame._neBuilt and frame:IsShown()) then return end
    postMerchantUpdate()
    -- The per-row pass too: it rides the same broken hook, so on the merchant tab the rarity colours
    -- and quest bangs would otherwise never be applied either.
    if frame.selectedTab == 2 then postUpdateBuybackInfo() else postUpdateMerchantInfo() end
  end)
end
Merch.SyncSoon = syncSoon

-- ----------------------------------------------------------------------------
-- Build
-- ----------------------------------------------------------------------------

-- The visual build is deferred from PLAYER_LOGIN to the first MERCHANT_SHOW: a session that never
-- visits a vendor pays nothing for chrome it never sees. MERCHANT_SHOW fires before MerchantFrame
-- paints (MerchantFrame_OnEvent -> ShowUIPanel -> OnShow -> MerchantFrame_Update), so the modern
-- chrome is in place before the first visible frame — no flash of wood. Vendors cannot be used in
-- combat, so this SetScale/SetPoint-bearing pass inherently runs out of combat.
--
-- What must NOT move here (it is armed at login instead): the classic-art suppression and the
-- update hooks. Both have to exist before the first MerchantFrame_Update, or that update repaints
-- the wood.
local built = false
local function buildModernChrome()
  if built then return end
  local f = _G.MerchantFrame
  if not f then return end
  built = true

  -- DOWNPORT: the 1.15 source pins the frame pixel-perfect here, flagging in its own comment that
  -- "UIPanel positioning math (ShowUIPanel) may not account for it". On 3.3.5a it demonstrably does
  -- not — UpdateUIPanelPositions measures GetWidth() unscaled, so a SetScale'd panel lays out in the
  -- wrong column and can push its neighbours off screen. Every reskinned Blizzard window in this
  -- addon (modules/inspect included) therefore leaves the client's scale alone; only our OWN
  -- standalone windows scale, through NE.scale.
  applyModernChrome()

  -- Rehost the title. PanelChrome builds its band + FontString; postMerchantUpdate feeds it the
  -- text FrameXML writes into the (now hidden) MerchantNameText.
  PC.EnsureTitle(f, (_G.MerchantNameText and _G.MerchantNameText:GetText()) or "")

  -- Seat the portrait in the metal corner ring, the same way every other NewEra panel does.
  if _G.MerchantFramePortrait and NE.portrait and NE.portrait.ApplyCutout then
    NE.portrait.ApplyCutout(_G.MerchantFramePortrait, f)
  end

  buildGridInset()
  buildBottomBand()
  reskinAllSlots()
  fitBuybackToBar()   -- after reskinAllSlots, which gives it the grid's sizes first
  addQuestBangs()
  reskinRepairIcons()
  buildMoneyInset()
  modernizeCloseButton()
  reskinPageNavButtons()

  if NE.tabs and NE.tabs.ReskinClassicTab then
    NE.tabs.ReskinClassicTab("MerchantFrameTab1")
    NE.tabs.ReskinClassicTab("MerchantFrameTab2")
    NE.tabs.SizeAndAnchorTabs(f, { "MerchantFrameTab1", "MerchantFrameTab2" })
  end

  for i = 1, BUYBACK_PER_PAGE do clampName(_G["MerchantItem" .. i .. "Name"], 84) end

  -- Sibling files attach the two added buttons. Construction only (CreateFrame + textures); their
  -- own event wiring refreshes nothing but the widgets they build, so deferring them is safe.
  if Merch.BuildSellAllJunk then Merch.BuildSellAllJunk() end
  if Merch.BuildBuybackUndo  then Merch.BuildBuybackUndo()  end

  -- The recess BG behind the repair/sell buttons — after BuildSellAllJunk creates its button.
  addRetailSlotBgs()

  f._neBuilt = true

  -- Re-drive the update against the now-built chrome: on this first show FrameXML's own
  -- MerchantFrame_Update already ran BEFORE this deferred build, so the per-row passes fired
  -- against widgets that did not exist yet.
  if f:IsShown() and _G.MerchantFrame_Update then
    MerchantFrame_Update()
  else
    postMerchantUpdate()
  end
  -- ...and again next frame through the timer path, which completes even if the call above threw
  -- somewhere inside FrameXML.
  syncSoon()
end

Merch.BuildModernChrome = buildModernChrome

-- ----------------------------------------------------------------------------
-- Boot
-- ----------------------------------------------------------------------------

-- Called once at PLAYER_LOGIN by Register.lua. Arms suppression + hooks only; the construction is
-- buildModernChrome, above, on the first MERCHANT_SHOW.
function Merch.Arm()
  -- Suppression first: the frame is hidden at login, so this just guarantees the wood never flashes
  -- on the first show. It must not wait for the deferred build.
  hideClassicChrome()

  -- Geometry is armed at login too, not deferred with the art: it is a handful of SetPoints, and
  -- doing it here means the very first ShowUIPanel measures the final width when it places the
  -- panel. (The texture work stays deferred — that is what the deferral was for.)
  applyLayout()

  -- MerchantFrame_Update is the wrapper both tabs go through; the two per-tab updaters carry the
  -- row data. Hook whichever this client defines — the post functions are idempotent, so a client
  -- that has all three simply runs them in order.
  if _G.MerchantFrame_Update then
    hooksecurefunc("MerchantFrame_Update", postMerchantUpdate)
  end
  if _G.MerchantFrame_UpdateMerchantInfo then
    hooksecurefunc("MerchantFrame_UpdateMerchantInfo", postUpdateMerchantInfo)
  end
  if _G.MerchantFrame_UpdateBuybackInfo then
    hooksecurefunc("MerchantFrame_UpdateBuybackInfo", postUpdateBuybackInfo)
  end
  -- Not every client factors the repair-button placement out into its own function; when it does,
  -- hook it so our positions win. When it does not, postMerchantUpdate already calls
  -- postRepairButtons after every update.
  if _G.MerchantFrame_UpdateRepairButtons then
    hooksecurefunc("MerchantFrame_UpdateRepairButtons", postRepairButtons)
  end

  -- Belt on the tab buttons. Everything above hangs off FrameXML's updaters, which is the right
  -- seam -- but a tab switch is precisely when our half of the window (title, portrait, the bottom
  -- band and its buttons) has to change, and it is the one moment where a missed sync leaves the
  -- window wearing the other tab's dressing while the item list looks perfectly correct. The tab's
  -- own OnClick calls PanelTemplates_SetTab then MerchantFrame_Update, and a HookScript runs after
  -- both, so this is a straight second path to the same pass. postMerchantUpdate is idempotent.
  for _, tabName in ipairs({ "MerchantFrameTab1", "MerchantFrameTab2" }) do
    local tab = _G[tabName]
    if tab and tab.HookScript then
      tab:HookScript("OnClick", function()
        stats.tabClick = stats.tabClick + 1
        syncSoon()
      end)
    end
  end

  -- The same sync driven off the merchant events directly. MERCHANT_SHOW covers reopening the window
  -- (which is where a stranded tab state is most visible), MERCHANT_UPDATE covers buying and selling.
  local sync = CreateFrame("Frame")
  sync:RegisterEvent("MERCHANT_SHOW")
  sync:RegisterEvent("MERCHANT_UPDATE")
  sync:RegisterEvent("MERCHANT_CLOSED")
  sync:SetScript("OnEvent", function(_, event)
    if event == "MERCHANT_SHOW" then
      stats.evShow = stats.evShow + 1;  trace("evSHOW")
    elseif event == "MERCHANT_CLOSED" then
      stats.evClosed = stats.evClosed + 1;  trace("evCLOSED")
    end
    syncSoon()
  end)

  -- MerchantFrame_OnShow resets the tab to 1 every time it runs, so knowing whether it ran is the
  -- whole question. HookScript, so the client's own handler is untouched.
  local mf = _G.MerchantFrame
  if mf and mf.HookScript then
    mf:HookScript("OnShow", function() stats.onShow = stats.onShow + 1; trace("OnShow") end)
    mf:HookScript("OnHide", function() stats.onHide = stats.onHide + 1; trace("OnHide") end)
  end
  for _, tabName in ipairs({ "MerchantFrameTab1", "MerchantFrameTab2" }) do
    local tab = _G[tabName]
    if tab and tab.HookScript then tab:HookScript("OnClick", function() trace("tab" .. tab:GetID()) end) end
  end

  -- GET_ITEM_INFO_RECEIVED is how an uncached row learns its quality and its "Begins a Quest" line.
  -- Retail re-drives this through MerchantFrame_RegisterForQualityUpdates, which this client has
  -- no equivalent of, so re-run the colour pass ourselves.
  local watcher = CreateFrame("Frame")
  watcher:RegisterEvent("GET_ITEM_INFO_RECEIVED")
  watcher:SetScript("OnEvent", function()
    local f = _G.MerchantFrame
    if not (f and f._neBuilt and f:IsShown()) then return end
    if f.selectedTab == 2 then postUpdateBuybackInfo() else postUpdateMerchantInfo() end
  end)
end
