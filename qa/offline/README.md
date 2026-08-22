# Offline harnesses

Run these **outside the game** to catch faults before a `/reload`. They complement `qa/Harness.lua`
(in-game, `/dnetest`) and `qa/staticcheck.sh` (TOC + trap grep).

Added during the Cooldown Manager port (see `modules/cooldownviewer/PORT_PLAN.md`).

## Requirements

- **LuaJIT** (Lua 5.1-compatible, the same dialect as the 3.3.5a client) — already on this machine at
  `~/AppData/Local/Programs/LuaJIT/bin/luajit`.
- **node**, plus `luaparse` for the syntax gate. There is no `luac` on this box; `luaparse` is the
  substitute. It must be resolvable from `check.js`, so install it either here:

  ```bash
  npm install --prefix qa/offline luaparse
  ```

  or globally (`npm install -g luaparse` and set `NODE_PATH`). `check.js` is the only thing that
  needs it — both `.lua` harnesses run on LuaJIT alone with no dependencies.

## Usage

`check.js` runs two passes: the Lua 5.1 syntax gate, and a **forward-reference** check for calls to a
file-local function written above its `local function` declaration. That second one is valid Lua and
parses clean, but the name is not in scope at the call site — it resolves to a nil global and throws
at call time. In this addon such calls are usually inside a `hooksecurefunc` post-hook, where a throw
silently kills the rest of the chain and strands whatever that hook keeps in sync; it reads as "the
window stopped updating", with no error shown. It has cost real debugging time here more than once.

Syntax-gate any set of files (Lua 5.1):

```bash
node qa/offline/check.js core/GridLayout.lua modules/cooldownviewer/Viewers.lua
```

Unit-test the grid layout engine (28 assertions: cell arithmetic, wrapping, direction mirroring,
per-child scale, retired/hidden children, degenerate cases):

```bash
luajit qa/offline/test_gridlayout.lua
```

Unit-test the panel coordinator (54 assertions: home-when-alone, the row starting from the leading
window's own position so nothing already on screen moves, left-to-right tiling by pushable then
show-recency, the frame-units conversion for scaled windows, the slide-left/tight-pack/cascade
escalation on a row that will not fit, user placement leaving the system both by drag and from
`db.windowPos`, the drag threshold that stops an accidental twitch counting as placement, the reset,
home coming from the declared default rather than a restored position, re-flow on resize, the combat
rule where a protected window keeps its slot but not its position, the secure-wrapped `watch` path,
and a row emptied by user placement — several windows up but the player has placed every one of them
— being a no-op rather than a fault):

```bash
luajit qa/offline/test_panelmgr.lua
```

Boot the whole Cooldown Manager stack against a stubbed 3.3.5a client and drive it through a
realistic event sequence (156 assertions) — load order, mover registration, spellbook rank
resolution, populate, cooldown start, rank-safe cooldown read, GCD suppression, live settings,
visibility, the buff viewers, the learn gate, custom-list shadowing, the alert engine and ready
sounds, spell hiding, and the `RegisterUnitEvent` filter:

```bash
luajit qa/offline/test_boot.lua
```

Exercise the Level Up Display's data layer against a stubbed trainer, battleground and dungeon API
(24 assertions) — trainer harvest across all three service filters, filter save/restore, collapsed
header handling, the no-level-requirement drop that keeps profession recipes out, realm namespacing,
server brackets beating Blizzlike constants, rank rendering, observed-over-fallback suppression, and
a custom server-only ability travelling end to end:

```bash
lua5.1 qa/offline/test_levelup.lua
```

Unlike `test_boot.lua` this one runs on stock Lua 5.1 (it stubs no rendering, only data), and it
deliberately covers `Assets`/`Data`/`Harvest`/`Unlocks` but not the two view files — see its header.

Drive the boss timers end to end against a stubbed client and a fake DBM (67 assertions) — the
`requiresAddOn` gate with and without DBM, the settings store, boot and editor registration, bar/
warning suppression, the timer feed, pause/resume, warning tiering, both views, the editor preview,
atlas coverage and the slash command:

