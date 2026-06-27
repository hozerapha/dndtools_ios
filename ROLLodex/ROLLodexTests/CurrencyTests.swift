import Testing
import Foundation
@testable import ROLLodex

struct CurrencyTests {

    @Test func totalCopperConversion() {
        let purse = Currency(cp: 7, sp: 5, ep: 2, gp: 3, pp: 1)
        // 7 + 5*10 + 2*50 + 3*100 + 1*1000 = 1457
        #expect(purse.totalCopper == 1457)
    }

    @Test func emptyCurrencyIsZero() {
        #expect(Currency().totalCopper == 0)
    }

    @Test func singleCoinConversions() {
        #expect(Currency(sp: 1).totalCopper == 10)
        #expect(Currency(ep: 1).totalCopper == 50)
        #expect(Currency(gp: 1).totalCopper == 100)
        #expect(Currency(pp: 1).totalCopper == 1000)
    }

    @Test func negativeValuesConvertArithmetically() {
        let purse = Currency(cp: 5, gp: -1)
        #expect(purse.totalCopper == -95)
    }

    @Test func equalityMatchesAllFields() {
        let a = Currency(cp: 1, sp: 2, gp: 3)
        let b = Currency(cp: 1, sp: 2, gp: 3)
        let c = Currency(cp: 1, sp: 2, gp: 4)
        #expect(a == b)
        #expect(a != c)
    }
}
