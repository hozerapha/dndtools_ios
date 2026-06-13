import Foundation

/// Validates an imported `ContentPack` before it's written to disk. The same
/// invariants the bundled-content lint test asserts (roadmap item 9e) —
/// non-empty unique ids, parseable dice strings — surfaced here as a list of
/// human-readable issues for an error sheet instead of a failing test.
///
/// Pure decode failures (unknown recipe type, malformed structure) are caught
/// upstream by `JSONDecoder` throwing; this catches the well-formed-but-wrong
/// packs that decode fine yet would misbehave at runtime.
enum ContentValidator {

    /// Returns an empty array when the pack is valid; otherwise one string per
    /// problem, ready to render in a sheet.
    static func validate(_ pack: ContentPack) -> [String] {
        var issues: [String] = []

        if pack.entryCount == 0 {
            issues.append("The pack is empty — it defines no content.")
        }

        // Per-category id hygiene: non-empty, unique within its section.
        checkIDs(pack.classes, "class", &issues)
        checkIDs(pack.species, "species", &issues)
        checkIDs(pack.backgrounds, "background", &issues)
        checkIDs(pack.weapons, "weapon", &issues)
        checkIDs(pack.armor, "armor", &issues)
        checkIDs(pack.gear, "item", &issues)
        checkIDs(pack.spells, "spell", &issues)
        checkIDs(pack.conditions, "condition", &issues)

        // Dice strings must parse — the single highest-value content check.
        for weapon in pack.weapons ?? [] {
            checkDice(weapon.damage, "weapon \(weapon.id) damage", &issues)
            if let v = weapon.versatileDamage {
                checkDice(v, "weapon \(weapon.id) versatile damage", &issues)
            }
            for recipe in weapon.actionRecipes {
                checkRecipeDice(recipe, "weapon \(weapon.id)", &issues)
            }
        }
        for spell in pack.spells ?? [] {
            for recipe in spell.actionRecipes {
                checkRecipeDice(recipe, "spell \(spell.id)", &issues)
            }
        }
        for cls in pack.classes ?? [] {
            for (level, features) in cls.levelFeatures {
                for feature in features {
                    for recipe in feature.actionRecipes {
                        checkRecipeDice(recipe, "\(cls.id) L\(level) \(feature.id)", &issues)
                    }
                }
            }
        }

        return issues
    }

    // MARK: - Helpers

    private static func checkIDs<T: Identifiable>(
        _ items: [T]?, _ kind: String, _ issues: inout [String]
    ) where T.ID == String {
        guard let items else { return }
        var seen = Set<String>()
        for item in items {
            if item.id.trimmingCharacters(in: .whitespaces).isEmpty {
                issues.append("A \(kind) entry has an empty id.")
            } else if !seen.insert(item.id).inserted {
                issues.append("Duplicate \(kind) id \"\(item.id)\".")
            }
        }
    }

    private static func checkRecipeDice(
        _ recipe: ActionRecipe, _ context: String, _ issues: inout [String]
    ) {
        switch recipe {
        case .heal(let dice, _, _, _):      checkDice(dice, "\(context) heal", &issues)
        case .rawDamage(let dice, _, _, _): checkDice(dice, "\(context) damage", &issues)
        default:                            break
        }
    }

    private static func checkDice(_ dice: String, _ context: String, _ issues: inout [String]) {
        if (try? DiceFormulaParser().parse(dice)) == nil {
            issues.append("Unparseable dice \"\(dice)\" in \(context).")
        }
    }
}
