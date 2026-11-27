import Foundation

public enum EnergyImpactLevel: String, Codable, Equatable, Sendable {
    case low
    case medium
    case high
}

public struct EnergyAppUsage: Equatable, Identifiable, Sendable {
    public let pid: Int32
    public let name: String
    public let bundleIdentifier: String?
    public let cpuPercent: Double
    public let impact: EnergyImpactLevel

    public var id: Int32 { pid }

    public init(
        pid: Int32,
        name: String,
        bundleIdentifier: String?,
        cpuPercent: Double
    ) {
        self.pid = pid
        self.name = name
        self.bundleIdentifier = bundleIdentifier
        self.cpuPercent = max(cpuPercent, 0)
        if cpuPercent >= 25.0 {
            self.impact = .high
        } else if cpuPercent >= 8.0 {
            self.impact = .medium
        } else {
            self.impact = .low
        }
    }
}

public protocol EnergyMonitorGateway: Sendable {
    func fetchTopEnergyApps(limit: Int) async throws -> [EnergyAppUsage]
    func fetchTopEnergyApps(limit: Int, threshold: EnergyUsageThreshold, includeBackground: Bool) async throws -> [EnergyAppUsage]
    @MainActor func terminateApp(pid: Int32) -> Bool
}

public extension EnergyMonitorGateway {
    func fetchTopEnergyApps(limit: Int, threshold: EnergyUsageThreshold, includeBackground: Bool) async throws -> [EnergyAppUsage] {
        let apps = try await fetchTopEnergyApps(limit: limit)
        return apps.filter { $0.cpuPercent >= threshold.minimumCPUPercent }
    }
}
