# Inspect — port notes

Downport of NewEra `InspectFrame/` (Classic 1.15) onto 3.3.5a.

Source files: `Assets.lua`, `InspectFrame.lua`, `InspectGuild.lua`, `InspectHonor.lua`,
`InspectSlotQuality.lua`, `InspectTalents.lua`.
Ported: `InspectFrame.lua` (split here into `InspectFrame.lua` + `PaperDoll.lua`), and — after the
first round of screenshots — the two panes the source draws itself, as `PvPPane.lua` and an inspect
mode on this addon's own talent window.

## The frame is not the same frame

The 1.15 source reskins Era's `InspectFrame`, which inherits `ButtonFrameTemplate` — so it hides
that template's border pieces, re-textures `f.NineSlice`, and everything else follows. None of that
exists here. Verified against the real 3.3.5a `Blizzard_InspectUI` (Interface 30300):

| | Era (1.15) | 3.3.5a |
|---|---|---|
| `InspectFrame` | `ButtonFrameTemplate`, ~338 wide | bare `Frame`, 384x512, owns one region (`InspectFramePortrait`) |
| frame chrome | the template's | drawn by each tab SUBFRAME, as four UNNAMED quadrant textures |
| tabs | Character, Honor | Character, PVP, Talents (`PanelTemplates_SetNumTabs(self, 3)`) |
| title | `TitleContainer.TitleText` (empty) + `InspectNameText` | `InspectNameFrame` / `InspectNameText` |
| rotate buttons | `InspectModelFrameRotate*Button` | `InspectModelRotate*Button` |
| "data arrived" | `INSPECT_READY` | **no `INSPECT_READY`** — `INSPECT_TALENT_READY` is the only signal |
| paperdoll slots | already carry `Char-*Slot` border art | bare `ItemButtonTemplate`, no border art at all |

Because the quadrants are unnamed, the chrome sweep matches them by texture PATH
(`ui-character-charactertab`, `ui-character-general`) — the same way DragonUI's character panel
finds the identical art on `CharacterFrame`'s subframes. It is deliberately narrow: the talent
tree's own `InspectTalentFrameBackground*` art is CONTENT and stays. (The PvP pane is a special
case — `PvPPane.lua` squelches all of its content, parchment included, and draws that tab itself.)

## Geometry: one window, three tabs

**338x424 on every tab** — DragonUI's character panel to the pixel. A window that changes shape when
you click a tab reads as broken, and the inspect window is the character window with someone else's
gear in it, so it is the same size on screen.

This was briefly 480. Blizzard's panes want 332x421 (talents) and ~336x389 (PvP) of content, and in
424's 360 of interior they had to shrink to 0.86-0.90 and read as small, adrift versions of
themselves; 480 gave them life size. Then both stopped being used — the PvP tab is ours and lays out
to whatever the interior is, and the Talents tab opens our own window — so the extra height bought
nothing and cost the match with the character panel.

The fit below is therefore a FALLBACK PATH now, not the normal one: it is what the window degrades
to if `PvPPane.lua` or this addon's talent module is unavailable. Blizzard's panes are laid out for
a 384x512 window whose WOODEN BORDER ate ~30px a side and ~90px at the bottom; take the border away
and the content sits in the middle of a lot of nothing. So each is handled the same way:

1. it keeps its declared 384x512 as an explicit size, breaking the XML's `setAllPoints` (every
   child is anchored in that coordinate space with absolute offsets, so the space has to survive);
2. it is scaled by `min(interiorW / contentW, interiorH / contentH)`;
3. it is anchored so its **content rect** — not its frame rect — lands on the interior, with any
   leftover width split evenly.

The content rects live at the top of `InspectFrame.lua`. The talents rect is read off Blizzard's XML
and deliberately runs to the BOTTOM OF THE TREE ART (-461), not to the points bar (-431): the art is
the bottom-most thing that draws, and anything left out of the rect ends up hanging outside the
window rather than inside it. The PvP rect's right and bottom edges are the exception — its plate is
a 512x512 sheet that is mostly transparent, so where the art actually stops was measured off a
screenshot. Neither scale is ever allowed above 1.

