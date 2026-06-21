-- DragonUI_NewEra/modules/character/TabButtons.lua — OUR OWN DF metal bottom tabs for the custom
-- character frame, + the 5 empty content panes the Wave-2 content agents fill.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): we do NOT reskin Blizzard's CharacterFrameTab1..5. We build
-- our OWN tab buttons hanging off the bottom of NE.charpanel.frame and switch our own content panes.
--
-- GEOMETRY (VISUAL_SPEC.md): 5 metal DF tabs — Character / Pet / Skills / Honor / Reputation.
--   * 36px tall INACTIVE, 42px tall ACTIVE.
--   * 1px gap between tabs.
--   * the ACTIVE tab is raised one frame level (so its taller body draws over its neighbours).
--
-- PANES: each tab owns an empty content frame parented to frame.Inset, named
--   DragonUI_NewEra_CharacterPane_<Tab>  (Tab in {Character,Pet,Skills,Honor,Reputation}).
-- Wave 2 fills them. The Character pane is the SLOTS+MODEL host (those widgets are reparented straight
-- onto the Inset in CharacterPanel.lua, so the Character pane is a thin always-on container that
-- never hides the model). Secondary panes cover the Inset and are hidden until selected.
--
-- HOW: each tab is a Button inheriting the vanilla "CharacterFrameTabButtonTemplate" (so it carries
-- the Left/Middle/Right + *Disabled child textures that NE.tabs.ReskinClassicTab swaps to the DF
-- metal atlases). On click a tab calls NE.charpanel.SelectTab(name).
--
-- DOWNPORT/degrade: if the vanilla template is unavailable, fall back to a plain UIPanelButton so the
-- tab row still works (unstyled) and never errors. No SetShown — Show()/Hide() only.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

-- Tab heights + spacing (VISUAL_SPEC).
local TAB_H_INACTIVE = 36
local TAB_H_ACTIVE   = 42
local TAB_GAP        = 1
local TAB_MIN_W      = 70

local function log(msg) if CP._log then CP._log(msg) end end

-- Tab order + display labels (VISUAL_SPEC: Character,Pet,Skills,Honor,Reputation).
-- DOWNPORT: use the localized globals where present, else English.
local TABS = {
  { key = "Character",  label = _G.CHARACTER  or "Character"  },
  { key = "Pet",        label = _G.PET        or "Pet"        },
  { key = "Skills",     label = _G.SKILLS     or "Skills"     },
  { key = "Honor",      label = _G.HONOR      or "Honor"      },
  { key = "Reputation", label = _G.REPUTATION or "Reputation" },
}

CP._tabs       = CP._tabs       or {}   -- key -> button
CP._tabPanes   = CP._tabPanes   or {}   -- key -> content frame (parented to Inset)
CP._activeTab  = CP._activeTab  or "Character"

-- Forward declarations (kept as locals, not globals).
local selectTab, selectInitial

-- Create (or reuse) a content pane for a tab, parented to frame.Inset. Wave 2 fills these.
-- Named DragonUI_NewEra_CharacterPane_<key> per the contract.
local function ensurePane(key)
  if CP._tabPanes[key] then return CP._tabPanes[key] end
  local f = CP.frame
  local host = (f and f.Inset) or f
  if not host then return nil end
  local pane = CreateFrame("Frame", "DragonUI_NewEra_CharacterPane_" .. key, host)
  pane:SetAllPoints(host)
  pane:SetFrameLevel((host:GetFrameLevel() or 1) + 1)
  if key ~= "Character" then pane:Hide() end   -- DOWNPORT: Hide(), no SetShown
  CP._tabPanes[key] = pane
  return pane
end
CP.EnsurePane = ensurePane

-- DOWNPORT (faithful to NewEra TabButtons.lua): per-tab width = max(70, textW+24) — NOT equal-fill
-- (that spread them across the whole bottom). Re-chain only VISIBLE tabs so a hidden Pet tab leaves
-- no gap.
local TAB_TEXT_BREATHING = 24

local function resizeTab(tab)
  if not tab then return end
  local text = _G[tab:GetName() .. "Text"]
  local textW = 0
  if text then text:SetWidth(0); textW = text:GetWidth() or 0 end   -- auto-size before measuring
  tab:SetWidth(math.max(TAB_MIN_W, math.floor(textW + TAB_TEXT_BREATHING)))
