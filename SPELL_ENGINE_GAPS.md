# Spell engine gaps (post-catalog polish todo)

Running log of spells whose mechanics or upcast our schema currently
can't express. Populated as I ship the SRD 5.2.1 spell catalog. Every
entry ships with the affected mechanic in the `description` /
`higherLevel` prose so players can adjudicate manually.

## Already known before catalog completion

- ~~**Smite riders**~~: NOT a live gap — the 2024 SRD 5.2.1 removed the
  individual smite spells (Blinding / Branding / Wrathful / Thunderous)
  and folded that mechanic into a single **Divine Smite** spell + a
  Paladin class feature of the same name. Divine Smite (spell) is now
  in the catalog with `extraDicePerLevel` upcast. The class-feature
  side still needs wiring (a `castSpell(divine_smite)` grantedAction
  that consumes a slot); track that in `PLAN_CharacterSheet.md`, not
  here.
- ~~**SpellRange.miles**~~: NOT a gap — `.miles(Int)` exists on
  `SpellRange` (SpellMetadata.swift). Old spec used
  `{"type":"feet","value":5280}` as a workaround; Clairvoyance /
  Project Image / Meteor Swarm now correctly use
  `{"type":"miles","value":N}`.
- **SpellDuration.days**: Gentle Repose's 10 days flattens to `hours:
  240`. Same story with Nondetection, Magic Circle at high slot levels.
- **Extra-ray upcast**: Scorching Ray gains 1 ray per slot level, not
  dice per level. No structured way to express "extra recipe applications
  per level" — currently text-only in `higherLevel`.
- **Walls / cloud persistence**: initial-cast damage lands via
  `rawDamage`, but the per-turn re-entry damage (Sleet Storm,
  Stinking Cloud, Wall of Fire, Cloudkill, Wall of Ice) is text-only.
  Would need a "recurring effect" mechanic tied to a battlefield zone.
- ~~**Aura-adjacent riders**~~: Crusader's Mantle / Aura of Purity /
  Elemental Weapon are all NOT in SRD 5.2.1 (removed). Aura of Life is
  still in-catalog and remains an open gap for "grant a rider to allies
  within range" — but it's a status buff (max HP floor + regen), not a
  damage rider, so lower priority. Magic Weapon: still in the SRD (L2
  Transmutation) and still an engine gap — "give this weapon +N
  attack/damage" has no `selfBuff` shape yet.

## Discovered during L4-L9 catalog completion

- **Bare-integer flat damage** — Guardian of Faith deals a flat 20
  Radiant hit per creature. Shipped as `dice: "20"` on the assumption
  the parser tolerates a bare integer; if it doesn't, change to
  `"20d1"` (mechanically identical). *Files:* `guardian_of_faith`.
- **Multi-recipe upcast (per-recipe scaling)** — Arcane Hand's SRD
  higher-level rule is "Clenched Fist damage increases by 2d8 AND
  Grasping Hand damage increases by 2d6 per slot level above 5th".
  `upcastEffect.extraDicePerLevel` only touches one `recipeIndex`.
  Shipped with only the Clenched Fist scaling; Grasping Hand's 2d6/level
  is in `higherLevel` text. Would want a list-of-upcasts or "multiple
  recipes scale" shape. *Files:* `arcane_hand`.
- **Damage-type-choice upcast on one recipe of a pair** — Flame Strike
  scales "1d6 to fire OR radiant, your choice per cast" every slot
  level. Currently ships with the upcast on the fire recipe only; the
  player choice at upcast time isn't modeled. *Files:* `flame_strike`.
- **Persistent cloud/wall damage** — Cloudkill/Wall of Fire/Insect
  Plague ship the initial-cast damage recipe; the "each creature
  entering the area takes damage again on subsequent turns" is
  text-only. Recurring per-turn AoE damage would need a new mechanic
  (a battlefield zone with a trigger). *Files:* `cloudkill`,
  `wall_of_fire`, `insect_plague` (L4/L5). Also affects
  `blade_barrier`, `wall_of_ice`, `wall_of_thorns` (L6).
- **Two-recipe upcast (dual damage rolls)** — Wall of Thorns' SRD
  higher-level rule is "BOTH damage rolls (piercing entry AND slashing
  movement) increase by 1d8 per slot level above 6". `upcastEffect`
  ships with the piercing scaling only; slashing stays flat. Same
  underlying gap as Arcane Hand's multi-mode scaling. *Files:*
  `wall_of_thorns`.
- **Flat + multiplier damage shape** — Disintegrate is `10d6 + 40`
  (dice + flat). The `rawDamage.dice` field accepts the compound
  `"10d6+40"` string, which the DiceFormulaParser should handle, but
  worth flagging if it doesn't. *Files:* `disintegrate`.
- **Concentration in days** — Find the Path is concentration up to 1
  day, encoded as `concentration 1440` minutes. Same shape gap as the
  earlier `hours` durations. *Files:* `find_the_path`.
- **Multi-mode ray tables** — Prismatic Spray fires 8 rays; player
  rolls d8 per target to pick color. Damage rays (Red/Orange/Yellow/
  Green/Blue) ship as a single `rawDamage` recipe with
  `damageTypeChoices` for the 5 elements; the Indigo (Restrained →
  Petrified), Violet (Blinded → planar banishment), and White (reroll
  two) rays aren't modeled at all — text-only. Same underlying "roll
  a table of effects" mechanic could recur for Chaos Bolt-style spells.
  *Files:* `prismatic_spray`.
- **HP-threshold effects** — Divine Word applies different conditions
  based on the target's current HP (≤50 Deafened, ≤40 +Blinded, ≤30
  +Stunned, ≤20 death; planar banish for outsiders). No structured
  way to express "outcome branches on target's remaining HP" —
  text-only. *Files:* `divine_word`.
- **Recurring per-turn attack** — Arcane Sword's initial attack ships
  as `[spellAttack, rawDamage]`, but the "each subsequent turn, use
  your Bonus Action to move the sword and attack again" is text —
  we don't model a persistent conjured entity that repeats an attack
  action. Same shape would apply if we ever added the Bigby's Hand
  attack modes as recurring actions. *Files:* `arcane_sword`.
- ~~**Long-range in miles**~~: NOT a gap — see the miles retraction
  above. Project Image now uses `{"type":"miles","value":500}`.
- **Multi-day durations** — Mirage Arcane's 10-day duration flattens
  to `hours 240`; Simulacrum, Sequester, and Symbol ship as
  `instantaneous` with "until dispelled" in prose. Same underlying
  `SpellDuration.days` / `.untilDispelled` gap. *Files:*
  `mirage_arcane`, `simulacrum`, `sequester`, `symbol`.
- **Rune / glyph tables** — Symbol has 8 rune modes (Death, Discord,
  Fear, Hopelessness, Insanity, Pain, Sleep, Stunning). Only Death's
  damage roll (`10d10` necrotic) is expressed as a recipe; the other
  7 modes are text-only. Same shape as Prismatic Spray's ray table
  and Chaos Bolt's damage table. *Files:* `symbol`.
- **Upcast changes duration (not dice)** — Dominate Monster's 9th-slot
  upcast extends concentration from 1 hour to 8 hours, no damage
  scaling. `UpcastEffect` only expresses `extraDicePerLevel` /
  `extraTargetsPerLevel`; no "swap duration at slot X" shape.
  Text-only in `higherLevel`. *Files:* `dominate_monster`.
- **Recurring-then-decaying wall damage** — Tsunami's wall does 6d10
  bludgeoning on cast, then 5d10 to any Huge-or-smaller creature it
  enters on subsequent turns, with the damage decreasing by 1d10 per
  round (5d10 → 4d10 → 3d10 → ... → 1d10 → 0). Same underlying
  "persistent wall damage" gap plus a novel decay shape. *Files:*
  `tsunami`.
- ~~**Retry-save cadence in days**~~: Feeblemind removed from SRD 5.2.1.
  The 8th-level replacement is **Befuddlement** (int/cha reduced to 1,
  cannot cast/understand language, retries every 30 days). Same shape
  gap as before — "retry every N days" still not encodable — but under
  a different name. *Files:* `befuddlement`.
- ~~**Unlimited / same-plane range**~~: NOT a gap for unlimited —
  `.unlimited` exists on `SpellRange`. Telepathy/Sending/Dream now
  use `{"type":"unlimited"}`. A dedicated `.samePlane` case is still
  wanted for the semantic ("works within the same plane, not across
  planes"), but the current `.unlimited` displays correctly.
- **Line-of-sight range** — Tsunami's SRD range is "sight" (up to the
  DM's discretion). Flattened to `feet 10000` as a stand-in. Need a
  `SpellRange.sight` case that defers to DM adjudication. *Files:*
  `tsunami`, `storm_of_vengeance`.
- **Multi-round scripted timeline** — Storm of Vengeance runs a
  10-round choreography: R1 thunderclap (2d6), R2 acid rain (1d6),
  R3 six lightning bolts (10d6 each), R4 hailstones (2d6), R5-10
  wind/rain effects. Shipped with the R3 lightning as the headline
  recipe; the other rounds are text-only. Would need a
  "round-scheduled effect" mechanic that fires different recipes on
  specific rounds of the spell's concentration. *Files:*
  `storm_of_vengeance`.
- **Concentration converts to permanent** — True Polymorph and
  Antipathy/Sympathy both work as concentration for the full duration
  and then become permanent (unlimited). No way to express "if the
  caster concentrates for the entire duration, the effect stops
  needing concentration". Text-only. *Files:* `true_polymorph`,
  `antipathy_sympathy`.
- **Extra caster-only turns** — Time Stop grants the caster 1d4+1
  additional consecutive turns. No structured way to grant
  "self-only extra turns". Text-only. *Files:* `time_stop`.
- **Spell-of-lower-level duplication** — Wish's primary use is to
  duplicate any spell of 8th level or lower without meeting
  requirements. No structured way to express "cast another spell as
  part of this one". Text-only, DM-adjudicated. *Files:* `wish`.
- **Per-cast escalating stress damage** — Wish's non-duplicate use
  imposes 1d10 necrotic per level of the (implied) duplicated spell,
  then 1d10 per level per subsequent spell cast until Long Rest, plus
  a 33% chance of losing Wish forever. No structured way to encode
  "recurring self-damage rider tied to spellcasting". Text-only.
  *Files:* `wish`.
- **Mode-selection with mode-specific counters** — Imprisonment's 6
  modes (Burial, Chaining, Hedged Prison, Minimus Containment,
  Slumber, Wall of Force) each have their own end-condition. Same
  underlying "roll a table of effects" gap as Symbol / Prismatic
  Spray, but on the *caster's* choice at cast time rather than a d8
  roll. *Files:* `imprisonment`.
- **Layered wall counter-conditions** — Prismatic Wall's 7 layers
  each require a specific effect to disable (Red = cold, Orange =
  strong wind, Yellow = force damage, etc.). Same shape gap as
  Prismatic Spray's ray table, but persistent and sequential.
  *Files:* `prismatic_wall`.
