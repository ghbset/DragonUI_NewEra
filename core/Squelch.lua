-- DragonUI_NewEra/core/Squelch.lua — NE.squelch: keep a Blizzard region hidden for good.
--
-- DOWNPORT of NewEra Core/Squelch.lua (Classic 1.15). Every reskin in this addon has the same
-- problem: FrameXML re-Shows the art we hid. A one-shot `:Hide()` holds only until the next
-- update pass runs, and the classic chrome comes back. Each module has so far solved it its own
-- way — the merchant re-runs its whole `hideClassicChrome` on every update hook, the inspect
-- window squelches regions one at a time — which works but means every module carries the same
-- few lines.
--
-- The case that forces a shared helper is a FrameXML window that repaints its own chrome from a
-- path we do not own — a size toggle that re-Shows the borders, the title and the dropdowns on
-- *every* change, with no single update hook to hang a sweep off.
--
-- WHAT IT DOES. `NE.squelch.Hide(region)` hides the region and installs an `OnShow` hook that
-- re-hides it. That covers Frames (which have OnShow scripts). Textures and FontStrings do NOT
-- have scripts, so for those the region's own `Show` method is swapped for a no-op — the caller's
-- Show() silently does nothing instead of erroring, which is what FrameXML expects.
--
-- NOT PROTECTED, NOT SECURE. Hiding a region and replacing a non-secure region's Show method are
-- both insecure-safe operations on unprotected art; no squelched region is ever a protected frame
-- (callers must not pass one — see `NE.squelch.IsProtectedish`). Nothing here calls Show/Hide on a
-- *protected* frame, so none of this is combat-gated.
--
-- REVERSIBLE. `NE.squelch.Restore(region)` puts the original Show back and un-hooks, so a module
-- that is turned off mid-session can hand the client's art back. (The addon's own toggles are
-- reload-gated, so this is for diagnostics more than for the options screen.)

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.squelch = NE.squelch or {}
local S = NE.squelch

-- region -> { show = <original Show>, hooked = true }
S.registry = S.registry or {}

-- A frame that is protected (or is a child of one) must never be Show/Hide'd from insecure code in
-- combat. Nothing this addon squelches is protected — the classic border art, titles and dropdowns
-- are all plain decoration — but the check is cheap and turns a silent in-combat error into a
-- refusal we can see in the log.
function S.IsProtectedish(region)
  if not region or not region.IsProtected then return false end
  local ok, protected = pcall(region.IsProtected, region)
  return ok and protected and true or false
end

local function noop() end

-- Hide a region and keep it hidden. Idempotent: squelching twice is a no-op, and the ORIGINAL Show
-- is only ever captured once (capturing our own noop as "the original" would make Restore a lie).
function S.Hide(region)
  if not region then return false end
  if S.registry[region] then
    -- Already squelched; just re-assert the hide in case something forced it visible another way.
    if region.Hide then pcall(region.Hide, region) end
    return true
  end
  if S.IsProtectedish(region) then
    if NE.Log then NE.Log("SQUELCH", "refused: region is protected") end
    return false
  end

  local entry = {}

  -- Frames get an OnShow hook, which catches the paths that bypass Show() entirely (a parent being
  -- shown, or the C side revealing a child). The hook reads the registry rather than closing over
  -- a boolean, so Restore below genuinely un-squelches instead of leaving an un-removable re-hide
  -- behind — HookScript is append-only on 3.3.5a, so the hook itself can never be taken off.
  if region.HookScript and region.GetObjectType and region:GetObjectType() ~= "Texture"
     and region:GetObjectType() ~= "FontString" then
    local ok = pcall(region.HookScript, region, "OnShow", function(self)
      if S.registry[self] then self:Hide() end
    end)
    entry.hooked = ok and true or false
  end

  -- Textures and FontStrings have no scripts at all, so the only lever is the Show method itself.
  -- Frames get this too, as a belt: an OnShow hook fires AFTER the frame has drawn once, which can
  -- flash the classic art for a frame; swapping Show stops it drawing in the first place.
  if region.Show then
    entry.show = region.Show
    region.Show = noop
  end

  S.registry[region] = entry
  if region.Hide then pcall(region.Hide, region) end
  return true
end

-- Squelch a list of GLOBAL names. Missing names are skipped silently — a downport routinely names
-- widgets that only some clients define, and "this client doesn't have it" is not an error.
function S.HideGlobals(names)
  if type(names) ~= "table" then return end
  for _, name in ipairs(names) do
    local r = _G[name]
    if r then S.Hide(r) end
  end
end

-- Hand a region back to the client. The registry entry is cleared FIRST so the OnShow hook (which
-- reads it) becomes inert, then the original Show is put back — so a Show() after this both works
-- and sticks.
function S.Restore(region)
  local entry = region and S.registry[region]
  if not entry then return false end
  S.registry[region] = nil
  if entry.show then region.Show = entry.show end
  return true
end

-- Restore everything. Diagnostics only; the module toggles are reload-gated.
function S.RestoreAll()
  for region in pairs(S.registry) do S.Restore(region) end
end

function S.IsSquelched(region)
  return region ~= nil and S.registry[region] ~= nil
end