```bash
luajit qa/offline/test_bossmods.lua
```

The fake DBM models the **installed** 3.3.5a fork (`AddOns/DBM-Core`, `AddOns/DBM-StatusBarTimers`),
not DBM master: it fires `DBM_TimerStart` and never `DBM_TimerBegin`, its payload stops at `guid`,
and its bars live on two unnamed anchors — the second of which does not exist until a huge bar is
created. That last detail is the one the 1.15 source's suppression would have missed, so it has its
own assertion. See `modules/bossmods/PORT_PLAN.md` §B.

Check the Details! theme against a stubbed Details v8.3.0 (71 assertions) — install at file load,
LibSharedMedia registration, every skin key the backport does NOT honour staying out of the table,
`show_timer` as its three-boolean form, the shipped BLPs' container (power-of-two and the palette
block — the client draws a BLP it cannot sample as solid bright green), the title bar's centring
arithmetic (nothing in that bar is positioned relative to the window, the header art's bottom rows
are shadow rather than bar so its centre line is not the band's, the title has to land on the row's
own inset to line up with the class icon, and plugin icons chain off the menu row in whichever
direction the skin picks), the K/M abbreviation plus the formatter re-select, the
window size being left to Details while the one scale an earlier build wrote is undone, Details' own
overhanging title-bar pieces being replaced and then handed back in their prior state, the header on
a re-apply (where Details skips the skin callback), both ways a reload loses the theme and the
restore for each, a skin the player chose being left alone across that restore, forced re-install,
and a clean no-op with Details absent:

```bash
luajit qa/offline/test_detailsskin.lua
```

The fake Details models the **backport in `ReferenceAddons/Details`**, not Details master: v8.3.0
refuses to overwrite an installed skin, has no `no_cache`, no `titlebar_*` keys, and — the detail the
port is built around — replaces an unknown skin name with the default and writes it back over the
player's saved choice. The skin-key assertions are a version contract: copying more of the 1.15
source back in fails here rather than silently doing nothing in game.

Drive the inspect window reskin against a stubbed `Blizzard_InspectUI` (141 assertions) — the
LoadOnDemand boot gate, the chrome sweep (the four UNNAMED wooden quadrants on each of the three tab
subframes go — and the talents pane declares its four one LAYER UP, which is what a BACKGROUND-only
walk used to miss; the talent tree's own art stays — the PvP pane's content does not, since we draw
that tab), the streak band's host
frame sitting above the nineslice that was covering it, the untinted stone body this window family
shares, the duplicate close button that has to stay hidden across a re-show, the rehosted title, the
tab strip's move to the frame's bottom-left, the ONE window size every tab keeps (the character panel's), the
scale-and-anchor fit that puts each native pane's content rect on the interior AT LIFE SIZE (plus
the mouse it has to give up, since a fitted pane hangs over the tabs), the slot anchors, the model
height derived from the interior with its race backdrop scaled to match, DragonUI's floating item
level being lifted off the weapon row it lands on, the hover-revealed model strip taking the native
rotate buttons down with it, the race backdrop's Gnome→Dwarf / Troll→Orc fallbacks, the header
lines — including the one that would error rather than misdraw, `string.format("%d", "??")` — the
modern PVP pane (its honor table, rank, arena rows, the empty-bracket row, the priming pass the
client needs before it answers, and the native frame it rides rather than hides), the Talents tab
opening the talent window on the inspected unit without stealing the pane, and the panel-layout
attributes that put the window beside the character panel instead of in its place:

```bash
luajit qa/offline/test_inspect.lua
```

The stubbed frame tree is transcribed from the real 3.3.5a `Blizzard_InspectUI` (Interface 30300),
not from the 1.15 source the module was ported from — the two windows share barely a frame name.
See `modules/inspect/PORT_NOTES.md` for that table.

