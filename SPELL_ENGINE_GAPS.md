# Spell engine gaps (post-catalog polish todo)

Running log of spells whose mechanics or upcast our schema currently
can't express. Populated as I ship the SRD 5.2.1 spell catalog. Every
entry ships with the affected mechanic in the `description` /
`higherLevel` prose so players can adjudicate manually.

## Already known before catalog completion

- **Smite riders** (Blinding Smite +1d8/level, Branding Smite +1d6/level,
  Wrathful Smite text). `grantsTriggeredEffect` has no upcast hook —
  the rider's dice stay flat. Fix: add optional
  `dicePerSlotLevel`/`levelsPerBonus` on `AddDamageDice`, and remember
  the cast slot on `ActiveEffect` so the resolver can scale.
- **SpellRange.miles**: Clairvoyance's 1-mile range flattens to `feet:
  5280`. Add a `miles` case to `SpellRange`.
- **SpellDuration.days**: Gentle Repose's 10 days flattens to `hours:
  240`. Same story with Nondetection, Magic Circle at high slot levels.
- **Extra-ray upcast**: Scorching Ray gains 1 ray per slot level, not
  dice per level. No structured way to express "extra recipe applications
  per level" — currently text-only in `higherLevel`.
- **Walls / cloud persistence**: initial-cast damage lands via
  `rawDamage`, but the per-turn re-entry damage (Sleet Storm,
  Stinking Cloud, Wall of Fire, Cloudkill, Wall of Ice) is text-only.
  Would need a "recurring effect" mechanic tied to a battlefield zone.
- **Aura-adjacent riders**: Crusader's Mantle (+1d4 radiant to weapon
  attacks from allies in a 30-ft aura), Aura of Purity, Aura of Life.
  `selfBuff` on `SpellEffect` doesn't cover "grant a weapon-damage
  rider to allies within range" — leave as text.
- **Elemental Weapon** (+1 attack/+1d4 element, upgraded at 5th/7th).
  `selfBuff` doesn't cover attack-bonus + element rider on a specific
  weapon; text-only.
- **Magic Weapon** (+1/+2/+3 by slot). Same story — no rider slot for
  "give this weapon +N attack/damage".

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