**The interior rect is symmetric, and retail's is not.** `PANEL_INSET_*` is 4 on the left against
-6 on the right, and every anchor hanging off that rect inherits the 2px lean. It is invisible on the
character panel, whose frame widens under the stats sidebar so its right edge is nowhere near the
columns; on a frame that is exactly 338 the right-hand column ends up with visibly more air beside
it. The right inset is -4 here, and the model and weapon row are centred by arithmetic off the
interior's width rather than carrying DragonUI's measured 48/83 — those are correct for ITS interior
and this one is now free to differ (feed the arithmetic a 328-wide interior and it returns 48).

The rest of the paperdoll follows the interior rather than fixed numbers too: the model's height is
`interior - 6 - 34` (at the character panel's 360 that is DragonUI's own 320), and the race
backdrop's quarters are fractions of that height rather than the flat 245/75. The PvP pane does the
same with its three bracket rows, which share out whatever the honor block leaves.

The one consequence worth knowing: a fitted pane's frame rect still measures 384x512 in its own
units, so it hangs ~65px below the window — over the tab strip. `EnableMouse(false)` on the pane
(its children keep their own mouse) plus raising the tabs above both panes is what keeps the tabs
clickable.

Every number in `PaperDoll.lua` is DragonUI's character-panel number, not the 1.15 source's: the
inspect window and the character window are the same window with someone else's gear in it, and
here they are built from the same Blizzard templates, so they line up together. That also settles
the art question — the slot frames come from DragonUI's `charpaperdollparts` sheet and the body from
the rock every other NewEra window already ships, so **this module ships no new textures**, and the
1.15 `Assets.lua` (one guild-tabard banner sheet, for a pane that does not exist here) is moot.

## Not ported, and why

* **`InspectGuild.lua`** — the inspect Guild tab is a Cataclysm feature (`InspectGuildFrame` first
  appears in 4.x). There is no fourth tab on 3.3.5a and no API to fill one: `GetGuildInfo(unit)`
  answers with a name and rank and nothing else. What survives of it is one line — the guild is now
  shown under the level line on the Character tab (`InspectGuildText`, a FontString Blizzard ships
  hidden and never fills in).
* **`InspectHonor.lua`** — a second instance of the 1.15 `CP.CreateHonorPane` factory, which lives
  in that addon's character panel. DragonUI owns the character panel here and its honor pane is a
  single player-only tab frame, not a factory, so there was nothing to instance. `PvPPane.lua` is
  the answer instead: the same job, written against this client's own data, sharing this window
  set's furniture rather than another addon's pane.
* **`InspectSlotQuality.lua`** — DragonUI already colours inspect slot borders by item quality
  (`modules/itemquality.lua`, which lists all nineteen `Inspect*Slot` buttons and hooks
  `InspectPaperDollItemSlotButton_Update`), and adds per-slot item levels on top
  (`modules/itemlevel.lua`). Porting this would be a second set of borders over the first.

## The two panes we DO draw

**PVP** (`PvPPane.lua`). Blizzard's whole PvP tab is a 512x512 `UI-Character-PVP` parchment with six
numbers and three arena plates on it; fitted into a modern frame that plate is the only thing left
that still reads as 2007. So the tab is drawn on this window set's own furniture from
`GetInspectHonorData` (todayHK/Honor, yesterdayHK/Honor, lifetimeHK, lifetimeRank) and
`GetInspectArenaTeamData`.

The native FRAME keeps running — Blizzard's tab machinery shows and hides it, its OnShow fires the
honor request, its OnEvent keeps the client's cache fresh — and only its CONTENT is squelched, with
`Show` neutered because `InspectPVPTeam_Update` re-shows the team plates on every honor tick. Hiding
the frame itself was the obvious move and is wrong: `InspectSwitchTabs` hides the outgoing pane, and
`Hide()` on an already-hidden frame fires no OnHide, so our pane would have been stranded on screen
over the paperdoll. Its boxes are insets with a BLACK ground rather than windows onto the stone: the
data is what should read, and rock behind a table of numbers is noise. Two smaller things the native pane gets wrong and this one doesn't: it reads
`UnitFactionGroup("player")` for the crest (so inspecting the other faction shows yours), and it
must be handed a priming `GetInspectArenaTeamData` pass per bracket before any read returns data.

