# SRD 5.2.1 Spell Manifest — Source Notes

## Source

- Document: `SRD_CC_v5.2.1.pdf` (6.03 MB, released May 2025)
- Extraction date: 2026-07-11
- Method: page-image OCR via Claude Read tool, cross-checked against per-class spell-list tables

## Page ranges consulted

- **pp. 1–3** — Legal / Table of Contents (confirmed section pagination)
- **pp. 33–34** — Bard Spell List (class-list cross-reference)
- **pp. 38–40** — Cleric Spell List
- **pp. 44–46** — Druid Spell List
- **pp. 55–56** — Paladin Spell List
- **pp. 60–61** — Ranger Spell List
- **pp. 67–69** — Sorcerer Spell List
- **pp. 74–76** — Warlock Spell List
- **pp. 79–82** — Wizard Spell List
- **pp. 104–106** — "Spells" chapter intro (Gaining/Casting Spells, Schools table)
- **pp. 107–175** — Spell Descriptions (A–Z, primary source of truth for name/level/school/classes)
- **p. 176** — Confirmed "Rules Glossary" heading — spell descriptions end here

## Method

The Spell Descriptions section is fully self-sufficient: each spell heading is followed by an italic line of the form `Level N School (Class, Class...)` or `School Cantrip (Class, Class...)`. Every one of the 337 extracted spells parsed unambiguously from that pattern. Where a spell's description spawns a follow-up creature stat block (e.g. Animate Objects → Animated Object, Find Steed → Otherworldly Steed, Summon Dragon → Draconic Spirit, Giant Insect → Giant Insect creature block), the stat block was skipped — it has an AC/HP/Speed line, not a `Level N School` line.

The class parenthetical inside each italic line was treated as the authoritative class list, not the per-class spell-list tables. Rationale: the per-class tables in the SRD are a rearrangement of the same data, and any discrepancy is a printing bug; the per-spell entry is what any player actually references.

## Counts

- **Total: 339 spells**
- L0=27, L1=57, L2=57, L3=42, L4=34, L5=38, L6=31, L7=20, L8=17, L9=16
- Sorted by (level, canonicalName). No duplicates. No spells with an empty class list.

