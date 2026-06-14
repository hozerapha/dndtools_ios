import Foundation

/// Canonical ids for the handful of features whose *mechanics* are still
/// resolved in Swift (fighting styles, weapon mastery, expertise). Content
/// authors must spell these exactly; collecting them here makes the coupling
/// grep-able and gives one place to change if a string moves.
///
/// This is the cheap first step of roadmap item 9c — it removes scattered
/// string literals. Making fighting-style *effects* fully data-driven (so a
/// homebrew style can add bonuses without Swift) is the larger, separate lift.
enum FeatureIDs {
    /// `FeatureSelection.id` for the single fighting-style pick.
    static let fightingStyle = "fighting_style"
    /// `FeatureSelection.id` for the weapon-mastery weapon picks.
    static let weaponMastery = "weapon_mastery"
    /// Substring marker on any expertise selection id (`expertise`,
    /// `expertise_6`, …) — the calculator treats a skill listed under such a
    /// selection as having expertise.
    static let expertiseMarker = "expertise"
    /// Substring marker on a class's level-1 skill-proficiency selection id
    /// (`rogue_class_skills`, …) — the calculator treats a skill listed under
    /// such a selection as proficient, resolved live from `featureSelections`
    /// (same content-free trick as expertise) so it's re-editable anywhere.
    static let classSkillsMarker = "class_skills"

    /// Option ids inside the `fighting_style` selection whose mechanical
    /// effects the calculator / interpreter apply directly.
    enum FightingStyle {
        static let archery = "archery"
        static let defense = "defense"
        static let dueling = "dueling"
    }
}
