-- DragonUI_NewEra/modules/character/LevelText.lua — class-colored "Level N Race Class" text on the
-- PaperDoll tab, with the retail two-line guild rule. Ported from NewEra/CharacterPanel/LevelText.lua.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): the vanilla CharacterLevelText/CharacterGuildText are layer
-- FontStrings on the now-HIDDEN PaperDollFrame, so they never render in our custom frame. DOWNPORT:
-- instead of reparenting Blizzard layer regions (fiddly + drags name/title), we own OUR OWN level +
-- guild FontStrings on the Inset's Character pane and keep them synced to the same data + the same
-- events 3.3.5a re-formats on (PaperDollFrame_SetLevel / PaperDollFrame_SetGuild). We ALSO recolor the
-- stock CharacterLevelText (harmless if hidden) so any future reparent stays class-colored.
--
-- Class color via NE.color.WrapClass (RAID_CLASS_COLORS-backed). Two-line rule: when the guild line
-- shows, the level line lifts to keep the pair centered as a block (retail PaperDollFrame_SetLevel).
--
-- GRACEFUL DEGRADATION (§B): every getter pcall-safe; if the Inset isn't built yet we just skip and
-- re-run on the next event. Never errors out of boot.

local NE = DragonUI_NewEra
NE.charpanel = NE.charpanel or {}
local CP = NE.charpanel

local MODULE = "character"

local function log(msg) if CP._log then CP._log(msg) elseif NE.Log then NE.Log("CHARPANEL", msg) end end

-- Build the "Level N Race ClassColored" string. Shared so the stock + our own FontStrings match.
local function buildColoredLevelText()
  local level = UnitLevel("player") or 1
  local raceName = UnitRace("player") or ""
  local classDisplay, classFile = UnitClass("player")
  classDisplay = classDisplay or ""
  local coloredClass = (NE.color and NE.color.WrapClass)
    and NE.color.WrapClass(classFile, classDisplay) or classDisplay
  return string.format("Level %d %s %s", level, raceName, coloredClass)
end

-- Our own guild string (GUILD_TITLE_TEMPLATE = "%s of <%s>"). Returns nil if not guilded.
local function buildGuildText()
  local guildName, title = GetGuildInfo("player")
  if not guildName then return nil end
  local tmpl = _G.GUILD_TITLE_TEMPLATE or "%s of %s"
  return string.format(tmpl, title or "", guildName)
end

-- Level-line Y: retail's two-line rule — lift to -36 when the guild line shows beneath, else -42.
local function levelTextY(guilded)
  return guilded and -36 or -42
end

-- Lazily create our level + guild FontStrings. DOWNPORT/REPORT: faithful NewEra — centered on the
-- FRAME top (CENTER,frame.TOP,(0,-36/-42)). The character NAME is shown in the title bar
-- (CharacterPanel.updateTitle); the level line sits centered at the frame top, guild just below it.
local function ensureOwnFontStrings()
  if CP._levelFS and CP._guildFS then return true end
  local f = CP.frame
  if not (f and f.Inset) then return false end

  if not CP._levelFS then
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    CP._levelFS = fs
  end
  if not CP._guildFS then
    local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    CP._guildFS = fs
  end
  return true
end

-- DOWNPORT/REPORT: faithful NewEra — the level line is centered on the FRAME TOP at CENTER(0, Y),
-- where Y = -36 when a guild line shows beneath, else -42 (retail PaperDollFrame_SetLevel two-line
-- rule). Reverted the prior "anchor under the title FS" change. The character NAME stays in the title
-- bar (CharacterPanel.updateTitle); guild, if any, sits just below the level line.
local function anchorHeader(guilded)
  local f = CP.frame
  if not (f and CP._levelFS) then return end
  CP._levelFS:ClearAllPoints()
  CP._guildFS:ClearAllPoints()
  CP._levelFS:SetPoint("CENTER", f, "TOP", 0, levelTextY(guilded))
  if guilded then
    CP._guildFS:SetPoint("TOP", CP._levelFS, "BOTTOM", 0, -2)
  end
end

local function applyLevelText()
  -- (1) Recolor the stock CharacterLevelText if present (covers a future reparent).
  if _G.CharacterLevelText and _G.CharacterLevelText.SetText then
    pcall(function() _G.CharacterLevelText:SetText(buildColoredLevelText()) end)
  end

  -- (2) Drive OUR OWN FontStrings — the ones that actually render in the custom frame.
  if not ensureOwnFontStrings() then return end

  local levelFS, guildFS = CP._levelFS, CP._guildFS
  levelFS:SetText(buildColoredLevelText())

  local guildStr = buildGuildText()
  if guildStr then
    guildFS:SetText(guildStr)
    guildFS:Show()
  else
    guildFS:SetText("")
    guildFS:Hide()
  end

  -- Anchor the lines in the header band above the Inset (centered over the model).
  anchorHeader(guildStr ~= nil)
end

CP.ApplyLevelText = applyLevelText

-- Once-only hook guards (session upvalues).
local setLevelHooked, setGuildHooked

local function installHooks()
  if _G.PaperDollFrame_SetLevel and not setLevelHooked then
    setLevelHooked = true
    hooksecurefunc("PaperDollFrame_SetLevel", function() pcall(applyLevelText) end)
  end
  if _G.PaperDollFrame_SetGuild and not setGuildHooked then
    setGuildHooked = true
    hooksecurefunc("PaperDollFrame_SetGuild", function() pcall(applyLevelText) end)
  end
end

local boot = CreateFrame("Frame")
boot:RegisterEvent("PLAYER_LOGIN")
boot:RegisterEvent("PLAYER_ENTERING_WORLD")
boot:RegisterEvent("PLAYER_LEVEL_UP")
boot:RegisterEvent("PLAYER_GUILD_UPDATE")
boot:RegisterEvent("UNIT_LEVEL")
boot:SetScript("OnEvent", function(_, event, unit)
  if NE.modules and NE.modules.IsEnabled and not NE.modules.IsEnabled(MODULE) then return end
  if event == "UNIT_LEVEL" and unit and unit ~= "player" then return end
  local ok, err = pcall(function() installHooks(); applyLevelText() end)
  if not ok then log("LevelText boot failed: " .. tostring(err)) end
end)
