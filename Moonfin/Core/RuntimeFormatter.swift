import Foundation

enum RuntimeFormatter {
    static func format(ticks: Int64) -> String {
        let totalMinutes = Int(ticks / 600_000_000)
        if totalMinutes >= 60 {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h"
        }
        return "\(totalMinutes)m"
    }
}
