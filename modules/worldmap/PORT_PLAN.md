# World Map — Port Plan (Build Contract)

Downport of `ReferenceAddons/NewEra/WorldMap/` (Classic Era 1.15) onto 3.3.5a. Read `CONTRACTS.md`
§0 first — every global convention there applies (`local NE = DragonUI_NewEra`, no `SetShown`, no
masks, hook rather than replace Blizzard methods, a `-- DOWNPORT:` note on every deviation).

**Status: Phases 1–4 implemented, plus fog-of-war reveal and drag-to-resize. Four in-game runs; the breadcrumb shares one implementation with the Adventure Guide.**

Chrome, breadcrumb, pin restyle and the quest-log side panel are in, plus `core/Squelch.lua`,
`core/MaxMin.lua` and the `RIVALS.WORLDMAP` row. `qa/offline/test_worldmap.lua` passes (338
assertions) and `qa/staticcheck.ps1` PASSes with the TOC block in.

**Three decisions were taken against what this plan first said**, each on evidence found while
building, and each recorded where the code is rather than only here:

1. **The map is taken OUT of `UIPanelWindows`** (§3 Phase 1 recommended leaving it in). This
   client's windowed-map geometry is entangled with that entry — it rewrites the table on every
   size toggle — and Mapster, the one addon demonstrably re-homing this frame on 3.3.5a, clears it.
   The window is now placed the way every other window in this addon is: `PersistWindowPosition`
   for the player's own spot, `NE.panelmgr` for the shared row, `EscClose` for ESC.
