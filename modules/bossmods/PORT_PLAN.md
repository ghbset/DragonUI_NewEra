# Boss Timers (Boss Mods) — Port Plan (Build Contract)

Downport of `ReferenceAddons/NewEra/Alerts/BossMods/` (Classic 1.15) onto 3.3.5a, as an **optional
module gated on DBM being installed**. Read `CONTRACTS.md` §0 first — every global convention there
applies (namespace `local NE = DragonUI_NewEra`, no `SetShown`, no masks, `-- DOWNPORT:` notes on
every deviation).

**Status: Phases 0-5 implemented and working in game.** Both views (the Timeline rail and the CDM
Bars list) and all three warning tiers are in, per the owner's call on §G.1 and §G.2. §G.3 (colouring
bars by DBM's `colorId`) was not taken — retail's timeline is single-coloured and nobody asked for
the divergence. §G.4 is resolved, not deferred: the anchor now includes the queued track's extent
(see §C.2), so the drag handle wraps it.

**Confirmed working in game**: the rail with icons riding it and countdowns on them, the queued
track above it, all three warning tiers, the imminent glow and grow, and — under `/dbm test` —
suppression of DBM's own bars AND warnings, so nothing double-draws.

Four in-game faults were found and fixed getting there — a crash (ERROR #132) on the first finished
bar (§C.5b), faded-in regions ending invisible (§C.5c), a parent's restored alpha never reaching its
child frames (§C.5d, which also caught an unbelted queued track and a highlight left fully opaque),
and retail's highlight swirl turning out to be an unclippable filled quad (§C.5e). Three are the
same underlying fact — **this client's animation engine does not leave regions where the animation
says it will** — and the fourth is art that only a mask can make sense of. The swirl's job is now
done by LibCustomGlow's ButtonGlow, held for the whole imminent window (§C.5e). The offline harness models
all of it, and `/nebossmods debug`, the dump that found the last three, is part of the module.

`qa/offline/test_bossmods.lua` passes (149 assertions): load order, the DBM gate, the settings store,
boot and editor registration, suppression across BOTH bar anchors, the timer feed with the installed
fork's exact payload, pause/resume, the animation-release cycle through both renderers, **that
railed events, queued events and warnings are all actually visible once their fades end**, warning
tiering, view swaps, the editor preview, atlas coverage (including that the §C.5e swirl is drawn on
no icon while the glow ring still is), the imminent glow's full lifecycle across pooled frames, the
diagnostic, both rail orientations and both icon directions, the imminent grow, hover tooltips
(including the non-spell fallback), the bar flip, the edit-mode dialog (coverage against NewEra's own
option list, the view-specific gating, Revert vs Reset, and per-tier editing) and the slash command.
Eight mutation checks confirm it bites — the source's `DBM.Bars`
lookup, the `SetScaleFrom`/`SetScaleTo` polyfill, the §C.5b Stop guards, either half of the §C.5c
end-state handling, the §C.5d child-frame restore, the glow's clear-on-release, and pinning
`isVertical()` back to true each fail it.
`qa/staticcheck.sh` PASSes with the TOC block in.

**Two lessons worth keeping**, both paid for the same way:

1. *Existence is not visibility.* The first round of assertions checked that frames were built,
   shown, textured and anchored — all true while nothing was on screen.
2. *A frame is not its tree.* The second round asserted the track's alpha and passed while the icon
   and countdown, which live on child frames, stayed at 0. Assert the thing the player actually
   looks at, not the handle you happen to hold.

**Still unproven: a real encounter.** `/dbm test` exercises the adapter end to end — real callbacks,
real bars, real warnings — so the remaining unknowns are the ones only a pull can answer: whether
`DBM_Announce`'s tiering reads sensibly against a real boss mod's traffic (the test mod fires only
regular announces and special warnings, so the Medium tier's personal-type routing is untested
against live data), whether MAX_BARS (12) is the right cap when a fight runs more timers than that,
and whether the horizontal rail — asserted but never yet on screen — reads correctly.

---

## A. What the source actually is

Retail has no native boss ability-timer bar — those are DBM/BigWigs even on retail. What retail *does*
have, since 11.1, is **`Blizzard_EncounterTimeline`** ("Boss Abilities": a vertical rail down which
spell icons slide toward "now", or a Cooldown-Manager-styled bar list) and
**`Blizzard_EncounterWarnings`** (three text tiers flanked by spell icons). Those are driven by
`C_EncounterTimeline`, which exists on no Classic-family client.

NewEra's answer — the one that ports — is the **Questie pattern applied to encounters**: the boss mod
addon keeps ownership of *detection* (combat-log heuristics, per-boss modules, the whole hard part),
and NewEra is just another consumer of its event bus, rendering the retail visuals. That indirection
lives behind one internal seam, `BM.Bus*`, with a per-backend adapter feeding it.

Source inventory (`ReferenceAddons/NewEra/Alerts/BossMods/`, 2,132 lines):

| File | Lines | Fate here |
| --- | ---: | --- |
| `BossMods.lua` | 1031 | **Port**, minus ~200 lines of retail Edit Mode settings codec (§C.1) |
| `Warnings.lua` | 331 | **Port** (Phase 4), minus its `NE.editmode` registration |
| `Suppress.lua` | 378 | **Drop** — BigWigs bar-skin API only (§C.4) |
| `EventIcon.lua` | 101 | **Port**, mask → `NE.tex.CropIcon` (§C.3) |
| `DBMAdapter.lua` | 153 | **Port**, retargeted at the 3.3.5a DBM fork (§B) |
| `EditModeRegister.lua` | 140 | **Drop** — replaced by `Register.lua` on `NE.RegisterHUDFrame` (§C.2) |
| `Assets.lua` | 29 | **Port** + inline the atlas rects from `Generated/AtlasData.lua` |

---

## B. The backend: what the *installed* DBM actually fires

The reference adapter was written against DBM master (2026). This client runs the **WotLK 3.3.5a
fork** (`AddOns/DBM-Core`, `AddOns/DBM-StatusBarTimers`). It was read directly; the surface is
compatible but narrower, and two things are outright different.

**Callback mechanics — unchanged.** `DBM:RegisterCallback(event, fn)` (`DBM-Core.lua:1564`), invoked
`pcall(fn, event, ...)` (`:1540`) — event name first, exactly as the adapter assumes.

**Events this fork fires** (the complete `fireEvent` list): `DBM_TimerStart`, `DBM_TimerStop`,
`DBM_TimerPause`, `DBM_TimerResume`, `DBM_TimerUpdate`, `DBM_TimerFadeUpdate`, `DBM_Announce`,
`DBM_Kill`, `DBM_Wipe`, `DBM_Pull`, `DBM_SetStage`, `DBM_PlaySound`, `DBM_MusicStart/Stop`,
`DBM_Debug`, `DBM_UpdateZone`, the party/raid join/leave pairs.

Deltas that matter:

1. **`DBM_TimerBegin` does not exist here.** This fork fires only the pre-rename `DBM_TimerStart`
   (`DBM-Core.lua:10049`). Registering both names, as the reference does, stays correct — one of them
   is simply never heard.
2. **Shorter arg list**, and it stops before every argument the reference treats as optional:
   ```
   fireEvent("DBM_TimerStart", id, msg, timer, icon, timerType, spellId, colorId, modId,
                               keep, fade, name, guid)                    -- DBM-Core.lua:10049
   ```
   No `timerCount`, `isPriority`, `fullType`, `hasVariance`, `variancePeakTimer`, `isBarEnabled`.
   The adapter's positional handler still lines up (those tail params arrive `nil`), and its two
   guards degrade correctly: `isBarEnabled == false` is never true, so nothing is dropped, and
   `hasVariance` is never set, so no bar is ever drawn as approximate (`~`). **Keep both guards** —
   they cost nothing and make the adapter forward-compatible if the server ships a newer DBM.
3. `DBM_Announce (message, icon, type, spellId, modId, isSpecial)` — `:8183` (isSpecial=false) and
   `:9259` (isSpecial=true). Matches the reference 1:1, minus a trailing `count`.
4. `DBM_TimerStop (id[, guid])`, `DBM_TimerPause (id)`, `DBM_TimerResume (id)`,
   `DBM_TimerUpdate (id, elapsed, totalTime)` — all match.
5. **`DBM.Bars` does not exist on this fork.** The bar library is the *global* `DBT`
   (`DBM-StatusBarTimers/DBT.lua:43`), and `DBT:GetBarIterator()` is at `:605`. The reference's
   `findDBTAnchor` reaches through `DBM.Bars` and would return `nil` forever → no suppression, so
   **double-drawn bars**. Fix in §C.4.
6. **Two bar anchors, not one.** `smallBarsAnchor, largeBarsAnchor` are both created at `DBT.lua:179`
   as unnamed `UIParent` children. The reference's "every bar is a child of the one small anchor, huge
   bars only re-`SetPoint`" claim is false here — `DBT.lua:852`/`:859` note that Simple/NoAnim bars
   are *created on the large anchor*. Suppression must cover both. Fix in §C.4.
7. `DBMWarning` (`DBM-Core.lua:7812`) and `DBMSpecialWarning` (`:8849`) exist under those exact global
   names, so warning suppression ports unchanged.

**Not ported: BigWigs.** The user's requirement is DBM. `BM.Bus*` stays as the seam so a BigWigs
adapter is a drop-in later, but `BM.Backend()` collapses to DBM-present / not, `Suppress.lua` is not
ported, and the `backend` preference (auto/bigwigs/dbm) is dropped rather than shipped as a
one-option picker.

---

## C. Deviations forced by 3.3.5a / by this addon

### C.1 Settings: retail Edit Mode codec → our own store

The source reads every setting out of the active retail Edit Mode layout via `NE.editmode` (a 6,441-line
Edit Mode reimplementation this addon does not have and will not port) and converts through
`EM_CODEC` — the `EditModeEncounterEventsSetting` int table at `BossMods.lua:100-200`. All of that is
dropped, exactly as the Cooldown Manager port dropped it.

Replacement: the CDM pattern, verbatim — a `getOpt(frameID, key)` chokepoint over
`DragonUI.db.profile.newera.bossmods.frames[frameID][key]`, storing **display values** (percentages,
enum strings) with `BM_DEFAULTS` as the fallback layer. See
`modules/cooldownviewer/CooldownViewer.lua:346-391` for the shape to copy, including the
per-character override bucket.

Settings that stay wired: `viewType`, `iconSize`, `opacity`, `background`, `padding`, `barWidth`,
`visibility`, `showTimer`, `length`. Settings the source itself only persists (`orientation`,
`iconDirection`, `flipHorizontal`, `showSpellName`, `tooltipAnchor`) are **not carried over** — a
stored value no renderer reads is worse here than absent, since we have no retail-layout import to be
compatible with.

### C.2 Positioning: `NE.editmode` → `NE.RegisterHUDFrame`

`EditModeRegister.lua` is replaced by `modules/bossmods/Register.lua`, following
`modules/cooldownviewer/Register.lua` and `modules/levelup/Register.lua`:

- register at **PLAYER_LOGIN**, not at file load (DragonUI's AceDB is not guaranteed ready earlier);
- `NE.RegisterHUDFrame{ name, label, frame, key, defaultPoint, editorVisible, showTest, hideTest }`
  — **not** `NE.RegisterPanel`, which wires a MoversSystem mover that `/dui edit` never drives;
- `showTest` drives `BM.SetEditActive(true)` → the existing `EDIT_PREVIEW` looping sample events, so
  the rail is populated and grabbable in the editor. This is already written in the source
  (`BossMods.lua:993-1015`) and needs only re-pointing at DragonUI's editor hooks;
- `BM.SetViewMode`/`updateAnchorSize` call `NE.editmode.RefreshHandles()` — swap for the DragonUI
  equivalent (or drop; the handle re-reads size on next editor open).

The queued-track overhang (`BM.TIMELINE_QUEUE_EXTENT = 208`) renders *above* the rail. Retail wraps
it into the selection rectangle with `editModeSelectionTopOffset`; DragonUI has no such knob.
**Resolved by making it moot**: the anchor is sized `railLen() + TIMELINE_QUEUE_EXTENT` and the rail
is pinned to its bottom, so the queued icons are genuinely inside the anchor and the handle covers
them without any offset. `NE.RegisterHUDFrame` mirrors the anchor's size onto the handle via the
content frame's `OnSizeChanged`, so a view swap or a Length change follows automatically.

### C.3 No mask textures

`Frame:CreateMaskTexture` returns `nil` on this client (`core/Portrait.lua:45-58`,
`modules/character/Assets.lua:40`). Three call sites need it:

- `EventIcon.lua` icon rounding → `NE.tex.CropIcon(tex)`, the same substitution
  `modules/cooldownviewer/ItemMixins.lua:64` already makes. The `UI-HUD-CoolDownManager-IconOverlay`
  ring on top is what actually sells the rounded look, and it is already registered here.
- `Warnings.lua` flanking icons (`makeIcon`) → same.
- `combattimeline-line-break-mask` → **not needed**. The rail ticks are already drawn as solid dashes
  on top of an unbroken line (`TICK_COLOR`, owner-confirmed as the retail look), never mask-cut gaps.
- `combattimeline-fx-highlight-mask` → the swirl it clips is **not ported at all**. This section
  originally claimed the swirl would "degrade to the unmasked texture"; that was an assumption, it
  was wrong, and it shipped. See §C.5e.

### C.4 DBM suppression, rewritten for this fork

The reference's approach is right — DBM's own `DontShow*`/`HideDBM*` options early-return *before*
the callback fires, so using them would starve our renderer. Suppress visually, session-only, no
SavedVariable writes. But the mechanism must change (§B.5, §B.6):

```
-- Collect every distinct bar-frame parent from DBT:GetBarIterator() and alpha-0 each one.
-- Both smallBarsAnchor and largeBarsAnchor are unnamed locals; a bar is the only handle we get.
-- Re-asserted on every heard callback (the `heard` wrapper already ticks), so a large anchor that
-- first appears mid-fight is caught within one event.
```
Warning hosts (`DBMWarning`, `DBMSpecialWarning`) suppress exactly as written. Sounds and voice stay
DBM's — same policy as the source.

Belt-and-braces: if `DBT` is absent entirely (bars addon disabled, timers still firing), suppression
is a no-op and the module still renders. Log once, don't error.

### C.5 No Boss Banner

`DBM_Kill` routes to `NE.alerts.BossBanner_Play` in the source. This addon has no `Alerts` module and
no `NE_BossBanner` frame. `onKill` becomes a no-op guarded on the frame existing, so the routing
survives if a banner is ported later. DBM ships its own `DBM-BossBannerToast` regardless.

### C.5b `AnimationGroup:Stop()` from inside its own `OnFinished` crashes the client

**Found in game, not offline.** First `/nebossmods test` took the client down:

```
ERROR #132 (0x85100084) Fatal Exception
Exception: 0xC0000005 (ACCESS_VIOLATION) at 0023:0049ADC6
  referenced memory at "0x00000034" — could not be read
Current Addon: DragonUI_NewEra
Current Addon function: <unnamed>:Stop
```

`<unnamed>:Stop` is an AnimationGroup. The source's release path walks straight into it: `finishBar`
hands `releaseBar` to the finish/cancel group as its `OnFinished` payload, and `releaseBar`'s first
act is to `Stop()` every group on the bar — **including the one currently firing**. Era's engine
tolerates that re-entry; 3.3.5a frees the object and then follows the pointer. It fires on the first
bar that finishes or is cancelled, in either view, which is every pull.

Fix: `BM.StopAnim(ag)` is the only Stop in the module. Two guards, because either alone leaves a
hole — a `_neFinishing` flag set for the duration of a handler (so a self-Stop is refused whatever
the widget reports), and an `IsPlaying` check (which covers every other path and makes stopping an
idle group free). `BM.OnFinished(ag, fn)` installs handlers with that flag managed, so remembering
it is never a caller's job.

The offline harness could not see this: its stubbed `Stop()` was a no-op flag write. It now **models
the crash** — `ag:Stop()` raises if the group is inside its own `OnFinished` — and drives expiry,
early cancel and wipe through both renderers. Removing either guard fails 9 assertions.

### C.5c An alpha animation does not leave its region at the `to` value

**Found in game, by the `/nebossmods debug` dump added for §C.5b.** With the crash fixed, the rail
line drew and the warning frames were up, but every event icon and every warning was invisible:

```
track: shown=yes alpha=0.00 size=35x35 CENTER-><rail>.BOTTOM(0,298)  tex=…\Ability_Warrior_Cleave
cd:    shown=yes text=8s
view:  shown=yes alpha=0.00 text="Boss Warning - Critical — sample text"   expires=in 23.45s
```

Shown, sized, textured, anchored, counting down — and at alpha 0. The common factor is that each is
the target of a 0 → 1 fade-in (`IntroAnim` on the rail track, the swing's `ShowAnim` on the warning
view). `AnimationGroup:SetToFinalAlpha` does not exist on 3.3.5a, so the `setToFinalAlpha` guard
silently skipped and the animation did not leave the region at 1. The rail line rendered throughout
because nothing animates it, which is what made it look like "a bar with nothing on it"; the
warnings were visible only for the 0.2s the fade was mid-flight, which is what "brief flashes" was.

This is documented behaviour in this addon and I did not follow it —
`modules/cooldownviewer/Alerts.lua:328` says "the animation moves it by -0.55 from wherever it
happens to be, not to an absolute 0.45" and sets its alpha by hand for exactly this reason.

Fix: nothing infers a final alpha from an animation. `BM.FadeIn(region, ag)` attaches an
`OnFinished` that sets the end state, `BM.PlayFadeIn` sets the start state, and both renderers carry
a belt (one float compare per frame) that restores alpha if the group never fired at all — the
difference between a missing 0.2s flourish and an event the player never sees.

The harness now **models the client's behaviour**: `ag:Finish()` drops the owner back to the
animation's `from` before `OnFinished` runs, so only code that sets its own end state survives.
Removing the end-state handling fails 2 assertions — the same two faults, offline.

### C.5d …and a frame's alpha does not reach its child frames

The §C.5c fix restored the rail track, and the rail *still* showed nothing but the trail streak. The
next dump said why:

```
track:  alpha=1.00   ← restored
cont:   alpha=0.00   ← child frame, still invisible
cdHost: alpha=0.00   ← child frame, still invisible
```

On 3.3.5a alpha is **not inherited at render time** — every frame carries its own — and the alpha
animation that fades a parent writes 0 into its child frames as it plays without putting it back.
Restoring the parent restores the parent. The trail is a texture *on* the track, so it drew; the
icon and the countdown live on child *frames*, so they did not.

Fix: `BM.SetAlphaChildren(frame, ...)` declares the tree at build time, and `applyAlpha` /
`needsAlphaRestore` operate on all of it. Two further faults surfaced in the same dump:

- The belt lived in the railed branch, so a **queued** event never met it and stayed at alpha 0
  (`[3] Enrage … queued=yes track: alpha=0.00`). It is now above the railed/queued split.
- The highlight swirl fades 1 → 0 and therefore ended at **1** — an additive 108x108 blob stuck over
  a 35px icon (`cont [9] … alpha=1.00`), which is what "a faint highlight going down it" was. Both
  highlight groups now set their end state explicitly, like every other fade in the module.

The harness models the child-frame clobbering, and asserts visibility over the whole tree rather
than the parent alone — asserting the track by itself is precisely what let the §C.5c build look
fixed while every icon was still invisible.

### C.5e The highlight swirl is a filled quad, and is not ported

With everything visible, one artefact remained: a large pale disc washing over the icon as each
event went imminent. It is `combattimeline-fx-highlight-fx`, retail's highlight swirl — a 108x108
additive quad that retail CLIPS to the 35px icon with `combattimeline-fx-highlight-mask`.

§C.3 originally asserted this would "degrade to the unmasked texture… close enough at 35px that it
reads as the same flourish". That was an assumption about art nobody had looked at. Sampling the
sheet's own pixels settles it:

| atlas | size | centre alpha | ring alpha | shape |
| --- | --- | ---: | ---: | --- |
| `combattimeline-fx-highlight` (glow) | 86x86 | 38 | 149 | **ring** |
| `combattimeline-fx-highlight-fx` (swirl) | 107x107 | **211** | 155 | **filled disc** |

A solid disc three times the icon's width, drawn additively over the spell art and its neighbours on
the rail. So it is **not ported**, and its OVERLAY sub-3 slot stays empty — the same call
`modules/cooldownviewer/Alerts.lua:44` made about retail's PandemicFX quads, for the same measured
reason ("Worse than no FX").

What remains is the glow RING, which the sample confirms is genuinely hollow and needs no clip. The
-180° rotation went with the swirl, having nothing left to spin. The atlas entry stays registered,
commented, so the decision is visible where someone would look for it — and the harness asserts the
swirl is on no icon while the ring still is.

**The ring alone was not enough** (owner, in game): a one-shot border flash on a 35px icon at an
effective scale of 0.53 is genuinely easy to miss on a moving rail. So the swirl's job — *be
visible* — is now done by **LibCustomGlow's ButtonGlow**, the action-button proc glow, held for the
whole highlight window rather than flashed once. That library is already embedded and already drives
the Cooldown Manager's alerts (`modules/cooldownviewer/Alerts.lua:375`), so this is the same
renderer the rest of the UI uses for "look at this now", not a second vocabulary. The ring still
fires as the entry cue; the glow supplies the visibility. Settable (`showGlow`, default on) for
anyone who wants the pure-retail subtlety back.

The lifecycle is the part worth testing, and it is: a track is **pooled**, so a glow started and
never stopped is inherited by whatever event recycles the frame — an ability lit up as imminent
while 40 seconds out. Every path that lets a track go clears it (release, re-show, dropping back to
queued, leaving the window), `SetImminent` is idempotent so a per-tick call is one comparison, and
the harness asserts all of it against a fake LibCustomGlow. Removing the clear-on-release fails it.

### C.5f The editor handle, and the on-frame settings dialog

Two in-game corrections, both from the owner looking at the handle.

**The box was much larger than the content.** §C.2 had the anchor reserve the queued track's full
extent (five slots, 208px) above the rail so the handle would wrap queued icons. On screen that made
the handle a third taller than anything drawn in it — the queue is rarely more than a slot or two
deep — and retail's 55px cross-axis constant made it half again wider than the 35px icons. The
anchor now bounds what is always there: `railWidth()` (the widest thing on the rail, an icon at the
current Icon Size) by `railLen()`. Queued icons overhang the top; they still drag with it, being
children of the frame. Bars view gets the same treatment — its handle was a fixed 240x28 while both
sliders moved the row, so it now uses `sizeBar`'s own arithmetic.

**The frame needed its settings on it, like every other panel.** `modules/bossmods/EditorPanel.lua`
is the Cooldown Manager's dialog with this module's settings in it — the same `editorSettings` seam,
the same `NE.cooldownviewersettings.controls` widget kit, the same chrome, geometry and
drag-to-move. One page per FRAME, keyed by the same frameID the settings store uses. Revert (session
undo, disabled when there is nothing to undo) and Reset (defaults) sit in the footer. The CDM's
modal confirm on Reset is deliberately not ported: it guards a spell-by-spell setup there, and ten
layout values here.

**Coverage is measured against NewEra's own popup**, not against "size and scale" — the owner's
steer. `ReferenceAddons/NewEra/Alerts/BossMods/EditModeRegister.lua:buildTimelineOptions` is the
yardstick, and the harness asserts every renderable entry in it is present:

| NewEra option | here | note |
| --- | --- | --- |
| View Type, Visibility, Icon Size, Background, Opacity, Padding, Bar Width, Show Timer, Show Spell Name | ✅ | ranges aligned to theirs (Icon Size 50-200, Bar Width 50-200) |
| Length (NE-only) | ✅ | 200-800 rather than their 120-480 — their max barely clears the 426 default, and a tall screen wants more |
| **OverallSize / Size** | ✅ **added** | their popup carried it as a built-in Scale slider, so it never appeared in the option list and I missed it first time. Applied through `PinPixelPerfect`'s `userScale`, not a bare `SetScale`, so the frame stays pixel aligned |
| Orientation, Icon Direction, Flip Horizontally, Tooltips | ✅ **implemented** | see §C.5g — the owner asked for them, so they were BUILT rather than persisted and ignored |
| Glow when imminent | ✅ **ours** | no retail counterpart; it replaces the unclippable swirl (§C.5e) |

Warning tiers get Size, Icon Size and Opacity — the subset that renders. Unlike the options page,
which writes all three tiers at once so one slider can mean "the warnings", the dialog is opened
from a tier and edits that tier.

NewEra's popup hides view-specific settings with `showWhen` predicates. The CDM widget kit now has an
equivalent — `o.disabled`, a predicate re-evaluated on every Refresh, added to
`SettingsControls.lua` at the owner's request. It **greys out rather than hides**, deliberately: a
vanishing row reflows the page under the cursor as the neighbouring View dropdown changes. The
disabling is real rather than cosmetic — the widget stops responding, and the row and its child
frames dim explicitly, because this client does not dependably inherit a parent's alpha down to child
frames (§C.5d).

### C.5g The four "shell" settings, implemented

§C.1 dropped Orientation, Icon Direction, Flip Horizontally and Tooltips on the grounds that the
1.15 source marks all four SHELL — persisted, read back, and read by no renderer. The owner asked
for them to be included. Rather than ship four controls that store a value nothing acts on — which
is the thing §C.1 was actually objecting to — each is now wired:

**Orientation + Icon Direction** are one change. The rail had `BOTTOM` and a `+y` offset hard-coded
through `layoutRail`, `layoutQueue` and the per-tick positioning; those now resolve through three
functions — `isVertical()`, `nowEdge()` (which END is "now", the point events travel toward) and
`along(dist)` (a distance up the rail, as a `(dx, dy)` pair). Icon Direction picks the end, so
retail's left/right reads as bottom/top on a vertical rail and one stored value means "the way icons
travel" in either orientation. The line art is authored horizontal, so a horizontal rail takes the
plain texcoord rect and a vertical one the 8-arg rotation; the shadow plate has a per-axis atlas on
the same sheet; the tick dashes swap their long side so they still cross the line. Both settings
change on a live frame — every piece records its atlas name so texcoords can be re-derived.

**Flip Horizontally** mirrors a bar row: icon to the right edge, bar draining the other way, label
and countdown swapped so the text still reads outward from the icon. Re-anchored rather than
rebuilt, so it toggles live. `StatusBar:SetReverseFill` is absent on some 3.3.5a builds and is
stubbed once at construction — without it a flipped bar still mirrors, it just drains from the same
end, a cosmetic loss rather than a broken layout.

**Tooltips** need something to show, and DBM supplies it: `DBM_TimerStart` carries a spellId (arg 6),
which the adapter now passes through the bus onto the bar. Hovering shows the spell tooltip via
`GameTooltip:SetHyperlink("spell:N")` — `SetSpellByID` does not exist on 3.3.5a — anchored at the
cursor or beside the frame, or suppressed entirely. DBM raises plenty of timers that are not a spell
(pull timers, phase changes), so the id is often nil and the ability's own name is shown instead.
Mouse stays enabled and the SETTING decides whether the handlers draw anything: toggling
`EnableMouse` would swallow clicks meant for whatever sits behind the rail whenever tooltips were on.

### C.5h The imminent grow

Owner's ask: an ability about to go off should "grow a little larger". Retail's `PulseAnimation`
loops 1 → 1.1 → 0.9, which oscillates around the base size — on average it grows by nothing, and
the icon is as often smaller as bigger. It is replaced by a monotonic swell to 1.35x, driven per
tick as a pure function of remaining time, so it reads as a countdown rather than a heartbeat.

Deliberately a per-tick `SetScale` and not an animation. Scale animations on this client leave the
region wherever they stopped (the same hazard as §C.5c/d, which cost three rounds to find), and a
LOOPING one fighting a per-tick scale over the same property has no good resolution. Driven directly
it cannot drift: any interruption self-corrects on the next frame, and Icon Size multiplies it in one
place so the two can never disagree.

### C.5i The warning icons were outside their own alpha tree

Reported in game as "a lot of misalignment with ability icons and text in the warnings", with a
screenshot showing the flanking icons adrift from any text.

`makeIcon` builds each flanking icon as a CHILD FRAME of the warning's view, and every alpha call in
`Warnings.lua` was a bare `view:SetAlpha(...)`. By §C.5d that restores the view — and the text, which
is a *region* of it — while leaving the icons wherever the swing's alpha animation dropped them. Text
and icons therefore end up in different states: icons showing with no text beside them, or the
reverse.

This is §C.5d again, in the file that did not get re-read when the rail was fixed. The machinery
already existed; the warnings simply were not using it. They now declare
`BM.SetAlphaChildren(view, LeftIcon, RightIcon)` and every alpha write — placeStart, placeRest, the
hide animation, ShowWarning, the editor preview and the per-frame belt — goes through
`BM.ApplyAlpha` / `BM.NeedsAlphaRestore`.

The harness now asserts the whole tree rather than the view, and separately that both icons are
still anchored to the text. Dropping the icons from the tree fails it.

`/nebossmods debug` reports the text and both icons together — alpha, size and anchor — because the
fault they exist to catch is the two disagreeing. (Writing that dump introduced a fault of its own:
it reached for `fmtPoint`, a local in `BossMods.lua`, which is nil from `Warnings.lua` and turned the
diagnostic into an error at the moment it would be needed. The harness drives the dump in both
views, which is what caught it.)

### C.5j DBM's own bars were never actually suppressed

Reported as icons on the right of the screen under `/dbm test`. They were DBM's: `DBT.lua:181`
anchors its small bars `TOPRIGHT, 223, -260`. So the whole point of §C.4 — no double-draw — had
never worked, and only a test that raises real DBM bars showed it.

Two independent causes, both now read off the source rather than assumed:

1. **The wrong instrument.** Suppression alpha-0'd the bar ANCHOR and relied on that reaching the bar
   frames parented to it. That is precisely the behaviour this client is unreliable about (§C.5d).
   Anchors are now **hidden**, which hides children unambiguously everywhere — and a bar created
   later is born under an already-hidden anchor, invisible from its first frame with no polling.
   DBT shows its two anchors once at load (`DBT.lua:184`, `:189`) and never again, so it sticks.
   The warning hosts keep ALPHA, deliberately: DBM calls `Show()` on `DBMWarning` /
   `DBMSpecialWarning` on every announce, so hiding those is a fight lost every time and won a frame
   later — a flicker.

2. **The wrong moment.** `DBM_TimerStart` fires BEFORE the bar is created (`DBM-Core.lua:10049`), so
   the synchronous pass inside the callback runs when the bar — and on a first pull, its anchor —
   does not exist yet. A zero-delay `C_Timer.After` re-assert now runs after `DBT:CreateBar` returns.

Discovery also gained a `DBT_Bar_N` named-global scan (`DBT.lua:249`), which finds the anchors
through DBT's reuse pool when no bar is live. That one is **belt, not the fix**: with a warm anchor
cache the iterator finds them too, and the mutation checks confirm only Hide-not-alpha (4 failures)
and the deferred re-assert (1) are load-bearing.

The harness now models DBM's real ordering — callback first, bar after — and its named bar globals
and TOPRIGHT anchor. Modelling that order is what makes the second cause visible at all.

### C.5k "Duplicate icons below the warning" — DBM's, after all

Reported as a second pair of flanking icons below the warning, and correctly guessed to be DBM's.
My first check said otherwise and was wrong: I grepped the two warning hosts for `CreateTexture`,
found none, and concluded DBM draws no warning icons. **It draws them as inline `|T…|t` texture
escapes inside its own font strings** (`DBM-Core.lua:8121-8127`, gated on `WarningIconLeft` /
`WarningIconRight`), so there is no texture object to find. The owner's evidence — present under
`/dbm test`, absent under `/nebossmods warn` — was the correct read and pointed straight at it.

Note what DBM passes us: `fireEvent("DBM_Announce", message, …)` sends the PLAIN message
(`:8183`), never the decorated `text`. So our own warnings never contain DBM's icons; the ones on
screen were DBM's hosts still rendering.

Alpha could not suppress them. DBM re-`Show()`s each host per announce and drives
`font:SetAlpha(1)` on a 0.05s ticker, so an alpha set on the parent is outrun. The hosts are now
**hidden**, with a `HookScript("OnShow")` guard that re-hides in the same frame DBM shows one — so
there is no flicker to trade for it. `HookScript`, never `SetScript`: DBM owns those frames.

Restoring had to be reordered as a direct consequence — the guard reads the suppression table, so
`Show()` while the flag is still set is undone instantly and suppression could never be switched
off. Flag cleared first, then restore. The harness caught that, not a play session.

A second, independent fault was found and fixed while chasing this: our own tiers could be left
half-shown.

They are one of our own tiers left half-shown: the frame still up, the view faded to invisible, and
the two flanking icons — child frames, so untouched by the view's alpha (§C.5d) — still lit, with no
text between them. It gets into that state when the hide swing's `OnFinished` does not run, the same
animation-end hazard as §C.5c: the fade completes visually but `f:Hide()` never happens.

Fixed as an INVARIANT rather than a patch on the paths that end a warning: the per-frame `onUpdate`
now asserts that a tier with nothing running, not being previewed and not mid-hide-swing is not on
screen — hiding the icons and the frame. No route out of a warning can leave a tier half-shown,
because this runs every frame the frame is up. Removing it fails the harness.

### C.6 Small API checks

- `SetColorTexture` — used by the tick dashes and the edit placeholder. Retail/Era API, but already
  used across `modules/character/*` here (provided by `!!!ClassicAPI`). Fine.
- 8-arg `SetTexCoord` (the rail's vertical rotation, `ensureRail`) — exists on 3.3.5a.
- AnimationGroups (icon Intro/Pulse, warning show/hide) — exist on 3.3.5a.
- `fmtTime` falls back to `NE.cd.FormatBarTime`; this addon's `core/CooldownNumbers.lua` exposes
  `NE.cd.FormatTime`, **not** `FormatBarTime`. Point the port at `NE.cd.FormatTime` or add the alias —
  don't ship the silent inline fallback as the real path.

---

## D. Art

From `ReferenceAddons/NewEra/Art/BossMods/` → `Textures/BossMods/`:

| BLP | Size | Take? |
| --- | ---: | --- |
| `7389803-combattimeline.blp` | 4.2 MB | **Yes** — the whole rail: line halves, pip, divider, icon-trail, deadly/pause/queued/highlight FX |
| `7499559-damagemeters-background.blp` | 513 KB | **Yes** — the Bars-view background plate (the "Background" slider) |
| `7390391-combattimeline-line-break-mask.blp` | 2 KB | No — masks are dead here (§C.3) |
| `7393789-combattimeline-fx-highlight-mask.blp` | 17 KB | No — same |

Both kept sheets are palettized power-of-two (2048×2048 and 512×1024) and load on 3.3.5a.

Atlas rects: the 34 `combattimeline-*` entries plus `damagemeters-background` live in
`ReferenceAddons/NewEra/Generated/AtlasData.lua:2507-2540` and `:4164`. Extract the ~18 non-`-2x`
entries we actually use into `modules/bossmods/Assets.lua` as an `NE.tex.RegisterAtlases{...}` table —
this addon resolves atlases through `NE.tex`, not `C_Texture.RegisterAtlas` (`core/Texture.lua:8-14`).

Already registered here, and reused unchanged: `UI-HUD-CoolDownManager-IconOverlay`, `-Bar`,
`-Bar-BG`, `-Bar-Pip` (`modules/cooldownviewer/Assets.lua:65-79`). The rail needs **no new art beyond
the two sheets above**. Add a `Textures/BossMods/` section to `Textures/ASSETS.md`.

---

## E. Files and load order (TOC block)

Slotted after the Cooldown Manager block (it reuses the CDM atlases, which must already be
registered) and before `core/_HelloDemo.lua`:

```
# --- Boss Timers (downport of NewEra/Alerts/BossMods) — DBM-driven ---
modules\bossmods\Assets.lua       # sheets + combattimeline atlas rects; before any SetAtlas call
modules\bossmods\BossMods.lua     # settings store, anchor, bar pool, rail, queue, OnUpdate, BM.Bus*
modules\bossmods\EventIcon.lua    # the shared event-icon assembly (rail icons + bar rows)
modules\bossmods\Warnings.lua     # the three warning tiers (Phase 4)
modules\bossmods\DBMAdapter.lua   # DBM callbacks -> BM.Bus*; suppression. After BossMods/Warnings.
modules\bossmods\Register.lua     # RegisterHUDFrame x4 + RegisterOptionSection + slash
```

`NE.modules.Register` entries (both `default = false` — this is opt-in):

```lua
NE.modules.Register("bossmods", {
  default = false, label = L["Boss Timers"], category = "HUD",
  requiresAddOn = { label = "DBM", present = BM.DBMPresent },
  events = { "PLAYER_LOGIN", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED" },
  onBoot = boot,
})
NE.modules.Register("bossmods_warnings", { ..., requires = { "bossmods" } })
```

`requiresAddOn` is the existing gate (`core/Modules.lua:84-86, 152, 180`): with DBM absent the module
reports as unsatisfied, never boots, and `Mods.missingAddOn` carries the label for the options row —
which is exactly the "requires DBM installed" requirement, using machinery already in the addon.
`default = false` differs from the source (`default = true`) and matches the Cooldown Manager's
opt-in decision.

Locale keys go in `Locales/enUS.lua` behind `NE.L` — this branch's predecessor made that seam work,
so no new string is hard-coded.

---

## F. Phasing — all delivered

| Phase | Deliverable | Status |
| --- | --- | --- |
| **0** | Art copied, `Assets.lua` registering both sheets + 14 atlas rects; TOC block; `Textures/ASSETS.md` §8 | Done — `staticcheck.sh` PASS |
| **1** | `BossMods.lua`: settings store (§C.1), anchor, bar pool, Bars view, `BM.Bus*` | Done |
| **2** | `DBMAdapter.lua`: the six timer callbacks + announce/kill/wipe; suppression per §C.4 | Done |
| **3** | `EventIcon.lua` + the Timeline rail: art, ticks, pip, queued track, Intro/Pulse/highlight, `BM.SetViewMode` | Done |
| **4** | `Warnings.lua`: the three tiers off `DBM_Announce`, each its own HUD frame | Done |
| **5** | `Register.lua`: 4 HUD frames + editor previews, options section, `/nebossmods`, 37 locale keys | Done |

Phase 3 was the expensive one (~450 lines of renderer plus the art wiring). It was kept whole rather
than severed, per the owner's call.

**Not in the plan, added because nothing else could see it**: `qa/offline/test_bossmods.lua`, 67
assertions over a stubbed client and a fake DBM modelled on the *installed* fork. The stub
deliberately omits `SetShown`, `CreateMaskTexture`, `AddMaskTexture` and `Animation:SetTarget`, so
reintroducing any of the four fails as a nil call here rather than silently doing nothing in game.

---

## G. Decisions taken

1. **Timeline rail AND bars** — both shipped, defaulting to `timeline` as retail and the source do.
   The `View` dropdown switches them live.
2. **Warning tiers** — shipped, as their own module (`bossmods_warnings`, `requires = {"bossmods"}`),
   so they can be turned off without losing the timers.
3. **DBM timer colours — not taken.** This fork passes `colorId` on every `DBM_TimerStart` (its
   Add/AoE/Interrupt/Role classes) and retail's timeline is single-coloured, so using it would be a
   deliberate divergence from the thing being ported. The argument is still there if wanted: it is
   one `SetStatusBarColor` at the bus, behind a setting.
4. **Queued-track drag handle** — resolved in §C.2 by sizing the anchor to include the queue.
5. **Per-tier warning settings collapsed to one pair.** Retail gives each tier its own Edit Mode
   dialog, which is where the source's per-tier icon-size/opacity lived. On a single options page,
   three identical sliders labelled Critical/Medium/Minor is a worse trade than one pair that means
   "the warnings", so the options write all three tiers. The store is still per-tier, so splitting
   them later is a UI change only.
