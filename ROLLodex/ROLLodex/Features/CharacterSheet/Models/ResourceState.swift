import Foundation

/// The mutable per-character slice of a resource. The `max` and refresh
/// behavior come from the `ResourceDefinition` in content; only the `current`
/// value lives on the character so schema edits to content don't invalidate
/// saved characters.
struct ResourceState: Codable, Equatable, Hashable {
    var current: Int

    init(current: Int) {
        self.current = current
    }
}
