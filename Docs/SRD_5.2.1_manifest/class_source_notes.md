# SRD 5.2.1 Classes/Subclasses Manifest — Source Notes

Source: `/Users/josecolina/Downloads/SRD_CC_v5.2.1.pdf` (labeled page numbers == PDF page numbers, offset 0 — verified against page 1 "Legal Information" and page 2 "Contents").

Extraction was done by reading each class's per-level features table and its "Class Features" prose section directly from the PDF (not from model memory). Every entry in `classes.json` / `subclasses.json` traces to a specific page below.

## Page ranges per class

| Class | Core traits + features table | Feature prose | Subclass |
|---|---|---|---|
| Barbarian | 28 | 28–30 | Path of the Berserker: 30 |
| Bard | 31 | 31–34 | College of Lore: 34–35 |
| Cleric | 36 | 36–38 | Life Domain: 38–40 |
| Druid | 41 | 41–43 | Circle of the Land: 46 |
| Fighter | 47 | 47–49 | Champion: 49 |
| Monk | 49–50 | 50–52 | Warrior of the Open Hand: 52 |
| Paladin | 53 | 53–55 | Oath of Devotion: 56 |
| Ranger | 57–58 | 58–59 | Hunter: 61 |
| Rogue | 61–62 | 62–63 | Thief: 64 |
| Sorcerer | 64–65 | 65–66 | Draconic Sorcery: 69–70 |
| Warlock | 70 | 71–72 | Fiend Patron: 76 |
| Wizard | 77 | 77–79, 82 | Evoker: 82 |

(Metamagic Options, Eldritch Invocation Options, and the spell lists between the base class and subclass sections were skipped — not needed for this manifest.)

## Method notes / judgment calls

1. **"Subclass feature" placeholder rows.** Each base class's per-level table has generic `Subclass feature` rows (e.g. Barbarian L6/10/14) marking levels where the chosen subclass grants a feature. These are NOT named class features — I skipped them in `classes.json`. The actual named features at those levels live in `subclasses.json` instead. I cross-checked that every "Subclass feature" table slot has a matching subclass feature at that level (all 12 checked out).

2. **Recurring same-named features.** Where the per-level table literally repeats a feature name at a later level with an incremented effect (e.g. Barbarian "Improved Brutal Strike" at both L13 and L17, each with its own `Level N: Improved Brutal Strike` prose header and distinct effect text), I recorded both level entries. Confirmed cases: Barbarian Improved Brutal Strike (13, 17), Bard/Rogue Expertise (increases at a second level), Fighter Indomitable (9, 13, 17 — table annotates "(one/two/three uses)" but I verified the level-9 prose header is the sole source of the uses text, so I still recorded three table rows since the table itself lists the name three times), Fighter Action Surge (2, 17), Warlock Mystic Arcanum (11, 13, 15, 17 — table annotates spell-level unlocked; kept the name without the parenthetical spell-level tag).

3. **Ability Score Improvement (ASI) levels.** Verified per class rather than assumed:
   - Barbarian, Bard, Cleric, Druid, Monk, Paladin, Ranger, Sorcerer, Warlock, Wizard: 4, 8, 12, 16 (+ Epic Boon at 19).
   - Fighter: 4, 6, 8, 12, 14, 16 (+ Epic Boon 19) — two extra ASIs vs. the standard pattern, matching the CLAUDE.md hint.
   - Rogue: 4, 8, 10, 12, 16 (+ Epic Boon 19) — one extra ASI at 10, matching the hint.
   - Epic Boon (L19) is recorded as its own feature per the task's rule ("the ASI IS the mechanism to pick an Epic Boon"); no separate Epic Boon feat names were recorded.

4. **`primaryAbility` for dual-ability classes.** The SRD's Core Traits table sometimes lists two abilities joined by "and" (both required) and once by "or" (either works). I encoded these as an array plus a `primaryAbilityCombinator` field (not in the original prompt's schema, but needed to stay faithful to the source — flagging for review):
   - `"strength or dexterity"` → Fighter, combinator `"or"`.
   - `"dexterity and wisdom"` → Monk, Ranger; `"strength and charisma"` → Paladin — combinator `"and"`.
   - All other classes have a single primary ability and are encoded as a plain string, matching the example in the task prompt.

