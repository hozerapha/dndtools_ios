import Testing
import Foundation
@testable import ROLLodex

struct RollResolutionModeTests {

    @Test func rawValuesMatchKeys() {
        #expect(RollResolutionMode.manual.rawValue == "manual")
        #expect(RollResolutionMode.tray.rawValue == "tray")
        #expect(RollResolutionMode.behindTheScenes.rawValue == "behindTheScenes")
    }

    @Test func labelsAreHumanReadable() {
        #expect(RollResolutionMode.manual.label == "Type result")
        #expect(RollResolutionMode.tray.label == "Roll in dice tray")
        #expect(RollResolutionMode.behindTheScenes.label == "Roll behind the scenes")
    }

    @Test func systemImagesAreSet() {
        #expect(RollResolutionMode.manual.systemImage == "keyboard")
        #expect(RollResolutionMode.tray.systemImage == "dice.fill")
        #expect(RollResolutionMode.behindTheScenes.systemImage == "wand.and.stars")
    }

    @Test func defaultStorageKeyIsStable() {
        #expect(RollResolutionDefaults.storageKey == "roll.resolution.default")
    }

    @Test func allCasesRoundTripThroughRawValue() {
        for mode in RollResolutionMode.allCases {
            #expect(RollResolutionMode(rawValue: mode.rawValue) == mode)
        }
    }
}
