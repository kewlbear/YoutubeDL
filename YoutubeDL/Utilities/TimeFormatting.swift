import Foundation

func secondsFromHMSString(_ string: String) -> Int? {
    let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let parts = trimmed.split(separator: ":").map(String.init)
    guard parts.count <= 3, parts.allSatisfy({ Int($0) != nil }) else { return nil }

    return parts.reduce(0) { partialResult, part in
        (partialResult * 60) + (Int(part) ?? 0)
    }
}

func formatSecondsToHMS(_ value: Int) -> String {
    guard value >= 0 else { return "0:00" }

    let hours = value / 3600
    let minutes = (value % 3600) / 60
    let seconds = value % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    } else {
        return String(format: "%d:%02d", minutes, seconds)
    }
}