Per-class counts (# of spells that class has access to according to the italic line):

| Class     | Count |
|-----------|-------|
| Wizard    | 218   |
| Sorcerer  | 140   |
| Bard      | 130   |
| Druid     | 124   |
| Cleric    | 109   |
| Warlock   | 72    |
| Ranger    | 48    |
| Paladin   | 38    |

School distribution:

| School        | Count |
|---------------|-------|
| Transmutation | 61    |
| Evocation     | 54    |
| Conjuration   | 54    |
| Abjuration    | 49    |
| Enchantment   | 34    |
| Divination    | 31    |
| Illusion      | 29    |
| Necromancy    | 27    |

The SRD itself does not print a total spell count, so no exact PDF-stated number to reconcile against.

## Confirmed present (previously-flagged 2024 SRD additions)

- **Elementalism** (Level 0 Transmutation; Druid, Sorcerer, Wizard) — present, page 133.
- **Starry Wisp** (Level 0 Evocation; Bard, Druid) — present, page 167.
- **Sorcerous Burst** (Level 0 Evocation; Sorcerer) — present, page 163.
- **Vitriolic Sphere** (Level 4 Evocation; Sorcerer, Wizard) — present, page 173.
- **Summon Dragon** (Level 5 Conjuration; Wizard) — present, page 166.
- **Befuddlement** (Level 8 Enchantment; Bard, Druid, Warlock, Wizard) — present, page 112 (renamed from 2014 "Feeblemind").
- **Power Word Heal** (Level 9 Enchantment; Bard, Cleric) — present, page 155.
- **Arcane Hand** (Level 5 Evocation; Sorcerer, Wizard) — present, page 111 (renamed from 2014 "Bigby's Hand").
- **Hideous Laughter** (Level 1 Enchantment; Bard, Warlock, Wizard) — present, page 140 (renamed from 2014 "Tasha's Hideous Laughter").

## Confirmed ABSENT (previously-flagged 2014-PHB carryovers that must NOT ship)

Searched the entire Spell Descriptions section (pp. 107–175) and the class-list tables — none of the following appear in SRD 5.2.1:

- Thorn Whip
- Thunderclap
- Word of Radiance
- Toll the Dead
- Booming Blade / Green-Flame Blade / Sword Burst (Cantrips from Sword Coast Adventurer's Guide / Tasha's — never SRD)
- Absorb Elements
- Catapult
- Frostbite
- Gust
- Infestation
- Mold Earth / Shape Water / Control Flames / Gust (elemental cantrips) — subsumed by the new "Elementalism" cantrip
- Mind Sliver

These should be treated as content bugs if present anywhere in the app's `Content/` bundle.

## Notable school reassignments vs. 2014 SRD

The 5.2.1 SRD reflects the 2024 rules revision, which reshuffled some school assignments. Preserved as printed in the PDF:

- **Cure Wounds** — Abjuration (was Evocation in 2014).
- **Healing Word / Mass Healing Word / Mass Cure Wounds / Prayer of Healing / Lesser Restoration / Greater Restoration** — Abjuration (all were Evocation or Abjuration variously in 2014; now consistently Abjuration).
- **Divine Favor** — Transmutation (was Evocation).
- **Bless / Bane** — Enchantment (were Enchantment in 2014 too; unchanged).
- **Guiding Bolt** — Evocation (was Evocation in 2014; unchanged, listing for completeness).
- **Continual Flame** — Evocation (was Evocation; unchanged).
- **Blindness/Deafness** — Transmutation (was Necromancy in 2014).
- **Fear** — Illusion (was Illusion; unchanged).
- **Silence** — Illusion (was Illusion; unchanged).
- **Ray of Enfeeblement** — Necromancy (unchanged).
- **False Life** — Necromancy (unchanged).
- **Poison Spray** — Necromancy (was Conjuration in 2014).
- **Chill Touch** — Necromancy (was Necromancy; unchanged, but note this is now a normal cantrip, not the ranged spell attack it once was).

If any downstream code assumes 2014 schools, it will diverge from this manifest by design. Trust the manifest.

## Cross-check: per-class spell-list tables vs. spell-description class parentheticals

The per-class tables (pp. 33–82) list spells by class + level. A separate full extraction of every class-list table was diffed against the manifest. Classes cleric, druid, paladin, ranger, warlock: 100% match between the two sources.

Corrections applied to the manifest as a result of the cross-check:
- **Chill Touch** — original extraction dropped `wizard` from the class list. Confirmed against p. 115: description reads "(Sorcerer, Warlock, Wizard)". Fixed.
- **Mass Suggestion** (Level 6 Enchantment; Bard, Sorcerer, Wizard) — missed entirely in the first extraction pass (skipped between "Mass Healing Word" and "Meld into Stone" on p. 148). Confirmed and added.
- **Maze** (Level 8 Conjuration; Wizard) — missed entirely (also between "Mass Healing Word" and "Meld into Stone" on p. 148). Confirmed and added.

### Known SRD internal inconsistencies (not manifest bugs)

After the corrections above, three per-class-table vs. per-spell-entry mismatches remain, and they are genuine SRD printing inconsistencies rather than extraction errors:

- **Mind Spike (Level 2 Divination)** — the spell's description on p. 149 reads "(Sorcerer, Warlock, Wizard)". The Sorcerer L2 spell-list table on p. 68 omits it. Manifest sides with the description (includes Sorcerer).
- **Phantasmal Force (Level 2 Illusion)** — the spell's description on p. 151 reads "(Bard, Sorcerer, Wizard)". The Bard L2, Sorcerer L2, and Wizard L2 tables all omit it. Manifest sides with the description (Bard, Sorcerer, Wizard).

Rationale for siding with the spell description: the italic line under each spell heading is the SRD's canonical statement of that spell's class list; the per-class tables are a derived rearrangement. A player reading the spell description will see it as available to their class regardless of the table's omission. Downstream code that generates class-specific spell pickers should therefore trust the manifest's `classes` array, not the SRD's per-class tables.

## Anomalies / caveats

- **Alphabetical ordering:** The PDF's column layout occasionally prints headings slightly out of strict alphabetical order (e.g. Irresistible Dance before Invisibility on p. 143; Regenerate before Reincarnate on p. 158). Manifest re-sorts by (level, canonicalName).
- **"Cantrip" == level 0** everywhere. Preserved as level 0 in the manifest.
- **`Blindness/Deafness` and `Enlarge/Reduce` and `Antipathy/Sympathy`** intentionally contain a slash — that's the printed canonical name.
- **`Hunter's Mark` and `Heroes' Feast`** contain apostrophes — preserved.
- **`Arcanist's Magic Aura`** — preserved as printed.
- **No spell had a missing/empty class parenthetical.** All 337 have at least one class.
- **No Artificer entries** appeared anywhere in the PDF. Consistent with the SRD 5.2.1 class inventory (Barbarian, Bard, Cleric, Druid, Fighter, Monk, Paladin, Ranger, Rogue, Sorcerer, Warlock, Wizard — no Artificer).
- **Boundary check across page-chunk extractions:** the alphabetical stitch points (Create Food and Water → Create or Destroy Water, Gaseous Form → Gate, Message → Meteor Swarm, Simulacrum → Sleep) all abut cleanly with no gap and no double-count.

## Flagged for user review

None. Every spell parsed cleanly with a canonical name, level 0–9, one of the eight schools, and at least one class from the SRD's eight spellcasting classes.

The only "close calls" — three spells whose per-class-table listing disagrees with their own description's class parenthetical — are documented above under "Known SRD internal inconsistencies." The manifest sides with the descriptions, which is the authoritative half of that split per the extraction method.
