# Character Panel — Visual Spec (THE build target)

**Mandate: match `/root/downport/DOWNPORT THIS/NewEra/CharacterPanel/` EXACTLY.** Port NewEra's
actual geometry/decoration logic faithfully into our custom frame (`DragonUI_NewEra_Character`,
Blizzard CharacterFrame hidden, slots+model reparented). When in doubt, read the NewEra source value
and replicate it. The whole window ships as ONE deliverable.

## Container layout (the key DF shift vs vanilla)
NOT "spread slots to frame edges." It's a CONTAINER design: a FIXED-width left content area (model +
tight slot columns + gold inner border) and a COLLAPSIBLE right stats sidebar.

```
┌──────────────────────────────────────────────────────────┐
 (○ class icon)      C H A R A C T E R            [✕]
├──────────────────────────────────────────────────────────┤
│ ┌─ Inset (FIXED 338w) ────────────┐ │ ┌ InsetRight 209w ┐ │
│ │ [Head]   ⟲ ⟳ controls   [Hands] │ │ │ (face)(T)(equip)│ │  sidebar tabs
│ │ [Neck]  ┌──────────────┐ [Waist] │ │ ├─────────────────┤ │
│ │ [Shldr] │ Model 231×320│ [Legs]  │ │ │ General      ▾  │ │
│ │ [Back]  │ (race bg,    │ [Feet]  │ │ │ Attributes   ▾  │ │
│ │ [Chest] │  desaturated)│ [Ring1] │ │ │ Melee        ▾  │ │  7 scrollable
│ │ [Shirt] │              │ [Ring2] │ │ │ Ranged       ▾  │ │  stat sections
│ │ [Tabrd] └──gold border─┘ [Trk1]  │ │ │ Spell        ▾  │ │
│ │ [Wrist]   [MH][OH][Rng]  [Trk2]  │ │ │ Defense      ▾  │ │
│ └──────────(gold inner border)─────┘ │ │ Resistances  ▾  │ │
├──────────────────────────────────────────────────────────┤
│ [Character] [Pet] [Skills] [Honor] [Reputation]            │  metal DF tabs
└──────────────────────────────────────────────────────────┘
  338w collapsed  →  548w when sidebar expanded
```

## Geometry (from NewEra source — replicate)
| Region | Size | Anchor / offset |
|---|---|---|
| Frame | 338×424 collapsed / 548×424 expanded | center; width grows when sidebar shown |
| Inset (left content) | **FIXED 338×364** | TOPLEFT(4,−60) of Frame |
| InsetRight (sidebar host) | 209×364 | TOPLEFT(1,0) off Inset.TOPRIGHT; shown only when expanded |
| Model viewport | 231×320 | (52,−66) within the paperdoll area; race 4-part bg, desaturated + dark overlay |
| Model controls | 132×32, 5 btns (zoom±, rotate L/R, reset) | TOP(0,−4) of model; hover-reveal, alpha 0.5 |
| Left slot column (8) | slots ~37px + 49×44 metal frame each | Head at Inset.TOPLEFT(4,−2), chain down: Head,Neck,Shoulder,Back,Chest,Shirt,Tabard,Wrist |
| Right slot column (8) | slots + 50×44 metal frame each | Hands at Inset.TOPRIGHT(−4,−2), chain down: Hands,Waist,Legs,Feet,Finger0,Finger1,Trinket0,Trinket1 |
| Bottom weapon row (3) | slots + 42×53 frame + gap fillers | MainHand at Frame.BOTTOMLEFT(84,24): MainHand,SecondaryHand,Ranged |
| Inner border | 7×7 gold corners + 5px edges + full-width divider 27px above bottom | around the model/slot viewport (Char-Paperdoll-Parts art) |
| Portrait | 62×62 circular | TOPLEFT(−5,7); CLASS icon (FDID 1662186), never the 3D face |
| Title | metal strip, text centered | top band |
| Stats pane (NE_CharacterStatsPane) | 197w, scrollable | InsetRight.TOPLEFT(3,−3); class-themed bg (197×355, ui-character-info-<class>-bg) |
| Stat row | 187×15, alternating bounce bg | chained; sections: General,Attributes,Melee,Ranged,Spell,Defense,Resistances |
| Sidebar tabs | 168×35 strip, 3 tabs 33×35 | above InsetRight: face / titles(disabled) / equipment |
| Bottom tabs | metal atlas, 36h inactive / 42h active, 1px gap | below frame: Character,Pet,Skills,Honor,Reputation; active raised frame level |

## Slot/model positioning rule
NewEra keeps slots at vanilla CharacterFrame positions and DECORATES them. We reparent into our Inset,
so REPLICATE the 3.3.5 vanilla `PaperDollFrame.xml` slot+model anchors (read
`/root/wow_interface/Interface/FrameXML/PaperDollFrame.xml`) so they land exactly where NewEra shows
them, then overlay NewEra's metal slot-frame decorations. The Inset is sized like the vanilla
paperdoll area so vanilla anchors translate directly.

## 3.3.5 adaptations (already decided)
- Sidebar/secondary-tab scroll: NewEra uses WowScrollBox (absent on 3.3.5) → **named FauxScrollFrame**
  + manual row pool. Bounded rows; non-virtualized is fine.
- Portrait = class icon (no spec system on 3.3.5).
- Equipment manager: 3.3.5 GLOBAL equip funcs via a `compat/C_EquipmentSet.lua` shim; ItemRack-model
  fallback.
- Gotchas: CreateMaskTexture returns nil (guard return), SetNormalTexture takes a path, raise child
  frame levels, no SetShown, named FauxScrollFrame, pcall stat getters.

Build to THIS. Faithful to NewEra is the acceptance bar.
