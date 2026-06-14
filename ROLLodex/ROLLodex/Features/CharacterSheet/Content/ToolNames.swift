import Foundation

/// Tools are bare string ids in content (there's no Tool enum/registry), so
/// the UI needs a readable name for them. Known tools get a curated label
/// (apostrophes and all); anything else falls back to title-casing the id so
/// homebrew tools still render legibly instead of as `snake_case`.
enum ToolNames {
    private static let known: [String: String] = [
        "thieves_tools": "Thieves' Tools",
        "calligraphers_supplies": "Calligrapher's Supplies",
        "gaming_set": "Gaming Set",
        "herbalism_kit": "Herbalism Kit",
        "disguise_kit": "Disguise Kit",
        "poisoners_kit": "Poisoner's Kit",
    ]

    static func display(_ id: String) -> String {
        if let name = known[id] { return name }
        return id
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }
}
