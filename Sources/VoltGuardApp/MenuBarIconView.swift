import SwiftUI
import VoltGuardDomain

public struct MenuBarIconView: View {
    @ObservedObject var presenter: VoltGuardPresenter

    public init(presenter: VoltGuardPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        let cfg = presenter.state.settings.menuBarIcon
        let telemetry: BatteryTelemetry? = {
            if case .loaded(let t, _) = presenter.state.telemetryState { return t }
            return nil
        }()
        let flow: PowerFlowMetrics? = {
            if case .loaded(_, let f) = presenter.state.telemetryState { return f }
            return nil
        }()

        HStack(spacing: 4) {
            Image(systemName: symbolName(for: cfg.style, telemetry: telemetry))
                .font(.system(size: 13, weight: .semibold))
                .accessibilityHidden(true)

            if cfg.showPercentage, let pct = telemetry?.percentage {
                Text("\(pct)%")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .monospacedDigit()
            }

            if cfg.showWattage, let flow {
                let watts = flow.adapterInputWatts > 0 ? flow.adapterInputWatts : flow.systemLoadWatts
                Text(String(format: "%.0fW", watts))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if cfg.showTemperature, let temp = telemetry?.temperatureCelsius {
                Text(String(format: "%.0f°", temp))
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if cfg.showTimeRemaining, let mins = presenter.state.batteryETA?.minutes {
                let hourUnit = presenter.state.settings.locale == .id ? "j" : "h"
                Text("\(mins / 60)\(hourUnit)\(String(format: "%02d", mins % 60))m")
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("VoltGuard \(telemetry?.percentage ?? 0)%"))
    }

    private func symbolName(for style: MenuBarIconStyle, telemetry: BatteryTelemetry?) -> String {
        switch style {
        case .shieldBattery:
            return telemetry?.isCharging == true ? "bolt.shield.fill" : "shield.lefthalf.filled"
        case .ringGauge:
            return "gauge.with.dots.needle.67percent"
        case .percentagePill:
            return telemetry?.isCharging == true ? "battery.100percent.bolt" : "battery.75percent"
        case .minimalBolt:
            return telemetry?.isPluggedIn == true ? "bolt.fill" : "bolt.slash"
        }
    }
}