2. **`core/NavBar.lua` was not created at first, and then was** (§3 Phase 2 proposed promoting the
   Encounter Journal's breadcrumb into core). The original call — that it was a refactor of a
   shipped feature no offline harness covered — was reversed once the cost of the alternative
   showed up in game. The world map's private copy re-derived a worse version of the journal's, and
   in two rounds re-introduced two faults the journal had already fixed **and documented in comments
   thirty lines away**: the Home crumb landing on the window's portrait, and crumbs painted over by
   their own bar. That is not a coincidence to fix twice; it is the argument for one implementation.

   The journal's version won — it was the better of the two, with descending frame levels so the
   connectors interlock without a seam, flush chaining so the overhang lands on the next crumb's
   padding rather than across a gap, and portrait clearance. It moved to `core/NavBar.lua` with the
   TRAIL handed in by the caller; both modules are now thin adapters that say what their crumbs mean
   and nothing about how one is drawn. Public surfaces are unchanged (`NE.ej.BuildNavBar`,
   `NE.ej.RefreshNavBar`, `f._neSearchBox`), and the harness now drives the shared widget with the
   JOURNAL's trail shape as well as the map's — including the overflow collapse, which the map has
   never yet been narrow enough to trigger.
3. **Phase 3 shipped with the swap gated on art that was not there yet.** FDID 136441 could not be
   extracted from this machine, and `RegisterLocal` on a path that is not on disk makes every
   landmark pin render *blank* rather than unchanged — so the registration was left out with the
   steps to enable it. **The owner has since supplied the sheet**
   (`Textures/Common/136441-poiicons.blp`) and the redirect is now live. `Pins.lua` still checks
   `NE.tex.Local(136441)` before touching a pin, so removing the file degrades to "no restyle"
   rather than to a map full of blank pins.

**One real bug was found by the harness rather than by reading**: `safe()` packed `pcall`'s results
into a table and unpacked from index 2, which loses arity — `#{...}` stops at the first `nil`, and
`GetQuestLogTitle` returns a nil `suggestedGroup` in the *middle* of its list. Every quest read as a
non-header with no complete and no daily flag. Fixed by passing the results through a
`stripOk(ok, ...)` helper instead of packing. The same shape existed in `NavBar.lua` and was fixed
with it.

**The harness bites.** Each of these, applied alone, fails it: reverting `safe()` to the packing
form (5 assertions), turning `core/Squelch.lua` back into a one-shot `Hide()` (2), dropping the
`WORLDMAP_SETTINGS.size` write (1), forgetting to divide the canvas anchor by the child's own scale
(2), replacing the close button's `OnClick` (1), and running the geometry pass in combat instead of
deferring it (1).

### What the in-game runs found

Both faults are in the screenshot and neither is visible *as* itself — they read as "the layout is
wrong", which is why `/neworldmap` (modules/worldmap/Diagnostics.lua) now exists.

1. **The client repainted its whole FULLSCREEN chrome around our window** — a 1024×768 border,
   backdrop quadrants and quest-panel parchment framing a 702-wide map. Cause:
   `WORLDMAP_SETTINGS.size == WORLDMAP_WINDOWED_SIZE` is this client's one and only "am I windowed?"
   test (the client asks it, and so does every addon that cares — `ModernMapMarkers_UI.lua:762`
   and `:942` are the copies on this machine). Writing our own scale into `size`, which the POI
   math requires, broke that identity and flipped the answer to "fullscreen".

   Fix: move the CONSTANT onto our scale too, so the two stay equal and every mode check agrees
   with what is actually on screen. The client's original value is captured once at boot into
   `WM.clientWindowedSize`. Second fix, belt to that brace: the art sweep now walks one level of
   CHILD frames — the quadrants and parchment were never on `WorldMapFrame` itself, which is why
   the original sweep found nothing to hide. That widened the path match to the whole
   `Interface\WorldMap\` directory, which contains the map tiles as well as the chrome, so the walk
   skips `WorldMapDetailFrame` by name and the harness asserts all twelve tiles survive.

2. **The breadcrumb drew its background plate and no crumbs.** Cause: the bar is pinned left and
   right into the title/canvas spacer and carries no explicit width, and the client does not resolve
   an anchored rect until its next layout pass — so the first `refresh`, which runs during the
   build, asked a frame born microseconds ago how wide it was and got `0`. It returned there, and
   nothing refreshed the bar again until the map changed.

   Fix: `availableWidth` falls back through the frames the bar is pinned to (one of which is always
   sized explicitly), with a one-shot next-frame retry behind that, and the bar refreshes on every
   map open. **The offline harness could never have caught this** — its stub resolves anchor spans
   synchronously. It now asserts the fallback instead, which is the honest thing for a stub to test.

A third thing the first run changed: the geometry pass used to `pcall` its listener tail and drop
the error. That is how fault 2 stayed invisible — the plate drew, the refresh after it failed, and
nothing said so. Errors there are now logged.

3. **The breadcrumb drew its plate and no crumbs — again, for a completely different reason.** The
   second run's dump reported all four crumbs *shown*, at sensible widths, with their backgrounds
   and connectors up, and with a correct trail (`World > Northrend > Dalaran > Dalaran City`, that
   last one being the floor selector). Every word of that was true and none of it was on screen.

   Cause: a child frame does not reliably come out above its parent's OVERLAY regions on this
   client, and the bar has one spanning its full width — the sheen. Nothing had pinned the crumbs'
   frame level, so the bar painted over its own contents and the result was a solid black band.

   Fix: crumbs are pinned to `bar level + 2` and their dropdown arrows to `+3`, and the sheen drops
   from OVERLAY to BORDER so no region of the bar can sit above a crumb at all. **The lesson is the
   bossmods harness's first one, met from a new direction**: *existence is not visibility*, and this
   time even "shown, sized and textured" was not visibility either. The offline stub was handing
   every child frame level 1, which made the whole question unaskable; it now models the client and
   gives a child its parent's level until something says otherwise.

   Two smaller things the same run showed: the panel's inset was mixed at 0.45 black over already
   dark stone and read as a hole rather than a recess (now 0.30), and the leftover-art list cried
   wolf about this window's own portrait, which is genuinely drawn from `Interface\QuestFrame\`
   onto our own border (the scan now skips our frames).

**`/neworldmap`** dumps the mode identity, the canvas frames and their scales, the chrome, the
breadcrumb (width, trail depth, per-crumb state), the quest panel, which art resolved, which
squelched widgets are still shown, and a **leftover classic art** list that should be empty — with
the owning frame named, so anything it prints says what to add to the sweep.

The harness bites on all of it. Each of these, applied alone, fails it: not moving
`WORLDMAP_WINDOWED_SIZE` onto our scale, sweeping the window but not its children, letting the sweep
reach `WorldMapDetailFrame`, dropping the quest-parchment path, reverting the breadcrumb's width
fallback, taking the explicit frame level off the crumbs or off their arrows, putting the sheen back
on OVERLAY, dropping the level off the search box / the cog / a quest row / a track checkbox, running
the drag band back under the buttons, putting the controls back at the band's level, making the crumb
levels ascend instead of descend, stopping the crumbs chaining flush, disabling the overflow collapse,
rendering the collapsed middles anyway, taking the boss-jump dropdown off the journal's trail,
reparenting the close button onto the chrome (4 assertions), dropping the UIPanelWindows re-clear,
sizing Home as though it had no dropdown, recording the client's junk overlay records, drawing
unexplored art on the same layer as explored art or without the tint, collapsing a wide overlay to a
single tile, dropping the y offset from the overlay packing, letting a geometry pass fight a live
drag (3 assertions), taking the dragged width without checking the height, deriving the height from
the wrong aspect (9), removing the minimum size, leaving the maximize flag set after a resize, and
saving a dragged width unclamped, laying the canvas out from the model instead of the frame's rect
(2 assertions), tinting the window body a second time, ignoring the drag's transient width (4),
taking the cursor's width without checking its height (4), skipping the cursor's conversion into
frame space (3), dropping the belt for a release the grip never saw (2), not re-pinning the
window by its TOPLEFT for the drag, preferring the bar's measured rect over the caller's model
(2 assertions), leaving the floor selector unsquelched, measuring the drag against the frame's live rect
(2 assertions), leaving screen clamping on during a drag, letting a click with no movement reset
the size, leaving the parchment or the quest-log chrome sheet unregistered (2 each), stretching the
zone-header bar instead of 3-slicing it (2), dropping the checkmark art, never resolving a quest
type badge, pinning the side-panel chevron so it cannot flip, never arming the client's
quest display at boot (3), never re-placing the markers after applying it (2), and never setting the
client's own objectives checkbox (2).

4. **Four dead controls in the quest panel, and a maximize button you had to miss to hit.** The
   third run's report: the cog did nothing, the search box would not focus, no quest row could be
   clicked, and tracking could not be toggled — plus a maximize button that only responded when the
   mouse was *near* rather than *on* it.

   The first four were one bug wearing four hats. The panel sets `EnableMouse(true)` so it does not
   leak clicks through to the map behind it, and on this client **a child frame does not reliably
   outrank its parent for mouse input** — so the panel was swallowing its own children's clicks.
   Every interactive child now carries an explicit level: the search box, the cog and the scroll
   frame above the panel, the scroll child above the scroll frame, each row above that, and each
   row's track checkbox above its row. The detail pane and its reward tiles and footer buttons the
   same.

   The maximize button is the same rule met from outside: the title band is mouse-enabled so the
   window drags by its title bar, and it spans the whole top of the frame — straight across the
   close and maximize buttons at the same level. Two fixes, because either alone leaves the other
   latent: the buttons are lifted clear of the band, and the band is stopped short of them.

   **This is the third distinct fault from one underlying fact**, after the crumbs and the sheen. It
   is worth stating once, plainly, for whatever gets built next on this client: *a frame being
   shown, sized, textured and mouse-enabled says nothing about whether the player can see or click
   it.* Only the frame level says that. The offline stub now models it — a child starts at its
   parent's level, not above it — which is what makes the question askable at all.

   Two smaller ones from the same run: the cog now builds its menu through `core/Menu.lua` rather
   than raw EasyMenu, so the TREE is assertable offline (there is now a real difference between "the
   cog opens nothing" and "it opens a menu whose entry does nothing"), and the breadcrumb's left
   inset moved from 10 to 59 so Home clears the portrait.

5. **The X button gutted the window instead of closing it — permanently.** `wireControls` called
   `close:SetParent(border)`, and `UIPanelCloseButton_OnClick` is `HideUIPanel(self:GetParent())`.
   So the X hid the CHROME rather than the map, and since nothing ever shows the border again the
   window stayed gutted for the session and reopened gutted.

   The 1.15 source says not to do this, in as many words, in a comment this port had already read
   and quoted: *"DON'T reparent the close button ... Kept parented to WorldMapFrame ... cross-parent
   SetPoint to our border is fine for positioning."* A frame level is absolute within its strata, so
   the button never needed reparenting to draw above the chrome — which is exactly what the source
   comment says and what the fix now does.

   Two adjacent hardenings from the same report: `WorldMap_ToggleSizeUp/Down` **rewrite**
   `UIPanelWindows["WorldMapFrame"]`, so clearing that entry once at boot let the panel manager start
   moving the window again on the next size change — it is now re-cleared from both size hooks and on
   every show; and the window's OnShow re-shows the border if anything has hidden it, so this shape
   of fault cannot persist across an open even if something else causes it.

6. **The ▾ overlapped the word "World".** Home is the only crumb that is both Home *and*
   arrow-bearing — the world map's Home carries the continent list; the Adventure Guide's carries
   nothing — and the padding rule was one three-way choice (`isHome and HOME_PAD or (hasArrow and
   ARROW_PAD or PLAIN_PAD)`) in which `isHome` won. Padding is now two independent decisions: a base
   pad, plus what a ▾ costs. The journal's numbers come out identical.

### Fog of war (added on request, not part of the original plan)

`modules/worldmap/FogClear.lua`, registered as its own module (`WorldMapFog`, `requires` the map).

3.3.5a draws one OVERLAY per subzone you have discovered on top of the mostly-empty base art, so
"clearing fog" means drawing the overlays the client would not have — tinted grey on BORDER, so that
exploring an area later lands its real art cleanly on ARTWORK above the tinted copy.

`GetNumMapOverlays()` only ever reports what the CURRENT character has discovered, and no API
enumerates the rest, so revealing an unvisited zone needs a stored table. Mapster ships one; it is
their data under an all-rights-reserved licence and is **not** copied. This harvests instead —
everything any character on the account has seen goes into `NE.db.worldmap.overlays` and is redrawn
for all of them. An alt sees your main's exploration immediately; a zone nobody on the account has
visited stays dark until somebody does. That trade is stated in the module header and in the options
description rather than left to be discovered.

### Drag-to-resize (added on request)

A grip in the bottom-right corner, in the client's own chat-window grabber art. The interesting part
is not the grip — it is that adding it **simplified** the geometry rather than complicating it.

The window is now described by **one number**: the canvas width, in the frame's own units. The canvas
height follows from the map child's fixed 1002/668 aspect, and the frame from adding the insets, the
spacer and whatever the side panel is claiming. "Minimized", "maximized" and "the size the player
dragged it to" collapsed into one code path with a different width; `computeMaximizedSize` became
`maximizedCanvasW`, and `FRAME_H` is now derived rather than asserted.

**The drag does not use the client's own sizing machinery**, and that is the point. `StartSizing`
drags the two edges independently, so the frame can be in a shape the map does not fill — and it
was: the window stretched free of the map for the whole drag and only snapped back on release. The
grip drives the size itself instead, off the cursor, deriving the same single canvas width every
frame. There is now no code path anywhere that sizes this window from anything but that one number,
so a wrong aspect is not a state the code can reach — not even for the single frame that a
snap-on-release leaves.

The cursor is converted into the frame's own coordinate space first (`GetCursorPosition` reports in
UIParent's; `GetLeft`/`GetTop` report in the frame's, and this window is pixel-pinned so the two
differ). Both axes are measured and the TIGHTER fit wins, so dragging either edge does something —
pull the bottom up and the height is the constraint, pull the right edge and the width is.

The window is re-pinned by its TOPLEFT for the duration, so it grows right and down under the cursor
rather than from its centre; the panel-row reflow is suppressed while dragging, since it would
re-anchor the window out from under the mouse every frame; and the update loop ends itself if the
button turns out to have been released somewhere the grip never saw, which `OnMouseUp` does not
guarantee.

Three details worth keeping:

* **The grip refuses in combat**, and says why. Re-laying the canvas out touches
  `WorldMapBlobFrame`'s scale, which is protected on this client; every other geometry pass defers
  through `AfterCombat`, and a drag cannot — there is nothing to defer, the player is holding the
  mouse down now.
* **Resizing drops out of the maximize preset.** The preset is a size, so choosing a different one is
  choosing not to be in it; leaving the flag set would make the next open snap back and read as the
  drag having been discarded.

Right-clicking the grip restores the default. Bounds are a 420 minimum canvas width (below which the
zone labels stop being readable) and 80% of the screen. `/neworldmap mode` prints the canvas width,
what is saved, and whether the resulting shape is one the map actually fills — flagged red if not,
since a letterboxed window is the one failure this design exists to prevent.

### Two faults from the fifth run

7. **The map did not follow the drag** — it sat frozen at its old size until the mouse came up.
   `layoutCanvas` was reading `windowSize()`, the size the frame is *supposed* to be, rather than
   its real rect. Those are identical on every pass except the one that matters: while
   `StartSizing` owns the frame the model has not moved yet. It now MEASURES the frame, with
   `windowSize()` only as a fallback for a frame that has no rect at all.

   The assertion written for this had been too weak to catch it — it asked only that a canvas scale
   existed, not that it tracked the rect being dragged. It now asserts the measured value, and the
   detail frame's anchor with it.

8. **The quest panel read as flat black.** Not the recess: this window was painting its stone body
   at `PC.BODY_TINT` (0.32), where every other window that paints its own body uses full brightness
   (`modules/inspect/InspectFrame.lua:216`, and the merchant). `BODY_TINT` is the multiplier
   PanelChrome's *own* `ApplyBodyFill` applies to its default rect — using it again here tinted the
   stone a second time, leaving this window roughly three times darker than the rest of the set.

   An inset reads as an inset because of the CONTRAST with what surrounds it, so a normal-depth
   recess over stone that dark came out the same colour as it. The panel's fill had been dialled
   back from 0.45 to 0.30 chasing this, which treated the symptom. With the body at full brightness
   the fill goes to **0.85** — the depth the Adventure Guide (0.85) and the inspect window (0.9)
   recess at — and the panel reads as sunk into stone rather than as a hole cut in it.

### Three from the sixth run

9. **The breadcrumb's backing plate kept the previous window's width** — running out past the right
   edge after minimising, stopping short of it after maximising. `availableWidth` preferred
   `bar:GetWidth()`, the bar's anchored rect, and **an anchored rect on this client lags a resize by
   a layout pass**: on the pass right after the window changes size it still reports the old width.

   The caller's own model now wins. `opts.fallbackWidth` became `opts.widthFunc` — an authoritative
   width, preferred over measuring the frame, with measurement kept as the fallback for a caller
   with a fixed width and nothing to declare (the Adventure Guide, whose bar is `SetWidth`'d
   outright). The world map declares `WM.CurrentCanvasWidth()`, the single number its whole geometry
   is built on, which is also correct mid-drag.

   This is the second time the same client behaviour has bitten, from opposite directions: the first
   time the rect had not resolved *yet* (width 0, empty trail), this time it had resolved to the
   *previous* value. Worth naming once: **an anchored rect is a frame behind.**

10. **The client's floor selector was drawing over the chrome.** `WorldMapLevelDropDown` was in the
    art sweep's keep-list but never squelched — and it is invisible everywhere except the handful of
    maps that have floors, so it went unnoticed until Dalaran, where it appeared next to the
    breadcrumb crumb that had replaced it. Squelched along with its two arrow buttons; the feature is
    unaffected, since the breadcrumb drives `SetDungeonMapLevel` directly.

11. **The quest panel, once more.** 0.85 was the wrong lesson from the right observation. The rest of
    the set recesses at 0.85–0.9, but those are small wells inside a window whose stone body is
    visible all around them, and that contrast is what makes them read as sunk. This panel is a
    full-height column taking a third of the window, with the map filling nearly all the rest — so
    there is barely any body left in view, and at the house depth it reads as a hole cut in the
    window. **0.55.** The number is about the panel's SIZE, which is what makes it different from the
    other insets; the earlier moves (0.45 → 0.30) were chasing the body-tint bug, which is fixed.

12. **Resizing the small window ran it to full size.** The drag measured against the frame's LIVE
    rect every frame, and the window is clamped to the screen — so the moment it grew past an edge
    the clamp SHIFTED it, which made the cursor look further from the origin, which grew the window,
    which clamped harder. A few frames of that and it had run all the way to the maximum.

    The origin is now captured ONCE at mouse-down and every frame measures against that, and screen
    clamping is switched off for the duration and restored on release. Also fixed alongside: a
    mouse-down with no movement left `dragCanvasW` nil, and passing that through read as "reset to
    default" — silently discarding the size the player already had.

    That is the *third* fault this module has had from reading a frame's rect at the wrong moment.
    The first two were staleness; this one is feedback. Same lesson, stated once more: **a frame's
    rect is an output, not an input — derive from the model, and read the frame only when nothing
    else can answer.**

### Art

`ART_AUDIT.md` is the record of what the reference screenshot needed. The owner then supplied all
twelve sheets into `Textures/WorldMap/`, and the quest panel is now dressed in retail's own art
rather than in placeholders:

* **`questlog-main-background`** — the parchment the list sits on. This is what the panel was missing
  all along; every previous attempt to fix "the panel looks black" was tuning a recess over bare
  stone, because there was no panel art behind it at all. The flat fill survives as a 0.25 wash over
  the paper (and as the 0.55 fallback if the sheet ever fails to resolve).
* **`questlog-tab`** on the zone headers, drawn as a real horizontal **3-slice** — 18px end caps and
  a stretched middle, per the reference addon's `AtlasSlice.lua`. Stretching the 64px source whole
  would pull those rounded caps to four and a half times their width, which reads as a smear rather
  than as a wider bar.
* **`questlog-icon-expand` / `-shrink`** in place of the `+` and `−` characters, moved to the right
  of the header where retail puts them.
* **`questlog-icon-ticksquare` + `-checkmark-yellow`** on the tracking box, in place of the stock
  `UI-CheckBox-*`.
* **`questlog-icon-setting`** on the cog, **`questlog-quest-glow-yellow`** on the row hover, and the
  filigree and bottom gradient framing the list.
* **`questlog-questtypeicon-*`** beside a quest's title. Matched against the client's own LOCALISED
  tag constants (`RAID`, `DUNGEON`, `PVP`, `ELITE`, `GROUP`) rather than English literals, with the
  suggested group size as the fallback — so the badges survive a translated client.
* **`questcollapse-show`/`-hide`** on the side-panel toggle, in place of `<` and `>`.

Every one of them degrades to its previous placeholder if the atlas fails to resolve, and the
harness asserts each actually **reached a widget** — an atlas that silently leaves the fallback in
place is the failure mode this module has re-learned more than once.

Four sheets are registered and deliberately unconsumed: the two tracking buttons want the filters
menu behind them (Phase 5), `ObjectIconsAtlas` wants the pin work, `ui-questpoi-questnumber` needs
the number the CLIENT assigned a quest rather than the row's position in our list, and the 2x
quest-log sheet only matters once the border is stretched large.

13. **No quest markers on the map at all.** Every quest POI and objective blob on this client is
    gated behind one checkbox, `WorldMapQuestShowObjectives`. The chrome squelches it — correctly,
    it is a stock tickbox floating over our layout and the cog offers the same switch — but
    squelching the WIDGET and never touching its STATE left the client deciding not to draw quest
    markers, and nothing said so.

    Mapster hits the same thing and settles it the same way (`Mapster.lua:132-134`): hide the box,
    set it *checked*, call the toggle so the client applies it. `WM.SetQuestObjectives` now does all
    three of the things that switch has to do — persist the choice, apply it through the client, and
    re-place the markers with `WorldMapFrame_UpdateQuests` — and the cog routes through it rather
    than poking the checkbox behind its back, which is how doing two of the three went unnoticed.

### Where the data for markers and fog actually is

Checked rather than assumed, because the obvious answer ("the reference addon must ship it") is
wrong in both directions.

**Fog of war — NewEra ships nothing.** The only thing in it matching "fog" is an atlas NAME
(`NE_ATLAS["fogofwar"]`, a texture). Era's MapCanvas has no vanilla overlay system to clear, so the
1.15 source has no reason to carry overlay data and does not.

**But this client does.** `WorldMapOverlay.dbc`, **988 rows**, in `patch-enUS.MPQ` — map, area,
texture name, offsets, dimensions, hit rect. That is the authoritative table Mapster's thousand-line
hand-written `errata` approximates, and the repo already has the pipeline to read it
(`tools/cdm-spellgen/dbc.py`, `mpyq`, pointed at the client's Data directory). Generating from the
player's own client is both cleaner than copying anyone's data and correct by construction.

**POIs — NewEra ships some, and none of what was asked for.**

| | What the 1.15 source has | Usable here? |
| --- | --- | --- |
| Cities, flight masters, innkeepers, mailboxes, transports | `WorldMap/UtilityPois_Seed.lua`, 304 lines, auto-generated from **Questie's** database | Keyed by Era **uiMapID** (947, 1411, …), which does not exist on 3.3.5a — every row would need remapping to this client's (continent, zone) index space. Questie-derived, so provenance needs settling before it is copied. |
| Faction-gated service POIs | `Quests/PoiData.lua` | Reads **Questie live at runtime**. Not shipped data at all. |
| **Dungeon and raid entrances** | — | **Nothing.** `Q.DungeonPois` reads Questie's `ZoneDB:GetDungeons()` live. The 1.15 source carries no entrance coordinates of its own. |

And the client cannot fill that gap either: `AreaPOI.dbc` has 738 rows of which **eight** even look
like dungeons, and those are zone names (Scholomance, Maraudon) rather than entrance markers.
`AreaTrigger.dbc` has 1,220 positions with no identity — which trigger leads where is server-side.
So dungeon entrance markers require hand-authored coordinates from somewhere, which is exactly why
ModernMapMarkers exists.

**Dungeon MAPS are a different thing and mostly already work.** 3.3.5a renders instance floors
natively (`GetNumDungeonMapLevels` / `SetDungeonMapLevel` / `GetCurrentMapDungeonLevel`, backed by
`DungeonMap.dbc`, 168 rows), and the breadcrumb already drives the floor selector — Dalaran's
"Dalaran City" crumb is that. The limit is that the client only shows a dungeon map while you are
INSIDE the instance: `SetMapZoom` has no dungeon entries, so there is no way to browse to Ulduar's
map from Stormwind. Making them browsable is what NewEra's 600-line `DungeonMap.lua` /
`DungeonMaps.lua` pair does, and the same technique works here because both halves ship in this
client — `WorldMapArea.dbc` for the texture folder and `Interface\WorldMap\<Folder>\` for the tiles.

14. **The canvas tooltip had no background.** `WorldMapTooltip` came up with its text and border and
    the map showing straight through it. It is a CHILD of the map window, which is what makes it
    ours: it inherits a strata we changed. Repaired rather than imposed — the backdrop is supplied
    only if the frame has none and the colour only if what it has is effectively transparent, so a
    skin that deliberately styled it keeps its styling — and lifted to TOOLTIP strata, which is what
    Mapster does to the same frame on this client for the same reason.

15. **ModernMapMarkers drew the previous zone's pins.** A Deadmines marker sitting in Hillsbrad. Not
    a positioning bug: MMM redraws off `WORLD_MAP_UPDATE` and short-circuits when the continent and
    zone it last drew for are unchanged, and its own throttle can swallow the event that would have
    told it. `MMM.ForceRedraw()` clears that pair so the next update passes.

    This is not a guess about its internals: MMM's own `NavigateToTransportDest` pairs `SetMapZoom`
    with `ForceRedraw` in exactly this order, so it is that addon's published idiom for "I moved the
    map myself" — and the breadcrumb moves the map the same way its transport popup does. Called
    from `setZoom` and when the dungeon overlay covers the canvas; costs nothing when MMM is absent.

    That is the module's stated position on POI data made good: this window seeds no markers of its
    own because a maintained addon already does it, so cooperating with that addon is a feature of
    the window rather than an afterthought.

**Still unverified, and only a `/reload` can settle it:** every geometry constant below is derived
from NewEra's source and from Mapster's, not measured in this client. See §6.

---

## 0. The headline finding: this is a rebuild, not a port

Every other window in this addon (Merchant, Inspect, Spellbook, …) downports a NewEra file that
drives *the same Blizzard frame* the 3.3.5a client ships, so the port is mostly art plus geometry.
The World Map is not that. NewEra's `WorldMap/` is 8,382 lines written **against Classic Era's
MapCanvas** — `WorldMapFrame.ScrollContainer`, `MapCanvasScrollControllerMixin`, `SetMapID`,
uiMapIDs, pin pools, data providers, `C_Map`, `C_QuestLog`. **None of that exists on 3.3.5a.**
`compat/C_Map.lua` in this repo already says so out loud: it stubs `GetMapInfo` to `nil` and notes
that the world map "is out of scope for v1".

3.3.5a instead ships a tile-and-dropdown map in FrameXML (not LoadOnDemand):

| NewEra / Era 1.15 | 3.3.5a equivalent | Verdict |
| --- | --- | --- |
| `WorldMapFrame.ScrollContainer` + `.Child` | `WorldMapDetailFrame` (1002×668, 12 tiles) inside `WorldMapPositioningGuide` | **rebuild the anchoring** |
| `MapCanvasScrollControllerMixin` (pan, wheel-zoom, click-to-navigate) | *nothing* — `SetMapZoom(continent, zone)` steps only | **write from scratch or drop** |
| uiMapID / `SetMapID` / `C_Map.*` | `GetMapContinents` / `GetMapZones` / `SetMapZoom` / `GetCurrentMapContinent` / `GetCurrentMapZone` | **remap the id space** |
| `MaximizeMinimizeButtonFrameTemplate` + `SynchronizeDisplayState` | `WorldMapFrameSizeUpButton` / `SizeDownButton`, `WORLDMAP_SETTINGS.size` | **rebuild the toggle** |
| Data providers + pin pools | `WorldMapPOIFrame` + `GetNumMapLandmarks` / `GetMapLandmarkInfo`; `WorldMapBlobFrame` + `QuestPOIGetIconInfo` | **rebuild the renderer** |
| `NavBarTemplate` (Era ships it) | *nothing* | **rebuild** — reuse `modules/encounterjournal/NavBar.lua`, which already solved this |
| `NE.squelch`, `NE.maxmin`, `NE.helpplate`, `NE.navbar` helpers | none of the four exist here | **write the ones we need** |
| Questie-derived POI seeds (`Quests/Pois.lua`, `UtilityPois_Seed.lua`) | Questie for 3.3.5a is a different fork with a different DB shape | **re-source or drop** |

So the useful question is not "how faithfully can we port these files" but "which of NewEra's map
*features* can 3.3.5a actually support, and in what order". That is what the phases below are.

### One thing that ports cleanly

NewEra's minimized window is 702×534, sized so its canvas is 697×465 and the 1002×668 child fits at
scale **0.6956** with zero letterboxing — the whole point of that number being that the canvas and
the child share an aspect ratio of 1.5.

3.3.5a's `WorldMapDetailFrame` is **the same 1002×668**. So NewEra's canvas geometry transfers
directly: the same window size, the same spacer, the same scale, no letterboxing.

What does *not* transfer is the client's own windowed scale. `WORLDMAP_WINDOWED_SIZE` is defined in
FrameXML (not readable from here) and, working back from Mapster's windowed frame of 623×437 with
`WorldMapDetailFrame:SetPoint("TOPLEFT", 37, -66)`, it must be **≈0.59**, not 0.6956. The port
therefore sets **its own** scale (697/1002) rather than reusing the client's constant, and writes
that value into `WORLDMAP_SETTINGS.size` so the client's POI math stays consistent with it (§5.3).
Nothing should hard-code either number: read `WORLDMAP_WINDOWED_SIZE` where the client's value is
needed, and derive ours from the canvas rect.

---

## 1. Ground truth for the 3.3.5a frame

Taken from `AddOns/Mapster/Mapster.lua` (installed here, v1.3.9, Interface 30300) — an addon that
already re-homes this exact frame on this exact client, so its element list is authoritative.

Frame tree and globals the port must know about:

- `WorldMapFrame` — 1024×768 full, 623×437 windowed. In `UIPanelWindows`; `SetToplevel(true)`;
  has an `OnKeyDown` (ESC) script; `BlackoutWorld` is the fullscreen dim behind it.
- `WorldMapPositioningGuide` — the layout anchor everything else hangs off in full mode.
- `WorldMapDetailFrame` — 1002×668, `SetScale(WORLDMAP_SETTINGS.size)`. Tiles `WorldMapDetailTile1..12`.
- `WorldMapButton` — the click/hover surface over the detail frame (drives `WorldMapFrameAreaLabel`).
- `WorldMapFrameAreaFrame` / `…AreaLabel` / `…AreaDescription` — the zone-name overlay.
- `WorldMapPOIFrame` — landmark pins, from `GetNumMapLandmarks()` / `GetMapLandmarkInfo(i)`,
  cropped out of `Interface\Minimap\POIIcons` by `WorldMap_GetPOITextureCoords(textureIndex)`.
- `WorldMapBlobFrame` — quest area blobs. **Protected in combat** — see §5.
- `QuestPOIGetIconInfo(questId)` + `WorldMapFrame_DisplayQuestPOI` — numbered quest pins.
- `WorldMapQuestScrollFrame` / `…QuestDetailScrollFrame` / `…QuestRewardScrollFrame` /
  `WorldMapQuestShowObjectives` / `WorldMapTrackQuest` — the native on-map quest log (full mode only).
- `WorldMapContinentDropDown`, `WorldMapZoneDropDown`, `WorldMapZoneMinimapDropDown`,
  `WorldMapZoomOutButton`, `WorldMapMagnifyingGlassButton` — the navigation the NavBar replaces.
- `WorldMapLevelDropDown` + `WorldMapLevelUpButton` / `…DownButton` — **dungeon floors are native
  here** (`GetNumDungeonMapLevels`, `SetDungeonMapLevel`, `GetCurrentMapDungeonLevel`).
- `WorldMapFrameCloseButton`, `WorldMapFrameSizeUpButton`, `WorldMapFrameSizeDownButton`,
  `WorldMapFrameTitle`, `WorldMapFrameMiniBorderLeft` / `…MiniBorderRight`, `WorldMapTitleButton`.
- `PlayerArrowFrame` / `PlayerArrowEffectFrame` — **`Model` frames, not textures** (`SetModelScale`).
  NewEra's `UI-WorldMapArrow-2x` texture swap does not apply; the arrow can only be scaled.
- `WORLDMAP_SETTINGS.size`, `WORLDMAP_FULLMAP_SIZE` (1.0), `WORLDMAP_QUESTLIST_SIZE` (0.8),
  `WORLDMAP_WINDOWED_SIZE` (0.695); `WorldMapFrame_SetPOIMaxBounds()` must be re-run after any
  size change or POIs clamp against stale bounds.

---

## 2. Conflict: Mapster is installed and enabled

`AddOns/Mapster` currently owns `WorldMapFrame` — it clears `UIPanelWindows["WorldMapFrame"]`, and
takes over drag, scale, position, strata, borders and the POI math. Two addons cannot own this
frame. NewEra's own module declares `conflictsWith = NE.modules.RIVALS.WORLDMAP` for exactly this
reason (it names Leatrix Maps and Carbonite).

**Action:** add a `WORLDMAP` row to `Mods.RIVALS` in `core/Modules.lua`:

```lua
WORLDMAP = { "Mapster", "Carbonite", "Leatrix_Maps", "MetaMap", "Cartographer", "Cartographer3" },
```

and register the module with `conflictsWith = NE.modules.RIVALS.WORLDMAP`. With Mapster loaded the
module reports as conflicted in the options and never boots, and the user keeps the existing
per-module `conflictOverride` escape hatch if they want ours instead.

`ModernMapMarkers` (also installed, v3.48) is **not** a rival — it does not touch the frame — but it
already draws dungeon, raid, world-boss, boat, zeppelin, tram and portal markers on this client's
map. That is most of what NewEra's `UtilityPois.lua` / `Dungeons.lua` / `OutlandPois.lua` exist to
provide. Phase 3 should therefore be scoped to **restyling the pins the client itself draws**, not
to re-seeding POI *data* someone else already seeds — otherwise every dungeon entrance gets two
markers. The two need checking against each other in game.

---

## 3. Phases

Each phase is independently shippable and leaves the map working. Sizes are estimates for *this*
client, not the source's line counts.

### Phase 1 — Chrome shell  *(~700 lines; no new art)*

The visible 80%, and the analogue of `modules/merchant` and `modules/inspect`.

- Suppress the client's chrome: `WorldMapFrameMiniBorderLeft/Right`, `WorldMapFrameTitle`,
  `WorldMapTitleButton`, `BlackoutWorld`, the three dropdowns, `WorldMapZoomOutButton`,
  `WorldMapMagnifyingGlassButton`. A NewEra `NE.squelch`-equivalent is needed (persistent
  re-hide on `OnShow`) because `WorldMap_ToggleSizeUp/Down` re-shows them on every open.
  → **new shared helper `core/Squelch.lua`**, useful to every future reskin.
- Build the HIGH-strata `NE_WorldMapBorderFrame` over `WorldMapFrame`: `NE.nineslice.ApplyLayout`
  with `PortraitFrameTemplateMinimizable`, `NE.portrait.ApplyCutout` on the quest-log book icon,
  the panel title, an `_UI-Frame-InnerTopTile` separator, and the 67px title/canvas spacer.
  **All of this art is already in `Textures/Common`** (2406979 / 2406984 / 2406987 / 1723831-3 /
  374155 rock / 4698972 RedButton-Exit). Nothing to extract.
- Re-home `WorldMapDetailFrame` + `WorldMapButton` + `WorldMapFrameAreaFrame` + `WorldMapBlobFrame`
  + `WorldMapPOIFrame` into the 702×534 window at scale 697/1002, driving `WORLDMAP_SETTINGS.size`
  so the client's own POI math stays consistent; re-run `WorldMapFrame_SetPOIMaxBounds()`.
- Reskin `WorldMapFrameCloseButton` to `RedButton-Exit-2x` **textures only** — leave its
  `OnClick` alone (the merchant/inspect taint rule; a replaced handler blocks closing in combat).
- Rebuild the maximize/minimize pair as `NE.maxmin` over `WorldMapFrameSizeUpButton` /
  `SizeDownButton` (the client has no `MaximizeMinimizeButtonFrameTemplate`), persisted in
  `DragonUI_NewEraDB`.
- Drag, `NE.panelmgr.Register`, pixel-perfect scale, `NE.modules.Register`, options row,
  QA harness entry.

**Open question for Phase 1:** whether to keep `UIPanelWindows["WorldMapFrame"]` (map shares the
panel row, closes with ESC, secure show/hide in combat) or clear it the way Mapster does (free
positioning, but we own show/hide and lose the combat-safe path). Recommend **keeping** it and
letting `NE.panelmgr` place the frame, consistent with every other window in this addon.

### Phase 2 — NavBar breadcrumb  *(~350 lines; no new art)*

Replaces the three dropdowns with `Azeroth > Kalimdor > Ashenvale`, plus the dungeon-floor
selector. Driven by `GetMapContinents` / `GetMapZones(c)` / `SetMapZoom(c, z)` /
`GetCurrentMapContinent` / `GetCurrentMapZone`, and `GetNumDungeonMapLevels` / `SetDungeonMapLevel`
for floors. **Reuse `modules/encounterjournal/NavBar.lua`** — it already rebuilt `NavBarTemplate`
from scratch for this client with overflow collapse, and ships its own art (516763 / 516764 /
423808). Promote it to `core/NavBar.lua` rather than forking it.

This is the phase with the highest UX payoff per line: it makes the map navigable the modern way,
and it is the only NewEra map feature with a clean 1:1 API mapping on 3.3.5a.

### Phase 3 — Pin and label restyle  *(~450 lines; needs 2 BLPs)*

- Modern `POIIcons` sheet (FDID 136441) over the client's landmark pins, and the crest-shield
  capital markers from NewEra's measured texcoords (already documented in the source's
  `Assets.lua` — the coordinates are transcribable verbatim).
- Quest POI pins restyled; area-label font/shadow to match the rest of the set.
- Tracking-button chrome (`Map-Filter-Button`, FDID 5756295) — only if Phase 5 lands, since
  without filters the button does nothing.
- **Not portable:** the player arrow. `PlayerArrowFrame` is a `Model`; the only lever is
  `SetModelScale`.

### Phase 4 — Quest Log side panel  *(~1,800 lines; the big one)*

NewEra's `QuestLogPanel.lua` + `QuestLogDetail.lua` (2,510 lines) rebuilt over 3.3.5a's quest-log
API (`GetNumQuestLogEntries`, `GetQuestLogTitle`, `SelectQuestLogEntry`, `GetQuestLogQuestText`,
`GetNumQuestLeaderBoards`, `GetQuestLogLeaderBoard`, `GetQuestLogRewardInfo`, `IsQuestWatched` /
`AddQuestWatch`). The window widens by 330px to seat it, exactly as the source does. Art (5684755 /
5684744 / 904010) must be extracted — none of it is in `Textures/` yet.

The client's own `WorldMapQuestScrollFrame` gets squelched, and `QuestLogFrame` is left alone.
Note this phase overlaps DragonUI's `modules/questtracker.lua` — check before starting.

`QuestNpcModel.lua` (the 3D model of the objective NPC) rides on this phase but needs an NPC data
source; without a 3.3.5a Questie equivalent it is a separate research problem.

### Phase 5 — Tracking menu and map filters  *(~350 lines)*

`core/Menu.lua` already provides the `MenuUtil`-shaped builder. 3.3.5a has no native landmark
filtering, so filters become our own per-pin show/hide over the Phase 3 renderer, persisted in
`DragonUI_NewEraDB.worldmap.filters`.

### Phase 6 — User pins / waypoints  *(~500 lines)*

Ctrl+click to place, share to chat, `/way` with TomTom's grammar, minimap mirror. Needs a
HereBeDragons-for-3.3.5a equivalent, or hand-rolled zone→continent coordinate translation. Self-
contained and genuinely useful; independent of every phase above except Phase 1's frame.

### Phase 7 — Zoom and pan  *(~400 lines, highest risk)*

The client has no continuous zoom. This would mean scaling and scrolling `WorldMapDetailFrame`
inside a clipping `ScrollFrame` and re-deriving every pin's position — and `WorldMapBlobFrame`
recomputes its hit translations off the detail frame's scale, so blobs must be re-drawn on every
zoom step (`WorldMapBlobFrame.xRatio = nil; WorldMapBlobFrame_CalculateHitTranslations()`).
**Recommend deferring** — it is the one feature where the client fights back hardest.

### Explicitly out of scope

- `DataProviders.lua` — re-registers Era mixins that do not exist here.
- `DungeonMap.lua` / `DungeonMaps.lua` — 3.3.5a renders dungeon floors natively (§1); the
  600-line tile-overlay workaround exists only because Era's uiMaps carry no art.
- `Dungeons.lua`, `UtilityPois*.lua`, `OutlandPois.lua`, `Quests/*` — Questie-DB-derived seeds
  against a fork that does not exist on this client, keyed to uiMapIDs.
- `Tutorial.lua` — depends on `Blizzard_HelpPlate`, which is Cataclysm+.

---

## 4. Proposed file layout

```
modules/worldmap/
  Assets.lua         -- Phase 3+: POIIcons / filter-button BLP registration
  WorldMap.lua       -- Phase 1: chrome, geometry, size toggle, squelch
  NavBar.lua         -- Phase 2: breadcrumb over core/NavBar.lua
  Pins.lua           -- Phase 3: landmark + quest POI restyle
  QuestLogPanel.lua  -- Phase 4
  QuestLogDetail.lua -- Phase 4
  TrackingMenu.lua   -- Phase 5
  UserPins.lua       -- Phase 6
  Register.lua       -- boot wiring, options row, QA entry
core/
  Squelch.lua        -- new shared helper (Phase 1)
  NavBar.lua         -- promoted from modules/encounterjournal (Phase 2)
```

`core/Modules.lua` gains the `RIVALS.WORLDMAP` row. Locale keys go in `Locales/` per the existing
convention (one key, one translation, shared between the module `desc` and the options row).

---

## 5. Known traps, in the order they will bite

1. **`WorldMapBlobFrame` is protected in combat.** Touching its parent, points, scale or
   visibility during combat throws. Mapster's `PLAYER_REGEN_DISABLED` / `_ENABLED` pair
   (`Mapster.lua:183-224`) is the known-good dance — reparent it off-screen for the duration and
   restore after, forcing `xRatio = nil` so hit translations recalculate. Any geometry pass we run
   must defer through `NE.dragon.CombatQueue`.
2. **The close button's `OnClick` must stay Blizzard's.** Same taint rule the merchant and inspect
   ports already document: an insecure replacement fails `HideUIPanel` in combat.
3. **`WORLDMAP_SETTINGS.size` is read by the client's own POI math.** Change it and re-run
   `WorldMapFrame_SetPOIMaxBounds()` in the same pass, or pins clamp to stale bounds.
4. **`WorldMap_ToggleSizeUp/Down` re-shows suppressed chrome on every open.** A one-shot `:Hide()`
   is not enough — hence `core/Squelch.lua`.
5. **`GetCurrentMapContinent()` / `GetCurrentMapZone()` are 1-based into `GetMapContinents()` /
   `GetMapZones(c)`, and both shift** when the player is inside an instance or on a battleground
   map. `pcall` the getters (CONTRACTS §0) and treat `0` as "no zone selected".
6. **`WorldMapFrame` has an `OnKeyDown` script.** Clearing it (Mapster does) breaks ESC; keeping it
   while the frame is out of `UIPanelWindows` breaks it differently. Decide with Phase 1's open
   question above.
7. **The detail-tile seam.** NewEra's `unsnapDetailTiles` fix relies on `SetSnapToPixelGrid` /
   `SetTexelSnappingBias`, **neither of which exists on 3.3.5a**. If seams appear at our fractional
   scale, the only lever is choosing a scale whose tile edges land on integer pixels.

---

## 6. Testing

No in-game verification is possible from here, so every phase should ship with an offline test in
`qa/offline/test_worldmap.lua` (the `test_inspect.lua` / `test_bossmods.lua` pattern): the WoW API
mock gets the §1 frame tree, and the tests assert the chrome is *visible* — not merely built —
per the bossmods harness's own lesson that "existence is not visibility". `qa/staticcheck.sh` must
pass with the TOC block in.

The geometry constants in §0 and Phase 1 are derived from Mapster's source, not measured in game.
They need one in-game pass to confirm, and the plan should be treated as unverified on that point
until then.
