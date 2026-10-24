import Foundation
import GridFleetCore

extension GameRules {
    var analyticsProperties: [String: AnalyticsValue] {
        [
            "preset": .string(preset.rawValue),
            "salvo": .bool(firing == .salvo),
            "specials": .bool(specialWeapons),
            "ships_may_touch": .bool(shipsMayTouch),
        ]
    }
}

extension Dictionary where Key == String, Value == AnalyticsValue {
    func merging(_ other: [String: AnalyticsValue]) -> [String: AnalyticsValue] {
        merging(other) { _, new in new }
    }
}