One stub detail is load-bearing: **anchored sizes are captured at anchor time and only refresh on an
explicit `layoutPass()`**, because that is what a real frame does — its rect does not resolve until
the next layout, so `GetHeight()` right after a parent resize hands back the old span. An honest
stub passed a build whose model measured the interior at that exact moment and came out 88px too
tall in game.

Exercise the world map port (121 assertions) — the geometry, the suppression, the breadcrumb, the
quest list and the side panel:

```bash
luajit qa/offline/test_worldmap.lua
```

This one matters more than most, because `modules/worldmap` is the only module in this addon that is
a **rebuild** rather than a downport: there is no 1.15 source to diff against when a result comes out
wrong. The stubbed frame tree is the real 3.3.5a world map (Interface 30300), cross-checked against
Mapster 1.3.9 — an addon that re-homes the same frame on the same client, and therefore ground truth
for which globals exist and which of them carry a scale of their own.

Four stub details are load-bearing:

- **`CreateFrame` returns a SHOWN frame**, as the client does. The breadcrumb lays itself out from
  `refresh()`, which is gated on `bar:IsShown()`; a stub that defaults to hidden silently builds a
  one-crumb trail and every navigation assertion passes vacuously.
- **`GetWidth()` resolves anchor spans.** A frame pinned TOPLEFT + TOPRIGHT into a sized parent has
  no explicit width and the client works it out. The navbar is exactly that shape and its whole
  layout is driven off `GetWidth`, so a stub returning 0 makes it draw nothing.
- **`Set*Texture` takes a path OR an object, and `Get*Texture` always returns a TEXTURE.** That
  asymmetry is why `core/MaxMin.lua` seeds each state from a path and then crops through the handle
  — the repo has evidence for both behaviours (`modules/spellbook` passes objects and works,
  `core/PanelChrome` records objects silently no-opping), and the path form is correct under both.
- **`WorldMap_ToggleSizeDown` re-Shows the client's chrome**, as the real one does. That is the
  whole reason `core/Squelch.lua` exists, and the test asserts the chrome stays hidden across it.

It also found the port's one real bug before the game did: `safe()` packed `pcall`'s results and
unpacked from index 2, which loses arity — `#{...}` stops at the first `nil`, and
`GetQuestLogTitle` returns a nil `suggestedGroup` in the *middle* of its list, so every quest read
as a non-header with no complete and no daily flag.

## What test_boot.lua stubs

A minimal widget API (`CreateFrame`, textures, font strings, scripts, events) plus the 3.3.5a game
functions the module touches. Two stub details matter and are deliberate:

- **`GetSpellInfo` returns the 9-value WotLK signature** (`name, rank, icon, cost, isFunnel,
  powerType, castTime, minRange, maxRange`). Position 7 is castTime, *not* spellID. This is the trap
  that makes `core/SpellRanks.lua` load-bearing; the test asserts rank resolution returns 10947 and
  not the 1500 castTime.
- **`Show()` fires `OnShow` only on a hidden→shown transition**, matching the client. Getting this
  wrong is what first surfaced the `Rebuild → RefreshLayout → Show → OnShow → Rebuild` re-entrancy
  (now guarded in `Viewers.lua`).
- **`GetTime()` is constant within a frame**, which is what `NE.aura`'s snapshot cache keys on. A
  test that changes auras must call `nextFrame()` or it reads the previous scan.
- **`PlaySoundFile` and LibCustomGlow record what they were asked to do** rather than no-opping, so
  a test can distinguish "played the right file" from "silently played nothing" — the distinction
  that matters here, since retail sound-kit IDs are inert on this client.

The alert tests drive the ticker directly (`M.alerts._ticker`'s `OnUpdate`) rather than waiting on
time, and assert on the recorded glow, so they cover the ready-transition edge, the refresh window
boundary and the data gate on `usable`.

Both harnesses exit non-zero on failure, so they can gate a commit hook.
