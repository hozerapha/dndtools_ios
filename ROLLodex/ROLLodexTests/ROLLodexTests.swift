import Testing
import Foundation
@testable import ROLLodex

@MainActor
struct ROLLodexTests {

    @Test func bundledContentLoads() {
        let store = ContentStore()
        #expect(!store.classes.isEmpty)
        #expect(!store.species.isEmpty)
        #expect(!store.backgrounds.isEmpty)
        #expect(!store.weapons.isEmpty)
        #expect(!store.spells.isEmpty)
        #expect(store.classDefinition(id: "fighter")?.name == "Fighter")
    }
}
