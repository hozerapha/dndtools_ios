# SRD 5.2.1 Non-Spell Manifest — Source Notes

## Source

- Document: `SRD_CC_v5.2.1.pdf` (6.03 MB)
- Extraction date: 2026-07-11
- Method: page-image reads via Claude's Read tool (`pages` param), transcribed directly from the rendered PDF page images — no content drawn from model memory of PHB/5.1-SRD editions.

## Page ranges consulted

| Manifest | Pages | Section(s) |
|---|---|---|
| `species.json` | 84–86 | "Character Species" (Species Descriptions) |
| `backgrounds.json` | 83–84 | "Character Backgrounds" (Background Descriptions) |
| `feats.json` | 87–88 | "Feats" (Feat Descriptions) |
| `conditions.json` | 176–191 | "Rules Glossary" (alphabetical `[Condition]`-tagged entries) |
| `weapons.json` | 89–91 | "Equipment" → Weapons (Properties, Mastery Properties, Weapons table) |
| `armor.json` | 92 | "Equipment" → Armor table |
| `gear.json` | 93–100, 209–253 | "Equipment" → Tools + Adventuring Gear tables; "Magic Items A–Z" |

TOC cross-check pages 1–6 were read first to locate every section's starting page and confirm no offset between printed page numbers and PDF page indices (they match 1:1 from page 2 onward).

## species.json (9 entries)

Table of contents lists exactly 9 species under "Character Species": Dragonborn, Dwarf, Elf, Gnome, Goliath, Halfling, Human, Orc, Tiefling. Matches the count already known from the project's SRD-compliance audit (9 species incl. Goliath, not Goblin). Each species' "Special Traits" list was read verbatim; trait names are the bold sub-headers under "As a [Species], you have these special traits."

**Confidence: high.** All 9 read directly from pp. 84–86 with full trait text.

## backgrounds.json (4 entries)

Only 4 backgrounds exist in the SRD: Acolyte, Criminal, Sage, Soldier (confirmed by TOC and by reading pp. 83–84 in full — no other background headers appear before "Character Species" begins). Matches the project's known compliance finding (only 4 backgrounds bundled/SRD-legal).

Each entry's Ability Scores / Feat / Skill Proficiencies / Tool Proficiency / Equipment (A or B) lines were read directly from the background's stat block. `equipmentB` is 50 (GP) for every background — SRD phrasing is uniformly "Choose A or B: (A) [items]; or (B) 50 GP."

**Confidence: high.**

## conditions.json (15 entries)

The Rules Glossary itself lists the canonical roster on p. 179 under the "Condition" glossary entry: Blinded, Charmed, Deafened, Exhaustion, Frightened, Grappled, Incapacitated, Invisible, Paralyzed, Petrified, Poisoned, Prone, Restrained, Stunned, Unconscious — exactly 15. Each condition's own `[Condition]`-tagged glossary entry (scattered alphabetically across pp. 177–191) was read and its bold sub-headers converted to `"Label: description"` bullet strings, one bullet per bold sub-header, preserving the SRD's own effect breakdown rather than inventing a bullet count.

**Confidence: high.** All 15 read directly; none inferred.

## weapons.json (38 entries)

Full "Weapons" table (p. 91) transcribed row-by-row: 10 Simple Melee, 4 Simple Ranged, 18 Martial Melee, 6 Martial Ranged = 38 total. Properties and Mastery columns copied verbatim per row; property definitions (Ammunition, Finesse, Heavy, Light, Loading, Range, Reach, Thrown, Two-Handed, Versatile) and the 8 Mastery properties (Cleave, Graze, Nick, Push, Sap, Slow, Topple, Vex) were cross-read from pp. 89–90 to confirm naming and that the SRD does indeed assign exactly one mastery property per weapon (confirmed — no weapon lacks one, none has two).

**Confidence: high.**

## armor.json (13 entries)

Full "Armor" table (p. 92) transcribed row-by-row: 3 Light, 5 Medium, 4 Heavy, 1 Shield = 13 total. `dexMod` derived from the table's AC column phrasing: "11 + Dex modifier" (no cap) → `"full"`; "12 + Dex modifier (max 2)" → `"capped:2"`; flat AC values (Ring Mail 14, Chain Mail 16, Splint 17, Plate 18) and Shield → `"none"`. Strength requirement column only populated for Chain Mail (13) and Splint/Plate (15); all others `null`.

**Confidence: high.**

## feats.json (17 entries)

**Important finding, flagged for user review:** The SRD 5.2.1 does **not** include the full PHB feat roster. Reading pp. 87–88 in full (start of "Feats" through the last entry before "Equipment" begins on p. 89) turned up only:

