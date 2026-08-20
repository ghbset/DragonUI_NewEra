-- DragonUI_NewEra/modules/merchant/Register.lua — boot wiring for the merchant window reskin.
--
-- MerchantFrame is always loaded (not LoadOnDemand), so the gate is the ordinary one: PLAYER_LOGIN
-- arms the classic-art suppression and the update hooks, and the first MERCHANT_SHOW builds the
-- chrome. Reload-gated like every other window toggle — turning the module off writes the flag and
-- the next /reload simply never boots it, leaving Blizzard's vendor window untouched.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

local Merch = NE.merchant
local L = NE.L
if not Merch then return end

local MODULE = "MerchantFrame"

local function boot(event)
  if event == "MERCHANT_SHOW" then
    -- First vendor of the session builds the chrome; later fires are a no-op (build-once guard).
    if Merch.BuildModernChrome then Merch.BuildModernChrome() end
    return
  end
  -- PLAYER_LOGIN.
  if Merch.Arm then Merch.Arm() end
end

if NE.modules and NE.modules.Register then
  NE.modules.Register{
    name     = MODULE,
    default  = true,
    label    = L["Merchant window"],
    category = "Windows",
    -- Same string the options row renders (integration/Options.lua): one key, one translation.
    desc     = L["Modern frame, portrait and tabs on the vendor window, plus a sell-all-junk button "
             .. "and the buyback undo arrow. Reload (/reload) to apply."],
    events   = { "PLAYER_LOGIN", "MERCHANT_SHOW" },
    onBoot   = boot,
  }
end

-- ----------------------------------------------------------------------------
-- QA harness entry (optional; guarded). The vendor window cannot be opened without a live merchant
-- NPC, so `open` is a no-op unless one is already talking to us — the honest result for a window
-- with no client-side opener.
-- ----------------------------------------------------------------------------
if NE.qa then
  NE.qa.modules = NE.qa.modules or {}
  table.insert(NE.qa.modules, {
    name  = L["Merchant window"],
    frame = _G.MerchantFrame,
    open  = function()
      if _G.MerchantFrame and UnitExists("npc") and _G.ShowUIPanel then
        ShowUIPanel(_G.MerchantFrame)
      end
    end,
    close = function()
      local f = _G.MerchantFrame
      if f and f:IsShown() then
        if HideUIPanel then HideUIPanel(f) else f:Hide() end
      end
    end,
  })
end
