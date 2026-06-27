# ROLLodex TDD Test Coverage Expansion — Summary

This document lists the new and updated automated test files added to `ROLLodex/ROLLodexTests/`.

## New test files

| File | Domain | What it covers |
|------|--------|----------------|
| `HistoryStoreTests.swift` | Store persistence | Recording order, `clear()`, `removeFirst()`, 200-entry cap, `UserDefaults` round-trip, malformed JSON fallback, duplicate recording behavior. |
| `PresetStoreTests.swift` | Store persistence | Add/delete, load/save round-trip, duplicate names, default empty state, backward-compatible `Preset` decode without `typedModifiers`, full encoder round-trip. |
| `PendingRollStoreTests.swift` | Cross-tab state | Enqueue/clear `pending`, `followUps`, `pendingCharacterID`, `pendingCostsToApply`, consumption order, idempotency, `PendingFollowUp.chainedDamage` convenience. |
| `DiceFormulaParserErrorTests.swift` | Parser error paths | Every `DiceFormulaParser.ParseError` case: empty input, invalid token, non-standard die size, overflow, negative/non-positive count, unknown modifier, modifier out of range, reroll threshold that always triggers, unknown damage type, invalid minimum, malformed typed-group syntax. |
| `CharacterCreationFinalizationTests.swift` | Character creation | `CharacterDraft.toCharacter()` plus real `ContentStore`-driven finalization: background ASI application & 20 cap, background skill proficiencies, class skill choices seeded as feature selections, class save/armor/weapon/tool proficiencies, real hit-die HP, species selection carry-over, and starting spell seeding for wizards. |
| `InventoryStateTests.swift` | Inventory/equipment/currency | Equip/unequip toggle, attuned toggle, base attunement limit of 3, override limit, attuned-count vs. limit, `CharacterCalculator.attunementEligibility` (`.notRequired`, `.eligible`, `.blocked`), `Currency.totalCopper` conversion, item-quantity weight totals, inventory weight totals, stack identity by UUID. |
| `CharacterSpellsTests.swift` | Spellbook/prepared/known | Independent prepared/known/spellbook lists, cantrip vs. leveled separation via `ContentStore.allSpells`, level-then-name sorting, prepared/known counts, empty state. |
| `ContentStoreEdgeCaseTests.swift` | Content store edge cases | Bundled content loads for every category, malformed imported JSON ignored, filename sanitization on import, imported entries shadowing bundled IDs, filename-order shadow tie-breaking, removing a pack restores bundled content, `reload()` idempotence. |
| `RollResolutionModeTests.swift` | Settings enum | Raw values, labels, system images, stable default storage key, raw-value round-trip for all cases. |
| `CurrencyTests.swift` | Currency model | `totalCopper` conversion, empty currency, single-coin conversions, negative-value arithmetic, equality. |
| `DamageTypeColorTests.swift` | Damage type UI mapping | Every `DamageType` produces a non-clear glow `UIColor`; exact component checks for fire, cold, and force. |

## Updated test files

| File | Changes |
|------|---------|
| `DiceRollerTests.swift` | Added deterministic coverage for `rerollOnceIfAtMost` (`resultFrom` and roll-loop floor), d100 keep/drop and range, multi-group keep/drop, and tied-value keep/drop stability. |
| `CharacterStoreTests.swift` | Added `exportedCharacterImportsWithFreshID()` — exports a character via `ExportedCharacter.exported(as: .json)`, writes the data, imports it through `CharacterStore.importCharacter(from:)`, and asserts a fresh ID plus persisted fields. |
| `DamageTypingTests.swift` | Added untyped-modifier edge cases (negative modifier attached to sole type, zero modifier omitted) and a `RollResult` Codable round-trip test. |
| `ROLLodexTests.swift` | Replaced the empty placeholder `example()` test with a real smoke test verifying that the bundled SRD content loads core categories. |

## Notes

- All new tests follow the project's Swift Testing conventions (`import Testing`, `@Test`, `#expect`, `@testable import ROLLodex`).
- No production Swift source files were modified; only test files and this summary.
- No markdown project documentation was edited.
