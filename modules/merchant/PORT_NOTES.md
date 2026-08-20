# Merchant — port notes

Downport of `NewEra/MerchantFrame/` (Classic 1.15) onto 3.3.5a. Source files and what became of
them:

| 1.15 source | here | note |
|---|---|---|
| `Assets.lua` | `Assets.lua` | same art; atlas rects registered through `NE.tex.RegisterAtlases` instead of the retail-only `NE_ATLAS` global |
| `MerchantFrame.lua` | `MerchantFrame.lua` | chrome half re-derived against the 3.3.5a frame (see below) |
| `SellAllJunk.lua` | `SellAllJunk.lua` | bag walk rewritten off `GetItemInfo`; confirmation is a real `StaticPopupDialogs` entry |
| `BuybackUndo.lua` | `BuybackUndo.lua` | unchanged in substance |
| — | `Register.lua` | the module entry; the 1.15 source registered inline at the bottom of `MerchantFrame.lua` |
| — | `Diagnostics.lua` | `/nemerchant`, a report-only state dump (see the bottom of this file) |

## Why the chrome half is re-derived rather than transcribed

Era's `MerchantFrame` inherits `ButtonFrameTemplate`, so the 1.15 source could hide `f.NineSlice`'s
template pieces and re-texture them in place, write the NPC name into `f.TitleContainer.TitleText`,
and paint the masked `f.PortraitContainer.portrait`.

On 3.3.5a the frame is a 384x512 classic wooden panel: four corner quadrants, a `MerchantNameText`
FontString for the title, `MerchantFramePortrait` for the face, and none of the modern subframes. So:

* the nineslice, the rock body fill and `f.Bg` are **built** by `PanelChrome`'s ensure\* path, not
  re-textured;
* the corner quadrants are unnamed in the XML **and sit on the BORDER layer**, with the buyback
  tab's own wooden backdrop (`BuybackFrameTopLeft` … `BotRight`) a layer above that on ARTWORK.
  PanelChrome's walk only covers BACKGROUND — all a `ButtonFrameTemplate` frame needs — so
  `hideClassicChrome` walks those two layers itself, matching on texture path, and re-runs after
  every update because `_UpdateMerchantInfo` / `_UpdateBuybackInfo` re-show the per-tab pieces;
* the title is rehosted into PanelChrome's title band, and `postMerchantUpdate` mirrors whatever
  FrameXML just wrote into the (now hidden) `MerchantNameText`;
* `MerchantFramePortrait` **is** the portrait — kept (via `PC.Keep`, so the walk does not take it)
  and seated in the metal ring with `NE.portrait.ApplyCutout`;
* `f.CloseButton` does not exist as a field; the global `MerchantFrameCloseButton` is adopted onto
  it so `PC.ModernizeCloseButton` reskins the real button.

## What has no counterpart on this client

* **`MerchantFrameItem_UpdateQuality`.** An Era function; 3.3.5a has none. The per-row name colour
  and quest bang hang off `MerchantFrame_UpdateMerchantInfo` / `_UpdateBuybackInfo` instead, with
  FrameXML's own row-index → link math.
* **The rarity BORDER.** Deliberately not ours. 3.3.5a's `ItemButtonTemplate` has no `IconBorder`,
  so `NE.itembutton.ApplyQuality` cannot paint one, and DragonUI's `itemquality` module already
  draws its own overlay on merchant buttons — a second one reads as a double border.
* **`MerchantFrame_RegisterForQualityUpdates`.** Absent; `Register`/`Arm` watches
  `GET_ITEM_INFO_RECEIVED` directly and re-runs the colour pass for the visible tab.
* **A close button that PanelChrome will lift by itself.** `MerchantFrameCloseButton` is adopted
  onto `f.CloseButton`, and PanelChrome only raises a close button it BUILT — so the adopted one
  needs an explicit `frameLevelBump`, or the nineslice (frame+1) and title band (frame+11) render
  over its X and only its highlight bleeds through on hover.