5. **`toolProficiencies` and restricted `weaponProficiencies`.** Where the SRD names a specific tool category with a "choose N" clause (Bard: 3 Musical Instruments; Monk: 1 Artisan's Tools or Musical Instrument) I kept the descriptive phrase as a single string rather than inventing an enum, since no tool-proficiency vocabulary was specified in the task schema. Where weapon proficiency is qualified by a weapon property (Monk: Martial weapons with the Light property only; Rogue: Martial weapons with the Finesse or Light property), I appended the qualifier in parentheses to the `"martial"` entry rather than dropping it — dropping it would overstate what these classes can use.

6. **Spellcasting fields.**
   - `cantripsAtL1: null` for Paladin and Ranger — confirmed by checking their Features tables have no "Cantrips" column (half-casters in 5.2.1 don't get cantrips).
   - `spellsKnownAtL1: null` for every caster — 5.2.1 uses "Prepared Spells" counts (a level-scaling table column) for every class except none use a fixed "spells known" list distinct from prepared count, so this field is null across the board. The `preparedSpells` count at L1 (from the tables) is: Bard 4, Cleric 4, Druid 4, Paladin 2, Ranger 2, Sorcerer 2, Warlock 2, Wizard 4 — not captured in this schema since it wasn't requested, but noted here in case it's useful later.
   - `preparedRule`: `"preparedFromAll"` for Bard, Cleric, Druid, Paladin, Ranger, Sorcerer (choose freely from the full class spell list each time the prepared list changes); `"preparedFromBook"` for Wizard (spells must be in the wizard's spellbook); `"pactMagic"` for Warlock.
   - Warlock is the only `casterType: "pact"`; no `"third"` casters exist among the 12 base classes in the 5.2.1 SRD (Eldritch Knight / Arcane Trickster equivalents are absent — see callout below).

7. **Subclass-granted features at the subclass's chosen level (L3).** Every subclass grants 2 named features at L3 (the level the subclass itself is chosen), even though the base class table only marks L3 as `"[Class] Subclass"` (the choice itself), not a `"Subclass feature"` slot. This is intentional — subclass selection at L3 always comes bundled with that subclass's L3 features in the SRD's presentation.

## Cross-checks performed

- All 12 classes have `subclassLevel: 3`, verified from each class's own features table (`"3: [Class] Subclass"` row).
- All 12 SRD 5.2.1 subclasses matched exactly against the task's expected list (name + parent class) — no mismatches found.
- Every base-class `"Subclass feature"` table slot has a corresponding subclass feature at that exact level (checked class-by-class); no orphaned slots or missing subclass features.
- Total counts (verified programmatically against the written JSON): **12 classes, 12 subclasses, 223 class-level features + 57 subclass-level features = 280 total features.**

## Callouts (things a future PHB-drift auditor should know)

- **No "third-caster" subclasses in the SRD 5.2.1 core 12.** Eldritch Knight (Fighter) and Arcane Trickster (Rogue) — both `"third"` casters in the 2014/2024 PHB — are **not present** in this SRD; each of those two classes gets only their one SRD subclass (Champion, Thief). If the bundled `classes.json`/`subclasses.json` in `ROLLodex/` contains Eldritch Knight or Arcane Trickster, that is 2024-PHB content absent from the SRD and should be flagged for removal or clearly marked non-SRD homebrew.
- **Weapon Mastery is a 2024-only mechanic** present at L1 for Barbarian, Fighter, Paladin, Ranger, Rogue in this SRD — if the bundle's Barbarian/Fighter/etc. lack a "Weapon Mastery" L1 feature, that's a gap versus this source of truth (not a PHB-drift issue, just worth flagging for consistency).
- I did not check the currently-bundled `ROLLodex/` catalog against this manifest — that comparison was explicitly out of scope for this task.
