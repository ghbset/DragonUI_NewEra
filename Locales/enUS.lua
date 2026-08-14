--[[
================================================================================
DragonUI_NewEra - English Locale (Default)
================================================================================
]]

local L = LibStub("AceLocale-3.0"):NewLocale("DragonUI_NewEra", "enUS", true, true)
if not L then return end

-- ============================================================================
-- PROFESSIONS
-- ============================================================================

L["Alchemy"]         = true
L["Blacksmithing"]   = true
L["Enchanting"]      = true
L["Engineering"]     = true
L["Herbalism"]       = true
L["Leatherworking"]  = true
L["Mining"]          = true
L["Smelting"]        = true
L["Skinning"]        = true
L["Tailoring"]       = true
L["Inscription"]     = true
L["Jewelcrafting"]   = true
L["Prospecting"]     = true
L["Cooking"]         = true
L["First Aid"]       = true
L["Fishing"]         = true
L["Select a recipe to craft"] = true
L["Hide item tooltips in list"]       = true
L["Colour names by skill difficulty"] = true
L["Plain skill bar (no animation)"]  = true
L["Create"]     = true
L["Create All"] = true
L["Show Learned"]   = true
L["Has Skill Up"]   = true
L["Have Materials"] = true

-- ============================================================================
-- AUCTION HOUSE
-- ============================================================================

L[" -- partial scan"] = true
L["Auction query is throttled. Try again in a moment."] = true
L["Buy out this auction for %s?"] = true
L["Choose search criteria and press \"Search\""] = true
L["Loading results..."] = true
L["Lvl"] = true
L["Modern visual shell for Buy/Sell/Auctions with optional Auctionator tab embedding."] = true
L["No listings."] = true
L["No results. Adjust filters and search again."] = true
L["Page %d of %d  (items %d-%d of %d, from %d auction)%s"] = true
L["Page %d of %d  (items %d-%d of %d, from %d auctions)%s"] = true
L["Page 1 of 1"] = true
L["Per Item"] = true
L["Place a bid of %s?"] = true
L["Scanning page %d of %d..."] = true
L["Searching..."] = true
L["Sort Per Item"] = true
L["You have no auctions."] = true

-- ============================================================================
-- BAGS
-- ============================================================================

L["All Bags"] = true
L["Auto-empty old bag when swapping"] = true
L["Auto-sell junk at merchants"] = true
L["Bag Options"] = true
L["Category (smart)"] = true
L["Combined bag (all-in-one)"] = true
L["Item Level"] = true
L["Keys"] = true
L["Merchant"] = true
L["Name"] = true
L["Not enough free space to swap that bag."] = true
L["One movable window showing every bag slot in a Dragonflight-style grid. Takes over bag opening and replaces the per-window 'Retail bags' restyle. Reload (/reload) to apply."] = true
L["Quality"] = true
L["Red-tint unusable items"] = true
L["Restyle the bag windows with the Dragonflight metal frame, portrait, and item quality borders. Disable to keep the stock Blizzard bags. Reload (/reload) to apply."] = true
L["Retail bags"] = true
L["Reverse sort order"] = true
L["Search"] = true
L["Separate specialty bags"] = true
L["Shift-right-click to stop watching"] = true
L["Show item level on items"] = true
L["Show keyring row"] = true
L["Sold %d junk item(s)."] = true
L["Sort Bags"] = true
L["Sort by"] = true
L["Sorting…"] = true
L["Swapping bag…"] = true
L["The same setting as Enable Item Level in DragonUI's options (Enhancements > Item Level). Covers the character panel and every other frame too."] = true
L["Turn on Item Level in DragonUI's options (Enhancements > Item Level) first."] = true

-- ============================================================================
-- COOLDOWN MANAGER
-- ============================================================================