* **`StaticPopup_ShowCustomGenericConfirmation`**, **`SELL_ALL_JUNK_ITEMS`**,
  **`SELL_ALL_JUNK_ITEMS_POPUP`.** None exist here; the popup is a normal `StaticPopupDialogs`
  entry and both strings route through `NE.L`.
* **`C_MerchantFrame.GetNumJunkItems` / `SellAllJunkItems`.** Retail-only on every Classic-family
  client — the bag walk is the implementation on both.
* **`BuybackBG`.** An Era region; nothing to gate here.
* **The FilterDropdown.** Cut in the 1.15 source already (no `C_MerchantFilter` API), and still cut.
* **EditMode registration.** `MerchantFrame` is UIPanel-managed on this client, so it is not one of
  ours to move — same call the 1.15 source made.

## Deliberate divergences

* **`MERCHANT_ITEMS_PER_PAGE` is 10 here, not 12.** Rows 11 and 12 exist but only the buyback tab
  uses them, so every loop runs to `BUYBACK_ITEMS_PER_PAGE` with an existence guard and the merchant
  pass only walks the first 10.
* **The window is re-laid-out, not just re-skinned.** The client's numbers are built around its
  wooden art's transparent margins: a 384x512 frame whose 2x5 grid starts at (24,-80) — 11px from
  the left edge and 65 from the right, with ~50px of dead air above it and another ~90 between the
  grid and the buyback slot. Under a border that does not have those margins painted into it, the
  grid reads as jammed against the left edge with a hole in the middle. `applyLayout` re-sizes the
  frame to 334x468 and re-anchors the grid, the buyback slot, the page arrows, the page text and
  the money frame onto symmetric margins. Every number is a named constant in the Layout block at
  the top of `MerchantFrame.lua` — that block is the knob to turn if anything still sits wrong.
  It runs at login rather than with the deferred art build, so the first `ShowUIPanel` measures the
  final width.
* **The window is nudged off the screen edge.** Left-area panels sit flush against it here —
  `UIParent`'s `LEFT_OFFSET` is 0 and `UIPanelWindows["MerchantFrame"]` declares no `xoffset`. That
  is fine for a wooden frame whose art carried its own transparent margin and wrong for a modern one
  that is opaque to its edge. `applyPanelLayout` sets `UIPanelLayout-xoffset` to 6 — DragonUI's
  character-panel nudge, so the set lines up — on the FRAME's attributes rather than in
  `UIPanelWindows`, because writing that table taints the first panel open in combat. Since
  `GetUIPanelWindowInfo` copies the whole row onto the frame the first time it is asked and only
  then treats attributes as authoritative, the row's other fields are restated and `-defined` is set
  last to seal it. Same pattern, and the same reasoning, as `modules/inspect`.
* **The repair icons are not `$parentIcon`.** The XML names them `MerchantRepairAllIcon` (not
  `…ButtonIcon`) and `MerchantGuildBankRepairButtonIcon`, and `MerchantRepairItemButton`'s is
  anonymous. A `buttonName .. "Icon"` guess misses two of three, and a draw-layer fallback is not
  safe either — a Button's own Normal/Pushed textures are regions of that same button and can share
  the layer, so the scan can retexture one of those and leave the real icon untouched. `REPAIR_ICONS`
  names the two real globals and finds the anonymous one by the classic sheet's texture path.
* **There is no `MerchantMoneyInset` on this client** (that is an Era/retail frame) — the player's
  money floats on the classic bottom art. `buildMoneyInset` builds retail's recess for it instead.

## Matching retail's layout

Compared against retail's own merchant window, the pieces that were added rather than ported:

* **A recessed panel behind the grid.** Retail sinks the item rows *and* the pagination row into one
  inset, with the button bar outside it below. That panel is most of what makes the window read as
  retail's rather than as a grid floating on a slab, and this client has nothing like it — its
  wooden art implied the recess. `buildGridInset` builds it from the shared `InsetFrameTemplate`
  layout. It has to sit **below** the rows: a child frame defaults to parent+1, which is exactly
  where the row frames already are, and same-level siblings draw in creation order — so the panel,
  built later, would paint over the grid. `applyLayout` lifts the rows, arrows and money frame to
  parent+4.
