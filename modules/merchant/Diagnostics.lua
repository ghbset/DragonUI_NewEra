-- DragonUI_NewEra/modules/merchant/Diagnostics.lua — /nemerchant, a state dump for the vendor window.
--
-- Two things about this reskin cannot be told apart from a screenshot: an icon that resolved and is
-- simply desaturated (which the client does on purpose when there is nothing to repair, and which
-- we do when there is no junk to sell) looks much like an icon that never resolved at all. Both
-- read as "a dark square". This prints the difference: whether the sheet is registered, whether each
-- atlas resolves, which region each button's icon actually IS, and what is currently on it.
--
-- Report-only. It never changes a widget, so it is safe to run at any time.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local Merch = NE.merchant
if not Merch then return end

local MERCHANT_SHEET = 5222222

local ATLASES = {
  "spellicon-256x256-selljunk",
  "spellicon-256x256-repair",
  "spellicon-256x256-repairall",
  "spellicon-256x256-repairallguild",
  "ui-merchant-botframe",
  "common-icon-undo",
}

local ICON_OWNERS = {
  { label = "RepairAll",  button = "MerchantRepairAllButton"       },
  { label = "RepairItem", button = "MerchantRepairItemButton"      },
  { label = "GuildRepair",button = "MerchantGuildBankRepairButton" },
  { label = "SellJunk",   button = "NE_MerchantSellAllJunkButton"  },
}

local function say(fmt, ...)
  local msg = select("#", ...) > 0 and fmt:format(...) or fmt
  DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1NE merchant|r " .. msg)
end

-- Shorten a texture path to its file name, so the dump stays readable in chat.
local function shortPath(p)
  if type(p) ~= "string" then return tostring(p) end
  return p:match("([^\\/]+)$") or p
end

local function dumpSheet()
  local path = NE.tex.localFiles and NE.tex.localFiles[MERCHANT_SHEET]
  if path then
    say("sheet %d -> %s", MERCHANT_SHEET, path)
  else
    say("|cffff4040sheet %d NOT registered|r — modules/merchant/Assets.lua did not run", MERCHANT_SHEET)
  end
end

local function dumpAtlases()
  for _, name in ipairs(ATLASES) do
    local e = NE.tex._atlasEntry and NE.tex._atlasEntry(name)
    if not e then
      say("|cffff4040atlas MISS|r %s", name)
    elseif type(NE.tex.localFiles and NE.tex.localFiles[e.file]) ~= "string" then
      say("|cffff4040atlas NO-LOCAL|r %s (fdid %s not shipped)", name, tostring(e.file))
    else
      say("|cff40ff40atlas ok|r %s (fdid %s, %sx%s)", name, tostring(e.file),
          tostring(e.width), tostring(e.height))
    end
  end
end

local function dumpIcons()
  for _, spec in ipairs(ICON_OWNERS) do
    local btn = _G[spec.button]
    if not btn then
      say("%s: button absent", spec.label)
    else
      local icon = btn._neIcon or btn.Icon
      if not icon then
        say("|cffff4040%s: no icon region was claimed|r (the reskin did not find one)", spec.label)
      else
        say("%s: %s btnShown=%s alpha=%.2f tex=%s", spec.label,
            (icon:IsShown() and "icon") or "icon(hidden)",
            tostring(btn:IsShown()), icon:GetAlpha() or 1, shortPath(icon:GetTexture()))
        if not btn:IsShown() then
          say("    |cffb0b0b0(button hidden -- its anchors are unresolved, so any size below is the")
          say("     texture FILE's intrinsic size, not the laid-out one. Re-run on the tab that")
          say("     shows it.)|r")
        end
        -- GetTexCoord returns the eight CORNER values (ULx,ULy,LLx,LLy,URx,URy,LRx,LRy). TOP and
        -- BOTTOM matter as much as left/right here: spellicon-256x256-repair and -repairallguild
        -- share a column on the sheet and differ ONLY vertically, so printing L/R alone cannot tell
        -- the two apart — which made a correctly-textured guild button look mis-textured.
        local ulx, uly, _, lly, urx = icon:GetTexCoord()
        if ulx then
          say("    texcoord L=%.4f R=%.4f T=%.4f B=%.4f", ulx, urx or -1, uly or -1, lly or -1)
        end
        local w, h = icon:GetWidth(), icon:GetHeight()
        say("    size %.0fx%.0f  vertexcolor %.2f/%.2f/%.2f",
            w or 0, h or 0, icon:GetVertexColor())
      end
    end
  end