L["(empty)"] = true
L["(your spec)"] = true
L["A ready sound plays when a COOLDOWN finishes.|nThis spell has none, so it can never play.|nClearing it also clears the badge."] = true
L["A spell can be on cooldown and buffing you at the same time. The glow says which icons are buffed; the timer says how long."] = true
L["Active"] = true
L["Alert"] = true
L["Always"] = true
L["Auto-track buffs under %ds"] = true
L["Available"] = true
L["Bar Content"] = true
L["Bar Width"] = true
L["Both of these are immediate and cannot be undone from here — Revert only covers layout changes."] = true
L["Buff Bars"] = true
L["Buff Icons"] = true
L["Buff tracking"] = true
L["Buffed spells"] = true
L["Buffs you have not seen before are recorded and listed under Not Displayed on the Tracked Buffs tab, where you can assign the ones you want. Nothing appears on screen until you do."] = true
L["Button Glow"] = true
L["Clear All Alerts"] = true
L["Clear Ready Sound"] = true
L["Clear all alerts and sounds"] = true
L["Clear every configured alert and ready sound?\n\nSpell lists and frame positions are not affected."] = true
L["Closes edit mode and opens the Cooldown Manager window, which carries the settings that are not per-viewer: alerts, ready sounds, buff tracking, icon fit and the resets."] = true
L["Cooldown Manager"] = true
L["Cooldown Manager Settings"] = true
L["Cooldown Manager layout string (Ctrl+C to copy):"] = true
L["Copy"] = true
L["Defensives, interrupts, CC and escapes."] = true
L["Delete"] = true
L["Delete the layout \"%s\"?"] = true
L["Drag onto Essential or Utility to track it."] = true
L["Draw the countdown number on each icon."] = true
L["Each viewer's own settings — size, spacing, orientation, visibility, what its icons show — live on the frame, in edit mode, where you can see what you are changing. These open edit mode with that viewer selected and its settings already up. Closes this window; not available in combat."] = true
L["Enable Cooldown Manager"] = true
L["Enabled"] = true
L["Essential Cooldowns"] = true
L["Everything"] = true
L["Everything (no spec)"] = true
L["Everything the Cooldown Manager can be told to do that is not about one viewer's layout. Layout and position both live on the frame itself, in edit mode (/dui edit) — click a viewer there for its own settings, or use the buttons just below to go straight to one."] = true
L["Export Layout"] = true
L["FX Style"] = true
L["Flashes once, the moment the cooldown finishes.|nWorks for every spell."] = true
L["Frame strength"] = true
L["Gap between icons. Retail offsets this by -4, so the low end overlaps slightly — that is the stock look, not a bug."] = true
L["Glow while buffed"] = true
L["Glows during the last %d%% of this buff's|nremaining time."] = true
L["Glows during the last %d%% of this spell's own|nbuff or debuff."] = true
L["Glows for as long as the spell is off cooldown|nand affordable."] = true
L["Glows for as long as this buff is on you.|n|nThe one that works for a proc: it asks whether the|nbuff is up, not whether something is castable|nor off cooldown."] = true
L["Glows for as long as this spell's effect is|nup on %s."] = true
L["Halo the icon gold while the spell's buff (or, for a shaman, its totem) is up."] = true
L["Hidden"] = true
L["Hide When Inactive"] = true
L["Horizontal"] = true
L["How many icons before the layout wraps. Vertical orientation reads this as icons per column."] = true
L["Icon Direction"] = true
L["Icon Limit"] = true
L["Icon Only"] = true
L["Icon Padding"] = true
L["Icon Size"] = true
L["Icon and Name"] = true
L["Icon fit"] = true
L["Icon inset"] = true
L["Import"] = true
L["Import Layout"] = true
L["In Combat"] = true
L["Lasts %s sec"] = true
L["Layouts"] = true
L["Layouts include appearance"] = true
L["Left"] = true
L["Load the %s starter layout?\n\nEssential is set to that spec's spells. Everything else for your class moves to Not Displayed — nothing is deleted, and you can drag any of it back.\n\nTracked auras, trinkets, alerts and frame positions are not affected."] = true
L["Marching Ants"] = true
L["Move to %s"] = true
L["Name Only"] = true
L["Name this layout:"] = true
L["New Layout"] = true
L["None"] = true
L["Not displayed on any viewer"] = true
L["Not yet learned"] = true
L["Nothing to undo. It covers LAYOUTS, not the settings|non these tabs — a viewer's own size and position revert|nfrom its edit-mode panel instead."] = true
L["Off by default. Turn on to show the four viewers; turn off to hide them again. Takes effect immediately either way, and nothing is forgotten — this switch stores one flag and touches nothing else, so your setup comes back exactly as you left it."] = true
L["Off, both specs share one set of lists. Turning it on copies the layout you have now into the spec you are in."] = true
L["Off, loading or importing a layout changes only what you track — lists, tracked buffs, trinkets, alerts and sounds. On, it also applies the orientation, icons per row, size, padding and opacity the layout was saved with.|n|nLayouts always SAVE appearance either way, so this only decides what happens when one is applied. Revert always puts appearance back, whatever this says."] = true
L["Off, orientation, icons per row, size, padding and opacity are one setup for every character. On, each character can differ — until you change something here it still follows the shared setup, so nothing moves when you tick this, and unticking it gives the shared setup back without losing what you changed."] = true
L["Offensive burst and damage cooldowns."] = true
L["Opacity"] = true
L["Open Cooldown Manager"] = true
L["Opens a share string you can copy with Ctrl+C.|nIt covers this class's spell lists, tracked auras,|ntrinket placement, alerts and sounds."] = true
L["Opens the Cooldown Manager window (/cdm) on its Spells tab. Needs the module on — the window configures the viewers, so it goes away with them."] = true
L["Options"] = true
L["Orientation"] = true
L["Pandemic Border"] = true
L["Paste a Cooldown Manager layout string:"] = true
L["Ready Sound"] = true
L["Ready sound: %s"] = true
L["Refresh"] = true
L["Refresh Window"] = true
L["Remove"] = true
L["Remove every per-spell alert and ready sound. Spell lists and positions are not affected."] = true
L["Rename"] = true
L["Requires the %s talent"] = true
L["Reset"] = true
L["Reset %s to its default layout?\n\nThis viewer's position, size, orientation and visibility all go back to stock. Nothing else is affected, and it cannot be undone."] = true
L["Reset Spell Lists"] = true
L["Reset spell and buff lists"] = true
L["Reset this class's Cooldown Manager spell and buff lists to their defaults?\n\nOther classes, alerts, sounds and frame positions are not affected."] = true
L["Reset to the starter layout?\n\nThis reverts every Cooldown Manager edit — spells, tracked auras, trinket placement, alerts and sounds — to their defaults, and clears your saved-layout selection.\n\nFrame positions are not affected."] = true
L["Restore the curated defaults and the auto-track window for THIS CLASS, clearing its spell lists, aura assignments and trinket placement. Other classes, alerts, sounds and positions are not affected."] = true
L["Retail's Cooldown Manager, driven from curated per-class cooldown lists. |cffffcc55Off by default|r — it adds four viewers to the middle of your screen, so it waits to be asked. Every setting — which spells and buffs are tracked, each viewer's layout, size and visibility, alerts and ready sounds — lives in the Cooldown Manager window itself (/cdm). Drag the viewers with DragonUI's editor mode to reposition them, and right-click one there for its own layout settings."] = true
L["Retail's behaviour: while buffed, the icon counts down the BUFF. Off, it counts down the spell's cooldown and the glow alone marks it as buffed — which is clearer when the two differ, as on Prayer of Mending."] = true
L["Revert"] = true
L["Right"] = true
L["Save, load, import and export the whole|nCooldown Manager setup for this class."] = true
L["Separate appearance per character"] = true
L["Separate layout per spec"] = true
L["Short-duration buffs and procs, as depleting bars."] = true
L["Short-duration buffs and procs, as icons."] = true
L["Show Timer"] = true
L["Show Tooltips"] = true
L["Show Unlearned"] = true
L["Show a slot only while its aura is active."] = true
L["Show a tooltip when hovering an icon."] = true
L["Show every short buff the moment it lands, without assigning it first. Convenient on a character you are still setting up; in a raid it fills the viewers with other people's cooldowns, food and flasks."] = true
L["Show the buff's time, not the cooldown"] = true
L["Show them as"] = true
L["Show this viewer at all. The editor handle stays either way, so this is reversible from right here."] = true
L["Sparkles"] = true
L["Talent specs"] = true
L["The frame is a soft shadow that falls on the icon's outer edge, so it only shows where there is icon underneath it. Strength draws it more than once to deepen it — that is also what makes its rounded corners read, since the icons themselves cannot be rounded here. Inset shrinks the icon, which slides the shadow off it, so raise that one sparingly."] = true
L["The full curated list for your class, both specs' spells|nincluded. This is what the Cooldown Manager shipped with|nbefore per-spec starters."] = true
L["Tracked automatically. Drag it into a section to pin it there."] = true
L["Undoes the last layout change — applying a layout,|nimporting one, or the starter reset.|n|nOne step, and only for this session."] = true
L["Usable"] = true
L["Use Starter Layout"] = true
L["Utility Cooldowns"] = true
L["Vertical"] = true
L["Viewer layout"] = true
L["Visibility"] = true
L["When this viewer is on screen at all. Hidden still leaves the editor handle here."] = true
L["Which of the two buff viewers auto-tracked buffs land in."] = true
L["Which spells and buffs you track is remembered separately for each talent spec, so a Discipline layout and a Holy one do not overwrite each other. Where each viewer sits is always remembered per character; the appearance settings are shared unless you say otherwise below."] = true
L["is turned off. Enable it in DragonUI's options, under New Era > Cooldown Manager."] = true
L["you"] = true
L["|n|nOn a buff row this is about RE-CASTING it,|nnot about the buff being up — that is Active."] = true
L["|n|nThe one for a DoT or a shield: it asks whether|nthe aura is up, not whether the cooldown is ready."] = true
L["|n|nThis one also waits for a target below %d%% health."] = true
L["|n|n|cff40ff40Applies %s to %s, so this will work.|r"] = true
L["|n|n|cff40ff40Its aura is active now, so this will work.|r"] = true
L["|n|n|cffffd200No aura of this name is up right now.|r"] = true