* **Pagination across the full width.** Back arrow and its "Prev" caption at the left, the page count
  centred, "Next" and the forward arrow at the right — retail's arrangement. The captions are the
  client's own (`text="PREV"` resolves through `GlobalStrings` to "Prev"), and it already anchors
  each on retail's side of its button, so they are kept rather than hidden; only the buttons moved
  out to the edges. An earlier pass hid them, which was wrong — they only looked out of place while
  both arrows were still huddled under column one.
* **The buyback slot lives in the button bar.** Retail keeps it there, after the repair/sell cluster;
  the client parks it out in the middle of the window. `postRepairButtons` chains it off whichever
  button ends the cluster, so it follows every branch instead of being pinned to one. Its art is
  re-fitted by `fitBuybackToBar` — `reskinSlot` gives every row the grid's 64px recess and ring,
  which beside a row of ~44px tiles reads as a mistake.
* **Button recesses are sized to the button.** Retail's bar is a row of tiles barely wider than their
  icons. The `UI-EmptySlot` sheet's native 64 behind a 36px button spills 28px past it, so at any
  sane spacing neighbouring recesses merge into one smear. They now bleed `TILE_BLEED` past the
  button and no further.

Still not ported: **retail's filter dropdown** (the "Priest" control under the title bar). It runs on
`C_MerchantFilter`, which exists on no Classic-family client — the 1.15 source cut it for the same
reason. Recreating it would mean filtering client-side against each item's own usability, which is a
feature rather than a port.

## Tab switching

Three things the client does across a Merchant/Buyback switch that this window has to undo:

* **The row pitch changes.** `_UpdateBuybackInfo` re-anchors rows 3/5/7/9 to a **-15** gap and
  `_UpdateMerchantInfo` puts them back to -8 — the client stretching its six-row buyback grid down
  into the dead space its own layout had at the bottom. We do not have that space: the grid lives in
  a recessed panel sized for the merchant tab, so at -15 the last row hangs ~20px out through the
  bottom of it. Retail's buyback grid is evenly spaced with its merchant grid, so `restoreRowPitch`
  puts the pitch back after every buyback update.
* **The buyback slot can get stranded hidden.** `_UpdateBuybackInfo` hides `MerchantBuyBackItem`,
  and `_UpdateMerchantInfo` only re-Shows it inside `if (buybackName)` — never in the `else`. So
  returning to the merchant tab with nothing to buy back leaves the slot hidden for the rest of the
  session. Retail keeps it there always and just desaturates its undo arrow when empty (which
  `BuybackUndo` already does), so `postMerchantUpdate` shows it unconditionally on the merchant tab.
* **The portrait unit token is case-sensitive.** FrameXML passes `SetPortraitTexture(…, "NPC")`
  uppercase, and the 1.15 source carries the same warning. A lowercase `"npc"` misses and leaves the
  buyback purse in place.

### The inset has to clear the portrait ring

`PortraitFrameTemplate`'s top-left metal corner is a 75x75 **circle** — centre (24.5, -21.5),
radius 37 — not a rectangle that stops at the frame's edge. A recess whose top-left corner is inside
that radius draws across the portrait, and at `INSET_TL_Y = -44` ours sat 27.9 from the centre. The
first row's slot was inside it too, at 35.4.

`-60` for the inset and `-76` for the grid put both outside (41.9 and 43.1), which is what the frame
growing to 494 pays for. Retail has the same gap between its title and its grid and fills it with the
filter dropdown; this client has no API for that, so ours is bare stone.

Worth keeping in mind for any future window on this template: the usable interior does not start at
the frame's inset, it starts below the portrait circle — and a corner-distance check is the way to
confirm it rather than eyeballing a bounding box.

### The two tabs' recesses are coloured separately

Not one compromise value. The merchant grid is full of item plates, so its recess barely shows and
wants to stay dark; the buyback grid is mostly empty slots, so the recess IS what you see there and
reads far too heavy at the merchant tab's value. Retail colours them separately for the same reason.
`INSET_FILL` / `INSET_FILL_BUYBACK`, switched by `setInsetForTab` alongside the inset's height.

