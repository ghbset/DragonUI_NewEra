# DragonUI_NewEra

A support / extension module for **[DragonUI](https://github.com/NeticSoul/DragonUI)** — the World of Warcraft **3.3.5a (WotLK)** port of the Dragonflight UI.

DragonUI ports the Dragonflight **HUD** to 3.3.5a. **DragonUI_NewEra** fills in the rest: it faithfully downports the panel work from **NewEra** (Ashgaroth's Classic Era 1.15 Dragonflight-style addon) to 3.3.5a, rebuilding the panels DragonUI hasn't ported yet so the whole interface matches the modern look — not just the action bars.

> **Requires DragonUI and ClassicAPI.** This is an add-on *to* DragonUI, not a standalone UI — it reuses DragonUI's textures, atlases, and chrome where possible and only rebuilds what's missing. It also depends on **`!!!ClassicAPI`**, a compatibility layer that backports the modern API (`C_Timer`, `C_Texture`, `C_Container`, `C_Spell`, `C_Map`, `Mixin`, …) onto the 3.3.5a client; the panels are built against those modern globals. Both are hard dependencies (declared in the `.toc`) and must be installed and enabled.

## What's inside

### Spellbook

![Spellbook](screenshots/spellbook.png)

A standalone War-Within-style two-page spellbook, replacing the 3.3.5a `SpellBookFrame`:

- **Card layout** — every learned spell as a Dragonflight-style card (icon + name + rank), flowing across a two-page evergreen book; a min/max button collapses it to a single page (↗ Expand / ↙ Condense).
- **Category tabs** — General, your class (sectioned by spec), and a live Pet tab, styled to match the rest of the window set.
- **Active vs passive** — active spells use the gold spellbook frame; passives use the dark square talent-node socket. Passive cells are click-inert (hover for tooltip only); pet cells ignore right-click.
- **Whole-cell interaction** — click anywhere on a cell to cast, drag to place it on a bar, hover anywhere for the tooltip.
- **Search + options** — filter spells by name; a cog menu toggles *Hide Passives* and *Show All Ranks* (off = highest rank only).

Built natively for 3.3.5a's index-based spellbook API (a compat shim maps the Cataclysm `GetSpellBookItem*` family onto it).

### Talents

![Talents](screenshots/talents.png)

A standalone War-Within-style talent window over WotLK's classic grid talents, opened with **`/netalents`** or the default talent key:

- **Three trees** on the Dragonflight metal chrome, with real talent data, per-tree point readouts, and a live **preview → Apply / Reset** flow — left-click to spend, right-click to refund, nothing is permanent until you Apply (behind a confirm).
- **Retail-style nodes** — square / circle / capstone art derived per talent, with a hover highlight, a gold flash when a rank lands, and a subtle random glint that wanders across the talents you've spent points in.
- **Per-tier centering** — rows with fewer than four talents are packed and centred (the way retail lays them out), and the three trees are centred in the window.
- **Spec-art backgrounds** — each class/spec paints its own artwork behind the trees.
- **Animated connectors** — prerequisite links draw as a flowing dotted line straight from one talent to the talent that needs it.
- **Multi-spec** — bottom tabs switch between up to 4 specs depending on server configurations; rename the specs from the cog (custom names persist per character). View your other spec read-only (dimmed) and hit **Activate** to switch to it.
- **Pet talents** — hunters with a talented pet out get a **Pet** tab (Ferocity / Tenacity / Cunning) on the pet's own family artwork, with the same live preview → Apply / Reset flow, the pet's circular portrait, the correct 3-points-per-tier gating, and the single tree centred in the window.
- Sound cues for spending, refunding, applying, and switching specs.

Built natively for 3.3.5a's talent + preview-talent API (`GetTalentInfo`, `AddPreviewTalentPoints`, `LearnPreviewTalents`, dual `GetActiveTalentGroup`, and their `isPet` variants).

### Glyphs

![Glyphs](screenshots/glyphs.png)

The **Glyphs** tab shares the talent window — a hexagon of major/minor glyph sockets you socket, swap, and clear directly (the stock glyph frame is suppressed):

- **Class artwork** — each class gets its own full-window Legion-artifact-style backdrop behind the sockets.
- **One title, per-spec labels** — a single **GLYPHS** header; under dual spec each spec's name (**PRIMARY** / **SECONDARY**, or your custom rename, in caps) is lined up above its own socket cluster instead of repeating the title.
- **Animated links** — the same flowing dotted connectors as the talent trees tie the sockets together.
- ***Optional*** - see a list of the effects of each glyphs next to the glyphs

### Professions

![Professions](screenshots/professions.png)

A standalone Dragonflight-style profession window replacing the 3.3.5a `TradeSkillFrame`, with a modern recipe list, item/reagent details, a generic skill bar, and cog options — plus optional **Auctionator** integration via an AH scan button.

### Auction House

![Auction House](screenshots/auctionhouse.png)

A standalone Dragonflight-style Auction House window replacing the 3.3.5a `AuctionFrame`:

- **Buy** — search the market; results aggregate by item, drilling into a per-item detail page for bid/buyout.
- **Sell** — drag an item into the sell slot, set quantity/price/duration against a live view of that item's current market listings, and post.
- **Auctions** — Auctions/Bids sub-tabs with a retail-style summary of your listings grouped by item, plus the full owner/bidder list and Cancel Auction.
- **Auctionator reskin** — when Auctionator is installed, its Buy/Sell/More panel is reparented straight into this window and fully restyled to match (dark fill, gold-trim insets, zebra-striped rows, reskinned scrollbars/tabs/dialogs) instead of popping open its own separate parchment-style frame. Its tabs sit alongside the shell's own Buy/Sell/Auctions tabs and drive the same window.

### Bags — *work in progress*

![Bags](screenshots/bags.png)

A retail-style **combined bag** plus a per-window restyle for the **individual** Blizzard bag frames, both sharing the same metal chrome, recessed slots, portrait treatment, and item cues as the rest of the addon. **This one is still being built and polished — expect rough edges.**

- **Combined window** (default) — every backpack/bag slot in one movable Dragonflight-style grid, with a search box, a smart sort, and a bottom band showing your money + watched currencies. It takes over bag opening; a toggle in the NewEra options turns it off (→ stock Blizzard bags, needs `/reload`).
- **Individual bags** — a lighter restyle that skins the stock per-window bags in place (metal frame, portrait, recessed slots, rarity/usable cues) for players who prefer separate windows. Superseded by the combined window by default.
- **Smart sort** — consolidates partial stacks, routes specialty items into their bags (arrows → quiver, bullets → ammo pouch, herbs → herb bag, soul shards → soul bag, profession mats → their bags), then arranges by category → subtype → quality, with the Hearthstone pinned first and same-item stacks ordered fullest-first. The sort runs behind a "Sorting…" cover and keeps going until the layout settles rather than for a fixed number of passes.
- **Separate specialty bags** *(optional toggle)* — split quivers, ammo pouches, soul bags, and profession bags out of the general grid into their own labeled sections below it (**QUIVER**, **MINING BAG**, **HERB BAG**, …), mirroring the keyring row.
- **Keyring row** *(optional)* — show your keys as a **KEYS** row inside the window.
- **At-a-glance cues** — item-rarity glow, a red tint on anything you can't use (missing weapon/armor proficiency, too low a level, or a recipe whose profession/skill you don't have), the merchant "sell" cursor, a quest-item glow, and optional auto-sell-junk at vendors.

### Social & Guild

![Guild and Social windows](screenshots/social-guild.png)

Standalone Dragonflight-style windows replacing the 3.3.5a `GuildFrame` and `FriendsFrame`:

**Guild** — a **Communities**-look window scoped to what 3.3.5a actually serves (no Benefits/Rewards, ClubFinder, or calendar — those are Cata+ systems):

- **Roster** — sortable member list (Level / Class icon / Name / Zone / Rank / Note) with a guild-tabard badge, member detail, and the full permission-gated action set: public/officer notes, promote/demote/remove, and party invite.
- **Guild Info** — the Message of the Day and Guild Information text wells, editable in place when you have the right, shown side by side with Guild Chat.
- **Guild Chat, with history sync** — regular guild and officer chat rendered in the modern chrome, with **class-colored names** (live and backlog). Since 3.3.5a keeps no server-side chat log, a rolling per-guild history is saved locally and, on login, synced from other online guildmates over an addon message so a fresh `/reload` doesn't show an empty window — deduplicated and correctly ordered even across guildmates' differing system clocks. History is shared across all characters on your account in the same guild.

**Social** — built on the classic friends/ignore/who/channels/raid APIs:

- **Friends** — two-line entries (status icon + name/level/class over zone) with Friends and Ignore sub-tabs.
- **Who** — the stock Name / Zone / Lvl / Class columns, with a switchable second column (zone/guild/race) and full filter support.
- **Guild** — opens the standalone Guild window above rather than hosting a duplicate view inline.
- **Chat** — the chat-channels tab: a grouped channel list (Group / World / Custom headers) on the left, a live roster for the selected channel on the right, and an Add-channel button.
- **Raid** — a native raid roster grid with convert-to-raid and a full right-click context menu (promote, demote, assign main tank/assist, remove), permission-gated the same as stock.

### Looking For Group

![Looking For Group](screenshots/Dungeon-Raid-Finder.png)

A unified Dragonflight-style Group Finder window merging the 3.3.5a Dungeon Finder (LFD) and Raid Browser (LFR) into one panel, replacing the two separate stock windows:

- **Left-hand category rail** — Dungeons / Raids, bluemenu chrome, and an animated searching-eye portrait (idle when closed, an eye-opening/searching flipbook while you're queued, role-checking, in a proposal, or listed).
- **Dungeons** — the full LFD queue: Random/type dropdown, specific-dungeon list with lock and reward icons, the random-dungeon reward panel (money/XP/loot), role selection, and join/backfill.
- **Raids** — both LFR modes on one pane: **Queue** (multi-select raid list + comment, list/unlist) and **Browse** (raid dropdown plus a live results list with whisper/invite).
- **Role selection** — modern round tank/healer/dps/leader medallions sharing one row component between the Dungeons and Raids panes.
- Drives the same native `LFDParentFrame` / `LFRParentFrame` queue state under the hood — this is a modern view over 3.3.5a's real Dungeon Finder and Raid Browser APIs, not a reimplementation, so it works with whatever LFD/LFR rules the server actually runs.

### Adventure Guide (Encounter Journal)

![Adventure Guide](screenshots/dungeon-journal.png)

A standalone Dragonflight-style **Adventure Guide**, downported from NewEra's Encounter Journal — 3.3.5a never shipped one natively (the Encounter Journal is a Cataclysm+ feature), so this is entirely new UI over hand-seeded boss/loot data. Open it with **`/aguide`** (aliases `/adventureguide`, `/ej`), the micro button next to the main menu icons, or the `ToggleEncounterJournal()` global this addon creates for other addons to hook into:

- **Classic, Burning Crusade, and Wrath of the Lich King** instances — dungeons and raids, browsable by expansion tier.
- **Per-boss pages** — abilities and full loot table, tabbed like retail's journal.
- **Loot browsing** — every boss's drops with icon, name, and armor/weapon type, split correctly across 10/25-man and Normal/Heroic where the source data distinguishes them.
- **Search + breadcrumb navigation** — filter the instance grid by name, drill into an instance and back out via the nav bar.

### Cooldown Manager

![Cooldown Manager](screenshots/cooldownmanager.png)

Retail's **Cooldown Manager** (a *War Within* feature) downported from NewEra — four HUD viewers that track what's ready, what's running, and what's on you, plus the window that decides what goes in them. Open it with **`/cdm`**; the viewers themselves are placed from **`/dragonui edit`**.

- **Four viewers** — **Essential** and **Utility** cooldown icon rows, a **Buff Icons** row, and **Tracked Bars** with names and countdowns. Each one is independently placed, sized, and toggled.
- **Curated per class, then filtered by you** — spell lists come from the client's own DBC data (never hand-typed IDs), and grouped into *Essential* / *Utility* / *Not Displayed*. Drag a tile between sections to move it; search to find one.
- **The picker is your character's arsenal, not your class's** — anything you haven't learned yet is hidden, talents you didn't take included, so *Not Displayed* means "you chose not to show this" rather than "you can't cast this". Newly trained abilities appear on their own. Turn on **Show Unlearned** in the cog to see the full class list anyway; unlearned entries there are tinted red.
- **Tracked buffs** — a generated per-class aura catalog plus a live registry of every buff the scanner has actually seen on you, so procs that aren't in any list still turn up and can be tracked.
- **Trinkets** — on-use trinkets are discovered from what you're wearing, no configuration.
- **A spell's frame lights gold while its own buff is up**, so you can see at a glance which of your cooldowns is currently *doing* something rather than merely off cooldown.
- **Alerts** — right-click any tile to pick a trigger (*Available*, *Refresh*, *Active*, *Usable*), an **FX Style**, a refresh window, and a **ready sound** from the client's full sound catalogue. A small badge marks every tile that has one configured.
- **Edit mode** — `/dragonui edit` gives each viewer a mover and a settings dialog: orientation, icon limit and direction, icon size, padding, opacity, visibility, timers, and tooltips.
- **Starter layouts per spec** — 30 curated starting points, one per talent tree. A new spec gets its own automatically the first time you play it; you can load any of them by hand from the Layout menu, and off-spec spells are switched *off* rather than removed, so anything you want back is one drag away in the picker. Your spec is read from talent points spent — with no points, or an exact tie, it asks rather than guessing.
- **Layouts** — save and apply layouts, share them as import/export strings, drop back to a starter layout, and undo the last layout change with **Revert**. Layouts are stored **per spec**, so your dual-spec setups don't fight each other.

Note: Module is off by default

### Level Up Display

![Level Up Display](screenshots/levelupdisplay.png)

Retail's **level-up banner**, which 3.3.5a never shipped — "You have reached level N", followed by what that level actually gave you. Preview it any time with **`/nelevelup <level>`**; place it from **`/dragonui edit`**.

The difference from every other version of this addon is where the data comes from. Others ship a hand-typed `spellList[CLASS][level]` table of spell IDs, which is only correct on the server it was written against — private servers move trainer levels, add abilities and remove others, and a baked table is then wrong *silently*, announcing spells that don't exist and missing the ones that do. **This one asks your server instead.**

- **Abilities are read from your own class trainer.** Opening a trainer harvests every service it offers — name, rank, icon, and the level *your server* requires — including the ones you can't train yet, so a single visit at level 20 fills in the requirements up to 80. Nothing is keyed on a spell ID, so a server's custom abilities are picked up correctly without this addon knowing they could exist.
- **Battlegrounds, dungeons and raids come from the client's own brackets**, already localized. A realm that opens Alterac Valley at 20 needs no configuration.
- **Talent points** are derived from your actual point totals, so a server granting a different rate is followed rather than assumed.
- **Auto-granted spells** are caught by a spellbook diff — abilities a server hands you on level-up appear at no trainer, and would otherwise be invisible.
- **Everything is stored per realm**, so one installed copy serves several servers without their data bleeding into each other.
- **Long lists go to a grid.** A single level can grant a dozen unlocks; rather than parade them one at a time for a minute, anything over four is shown at once in a panel.
- **A small Blizzlike fallback** covers only what no API can report — glyph slots, dual spec, riding — and withdraws the moment the harvest observes the server's own answer.

`/nelevelup coverage` reports what has been learned for the current realm and class; `/nelevelup harvest` re-reads an open trainer on demand.

### Boss Timers

Retail's **Boss Abilities** timeline and **encounter warnings** (the `Blizzard_EncounterTimeline` / `Blizzard_EncounterWarnings` systems added in 11.1), downported from NewEra — a vertical rail down which spell icons slide toward "now", plus three tiers of centre-screen warning text flanked by spell icons.

**Requires Deadly Boss Mods.** DBM keeps ownership of *detection* — the combat log heuristics, the per-boss modules, the whole hard part — and this is a second view over its event bus, drawing retail's visuals from DBM's timers. Nothing here knows what a boss does. With DBM absent the module reports as unsatisfied in the options and never boots.

- **Two views, switched live** — the **Timeline** rail (icons riding a line toward the "now" end, with a queued track above it for what's further out) or **Bars**, a Cooldown-Manager-styled row list. Both are placed from **`/dragonui edit`**, with their settings on the frame itself.
- **Imminent cues** — an ability nearing its cast swells toward 1.35x, lights a proc glow, and blinks in its final second. The countdown sizes itself off the drawn icon and carries a shadow under its outline, so it stays readable on top of spell art at any Icon Size.
- **Three warning tiers** — Critical, Medium and Minor, each its own placeable frame off `DBM_Announce`, each sized and dimmed from its own handle.
- **DBM's own display is suppressed** while this is up, so nothing double-draws — bars *and* warnings, session-only, with no writes to DBM's saved settings. That isn't a setting: it follows whether this module is running, since the two are the same decision. DBM's sounds and voice packs are left alone either way.
- **Nothing DBM draws is lost.** A raid leader's pizza timer and the world-buff alert go straight to DBM's bar library and fire no callback, so they're adopted off a hook and rendered here rather than vanishing with the rest of DBM's bars.
- **Per-frame settings** — view, orientation, icon direction, icon size, length, bar width, flip, background, opacity, padding, timers, tooltips, visibility, and the imminent glow; Revert (session undo) and Reset in the footer.

**Off by default.**

## Roadmap

Faithfully downporting the remaining NewEra panels to 3.3.5a:

- [x] ~~**Spellbook**~~ — *done* (two-page book, category tabs, active/passive frames, search + Hide Passives / Show All Ranks, single/double-page toggle)
- [x] ~~**Talents**~~ — *done* (3-tree panel, live preview/Apply/Reset, retail-style nodes, per-tier centering, spec-art backgrounds, animated connectors, dual-spec tabs with custom names, hunter **pet talents** tab, and a **glyphs** page with per-class artwork)
- [x] ~~**Professions**~~ — *done* (Main profession Window, extra integration with Auctionator via AH Scan Button)
- [x] ~~**Auction House**~~ — *done* (Buy/Sell/Auctions panel, plus a full Auctionator embed + reskin when it's installed)
- [x] ~~**Guild**~~ — *done* (Roster with member actions, Guild Info, Guild Chat with class-colored names + cross-session/cross-character history sync)
- [x] ~~**Social**~~ — *done* (Friends + Ignore, Who, Chat channels, Raid roster; Guild tab opens the standalone Guild window)
- [x] ~~**Looking For Group**~~ — *done* (unified Dungeon Finder + Raid Browser window: Dungeons/Raids category rail, role selection, raid queue + browse)
- [x] ~~**Adventure Guide (Encounter Journal)**~~ — *done* (Classic/TBC/Wrath instances, per-boss abilities + loot pages, search + breadcrumb nav)
- [x] ~~**Cooldown Manager**~~ — *done* (Essential/Utility/Buff-icon/Tracked-bar viewers, DBC-sourced talent-gated spell lists, tracked buffs + trinkets, right-click alerts and ready sounds, edit-mode movers and per-viewer settings, per-spec layouts with import/export)
- [x] ~~**Level Up Display**~~ — *done* (retail's level-up banner, with unlocks harvested from the live server's own trainer/battleground/dungeon data rather than a baked spell table, per-realm storage, grid overflow panel, `/nelevelup`)
- [x] ~~**Boss Timers**~~ — *done* (retail's encounter timeline + warning tiers over DBM's event bus: rail or bar view, imminent glow/grow/blink, three placeable warning tiers, DBM display suppression with orphan-bar adoption; requires DBM)
- [ ] **Bags** — *work in progress* (retail combined bag + individual-bag restyle: grid, smart sort, separated specialty-bag sections, keyring row, rarity/usable cues, money + currency band)
- [ ] **Quest Log**
- [ ] **Merchant**
- [ ] **Mail**

## Credits

- **[DragonUI](https://github.com/NeticSoul/DragonUI)** by NeticSoul — the base 3.3.5a Dragonflight UI port this builds on.
- **NewEra** by Ashgaroth — the Classic Era Dragonflight-style addon these panels are downported from.
- **EZCollections** by ZEUStiger — some retail-look art (the bag window's loading spinner) is ported from EZCollections.
- **Deadly Boss Mods** — the encounter detection behind the Boss Timers module; this addon only draws what DBM reports.
- Dragonflight UI © Blizzard Entertainment.
