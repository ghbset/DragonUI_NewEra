-- DragonUI_NewEra/core/_HelloDemo.lua — Sprint-0 exit proof.
--
-- Registers slash /dnehello: builds a STANDALONE CreateFrame and runs NE.chrome.Apply to render a
-- Dragonflight portrait-frame on it (title "New Era — Hello", a portrait, a close button). It must
-- DEGRADE GRACEFULLY if the metal atlas art isn't registered yet — NE.chrome.Apply already falls
-- back to a solid colour + flat border, and we additionally print a warning so the tester knows
-- the art layer (Textures/Assets.lua, §3) hasn't landed. It must never hard-error.
--
-- Also registers itself into NE.qa.modules so the QA harness (/dnetest) can open/close it.

local NE = DragonUI_NewEra

local FRAME_NAME = "DragonUI_NewEra_HelloDemo"

local function chat(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff1784d1DragonUI NewEra|r " .. msg)
  end
end

local demoFrame   -- created lazily on first /dnehello (so the chrome toolkit is fully loaded)

local function buildDemo()
  if demoFrame then return demoFrame end

  -- Standalone frame — NOT a Blizzard panel (that's Sprint 1). Named so the QA harness can find it.
  local f = CreateFrame("Frame", FRAME_NAME, UIParent)
  f:SetSize(338, 424)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()

  -- Detect whether the Sprint-0 metal art is registered so we can warn (but still render).
  local artReady = NE.tex and NE.tex.HasAtlas and NE.tex.HasAtlas("ui-frame-portraitmetal-cornertopleft-2x")
    and NE.tex.localFiles and NE.tex.localFiles[2406979] ~= nil

  -- THE proof: turn the bare frame into a DF portrait-frame via the §2 chrome entry. Wrapped in
  -- pcall so a not-yet-shipped art layer can never hard-error the demo.
  local ok, err = pcall(function()
    NE.chrome.Apply(f, {
      layout  = "PortraitFrameTemplate",
      title   = "New Era — Hello",
      -- No portrait art supplied → PanelChrome defaults to the player portrait (native circular).
      pixelPerfect = true,
    })
  end)

  NE._helloApplyOk  = ok
  NE._helloApplyErr = (not ok) and err or nil
  if not ok then
    chat("|cffff5555Hello demo: chrome Apply errored:|r " .. tostring(err))
    -- Minimal fallback so the frame is still visible/closable.
    if f.SetBackdrop then
      f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 },
      })
    end
    if not f.CloseButton then
      f.CloseButton = CreateFrame("Button", nil, f, "UIPanelCloseButton")
      f.CloseButton:SetPoint("TOPRIGHT", 1, 0)
    end
  end

  -- A line of body text so the panel content area reads as populated.
  local body = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  body:SetPoint("TOP", f, "TOP", 0, -64)
  body:SetWidth(280)
  body:SetJustifyH("CENTER")
  if artReady then
    body:SetText("Sprint-0 chrome OK.\nPortrait-frame nineslice + portrait + close button rendered from the downported Core toolkit.")
  else
    body:SetText("Sprint-0 chrome (degraded).\nMetal atlas art not registered yet — showing the solid-colour fallback. Ship Textures/Assets.lua to render the real frame.")
    chat("|cffffcc00Hello demo: metal atlas art not registered (Textures/Assets.lua pending) — rendered the graceful fallback.|r")
  end

  demoFrame = f
  return f
end

local function openDemo()
  local f = buildDemo()
  f:Show()
  return f
end

local function closeDemo()
  if demoFrame then demoFrame:Hide() end
end

-- Slash command.
SLASH_DNEHELLO1 = "/dnehello"
SlashCmdList["DNEHELLO"] = function()
  local f = openDemo()
  if f and f:IsShown() then
    chat("Hello demo shown (/dnehello). Drag to move; close button to dismiss.")
  end
end

-- Build the frame eagerly (hidden) at boot so the QA registry can carry the actual `frame`
-- handle per the §2 spec. Wrapped in pcall + deferred via C_Timer so a not-yet-loaded sibling
-- can't break load order; build at file scope is safe (CreateFrame + chrome are all available).
local builtOk = pcall(buildDemo)

-- Register into the QA harness registry. NE.qa.modules is seeded by bootstrap.lua.
NE.qa = NE.qa or { modules = {} }
NE.qa.modules = NE.qa.modules or {}
NE.qa.modules[#NE.qa.modules + 1] = {
  name  = "HelloDemo",
  frame = demoFrame,                               -- the actual frame (built above) per §2 spec
  getFrame = function() return demoFrame or _G[FRAME_NAME] end,
  open  = function() openDemo() end,
  close = function() closeDemo() end,
}

if not builtOk then
  chat("|cffffcc00Hello demo: deferred build (will construct on first /dnehello).|r")
end