### The buyback tile keeps the item frame; only its X moved

The tile is an item slot and wears the item frame — UI-EmptySlot behind the icon, the UI-Quickslot2
ring around it, both at their native 64 against a 37px button, exactly as every grid row wears them.
`reskinSlot` already dresses it that way and nothing undoes it.

The 64 is a BOUNDING BOX, not the visible extent: most of it is the frame art's transparent margin,
and the gold border hugs the 37px opening. Reading it as the visible size is what sent three
successive attempts wrong — it looked like the ring could not fit the band's 44-tall recess, so the
ring was shrunk (its opening then landed ON the icon), then the whole tile was scaled down with it
(the icon dropped to 25 and read small), then the frame was dropped altogether. None of it was
needed. Vertically the visible ring sits inside the recess perfectly well.

The only real collision was HORIZONTAL, against the divider between the band's two compartments, and
the fix is one number: `BUYBACK_X` 218 -> 228. The bounding box still starts a shade inside the
divider; the visible border clears it by about 11.

### The recess is tinted ROCK, not a colour swatch

A flat `SetTexture(r,g,b,a)` is what made the panel read as dead grey. At 0.92 alpha the stone
underneath contributes 8%, and its GRAIN is compressed by the same factor — to a fraction of a
percent, which is invisible. Lowering the alpha to let more through just washes the tone out before
the texture becomes legible; there is no value that gives both.

So the recess paints the same tiled 374155 sheet the body uses and sets its tone through
`SetVertexColor`. The grain then IS the texture rather than something trying to show through it, and
the tone is still one number per tab. Those numbers are vertex multipliers on the sheet, so they read
directly against `PC.BODY_TINT`'s 0.32: below it is a recess, above it is a lit panel.

### Recess colour: ratio on the merchant tab, absolute on buyback

The merchant tab's recess is tuned as a RATIO against the body it is sunk into — it barely shows
behind a full grid, and what matters is that it reads as sunken. The buyback tab's is tuned to
retail's ABSOLUTE tone instead, because there the recess is the surface you actually look at, and
holding a ratio against our body just reproduces our body's darkness (`PC.BODY_TINT` puts the rock at
0.32) in the one place retail is plainly light.

Composited over the body: merchant ~0.06, buyback ~0.25. `INSET_FILL_BUYBACK` is the single number to
turn if the buyback panel wants to go further either way. Alpha stays under 1 on both so a little of
the rock's grain reads through, which is what keeps them looking like sunken stone rather than flat
grey rectangles.

### An InsetFrameTemplate is a BORDER, not a recess

The shared `InsetFrameTemplate` nineslice draws the thin gold trim and **nothing inside it**. On its
own it outlines a recess without sinking one, which is why the grid read as the same stone as the
frame rather than retail's visibly darker panel. Each inset therefore gets an explicit fill, in the
colour and at the placement the addon already uses (`modules/cooldownviewer/SettingsPanel.lua`): a
BACKGROUND texture at **subLevel 1**.

The sublevel is the point. `f.Bg` spans the whole frame at subLevel 0, so a fill at the default or
below draws *underneath* the body stone and is never once visible — the same trap the Cooldown
Manager's settings panel documents. `PC.Keep` then guards it from `hideClassicChrome`'s BACKGROUND
walk, which hides everything but `f.Bg` on every update.

### The band is two compartments, not one strip

`UI-Merchant-BotFrame` is not a single recessed strip: it is a wide compartment at the left for the
repair/sell cluster and a narrower one at the right, and retail puts the **buyback tile in the right
one**. Chaining the buyback tile off the end of the cluster kept it inside the left compartment and
left the right one standing empty. It is now placed at a fixed offset from the frame, so its position
no longer depends on how many repair buttons the vendor happens to offer — which is also how retail
behaves — and it is placed before the branch that can bail out when a repair button is missing.

Measured off the reference shot, retail's buyback tile starts at 0.591 of the frame's width, which
lands just inside the right compartment with the same ~5px padding from its edge that `BAR_X` gives
the cluster from the left one's.

### The buyback tab gets the room the button bar isn't using