-- ============================================================================
-- ADVENTURE GUIDE
-- ============================================================================

L["(No abilities recorded for this encounter.)"] = true
L["(no model)"] = true
L["Adventure Guide"] = true
L["Eastern Kingdoms"] = true
L["Kalimdor"] = true
L["Model will load once seen within this session due to client limitations."] = true
L["Phase %d"] = true
L["The Adventure Guide: bosses, abilities, and loot for Classic and Burning Crusade dungeons and raids (/aguide)."] = true

-- ============================================================================
-- GUILD
-- ============================================================================

L["GuildControlPopupFrame is missing on this client."] = true
L["Modern Communities-style guild window (Roster / Info / Chat)."] = true
L["Promote"] = true

-- ============================================================================
-- LEVEL UP DISPLAY
-- ============================================================================

L["Battleground available"] = true
L["Can be learned from a trainer"] = true
L["Dungeon available"] = true
L["Enable Level Up Display"] = true
L["Level Up Display"] = true
L["New Feature"] = true
L["New Riding Skill"] = true
L["New Talent Point"] = true
L["New Talent Points"] = true
L["New rank available"] = true
L["On by default. Turn off to stop the banner appearing on level-up; the harvest keeps running either way, so turning it back on costs nothing."] = true
L["Play the level-up sound"] = true
L["Raid available"] = true
L["Retail's level-up banner. What it announces is read from |cffffcc55this server|r — abilities and their levels come from your class trainer's own list, battlegrounds and dungeons from the client's brackets. Visit a trainer once to fill it in; |cffffcc55/nelevelup coverage|r shows what it knows."] = true
L["Talents"] = true
L["You have reached"] = true
L["level %d"] = true
L["|cffffcc55Off by default.|r The game already plays its own fanfare when you level, so this only adds a second copy on top of it. Turn it on if you want /nelevelup previews to make a sound, since those fire no game sound of their own."] = true

