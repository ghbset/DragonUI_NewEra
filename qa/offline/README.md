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