Nothing sits under the grid on the buyback tab — no band, no repair or sell tiles — and retail lets the
grid have that space: six rows spread to fill a taller recess, with the money box tucked against its
bottom edge. Holding the merchant tab's inset height there instead left about a third of the tab as
bare stone.

So both the inset's bottom edge and the row pitch are per-tab: `INSET_BR_Y` 101 / `INSET_BR_Y_BUYBACK`
30, and `ROW_GAP_MERCHANT` -8 / `ROW_GAP_BUYBACK` -22. The merchant value is the client's own; the
buyback one is ours, because FrameXML's -15 was measured for the dead space ITS layout had down there
and ours has a different amount of room.

### The bottom bar follows retail's two rows

Retail runs two rows below the grid: the button strip, and **below it** the player's money in its own
recess at the right. Ours had both on one line, which crowded the money against the buyback tile and
made the whole bar read as one dense row instead of retail's two. The frame is 486 tall rather than
468 to make room — that is retail's own proportion, 1.31 tall per unit wide, measured off the
reference shot against ours at 1.27.

Spacing inside the strip is retail's too: the repair/sell tiles sit tight at `BUTTON_GAP` 6, and the
buyback tile is set clearly apart at `BUYBACK_GAP` 34 rather than being spaced like one more of them.

Splitting the rows also retires a hazard the notes used to warn about: the money frame's width tracks
how much gold is carried, so on one row a rich character's recess could reach left into the buyback
tile. On two rows they cannot meet.

The whole vertical budget is checked arithmetically rather than by eye — buyback rows clear the inset
bottom, pagination sits inside the inset and clear of the merchant rows, the band clears the inset,
the buttons sit inside the band, and the money recess clears the band and stays inside the frame.

### The stone body is painted here, like every other window's

`PanelChrome.ApplyBodyFill` does build an `f.Bg`, but on its own default rect — `TOPLEFT(1,-4)` to
`BOTTOMRIGHT(-1,2)` — which reaches up behind the title bar and stops short of the bottom edge. Every
window in this set that reads as stone rather than as a slab re-anchors it to start just under the
title and run flush to the frame's bottom-right, at full brightness: `modules/inspect` (`paintBody`),
`modules/guild` (`buildChrome`), `modules/auctionhouse`, `modules/encounterjournal`. The merchant now
does the same three lines rather than being the one window with its own geometry.

Flush on the left (0), not guild's 4px inset: that inset is for a border whose opaque coverage falls
inside the frame's nominal edge, and this window wears the same `PortraitFrameTemplate` metal the
inspect window does, where a 4 left a visible strip of bare frame down the left side.

`f.Bg` is also re-shown in the update pass. `hideClassicChrome` walks the BACKGROUND layer hiding
everything but `f.Bg`, which makes the body the one texture on that layer whose survival is
load-bearing — re-asserting it costs nothing and means no later change to that walk can leave the
window bare.

### Definition order matters for the per-update helpers

`setRowPitch` and `setInsetForTab` sit ABOVE `postMerchantUpdate` and the two row passes on purpose.
A `local function` declared *after* a call site is not in scope there — the name resolves to a nil
global and throws at call time — and every one of these is called from a `hooksecurefunc` post-hook,
where a throw kills the rest of the chain and strands the window's whole sync with no visible error.
Exactly the same symptom as the circular-anchor bug below, from a completely different cause.

`luac` and `luaparse` both accept it, so `qa/offline/check.js` now greps for it as a second pass.

### Never invert an anchor dependency the client re-asserts

`MerchantFrame_UpdateRepairButtons` runs

```lua
MerchantRepairItemButton:SetPoint("RIGHT", MerchantRepairAllButton, "LEFT", ...)
```

on **every** update: repair-one depends on repair-all, and never the reverse. Re-anchoring repair-all
off repair-one — the obvious way to walk the button row left to right from the frame's edge — turns
that line into a circular anchor, and it throws:

```
MerchantFrame.lua:575: MerchantRepairItemButton:SetPoint(): MerchantRepairAllButton is dependent on this
```