end

local function dumpHooks()
  local st = Merch.stats
  if not st then say("no hook counters (MerchantFrame.lua did not arm)"); return end
  say("CanMerchantRepair=%s  CanGuildBankRepair=%s  (the client's own gates on those buttons)",
      tostring(CanMerchantRepair and CanMerchantRepair()),
      tostring(CanGuildBankRepair and CanGuildBankRepair()))
  say("hooks fired: Update=%d MerchantInfo=%d BuybackInfo=%d Repair=%d TabClick=%d  lastTab=%s",
      st.update or 0, st.merchantInfo or 0, st.buybackInfo or 0, st.repair or 0,
      st.tabClick or 0, tostring(st.tab))
  say("window: OnShow=%d OnHide=%d  evSHOW=%d evCLOSED=%d",
      st.onShow or 0, st.onHide or 0, st.evShow or 0, st.evClosed or 0)
  if st.tabTrace and #st.tabTrace > 0 then
    say("trace (oldest first): %s", table.concat(st.tabTrace, "  "))
  end
  local f = _G.MerchantFrame
  if f then
    say("selectedTab=%s  title=%q  nameText=%q", tostring(f.selectedTab),
        (f.Title and f.Title:GetText()) or "<none>",
        (_G.MerchantNameText and _G.MerchantNameText:GetText()) or "<none>")
  end
end

-- Run the client's own updaters under pcall and print whatever they throw.
--
-- This is the question the counters raised and could not answer: MerchantInfo=0 while nameText held
-- the vendor's name means _UpdateMerchantInfo RAN and then died partway, because a hooksecurefunc
-- post-hook does not run when the original errors. That silently strands every piece of chrome this
-- module owns -- and the error itself never surfaces, because the first call happens inside the
-- module dispatcher's pcall. Calling it again here is safe: both updaters are idempotent redraws.
local function dumpUpdaterErrors()
  local f = _G.MerchantFrame
  if not (f and f:IsShown()) then
    say("updater probe skipped -- open a vendor first")
    return
  end
  for _, name in ipairs({ "MerchantFrame_UpdateMerchantInfo", "MerchantFrame_UpdateBuybackInfo" }) do
    local fn = _G[name]
    if type(fn) ~= "function" then
      say("|cffff4040%s missing|r", name)
    else
      local ok, err = pcall(fn)
      if ok then
        say("|cff40ff40%s ran clean|r", name)
      else
        say("|cffff4040%s THREW:|r %s", name, tostring(err))
      end
    end
  end
end

-- Rarity borders on the merchant window are DragonUI's itemquality module, not ours (see
-- PORT_NOTES). It hooks MerchantFrame_UpdateMerchantInfo and _UpdateBuybackInfo and hangs a glow
-- overlay off each item button. When a border is missing there are three separable causes, and only
-- data tells them apart: the overlay was never created (its hook never reached that button), it
-- exists but is hidden (the item is below its min_quality threshold, which defaults to Uncommon), or
-- the item has no link to derive a quality from at all.
local function dumpRarity()
  local f = _G.MerchantFrame
  if not (f and f:IsShown()) then return end

  local function line(label, button, link)
    if not button then return end
    local ov = button.__DragonUI_QualityOverlay
    local q = link and select(3, GetItemInfo(link)) or nil
    say("  %-14s q=%-4s overlay=%s shown=%s %s", label, tostring(q),
        ov and string.format("%.0fpx", ov:GetWidth() or 0) or "|cffff4040NONE|r",
        ov and tostring(ov:IsShown()) or "-",
        link and (link:match("%[(.-)%]") or "?") or "(empty)")
  end

  say("rarity borders (DragonUI itemquality owns these):")
  local n = (GetNumBuybackItems and GetNumBuybackItems()) or 0
  line("buyback slot", _G.MerchantBuyBackItemItemButton,
       (n > 0 and GetBuybackItemLink) and GetBuybackItemLink(n) or nil)
  if f.selectedTab == 2 then
    for i = 1, 12 do
      local b = _G["MerchantItem" .. i .. "ItemButton"]
      if b and b:IsShown() then line("buyback row " .. i, b, GetBuybackItemLink and GetBuybackItemLink(i)) end
    end
  else
    for i = 1, 3 do
      local b = _G["MerchantItem" .. i .. "ItemButton"]
      local page = f.page or 1
      if b and b:IsShown() then
        line("merchant row " .. i, b,
             GetMerchantItemLink and GetMerchantItemLink((page - 1) * 10 + i))
      end
    end
  end