-- ============================================================================
-- PROFESSIONS
-- ============================================================================

L["Auctionator API not available for reagent scans."] = true
L["Auctionator scan started for recipe reagents."] = true
L["Open the Auction House first to run Auctionator scans."] = true
L["Requires the Auction House window to be open."] = true
L["Requires: %s"] = true
L["Retail-style crafting window for all professions."] = true
L["Scan AH"] = true
L["Searches Auctionator for the selected recipe and its reagents."] = true

-- ============================================================================
-- SOCIAL
-- ============================================================================

L["Away"] = true
L["Busy"] = true
L["Cancel Extend"] = true
L["Enter a note for %s:"] = true
L["Extend"] = true
L["Extended"] = true
L["ID: %s"] = true
L["Instance"] = true
L["Modern friends window (Friends / Ignore / Who) with a Guild tab."] = true
L["Promote to Assistant"] = true
L["Promote to Raid Leader"] = true
L["Resets In"] = true
L["Set Note"] = true
L["You are not saved to any instances."] = true

-- ============================================================================
-- SPELLBOOK
-- ============================================================================

L["Spellbook"] = true
L["The modern Dragonflight spellbook window. Disable to keep the stock Blizzard spellbook."] = true

-- ============================================================================
-- TALENTS
-- ============================================================================

