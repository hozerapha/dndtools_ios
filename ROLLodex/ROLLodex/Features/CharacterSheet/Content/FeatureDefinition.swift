import Foundation

struct FeatureDefinition: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let actionRecipes: [ActionRecipe]
    /// If non-nil, this feature sets the character's attunement slot count
    /// while it is active. The calculator picks the highest value across all
    /// active features (Artificer's "Magic Item Adept" → 4, "Master" → 5,
    /// "Savant" → 6). Absent means the feature doesn't touch attunement.
    let attunementSlots: Int?
    /// If present, this feature grants a charge / use pool. The pool's `id`
    /// keys into the character's `resources` map; absence means the feature
    /// has no consumable cost (always-on, like Fighting Style).
    let resource: ResourceDefinition?
    /// Proficiencies this feature automatically grants when unlocked. Applied
    /// during character creation and level-up so the sheet reflects them
    /// immediately (e.g. Rogue's Slippery Mind → WIS/CHA saves).
    let grantsProficiencies: [ProficiencyKey]?
    /// Informational categorization. Defaults to `.passive` so older JSON
    /// without a `kind` key still decodes; the Features tab uses this to
    /// pick the right header icon and to decide whether to show toggle
    /// affordances. The kind is purely descriptive — the mechanical surface
    /// (resource, selection, actionRecipes) drives real behavior.
    let kind: FeatureKind
    /// If present, the Features tab renders a picker so the player can choose
    /// N options. Their picks are persisted under `Character.featureSelections[selection.id]`.
    let selection: FeatureSelection?
    /// Turn cost when the feature is tapped from the action grid. Nil for
    /// purely passive features. JSON defaults to `.action` when the feature
    /// has tappable recipes but doesn't declare a cost.
    let actionCost: ActionCost?
    /// Standing rider this feature contributes — Sneak Attack's opt-in
    /// damage rider, future Rage's automatic STR-damage boost, etc. Nil for
    /// features without a trigger hook (most features).
    let triggeredEffect: TriggeredEffect?
    /// Minimum floor this feature imposes on the character's skill checks
    /// (Reliable Talent: treat a d20 ≤ 9 as 10 from Rogue level 7). The floor
    /// only applies to skills the character is proficient in — that gate
    /// stays in the interpreter. Resolved against the owning class level so a
    /// future subclass could grant it at a different level without code.
    let skillCheckMinimum: LevelScaledValue?
    /// Whether this feature should appear as a tappable row in the action
    /// grid. False for reactive features the dice tab handles after a roll
    /// (Stroke of Luck) — they still own their resource pool, they just
    /// don't get a do-nothing button. Defaults true.
    let surfacesAsAction: Bool
    /// Named action options this feature confers, shown on the Actions tab
    /// grouped by economy (Cunning Action → Dash / Disengage / Hide). Each
    /// may carry its own roll. Empty for features that grant no discrete
    /// action options.
    let grantedActions: [GrantedAction]
    /// Spells this feature/trait always grants (Tiefling Otherworldly Presence
    /// → Thaumaturgy). Always-prepared; see `SpellGrant`. For choice-gated
    /// grants (a lineage's spells), put the grant on the `SelectionOption`
    /// instead. Empty for features with no spell payload.
    let grantsSpells: [SpellGrant]

    private enum CodingKeys: String, CodingKey {
        case id, name, description, actionRecipes
        case attunementSlots, resource, grantsProficiencies, kind, selection, actionCost, triggeredEffect
        case skillCheckMinimum, surfacesAsAction, grantedActions, grantsSpells
    }

    init(
        id: String,
        name: String,
        description: String,
        actionRecipes: [ActionRecipe] = [],
        attunementSlots: Int? = nil,
        resource: ResourceDefinition? = nil,
        grantsProficiencies: [ProficiencyKey]? = nil,
        kind: FeatureKind = .passive,
        selection: FeatureSelection? = nil,
        actionCost: ActionCost? = nil,
        triggeredEffect: TriggeredEffect? = nil,
        skillCheckMinimum: LevelScaledValue? = nil,
        surfacesAsAction: Bool = true,
        grantedActions: [GrantedAction] = [],
        grantsSpells: [SpellGrant] = []
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.actionRecipes = actionRecipes
        self.attunementSlots = attunementSlots
        self.resource = resource
        self.grantsProficiencies = grantsProficiencies
        self.kind = kind
        self.selection = selection
        self.actionCost = actionCost
        self.triggeredEffect = triggeredEffect
        self.skillCheckMinimum = skillCheckMinimum
        self.surfacesAsAction = surfacesAsAction
        self.grantedActions = grantedActions
        self.grantsSpells = grantsSpells
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decode(String.self, forKey: .description)
        actionRecipes = try c.decodeIfPresent([ActionRecipe].self, forKey: .actionRecipes) ?? []
        attunementSlots = try c.decodeIfPresent(Int.self, forKey: .attunementSlots)
        resource = try c.decodeIfPresent(ResourceDefinition.self, forKey: .resource)
        grantsProficiencies = try c.decodeIfPresent([ProficiencyKey].self, forKey: .grantsProficiencies)
        selection = try c.decodeIfPresent(FeatureSelection.self, forKey: .selection)
        triggeredEffect = try c.decodeIfPresent(TriggeredEffect.self, forKey: .triggeredEffect)
        skillCheckMinimum = try c.decodeIfPresent(LevelScaledValue.self, forKey: .skillCheckMinimum)
        surfacesAsAction = try c.decodeIfPresent(Bool.self, forKey: .surfacesAsAction) ?? true
        grantedActions = try c.decodeIfPresent([GrantedAction].self, forKey: .grantedActions) ?? []
        grantsSpells = try c.decodeIfPresent([SpellGrant].self, forKey: .grantsSpells) ?? []
        // Explicit JSON wins; otherwise default to .action when the feature
        // surfaces a tappable recipe, and nil for pure passives.
        if let declared = try c.decodeIfPresent(ActionCost.self, forKey: .actionCost) {
            actionCost = declared
        } else {
            actionCost = actionRecipes.isEmpty && resource == nil ? nil : .action
        }
        // Fall back to a sensible auto-kind when JSON omits it: a feature
        // with a selection is `.selection`, one with a resource is `.active`,
        // and everything else is `.passive`. Explicit `kind` always wins.
        if let declared = try c.decodeIfPresent(FeatureKind.self, forKey: .kind) {
            kind = declared
        } else if selection != nil {
            kind = .selection
        } else if resource != nil {
            kind = .active
        } else {
            kind = .passive
        }
    }
}
