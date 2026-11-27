import Foundation
import VoltGuardDomain

public protocol HealthHistoryRepository: Sendable {
    func loadSnapshots() -> [BatteryHealthSnapshot]
    func recordSnapshot(from telemetry: BatteryTelemetry) -> [BatteryHealthSnapshot]
    func exportCSV() -> String
}

public final class JSONHealthHistoryRepository: HealthHistoryRepository, @unchecked Sendable {
    private let fileURL: URL
    private let lock = NSLock()
    private let maxEntries = 365
    private var cachedSnapshots: [BatteryHealthSnapshot]?
    private var lastSnapshotSignature: String?

    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    public init(fileURL: URL? = nil) {
        if let customURL = fileURL {
            self.fileURL = customURL
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory())
            self.fileURL = appSupport
                .appendingPathComponent(DataConstants.Storage.appFolderName, isDirectory: true)
                .appendingPathComponent(DataConstants.Storage.healthHistoryFileName)
        }
    }

    public func loadSnapshots() -> [BatteryHealthSnapshot] {
        lock.withLock { loadLocked() }
    }

    public func recordSnapshot(from telemetry: BatteryTelemetry) -> [BatteryHealthSnapshot] {
        lock.withLock {
            var list = loadLocked()
            let key = Self.dayFormatter.string(from: telemetry.timestamp)
            let sig = "\(key)|\(telemetry.healthPercent)|\(telemetry.cycleCount)|\(String(format: "%.1f", telemetry.temperatureCelsius))"
            if sig == lastSnapshotSignature {
                return list
            }
            var didChange = false

            if let idx = list.firstIndex(where: { $0.id == key }) {
                let existing = list[idx]
                let updatedCycles = max(existing.cycleCount, telemetry.cycleCount)
                let updatedPeak = max(existing.peakTemperatureCelsius, telemetry.temperatureCelsius)
                if existing.healthPercent != telemetry.healthPercent
                    || existing.cycleCount != updatedCycles
                    || updatedPeak > existing.peakTemperatureCelsius {
                    list[idx] = BatteryHealthSnapshot(
                        id: key,
                        date: telemetry.timestamp,
                        healthPercent: telemetry.healthPercent,
                        cycleCount: updatedCycles,
                        peakTemperatureCelsius: updatedPeak
                    )
                    didChange = true
                }
            } else {
                list.append(
                    BatteryHealthSnapshot(
                        id: key,
                        date: telemetry.timestamp,
                        healthPercent: telemetry.healthPercent,
                        cycleCount: telemetry.cycleCount,
                        peakTemperatureCelsius: telemetry.temperatureCelsius
                    )
                )
                if list.count > maxEntries {
                    list.removeFirst(list.count - maxEntries)
                }
                didChange = true
            }

            if didChange {
                cachedSnapshots = list
                saveLocked(list)
            }
            if let last = list.last(where: { $0.id == key }) {
                lastSnapshotSignature = "\(key)|\(last.healthPercent)|\(last.cycleCount)|\(String(format: "%.1f", last.peakTemperatureCelsius))"
            }
            return list
        }
    }

    public func exportCSV() -> String {
        let list = loadSnapshots()
        var lines = ["date,health_percent,cycle_count,peak_temp_c"]
        for item in list {
            lines.append(String(format: "%@,%d,%d,%.1f", item.id, item.healthPercent, item.cycleCount, item.peakTemperatureCelsius))
        }
        return lines.joined(separator: "\n")
    }

    private func loadLocked() -> [BatteryHealthSnapshot] {
        if let cached = cachedSnapshots {
            return cached
        }
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([BatteryHealthSnapshot].self, from: data) else {
            cachedSnapshots = []
            return []
        }
        cachedSnapshots = decoded
        return decoded
    }

    private func saveLocked(_ list: [BatteryHealthSnapshot]) {
        let dir = fileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(list) else { return }
        try? data.write(to: fileURL, options: [.atomic])
    }
}