**TALENTS** — the tab stays in the strip beside Character and PvP, where a third tab belongs; what
changes is where it leads. Instead of the native tree pane it opens this addon's own talent window
on the inspected unit, through the new `NE.talents.ShowInspect`, and it deliberately does not become
the SELECTED tab (`InspectSwitchTabs` is never called), so the window keeps showing the pane you
were on. Retail and the 1.15 source both use a paperdoll BUTTON for this instead; a tab is what was
asked for here, and it reads better beside the other two.

Blizzard's own level gate does the work: `InspectFrame_UpdateTalentTab` disables tab 3 for a level
1-9 unit on every unit change, and a disabled tab fires no OnClick.

Every talent getter on this client takes an `isInspect` flag in the argument slot `modules/talents`
was passing a hard `false` to, so inspect mode there is that flag threaded through the reads plus
`editable = false`. With no inspect unit set every one of those call sites passes exactly what it
passed before, which is the property that keeps the player's own window untouched. Read-only means
read-only: the preview API has no inspect side, so a click would spend YOUR points.

Why not host the trees in the tab: three 4x11 trees need ~900px of width. Blizzard's native tab fits
them in 296px by showing ONE at a time behind a scrollbar; the modern renderer shows all three and
is sized for its own window. In a 328-wide tab it would have to shrink to about a third — smaller
than the pane it replaced.

## Where the window opens

Two attributes, both set on the FRAME rather than in `UIPanelWindows` — writing that table taints
the first panel open in combat (DragonUI `modules/characterpanel/chrome.lua:126`):

