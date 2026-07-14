# Manual QA Checklist

In-app test cases to run on the Simulator. The automated suite (`⌘U`) covers
pure logic; this doc covers the things only a running build reveals — tab
gating, navigation, picker wiring, sheet behavior, persistence across
relaunch. Several bugs we've shipped were invisible to unit tests and only
showed up here (the Spells tab being hidden for non-casters, species choices
not surfacing at creation), which is why this list exists.

## Regression watches

- [ ] **Legacy character roster survives (2026-07-13 backfill).** After
  installing a build that includes this line, launch the app. Every
  character you'd created before 2026-07-12 should still appear on the
  roster, with correct ability scores, HP, class, etc. If the roster is
  empty but `Documents/Characters/*.json` (on the sim, via the file browser)
  still contains files, this test failed — the recovery scan should have
  re-attached them; the fallback decoder should have accepted their legacy
  `abilityScores` array shape. Once loaded, editing any field will re-save
  in the current object shape; both shapes decode indefinitely, so no
  further action needed.

## How to use
- Each feature area has a list of concrete, step-by-step cases with a checkbox.
- Status: `[ ]` not yet verified · `[x]` verified · `[~]` partial / known issue
  (leave a `— note:` after the case explaining what's off).
- Check boxes off as you test. It's fine to defer testing — the unchecked
  boxes are your worklist when you next sit down.
- **Claude updates this file whenever a user-facing feature is added or
  changed** (see CLAUDE.md), adding new cases as `[ ]` and re-opening boxes
  for cases whose behavior changed. Claude does not check boxes — verification
  is yours.

> **Recently changed — needs verification:** the **Ranger** class + Hunter
> (2026-07-06, new — see "Ranger" under Classes) — **the class catalog is
> now complete (12/12 classes, 12/12 subclasses)** and this pass also shipped
> a prep-cap fix so Bard/Sorcerer/Ranger are gated by their `spellsKnown`
> table instead of ability mod; the **Monk** class + Warrior of the Open Hand
> (2026-07-06, new — see "Monk" under Classes; shared Focus pool, scaling
> Martial Arts die, unarmored speed bonus, and an unarmed-strike proficiency
> fix that affects every class); the **Warlock** class + Fiend Patron
> (2026-07-02, new — see "Warlock" under Classes; first pact-magic caster +
> Eldritch Blast) and the **subclass backfill** — Path of the Berserker, Oath
> of Devotion, Evoker (2026-07-02, new — see "Subclass backfill" under
> Classes); the **Settings page + Natural 20
> crit styles** (2026-06-27, new — see "Settings & critical-hit styles"); the
> **QA P0 quick batch**
> (2026-06-27, mostly covered by unit tests — see "QA fixes" below); the
> **Sorcerer** class + mechanics pass (Unarmored Defense, feature HP, granted
> subclass spells, Innate Sorcery), which also fixed **Barbarian Unarmored
> Defense** and **Dwarven Toughness**; the **Bard** class (2026-06-17); and the
> Species epoch.

---

## Character creation

- [ ] **Full happy path.** Create a character end to end (name → species →
  background → class → skills → abilities → review → save). It appears in the
  character list and opens to a populated sheet.
- [ ] **Debug autofill (DEBUG builds).** On the Ability Scores step, tap
  "Autofill (debug)". All six scores fill and the origin (background) bonus is
  assigned; "Next" becomes enabled immediately. Works on Point Buy, Array, and
  Roll methods.
- [ ] **Species with no choices skip the choices step.** Creating a Human /
  Dwarf / Halfling / Orc goes straight from Species to Background (no extra
  step).
- [ ] **Species with choices stop for them.** Creating a Dragonborn / Elf /
  Gnome / Goliath / Tiefling shows a "<Species> Traits" step after Species.
- [ ] **Picks persist onto the new character.** Pick Red Dragon (Dragonborn)
  at creation → open the sheet → the Breath Weapon is already fire-typed
  without visiting the Features tab.
- [ ] **Switching species clears stale picks.** Choose Tiefling, pick a
  legacy, go back, switch to Dragonborn → the Tiefling legacy pick is gone
  (no leftover selection).
- [ ] **Choices are optional.** Skip a species choice at creation, finish, then
  set it later on the Features tab — it takes effect.

## Species traits & choices (Features tab)

- [ ] **Lineage/ancestry/legacy pickers are editable post-creation.** On an
  existing Dragonborn/Elf/Gnome/Goliath/Tiefling, the Features tab shows the
  ancestry/lineage/legacy picker and the "Innate Spellcasting" ability picker;
  changing them updates the sheet.
- [ ] **Breath Weapon (Dragonborn).** Actions tab shows "Breath Weapon" as an
  Action that rolls 1d10 at L1–4, **scaling** to 2d10 (L5), 3d10 (L11), 4d10
  (L17). The damage type matches the chosen ancestry (Red→fire, White→cold,
  Green→poison, …); untyped only if no ancestry is chosen. Has a Proficiency-
  Bonus use counter.
- [ ] **Stonecunning (Dwarf).** Surfaces as a usable **Bonus Action** with a
  PB-uses counter (5.2.1 tremorsense wording), not a passive line.
- [ ] **Adrenaline Rush (Orc) / Large Form (Goliath L5).** Each surfaces as a
  Bonus Action with its own use counter.
- [ ] **Passive traits stay text-only.** Relentless Endurance, Powerful Build,
  Brave, Luck, etc. show on the Features tab with no action row.

## Spells & granted spells

- [ ] **Class/subclass grants cast from normal slots, not a free-cast pool
  (2026-07-13).** Cast a Druid Circle-of-the-Land Circle Spell (Burning Hands
  under Arid at L3, say). The cast sheet should show only the slot picker —
  **no "Cast free (Innate)"** card, since Circle Spells don't have a free-cast
  pool. Picking L3 in the slot picker + tapping Roll Damage should scale to
  5d6 fire and consume a L3 druid slot. Regression check: a Tiefling Fighter's
  Hellish Rebuke at L3+ should still show its Cast free (Innate) card because
  the species grant DOES have a per-Long-Rest pool.
- [ ] **Level-up "pending picks" banner no longer flags unlocks-at-new-level
  (2026-07-13).** L3 Druid with all Features-tab picks filled (skills,
  Primal Order, Subclass, Circle Type). Open Level Up (going to L4). Banner
  says **0 pending**, not "1 pending" — the L4 ASI, which unlocks AT L4,
  isn't counted because the character couldn't have picked it yet. Same
  Druid, L4 → L5 with the L4 ASI still partly distributed (say 1 of 2
  points spent) → banner says **1 pending** (that's the leftover ASI point).
  Multiclass-add exception: adding Fighter as a NEW class at L1 still
  counts Fighting Style etc. as pending so the player is nudged toward it
  after finishing.
- [ ] **Filled selection features look calm (2026-07-13).** In the Features
  tab, a Primal Order card with Magician picked now uses a **secondary /
  gray** tint on the header badge ("Selected"), the check icon, and the
  Change button — same visual weight as a passive feature like Druidcraft.
  A brand-new selection with nothing picked still shows in **orange** with
  the checklist icon so the eye lands on it. Same for Subclass, Fighting
  Style, Metamagic, Weapon Mastery, ASI once distributed. The green picked-
  option summary (option name + description) stays visible under the
  header, and the Change button still opens the picker.
- [ ] **Upcast damage now wired on 4 previously text-only spells
  (2026-07-13).** Cast each at a higher-than-base slot and confirm the
  damage scales:
  - **Ray of Sickness** (L1 → +1d8 poison per slot above 1st) — recipeIndex
    1 (the damage, not the attack)
  - **Chromatic Orb** (L1 → +1d8 per slot above 1st)
  - **Hellish Rebuke** (L1 → +1d10 per slot above 1st)
  - **Dragon's Breath** (L2 → +1d6 per slot above 2nd)
  Scorching Ray (adds an extra ray per slot), Geas (duration extends), and
  Chain Lightning (extra bolt-targets) intentionally stay text-only —
  those are engine-gap shapes we haven't wired.
- [ ] **Follow-up chips PERSIST until each is fired (2026-07-13).** Cast
  Ice Knife → attack → dice tab shows two chips (piercing 1d10, cold 2d6).
  Tap **piercing** → roll — result is 1d10 piercing AND the cold chip
  **stays visible** for the next roll. Now tap **cold** → 2d6 rolled → the
  cold chip disappears. On a miss (Nat 1 or otherwise), the whole rail
  suppresses per the existing Nat-1 behavior. Regression: single-follow-up
  spells (Fire Bolt → damage chain) still hide the sole chip once fired.
- [ ] **Ice Knife chains BOTH damage rolls after the attack (2026-07-13).**
  Cast Ice Knife. Sheet shows three roll buttons: Roll Spell Attack, Roll
  Damage (1d10 piercing, "Ice Knife (Piercing)"), Roll Damage (2d6 cold,
  "Ice Knife (Explosion)"). Tap Roll Spell Attack — sheet dismisses to dice
  tab, which shows the attack roll plus **two follow-up chips**: one for the
  piercing, one for the cold explosion. Both remain tappable so the player
  rolls piercing (if hit; honor-system) and cold (always). Cast at L2 slot
  → cold chip scales to 3d6, piercing stays 1d10 (upcast recipeIndex 2 only).
  Regression check: Fire Bolt (attack + 1 damage recipe) still emits exactly
  one chip after the attack.
- [ ] **Spell description updates dice for the selected slot level
  (2026-07-13).** On a caster with Fireball prepared, open the cast sheet.
  Base description reads "…**8d6** Fire damage on a failed save…" with 8d6
  bolded (L3 base). Tap L4 in the slot picker — the description updates to
  "…**9d6** Fire damage…" (still bolded). L5 → 10d6, etc. Same on Cure
  Wounds: base "**2d8** Hit Points" (L1), scaled to "**4d8**" at L2, "6d8"
  at L3, etc. Spells where the description text doesn't reference the
  recipe's exact dice string (e.g. Magic Missile mentions "1d4+1 per dart"
  but the recipe is a compound formula) leave the description alone — the
  RollButton subtitle below still shows the full scaled formula so the
  player has the exact roll.
- [ ] **Granted spells merge into their level sections with a source tag
  (2026-07-13).** The "Granted" section is gone. On the Druid from the
  Circle-of-the-Land case: at L3 with Temperate, Misty Step and Shocking
  Grasp show inside the **Cantrips / 1st Level / 2nd Level** groups the
  same way prepared spells do, each carrying a small blue **Circle of the
  Land** capsule at the right edge. Non-caster with grants still works: a
  Tiefling Fighter shows Fire Bolt / Thaumaturgy under **Cantrips** with a
  **Fiendish Legacy** tag. **Long-pressing a granted row does NOT show a
  Forget option** — granted spells are always-prepared from the feature and
  can only go away by changing the feature pick. A spell that is both
  prepared AND granted (edge case) shows once, with the grant tag winning.
- [ ] **Circle of the Land — Circle Spells granted per land (2026-07-13).**
  Level a Druid to 3, pick Circle of the Land, pick **Temperate**. The
  Spells tab should now show a **Granted** section with Misty Step, Shocking
  Grasp, and Sleep (source: "Circle of the Land"). Level to 5 → Lightning
  Bolt joins. L7 → Freedom of Movement. L9 → Tree Stride. Swapping the land
  pick (e.g. to Arid) atomically swaps the whole granted list to Blur /
  Burning Hands / Fire Bolt at L3, plus the level-gated adds (Fireball L5,
  Blight L7, Wall of Stone L9). Every land's spell IDs already exist in the
  bundle — no missing content. Known cosmetic gap: the SRD writeup says
  "Druid levels 3/5/7/9" but the current gate uses CHARACTER level, so a
  Druid 3 / Fighter 2 (character L5) would see Fireball prematurely.
  Single-class Druid — the intended target — is correct.
- [ ] **Primal Order Magician wires WIS → Arcana / Nature (2026-07-13).**
  Create a Druid at L1, WIS 16 (mod +3), INT 10 (mod +0). Open Features tab,
  Primal Order, pick **Magician**. Return to the Abilities tab. Arcana and
  Nature rows should now show a small blue **+3 feat** tag beside the ability
  abbreviation and the modifier itself should include the +3 (an INT-10
  Druid with no Arcana proficiency previously read Arcana +0; now reads +3
  with the "+3 feat" tag). Rolling from either row produces "1d20 + INT
  (skill) — incl. +3 feature bonus". Other skills stay unchanged. Switching
  the pick to **Warden** clears the tags; toggling back restores them.
- [ ] **Selected feature option visible in the Features tab (2026-07-13).**
  On the same Druid, open Features tab. The Primal Order card now shows a
  green-tinted row under the description with **the picked option name and
  description** (e.g. "Magician — One extra Druid cantrip; add WIS to
  Arcana and Nature checks."), so you can read what your choice does without
  opening the picker. The action button below now says **Change** once
  something is picked (was: the full prompt). Same treatment for other
  fixedOptions selections (Fighting Style, Metamagic) and for subclass
  pickers (the picked subclass's name + description appears on the
  subclass-picker feature).
- [ ] **Spell info affordance in the picker (2026-07-13).** Open **Add Spell**
  (Learn / Prepare / Manage). Every row has a small ⓘ on the leading edge —
  tapping it opens a **SpellDetailSheet** with school + level, casting time,
  range, duration, components (with material text if any), full description,
  higher-level scaling block, and class list. Tapping the row body still
  toggles prepared/known as before. **The main character-sheet spell list
  intentionally does NOT get the ⓘ** — tapping a spell there already opens
  the cast sheet which surfaces the same information; a duplicate button
  would be noise.
- [ ] **Non-caster sees granted spells.** An Infernal Tiefling **Fighter** has
  a **Spells** tab (it should NOT be hidden) with a "Granted" section showing
  **Fire Bolt** + **Thaumaturgy**.
- [ ] **Level-gated grants.** That Tiefling shows only the cantrips at L1–2;
  **Hellish Rebuke** appears at L3 and **Darkness** at L5 (level the character
  up or create at those levels to check).
- [ ] **Legacy/lineage swap updates spells.** Switch the legacy from Infernal
  to Abyssal → Fire Bolt is replaced by Poison Spray.
- [ ] **Innate casting ability.** Cast Fire Bolt on a non-caster → the attack
  roll uses your highest of INT/WIS/CHA by default; setting the "Innate
  Spellcasting" pick to a specific ability overrides that.
- [ ] **Free cast (leveled grants).** For a granted leveled spell (e.g.
  Hellish Rebuke at L3+), the cast sheet shows a **"Cast free (Innate)"** path
  with a 1/Long-Rest counter; using it spends the counter, not a slot. A Long
  Rest refills it.
- [ ] **Caster + grants coexist.** A Tiefling Wizard shows both their prepared
  list and the Granted section without duplication.
- [ ] **Split-catalog spell load (2026-07-10 refactor).** Cold-launch the app
  (kill from app switcher first). Create a Wizard. Open **Add Spell**. The
  picker shows spells for **every** level 0–9 (spot-check: Fire Bolt at L0,
  Magic Missile at L1, Fireball at L3, Wall of Fire at L4, Meteor Swarm at
  L9). Settings → Content shows no "Missing bundled content" or "Duplicate id"
  errors. Bundle now loads spells from `Content/Spells/SRD/L*.json` (10 files)
  instead of a single `spells.json`.
- [ ] **SRD 5.2.1 compliance audit — cantrip picker (2026-07-11).** Create a
  Druid. Open **Add Spell** at cantrip level. Confirm **Thorn Whip** and
  **Thunderclap** are NO LONGER in the picker (they were 2014-PHB, not SRD).
  Confirm **Message** now appears in the Druid list. Confirm **Elementalism**
  appears at L0 for druid/sorcerer/wizard. For a Sorcerer specifically,
  confirm **Sorcerous Burst** appears at L0.
- [ ] **SRD 5.2.1 compliance — smites (2026-07-11).** Create a Paladin. Open
  Add Spell. Confirm Thunderous / Wrathful / Branding / Blinding Smite are
  NO LONGER available (5.2.1 folded them into a single Divine Smite spell +
  Divine Smite class feature). Confirm **Divine Smite** (the spell) is now
  available for the Paladin at L1 with `+1d8 radiant per slot level` scaling.
- [ ] **SRD 5.2.1 compliance — L6 renames (2026-07-11).** Confirm **Otto's
  Irresistible Dance** is no longer available; **Irresistible Dance** (the
  5.2.1 canonical name) is available at L6 for bard/wizard.
- [ ] **SRD 5.2.1 compliance — Feeblemind replaced (2026-07-11).** At L8,
  confirm **Feeblemind** is gone; **Befuddlement** (its SRD 5.2.1 successor)
  is available for bard/druid/warlock/wizard.
- [ ] **SRD 5.2.1 compliance — new adds (2026-07-11).** Spot-check the spell
  picker for at least three of the newly authored spells: **Hideous Laughter**
  (L1, bard/warlock/wizard), **Blink** (L3, sorcerer/wizard), **Vitriolic
  Sphere** (L4, sorcerer/wizard), **Power Word Heal** (L9, bard/cleric).
- [ ] **SRD 5.2.1 conditions — Exhaustion added (2026-07-11).** Open Conditions
  from a character sheet. The list now has 15 conditions (was 14) — verify
  **Exhaustion** appears in the picker with the "cumulative levels; 6 kills you"
  description. Applying it should show up on the sheet like other conditions
  (the specific mechanical scaling — Speed/roll penalties per level — is
  honor-system for now, not automatically applied).
- [ ] **SRD 5.2.1 gear renames (2026-07-11).** In the inventory/equipment
  picker, confirm the entries formerly labelled "Rations (1 day)" and
  "Rope, Hempen (50 feet)" now display as **Rations** and **Rope**
  respectively (the SRD 5.2.1 canonical names).
- [ ] **SRD 5.2.1 class feature backfill (2026-07-11).** For each class,
  level up (or create at a specific level) and confirm the newly authored
  features appear in the Features tab and on level-up preview:
  - **Barbarian**: Danger Sense + Reckless Attack at L2; Primal Knowledge
    at L3; Fast Movement at L5; Feral Instinct + Instinctive Pounce at L7;
    Brutal Strike at L9; Relentless Rage at L11; Persistent Rage at L15;
    Indomitable Might at L18; Primal Champion at L20.
  - **Fighter**: Tactical Mind at L2; Tactical Shift at L5; Indomitable
    at L9/13/17; Tactical Master at L9; Two Extra Attacks at L11;
    Studied Attacks at L13; Three Extra Attacks at L20.
  - **Wizard**: Ritual Adept at L1; Scholar at L2; Memorize Spell at L5;
    Spell Mastery at L18; Signature Spells at L20.
  - **Druid**: Wild Resurgence at L5; Elemental Fury at L7; Improved
    Elemental Fury at L15.
  - **Warlock**: L11/13/15/17 Mystic Arcanum entries now display as
    plain **Mystic Arcanum** (not "Mystic Arcanum (6th)/(7th)/…").
  - **Ranger**: L1 Spellcasting now surfaced as a feature; L6 Roving
    replaces the old L5 placement; L3 no longer shows Primal Awareness
    (2014 leftover, removed).
  - **Paladin**: Abjure Foes at L9.
  - **Monk**: Uncanny Metabolism at L2 (alongside Monk's Focus + Flurry
    of Blows / Patient Defense / Step of the Wind).
  - **All classes**: **Ability Score Improvement** entries at L4/8/12/16
    (Fighter also 6/14; Rogue also 10) and **Epic Boon** at L19 now show
    up as their own features.
- [ ] **Barbarian Fast Movement wires speed (2026-07-11).** Create a
  Barbarian at L5 in light or no armor. Speed chip should show base speed
  + **10** ft. Equip Chain Mail (heavy) → speed drops back to base. Match
  the Unarmored Movement pattern for Monk.
- [ ] **Barbarian Brutal Strike opt-in rider (2026-07-11).** Create a
  Barbarian at L9. On a weapon attack that hits, the damage tab shows a
  toggleable **Brutal Strike +1d10 force** chip. Toggling it in adds 1d10
  to the roll. It's disabled after use until start of next turn (once
  per turn — matches Sneak Attack pattern). The target-side effect
  (Forceful Blow shove / Hamstring Blow speed reduction) is honor-system
  and mentioned in the feature description.
- [ ] **Fighter Indomitable resource pool (2026-07-11).** Create a Fighter
  at L9. Features tab / Resources card shows **Indomitable Uses: 1/1**.
  Level up to L13 → pool grows to 2/2; L17 → 3/3. Refreshes on Long Rest.
  Rerolling a failed save is honor-system (mention "spend a use here"
  in the description).
- [ ] **Barbarian Reckless Attack toggle (2026-07-11).** Create a Barbarian
  at L2+. Open Features tab. Reckless Attack should show as a toggleable
  active feature (Free action). Toggle it on — an active-effect chip appears
  on the sheet. Perform a weapon attack from the Actions/Attacks tab. The
  attack should roll with **Advantage** (2d20 keep highest) and the label
  should include "(Advantage)". Toggle Reckless Attack off; the next attack
  should roll normally.
- [ ] **Barbarian Feral Instinct — Init chip (2026-07-11).** Level a
  Barbarian to L7. The Init stat chip should now display the modifier
  followed by "(Adv)" (e.g. "+2 (Adv)"). Compare to a Barbarian at L6:
  no suffix. Non-barbarians never show the suffix.
- [ ] **Barbarian Indomitable Might — d20 floor on STR (2026-07-11).**
  Level a Barbarian with STR 18 to L18. Roll a Strength check from the
  Abilities tab. Even if the d20 lands 5, the resulting roll should
  display "1d20+STR (+4) — d20 floor 14" and the effective d20 should
  be clamped to 14 (total 18 = STR). Same behavior on a STR save. Rolling
  an Athletics check (STR-based skill) should ALSO get the floor. DEX/CON
  checks/saves get no floor. Bumping STR to 20 changes the floor to 15.
- [ ] **SRD 5.2.1 compliance — spell schools shifted (2026-07-11).** In the
  spell picker or a spell's detail view, verify: **Cure Wounds** → Abjuration,
  **Poison Spray** → Necromancy, **Acid Splash** → Evocation, **Mass Heal** →
  Abjuration. Older lists had these under different schools.

## Actions & combat — Giant Ancestry (Goliath)

- [ ] **Granted actions are choice-gated.** Pick **Stone's Giant** → Actions
  tab shows "Stone's Endurance" as a **Reaction** that rolls **1d12 + CON**.
  Pick **Cloud's Giant** → "Cloud's Jaunt" Bonus Action. Pick **Storm's Giant**
  → "Storm's Thunder" Reaction rolling 1d8 thunder. Only the chosen one shows.
- [ ] **On-hit riders are choice-gated.** Pick **Fire's Giant** → a "Fire's
  Burn" chip appears on weapon attacks adding **+1d10 fire** to the damage roll.
  Pick **Frost's Giant** → "Frost's Chill" (+1d6 cold). Switching the pick
  swaps which chip appears; other giants show no rider.
- [ ] **Hill's Tumble** is descriptive only (no action row / chip).
- [ ] _Known gap:_ the "PB uses per Long Rest" limit on giant benefits is **not
  metered** — actions/riders are always available; track uses yourself.

---

## Settings & critical-hit styles (new 2026-06-27)

- [ ] **Settings → Combat shows a "Natural 20 style" picker** with: Off, Double
  the dice (RAW, default), Double the rolled value, Max die + roll, Maximize
  dice, Double the total. The footer explains the selected style.
- [ ] **Choice persists across relaunch.** Pick a non-default style, force-quit,
  relaunch → it's still selected.
- [ ] **Crit applies on the damage follow-up.** Roll a weapon (or spell) attack
  that lands a **natural 20**; the damage chip reads **"Roll critical damage"**
  and its subtitle shows the transformed dice. Each style:
  - Double the dice → e.g. a greatsword's `2d6+3` becomes `4d6+3`.
  - Double the rolled value → rolls `2d6`, the total doubles the dice you rolled, +3.
  - Max die + roll → `12 + 2d6 + 3`.
  - Maximize → every damage die shows its max (e.g. all 6s).
  - Double the total → dice doubled and the +3 becomes +6.
  - Off → damage rolls normally (no crit change).
- [ ] **No crit on a dropped 20.** With disadvantage, a 20 that gets dropped
  (keep-lowest) is NOT a crit — damage rolls normally.
- [ ] **Non-crit attacks unaffected.** A normal hit's damage chip is unchanged.
- [ ] _Note:_ crit applies to the attack→damage follow-up (weapon + spell
  attack rolls), not to manual dice-tab rolls with no attack context.

## Stackable damage riders (changed 2026-06-27)

Riders (Sneak Attack, Divine Smite, Fire's Burn, …) are no longer mutually-
exclusive chips — they're independent **toggles** stacked onto one damage roll.

- [ ] **Riders are toggles, not one-shot chips.** After an attack, the rail
  shows a "Roll damage" chip plus a toggle per available rider. Tapping a rider
  highlights it (and updates the "Roll damage" subtitle to the combined dice);
  tapping again turns it off. Tapping "Roll damage" rolls base + all active
  riders as one roll.
- [ ] **Stacking works.** A Paladin/Rogue multiclass can turn on **both** Sneak
  Attack and Divine Smite and roll them together (previously impossible).
- [ ] **Cost paid only at roll time.** Toggling a rider on/off spends nothing;
  switching tabs without rolling spends nothing. Only tapping "Roll damage"
  spends each active rider's resource (Sneak Attack once-per-turn flag, Divine
  Smite spell slot). [Fixes the rider half of QA audit #2.]
- [ ] **Crit doubles every active rider.** On a nat-20, "Roll critical damage"
  applies the crit style to the whole combined formula — weapon + Sneak Attack +
  Smite dice all transform.
- [ ] **Divine Smite slot level** still shows in the toggle label ("Divine
  Smite (L1 slot)") and consumes the slot it names.
- [ ] **Once-per-turn riders disappear after use.** After firing Sneak Attack,
  it's gone from the rail until Start New Turn clears the flag.

## Spell effects on the sheet (new 2026-06-27)

Spells can now change the caster's sheet on cast, and impose-condition spells
offer an apply button (one-PC app — no enemy sheet).

- [ ] **False Life grants temp HP.** Cast False Life (a leveled spell — tap a
  slot) → the character gains 2d4+4 temp HP (rolled). Re-casting takes the
  higher value, doesn't stack.
- [ ] **Control spells offer "Apply to this character".** Open Hold Person /
  Fear / Ray of Sickness / Charm Monster in the cast sheet → an "Imposes"
  section shows an **Apply Paralyzed/Frightened/Poisoned/Charmed** button.
  Tapping it adds the condition to the character; the button then reads
  "applied" and disables.
- [ ] **Applied debuff actually bites.** Apply Poisoned via Ray of Sickness →
  go roll a skill/attack → it's at disadvantage (condition enforcement). Apply
  Paralyzed → the character shows the condition badge.
- [ ] **Plain damage spells have no effect section.** Fire Bolt / Magic Missile
  show no "Imposes" section.
- [ ] _Note:_ debuffs land on **your** character (honor-system, for when you're
  the target) — there's no enemy sheet to target.

## Condition enforcement (new 2026-06-27)

Tracked conditions now actually change d20 rolls (attacks, ability/skill checks,
saves) — for the rolling character. (`attacksAgainst…` effects act on the
attacker, so they're not applied to the afflicted character's own dice.)

- [ ] **Poisoned → disadvantage.** Add Poisoned to a character; a weapon attack
  rolls **2d20 keep-lowest**, and any skill/ability check does too (label notes
  "Disadvantage"). Saves are unaffected by Poisoned.
- [ ] **Invisible → attack advantage.** An Invisible character's attacks roll
  2d20 keep-highest.
- [ ] **Restrained → DEX saves only.** A Restrained character's **Dexterity**
  save rolls disadvantage; a Wisdom save rolls normally. (Restrained also gives
  attack disadvantage.)
- [ ] **Advantage + disadvantage cancel.** Poisoned, then tap the skill's
  **Advantage** chip → it rolls a normal single d20 (the two cancel per 5e).
- [ ] **Weapon attacks honor conditions** even though they have no adv/dis
  chips (applied automatically in the handoff).
- [ ] **Spell attacks combine sources.** A Poisoned Sorcerer with Innate Sorcery
  active (advantage) casting a spell attack → the advantage and disadvantage
  cancel to a normal roll.
- [ ] **Damage unaffected.** Conditions change only the d20 (attack/check/save),
  never damage dice.
- [ ] **STR/DEX saves auto-fail (new 2026-06-27).** Add Paralyzed (or Stunned)
  to a character, then tap a **Strength** or **Dexterity** save → an alert
  "Save auto-fails" appears and **no roll happens**. A Wisdom save still rolls
  normally. Remove the condition → STR/DEX saves roll again.
- [ ] **Armor Stealth disadvantage (new 2026-06-27).** Equip Chain Mail (or any
  medium/heavy armor flagged `stealthDisadvantage`), then roll a **Stealth**
  check → it rolls 2d20 keep-lowest and the label notes "Disadvantage". Other
  Dexterity skills are unaffected. Unequip → Stealth rolls normally.

## Structural P0 fixes (2026-06-27)

- [ ] **Stroke of Luck replaces the right roll.** As a Rogue 20 with Stroke of
  Luck available, roll an attack that offers the prompt; roll something else in
  the dice tab without tapping it; then tap Stroke of Luck → history shows the
  forced-20 result and the *unrelated* roll is untouched (previously it deleted
  the wrong entry). With a multi-d20 formula, every d20 is forced to 20.
- [ ] **Stroke of Luck doesn't leak.** Do a character info-only action (e.g. a
  save DC), then a manual dice-tab roll → no Stroke of Luck prompt appears for
  the manual roll.
- [ ] **Bad content degrades, doesn't crash.** (Dev) Corrupt a bundled
  `Content/*.json` and launch → app still opens; Settings shows a "Content
  Problems" warning instead of a crash.
- [ ] **Colliding pack names don't overwrite.** Import two packs named "Pack 1"
  and "Pack!1" → both appear in Settings (distinct files). Re-importing "Pack 1"
  replaces only itself.
- [ ] **Rollable resource cost spent only on the roll.** Tap a feature that
  rolls *and* costs a use (e.g. Second Wind), switch tabs **without** rolling →
  the use is NOT spent. Actually roll it → the use is spent once. (Action Surge,
  no roll, still spends on tap; Rage still spends when toggled on.)

## Selection pickers — no double-grants (fixed 2026-06-27)

- [ ] **Second Expertise doesn't re-offer existing expertise.** A Rogue picks
  Expertise at L1; at L6 the second Expertise picker shows the L1-chosen skills
  as **disabled** with "Already expertise" (can't pick them twice). Same for a
  **Bard** (L2 + L9 Expertise). The current picker's own picks stay toggleable.
- [ ] **Class-skill pickers still exclude already-proficient skills** (existing
  behavior unchanged — "Already proficient").

## QA fixes (P0 quick batch, 2026-06-27)

Mostly unit-tested; two have an in-app surface worth a quick check:

- [ ] **Formula bar accepts `min` + keep/drop.** Type `1d20kh1min10` (and
  `1d20min10kh2`) into the dice formula bar — both parse and roll (previously
  rejected). `1d20min` (no number) still errors.
- [ ] **Reliable Talent floor applies to a class-skill proficiency.** A Rogue 7+
  whose proficiency in a skill came from the class skill-choice (not a
  background) rolls that skill **with the floor** — roll it with advantage and
  the dice tab shows `2d20kh1min10`, not `1d20`.

## Classes

### Bard (new 2026-06-17)
- [OK] **Bard core verified** — creation (any-3 skills, Charisma caster),
  Bardic Inspiration pool = CHA mod (Bonus Action, refills on Long Rest),
  Expertise L2/L9 editable, College of Lore at L3 (Bonus Proficiencies +
  Cutting Words), full-caster slots, and reaction features (Countercharm,
  Cutting Words, Peerless Skill) all confirmed.
- [ ] **Jack of All Trades (L2) does the math.** On a level-2+ Bard, every
  skill you're NOT proficient in shows a **diagonal half-filled dot** (blue) in
  place of the empty circle, and that skill's modifier includes half your
  Proficiency Bonus (round down) — e.g. a level-5 Bard (PB 4) with DEX 14 shows
  Stealth at **+4** (+2 DEX +2 half-PB). Proficient (green check) / Expertise
  (yellow star) dots are unchanged and get no extra bonus. Rolling such a skill
  from the table carries the bonus into the dice tab, and passive Perception
  reflects it when Perception isn't proficient.
- [ ] _Known simplifications:_ Font of Inspiration's short-rest recovery is
  **not** auto-applied (pool refreshes on Long Rest — track short-rest manually);
  Magical Secrets / Magical Discoveries cross-list spell choices are
  descriptive, not auto-applied.

### Sorcerer (new 2026-06-27)
- [ ] **Create a Sorcerer.** Class skills step offers exactly 6 options
  (Arcana, Deception, Insight, Intimidation, Persuasion, Religion), choose 2.
  Sheet opens with a Spells tab (Charisma caster, no armor).
- [ ] **Innate Sorcery (L1)** is a **toggle** Bonus Action (2 / Long Rest):
  activating it shows an active effect; **while active**, the cast sheet shows
  your **Spell Save DC +1** and **Advantage** on spell-attack rolls (the spell
  attack rolls 2d20-keep-highest), and "End Innate Sorcery" appears. Ending it
  (or a Long Rest) clears the buff.
- [ ] **Sorcery Points (L2 Font of Magic)** appear as a **counter** (in the
  resources card), value equal to your Sorcerer level (2 at L2, 5 at L5, …),
  and are NOT a tappable action row. A Long Rest refills them. None at L1.
- [ ] **Metamagic (L2)** shows on the Features tab as a picker with **2**
  choices at L2, growing to **4** at L10 and **6** at L17, from the 10 options.
- [ ] **Subclass at L3** prompts "Choose a Sorcerous origin" with **Draconic
  Sorcery**; its features appear as you level (Draconic Resilience + Draconic
  Spells at L3, Elemental Affinity at L6, Dragon Wings at L14).
- [ ] **Elemental Affinity (L6)** offers a damage-type picker (Acid/Cold/Fire/
  Lightning/Poison) on the Features tab.
- [ ] **Dragon Wings (L14)** is a Bonus Action with a 1 / Long Rest counter.
- [ ] **Draconic Resilience (L3)** — once Draconic Sorcery is chosen, the
  character's **AC while unarmored is 10 + DEX + CHA**, and **max HP increases
  by your sorcerer level** (e.g. +3 at L3, +5 at L5). Leveling up adds 1 more.
- [ ] **Draconic Spells** become always-prepared on the Spells tab by tier:
  L3 (Alter Self, Chromatic Orb, Command, Dragon's Breath), L5 (Fear, Fly),
  L7 (Arcane Eye, Charm Monster), L9 (Legend Lore, Summon Dragon).
- [ ] **Full-caster slots** — a high-level Sorcerer reaches a 9th-level slot.
- [ ] _Known simplifications:_ Sorcery-point spending (Metamagic, creating/
  converting slots) and Sorcerous Restoration's short-rest recovery remain
  **manual** (the points counter is adjusted by hand). Summon Dragon's stat
  block is text-only. "Sorcerer spells" advantage/DC applies to all the
  character's spells (single-class assumption).

### Cross-class fixes from the Sorcerer pass (verify these too)
- [ ] **Barbarian Unarmored Defense** now actually computes: a no-armor
  Barbarian's AC is **10 + DEX + CON** (previously the feature did nothing).
- [ ] **Dwarven Toughness** now actually adds HP: a Dwarf's max HP is **+1 per
  character level** (previously descriptive only).

### Druid + spell preparation (new 2026-07-01)
- [ ] **Create a Druid** — Wisdom caster, d8 HP, Light armor + Shields + Simple
  weapons, INT & WIS saves. Creation offers 2 skills from the Druid list and a
  Primal Order pick (Magician / Warden).
- [ ] **Full-caster slots** — a level-3 Druid has 4× L1 and 2× L2 slots in the
  Spells card.
- [ ] **Wild Shape** appears as a **Bonus Action** on the Actions tab with a
  **2-use** pool (3 at L6, 4 at L17); tapping consumes a use; Short Rest gives
  one back, Long Rest refills.
- [ ] **Circle of the Land at L3** — subclass picker offers it; choosing it
  prompts a land type (Arid/Polar/Temperate/Tropical) and lists Land's Aid,
  Natural Recovery (L6), Nature's Ward (L10), Nature's Sanctuary (L14).
- [ ] **Prepare Spells button** — the Spells card shows **"Prepared: X / N"**
  (N = WIS mod + Druid level) and a **"Prepare Spells"** button (not "Add
  Spell").
- [ ] **Prep picker is class-filtered** — tapping Prepare Spells lists **only
  Druid spells** (Druidcraft, Cure Wounds, Faerie Fire, Hold Person, …); Fire
  Bolt / Magic Missile do **not** appear.
- [ ] **Prepare / unprepare toggles** — tap a leveled spell to prepare it
  (green check); tap again to unprepare. The "Leveled prepared: X / N" counter
  updates live.
- [ ] **Cap enforced** — once leveled prepared hits N, un-prepared leveled
  spells show a slashed circle and can't be added until you unprepare one.
  Cantrips have their own "x / y" budget.
- [ ] **Daily re-prep** — you can freely unprepare and prepare different spells
  (models "change your prepared list after a long rest").
- [ ] **Fresh Druid isn't over-prepared** — a newly created Druid starts with a
  prepared list capped at N leveled spells (all Druid-list), not every L1 spell.
- [ ] _Known simplifications:_ Wild Shape beast forms aren't modeled (track your
  form + stats manually); per-land circle spell lists are text-only; Natural
  Recovery slot recovery is manual; the "must long-rest to re-prepare" gate is
  honor-system (editing is always allowed).

### Multiclassing (new 2026-07-01)
- [ ] **Class picker at level-up.** On a Druid 2, tap Level Up → a **Class**
  card shows a "Druid L2 → 3" button (selected) and a **"Multiclass into…"**
  menu listing the other classes.
- [ ] **RAW prerequisites hard-block.** A character with WIS 10 opens the
  multiclass menu → **Druid** shows a lock with "Druid needs WIS 13 (you have
  10)" and can't be tapped. A STR 10 Fighter is blocked from adding ANY class
  (fighter's own primary must also be 13+).
- [ ] **Adding a class.** An eligible Druid 2 (WIS 16, STR 13) picks Fighter →
  header reads "Fighter · NEW class → Level 1", the HP card uses **1d10** (not
  1d8), and the card notes what multiclassing grants (Light/Medium armor,
  Shield, Simple/Martial weapons). Finish → sheet header shows
  **"Druid 2 / Fighter 1"**, and the granted proficiencies appear.
- [ ] **No L1 skill picks for the second class.** After adding Fighter, the
  Features tab does **not** offer Fighter's "choose 2 skills" picker (5e
  multiclass rule). The first class's picker is unaffected.
- [ ] **Slot merging.** Level a Druid 2 / Cleric 2 → the Spells card shows ONE
  set of slots: **4× L1 and 3× L2** (combined caster level 4 on the shared
  table), not two separate 3× L1 pools. A Druid 3 / Fighter 2 keeps normal
  Druid slots (one casting class → no merge).
- [ ] **Half-caster counts half.** Druid 3 / Paladin 3 → combined caster level
  4 (3 + 3÷2).
- [ ] **Per-class preparation.** As Druid 3 / Cleric 2 (WIS 16), open Prepare
  Spells → a **class segment picker** appears; Druid shows "Leveled prepared:
  X / 6", Cleric "X / 5", each with its own class-filtered list and bucket.
  The Spells card lists both "Druid prepared: X/6" and "Cleric prepared: X/5".
- [ ] **Casting ability follows the class.** A spell prepared under the Druid
  bucket casts with WIS even when another casting class (different ability)
  is present — check the spell attack/DC math in the cast sheet.
- [ ] **Old saves migrate.** A pre-existing single-class prepared caster loads
  with its prepared list intact (moved into the class bucket invisibly).
- [ ] _Known simplifications:_ known-caster (Bard/Sorcerer) per-level spell
  picks aren't budget-gated; Bard/Rogue multiclass skill/tool CHOICE grants are
  manual; the level-up Spellcasting card diffs the leveled class's own slot
  table, not the merged pools; on the level-up that first merges slots, the
  pools reset to full (old per-class ids are retired).

### Spell class lists, learning budgets & starting spells (new 2026-07-01)
- [ ] **Class-restricted lists.** A Wizard's spell picker no longer shows
  Bless (cleric/paladin only); a Cleric's does. Every picker (Prepare/Learn/
  Add) shows only the class's own list.
- [ ] **Mode titles per class.** Druid/Cleric → "Prepare Spells"; Bard/
  Sorcerer → "Learn Spells" with a "Spells known: X / N" counter; Wizard →
  "Add Spell". A Druid/Sorcerer multiclass shows a class segment picker and
  "Manage Spells" on the button.
- [ ] **Learn budget enforced.** A level-1 Sorcerer can learn at most 2
  leveled spells (bard: 4); at the cap un-learned spells show a slashed
  circle until one is toggled off. Cantrips have their own budget.
- [ ] **Creation Spells step (casters only).** Creating a Druid: after
  Abilities a "Spells" step appears with Cantrips and Level 1 sections, live
  "X / N" counters (druid: 2 cantrips; leveled = WIS mod + 1); creating a
  Fighter skips straight to Review.
- [ ] **Cap + auto-pick in creation.** Over-budget picks are blocked (slashed
  circle); "Auto-pick the rest" fills remaining budget alphabetically; Next
  requires at least one pick.
- [ ] **Created character matches picks.** The finished character's Spells
  card lists exactly the chosen spells (not the whole catalog, which was the
  old behavior).
- [ ] **Level-up prompts spell learning.** Level a Sorcerer 1 → 2 (spells
  known 2 → 4): after Finish, the spell picker opens automatically in Learn
  mode. A Fighter level-up opens no picker.
- [ ] _Known simplifications:_ wizard remains Add mode until spellbook
  management lands; Learn-mode edits aren't time-gated (RAW "swap one spell
  per level-up" is honor-system); auto-seed still applies to drafts that skip
  the step (DEBUG autofill).

### Level-up sheet sync (new 2026-07-01)
- [ ] **HP preview includes feature bonuses.** Level up a **Dwarf** (Dwarven
  Toughness) → the staged HP line shows **+1 more** than die + CON, with an
  "incl. +1 from features" caption, and the committed max matches the preview
  exactly. A Draconic Sorcerer shows the same (+1/level).
- [ ] **Subclass unlock callout.** Level a Druid (or any class) from 2 → 3 with
  no subclass chosen → a purple banner names the unlock ("Level 3 unlocks your
  Druid subclass — choose it in the Features tab"). After picking a subclass,
  leveling further shows no banner.
- [ ] **Spellcasting card on caster level-ups.** Druid 1 → 2 shows "More slots
  at: L1 (2 → 3)" and "Prepared spells: N → N+1"; Druid 2 → 3 shows "New spell
  slot level: L2"; Druid 3 → 4 shows "Cantrips known: 2 → 3". A Fighter
  level-up shows no Spellcasting card.
- [ ] **New resources appear without any sync step.** Level a Druid 1 → 2 →
  Wild Shape shows up on the Actions tab with a full 2-use pool; the new L1
  slot and (at 3) L2 slots appear in the Spells card already full.

### Warlock (new 2026-07-02)
- [ ] **Create a Warlock.** Charisma caster, d8 HP, Light armor + Simple
  weapons, WIS & CHA saves; class skills step offers 2 of 7 (Arcana,
  Deception, History, Intimidation, Investigation, Nature, Religion). The
  creation Spells step shows only warlock-list spells (Eldritch Blast present;
  Fire Bolt absent) with budgets of 2 cantrips / 2 known spells.
- [ ] **Pact Magic slots.** A level-1 Warlock's Spells card shows ONE slot
  pool (1× L1); at L5 it's **2 slots, both level 3** (no separate L1/L2
  pools). A **Short Rest** refills them (unlike every other caster's slots).
- [ ] **Learn Spells.** The Spells card button reads **"Learn Spells"** with a
  "Spells known: X / N" counter following the Warlock table (2 at L1, 6 at
  L5); at the cap, un-learned spells show a slashed circle until one is
  toggled off.
- [ ] **Eldritch Invocations.** The Features tab shows an invocations picker
  offering **13** options — **1** pick at L1, growing to **3** at L2 (re-open
  the picker after leveling); the feature text notes mechanics are manual.
- [ ] **Level-up prompts spell learning.** Warlock 1 → 2 (spells known 2 → 3,
  second pact slot): after Finish, the spell picker opens automatically.
- [ ] **Fiend Patron at L3.** Subclass picker offers it; choosing it puts
  **Command** in the Granted section of the Spells tab; at L6 **Dark One's Own
  Luck** shows a use pool equal to your CHA modifier; at L14 **Hurl Through
  Hell** is a tappable action rolling **8d10 psychic** with a 1 / Long Rest
  counter.
- [ ] **Multiclass keeps pact separate.** A Druid 3 / Warlock 3 shows the
  normal Druid slots AND the pact slots as separate pools (pact magic is
  excluded from the shared multiclass slot table — no merged pool).
- [ ] _Known simplifications:_ invocation effects are text-only (Agonizing
  Blast's +CHA damage is manual); Eldritch Blast's multi-beam scaling means
  rolling the attack once per beam manually; Dark One's Blessing temp HP is
  applied by hand via the HP editor; Mystic Arcanum spells (L6+) aren't
  bundled; Magical Cunning's slot regain is manual (the 1/LR counter just
  tracks the rite).

### Subclass backfill — Berserker, Devotion, Evoker (new 2026-07-02)
- [ ] **Every class now has a subclass picker.** A Barbarian / Paladin /
  Wizard at L3 offers a subclass picker on the Features tab ("Choose your
  Primal Path" / "Choose your Sacred Oath" / "Choose your Arcane Tradition"),
  and leveling 2 → 3 without one shows the purple subclass-unlock banner.
- [ ] **Frenzy rider (Berserker).** With Path of the Berserker picked and a
  melee weapon equipped, a weapon attack shows a **"Frenzy"** toggle chip that
  adds **2d6** (weapon-typed) to the damage roll; at L9 it's **3d6**; after
  using it, the chip greys out until **Start New Turn**. The Rage-active +
  Reckless-Attack requirement is a note in the feature text, not enforced.
- [ ] **Intimidating Presence (Berserker L14).** Appears as a **Bonus Action**
  row showing a **Strength-based save DC** with a **1 / Long Rest** counter.
- [ ] **Devotion oath spells.** Picking Oath of Devotion at L3 puts **Shield
  of Faith** in the Granted section of the Spells tab (castable — its +2 AC
  buff applies); the other oath spells are listed as text.
- [ ] **Holy Nimbus (Devotion L20).** A **Bonus Action** with a **1 / Long
  Rest** counter; its damage/advantage effects are manual.
- [ ] **Evoker.** All five features (Evocation Savant + Potent Cantrip at L3,
  Sculpt Spells L6, Empowered Evocation L10, Overchannel L14) appear at their
  levels as text; no action rows expected.
- [ ] _Known simplifications:_ Frenzy's Rage/Reckless gate, Sacred Weapon's
  +CHA attack bonus, Mindless Rage's condition immunity, and the Sculpt
  Spells / Potent Cantrip / Overchannel math are all manual.

### Monk (new 2026-07-06)
- [ ] **Create a Monk.** DEX/WIS class, d8 HP, **no** armor proficiencies,
  STR & DEX saves; class skills step offers 2 of 6 (Acrobatics, Athletics,
  History, Insight, Religion, Stealth); no Spells step appears (non-caster).
  The sheet's unarmored AC is **10 + DEX + WIS**.
- [ ] **Unarmed Strike.** The Actions tab shows a Martial Arts / Unarmed
  Strike row: the attack rolls **d20 + DEX + PB**, and the damage rolls
  **1d6 + DEX** at L1 — level up and re-check: **1d8** at L5, **1d10** at
  L11, **1d12** at L17.
- [ ] **Focus points (L2).** A **"Focus Points"** pool (2/2) appears in the
  resources card and refills on a **Short Rest**. Flurry of Blows / Patient
  Defense / Step of the Wind rows all show the **same shared pool badge**,
  and tapping each debits that one pool by 1.
- [ ] **Unarmored Movement.** At L2 the Speed chip gains **+10 ft** (30 → 40
  for a human); equipping any armor or a shield removes the bonus; at L6
  it's +15.
- [ ] **Deflect Attacks (L3).** A **Reaction** row that rolls
  **1d10 + DEX + monk level**.
- [ ] **Stunning Strike (L5).** Tapping it shows a **Wisdom-based save DC**
  and spends **1 Focus point**.
- [ ] **Superior Defense (L18).** The row greys out when fewer than **3**
  Focus points remain.
- [ ] **Warrior of the Open Hand at L3.** The subclass picker offers it;
  **Wholeness of Body** (L6) rolls the Martial Arts die + WIS with a
  WIS-mod / Long Rest pool; **Quivering Palm** (L17) rolls **10d12 force**
  and costs **4 Focus** (deferred to the roll).
- [ ] _Known simplifications:_ Flurry's second/third strike = tap Unarmed
  Strike again; Extra Attack, Open Hand Technique's rider saves, Heightened
  Focus upgrades, Deflect Attacks' redirect, and Disciplined Survivor's
  reroll are all manual.

### Ranger (new 2026-07-06 — class catalog complete)
- [ ] **Create a Ranger.** Wisdom caster, d10 HP, Light + Medium armor +
  Shield + Simple/Martial weapons, STR & DEX saves; class skills step offers
  **3 of 8** (Animal Handling, Athletics, Insight, Investigation, Nature,
  Perception, Stealth, Survival); no cantrips (the creation Spells step
  shows only a Level 1 section). Even a WIS 8 Ranger shows the prep budget
  as **2 / 2** at L1 (the `spellsKnown` table caps prep, not ability mod).
- [ ] **Half-caster slots.** L1 shows **NO** spell slots (SRD half-caster
  starts at L2). L2 = **2 × L1** slots. L5 = **4 × L1 + 2 × L2** (identical
  to a Paladin at the same level).
- [ ] **Hunter's Mark always prepared.** From L1, **Hunter's Mark** appears
  in the Granted section of the Spells tab; casting it applies the on-damage
  rider chip to weapon attacks (existing Hunter's Mark plumbing). The
  Resources card shows a **"Hunter's Mark (free)"** pool = **2** at L1,
  growing to **3 / 4 / 5** at levels 5 / 13 / 17; casting from that pool
  doesn't spend a slot.
- [ ] **Fighting Style at L2.** The Features picker offers **Archery,
  Defense, Dueling, Two-Weapon Fighting** — **no** Great Weapon Fighting.
  Archery adds +2 to ranged attack rolls; the others behave as before.
- [ ] **Weapon Mastery at L1.** Picker for **2** weapons; at **L9** the same
  picker reopens for a **3rd** choice.
- [ ] **Expertise at L2 and L9.** Two independent skill pickers (Deft
  Explorer at L2, Expertise at L9); a chosen skill's dot upgrades to the
  yellow expertise star.
- [ ] **Roving at L5.** Speed chip **+10 ft** while unarmored (30 → 40 for a
  human); equipping any heavy armor removes it. (Known simplification: the
  SRD's "not wearing Heavy armor" is honored as app-level "unarmored" —
  swap heavy armor manually if you're testing light/medium.)
- [ ] **Multiclass caster level.** A Druid 3 / Ranger 4 shows merged
  multiclass slot pools at combined caster level **5** (druid 3 + ranger
  4 ÷ 2), not the ranger's own pools.
- [ ] **Hunter at L3.** Subclass picker offers Hunter; picking it exposes
  **Colossus Slayer** as an opt-in toggle chip on weapon attacks adding
  **1d8 weapon-typed damage**, greying out after use until **Start New
  Turn**.
- [ ] **Hunter L7 / L11 / L15 features.** Escape the Horde (L7), Evasion
  (L11), and Superior Hunter's Prey (L15) appear as text-only features on
  the Features tab.
- [ ] _Known simplifications:_ Hunter's Prey / Defensive Tactics / Superior
  Hunter's Defense each have 3 SRD options — only one authored per tier
  (swap manually); Foe Slayer +1d10, Precise Hunter advantage, Relentless
  Hunter concentration protection, Feral Senses blindsight, and Superior
  Prey's d10 bump are all text — apply manually.

---

## P1 rules-fidelity batch (new 2026-06-27)

### Natural 1 suppresses the damage chip
- [ ] Tap a weapon **Attack**; on the dice tab, roll a **natural 1** on the
  attack d20 → the follow-up rail shows **"Natural 1 — miss. No damage."** and
  the "Roll damage" chip + any rider toggles are hidden.
- [ ] Roll a non-1 attack → the damage chip + riders appear as before.

### Choose-damage spells
- [ ] Cast **Chromatic Orb** → a **Damage type** picker shows 6 options (acid,
  cold, fire, lightning, poison, thunder). Pick **cold**, roll damage → the
  result breakdown reads **cold** (not fire).
- [ ] Cast **Dragon's Breath** → picker shows 5 options; the chosen type carries
  into the damage roll.
- [ ] A fixed-type damage spell (e.g. Fire Bolt) shows **no** type picker.

### Fighting Styles — Great Weapon Fighting & Two-Weapon Fighting
- [ ] A Fighter with **Great Weapon Fighting** wielding a **Greatsword** (or a
  longsword's **2H** damage) → the damage roll **rerolls 1s and 2s** once
  (description shows "(reroll 1-2)"); a one-handed longsword swing does **not**.
- [ ] A Fighter with **Two-Weapon Fighting** — verify the engine restores the
  ability mod to an off-hand (mod-less) attack. _Note: a separate off-hand
  attack row isn't generated yet, so this is mostly engine-level for now._
- [ ] Archery / Dueling / Defense still behave as before (no regression).

### Weapon Mastery — resolved mechanics
- [ ] Equip a **Quarterstaff** (Topple) with the Weapon Mastery feature + it
  selected → tap the **Topple** badge → the sheet shows **"…DC N Constitution
  save or falls Prone"** with N computed (8 + attack mod + PB).
- [ ] Equip a **Greatsword** (Graze) similarly → the badge detail shows
  **"On a miss: deal N <type> damage"** with N = your attack ability mod.
- [ ] Sap/Slow/Nick/Vex masteries still show their rule text (narrative — no
  enemy sheet).

### Buff spells touch the sheet
- [ ] Cast **Shield of Faith** (concentration) → **AC goes up by 2**; an
  effect pill appears. Drop concentration → AC returns and the pill clears.
- [ ] Cast **Shield** (reaction, 1 round) → **AC +5**; tap **Start New Turn** →
  the buff expires and AC returns.
- [ ] Cast **Mage Armor** while **unarmored** → AC becomes **13 + DEX** (pill
  shows "Unarmored AC base 13"). With body armor equipped it has no effect.
- [ ] Cast **Bless** → tap a weapon **Attack**, a **spell attack**, and a
  **saving throw** → each rolls an extra **1d4** (label notes "+Bless"). Ability
  and skill checks do **not** get the d4. Drop concentration → the d4 stops.
- [ ] Cast **Longstrider** → **Speed increases by 10 ft**. Dismiss the pill →
  speed returns.
- [ ] Shield + Shield of Faith together → **AC +7** (they stack).

## Feats — content foundation (new 2026-07-13)

Schema + bundled catalog land first; picker wiring (Origin at background,
General at ASI L4/8/12/16, Epic Boon at L19) comes in the follow-up tasks
and gets its own section then. For this pass, the surface area is invisible
to the player — verify content loads cleanly.

- [ ] ⌘U → **ContentLintTests** all green. Notably: `featsMatchSRDManifest`,
  `idsAreUniqueWithinEachFile` (now includes `feats`), and
  `backgroundReferencesResolveOrAreAllowListed`.
- [ ] Launch the app → **Settings → Content diagnostics** shows **no new
  errors** referencing `feats.json` (empty is the pass case).
- [ ] Open a character that has a background referencing a feat (e.g.
  a background whose `feat` is `alert` or `savage_attacker`) → no picker
  yet, but the sheet loads and the feat's grant text is at worst a stub
  in the Features tab (regression watch — the picker will populate later).

### Per-turn gating relaxed (new 2026-07-14)

Per-turn gating (Sneak Attack turn flag, Wild Resurgence slot → Wild
Shape once-per-turn) is now off by default: `Character.inCombat` starts
false, and `hasTurnFlag` / `setTurnFlag` both no-op while it's false.
The visible combat toggle is deferred until we ship real-time turn
tracking — this is a data-model unblock, not a UI feature yet.

- [ ] Druid L5 Wild Resurgence: with Wild Shape at 0, trade a slot for a
  Wild Shape use. Trade **again** immediately without tapping any "New
  Turn" button → the second trade is legal (no "Already traded this turn"
  block).
- [ ] Round-ticking effects still work: cast Rage, the orange "This turn"
  banner surfaces with a **Start New Turn** button; tapping it decrements
  Rage's round counter as before.
- [ ] With no active flags AND no round-ticking effects, the "This turn"
  banner is hidden (Actions tab looks unchanged from pre-feats work).

### Druid L5 Wild Resurgence exchange (new 2026-07-13)

The Wild Resurgence feature now has a "Trade Available (LR)" resource
chip (1/1 out of Long Rest) and an interactive **Exchange** button below
the card. Two directions:

1. **Spell slot → Wild Shape use** — legal only when Wild Shape uses
   are at 0. Consumes the character's lowest-level slot (L1 preferred).
   Once per turn (uses the same turn-flag system as Sneak Attack).
2. **Wild Shape use → L1 slot** — consumes 1 Wild Shape use, refunds 1
   L1 slot (up to max). Once per Long Rest, tracked by the trade pool.

Cases:

- [ ] Create a **Druid L5** → Features tab shows a **Wild Resurgence**
  card. The card shows a resource chip "**Trade Available (LR) 1/1**".
  Below the card is a green button "**Exchange Wild Shape ↔ Spell Slot**".
- [ ] Tap the button → sheet opens with two exchange cards and a "Live
  state" footer showing current pools (Wild Shape, Trade Available,
  L1–L3 slots).
- [ ] **Slot → Wild Shape** direction: character has Wild Shape 2/2 →
  the card status reads "Wild Shape must be at 0 to trade" and the
  trade button is disabled.
- [ ] Drop Wild Shape to 0/2 (via the Actions tab minus, or manually) →
  status flips to "Ready — trade eligible". Tap the button → L1 slot
  drops by 1, Wild Shape goes to 1/2. Card now says "Already traded
  this turn" and disables until the player taps "Start New Turn" on
  the sheet's turn-flag banner.
- [ ] **Wild Shape → L1** direction: character has Wild Shape 1/2 and
  L1 slot at max → status reads "L1 slot is already full". Cast a L1
  spell to burn a slot → status flips to "Ready". Tap the button →
  Wild Shape drops to 0/2, L1 slot goes back to full, "Trade Available"
  pool drops to 0/1.
- [ ] Try again → both directions blocked appropriately: forward one
  fires again after a New Turn (but requires 0/2 Wild Shape), reverse
  one stays disabled "Already used this Long Rest".
- [ ] Long Rest → Trade Available refreshes to 1/1. All slots and Wild
  Shape refresh normally too.
- [ ] **No Druid L5** → no button, no trade pool (feature card doesn't
  exist below L5 anyway; the resource `byClassLevel` starts at 5).
- [ ] Save + relaunch → live pool state persists.

### Magic Initiate spell picker (new 2026-07-13)

Backgrounds that grant Magic Initiate (Sage → Wizard list, Acolyte →
Cleric list) now surface a "Set up Magic Initiate spells" button under
the Origin Feat card. The picker lets the player choose 2 cantrips + 1
level-1 spell from the locked list, plus INT/WIS/CHA as this feat's
spellcasting ability. The L1 spell gets a once-per-Long-Rest free cast
via the standard granted-spell resource pool.

- [ ] Create a **Sage** character → Features tab shows the **Magic
  Initiate** card + an orange "Set up Magic Initiate spells" button
  below it. Prior sessions' Magic Initiate stubs won't have a button
  (they never got picks recorded — mark them for setup on next open).
- [ ] Tap the button → sheet opens with "Class list: Wizard" header,
  an ability selector (INT / WIS / CHA), and two sections: **Cantrips
  (0 / 2)** and **Level-1 spell (0 / 1)**. Only Wizard-list spells
  appear.
- [ ] Pick an ability (e.g. **INT**) → chip highlights.
- [ ] Pick 2 cantrips (e.g. Fire Bolt, Mage Hand) → **Cantrips (2 / 2)**
  in green. Attempting a 3rd disables the un-picked rows until one is
  unselected.
- [ ] Pick 1 L1 spell (e.g. Magic Missile) → **Level-1 spell (1 / 1)**
  in green. **Done** button in the toolbar becomes enabled.
- [ ] Tap **Done** → back on the Features tab, the button now dims to
  grey and reads e.g. "Fire Bolt · Mage Hand · Magic Missile — INT".
- [ ] Switch to the **Spells tab** → the 3 picks appear in the granted
  list with source label "Sage · Magic Initiate". The L1 spell has a
  **once/Long Rest free-cast pool** ("Magic Missile (Innate) 1/1").
- [ ] Long Rest → the free-cast pool refreshes to 1/1.
- [ ] Cast Magic Missile via the free-cast affordance → pool drops to
  0/1. Cantrips (Fire Bolt / Mage Hand) remain at-will.
- [ ] Create an **Acolyte** → same flow but Cleric list. Sacred Flame,
  Guidance, Cure Wounds etc. show.
- [ ] Reopen the Magic Initiate setup sheet → previously picked ability
  and spells are pre-selected. Change one → the new pick sticks.
- [ ] Save + relaunch → picks persist.
- [ ] Non-MI backgrounds (Soldier → Savage Attacker, Criminal → Alert)
  do NOT show the setup button.

### Epic Boon picker at L19 (new 2026-07-13)

Every class's L19 Epic Boon feature now opens the Epic Boon feat picker.
Epic Boons raise the ability-score cap on the bumped score to 30. Boon
of Spell Recall requires an already-acquired Spellcasting feature.

- [ ] Create or promote a character to **level 19** (any class) → the L19
  Epic Boon feature card shows the picker with prompt **"Choose an Epic
  Boon"** and count **0 / 1**.
- [ ] Tap **Choose**. The picker lists **7 Epic Boons**: Combat Prowess,
  Dimensional Travel, Fate, Irresistible Offense, Spell Recall, the
  Night Spirit, Truesight. Each is tagged with **Level 19+**.
- [ ] **Non-spellcaster at L19** (Barbarian, Fighter Champion, Rogue) →
  **Boon of Spell Recall is hidden** (its "Spellcasting Feature" prereq
  fails).
- [ ] **Spellcaster at L19** (Wizard, Cleric, Druid, Bard, Sorcerer,
  Warlock, Paladin, Ranger) → Boon of Spell Recall appears in the list.
  Its allowed abilities in the sub-picker are **INT / WIS / CHA only**.
- [ ] Pick **Boon of Truesight** → sub-picker offers all 6 abilities.
  Character with CHA 20 → tap **+** on CHA → CHA becomes **21** (the
  cap is 30 for this bump, not 20). The + button stays enabled up to 30.
- [ ] Pick **Boon of Irresistible Offense** → sub-picker restricted to
  **STR / DEX only** (matches SRD).
- [ ] Change the Boon after picking → the previous ability bump rolls
  back cleanly (CHA 21 → 20). The new Boon starts with a fresh sub-pick.
- [ ] The Epic Boon card summary reads e.g. "Boon of Truesight — +1 CHA"
  once the sub-pick is placed, and the card dims to satisfied state.
- [ ] Save + relaunch → the picked Boon + ability bump persist. Score
  above 20 stays above 20.

### Fighting Style feats consolidation (new 2026-07-13)

Fighter L1, Fighter L10 "Additional Fighting Style", Paladin L2, and
Ranger L2 all pulled their options from inline `fixedOptions` lists. They
now share the Fighting Style feat picker from `feats.json` — the same
picker Fighter L10 uses for its second style.

- [ ] Create a **Fighter L1** → Features tab shows a **Fighting Style**
  card whose picker prompt is **"Choose a Fighting Style"** and count is
  **0 / 1**. Tap **Choose**. The picker lists **Archery / Defense /
  Great Weapon Fighting / Two-Weapon Fighting** — 4 SRD 5.2.1 feats.
- [ ] **Dueling** is NOT offered (not in SRD 5.2.1). This is intentional.
  Legacy characters who already picked Dueling keep the +2 damage bonus
  in the interpreter — no regression on old saves.
- [ ] Pick **Archery** → ranged attack rolls gain **+2** on the sheet's
  attack chips. Card dims to satisfied state.
- [ ] Level the same Fighter to L10 → the **Additional Fighting Style**
  feature offers the same picker MINUS Archery (already picked)? *Not
  yet — the picker doesn't dedupe against the primary FS. Repeat-picks
  currently allowed; add a dedupe pass as its own task if surface-tested.*
- [ ] Create a **Paladin L2** → same picker, same 4 options.
- [ ] Create a **Ranger L2** → same picker, same 4 options.
- [ ] Prereqs: `Archery` etc. carry a "Fighting Style Feature" prereq
  that is auto-met when the picker's own category IS Fighting Style —
  they show up normally in this picker but stay hidden from the L4
  General-feat picker (only Ability Score Improvement and Grappler
  should surface there).

### Origin feats from Background (new 2026-07-13)

Backgrounds lock one Origin feat each per SRD 5.2.1:

- **Soldier** → Savage Attacker
- **Sage** → Magic Initiate (Wizard flavor — spell picker deferred)
- **Acolyte** → Magic Initiate (Cleric flavor — spell picker deferred)
- **Criminal** → Alert

Cases:

- [ ] Create a **Criminal** character → Features tab shows a new card
  **"Alert"** with source label **"Criminal · Origin Feat"**. Description
  matches the SRD text (Initiative Proficiency + Initiative Swap).
- [ ] On the same character, look at the **Initiative** value on the sheet
  → it now includes **+PB** on top of DEX modifier. At L1: DEX-mod + 2.
  At L5: DEX-mod + 3. At L9: DEX-mod + 4.
- [ ] Create a **Soldier** → Features tab shows **Savage Attacker** card
  under "Soldier · Origin Feat". Initiative is DEX-mod only (no PB bump).
- [ ] Create a **Sage** or **Acolyte** → Features tab shows a **Magic
  Initiate** card. Spell picker is NOT yet available (regression watch —
  when the spell picker lands, this line's expectation flips).
- [ ] The Origin Feat card is anchored to L1 in the level-sort ordering
  (top of the list when sort is ascending).
- [ ] Save + relaunch → the card persists across sessions.

### Features tab — sort by level (new 2026-07-13)

- [ ] Open any character's Features tab → cards are ordered by unlock level
  ascending (L1 first). Species traits ride at L1 alongside the class's
  L1 features.
- [ ] Small button at the top of the section reads **"Low → High"** with an
  up-arrow icon. Tap it → toggles to **"High → Low"** with a down-arrow;
  cards reverse order. Tap again → returns to ascending.
- [ ] Quit + relaunch the app → the toggle direction persists (last-chosen
  order is what's shown on the next launch).
- [ ] Multiclass (e.g. Fighter 3 / Wizard 2) → within a given level, class
  features stay grouped in derivation order (no jumbling of Fighter L1 and
  Wizard L1 features).

### ASI-vs-Feat branch at L4/8/12/16 (new 2026-07-13)

Every class's Ability Score Improvement moments (Fighter also at L6/L14,
Rogue at L10, etc.) now open the General-feat picker instead of jumping
straight to point-buy. ASI is one of the General feats — picking it opens
the same distribute-2-points UI that used to live at that level.

- [ ] Create a **Level 4 Fighter** → Features tab shows the L4 "Ability
  Score Improvement" feature card. Its selection prompt now reads
  **"Choose a General feat"** with **0 / 1** picked.
- [ ] Tap **Choose**. Picker lists **Ability Score Improvement** and
  **Grappler** (only 2 General feats today) with their descriptions.
- [ ] Tap **Ability Score Improvement** → an inline **"Distribute 2 points
  across STR / DEX / CON / INT / WIS / CHA"** section appears. Increment
  STR twice → the character's STR increases by 2 immediately on the sheet.
  Close. Return to Features tab → the card is dimmed (satisfied) with
  "Ability Score Improvement — +2 STR" summary.
- [ ] Level up to **5** → the level-up sheet's pending banner is **0** at
  the L5 sheet if all L4 selections were completed (no false-positive from
  the outer "1 pick" being counted before ability sub-picks).
- [ ] Undo: reopen the L4 feature → tap **Change feat** → confirm STR
  drops back by 2 (the previous ASI's ability sub-picks rolled back).
- [ ] Pick **Grappler** instead. Prereq line reads "Level 4+, Strength or
  Dexterity 13+". Only offered when the character's STR **or** DEX ≥ 13.
- [ ] After picking Grappler, the "+1" sub-picker shows **STR / DEX only**
  (Grappler restricts the ability list). Choose STR → +1 applied. Card
  dims to "Grappler — +1 STR".
- [ ] **Character with STR 10, DEX 10** at L4 → Grappler doesn't appear in
  the picker (fails the ability prereq).
- [ ] Save the character, quit + relaunch → the picked feat + ability
  bumps persist. STR/DEX still reflects the bump.
- [ ] **Multiclass level-up into a class whose L4 is coming later** → no
  General-feat branch appears yet (only its own L1 pickers).

### Feat catalog browser (new 2026-07-13)

- [ ] Settings tab → **About** → row **"Bundled feats"** shows a count of
  **17** and has a chevron.
- [ ] Tap it → **Feats** screen groups entries under **Origin**, **General**,
  **Fighting Style**, **Epic Boon**. Each row shows the feat name (+
  "Repeatable" chip where applicable) and, when present, a prerequisite
  line under it.
- [ ] Tap **Alert** → detail view shows a green **Origin** chip, full SRD
  description, and a **Mechanical hooks** section listing "Adds Proficiency
  Bonus to Initiative".
- [ ] Tap **Grappler** → prerequisite reads "Level 4+, Strength or Dexterity 13+";
  hooks include "+1 to one of STR / DEX (max 20)".
- [ ] Tap **Boon of Truesight** → purple **Epic Boon** chip; hooks include
  "+1 to one of STR / DEX / … (max 30)" and "Truesight 60 ft".
- [ ] Tap **Magic Initiate** → hooks include "2 cantrips + 1 L1 spell from
  Cleric / Druid / Wizard list" and "once-per-Long-Rest free cast". "Repeatable"
  chip visible.
- [ ] Tap **Defense** (Fighting Style) → hooks include "+1 AC while wearing armor".
- [ ] Back → the browser reflects the same list on re-entry (no reload glitch).

## Backlog to backfill (older features, not yet itemized here)

These shipped before this doc existed; add cases on demand when we next touch
them or when you want a full regression pass:

- [ ] Dice roller (3D tray, formulas, history, presets, advantage/disadvantage)
- [ ] Character sheet core (HP/CON, AC, initiative, rest, conditions,
  concentration, inventory/attunement)
- [ ] Class progression (leveling, subclasses, Expertise, Sneak Attack, Rage,
  Divine Smite, spell slots)
- [ ] Content import/export & SRD attribution