end

-- Pet tab shows only when the player has a controllable pet UI (Blizzard PetTab_Update rule). For a
-- priest/mage there is no pet → the tab hides and the others pack contiguous (matches NewEra).
local function petTabShown()
  local ok, v = pcall(function() return HasPetUI and HasPetUI() end)
  return ok and v and true or false
end

-- Left-pack the VISIBLE tabs: first at frame.BOTTOMLEFT(11,2) by TOPLEFT, rest chain TOPLEFT to the
-- previous visible tab's TOPRIGHT with a 1px gap (NewEra rechainVisibleTabs). Tabs HANG BELOW the
-- frame, tops aligned, so the active (42h) tab grows downward.
local function rechainVisibleTabs(f)
  local prev
  for _, def in ipairs(TABS) do
    local tab = CP._tabs[def.key]
    if tab and tab:IsShown() then
      tab:ClearAllPoints()
      if prev then
        tab:SetPoint("TOPLEFT", prev, "TOPRIGHT", TAB_GAP, 0)
      else
        tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 11, 2)
      end
      prev = tab
    end
  end
end
CP._rechainVisibleTabs = rechainVisibleTabs
CP._resizeTab = resizeTab

-- Build the DF metal tab row across the bottom of our frame.
local function buildTabs()
  local f = CP.frame or (CP.BuildFrame and CP.BuildFrame())
  if not f then log("buildTabs: frame not built yet"); return end

  for i, def in ipairs(TABS) do
    local name = "DragonUI_NewEra_CharacterTab" .. i
    local tab = CP._tabs[def.key] or _G[name]
    if not tab then
      -- Prefer the vanilla tab template (gives us Left/Middle/Right children to reskin); else plain.
      local ok, t = pcall(CreateFrame, "Button", name, f, "CharacterFrameTabButtonTemplate")
      if ok and t then
        tab = t
      else
        tab = CreateFrame("Button", name, f, "UIPanelButtonTemplate")
        tab._nePlain = true
      end
      tab:SetID(i)
      tab.tabKey = def.key
      local txt = _G[name .. "Text"]
      if txt then txt:SetText(def.label) elseif tab.SetText then tab:SetText(def.label) end
      tab:SetScript("OnClick", function(self)
        if PlaySound then pcall(PlaySound, "igCharacterInfoTab") end
        CP.SelectTab(self.tabKey)
      end)
      CP._tabs[def.key] = tab
    end

    -- DF metal skin via the shared Core walker (no-op on plain fallback buttons).
    if not tab._nePlain and NE.tabs and NE.tabs.ReskinClassicTab then
      pcall(NE.tabs.ReskinClassicTab, name, {})
    end

    -- Pet tab visibility (others always shown).
    if def.key == "Pet" then
      if petTabShown() then tab:Show() else tab:Hide() end
    end

    resizeTab(tab)
    tab:SetHeight(TAB_H_INACTIVE)

    ensurePane(def.key)
  end

  -- Left-pack the visible tabs (after all are sized + visibility set).
  rechainVisibleTabs(f)

  -- Re-evaluate Pet-tab visibility + re-chain when pets come/go.
  if not CP._petTabWatcher then
    local w = CreateFrame("Frame")
    w:RegisterEvent("UNIT_PET")
    w:RegisterEvent("PET_UI_UPDATE")
    w:RegisterEvent("PLAYER_ENTERING_WORLD")
    w:SetScript("OnEvent", function()
      local petTab = CP._tabs["Pet"]
      if petTab then if petTabShown() then petTab:Show() else petTab:Hide() end end
      rechainVisibleTabs(CP.frame)
    end)
    CP._petTabWatcher = w
  end

  -- Select the resting tab (Character).
  selectInitial()
end