L["  %s: have %d, build wants %d"] = true
L["%s\n\nImport anyway?"] = true
L["ACTIVE EFFECTS"] = true
L["Activate"] = true
L["Copy this build string (Ctrl+C). Talented & the WoWhead/wotlkdb calculators import it too:"] = true
L["Delete loadout '%s'?"] = true
L["GLYPHS"] = true
L["Glyph options"] = true
L["Glyphs"] = true
L["Import…"] = true
L["Loadouts"] = true
L["Locked"] = true
L["MAJOR GLYPHS"] = true
L["MINOR GLYPHS"] = true
L["NO ACTIVE EFFECTS"] = true
L["Name this imported loadout:"] = true
L["Name this loadout (saves your current spec):"] = true
L["Paste a talent string or calculator URL (Talented / WoWhead / wotlkdb):"] = true
L["Pet"] = true
L["Remove this glyph?"] = true
L["Rename loadout:"] = true
L["Rename specialization"] = true
L["Rename this specialization (letters only, max %d):"] = true
L["Save current spec…"] = true
L["Server uses custom talents"] = true
L["Show glyph effects"] = true
L["Show glyph names"] = true
L["Tags exported builds with this realm so imports onto other layouts warn first."] = true
L["Talents Panel"] = true
L["The modern talents window. Turn off to use the standard Blizzard talent window."] = true
L["This loadout has fewer points in some talents than you've already spent, so it needs a respec first:\n"] = true
L["Toggle slot name labels and the active-effects list."] = true
L["Unlock Spec"] = true
L["\n\nReset at a class trainer, then load again. (The rest has been staged — click Apply to learn it.)"] = true

-- ============================================================================
-- OPTIONS PANEL
-- ============================================================================

L["Adventure Guide (Encounter Journal)"] = true
L["Auction House"] = true
L["Boss and loot browser. Requires a /reload to take effect (the micro button doesn't re-check this live)."] = true
L["Click for this frame's settings."] = true
L["Combined Bag"] = true
L["Custom"] = true
L["Custom scale"] = true
L["Drag to move."] = true
L["Each window's size: \"Use UI scale\" follows the game's UI Scale slider, \"No scaling\" stays pixel-perfect, \"Custom\" uses its slider. The custom slider is greyed out and locked unless that window's mode is set to Custom."] = true
L["Guild"] = true
L["Looking For Group"] = true
L["Looking For Group (Dungeon/Raid Finder)"] = true
L["NewEra panels ported onto DragonUI. Toggle a panel below to enable or disable it. Panels appear here as their modules load."] = true
L["No scaling"] = true
L["Our all-in-one bag window. Turn OFF to use the stock Blizzard bags instead. Reload (/reload) to apply."] = true
L["Professions"] = true
L["Reload (/reload) to apply."] = true
L["Scale mode"] = true
L["Scaling controls are unavailable: the 'core\\Scale.lua' file isn't loaded. Make sure your installed DragonUI_NewEra includes core/Scale.lua AND its line in the .toc, then /reload."] = true
L["Scaling controls need a newer DragonUI options panel (AddSlider/AddDropdown)."] = true
L["Social"] = true
L["Social (Friends/Who/Guild/Chat/Raid)"] = true
L["Use DragonUI's window in place of the Blizzard default. Changes take effect after a /reload."] = true
L["Use UI scale"] = true
L["Window Scaling"] = true
L["Windows"] = true

