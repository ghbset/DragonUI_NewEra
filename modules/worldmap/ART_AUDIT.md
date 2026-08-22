# World Map — art audit against the reference screenshot

> **Update (2026-08-21, same day):** the owner supplied all twelve sheets into `Textures/WorldMap/`.
> Everything in "Already on disk" and the quest-log half of "Missing" is now **registered and
> wired** — see `modules/worldmap/Assets.lua` for the rects and the tail of that file for the four
> sheets that are registered but still waiting on UI to consume them. The audit below is kept as the
> record of what was needed and why.

What the retail-style map shows, what we ship, and what is missing. Written after the owner supplied
a reference shot (2026-08-21) and asked which textures stand between us and it.

**The coordinates are not the problem.** `ReferenceAddons/NewEra/Generated/AtlasData.lua` is a full
generated atlas database — every rect below is already measured and transcribable. The only thing
missing is BLP files.

---

## Already on disk, just not wired up

**`Textures/Spellbook/5684744-questlog.blp`** — shipped for the spellbook, and it turns out to carry
most of the quest-log panel's chrome:

| Atlas | What it draws in the reference shot |
| --- | --- |
| `questlog-tab` | the zone header bars (`Eversong Woods`, `Ritual Sites`) — a 9-slice that stretches |
| `questlog-icon-expand` / `-shrink` | the `+` / `−` on each header |
| `questlog-icon-ticksquare` + `-checkmark-yellow` | the tracking checkbox on each quest row |
| `questlog-icon-setting` | the cog top-right of the panel |
| `questlog-frame` + `-filigree` + `-gradient-bottom` | the border and top filigree around the list |
| `questlog-quest-glow-yellow` | the row hover highlight |
| `questlog-tab-icon-maplegend` / `-quest` | the map-legend toggle (Phase 5) |
| `questlog-reward-*` | the reward block in the detail pane |

Everything in that table can be wired **today, with no new art**, replacing the stock
`UI-CheckBox-*`, `UI-OptionsButton` and plain `+`/`−` text characters we currently draw. That is the
single largest visual gap between our panel and the reference, and it costs nothing but the work.

---

## Missing, and worth having

Ordered by how much of the reference they buy.

| FDID | Suggested filename | What it unlocks |
| --- | --- | --- |
| **5684755** | `5684755-questlog.blp` | **`questlog-main-background`** — the 307×510 parchment the quest list sits on. This is why our panel reads as a dark slab: there is no panel art at all behind it, only a tinted recess. Highest impact of anything on this list. |
| **5756295** | `5756295-map-filter-button.blp` | `Map-Filter-Button` — the funnel icon in the round button at the canvas's top-right (the one showing "2" in the reference). Needed before the tracking/filters menu (Phase 5) has anything to hang on. |
| **3500068** | `3500068-waypoint-mappin.blp` | `Waypoint-MapPin-Untracked` / `-Tracked` — the pin icon in the button below it, and the user-waypoint pins themselves (Phase 6). |
| **136430** | `136430-minimap-trackingborder.blp` | `MiniMap-TrackingBorder` — the metal ring both of those buttons sit in. This client ships an older, lower-detail version at the same path, so it needs overriding rather than adding. |
| **136467** | `136467-ui-minimap-background.blp` | `UI-Minimap-Background` — the dark disc inside that ring. Same override situation. |
| **136477** | `136477-ui-minimap-zoombutton-highlight.blp` | the hover glow on those buttons. |
| **3509691** | `3509691-ui-minimap-zoombutton-toggle.blp` | the "selected" ring retail draws on the pin button while placing a waypoint. |
| **904010** | `904010-cs-helptextures.blp` | `MapCornerShadow-Right` (the drop shadow under those buttons) and the `QuestCollapse-Show`/`-Hide` chevrons — which is what our side-panel toggle should be instead of the `<` / `>` text characters it draws now. |
| **5684767** | `5684767-questlog-2x.blp` | the 2x quest-log sheet. Only matters once the panel's border is stretched large; without it the 1x border softens on a big window. |
| **5151356** | `5151356-questtypeicon.blp` | `questlog-questtypeicon-dungeon` / `-raid` / `-group` / `-pvp` / `-daily` — the badge beside a quest's title. 3.3.5a reports the tag through `GetQuestLogTitle`'s `questTag`, so the data is there and only the art is not. |
| **5320914** | `5320914-questpoi.blp` | `ui-questpoi-questnumber` — the numbered POI blips in the reference's list and on its canvas. |
| **1121272** | `1121272-objecticonsatlas.blp` | the modern shared POI set (dungeon, raid, taxi node, innkeeper, mailbox). Would complete the pin restyle that `136441-poiicons.blp` started. |

---

## Not worth chasing

| From the reference | Why not |
| --- | --- |
| The **campaign header card** ("The Curse of Ula'tek", `Campaign: 0/6 Chapters`) | Campaigns are a Legion+ quest-log concept. 3.3.5a has no campaign, chapter or "next step" data to fill it with. |
| The **tutorial "i" button** top-left | Retail's `MainHelpPlateButton` drives `Blizzard_HelpPlate`, which is Cataclysm+. Already recorded as out of scope in PORT_PLAN.md. |
| The **circular dial** bottom-left of the canvas | Not part of retail's world map — the reference is a custom-content client, and this appears to be one of its own additions. |
| **5262907** (`RedButton-Expand` / `-Condense`) | Not needed: the same glyphs exist on `4698972`, which is already shipped, and `core/MaxMin.lua` uses them. |
| **1339312** (`worldquest-questmarker-dragon`) | The elite-world-quest underlay. No world quests on this client. |

---

## What to do about it

The zero-cost half — wiring `5684744` into the quest panel — is worth doing regardless, and would
land the zone headers, the tracking checkboxes, the cog and the list border in one pass.

For the rest, the sheets come from `wago.tools/api/casc/<FDID>` and drop into `Textures/Common/` (or
a new `Textures/WorldMap/`). **Registering an FDID whose BLP is not on disk is worse than not
registering it** — the redirect is set up, the texture silently fails to load, and everything using
it renders blank with no error. So each one gets wired only once its file is actually shipped, which
is the rule `modules/worldmap/Assets.lua` already follows for `136441`.
