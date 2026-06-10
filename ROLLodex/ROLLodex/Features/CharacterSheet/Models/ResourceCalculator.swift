import Foundation

/// A single pool surfaced to the UI: definition + computed `max` + the
/// character's current value + a friendly source label.
struct ResolvedResource: Identifiable, Equatable {
    let definition: ResourceDefinition
    let max: Int
    let current: Int
    let sourceLabel: String

    var id: String { definition.id }

    var isExhausted: Bool { current <= 0 }
    var isFull: Bool { current >= max }
}

/// One refresh that needs a dice roll resolved by the user (or the system,
/// depending on `RollResolutionMode`). Returned by `applyRest` so the rest
/// flow can prompt for each.
struct PendingRefresh: Identifiable, Equatable {
    let resourceID: String
    let resourceName: String
    let formula: String
    let max: Int
    let currentBeforeRefresh: Int

    var id: String { resourceID }
}

/// Pure functions over the character + content store. MainActor-isolated
/// because the underlying ContentStore reads are MainActor.
@MainActor
enum ResourceCalculator {

    // MARK: - Enumeration

    /// Every pool the character has access to right now: features at or below
    /// each class's level, plus equipped items (Phase K). Phase I covers
    /// features only — items hook in once they declare their own resource.
    static func availableResources(
        character: Character,
        content: ContentStore
    ) -> [ResolvedResource] {
        var resolved: [ResolvedResource] = []

        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolvedFeature in cls.resolvedFeatures(
                throughClassLevel: entry.level,
                subclassID: subclassID
            ) {
                guard let definition = resolvedFeature.feature.resource else { continue }
                let maxValue = definition.max.value(
                    classLevel: entry.level,
                    characterLevel: character.level
                )
                let current = currentClamped(
                    character: character,
                    resourceID: definition.id,
                    max: maxValue
                )
                let sourceName = resolvedFeature.subclassName ?? cls.name
                resolved.append(ResolvedResource(
                    definition: definition,
                    max: maxValue,
                    current: current,
                    sourceLabel: "\(sourceName) \(resolvedFeature.feature.name)"
                ))
            }

            // Spell slots: synthesize one resource per slot level from the
            // class's slot table. Refresh trigger = long rest for full
            // casters, short rest for pact magic.
            resolved.append(contentsOf: synthesizedSlotResources(for: entry, in: cls, character: character))
        }

        // Items the character is carrying. We include carried-but-unequipped
        // items so consumables (scrolls, potions w/ charges) still appear in
        // the resources card — the action grid filters separately to keep
        // its rows scoped to equipped items. Items that require attunement
        // are skipped until they're actually attuned, since you can't spend
        // their charges otherwise. Two stacks of the same item share one
        // pool (per Phase K.1's `<itemID>_charges` convention), so de-dupe
        // by resource id rather than emitting two rows.
        var seen = Set(resolved.map(\.id))
        for inv in character.inventory {
            guard let definition = content.itemResource(forItemID: inv.itemID) else { continue }
            if content.attunementRule(forItemID: inv.itemID) != nil && !inv.attuned { continue }
            guard !seen.contains(definition.id) else { continue }
            seen.insert(definition.id)
            let maxValue = definition.max.value(
                classLevel: character.level,
                characterLevel: character.level
            )
            let current = currentClamped(
                character: character,
                resourceID: definition.id,
                max: maxValue
            )
            let itemName = content.itemName(forItemID: inv.itemID) ?? inv.itemID
            resolved.append(ResolvedResource(
                definition: definition,
                max: maxValue,
                current: current,
                sourceLabel: itemName
            ))
        }