-- ============================================================================
-- SHARED UI
-- ============================================================================

L["Select All"] = true

-- ============================================================================
-- BOSS TIMERS (modules/bossmods)
-- ============================================================================

L["Boss Timers"] = true
L["Boss Abilities"] = true
L["Boss Warnings"] = true
L["Boss Warning - Critical"] = true
L["Boss Warning - Medium"] = true
L["Boss Warning - Minor"] = true
L["Boss ability timers as a retail-style timeline or bar list. Reads its encounter data from DBM; without DBM installed there is nothing to show."] = true
L["Large on-screen warnings for important boss abilities. Needs DBM and the Boss Timers module."] = true
L["|cffff5555DBM is not installed.|r This module renders boss ability timers, it does not detect them — the encounter data comes from Deadly Boss Mods. Install DBM and reload to use it; the settings below are saved either way."] = true
L["Retail's boss ability timeline, drawn from |cffffcc55DBM's|r timers. Shows as a vertical rail of ability icons sliding toward now, or as a list of depleting bars. |cffffcc55Off by default.|r Drag it with DragonUI's editor mode to reposition it."] = true
L["Enable Boss Timers"] = true
L["Enable Boss Warnings"] = true
L["Off by default. Reload (/reload) to apply."] = true
L["The three large on-screen warning lines. Needs Boss Timers on. Reload (/reload) to apply."] = true
L["Hide DBM's own bars and warnings"] = true
L["On by default, and the reason this does not simply double up on screen. DBM's sounds and voice packs are left alone either way — only what it DRAWS is hidden."] = true
L["The layout settings need a newer DragonUI options panel (AddSlider/AddDropdown)."] = true
L["Appearance"] = true
L["View"] = true
L["Timeline (rail)"] = true
L["Bars"] = true
L["Show the frame"] = true
L["In combat only"] = true
L["Icon size"] = true
L["Rail length"] = true
L["Bar width"] = true
L["Space between bars"] = true
L["Show the countdown"] = true
L["Show the ability name"] = true
L["Timeline view only — the bar list always names its abilities."] = true
L["Warning icon size"] = true
L["Warning opacity"] = true
L["Show a test timer"] = true
L["Runs four sample timers and one warning through the same path a real DBM timer takes, so what you see is what an encounter will look like."] = true
L["Glow when an ability is imminent"] = true
L["On by default. The action-button proc glow, held for the last five seconds before an ability lands. It stands in for a retail effect this client cannot draw; with it off you get only the brief border flash, which is easy to miss."] = true
L["Revert Changes"] = true
L["Reset to Default"] = true
L["Timeline view only. How far out the rail reaches — the icons space themselves along it."] = true
L["Bars view only."] = true
L["Size"] = true
L["Scales the whole frame — the rail, the icons and the text together. Icon Size below scales only the icons."] = true
L["The plate behind the frame. Retail ships it invisible."] = true
L["Scales the whole warning — text and both flanking icons together."] = true
L["The two spell icons either side of the text."] = true
L["Orientation"] = true
L["Vertical"] = true
L["Horizontal"] = true
L["Icon direction"] = true
L["Down / Right"] = true
L["Up / Left"] = true
L["Tooltips"] = true
L["At the cursor"] = true
L["Beside the frame"] = true
L["Off"] = true
L["Flip horizontally"] = true
L["Timeline view only. Which way the rail runs; the icons travel along it either way."] = true
L["Timeline view only. Which end of the rail is |cffffcc55now|r — the end abilities travel toward and go off at."] = true
L["Bars view only. Mirrors each row — the icon moves to the right and the bar drains the other way."] = true
L["Hovering an ability shows its spell tooltip. DBM raises some timers that are not a spell at all — a pull timer, a phase change — and those show their own name instead."] = true
L["Show the ability icons"] = true
L["The two copies of the ability's own icon either side of the text — what retail draws. The text already names the ability, so this is decoration; turn it off for a plain line of text."] = true
