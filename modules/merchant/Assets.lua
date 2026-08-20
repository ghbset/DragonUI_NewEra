-- DragonUI_NewEra/modules/merchant/Assets.lua — texture + atlas registration for the merchant
-- window reskin.
--
-- DOWNPORT of NewEra/MerchantFrame/Assets.lua. Same art, three changes:
--   * paths repointed at OUR Textures/ tree;
--   * the atlas-name -> texcoord rects that NewEra read out of the retail-only NE_ATLAS global are
--     registered here through NE.tex.RegisterAtlases (verbatim from
--     ReferenceAddons/NewEra/Generated/AtlasData.lua, build 12.0.5.67451);
--   * the two SHARED slot sheets (130766 UI-EmptySlot recess, 130841 UI-Quickslot2 ring) live in
--     Textures/Assets.lua, not here — NewEra moved them to its Core atlas file for the same reason
--     (they are generic chrome, and disabling this module must not drop them elsewhere).
--
-- Load order: before MerchantFrame.lua / SellAllJunk.lua / BuybackUndo.lua, so every
-- NE.tex.SetAtlas call in those files resolves to a shipped local sheet.

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

local P = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\Merchant\\"

-- ============================================================================
-- 1. fdid -> shipped BLP path  (NE.tex.RegisterLocal)
-- ============================================================================

-- 5222222 — the merchant pack (256x256). Carries the four modern 72x72 spell-icon buttons
-- (SellJunk / Repair / RepairAll / RepairAllGuild) and the 332x61 modern bottom band
-- (UI-Merchant-BotFrame). Extracted from retail build 12.0.5.67451.
NE.tex.RegisterLocal(5222222, P .. "5222222-merchant-pack.blp")

-- 136423 — Interface\MerchantFrame\UI-Merchant-LabelSlots (128x64): the wide label plate behind
-- each row's name/price. Same-FDID-different-art between clients — 3.3.5a's own copy is the
-- classic wooden plate, so we ship retail's and point the row at it.
NE.tex.RegisterLocal(136423, P .. "136423-ui-merchant-labelslots-retail.blp")

-- 130822 — Interface\Buttons\UI-PageButton-Background (32x32), the plate behind the prev/next page
-- arrows. Same-FDID-different-art again: 3.3.5a serves the classic wooden ring.
NE.tex.RegisterLocal(130822, P .. "130822-ui-pagebutton-background-retail.blp")

-- Page-arrow glyphs + hover (all 32x32: Interface\Buttons\UI-SpellbookIcon-* and
-- UI-Common-MouseHilight). Retail draws the NATIVE textures at these paths; 3.3.5a's CASC serves
-- the low-res classic art at the same names, so ship retail's BLPs and retexture in place.
NE.tex.RegisterLocal(130869, P .. "130869-ui-spellbookicon-prevpage-up-retail.blp")
NE.tex.RegisterLocal(130868, P .. "130868-ui-spellbookicon-prevpage-down-retail.blp")
NE.tex.RegisterLocal(130867, P .. "130867-ui-spellbookicon-prevpage-disabled-retail.blp")
NE.tex.RegisterLocal(130866, P .. "130866-ui-spellbookicon-nextpage-up-retail.blp")
NE.tex.RegisterLocal(130865, P .. "130865-ui-spellbookicon-nextpage-down-retail.blp")
NE.tex.RegisterLocal(130864, P .. "130864-ui-spellbookicon-nextpage-disabled-retail.blp")
NE.tex.RegisterLocal(130757, P .. "130757-ui-common-mousehilight-retail.blp")

-- 3487944 — retail's common-buttons-icons sheet, home of `common-icon-undo` (the buyback undo
-- arrow). DOWNPORT: the sheet is 8 MB and DragonUI — a hard dependency — already ships exactly this
-- FDID as Textures\CharacterPanel\commonicons.blp (its own atlas table quotes the same texcoords
-- we register below), so we point at that copy instead of duplicating it. If DragonUI ever moves
-- the file, NE.tex.SetAtlas reports a miss and BuildBuybackUndo skips the arrow — no error.
NE.tex.RegisterLocal(3487944, "Interface\\AddOns\\DragonUI\\Textures\\CharacterPanel\\commonicons.blp")

-- ============================================================================
-- 2. Atlas-name -> texcoord rect  (NE.tex.RegisterAtlases)
--    Coords transcribed verbatim from ReferenceAddons/NewEra/Generated/AtlasData.lua.
-- ============================================================================

NE.tex.RegisterAtlases({
  -- Sheet 5222222 — the four 72x72 modern button icons + the bottom band.
  ["spellicon-256x256-selljunk"]      = { file=5222222, left=0.001953, right=0.142578, top=0.250000, bottom=0.531250, width=72,  height=72 },
  ["spellicon-256x256-repair"]        = { file=5222222, left=0.146484, right=0.287109, top=0.250000, bottom=0.531250, width=72,  height=72 },
  ["spellicon-256x256-repairall"]     = { file=5222222, left=0.001953, right=0.142578, top=0.539062, bottom=0.820312, width=72,  height=72 },
  ["spellicon-256x256-repairallguild"]= { file=5222222, left=0.146484, right=0.287109, top=0.539062, bottom=0.820312, width=72,  height=72 },
  ["ui-merchant-botframe"]            = { file=5222222, left=0.001953, right=0.650391, top=0.003906, bottom=0.242188, width=332, height=61 },

  -- Sheet 3487944 — the undo arrow drawn inside the buyback slot.
  ["common-icon-undo"]                = { file=3487944, left=0.378418, right=0.503418, top=0.252930, bottom=0.502930, width=25,  height=25 },
})