-- DOWNPORT: drive the tab's selected/deselected ART manually (we don't call PanelTemplates_SelectTab,
-- which would resize the tab). The reskin put the INACTIVE atlas on Left/Middle/Right and the ACTIVE
-- (gold, taller) atlas on the *Disabled pieces; the vanilla template normally toggles which set is
-- visible. SELECTED → show the *Disabled (gold/active) pieces, hide the regular ones; DESELECTED →
-- the reverse. (Without this the unselected tabs wrongly showed the gold art and vice-versa.)
local function setTabArt(tab, selected)
  if not tab then return end
  local n = tab:GetName()
  local function set(suffix, show)
    local t = _G[n .. suffix]
    if t then if show then t:Show() else t:Hide() end end
  end
  set("Left",  not selected); set("Middle",  not selected); set("Right",  not selected)
  set("LeftDisabled", selected); set("MiddleDisabled", selected); set("RightDisabled", selected)

  -- DOWNPORT/REPORT: the SELECTED tab must NOT show the hover highlight (ReskinClassicTab's custom
  -- HIGHLIGHT-layer 3-slice auto-lit on mouseover even when active — it's shaped/sized for the inactive
  -- tab and bled over the gold art). Mute it (alpha 0) while selected; restore 0.4 when deselected.
  local hl = tab._neCustomHL
  if hl then
    local a = selected and 0 or 0.4
    if hl.left   and hl.left.SetAlpha   then hl.left:SetAlpha(a)   end
    if hl.middle and hl.middle.SetAlpha then hl.middle:SetAlpha(a) end
    if hl.right  and hl.right.SetAlpha  then hl.right:SetAlpha(a)  end
  end
end

