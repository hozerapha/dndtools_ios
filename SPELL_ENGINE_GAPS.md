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
