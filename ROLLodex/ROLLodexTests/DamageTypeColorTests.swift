import Testing
import UIKit
@testable import ROLLodex

struct DamageTypeColorTests {

    private func components(for type: DamageType) -> [CGFloat]? {
        type.glowColor.cgColor.components
    }

    @Test func fireGlowIsOrangeRed() {
        let comps = components(for: .fire)
        #expect(comps?[0] == 1.0)
        #expect(comps?[1] == 0.5)
        #expect(comps?[2] == 0.1)
    }

    @Test func coldGlowIsIceCyan() {
        let comps = components(for: .cold)
        #expect(comps?[0] == 0.45)
        #expect(comps?[1] == 0.85)
        #expect(comps?[2] == 1.0)
    }

    @Test func forceGlowIsViolet() {
        let comps = components(for: .force)
        #expect(comps?[0] == 0.75)
        #expect(comps?[1] == 0.55)
        #expect(comps?[2] == 1.0)
    }

    @Test func everyDamageTypeHasAGlowColor() {
        let types: [DamageType] = [
            .bludgeoning, .piercing, .slashing, .acid, .cold,
            .fire, .force, .lightning, .necrotic, .poison,
            .psychic, .radiant, .thunder
        ]
        for type in types {
            let color = type.glowColor
            #expect(color != .clear)
            #expect(color.cgColor.components?.count == 4)
        }
    }
}