end

local function dumpGeometry()
  local f = _G.MerchantFrame
  if not f then return end
  say("frame %.0fx%.0f  xoffset=%s  built=%s",
      f:GetWidth() or 0, f:GetHeight() or 0,
      tostring(f.GetAttribute and f:GetAttribute("UIPanelLayout-xoffset")),
      tostring(f._neBuilt))
  local row = _G.MerchantItem2
  if row then
    -- What the right column actually reaches, in frame coordinates — the number PANEL_W has to
    -- clear. Read off the live widget rather than derived from the template, so it is the truth.
    local plate = _G.MerchantItem2NameFrame
    local edge = plate and plate:GetRight()
    local fr = f:GetRight()
    if edge and fr then
      say("right column plate ends %.0f px %s the frame edge",
          math.abs(edge - fr), (edge > fr) and "|cffff4040PAST|r" or "inside")
    end
  end
  local bg = f.Bg
  if bg then
    local r, g, b = bg:GetVertexColor()
    say("body: shown=%s  tex=%s  vertex %.2f/%.2f/%.2f  %.0fx%.0f",
        tostring(bg:IsShown()), shortPath(bg:GetTexture()), r or 0, g or 0, b or 0,
        bg:GetWidth() or 0, bg:GetHeight() or 0)
  else
    say("|cffff4040body: no f.Bg at all|r")
  end
  say("band=%s  gridInset=%s  moneyInset=%s  botFrame shown=%s",
      tostring(f._neBotFrame ~= nil), tostring(f._neGridInset ~= nil),
      tostring(f._neMoneyInset ~= nil),
      tostring(f._neBotFrame and f._neBotFrame:IsShown()))

  -- The bottom bar, left to right. Overlap here is the thing that is hard to judge from a
  -- screenshot: the money frame's width follows how much gold you are carrying, so a rich character
  -- can push its recess left into the buyback slot on a layout that looked fine when poorer.
  local fl, fb = f:GetLeft(), f:GetBottom()
  -- Vertical spans too: "not centred in its box" is not judgeable from a screenshot, and the band
  -- art's recess is not centred within its own atlas slice, so the buttons' gap above and below has
  -- to be read off the widgets rather than assumed from the band's midpoint.
  local function span(label, name)
    local w = _G[name]
    if not (w and fl and fb and w:GetLeft()) then return end
    say("  bar %-11s x %.0f..%.0f   y %.0f..%.0f%s", label,
        w:GetLeft() - fl, w:GetRight() - fl, w:GetBottom() - fb, w:GetTop() - fb,
        w:IsShown() and "" or "   (hidden: values stale)")
  end
  local band = f._neBotFrame
  if band and fb and band:GetBottom() then
    say("  band            y %.0f..%.0f  (buttons should look centred in its VISIBLE recess,",
        band:GetBottom() - fb, band:GetTop() - fb)
    say("                   which is inset from these bounds by the atlas's own border)")
  end
  span("repairItem", "MerchantRepairItemButton")
  span("repairAll",  "MerchantRepairAllButton")
  span("guildRepair","MerchantGuildBankRepairButton")
  span("sellJunk",   "NE_MerchantSellAllJunkButton")
  span("buyback",    "MerchantBuyBackItem")
  local bb = _G.MerchantBuyBackItemItemButton
  if bb then
    local ic = _G.MerchantBuyBackItemItemButtonIconTexture
    local glow = bb.__DragonUI_QualityOverlay
    if not bb:IsShown() then
      say("  |cffb0b0b0buyback tile hidden -- sizes below are intrinsic, not laid out|r")
    end
    say("  buyback tile %.0fx%.0f  icon %.0fx%.0f shown=%s  dragonUIglow %.0f",
        bb:GetWidth() or 0, bb:GetHeight() or 0,
        (ic and ic:GetWidth()) or 0, (ic and ic:GetHeight()) or 0,
        tostring(ic and ic:IsShown()), (glow and glow:GetWidth()) or 0)
  end
  span("money",      "MerchantMoneyFrame")
end

function Merch.Diagnose()
  say("---- state ----")
  dumpSheet()
  dumpAtlases()
  dumpIcons()
  dumpHooks()
  dumpUpdaterErrors()
  dumpRarity()
  dumpGeometry()
  say("---- end ----")
end

SLASH_NEMERCHANT1 = "/nemerchant"
SlashCmdList["NEMERCHANT"] = function() Merch.Diagnose() end