        return resolved
    }

    private static func synthesizedSlotResources(
        for entry: ClassEntry,
        in cls: ClassDefinition,
        character: Character
    ) -> [ResolvedResource] {
        guard let spellcasting = cls.spellcasting else { return [] }
        let slots = spellcasting.slotTable.slots(atClassLevel: entry.level)
        guard !slots.isEmpty else { return [] }

        let isPact = spellcasting.slotTable.isPactMagic
        let trigger: RefreshTrigger = isPact ? .shortRest : .longRest

        return slots.sorted(by: { $0.key < $1.key }).map { (slotLevel, count) in
            let id = "\(cls.id)_slot_\(slotLevel)"
            let definition = ResourceDefinition(
                id: id,
                name: slotLabel(level: slotLevel),
                max: .flat(count),
                refreshOn: trigger,
                refreshAmount: .all,
                displayHint: .spellSlot(level: slotLevel)
            )
            let current = currentClamped(character: character, resourceID: id, max: count)
            return ResolvedResource(
                definition: definition,
                max: count,
                current: current,
                sourceLabel: "\(cls.name) (L\(entry.level))"
            )
        }
    }

    private static func slotLabel(level: Int) -> String {
        switch level {
        case 1: return "1st-Level Slots"
        case 2: return "2nd-Level Slots"
        case 3: return "3rd-Level Slots"
        default: return "\(level)th-Level Slots"
        }
    }

    // MARK: - Reads

    /// Current value for `resourceID`, defaulting to the resource's max when
    /// the character has no recorded state for it (a freshly-granted feature
    /// starts full). Result is always clamped to `[0, max]`.
    static func current(
        character: Character,
        content: ContentStore,
        resourceID: String
    ) -> Int {
        guard let resolved = availableResources(character: character, content: content)
            .first(where: { $0.definition.id == resourceID }) else { return 0 }
        return resolved.current
    }

    private static func currentClamped(
        character: Character,
        resourceID: String,
        max: Int
    ) -> Int {
        let raw = character.resources[resourceID]?.current ?? max
        return Swift.max(0, Swift.min(raw, max))
    }

    // MARK: - Spell slots

    /// Lowest spell-slot level in `minLevel...maxLevel` with at least one
    /// slot remaining, across every slot pool the character has (class-
    /// agnostic via the `.spellSlot` display hint, so a multiclass caster's
    /// cheapest eligible slot wins). Nil when nothing in range is available —
    /// callers use that to suppress slot-fueled chips (Divine Smite).
    static func lowestAvailableSlotLevel(
        min minLevel: Int,
        max maxLevel: Int,
        character: Character,
        content: ContentStore
    ) -> Int? {
        availableResources(character: character, content: content)
            .compactMap { resolved -> Int? in
                guard case .spellSlot(let level)? = resolved.definition.displayHint,
                      (minLevel...maxLevel).contains(level),
                      resolved.current > 0 else { return nil }
                return level
            }
            .min()
    }

    /// Spend one spell slot of exactly `level`. Returns false when no pool of
    /// that level has a slot left.
    @discardableResult
    static func consumeSpellSlot(
        level: Int,
        in character: inout Character,
        content: ContentStore
    ) -> Bool {
        let pools = availableResources(character: character, content: content)
        guard let resolved = pools.first(where: { resolved in
            if case .spellSlot(let l)? = resolved.definition.displayHint {
                return l == level && resolved.current > 0
            }
            return false
        }) else { return false }
        return consume(amount: 1, from: resolved.id, in: &character, content: content)
    }

    // MARK: - Mutations

    /// Decrement a pool by `amount`. Returns whether the consumption succeeded
    /// (it fails when current < amount). Callers should check first via
    /// `current(...)` to grey out the UI.
    @discardableResult
    static func consume(
        amount: Int,
        from resourceID: String,
        in character: inout Character,
        content: ContentStore
    ) -> Bool {
        let now = current(character: character, content: content, resourceID: resourceID)
        guard now >= amount, amount > 0 else { return false }
        character.resources[resourceID, default: ResourceState(current: now)].current = now - amount
        return true
    }

    /// Refresh applicable pools and return any that need a dice roll the
    /// user has to resolve (`.roll(formula:)` amounts). Synchronous changes
    /// (`.all`, `.fixed`, `.byClassLevel`) are applied immediately.
    ///
    /// 5e RAW: a long rest fills any non-roll resource to max regardless of
    /// the short-rest bump amount (e.g. Second Wind has `fixed(1)` on short
    /// rest but a long rest restores both uses). Roll-typed amounts (Wand of
    /// Magic Missiles' `1d6+1` at dawn) still get rolled on a long rest, since
    /// the dice are the whole point.
    static func applyRest(
        _ kind: RestKind,
        to character: inout Character,
        content: ContentStore
    ) -> [PendingRefresh] {
        var pending: [PendingRefresh] = []
        let resources = availableResources(character: character, content: content)

        for resolved in resources {
            guard resolved.definition.refreshOn.fires(on: kind) else { continue }
            if case .roll(let formula) = resolved.definition.refreshAmount {
                pending.append(PendingRefresh(
                    resourceID: resolved.id,
                    resourceName: resolved.definition.name,
                    formula: formula,
                    max: resolved.max,
                    currentBeforeRefresh: resolved.current
                ))
                continue
            }

            let bump = bumpAmount(
                resolved: resolved,
                kind: kind,
                character: character,
                content: content
            )
            let next = Swift.min(resolved.max, resolved.current + bump)
            writeCurrent(character: &character, resourceID: resolved.id, to: next)
        }

        // Long rest also fully heals (5e RAW) and clears temp HP. HP is its
        // own concern, not a resource, so we handle it here in one place.
        if kind == .long {
            character.currentHP = character.maxHP
            character.tempHP = 0
        }

        return pending
    }

    private static func bumpAmount(
        resolved: ResolvedResource,
        kind: RestKind,
        character: Character,
        content: ContentStore
    ) -> Int {
        // Long rest: refill to max for any non-roll amount.
        if kind == .long {
            return resolved.max - resolved.current
        }
        switch resolved.definition.refreshAmount {
        case .all:
            return resolved.max - resolved.current
        case .fixed(let n):
            return n
        case .byClassLevel(let table):
            let lookup = LevelScaledValue.byClassLevel(table)
            return lookup.value(
                classLevel: classLevelFor(resourceID: resolved.id, character: character, content: content),
                characterLevel: character.level
            )
        case .roll:
            return 0  // handled by the pending-refresh branch above
        }
    }

    /// Apply a roll-resolved refresh amount. Called by the rest flow after the
    /// user types / rolls / hides each pending refresh.
    static func applyResolvedRefresh(
        resourceID: String,
        amount: Int,
        in character: inout Character,
        content: ContentStore
    ) {
        let resources = availableResources(character: character, content: content)
        guard let resolved = resources.first(where: { $0.definition.id == resourceID }) else { return }
        let next = Swift.min(resolved.max, resolved.current + Swift.max(0, amount))
        writeCurrent(character: &character, resourceID: resourceID, to: next)
    }

    /// Manual setter for the resources card's `−` / `+` buttons (DM correction).
    static func setCurrent(
        _ value: Int,
        for resourceID: String,
        in character: inout Character,
        content: ContentStore
    ) {
        let resources = availableResources(character: character, content: content)
        guard let resolved = resources.first(where: { $0.definition.id == resourceID }) else { return }
        let clamped = Swift.max(0, Swift.min(value, resolved.max))
        writeCurrent(character: &character, resourceID: resourceID, to: clamped)
    }

    // MARK: - Helpers

    private static func writeCurrent(
        character: inout Character,
        resourceID: String,
        to value: Int
    ) {
        character.resources[resourceID] = ResourceState(current: value)
    }

    /// Find which class entry granted a resource so byClassLevel scaling
    /// resolves correctly. Walks subclass features too so subclass-granted
    /// resources scale by the right class level. Falls back to
    /// character.level if not found.
    private static func classLevelFor(
        resourceID: String,
        character: Character,
        content: ContentStore
    ) -> Int {
        for entry in character.classEntries {
            guard let cls = content.classDefinition(id: entry.classID) else { continue }
            let subclassID = character.featureSelections[
                ClassDefinition.subclassSelectionID(forClassID: entry.classID)
            ]?.first
            for resolved in cls.resolvedFeatures(throughClassLevel: entry.level, subclassID: subclassID) {
                if resolved.feature.resource?.id == resourceID {
                    return entry.level
                }
            }
        }
        return character.level
    }
}