The first update is fine and every one after it dies, which is a nasty shape: the item list still
paints (the throw is late in the function) while everything downstream of it silently stops. So
`postRepairButtons` gives repair-**all** the absolute position and hangs repair-one off it, the
client's way round. The row still reads left to right; it is just measured from the second tile.
Guild-bank repair hangs off repair-all in the client too, so restating that one is safe. Our own
buttons — sell-junk and the buyback slot — have nothing anchored to them, so their direction is free.

### The buyback tile and DragonUI's rarity glow

Moving the buyback slot into the button bar made it a compact tile, and two things had to follow it
there:

* **The ring stays; only the recess is replaced.** The buyback slot is an ITEM slot, not an action
  button like the repair and sell tiles beside it, so it keeps the gold ring every item slot in this
  window wears — that ring is the "item frame". Hiding it along with the row's oversized recess left
  the icon sitting bare in the tile. `reskinSlot` has already pointed it at retail's UI-Quickslot2;
  all it needs here is the bar's proportions, so it frames the tile exactly as the recess does.
* **The tile is built the same way its neighbours are, not sized to match them.** NewEra has no
  answer to copy here: it leaves the buyback slot in the GRID (shifted 30px right) and gives it the
  same 64px recess and 64px ring every merchant row gets, so it never needs to match a bar tile.
  Moving it into the bar is this port's change, following retail. The first attempt scaled the row's
  art down to about the bar's tile size, which left two different constructions to keep numerically
  in step — and they drifted. The row art is now hidden outright and the button goes through
  `addRetailSlotBg`, the same call the repair and sell-junk buttons use, with its icon pinned by the
  same `SetAllPoints(button)` that `reskinRepairIcon` makes. Same thing, not a lookalike.
* **Size the BUTTON, not just the art round it.** Everything the client draws inside an item button —
  the icon, the stack count, any overlay another addon hangs on it — is sized off the button. Hugging
  only the recess left the tile correct while empty and let the icon burst out of it the moment a real
  item arrived. `fitBuybackToBar` pins the button (and its row, which is 153 wide and only shows the
  tile) to the bar's tile size.
* **Do not shrink the rarity halo.** It is `UI-ActionButton-Border` in ADD blend — a soft glow whose
  visible energy sits in its OUTER portion. Scaling it down to just past the tile edge (1.25x was
  tried, to stop it reading as oversized) clips off the part you can actually see, and the rarity cue
  disappears entirely. The thing that genuinely needs correcting is only the RATIO's input: DragonUI
  sizes the overlay once from whatever the button measured at creation, and this tile is resized
  after that, so `fitBuybackQualityGlow` re-applies DragonUI's own 1.7x against the final tile size.
* **DragonUI's rarity cue is a glow halo at 1.7x the button** (`modules/itemquality.lua`,
  `GetOrCreateOverlay`), sized once at creation and cached on the button — so 37 x 1.7 = 63 around a
  44 tile. That is the right look on a bag or grid slot and the wrong one in a button bar, and the bar
  is a thing this module invented by moving the slot into it, so it is ours to fix.
  `fitBuybackQualityGlow` re-fits that one overlay to the tile; because DragonUI sizes it only at
  creation, it runs in the update pass rather than at build time. The merchant grid rows keep
  DragonUI's halo exactly as it ships.

The name and price FontStrings are hidden too — retail's bar carries a bare tile, and both are still
in the tooltip. `_UpdateMerchantInfo` rewrites the name and re-Shows the money frame on every update,
so that is re-asserted in the update pass rather than done once.

### The sync cannot depend on FrameXML's updaters completing

`hooksecurefunc` post-hooks **do not run when the original function errors**. So one fault anywhere
inside `MerchantFrame_UpdateMerchantInfo` — in the client's own body, or in any *earlier-registered*
post-hook from another addon, since the chain aborts at the first thrower — silently strands
everything this module owns: the title, the portrait, the bottom band and its buttons all keep
whatever the previous tab left them. It survives closing and reopening the window, because the next
call throws in the same place. And it never surfaces as an error the player sees, because the first
call happens inside the module dispatcher's `pcall`.

