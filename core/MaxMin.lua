-- DragonUI_NewEra/core/MaxMin.lua — NE.maxmin: the retail maximize / minimize button pair.
--
-- DOWNPORT of NewEra Core/Chrome/MaxMin.lua (Classic 1.15). The 1.15 source RESKINS Era's shipped
-- `MaximizeMinimizeButtonFrameTemplate` — 32x32 with the old UI-Panel-Bigger/SmallerButton art —
-- down to 24x24 on retail's RedButton-Expand / RedButton-Condense atlases. **3.3.5a ships no such
-- template**, so this BUILDS the button instead of reskinning one, exposing the same surface the
-- source's callers use (`SetOnMaximizedCallback` / `SetOnMinimizedCallback` / `SetMaximizedLook` /
-- `SetMinimizedLook`) so ported call sites read the same.
--
-- ONE BUTTON, NOT TWO. Retail's template is a frame holding a MaximizeButton and a MinimizeButton
-- and shows exactly one at a time. A single button whose art swaps is the same thing with half the
-- widgets, and it sidesteps the naming trap the 1.15 source spends a paragraph on (`SetMinimizedLook`
-- reveals the MAXIMIZE button). Here the rule is stated once and directly:
--
--     currently MINIMIZED  ->  offer the maximize action  ->  show the EXPAND glyph
--     currently MAXIMIZED  ->  offer the minimize action  ->  show the CONDENSE glyph
--
-- ONE FLAG, NEVER TWO. The glyph and the tooltip are the same decision rendered twice, so they read
-- the same source -- and that source is the OWNER'S live state, not a copy kept here.
--
-- The copy is what went wrong. This button used to cache `_maximized` and both symptoms of it
-- disagreeing with the window ("the arrows point the wrong way", "the tooltip names the wrong
-- action") looked like separate art bugs, which cost a wrong fix: the atlas mapping was swapped on
-- the strength of one of them while the real fault -- a cached flag out of step with the window --
-- went untouched and the other symptom survived. `stateFunc` removes the copy: when the owner can
-- answer "am I maximized?", the button asks, every time it draws or is hovered.
--
-- Art is the RedButton family on sheet 4698972, already shipped for the X close button and
-- registered in core/NineSliceLayouts.lua — so no new BLP, and the button matches the close button
-- it sits beside. If the atlas is missing the button still builds and still works; it just draws
-- with no glyph, which is the same graceful-degrade contract PanelChrome keeps.
--
-- NOT PROTECTED. Building a Button, swapping its textures and running an OnClick that resizes an
-- unprotected frame are all insecure-safe. Callers whose resize touches a protected frame must do
-- their own combat deferral (NE.FrameUtil.AfterCombat) — this file never does it for them, because
-- swallowing a click silently is worse than the caller knowing.
--
-- The spellbook (modules/spellbook/Window.lua buildMinimize) has an older inline copy of this,
-- written before there was a shared helper. It works and is left alone; migrating it is a tidy-up,
-- not a fix.

local NE = DragonUI_NewEra
if not NE or NE.disabled then return end

NE.maxmin = NE.maxmin or {}
local MM = NE.maxmin

local SIZE = 24   -- retail's; matches PanelChrome.ModernizeCloseButton's default

-- Build (or return) the maximize/minimize button on `parent`.
--
-- opts:
--   name        (string)   global name for the button; nil for anonymous
--   anchorTo    (region)   sit immediately left of this (normally the close button)
--   size        (number)   default 24
--   frameLevel  (number)   absolute frame level; defaults to parent's + 21 (above the chrome stack,
--                          the same lift PanelChrome gives the close button)
--   maximized   (bool)     initial state; default false (minimized)
--   onMaximize  (function) called when the user clicks while minimized
--   onMinimize  (function) called when the user clicks while maximized
--   tooltipMax  (string)   tooltip shown while the EXPAND glyph is up
--   tooltipMin  (string)   tooltip shown while the CONDENSE glyph is up
function MM.Build(parent, opts)
  if not parent then return nil end
  if parent._neMaxMin then return parent._neMaxMin end
  opts = opts or {}

  local b = CreateFrame("Button", opts.name, parent)
  local size = opts.size or SIZE
  b:SetSize(size, size)

  if opts.anchorTo then
    b:SetPoint("RIGHT", opts.anchorTo, "LEFT", -1, 0)
  else
    b:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -(size + 3), 0)
  end

  local base = (parent.GetFrameLevel and parent:GetFrameLevel()) or 1
  b:SetFrameLevel(opts.frameLevel or (base + 21))

  -- DOWNPORT, and the one thing in this file worth being careful about. There are two ways to give
  -- a Button its state textures on 3.3.5a and the repo contains evidence for both:
  --   * modules/spellbook/Window.lua builds this same button by passing CreateTexture OBJECTS to
  --     SetNormalTexture, and it ships and works.
  --   * core/PanelChrome.lua's ModernizeCloseButton records the opposite — "passing an object
  --     silently no-ops → blank button — the bug we chased" — and uses the PATH form instead.
  -- Rather than pick a side, seed each state from a PATH (which creates the texture whichever
  -- behaviour is true) and then drive the crop through the Get*Texture handle. That is correct
  -- under both readings, and it is PanelChrome's own pattern, so the close button and the button
  -- beside it are built the same way.
  local SHEET = 4698972   -- the RedButton sheet, shipped for the X close button
  local seed = (NE.tex and NE.tex.Local and NE.tex.Local(SHEET))
               or "Interface\\Buttons\\UI-Panel-MinimizeButton-Up"
  b:SetNormalTexture(seed)
  b:SetPushedTexture(seed)
  b:SetHighlightTexture(seed)
  local nt, pt, ht = b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture()
  for _, t in ipairs({ nt, pt, ht }) do
    if t and t.SetAllPoints then t:SetAllPoints(b) end
  end
  if ht and NE.tex and NE.tex.SetAtlas then
    NE.tex.SetAtlas(ht, "redbutton-highlight-2x", false)
    if ht.SetBlendMode then ht:SetBlendMode("ADD") end
  end

  b._maximized = opts.maximized and true or false

  local function syncIcon()
    if not (NE.tex and NE.tex.SetAtlas) then return end
    local base = b:IsMaximized() and "redbutton-condense" or "redbutton-expand"
    -- Recorded so the diagnostic can report which glyph is actually on the button. Reading
    -- `_neAtlas` was useless for that: it belongs to the status-bar helper and holds coordinates.
    if nt and NE.tex.SetAtlas(nt, base .. "-2x", false) then b._neGlyph = base end
    if pt then NE.tex.SetAtlas(pt, base .. "-pressed-2x", false) end
  end

  -- The source's surface, so ported call sites read unchanged. Both are pure visual — no callback,
  -- no state write beyond the flag the glyph is drawn from.
  function b:SetMaximizedLook() b._maximized = true;  syncIcon() end
  function b:SetMinimizedLook() b._maximized = false; syncIcon() end

  -- The owner's answer wins when there is one. A cached flag can drift from the window it describes;
  -- a question asked at draw time cannot.
  b._stateFunc = opts.stateFunc
  function b:SetStateFunc(fn) b._stateFunc = fn; syncIcon() end
  function b:IsMaximized()
    if b._stateFunc then
      local ok, v = pcall(b._stateFunc)
      if ok and v ~= nil then return v and true or false end
    end
    return b._maximized
  end

  function b:SetOnMaximizedCallback(fn) b._onMax = fn end
  function b:SetOnMinimizedCallback(fn) b._onMin = fn end
  b._onMax = opts.onMaximize
  b._onMin = opts.onMinimize

  -- Set the state WITHOUT firing a callback — for a caller reconciling against a saved preference
  -- on open, which must not be mistaken for the user clicking.
  function b:SetStateSilently(maximized)
    b._maximized = maximized and true or false
    syncIcon()
  end

  b:SetScript("OnClick", function(self)
    -- THE ACTION READS THE SAME SOURCE AS THE LABEL. This used to branch on the cached `_maximized`
    -- while the glyph and tooltip went through IsMaximized() -- so on a window that had reached full
    -- size WITHOUT being in maximize mode (dragged there, or grown while the quest panel was hidden)
    -- the button read "Minimize" and maximized instead, shrinking the window to the preset. Which
    -- looks precisely like "maximize stopped giving me the larger window".
    --
    -- One source for what the button SAYS and what it DOES, or they disagree again.
    local goingMax = not self:IsMaximized()
    self._maximized = goingMax

    -- THE CALLBACK FIRST, THE ART AFTER. `IsMaximized` prefers the owner's live answer, and the owner
    -- has not changed its mind yet at this point in the click -- so drawing here draws the state we
    -- are LEAVING. It used to self-correct only because the world map happens to call
    -- SetStateSilently on the way back through; an owner that does not leaves the button showing the
    -- opposite of what it is, permanently, in both the glyph and the tooltip.
    local fn = goingMax and self._onMax or self._onMin
    if fn then
      local ok, err = pcall(fn, goingMax)
      if not ok and NE.Log then NE.Log("MAXMIN", "callback error: " .. tostring(err)) end
    end
    syncIcon()
  end)

  b:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    -- Same source as the glyph, so the two cannot name different actions.
    local text = self:IsMaximized() and (opts.tooltipMin or MINIMIZE or "Minimize")
                                     or (opts.tooltipMax or MAXIMIZE or "Maximize")
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:SetText(text)
    GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)

  syncIcon()
  parent._neMaxMin = b
  return b
end