-- Switch the active tab: show its pane, hide the rest, swap selection art + height + frame level.
selectTab = function(key)
  if not CP._tabs[key] then return end
  CP._activeTab = key
  local f = CP.frame
  local baseLevel = (f and f:GetFrameLevel() or 1) + 2
  for _, def in ipairs(TABS) do
    local tab  = CP._tabs[def.key]
    local pane = CP._tabPanes[def.key]
    local on   = (def.key == key)
    if tab then
      setTabArt(tab, on)                              -- selected → gold/active art; else dark/inactive
      -- 42h active / 36h inactive; active tab raised above siblings. Tabs hang below the frame with
      -- tops aligned, so the taller active tab grows DOWNWARD.
      tab:SetHeight(on and TAB_H_ACTIVE or TAB_H_INACTIVE)
      if CP._resizeTab then CP._resizeTab(tab) end   -- keep per-tab text width
      if tab.SetFrameLevel then tab:SetFrameLevel(baseLevel + (on and 8 or 0)) end
      -- Label centered; nudge DOWN on the active tab (tabs grow downward from the top-aligned edge,
      -- so the active tab's extra 6px is below — center the label in the visible body).
      local txt = _G[tab:GetName() .. "Text"]
      if txt then txt:ClearAllPoints(); txt:SetPoint("CENTER", tab, "CENTER", 0, on and -3 or 0) end
    end
    if pane then
      if on then
        -- DOWNPORT/REPORT: raise the ACTIVE secondary pane ABOVE the (now-hidden) paperdoll so its
        -- content draws cleanly and fills the Inset (panes are SetAllPoints(Inset), so they follow
        -- the per-tab Inset width automatically). Model sits at host+2, slots at host+5.
        local host = (f and f.Inset) or f
        if pane.SetFrameLevel and host and host.GetFrameLevel then
          pane:SetFrameLevel((host:GetFrameLevel() or 1) + 10)
        end
        pane:Show()
      else
        pane:Hide()                                                  -- DOWNPORT: no SetShown
      end
    end
  end

  -- Keep the visible tab row tight after width/height changes.
  if CP._rechainVisibleTabs then CP._rechainVisibleTabs(f) end

  -- DOWNPORT/REPORT: hide/show the WHOLE player-paperdoll group (model + 19 slots + decorations) so
  -- Skills/Reputation/Honor no longer show the paperdoll behind/over their content. Only the
  -- Character tab shows the player paperdoll; Pet drives its OWN pet model (DragonUI_NewEra_PetModel)
  -- inside its pane, so the player model/slots hide there too.
  if CP.ShowPaperDoll then pcall(CP.ShowPaperDoll, key == "Character") end

  -- DOWNPORT/REPORT: per-tab frame + Inset WIDTH (the state-machine fix). ApplyTabState sets the
  -- wide-tab flag + frame/Inset width and force-collapses the sidebar on the three Era tabs; on
  -- Character/Pet it restores the narrow fixed-width Inset. Run BEFORE the sidebar expand below so
  -- the wide-tab flag is set when ExpandSidebar/SetSidebarExpanded run.
  if CP.ApplyTabState then pcall(CP.ApplyTabState, key) end

  -- DOWNPORT/REPORT (Issue A): ApplyTabState just re-anchored the frame + Inset to the per-tab WIDTH
  -- (445 for the wide Era tabs). The active pane is SetAllPoints(Inset) once at boot, but re-assert it
  -- here (in case anything cleared its points) and then trigger the tab's own content RELAYOUT so its
  -- FauxScrollFrame + content frame re-read the NOW-RESIZED width and re-flow rows (without this the
  -- rows were laid out at the narrow ~272px width → clipped/empty, and the scrollbar sat at the old x).
  do
    local host = (f and f.Inset) or f
    local pane = CP._tabPanes[key]
    if pane and host then
      pane:ClearAllPoints()
      pane:SetAllPoints(host)
    end
    -- DOWNPORT/REPORT: ALWAYS reset the entering tab's scroll to the TOP. Persisting a scroll offset
    -- across tabs left a new (often shorter) list scrolled partway down — rows missing, layout off.
    -- Reset the Faux offset + the frame's own vertical scroll BEFORE the refresh re-lays out from row 1.
    local scrollNames = {
      Skills     = "DragonUI_NewEra_SkillsScroll",
      Reputation = "DragonUI_NewEra_RepScroll",
      Honor      = "DragonUI_NewEra_HonorScroll",
    }
    local sf = scrollNames[key] and _G[scrollNames[key]]
    if sf then
      if FauxScrollFrame_SetOffset then pcall(FauxScrollFrame_SetOffset, sf, 0) end
      if sf.SetVerticalScroll then pcall(sf.SetVerticalScroll, sf, 0) end
    end
    local refreshers = {
      Skills     = CP.RefreshSkills,
      Reputation = CP.RefreshReputation,
      Honor      = CP.RefreshHonor,
      Pet        = CP.RefreshPet,
    }
    local fn = refreshers[key]
    if fn then
      pcall(fn)
      -- DOWNPORT/REPORT: the Inset SetPoint width change resolves on the NEXT frame, so a synchronous
      -- refresh can still read the old width. Re-run one frame later so rows reflow at the final width.
      -- (The scroll's OnSizeChanged hook also covers this; the deferred call is belt-and-suspenders.)
      if C_Timer and C_Timer.After then C_Timer.After(0, function() pcall(fn) end) end
    end
  end

  -- Tie the sidebar to the active tab (NewEra Sidebar.lua:743-755): the Character/PaperDoll tab RESTS
  -- with the right-side stats sidebar EXPANDED (this is the missing right third of the panel); Pet
  -- expands its pet-stats sidebar; Reputation/Skills/Honor are full-width with no sidebar (already
  -- force-collapsed by ApplyTabState — SetSidebarExpanded no-ops the expand while wide).
  if key == "Character" then
    -- DOWNPORT/REPORT: always return to the STATS view on entering Character, even if the Equipment
    -- Manager (sidebar 3) was the last sub-tab open. ExpandSidebar restores CP._activeSidebar, so reset
    -- it to 1 first (selectSidebar(1) inside ExpandSidebar then hides the equip pane + shows stats).
    CP._activeSidebar = 1
    if CP.HideEquipManager then pcall(CP.HideEquipManager) end
    if CP.HideTitles then pcall(CP.HideTitles) end
    if CP.ExpandSidebar then pcall(CP.ExpandSidebar) end
  elseif key == "Pet" then
    if CP.ExpandPetSidebar then pcall(CP.ExpandPetSidebar)
    elseif CP.ExpandSidebar then pcall(CP.ExpandSidebar) end
  else
    if CP.CollapseSidebar then pcall(CP.CollapseSidebar) end
  end
  -- Re-assert resting layout (slot/model positions) on tab switch.
  if CP.ReassertLayout then pcall(CP.ReassertLayout) end
end

-- Select the resting tab after a (re)build.
selectInitial = function()
  selectTab(CP._activeTab or "Character")
end

-- Publish the surface.
CP.BuildTabs  = buildTabs
CP.SelectTab  = selectTab

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:SetScript("OnEvent", function()
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled("character") then return end
  local ok, err = pcall(buildTabs)
  if not ok then log("tab build failed: " .. tostring(err)) end
end)
