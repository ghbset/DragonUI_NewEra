-- DragonUI_NewEra/modules/bossmods/Assets.lua — art for the Boss Timers port.
--
-- Downport of ReferenceAddons/NewEra/Alerts/BossMods/Assets.lua. That file registered the sheet
-- BLPs and relied on NewEra's Generated/AtlasData.lua for the texcoords; this addon ships no such
-- generated table, so the rects we actually use are inlined here (values copied verbatim from
-- ReferenceAddons/NewEra/Generated/AtlasData.lua:2507-2540 and :4164).
--
-- DOWNPORT: the two MASK sheets the source also registered (7390391 combattimeline-line-break-mask,
-- 7393789 combattimeline-fx-highlight-mask) are NOT shipped. Frame:CreateMaskTexture returns nil on
-- 3.3.5a — !!!ClassicAPI declares it Private.Void — so a mask atlas has nothing to be applied to.
-- See PORT_PLAN.md §C.3 for what stands in: a 0.07-0.93 texcoord trim for the icon rounding (the
-- same fallback modules/cooldownviewer/ItemMixins.lua takes), and the rail ticks were already solid
-- dashes drawn over an unbroken line rather than mask-cut gaps.
--
-- Shared Cooldown Manager atlases this port also uses are registered by
-- modules/cooldownviewer/Assets.lua, which the TOC loads before us:
--   UI-HUD-CoolDownManager-IconOverlay / -Bar / -Bar-BG / -Bar-Pip   (fdid 6704514)

local NE = DragonUI_NewEra
if not (NE and NE.tex and NE.tex.RegisterLocal) then return end

local PATH = "Interface\\AddOns\\DragonUI_NewEra\\Textures\\BossMods\\"

-- 7389803 — the `combattimeline` sheet: rail halves, pip, divider, icon-trail, and the icon-state
-- FX (deadlyglow / pause / queued / highlight). The whole Timeline (rail) view comes off this one.
NE.tex.RegisterLocal(7389803, PATH .. "7389803-combattimeline.blp")
-- 7499559 — `damagemeters-background`: the Bars-view background plate (default alpha 0, exposed
-- as the "Background" slider).
NE.tex.RegisterLocal(7499559, PATH .. "7499559-damagemeters-background.blp")

NE.tex.RegisterAtlases({
  -- ── the rail itself ───────────────────────────────────────────────────────────────────────────
  -- line-left/-right are the two halves of the (continuous) rail line, authored HORIZONTAL at
  -- 193x14. We rotate them to vertical with the 8-arg SetTexCoord, so callers need the raw rect —
  -- hence they read it back through NE.tex.GetAtlasRect rather than letting SetAtlas set it.
  ["combattimeline-line-left"]            = { file = 7389803, left = 0.694336, right = 0.882812, top = 0.000977, bottom = 0.014648, width = 193, height = 14 },
  ["combattimeline-line-right"]           = { file = 7389803, left = 0.694336, right = 0.882812, top = 0.016602, bottom = 0.030273, width = 193, height = 14 },
  ["combattimeline-line-shadow-vertical"] = { file = 7389803, left = 0.000977, right = 0.056641, top = 0.058594, bottom = 0.750000, width = 57,  height = 708 },
  -- The same plate authored the other way, for a horizontal rail (the Orientation setting).
  ["combattimeline-line-shadow"]          = { file = 7389803, left = 0.000977, right = 0.692383, top = 0.000977, bottom = 0.056641, width = 708, height = 57 },
  ["combattimeline-line-icontrail"]       = { file = 7389803, left = 0.884766, right = 0.916016, top = 0.000977, bottom = 0.002930, width = 32,  height = 2 },
  ["combattimeline-pip"]                  = { file = 7389803, left = 0.712891, right = 0.728516, top = 0.032227, bottom = 0.047852, width = 16,  height = 16 },
  ["combattimeline-cooldown-divider"]     = { file = 7389803, left = 0.000977, right = 0.055664, top = 0.751953, bottom = 0.796875, width = 56,  height = 46 },

  -- ── per-icon state FX (EventIcon.lua) ─────────────────────────────────────────────────────────
  ["combattimeline-fx-deadlyglow-base"]    = { file = 7389803, left = 0.166016, right = 0.250000, top = 0.058594, bottom = 0.142578, width = 86,  height = 86 },
  ["combattimeline-fx-deadlyglow-overlay"] = { file = 7389803, left = 0.251953, right = 0.335938, top = 0.058594, bottom = 0.142578, width = 86,  height = 86 },
  ["combattimeline-fx-pause"]              = { file = 7389803, left = 0.423828, right = 0.507812, top = 0.058594, bottom = 0.142578, width = 86,  height = 86 },
  ["combattimeline-fx-pause-icon"]         = { file = 7389803, left = 0.000977, right = 0.024414, top = 0.798828, bottom = 0.824219, width = 24,  height = 26 },
  ["combattimeline-fx-queued"]             = { file = 7389803, left = 0.509766, right = 0.593750, top = 0.058594, bottom = 0.142578, width = 86,  height = 86 },
  ["combattimeline-fx-queued-icon"]        = { file = 7389803, left = 0.694336, right = 0.710938, top = 0.032227, bottom = 0.048828, width = 17,  height = 17 },
  ["combattimeline-fx-highlight"]          = { file = 7389803, left = 0.337891, right = 0.421875, top = 0.058594, bottom = 0.142578, width = 86,  height = 86 },
  -- NOT DRAWN, deliberately, and kept only so the decision is visible where someone would look for
  -- it. This is retail's highlight swirl, which it clips to the icon with a MaskTexture; the sheet
  -- itself is a FILLED quad (centre alpha 211 against the ring's 38), so unmasked at 108x108 over a
  -- 35px icon it is a solid disc, not a flourish. EventIcon.lua carries the measurement and the
  -- reasoning; modules/cooldownviewer/Alerts.lua declined retail's PandemicFX quads identically.
  ["combattimeline-fx-highlight-fx"]       = { file = 7389803, left = 0.058594, right = 0.164062, top = 0.058594, bottom = 0.164062, width = 108, height = 108 },

  -- ── Bars-view plate ───────────────────────────────────────────────────────────────────────────
  ["damagemeters-background"] = { file = 7499559, left = 0.001953, right = 0.302734, top = 0.003906, bottom = 0.582031, width = 154, height = 148 },
})