That was diagnosed from `/nemerchant`: `MerchantInfo=0` (our post-hook had never fired) next to
`nameText="Palja Amboss"` (the function had plainly run) next to `Repair=1` (a hook on a function
called *from inside* it). Started, got partway, threw.

So `syncSoon` runs the whole pass on a **timer** instead — a next-frame single shot, coalesced, which
nothing upstream can abort. It is driven from the tab buttons, from `MERCHANT_SHOW`/`MERCHANT_UPDATE`
on our own frame, and once at the end of the build. The hooks are kept as the fast path; the timer is
what guarantees the window is never left wearing the other tab's dressing.

`/nemerchant` also runs both updaters under `pcall` and prints whatever they throw, so the underlying
fault can be named rather than worked around blindly.

The tab buttons are also hooked directly (`OnClick`, which runs after `PanelTemplates_SetTab` and
`MerchantFrame_Update`) as a second path to the same sync. A tab switch is the one moment where a
missed sync leaves the window wearing the other tab's dressing — title, portrait, bottom band — while
the item list looks perfectly correct, so it is worth not depending on a single seam.
`Merch.stats` counts every post-hook firing and `/nemerchant` prints it, so "our sync ran and got it
wrong" and "our sync never ran" are one command apart rather than a guess.

`/nemerchant` prints every bar element's left..right span, which is the quickest way to check the
strip after a change — particularly with guild-bank repair available, when it carries five tiles.
* **No pixel-perfect pin.** The 1.15 source calls `PinPixelPerfect` on the frame and flags the risk
  in its own comment. On 3.3.5a `UpdateUIPanelPositions` measures `GetWidth()` without scale, so a
  `SetScale`'d UIPanel-managed window lays out in the wrong column and can shove its neighbours off
  screen. Every reskinned Blizzard window here (`modules/inspect` included) leaves the client's
  scale alone; only our own standalone windows scale, through `NE.scale`.
* **Junk filter is stricter.** `!!!ClassicAPI`'s `C_Container.GetContainerItemInfo` hardcodes
  `hasNoValue = false` and runs a hidden-tooltip scan per slot, so the sweep reads
  `GetContainerItemLink` + `GetItemInfo` instead: poor quality, a non-zero vendor price, and not a
  quest item. Quest items are excluded because losing a gray quest item here is unrecoverable — the
  same guard DragonUI's own scrap-sell uses.
* **Quest-starter detection** goes through the new `NE.itemgrid.ItemStartsQuestByLink`
  (`core/ItemGrid.lua`), a `SetHyperlink` sibling of the existing bag-bound scan sharing its
  per-itemID cache. Merchant rows have no bag/slot to scan, and this client's container quest API
  cannot answer for a vendor item at all.

### Reading `/nemerchant`: sizes off HIDDEN widgets are lies

`GetWidth()` on a widget whose frame is hidden does not return its laid-out size — the anchors are
unresolved, so it falls back to the texture FILE's intrinsic size. That is why a correctly-sized
36px buyback icon reported `64x64` (item icons are 64px BLPs) and correctly-sized 36px repair icons
reported `512x256` (the merchant sheet's dimensions). Both were read as bugs and chased. The dump now
says so explicitly whenever the owning button is hidden; **run it on the tab that shows the widget you
are measuring.**

## `/nemerchant`

A report-only dump of the window's state: whether the merchant sheet registered, whether each atlas
resolves to a shipped local file, which region each repair/sell button's icon actually is and what
is currently on it (path, texcoords, size, vertex colour), the frame's size and panel offset, and
how far the right column's name plate reaches relative to the frame edge.

It exists because two different failures look identical on screen. An icon that resolved and is
merely desaturated — which the client does deliberately when there is nothing to repair, and which
this module does when there is no junk to sell — reads as a dark square, and so does an icon that
never resolved at all. Guessing between them from a screenshot wastes a round trip; this prints
which one it is. `PANEL_W` is tuned from its "right column plate ends N px past the frame edge" line.

## Related surfaces

DragonUI ships a "sell scrap" button on its own bag windows. That is a different surface; this is
retail's button on the vendor frame, and the two do not interact.
