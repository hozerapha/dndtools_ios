import Foundation

struct Currency: Codable, Equatable {
    var cp: Int = 0
    var sp: Int = 0
    var ep: Int = 0
    var gp: Int = 0
    var pp: Int = 0

    var totalCopper: Int {
        cp + sp * 10 + ep * 50 + gp * 100 + pp * 1000
    }
}
