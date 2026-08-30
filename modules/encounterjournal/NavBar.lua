-- DragonUI_NewEra/modules/encounterjournal/NavBar.lua — the Adventure Guide's breadcrumb + search.
--
-- DOWNPORT of NewEra/EncounterJournal/NavBar.lua. NewEra reuses Era's shipped `NavBarTemplate` via
-- its Core NE.navbar wrapper; neither exists on 3.3.5a, so the breadcrumb was rebuilt from scratch
-- here — the trail, the art, the collapse, the interlocking frame levels, all of it in this file.
--
-- **That implementation now lives in core/NavBar.lua**, unchanged in behaviour, and this file is
-- what is left once the widget moves out: the TRAIL (Home > Instance ▾ > Boss), the boss-jump
-- dropdown, and the search box. The move happened because a second window rebuilt the same widget
-- from scratch and re-introduced two faults this file had already fixed and documented — the Home
-- crumb sitting on the window's portrait, and crumbs drawn underneath their own bar. The art
-- measurements, the colour rule, the crop-and-stretch treatment and the reasoning behind all three
-- moved with the code; core/NavBar.lua's header is now where they live.
--
-- Public surface is unchanged, because EncounterJournal.lua and EncounterPage.lua call it from five
-- places: `NE.ej.BuildNavBar(f)`, `NE.ej.RefreshNavBar()`, and `f._neSearchBox`.
--
-- SEARCH stays here rather than in core: it is not part of a breadcrumb, and it filters the
-- instance grid. A second caller's search box would sit somewhere else on its own window.

local NE = DragonUI_NewEra
if not NE then return end

NE.ej = NE.ej or {}

-- Bar width: fill the header from just past the portrait to just before the search box. The frame
-- is 800 wide; the search box sits at TOPRIGHT(-30) width 180 (so it starts at x~590), and a 520px
-- bar ends at x580 — the whole gap. Wide enough that a normal three-crumb trail
-- (Home > Instance > Boss) fits WITHOUT collapsing anything into the overflow badge.
local NAVBAR_W = 520
-- PortraitFrameTemplate's round portrait (60x60 at TOPLEFT(-6,7)) reaches out to x~54 from the
-- frame's corner. A 14px start sat the Home crumb's text right on top of that art; 60 clears it.
local NAVBAR_X, NAVBAR_Y = 60, -24

-- ---------------------------------------------------------------------------------------
-- Trail model
-- ---------------------------------------------------------------------------------------

-- The instance crumb's ▾: jump straight to any boss in the instance you are already inside.
local function bossJumpList()
  local f = NE.ej.frame
  local inst = f and f._currentInstance
  local list = {}
  if inst and inst.encounters then
    for _, e in ipairs(inst.encounters) do
      list[#list + 1] = {
        text = e.name,
        notCheckable = true,
        func = function() if NE.ej.ShowBoss then NE.ej.ShowBoss(e) end end,
      }
    end
  end
  return list
end

-- Home > Instance ▾ > Boss. Entry 1 is always Home; core/NavBar.lua owns everything past that.
local function buildTrail()
  local f = NE.ej.frame
  local entries = {
    {
      name    = _G.HOME or "Home",
      OnClick = function() if NE.ej.ShowList then NE.ej.ShowList() end end,
    },
  }
  if not f then return entries end

  local inst = f._currentInstance
  if inst then
    entries[#entries + 1] = {
      name     = inst.name,
      OnClick  = function() if NE.ej.ShowInstance then NE.ej.ShowInstance(inst) end end,
      listFunc = bossJumpList,
    }
  end

  local boss = f._currentBoss
  if boss then
    entries[#entries + 1] = {
      name    = boss.name,
      OnClick = function() if NE.ej.ShowBoss then NE.ej.ShowBoss(boss) end end,
    }
  end
  return entries
end
NE.ej.BuildNavTrail = buildTrail   -- test seam: assertable without building a widget

-- ---------------------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------------------

function NE.ej.BuildNavBar(f)
  if f._neNavBar then return f._neNavBar end
  if not (NE.navbar and NE.navbar.Create) then return nil end

  local lvl = ((f.NineSlice and f.NineSlice:GetFrameLevel()) or f:GetFrameLevel() or 1) + 6

  local navBar = NE.navbar.Create(f, {
    name       = "NE_EncounterJournalNavBar",
    height     = 34,
    frameLevel = lvl,
    trailFunc  = buildTrail,
  })
  navBar:SetWidth(NAVBAR_W)
  navBar:SetPoint("TOPLEFT", f, "TOPLEFT", NAVBAR_X, NAVBAR_Y)
  f._neNavBar = navBar

  -- Search box (filters the instance grid). pcall the ClassicAPI template and fall back to a plain
  -- InputBoxTemplate if a future build renames it — the journal works without search.
  local ok, sb = pcall(CreateFrame, "EditBox", "NE_EncounterJournalSearchBox", f, "SearchBoxTemplate")
  if not (ok and sb) then
    ok, sb = pcall(CreateFrame, "EditBox", "NE_EncounterJournalSearchBox", f, "InputBoxTemplate")
    if ok and sb then sb:SetAutoFocus(false) end
  end
  if ok and sb then
    sb:SetSize(180, 20)
    sb:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -32)
    sb:SetFrameLevel(lvl)
    -- DOWNPORT: SearchBoxTemplate_OnLoad/OnEditFocusLost (!!!ClassicAPI) write the literal SEARCH
    -- placeholder into the box's real text (no retail overlay watermark), so OnTextChanged fires
    -- with that placeholder both on load and on every blur — NE.ej.ReadSearchText treats it as
    -- "no search" instead of a literal filter string that matches zero instances.
    sb:HookScript("OnTextChanged", function(self)
      if NE.ej.FilterGrid then
        NE.ej.FilterGrid(NE.ej.ReadSearchText and NE.ej.ReadSearchText(self) or self:GetText())
      end
    end)
    sb:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f._neSearchBox = sb
  end

  navBar:Relayout()
  return navBar
end

function NE.ej.RefreshNavBar()
  local f = NE.ej.frame
  local navBar = f and f._neNavBar
  if navBar then navBar:Refresh() end
end
