import Foundation

struct Preset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var formula: DiceFormula

    init(id: UUID = UUID(), name: String, formula: DiceFormula) {
        self.id = id
        self.name = name
        self.formula = formula
    }
}
