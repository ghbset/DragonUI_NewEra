-- DragonUI_NewEra/modules/character/EditModeRegister.lua — INTENTIONALLY REGISTERS NOTHING.
--
-- ARCHITECTURE PIVOT (CONTRACT_S1 §A0): the character panel is now our CUSTOM frame
-- (NE.charpanel.frame = "DragonUI_NewEra_Character"), opened/closed like a UIPanel window. Per the
-- project's Edit Mode scope rule (Edit Mode is scoped to always-on HUD frames, NOT toggled windows
-- like Merchant/Mail/Bank/Gossip/Character) and retail's own behaviour (panels live in window slots,
-- not as EditModeSystems), the character panel must NOT get an Edit Mode handle.
--
-- 3.3.5a additionally has no native Edit Mode at all; even if a DragonUI Edit Mode shim exists, a
-- handle over the closed panel's slot would render an empty mystery box. If panel scaling/position is
-- ever wanted, surface it in the New Era options tab (CharacterPanel.lua already registers there),
-- not Edit Mode. (The custom frame IS movable — drag the title band — see CharacterPanel.lua.)
--
-- This file is kept (rather than deleted) so the load order in the TOC stays stable and the decision
-- is documented at the point a future maintainer would look for it.

local NE = DragonUI_NewEra
-- (no-op: registers nothing by design)