- **Origin Feats (4 of the PHB's 8):** Alert, Magic Initiate, Savage Attacker, Skilled. **Missing from the SRD: Lucky, Musician, Tavern Brawler, Tough.** This lines up exactly with which origin feats the SRD's own Backgrounds/Species text references (Acolyte/Sage → Magic Initiate, Criminal → Alert, Soldier → Savage Attacker, Human's Versatile trait recommends Skilled) — the SRD appears to only license the origin feats it actually needs elsewhere in its own text.
- **General Feats (2 total):** Ability Score Improvement, Grappler. No Athlete/Chef/Crusher/Durable/Great Weapon Master/etc.
- **Fighting Style Feats (4 total):** Archery, Defense, Great Weapon Fighting, Two-Weapon Fighting. No Blind Fighting/Dueling/Interception/Protection/Thrown Weapon Fighting/Unarmed Fighting.
- **Epic Boon Feats (7 total):** Boon of Combat Prowess, Boon of Dimensional Travel, Boon of Fate, Boon of Irresistible Offense, Boon of Spell Recall, Boon of the Night Spirit, Boon of Truesight. No Boon of Energy Resistance/Fortitude/Invulnerability/Speed/the Unfettered/Undetectability.

This gives 4 + 2 + 4 + 7 = **17 feats total**, confirmed by reading every line of pp. 87–88 (the section runs out exactly at the page break before "Equipment"). **This is a hard SRD boundary, not an extraction gap** — do not backfill the "missing" feats from memory; they are not CC-BY licensed in this document.

`abilityScoreImprovement: ["Any"]` is a manifest-local convention (not literal SRD text) used where the feat's Ability Score Increase lets you pick any ability — flagging this so the lint test author knows `"Any"` is a sentinel, not a literal SRD ability name.

**Confidence: high on the 17 entries read; the "missing" feats are a confirmed SRD omission, not something to fix.**

## gear.json (390 entries: 91 adventuring, 37 tool, 262 magic_item)

Extracted by a sub-agent from pp. 93–100 (Tools + Adventuring Gear tables) and pp. 209–253 (Magic Items A–Z), per the same PDF-only rule. Both magic items ROLLodex currently bundles were confirmed present: **Potion of Healing** (p. 236, base/greater/superior/supreme rarity tiers) and **Wand of Magic Missiles** (p. 251, Uncommon, 7 charges).

Notable decisions (flagged for user review):

- **Potion of Healing** and **Spell Scroll (Cantrip/Level 1)** appear in the Adventuring Gear table with GP costs but are true magic items per their prose entries — categorized as `magic_item`, not `adventuring`, to avoid a duplicate row under two categories. **User review needed** if the lint test expects them under `adventuring` instead because that's the table they're priced in.
- 252 of 262 magic items have no GP cost or weight printed in the SRD text (`cost:""`, `weight:0.0`) — this is expected per SRD convention (Equipment's "Magic Items" intro says magic item prices are handled separately/by rarity, not itemized per-item in most entries), not a missed extraction. 10 items had explicit prose weights and those were captured (Apparatus of the Crab, Bag of Holding, Chime of Opening, Decanter of Endless Water, Folding Boat, Handy Haversack, Iron Bands, Marvelous Pigments, Mirror of Life Trapping, Stone of Controlling Earth Elementals).
- Multi-variant items with one headline name but a rarity/strength sub-table (Belt of Giant Strength, Ioun Stone, Horn of Valhalla, Potion of Giant Strength, Feather Token, Figurine of Wondrous Power, Bag of Tricks) were kept as **one** canonical entry each rather than exploded into sub-variants — matches how the SRD headlines them.
- "Gaming Set" and "Musical Instrument" generic wrapper rows were skipped (their table cost is "Varies", not a real GP unit); their individually-priced variants were captured as standalone `tool` entries instead (Dice Set, Dragonchess Set, Playing Card Set, Three-Dragon Ante Set; Bagpipes, Drum, Dulcimer, Flute, Horn, Lute, Lyre, Pan Flute, Shawm, Viol).
- Arcane Focus / Druidic Focus / Holy Symbol sub-table variants (Crystal, Orb, Rod, Staff, Wand / Sprig of Mistletoe, Wooden Staff, Yew Wand / Amulet, Emblem, Reliquary) were captured as individual `adventuring` entries. "Staff (Arcane Focus)" and "Wand (Arcane Focus)" are named to disambiguate from the many "Staff of X" / "Wand of X" magic items.
- Excluded two monster stat-block references that appear inside magic item prose (Avatar of Death, Giant Fly) — not items themselves.

**Confidence: high on presence/absence of the two bundled items; medium on the exact category split for Potion of Healing / Spell Scroll — flagged above for user/lint-author decision.**

## Overall counts

```
species=9 backgrounds=4 conditions=15 weapons=38 armor=13 gear=390 feats=17
```

## Callouts requiring user review

1. **Feats: SRD 5.2.1 only licenses 17 of the PHB's ~29 feats.** Lint tests must not expect Lucky, Musician, Tavern Brawler, Tough (origin); the ~13 other general feats (Athlete, Chef, Crusher, Defensive Duelist, Dual Wielder, Durable, Elemental Adept, Great Weapon Master, Healer, Heavily/Lightly/Moderately Armored, Inspiring Leader, Keen Mind, Mage Slayer, Martial Weapon Training, Piercer, Poisoner, Ritual Caster, Shield Master, Skill Expert, Slasher, Speedy, Telekinetic, Telepathic, War Caster, Weapon Master); Blind Fighting/Dueling/Interception/Protection/Thrown Weapon Fighting/Unarmed Fighting (fighting style); or the other ~6 Epic Boons — none of those are SRD-legal content and must not be bundled even if they're common D&D knowledge.
2. **gear.json: Potion of Healing and Spell Scroll categorization** (`magic_item` vs `adventuring`) — decide which category the lint test should check against; both are valid readings of the source.
3. **gear.json: multi-variant items kept singular** (Belt of Giant Strength, Ioun Stone, etc.) — if ROLLodex needs per-variant strength/rarity tiers as separate bundled items, this manifest will need a follow-up pass to explode those tables.