* `UIPanelLayout-xoffset = 6`. Left-area panels sit flush against the screen edge on this client
  (UIParent's `LEFT_OFFSET` is 0). That was fine for a wooden frame whose art carried its own
  transparent margin, and is not for a modern one that is opaque to its edge. Same nudge DragonUI
  gives the character panel.
* `UIPanelLayout-pushable = 3`. The table declares 0 and the character panel declares 3, so opening
  this window took the LEFT slot and shoved the character panel to the centre — the two swapped
  places. At 3 the manager's "only one open" branch stops preferring us and we land in the centre
  slot: to the RIGHT of the character panel, which stays where it is.

The catch: `GetUIPanelWindowInfo` copies the whole `UIPanelWindows` row onto the frame the first
time it is asked and only then treats attributes as authoritative, so setting `pushable` before that
copy would simply be overwritten by it. Hence the row's other fields are restated here and the frame
is marked `UIPanelLayout-defined` — the documented way to opt a frame out of the table.

One more thing that has to be centred on the WINDOW rather than on what it sits in: the title. The
band is inset 58 from the left to clear the portrait and 24 from the right to clear the close button,
so a title centred inside it lands 17px right of the window's middle. The professions and guild
windows centre theirs on the frame for the same reason.

## Things that would have broken quietly

* **The wooden quadrants are not all on the same layer.** The paperdoll and PvP panes declare them
  on BACKGROUND; the TALENTS pane declares the identical four textures on BORDER. A
  BACKGROUND-only sweep hides two panes' chrome and leaves the third's whole wooden frame drawn
  inside the modern one — which is exactly what happened. The sweep walks every layer now; the
  path match is the only thing deciding, and it names two texture families and nothing else.
* **The streak band under the title has to be hosted above the nineslice.**
  `PC.ApplyModernChrome` leaves it on the frame itself at BORDER, and `f.NineSlice` is a CHILD
  FRAME whose `TopEdge` piece is 75 tall on OVERLAY — covering y -21 to -64, which is the band.
  The guild and professions windows work around it with a host frame above the nineslice; **this
  window does not, deliberately.** That host is a CHILD frame, and a child frame draws over every
  texture on the frame below it — `InspectFramePortrait` included — so the band covered the
  inspected player's face from the eyes down, and starting it clear of the portrait left its cut
  edge reading as a hard shadow across the stone. The placement that would actually work is
  DragonUI's on the character panel: nineslice pieces on the FRAME ITSELF, so draw layers order the
  stack (rock BACKGROUND < streaks BORDER < portrait ARTWORK < metal OVERLAY). `NE.nineslice` always
  applies to a child, so that means bypassing `PC`'s chrome build — not worth it for a decorative
  band when the rock body is what makes this window read like the family.
* **The body needs BOTH halves of the character panel's stack.** `PC.ApplyModernChrome` fills the
  body through `PC.ApplyBodyFill`, which multiplies the rock by `PC.BODY_TINT` (0.32) — the
  near-black the bag windows want — so the stone is painted here untinted instead, the way every
  window in this family that reads as stone does it. On top of it goes the recessed
  `character-panel-background` ground, which is what makes the content area read as an INSET rather
  than as content floating on wallpaper. A round with only the ground looked like a black blanket
  over the stone; a round with only the stone lost the inset. Neither is the character panel.
  The body is also flush LEFT: guild's measured 4px inset covers a sliver its border would
  otherwise show past, and here that 4 was itself the visible strip. Two rims go on top — one around
  the interior rect and one around the MODEL viewport — so the content area and the character viewer
  each read as a window within the window.

  Those rims are drawn by **DragonUI's own `CP.DrawPaneBorder`**, not by our nineslice: it is public
  on its character panel, it is the routine that panel rims its own insets with (6px UI-Frame-Inner
  corners over 3px tiles, including the one-pixel drop the bottom pair needs), and the two windows
  are supposed to be the same window. "The same" is easier to keep true when it is literally the
  same code. The model's rim is hosted on the PAPERDOLL at a 2px outset, exactly as
  `modules/characterpanel/innerborder.lua` hosts its own — the outset is what keeps it outside the
  model's rect, which is what lets a texture on the parent show around a child frame's render at
  all. Our `InsetFrameTemplate` nineslice remains the fallback if that seam ever goes away.
* **"The player" is assumed in more places than the getters.** Threading `isInspect` through the
  talent READS is not the whole job, and two bugs came out of the places it missed:
  `UnitClass("player")` in the portrait path (the window wears a class circle, and it was the
  VIEWER's class), the same call in `T.BackgroundNick` (an inspected Death Knight's trees painted on
  your Paladin's spec artwork), and `GameTooltip:SetTalent`, which is not a getter but takes the
  same flag in the same argument slot — with a hard `false` it describes the talent YOU have at that
  (tab, index) rather than the one under the cursor (issue #77). `modules/talents/Behavior.lua` now
  carries a checklist of every call site the flag has to reach and what each one does about it.
* **`InspectTalentFramePortrait`** is the talents pane's own copy of the frame portrait. It is
  invisible in Blizzard's layout because it sits exactly under the real one; move the pane and it
  becomes a second head somewhere in the middle of the tree.
* **A frame's size does not update when you resize its parent.** The rect resolves at the next
  layout pass, so `NE_Inset:GetHeight()` immediately after the window is resized hands back the
  span from BEFORE it. Measuring there gave the model 408 (Blizzard's 512-tall window less the
  insets) instead of 320, which put its backdrop through the bottom of the window and dragged
  DragonUI's item-level text down onto the tab strip. Everything that needs the interior's size
  takes it from `I.InteriorSize()`, which computes it. The offline harness models this — anchored
  sizes there are captured at anchor time and only refresh on an explicit `layoutPass()` — because
  an honest stub is what let this through in the first place.
* **DragonUI's floating item level appears LATE.** It is built on that module's own debounce off
  `INSPECT_TALENT_READY`, which lands after the refresh we re-anchor it from — so a single look
  finds nothing, the text turns up unpinned over the weapon row, and it looks like the fix simply
  did not work. The pin retries for ~2s and stops the moment it lands.

* `SetEnabled` (used by the source's talents button) does not exist on 3.3.5a — `Enable`/`Disable`
  do. Nothing here calls it, but it is the trap in that part of the source.
* `SetColorTexture` does not exist either; `SetTexture(r, g, b[, a])` takes colour arguments.
* `string.format("%d", "??")` errors in Lua 5.1, and an out-of-range level IS the string `"??"`,
  so the localized `PLAYER_LEVEL` template has its `%d` relaxed to `%s` before it is used.
* The two rotate buttons are found BY GLOBAL NAME by Blizzard's `InspectModelFrame_OnUpdate`
  (that is what makes press-and-hold spin the model), so they are restyled and moved, never
  replaced.
