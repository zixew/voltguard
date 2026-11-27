import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VoltGuardDomain

public enum DashboardSection: String, CaseIterable, Identifiable {
    case overview
    case charging
    case energy
    case schedule
    case appearance
    case system

    public var id: String { rawValue }

    public var icon: String {
        switch self {
        case .overview: return "gauge.with.dots.needle.67percent"
        case .charging: return "bolt.batteryblock"
        case .energy: return "cpu"
        case .schedule: return "calendar.badge.clock"
        case .appearance: return "paintpalette"
        case .system: return "gearshape.2"
        }
    }

    public func title(locale: AppLocale) -> String {
        switch self {
        case .overview: return L10n.text(.tabOverview, locale: locale)
        case .charging: return L10n.text(.tabCharging, locale: locale)
        case .energy: return L10n.text(.tabEnergy, locale: locale)
        case .schedule: return L10n.text(.tabSchedule, locale: locale)
        case .appearance: return L10n.text(.tabTheme, locale: locale)
        case .system: return L10n.text(.tabGuide, locale: locale)
        }
    }
}

public struct FullDashboardView: View {
    @ObservedObject var presenter: VoltGuardPresenter
    @State private var selectedSection: DashboardSection = .overview
    @State private var newRuleTitle: String = ""
    @State private var newRuleHour: Int = 8
    @State private var newRuleMinute: Int = 0
    @State private var newRuleWeekdays: Set<Int> = [2, 3, 4, 5, 6]
    @State private var newRuleAction: ScheduleAction = .setLimit80
    @State private var customHexInput: String = ""
    @State private var hoveredSidebarSection: DashboardSection?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(presenter: VoltGuardPresenter, initialSection: DashboardSection = .overview) {
        self.presenter = presenter
        self._selectedSection = State(initialValue: initialSection)
    }

    public var body: some View {
        let locale = presenter.state.settings.locale
        let palette = presenter.state.palette
        let theme = presenter.state.settings.theme

        ZStack {
            CustomBackgroundLayer(theme: theme, palette: palette)

            HStack(spacing: 0) {
                sidebarRail(locale: locale, palette: palette)
                    .frame(width: AppLayoutConstants.sidebarIdealWidth)
                    .background(palette.surface.opacity(0.65))

                Rectangle()
                    .fill(palette.border)
                    .frame(width: 1)

                ScrollView {
                    detailContent(locale: locale, palette: palette)
                        .id(selectedSection)
                        .transition(
                            reduceMotion
                                ? .identity
                                : .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 8)),
                                    removal: .opacity
                                )
                        )
                        .padding(24)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .animation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.86), value: selectedSection)
            }
        }
        .frame(
            minWidth: AppLayoutConstants.fullWindowMinWidth,
            minHeight: AppLayoutConstants.fullWindowMinHeight
        )
        .preferredColorScheme(palette.isDark ? .dark : .light)
        .tint(palette.accent)
        .compatOnChange(of: selectedSection) { newValue in
            if newValue == .energy {
                presenter.dispatch(.refreshEnergyApps)
            } else if newValue == .system {
                presenter.dispatch(.runDiagnostics)
            }
        }
        .compatOnChange(of: presenter.state.requestedDashboardTab) { tabIdx in
            guard let tabIdx, DashboardSection.allCases.indices.contains(tabIdx) else { return }
            selectedSection = DashboardSection.allCases[tabIdx]
        }
    }

    @ViewBuilder
    private func sidebarRail(locale: AppLocale, palette: ThemePalette) -> some View {
        let liveTelemetry: (BatteryTelemetry, PowerFlowMetrics)? = {
            if case .loaded(let t, let f) = presenter.state.telemetryState { return (t, f) }
            return nil
        }()
        let activeLEDColor: Color = {
            let reason = presenter.state.lastReason
            if reason == .manualDischarge || reason == .automaticDischarge {
                return palette.secondaryText.opacity(0.45)
            }
            if reason == .limitReached || reason == .sailingPaused {
                return Color(hex: "#22C55E")
            }
            return Color(hex: "#F59E0B")
        }()

        VStack(spacing: 0) {
            HStack(spacing: 10) {
                BrandLogoView(size: 30, accentColor: palette.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.text(.appTitle, locale: locale))
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    HStack(spacing: 5) {
                        Circle()
                            .fill(presenter.state.helperConnected ? palette.accent : palette.warning)
                            .frame(width: 6, height: 6)
                        Text(L10n.text(presenter.state.helperConnected ? .helperConnected : .helperDryRun, locale: locale))
                            .font(.caption2)
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            if let (telemetry, flow) = liveTelemetry {
                let watts = flow.adapterInputWatts > 0 ? flow.adapterInputWatts : flow.systemLoadWatts
                HStack(spacing: 8) {
                    HStack(spacing: 5) {
                        Image(systemName: telemetry.isCharging ? "bolt.fill" : (telemetry.isPluggedIn ? "powerplug.fill" : "battery.75percent"))
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.accent)
                        Text("\(telemetry.percentage)%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())
                            .foregroundStyle(palette.primaryText)
                    }

                    Spacer()

                    Text(String(format: "%.1f W", watts))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .contentTransition(.numericText())
                        .foregroundStyle(palette.secondaryText)

                    if presenter.state.effectiveCompatibility.magSafeLED.supported {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(activeLEDColor)
                                .frame(width: 7, height: 7)
                                .shadow(color: activeLEDColor.opacity(0.75), radius: 3)
                            Text("LED")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(palette.surface)
                        .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(palette.background.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.border.opacity(0.7), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            VStack(spacing: 4) {
                ForEach(DashboardSection.allCases) { section in
                    let isSelected = selectedSection == section
                    let isHovered = hoveredSidebarSection == section
                    Button {
                        withAnimation(reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.85)) {
                            selectedSection = section
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: section.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .frame(width: 18)
                                .foregroundStyle(isSelected ? palette.accent : (isHovered ? palette.primaryText : palette.secondaryText))
                                .accessibilityHidden(true)
                            Text(section.title(locale: locale))
                                .font(.system(size: 13, weight: isSelected ? .semibold : .medium))
                                .foregroundStyle(isSelected ? palette.primaryText : (isHovered ? palette.primaryText : palette.secondaryText))
                                .lineLimit(1)
                                .minimumScaleFactor(0.9)
                            Spacer()
                            if isSelected {
                                Capsule()
                                    .fill(palette.accent)
                                    .frame(width: 3, height: 14)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(isSelected ? palette.accent.opacity(0.18) : (isHovered ? palette.background.opacity(0.55) : Color.clear))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(isSelected ? palette.accent.opacity(0.55) : Color.clear, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .compatFocusEffectDisabled()
                    .onHover { hovering in
                        hoveredSidebarSection = hovering ? section : (hoveredSidebarSection == section ? nil : hoveredSidebarSection)
                    }
                }
            }
            .padding(.horizontal, 10)

            Spacer()

            Rectangle()
                .fill(palette.border)
                .frame(height: 1)

            VStack(spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(AppLocale.allCases, id: \.self) { loc in
                        let isCurrent = locale == loc
                        Button {
                            presenter.dispatch(.updateLocale(loc))
                        } label: {
                            Text(loc.rawValue.uppercased())
                                .font(.system(size: 11, weight: isCurrent ? .bold : .medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 5)
                                .foregroundStyle(isCurrent ? (palette.isDark ? Color.black : Color.white) : palette.secondaryText)
                                .background(
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .fill(isCurrent ? palette.accent : Color.clear)
                                )
                                .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .compatFocusEffectDisabled()
                    }
                }
                .padding(3)
                .background(palette.background.opacity(0.75))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                HStack(spacing: 6) {
                    Button {
                        presenter.dispatch(.minimizeToBackground)
                    } label: {
                        Text(L10n.text(.minimizeToBackground, locale: locale))
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(palette.primaryText)
                            .background(palette.background.opacity(0.7))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .compatFocusEffectDisabled()

                    Button {
                        presenter.dispatch(.quitApp)
                    } label: {
                        Text(L10n.text(.quit, locale: locale))
                            .font(.system(size: 11, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                            .foregroundStyle(palette.danger)
                            .background(palette.danger.opacity(0.12))
                            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.danger.opacity(0.45), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .compatFocusEffectDisabled()
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder
    private func themedCard<Content: View>(
        title: String? = nil,
        palette: ThemePalette,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let title, !title.isEmpty {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.primaryText)
            }
            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    @ViewBuilder
    private func detailContent(locale: AppLocale, palette: ThemePalette) -> some View {
        switch selectedSection {
        case .overview:
            overviewSection(locale: locale, palette: palette)
        case .charging:
            chargingSection(locale: locale, palette: palette)
        case .energy:
            energySection(locale: locale, palette: palette)
        case .schedule:
            scheduleAndCalibrationSection(locale: locale, palette: palette)
        case .appearance:
            appearanceAndLayoutSection(locale: locale, palette: palette)
        case .system:
            systemAndGuideSection(locale: locale, palette: palette)
        }
    }

    @ViewBuilder
    private func overviewSection(locale: AppLocale, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(.tabOverview, locale: locale))
                .font(.title2.bold())
                .foregroundStyle(palette.primaryText)

            switch presenter.state.telemetryState {
            case .loading:
                ProgressView(L10n.text(.telemetryLoading, locale: locale))
            case .error(let msg):
                if presenter.state.hardwareProfile.isDesktopMac {
                    themedCard(palette: palette) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(L10n.text(.desktopMacTitle, locale: locale), systemImage: "desktopcomputer")
                                .font(.headline)
                                .foregroundStyle(palette.accent)
                            Text(L10n.text(.desktopMacBody, locale: locale))
                                .font(.callout)
                                .foregroundStyle(palette.secondaryText)
                            Text("\(presenter.state.hardwareProfile.modelIdentifier) · \(presenter.state.hardwareProfile.architecture) · macOS \(presenter.state.hardwareProfile.macOSVersionString)")
                                .font(.caption.monospaced())
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.text(.telemetryErrorTitle, locale: locale)).font(.headline)
                        Text(msg).foregroundStyle(palette.secondaryText)
                        Button(L10n.text(.telemetryRetry, locale: locale)) {
                            presenter.dispatch(.refreshTelemetry)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                    }
                }
            case .loaded(let telemetry, let flow):
                HStack(spacing: 18) {
                    LiquidBatteryCellView(
                        percentage: telemetry.percentage,
                        limitPercent: presenter.state.settings.policy.limitPercent,
                        sailingDeltaPercent: presenter.state.settings.policy.sailingModeEnabled ? presenter.state.settings.policy.sailingDeltaPercent : nil,
                        temperatureCelsius: telemetry.temperatureCelsius,
                        colorStyle: presenter.state.settings.theme.batteryColorStyle,
                        mode: dashboardVisualMode(presenter.state.lastReason, telemetry: telemetry),
                        palette: palette,
                        isVisible: presenter.state.isUIVisible,
                        width: 78,
                        height: 112
                    ) { newLimit in
                        presenter.dispatch(.setChargeLimit(newLimit))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("\(L10n.text(.chargeLimit, locale: locale)): \(presenter.state.settings.policy.limitPercent)%")
                                .font(.headline)
                                .contentTransition(.numericText())
                                .foregroundStyle(palette.primaryText)
                            Spacer()
                            if let etaText = BatteryETAFormatter.text(for: presenter.state.batteryETA, locale: locale) {
                                Text(etaText)
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(palette.accent)
                            }
                        }

                        Slider(
                            value: Binding(
                                get: { Double(presenter.state.settings.policy.limitPercent) },
                                set: { presenter.dispatch(.setChargeLimit(Int($0.rounded()))) }
                            ),
                            in: Double(VoltGuardLimits.minLimitPercent)...Double(VoltGuardLimits.maxLimitPercent)
                        )
                        .tint(palette.accent)

                        HStack(spacing: 8) {
                            ForEach(VoltGuardLimits.quickPresets, id: \.self) { preset in
                                let isSelected = presenter.state.settings.policy.limitPercent == preset
                                Button {
                                    presenter.dispatch(.setChargeLimit(preset))
                                } label: {
                                    Text("\(preset)%")
                                        .font(.system(size: 12, weight: .semibold))
                                        .padding(.horizontal, 16)
                                        .padding(.vertical, 7)
                                        .foregroundStyle(isSelected ? (palette.isDark ? Color.black : Color.white) : palette.primaryText)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .fill(isSelected ? palette.accent : palette.background.opacity(0.65))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                                .strokeBorder(isSelected ? Color.clear : palette.border, lineWidth: 1)
                                        )
                                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                        .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .compatFocusEffectDisabled()
                            }
                        }

                        if presenter.state.telemetryHistory.count >= 2 {
                            TelemetrySparklineView(samples: presenter.state.telemetryHistory, palette: palette)
                        }
                    }
                }
                .padding(16)
                .background(palette.surface)
                .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))

                PowerTopologyCardView(
                    telemetry: telemetry,
                    flow: flow,
                    palette: palette,
                    locale: locale,
                    batteryETA: presenter.state.batteryETA,
                    isVisible: presenter.state.isUIVisible
                )

                HStack(spacing: 14) {
                    healthGaugeCard(telemetry: telemetry, locale: locale, palette: palette)
                    InteractiveThermalZoneCard(
                        telemetry: telemetry,
                        maxAllowedTemp: presenter.state.settings.policy.maxTemperatureCelsius,
                        heatProtectionEnabled: presenter.state.settings.policy.heatProtectionEnabled,
                        locale: locale,
                        palette: palette,
                        isVisible: presenter.state.isUIVisible,
                        onAdjustMaxTemp: { nextTemp in
                            presenter.dispatch(.setMaxTemperature(nextTemp))
                        },
                        onToggleHeatProtection: {
                            presenter.dispatch(.toggleHeatProtection)
                        }
                    )
                    timeAndModeCard(telemetry: telemetry, flow: flow, locale: locale, palette: palette)
                }

                batteryConditionDetailCard(telemetry: telemetry, flow: flow, locale: locale, palette: palette)

                chargerPDVerifierCard(telemetry: telemetry, flow: flow, locale: locale, palette: palette)

                recommendedProfilesSection(locale: locale, palette: palette)
            }
        }
    }

    @ViewBuilder
    private func batteryConditionDetailCard(
        telemetry: BatteryTelemetry,
        flow: PowerFlowMetrics,
        locale: AppLocale,
        palette: ThemePalette
    ) -> some View {
        let wearMah = max(telemetry.designCapacityMah - telemetry.maxCapacityMah, 0)
        let conditionText: String = {
            switch telemetry.batteryCondition {
            case .normal: return L10n.text(.conditionNormal, locale: locale)
            case .fair: return L10n.text(.conditionFair, locale: locale)
            case .serviceRecommended: return L10n.text(.conditionService, locale: locale)
            }
        }()
        let conditionColor: Color = {
            switch telemetry.batteryCondition {
            case .normal: return palette.accent
            case .fair: return palette.warning
            case .serviceRecommended: return palette.danger
            }
        }()

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.text(.moduleBatteryHealth, locale: locale))
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Text("\(L10n.text(.batteryCondition, locale: locale)): \(conditionText)")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(conditionColor.opacity(0.18))
                    .foregroundStyle(conditionColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            if telemetry.isPluggedIn && !telemetry.isCharging && presenter.state.lastReason == .normalCharging && telemetry.percentage < presenter.state.settings.policy.limitPercent && flow.batteryNetWatts < -3.0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(palette.warning)
                        .accessibilityHidden(true)
                    Text(L10n.text(.underpoweredCharger, locale: locale))
                        .font(.caption)
                        .foregroundStyle(palette.warning)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.background)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.warning.opacity(0.6), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                detailMetricCell(
                    label: L10n.text(.cycles, locale: locale),
                    value: "\(telemetry.cycleCount)",
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.maxCapacity, locale: locale),
                    value: "\(telemetry.maxCapacityMah) mAh",
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.designCapacity, locale: locale),
                    value: "\(telemetry.designCapacityMah) mAh",
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.currentCapacity, locale: locale),
                    value: telemetry.currentCapacityMah.map { "\($0) mAh" } ?? "\(telemetry.percentage)%",
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.capacityLoss, locale: locale),
                    value: "-\(wearMah) mAh (\(max(100 - telemetry.healthPercent, 0))%)",
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.batteryChip, locale: locale),
                    value: telemetry.deviceName ?? "AppleSmartBattery",
                    palette: palette
                )
            }

            // Visual Capacity Comparison Bar (Current mAh vs Max Capacity vs Design Capacity)
            let designCap = Double(max(telemetry.designCapacityMah, 1))
            let maxCapRatio = min(max(Double(telemetry.maxCapacityMah) / designCap, 0.05), 1.0)
            let curMah = Double(telemetry.currentCapacityMah ?? Int(Double(telemetry.maxCapacityMah) * Double(telemetry.percentage) / 100.0))
            let curRatio = min(max(curMah / designCap, 0.02), maxCapRatio)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("\(L10n.text(.currentCapacity, locale: locale)): \(Int(curMah)) mAh")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.accent)
                    Spacer()
                    Text("\(L10n.text(.maxCapacity, locale: locale)): \(telemetry.maxCapacityMah) / \(telemetry.designCapacityMah) mAh (\(telemetry.healthPercent)%)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(palette.background)
                        Capsule()
                            .fill(palette.secondaryText.opacity(0.28))
                            .frame(width: geo.size.width * CGFloat(maxCapRatio))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [palette.accent.opacity(0.8), palette.accent],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * CGFloat(curRatio))
                    }
                }
                .frame(height: 8)
            }
            .padding(10)
            .background(palette.background.opacity(0.6))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(palette.border.opacity(0.6), lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.text(.healthTrendTitle, locale: locale))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.secondaryText)

                if presenter.state.healthSnapshots.count >= 2 {
                    HealthTrendChartView(snapshots: presenter.state.healthSnapshots, palette: palette)
                } else {
                    Text(L10n.text(.healthHistoryEmpty, locale: locale))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(palette.background)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .padding(16)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    @ViewBuilder
    private func detailMetricCell(label: String, value: String, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.callout.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func recommendedProfilesSection(locale: AppLocale, palette: ThemePalette) -> some View {
        let rec = presenter.state.liveRecommendation
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(L10n.text(.recommendedProfilesTitle, locale: locale))
                    .font(.headline)
                    .foregroundStyle(palette.primaryText)
                Spacer()
                if let rec {
                    Text(profileReasonText(rec.reason, locale: locale))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(BatteryProfileTier.allCases) { tier in
                    let isSuggested = rec?.tier == tier
                    let isApplied = isSuggested && (rec?.isAlreadyApplied == true)
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(profileTitle(tier, locale: locale))
                                .font(.headline)
                                .foregroundStyle(palette.primaryText)
                            Spacer()
                            if isSuggested {
                                Text(L10n.text(.recommendedBadge, locale: locale))
                                    .font(.caption2.weight(.semibold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(palette.accent.opacity(0.2))
                                    .foregroundStyle(palette.accent)
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                        }

                        Text(profileDescription(tier, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Button(isApplied ? L10n.text(.appliedProfile, locale: locale) : L10n.text(.applyProfile, locale: locale)) {
                            presenter.dispatch(.applyProfileTier(tier))
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isApplied ? palette.border : palette.accent)
                        .disabled(isApplied)
                    }
                    .padding(12)
                    .background(palette.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: palette.cornerRadius)
                            .stroke(isSuggested ? palette.accent : palette.border, lineWidth: isSuggested ? 1.5 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
                }
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.text(.customProfileTitle, locale: locale))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.primaryText)
                    if let custom = presenter.state.settings.customProfile {
                        Text("\(custom.limitPercent)% | \(L10n.text(.sailingDeltaLabel, locale: locale)): \(custom.sailingDeltaPercent)% | \(Int(custom.maxTemperatureCelsius)) C")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(palette.secondaryText)
                    } else {
                        Text(L10n.text(.customProfileEmpty, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }
                }
                Spacer()
                Button(L10n.text(.saveCustomProfile, locale: locale)) {
                    presenter.dispatch(.saveCustomProfile)
                }
                .buttonStyle(.bordered)
                if presenter.state.settings.customProfile != nil {
                    Button(L10n.text(.applyCustomProfile, locale: locale)) {
                        presenter.dispatch(.applyCustomProfile)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }
            }
            .padding(12)
            .background(palette.surface)
            .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
            .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
        }
    }

    private func profileTitle(_ tier: BatteryProfileTier, locale: AppLocale) -> String {
        switch tier {
        case .travel: return L10n.text(.profileTravelTitle, locale: locale)
        case .balanced: return L10n.text(.profileBalancedTitle, locale: locale)
        case .deskDocked: return L10n.text(.profileDeskTitle, locale: locale)
        case .maxLifespan: return L10n.text(.profileMaxLifespanTitle, locale: locale)
        }
    }

    private func profileDescription(_ tier: BatteryProfileTier, locale: AppLocale) -> String {
        switch tier {
        case .travel: return L10n.text(.profileTravelDesc, locale: locale)
        case .balanced: return L10n.text(.profileBalancedDesc, locale: locale)
        case .deskDocked: return L10n.text(.profileDeskDesc, locale: locale)
        case .maxLifespan: return L10n.text(.profileMaxLifespanDesc, locale: locale)
        }
    }

    private func profileReasonText(_ reason: RecommendationReason, locale: AppLocale) -> String {
        switch reason {
        case .highTemperature: return L10n.text(.reasonHighTemp, locale: locale)
        case .clamshellDocked: return L10n.text(.reasonClamshell, locale: locale)
        case .lowBatteryUnplugged: return L10n.text(.reasonLowBattery, locale: locale)
        case .dailyBalanced: return L10n.text(.reasonDaily, locale: locale)
        }
    }

    @ViewBuilder
    private func healthGaugeCard(telemetry: BatteryTelemetry, locale: AppLocale, palette: ThemePalette) -> some View {
        let fraction = min(max(Double(telemetry.healthPercent) / 100.0, 0), 1)
        let ringColor: Color = telemetry.healthPercent >= 85 ? palette.accent : (telemetry.healthPercent >= 80 ? palette.warning : palette.danger)
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .stroke(palette.border.opacity(0.6), lineWidth: 5.5)
                Circle()
                    .trim(from: 0, to: CGFloat(fraction))
                    .stroke(ringColor, style: StrokeStyle(lineWidth: 5.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(telemetry.healthPercent)%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(palette.primaryText)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.text(.batteryHealth, locale: locale))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Text("\(telemetry.healthPercent)%")
                    .font(.title3.bold().monospacedDigit())
                    .contentTransition(.numericText())
                    .foregroundStyle(palette.primaryText)
                Text("\(telemetry.cycleCount) \(L10n.text(.cycles, locale: locale).lowercased())")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func thermalZoneCard(telemetry: BatteryTelemetry, maxAllowedTemp: Double, locale: AppLocale, palette: ThemePalette) -> some View {
        let temp = telemetry.temperatureCelsius
        let normalized = min(max((temp - 20.0) / 25.0, 0.04), 1.0)
        let limitNorm = min(max((maxAllowedTemp - 20.0) / 25.0, 0.1), 0.98)
        let tempColor: Color = temp >= maxAllowedTemp ? palette.danger : (temp >= maxAllowedTemp - 2.5 ? palette.warning : palette.accent)

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(L10n.text(.temperature, locale: locale))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text("Max \(Int(maxAllowedTemp)) C")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.secondaryText)
            }

            Text(String(format: "%.1f C", temp))
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
                .foregroundStyle(tempColor)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.background)
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [palette.accent, palette.warning, palette.danger],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(geo.size.width * CGFloat(normalized), 6))
                    Rectangle()
                        .fill(palette.primaryText)
                        .frame(width: 2, height: 10)
                        .offset(x: geo.size.width * CGFloat(limitNorm))
                }
            }
            .frame(height: 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func chargerPDVerifierCard(
        telemetry: BatteryTelemetry,
        flow: PowerFlowMetrics,
        locale: AppLocale,
        palette: ThemePalette
    ) -> some View {
        let adapterName = telemetry.adapterName ?? (telemetry.isPluggedIn ? "USB-C PD Adapter" : L10n.text(.pdUnpluggedBadge, locale: locale))
        let watts = Int(telemetry.adapterWatts.rounded())
        let pdBadge: (String, Color) = {
            guard telemetry.isPluggedIn else {
                return (L10n.text(.pdUnpluggedBadge, locale: locale), palette.secondaryText)
            }
            if telemetry.adapterWatts >= 60 {
                return (L10n.text(.pdFastBadge, locale: locale), Color(hex: "#10B981"))
            }
            if telemetry.adapterWatts > 0 && flow.systemLoadWatts > telemetry.adapterWatts {
                return (L10n.text(.pdLowPowerBadge, locale: locale), palette.danger)
            }
            return (L10n.text(.pdStandardBadge, locale: locale), palette.accent)
        }()

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "cable.connector.horizontal")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.accent)
                    Text(L10n.text(.pdVerifierTitle, locale: locale))
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                }
                Spacer()
                Text(pdBadge.0)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(pdBadge.1.opacity(0.16))
                    .foregroundStyle(pdBadge.1)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            HStack(spacing: 12) {
                detailMetricCell(
                    label: L10n.text(.adapterDetails, locale: locale),
                    value: watts > 0 ? "\(adapterName) (\(watts) W)" : adapterName,
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.pdVoltageLabel, locale: locale),
                    value: telemetry.adapterVoltageVolts.map { String(format: "%.1f V", $0) } ?? "--",
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.pdCurrentLabel, locale: locale),
                    value: telemetry.adapterCurrentAmps.map { String(format: "%.2f A", $0) } ?? "--",
                    palette: palette
                )
                detailMetricCell(
                    label: L10n.text(.pdProtocolLabel, locale: locale),
                    value: telemetry.adapterProtocol ?? (telemetry.isPluggedIn ? "USB PD" : "--"),
                    palette: palette
                )
            }
        }
        .padding(14)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func timeAndModeCard(telemetry: BatteryTelemetry, flow: PowerFlowMetrics, locale: AppLocale, palette: ThemePalette) -> some View {
        let etaText = BatteryETAFormatter.text(for: presenter.state.batteryETA, locale: locale) ?? L10n.text(.etaCalculating, locale: locale)
        let reason = presenter.state.lastReason
        let isSteppingDown = telemetry.isPluggedIn && !telemetry.isCharging && flow.batteryNetWatts <= -MotionConstants.activeFlowWattThreshold
        let modeBadge: (String, Color) = {
            switch reason {
            case .limitReached, .sailingPaused:
                if isSteppingDown {
                    return (L10n.text(.adapterStepDownBadge, locale: locale), palette.warning)
                }
                return (L10n.text(.bypassActiveBadge, locale: locale), palette.accent)
            case .heatProtectionPaused:
                return (L10n.text(.statusHeatPaused, locale: locale), palette.danger)
            case .manualDischarge, .automaticDischarge:
                return (L10n.text(.statusManualDischarge, locale: locale), palette.warning)
            case .calibrationActive:
                return (L10n.text(.statusCalibration, locale: locale), palette.warning)
            case .topUpActive:
                return (L10n.text(.statusTopUp, locale: locale), palette.accent)
            case .sleepingInhibited:
                return (L10n.text(.statusSleepingInhibited, locale: locale), palette.secondaryText)
            case .normalCharging:
                return telemetry.isPluggedIn
                    ? (L10n.text(.statusCharging, locale: locale), palette.accent)
                    : (L10n.text(.statusOnBattery, locale: locale), palette.warning)
            }
        }()

        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(L10n.text(.timeRemaining, locale: locale))
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Text(modeBadge.0)
                    .font(.system(size: 9, weight: .bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(modeBadge.1.opacity(0.18))
                    .foregroundStyle(modeBadge.1)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .lineLimit(1)
            }
            Text(etaText)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(palette.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(String(format: "%+.2f A  |  %.2f V", telemetry.amperageAmps, telemetry.voltageVolts))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func chargingSection(locale: AppLocale, palette: ThemePalette) -> some View {
        let policy = presenter.state.settings.policy
        let isBypassActive: Bool = {
            if case .loaded(let t, let flow) = presenter.state.telemetryState {
                return t.isPluggedIn && !t.isCharging && abs(flow.batteryNetWatts) < MotionConstants.activeFlowWattThreshold
            }
            return false
        }()
        let isSteppingDown: Bool = {
            if case .loaded(let t, let flow) = presenter.state.telemetryState {
                return t.isPluggedIn && !t.isCharging && flow.batteryNetWatts <= -MotionConstants.activeFlowWattThreshold
            }
            return false
        }()

        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(.tabCharging, locale: locale))
                .font(.title2.bold())
                .foregroundStyle(palette.primaryText)

            themedCard(palette: palette) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.text(.bypassCardTitle, locale: locale), systemImage: "bolt.horizontal.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                        Spacer()
                        let badgeKey: L10nKey = isBypassActive ? .bypassActiveBadge : (isSteppingDown ? .adapterStepDownBadge : .appliedProfile)
                        let badgeColor = isSteppingDown ? palette.warning : palette.accent
                        Text(L10n.text(badgeKey, locale: locale))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(badgeColor.opacity(0.18))
                            .foregroundStyle(badgeColor)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    Text(L10n.text(.bypassCardDesc, locale: locale))
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                }
            }

            let compat = presenter.state.effectiveCompatibility
            themedCard(palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    settingToggleRow(
                        icon: "arrow.down.circle.fill",
                        title: L10n.text(.discharge, locale: locale),
                        subtitle: compat.discharge.supported ? L10n.text(.dischargeDesc, locale: locale) : compatReasonText(compat.discharge, locale: locale),
                        isOn: policy.manualDischarge,
                        isDisabled: !compat.discharge.supported,
                        palette: palette
                    ) { presenter.dispatch(.toggleManualDischarge) }

                    settingToggleRow(
                        icon: "arrow.triangle.2.circlepath.circle.fill",
                        title: L10n.text(.autoDischarge, locale: locale),
                        subtitle: compat.discharge.supported ? L10n.text(.autoDischargeDesc, locale: locale) : compatReasonText(compat.discharge, locale: locale),
                        isOn: policy.automaticDischarge,
                        isDisabled: !compat.discharge.supported,
                        palette: palette
                    ) { presenter.dispatch(.toggleAutomaticDischarge) }

                    settingToggleRow(
                        icon: "laptopcomputer.slash",
                        title: L10n.text(.clamshellDischarge, locale: locale),
                        subtitle: compat.discharge.supported ? L10n.text(.clamshellDischargeDesc, locale: locale) : compatReasonText(compat.discharge, locale: locale),
                        isOn: policy.dischargeInClamshell,
                        isDisabled: !compat.discharge.supported,
                        palette: palette
                    ) { presenter.dispatch(.toggleClamshellDischarge) }

                    settingToggleRow(
                        icon: "bolt.circle.fill",
                        title: L10n.text(.topUp, locale: locale),
                        subtitle: L10n.text(.topUpDesc, locale: locale),
                        isOn: policy.topUpActive,
                        palette: palette
                    ) { presenter.dispatch(.toggleTopUp) }
                }
            }

            themedCard(palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    settingToggleRow(
                        icon: "wind",
                        title: L10n.text(.sailingMode, locale: locale),
                        subtitle: L10n.text(.sailingModeDesc, locale: locale),
                        isOn: policy.sailingModeEnabled,
                        palette: palette
                    ) { presenter.dispatch(.toggleSailingMode) }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.text(.sailingDeltaLabel, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text("\(policy.sailingDeltaPercent)% (\(max(policy.limitPercent - policy.sailingDeltaPercent, VoltGuardLimits.minSailingFloorPercent))% - \(policy.limitPercent)%)")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(palette.accent)
                        }
                        Slider(
                            value: Binding(
                                get: { Double(policy.sailingDeltaPercent) },
                                set: { presenter.dispatch(.setSailingDelta(Int($0.rounded()))) }
                            ),
                            in: Double(VoltGuardLimits.minSailingDeltaPercent)...Double(VoltGuardLimits.maxSailingDeltaPercent)
                        )
                        .disabled(!policy.sailingModeEnabled)
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)
                    .opacity(policy.sailingModeEnabled ? 1.0 : 0.45)

                    Divider()

                    settingToggleRow(
                        icon: "thermometer.medium",
                        title: L10n.text(.heatProtection, locale: locale),
                        subtitle: L10n.text(.heatProtectionDesc, locale: locale),
                        isOn: policy.heatProtectionEnabled,
                        palette: palette
                    ) { presenter.dispatch(.toggleHeatProtection) }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(L10n.text(.temperature, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text("\(Int(policy.maxTemperatureCelsius)) C")
                                .font(.caption.weight(.semibold).monospacedDigit())
                                .foregroundStyle(palette.warning)
                        }
                        Slider(
                            value: Binding(
                                get: { policy.maxTemperatureCelsius },
                                set: { presenter.dispatch(.setMaxTemperature($0.rounded())) }
                            ),
                            in: VoltGuardLimits.minTemperatureCelsius...VoltGuardLimits.maxTemperatureCelsius
                        )
                        .disabled(!policy.heatProtectionEnabled)
                    }
                    .padding(.horizontal, 10)
                    .opacity(policy.heatProtectionEnabled ? 1.0 : 0.45)
                }
            }

            themedCard(palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    settingToggleRow(
                        icon: "moon.zzz.fill",
                        title: L10n.text(.sleepControl, locale: locale),
                        subtitle: L10n.text(.sleepControlDesc, locale: locale),
                        isOn: policy.sleepControlEnabled,
                        palette: palette
                    ) { presenter.dispatch(.toggleSleepControl) }

                    settingToggleRow(
                        icon: "bed.double.fill",
                        title: L10n.text(.stopChargingOnSleep, locale: locale),
                        subtitle: L10n.text(.stopChargingOnSleepDesc, locale: locale),
                        isOn: policy.stopChargingWhenSleeping,
                        palette: palette
                    ) { presenter.dispatch(.toggleStopChargingOnSleep) }

                    settingToggleRow(
                        icon: "leaf.fill",
                        title: L10n.text(.lowPowerOnBattery, locale: locale),
                        subtitle: compat.lowPowerMode.supported ? L10n.text(.lowPowerOnBatteryDesc, locale: locale) : compatReasonText(compat.lowPowerMode, locale: locale),
                        isOn: policy.lowPowerModeOnBattery,
                        isDisabled: !compat.lowPowerMode.supported,
                        palette: palette
                    ) { presenter.dispatch(.toggleLowPowerOnBattery) }

                    settingToggleRow(
                        icon: "leaf.circle.fill",
                        title: L10n.text(.lowPowerAlways, locale: locale),
                        subtitle: compat.lowPowerMode.supported ? L10n.text(.lowPowerAlwaysDesc, locale: locale) : compatReasonText(compat.lowPowerMode, locale: locale),
                        isOn: policy.lowPowerModeAlways,
                        isDisabled: !compat.lowPowerMode.supported,
                        palette: palette
                    ) { presenter.dispatch(.toggleLowPowerAlways) }

                    settingToggleRow(
                        icon: "arrow.uturn.backward.circle.fill",
                        title: L10n.text(.restoreDefaultOnQuit, locale: locale),
                        subtitle: L10n.text(.restoreDefaultOnQuitDesc, locale: locale),
                        isOn: policy.restoreDefaultOnQuit,
                        palette: palette
                    ) { presenter.dispatch(.toggleRestoreDefaultOnQuit) }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.text(.magSafeLED, locale: locale))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text(
                                compat.magSafeLED.supported
                                    ? ledModeTitle(policy.magSafeLEDMode, locale: locale)
                                    : L10n.text(.compatStatusUnavailable, locale: locale)
                            )
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(compat.magSafeLED.supported ? palette.primaryText : palette.warning)
                        }

                        HStack(spacing: 8) {
                            ForEach(MagSafeLEDMode.allCases, id: \.self) { mode in
                                let isSelected = policy.magSafeLEDMode == mode && compat.magSafeLED.supported
                                Button {
                                    presenter.dispatch(.setMagSafeLED(mode))
                                } label: {
                                    VStack(spacing: 5) {
                                        Circle()
                                            .fill(ledDotColor(mode, palette: palette))
                                            .frame(width: 9, height: 9)
                                            .shadow(color: ledDotColor(mode, palette: palette).opacity(isSelected ? 0.7 : 0), radius: 3)
                                        Text(ledModeTitle(mode, locale: locale))
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 4)
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? palette.accent.opacity(0.18) : palette.background.opacity(0.55))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isSelected ? palette.accent : palette.border, lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .compatFocusEffectDisabled()
                                .disabled(!compat.magSafeLED.supported)
                            }
                        }
                        .opacity(compat.magSafeLED.supported ? 1.0 : 0.42)

                        if compat.magSafeLED.supported {
                            Text(L10n.text(policy.magSafeLEDMode == .matchBattery ? .magSafeHardwareNote : .magSafeSyncLegend, locale: locale))
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption)
                                    .foregroundStyle(palette.warning)
                                Text(compatReasonText(compat.magSafeLED, locale: locale))
                                    .font(.caption)
                                    .foregroundStyle(palette.warning)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.background.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.warning.opacity(0.45), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func energySection(locale: AppLocale, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(.energyMonitorTitle, locale: locale))
                        .font(.title2.bold())
                        .foregroundStyle(palette.primaryText)
                    Text(L10n.text(.energyMonitorSubtitle, locale: locale))
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
                Button(L10n.text(.energyRefresh, locale: locale)) {
                    presenter.dispatch(.refreshEnergyApps)
                }
                .buttonStyle(.borderedProminent)
                .tint(palette.accent)
            }

            switch presenter.state.energyState {
            case .idle, .loading:
                ProgressView(L10n.text(.energyLoading, locale: locale))
                    .onAppear {
                        if presenter.state.energyState == .idle {
                            presenter.dispatch(.refreshEnergyApps)
                        }
                    }
            case .error(let msg):
                Text(msg).foregroundStyle(palette.danger)
            case .loaded(let apps) where apps.isEmpty:
                Text(L10n.text(.energyEmpty, locale: locale))
                    .foregroundStyle(palette.secondaryText)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
            case .loaded(let apps):
                let maxCPU = max(apps.map(\.cpuPercent).max() ?? 25.0, 25.0)
                VStack(spacing: 8) {
                    ForEach(apps) { app in
                        let barColor = impactColor(app.impact, palette: palette)
                        let ratio = min(max(app.cpuPercent / maxCPU, 0.04), 1.0)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(app.name)
                                        .font(.headline)
                                        .foregroundStyle(palette.primaryText)
                                    Text(String(format: "PID %d  |  CPU %.1f%%", app.pid, app.cpuPercent))
                                        .font(.caption.monospaced())
                                        .foregroundStyle(palette.secondaryText)
                                }
                                Spacer()
                                Text(impactLabel(app.impact, locale: locale))
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(barColor.opacity(0.18))
                                    .foregroundStyle(barColor)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                                Button(L10n.text(.energyQuitApp, locale: locale)) {
                                    presenter.dispatch(.terminateEnergyApp(app.pid))
                                }
                                .buttonStyle(.bordered)
                                .tint(palette.danger)
                            }

                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(palette.background)
                                    Capsule()
                                        .fill(barColor)
                                        .frame(width: geo.size.width * CGFloat(ratio))
                                }
                            }
                            .frame(height: 5)
                        }
                        .padding(12)
                        .background(palette.surface)
                        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func scheduleAndCalibrationSection(locale: AppLocale, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(.tabSchedule, locale: locale))
                .font(.title2.bold())
                .foregroundStyle(palette.primaryText)

            themedCard(title: L10n.text(.calibrationMode, locale: locale), palette: palette) {
                let pct: Int? = {
                    if case .loaded(let t, _) = presenter.state.telemetryState { return t.percentage }
                    return nil
                }()
                let isPluggedIn: Bool = {
                    if case .loaded(let t, _) = presenter.state.telemetryState { return t.isPluggedIn }
                    return true
                }()

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.text(.calibrationActiveHint, locale: locale))
                                .font(.callout)
                        }
                        Spacer()
                        if presenter.state.calibration.isActive {
                            Button(L10n.text(.stopCalibration, locale: locale)) {
                                presenter.dispatch(.stopCalibration)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.danger)
                        } else {
                            Button(L10n.text(.startCalibration, locale: locale)) {
                                presenter.dispatch(.startCalibration)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.accent)
                            .disabled(!isPluggedIn)
                        }
                    }

                    if !presenter.state.calibration.isActive {
                        if !isPluggedIn {
                            Text(L10n.text(.calNeedsCharger, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.warning)
                        } else if !presenter.state.helperConnected {
                            Text(L10n.text(.calNeedsHelper, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.warning)
                        }
                    }

                    CalibrationProgressView(
                        session: presenter.state.calibration,
                        currentPercentage: pct,
                        palette: palette,
                        locale: locale,
                        compact: false,
                        isVisible: presenter.state.isUIVisible
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 6) {
                        Label(L10n.text(.calExpectedOutcomeTitle, locale: locale), systemImage: "scope")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                        Text(L10n.text(.calExpectedOutcomeBody, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(palette.accent.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.accent.opacity(0.28), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(L10n.text(.calResultTitle, locale: locale), systemImage: "arrow.left.arrow.right.circle.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.primaryText)
                            Spacer()
                            if let result = presenter.state.settings.lastCalibrationResult {
                                Text(result.completedAt.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }

                        if let result = presenter.state.settings.lastCalibrationResult {
                            let signMah = result.deltaMah >= 0 ? "+\(result.deltaMah)" : "\(result.deltaMah)"
                            let signHealth = result.deltaHealthPercent >= 0 ? "+\(result.deltaHealthPercent)" : "\(result.deltaHealthPercent)"
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.text(.calResultBeforeLabel, locale: locale))
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                    Text("\(result.beforeMaxCapacityMah) mAh (\(result.beforeHealthPercent)%)")
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundStyle(palette.primaryText)
                                    Text("\(result.beforeCycleCount) cyc")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(palette.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(palette.background.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                Image(systemName: "arrow.right")
                                    .font(.caption.bold())
                                    .foregroundStyle(palette.accent)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.text(.calResultAfterLabel, locale: locale))
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                    Text("\(result.afterMaxCapacityMah) mAh (\(result.afterHealthPercent)%)")
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundStyle(palette.accent)
                                    Text("\(result.afterCycleCount) cyc")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(palette.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(palette.background.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(L10n.text(.calResultDeltaLabel, locale: locale))
                                        .font(.caption2)
                                        .foregroundStyle(palette.secondaryText)
                                    Text("\(signMah) mAh")
                                        .font(.caption.bold().monospacedDigit())
                                        .foregroundStyle(result.deltaMah >= 0 ? palette.accent : palette.warning)
                                    Text("\(signHealth)%")
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(palette.secondaryText)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                                .background(palette.background.opacity(0.55))
                                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                        } else {
                            Text(L10n.text(.calResultEmptyHint, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                        }
                    }
                    .padding(10)
                    .background(palette.background.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(palette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
            }

            themedCard(title: L10n.text(.schedule, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        TextField(L10n.text(.scheduleRulePlaceholder, locale: locale), text: $newRuleTitle)
                            .textFieldStyle(.roundedBorder)

                        HStack(spacing: 4) {
                            Picker("", selection: $newRuleHour) {
                                ForEach(0..<24, id: \.self) { h in
                                    Text(String(format: "%02d", h)).tag(h)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 60)

                            Text(":")
                                .font(.headline.monospaced())
                                .foregroundStyle(palette.secondaryText)

                            Picker("", selection: $newRuleMinute) {
                                ForEach([0, 15, 30, 45], id: \.self) { m in
                                    Text(String(format: "%02d", m)).tag(m)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 60)
                        }

                        Picker("", selection: $newRuleAction) {
                            ForEach(ScheduleAction.allCases, id: \.self) { action in
                                Text(scheduleActionTitle(action, locale: locale)).tag(action)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 165)

                        Button(L10n.text(.addSchedule, locale: locale)) {
                            let rule = ScheduleRule(
                                title: newRuleTitle.isEmpty ? scheduleActionTitle(newRuleAction, locale: locale) : newRuleTitle,
                                hour: newRuleHour,
                                minute: newRuleMinute,
                                weekdays: newRuleWeekdays.isEmpty ? Set(1...7) : newRuleWeekdays,
                                action: newRuleAction
                            )
                            presenter.dispatch(.addScheduleRule(rule))
                            newRuleTitle = ""
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                    }

                    HStack(spacing: 6) {
                        ForEach(weekdayPairs(locale: locale), id: \.0) { day, label in
                            let selected = newRuleWeekdays.contains(day)
                            Button {
                                if selected { newRuleWeekdays.remove(day) } else { newRuleWeekdays.insert(day) }
                            } label: {
                                Text(label)
                                    .font(.system(size: 11, weight: selected ? .semibold : .medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(selected ? palette.accent.opacity(0.20) : palette.background.opacity(0.6))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(selected ? palette.accent : palette.border, lineWidth: 1)
                                            )
                                    )
                                    .foregroundStyle(selected ? palette.accent : palette.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .compatFocusEffectDisabled()
                        }
                    }

                    if presenter.state.settings.schedules.isEmpty {
                        Text(L10n.text(.noSchedulesHint, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                            .padding(.vertical, 6)
                    } else {
                        VStack(spacing: 6) {
                            ForEach(presenter.state.settings.schedules) { rule in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(
                                        get: { rule.isEnabled },
                                        set: { _ in presenter.dispatch(.toggleScheduleRule(rule.id)) }
                                    ))
                                    .labelsHidden()
                                    .toggleStyle(.switch)
                                    .controlSize(.small)

                                    Text(rule.title)
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(rule.isEnabled ? palette.primaryText : palette.secondaryText)

                                    Spacer()

                                    Text(String(format: "%02d:%02d", rule.hour, rule.minute))
                                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(palette.surface)
                                        .foregroundStyle(palette.primaryText)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Text(scheduleActionTitle(rule.action, locale: locale))
                                        .font(.system(size: 10, weight: .semibold))
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background(palette.accent.opacity(0.16))
                                        .foregroundStyle(palette.accent)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))

                                    Button(role: .destructive) {
                                        presenter.dispatch(.removeScheduleRule(rule.id))
                                    } label: {
                                        Image(systemName: "trash")
                                            .font(.system(size: 11))
                                            .foregroundStyle(palette.danger)
                                    }
                                    .buttonStyle(.plain)
                                    .compatFocusEffectDisabled()
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(palette.background.opacity(0.55))
                                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border.opacity(0.7), lineWidth: 1))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func appearanceAndLayoutSection(locale: AppLocale, palette: ThemePalette) -> some View {
        let theme = presenter.state.settings.theme
        let iconCfg = presenter.state.settings.menuBarIcon
        let layoutCfg = presenter.state.settings.popoverLayout

        VStack(alignment: .leading, spacing: 18) {
            Text(L10n.text(.tabTheme, locale: locale))
                .font(.title2.bold())
                .foregroundStyle(palette.primaryText)

            themedCard(palette: palette) {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(L10n.text(.themePreset, locale: locale))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text(themePresetTitle(theme.preset, locale: locale))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(palette.primaryText)
                        }

                        HStack(spacing: 10) {
                            ForEach(ThemePresetID.allCases) { preset in
                                themeSwatchCard(for: preset, currentTheme: theme, palette: palette, locale: locale)
                            }
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 10) {
                        Text(L10n.text(.workspaceBackgroundTitle, locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)

                        HStack(spacing: 8) {
                            backgroundModeButton(
                                title: L10n.text(.bgSolidTheme, locale: locale),
                                icon: "square.fill",
                                isSelected: !theme.useCustomBackground,
                                palette: palette
                            ) {
                                var next = theme
                                next.useCustomBackground = false
                                presenter.dispatch(.updateTheme(next))
                            }

                            backgroundModeButton(
                                title: L10n.text(.bgCustomImage, locale: locale),
                                icon: "photo",
                                isSelected: theme.useCustomBackground,
                                palette: palette
                            ) {
                                if (theme.customBackgroundPath ?? "").isEmpty {
                                    pickCustomBackgroundImage(currentTheme: theme)
                                } else {
                                    var next = theme
                                    next.useCustomBackground = true
                                    presenter.dispatch(.updateTheme(next))
                                }
                            }
                        }

                        if theme.useCustomBackground {
                            HStack(spacing: 10) {
                                if let thumb = CustomBackgroundImageCache.shared.image(for: theme.customBackgroundPath) {
                                    Image(nsImage: thumb)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 28, height: 28)
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(palette.border, lineWidth: 1))
                                } else {
                                    Image(systemName: "photo.badge.plus")
                                        .font(.system(size: 13))
                                        .foregroundStyle(palette.secondaryText)
                                        .frame(width: 28, height: 28)
                                        .background(RoundedRectangle(cornerRadius: 6).fill(palette.background))
                                }

                                Text(customBackgroundFileName(theme.customBackgroundPath, locale: locale))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(palette.primaryText)
                                    .lineLimit(1)
                                    .truncationMode(.middle)

                                Spacer()

                                Button(L10n.text(.bgChooseImage, locale: locale)) {
                                    pickCustomBackgroundImage(currentTheme: theme)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8).fill(palette.background.opacity(0.6)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border, lineWidth: 1))
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(L10n.text(.bgScrimOpacity, locale: locale))
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText)
                                    Spacer()
                                    Text("\(Int(theme.backgroundScrimOpacity * 100))%")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(palette.primaryText)
                                }
                                Slider(
                                    value: Binding(
                                        get: { theme.backgroundScrimOpacity },
                                        set: {
                                            var next = theme
                                            next.backgroundScrimOpacity = $0
                                            presenter.dispatch(.updateTheme(next))
                                        }
                                    ),
                                    in: 0.0...0.90
                                )
                                .disabled(!theme.useCustomBackground)
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(L10n.text(.bgBlur, locale: locale))
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText)
                                    Spacer()
                                    Text("\(Int(theme.backgroundBlurRadius))px")
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(palette.primaryText)
                                }
                                Slider(
                                    value: Binding(
                                        get: { theme.backgroundBlurRadius },
                                        set: {
                                            var next = theme
                                            next.backgroundBlurRadius = $0
                                            presenter.dispatch(.updateTheme(next))
                                        }
                                    ),
                                    in: 0.0...24.0
                                )
                                .disabled(!theme.useCustomBackground)
                            }
                        }
                        .opacity(theme.useCustomBackground ? 1.0 : 0.45)
                    }

                    Divider()

                    HStack {
                        Text(L10n.text(.customAccent, locale: locale))
                            .font(.callout)
                        Spacer()
                        ForEach(ThemeHexConstants.accentSwatches, id: \.self) { hex in
                            let isCurrentAccent = palette.accentHex.caseInsensitiveCompare(hex) == .orderedSame
                            Button {
                                var next = theme
                                next.customAccentHex = hex
                                presenter.dispatch(.updateTheme(next))
                            } label: {
                                Circle()
                                    .fill(Color(hex: hex))
                                    .frame(width: 22, height: 22)
                                    .overlay(
                                        Circle()
                                            .stroke(isCurrentAccent ? palette.primaryText : Color.clear, lineWidth: 2)
                                    )
                            }
                            .buttonStyle(.plain)
                            .compatFocusEffectDisabled()
                        }
                        TextField("#10B981", text: $customHexInput)
                            .frame(width: 90)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit {
                                var next = theme
                                next.customAccentHex = customHexInput
                                presenter.dispatch(.updateTheme(next))
                            }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text(.batteryColorStyleTitle, locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                        HStack(spacing: 8) {
                            ForEach(BatteryColorStyle.allCases, id: \.self) { style in
                                let isSelected = theme.batteryColorStyle == style
                                Button {
                                    var next = theme
                                    next.batteryColorStyle = style
                                    presenter.dispatch(.updateTheme(next))
                                } label: {
                                    Text(batteryColorStyleTitle(style, locale: locale))
                                        .font(.caption.weight(isSelected ? .semibold : .medium))
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 6)
                                        .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                                        .background(
                                            RoundedRectangle(cornerRadius: 7)
                                                .fill(isSelected ? palette.accent.opacity(0.18) : palette.background.opacity(0.55))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 7)
                                                        .stroke(isSelected ? palette.accent : palette.border, lineWidth: 1)
                                                )
                                        )
                                }
                                .buttonStyle(.plain)
                                .compatFocusEffectDisabled()
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(L10n.text(.cornerRadius, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text("\(Int(theme.cornerRadius))px")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(palette.primaryText)
                        }
                        Slider(
                            value: Binding(
                                get: { theme.cornerRadius },
                                set: {
                                    var next = theme
                                    next.cornerRadius = $0.rounded()
                                    presenter.dispatch(.updateTheme(next))
                                }
                            ),
                            in: VoltGuardLimits.minCornerRadius...VoltGuardLimits.maxCornerRadius
                        )
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(L10n.text(.surfaceOpacity, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.secondaryText)
                            Spacer()
                            Text("\(Int(theme.surfaceOpacity * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(palette.primaryText)
                        }
                        Slider(
                            value: Binding(
                                get: { theme.surfaceOpacity },
                                set: {
                                    var next = theme
                                    next.surfaceOpacity = ($0 * 100).rounded() / 100
                                    presenter.dispatch(.updateTheme(next))
                                }
                            ),
                            in: VoltGuardLimits.minSurfaceOpacity...VoltGuardLimits.maxSurfaceOpacity
                        )
                    }
                }
            }

            themedCard(title: L10n.text(.tabInterface, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.text(.menuBarStyle, locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                        HStack(spacing: 8) {
                            ForEach(MenuBarIconStyle.allCases, id: \.self) { style in
                                let isSelected = iconCfg.style == style
                                Button {
                                    var next = iconCfg
                                    next.style = style
                                    presenter.dispatch(.updateMenuBarConfig(next))
                                } label: {
                                    VStack(spacing: 5) {
                                        Image(systemName: iconStyleSymbol(style))
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(isSelected ? palette.accent : palette.primaryText)
                                            .accessibilityHidden(true)
                                        Text(iconStyleTitle(style, locale: locale))
                                            .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                            .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.85)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                    .padding(.horizontal, 6)
                                    .contentShape(Rectangle())
                                    .background(
                                        RoundedRectangle(cornerRadius: 8)
                                            .fill(isSelected ? palette.accent.opacity(0.18) : palette.background.opacity(0.55))
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8)
                                                    .stroke(isSelected ? palette.accent : palette.border, lineWidth: 1)
                                            )
                                    )
                                }
                                .buttonStyle(.plain)
                                .compatFocusEffectDisabled()
                            }
                        }
                    }
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        menuBarBadgeToggleCard(
                            title: L10n.text(.showPercentage, locale: locale),
                            icon: "percent",
                            isOn: iconCfg.showPercentage,
                            palette: palette
                        ) {
                            var next = iconCfg
                            next.showPercentage.toggle()
                            presenter.dispatch(.updateMenuBarConfig(next))
                        }

                        menuBarBadgeToggleCard(
                            title: L10n.text(.showWattage, locale: locale),
                            icon: "bolt.fill",
                            isOn: iconCfg.showWattage,
                            palette: palette
                        ) {
                            var next = iconCfg
                            next.showWattage.toggle()
                            presenter.dispatch(.updateMenuBarConfig(next))
                        }

                        menuBarBadgeToggleCard(
                            title: L10n.text(.showTemperature, locale: locale),
                            icon: "thermometer.medium",
                            isOn: iconCfg.showTemperature,
                            palette: palette
                        ) {
                            var next = iconCfg
                            next.showTemperature.toggle()
                            presenter.dispatch(.updateMenuBarConfig(next))
                        }

                        menuBarBadgeToggleCard(
                            title: L10n.text(.showTimeRemaining, locale: locale),
                            icon: "clock",
                            isOn: iconCfg.showTimeRemaining,
                            palette: palette
                        ) {
                            var next = iconCfg
                            next.showTimeRemaining.toggle()
                            presenter.dispatch(.updateMenuBarConfig(next))
                        }
                    }

                    Divider()

                    HStack {
                        Text(L10n.text(.popoverDensity, locale: locale))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        HStack(spacing: 6) {
                            ForEach(PopoverDensity.allCases, id: \.self) { density in
                                let isSelected = layoutCfg.density == density
                                Button {
                                    var next = layoutCfg
                                    next.density = density
                                    presenter.dispatch(.updatePopoverLayout(next))
                                } label: {
                                    Text(densityTitle(density, locale: locale))
                                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 5)
                                        .foregroundStyle(isSelected ? (palette.isDark ? Color.black : Color.white) : palette.primaryText)
                                        .background(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .fill(isSelected ? palette.accent : palette.background.opacity(0.65))
                                        )
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                                .strokeBorder(isSelected ? Color.clear : palette.border, lineWidth: 1)
                                        )
                                        .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .compatFocusEffectDisabled()
                            }
                        }
                    }

                    Divider()

                    VStack(spacing: 6) {
                        ForEach(Array(layoutCfg.orderedModules.enumerated()), id: \.element) { idx, mod in
                            let isVisible = !layoutCfg.hiddenModules.contains(mod)
                            HStack(spacing: 10) {
                                Toggle("", isOn: Binding(
                                    get: { isVisible },
                                    set: { visible in
                                        var next = layoutCfg
                                        if visible { next.hiddenModules.remove(mod) } else { next.hiddenModules.insert(mod) }
                                        presenter.dispatch(.updatePopoverLayout(next))
                                    }
                                ))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)

                                Text(moduleTitle(mod, locale: locale))
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(isVisible ? palette.primaryText : palette.secondaryText)

                                Spacer()

                                Button {
                                    presenter.dispatch(.movePopoverModule(mod, -1))
                                } label: {
                                    Image(systemName: "arrow.up")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 22, height: 22)
                                        .background(palette.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .compatFocusEffectDisabled()
                                .disabled(idx == 0)
                                .opacity(idx == 0 ? 0.35 : 1)
                                .accessibilityLabel(Text(L10n.text(.moveUp, locale: locale)))

                                Button {
                                    presenter.dispatch(.movePopoverModule(mod, 1))
                                } label: {
                                    Image(systemName: "arrow.down")
                                        .font(.system(size: 10, weight: .bold))
                                        .frame(width: 22, height: 22)
                                        .background(palette.surface)
                                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                                }
                                .buttonStyle(.plain)
                                .compatFocusEffectDisabled()
                                .disabled(idx == layoutCfg.orderedModules.count - 1)
                                .opacity(idx == layoutCfg.orderedModules.count - 1 ? 0.35 : 1)
                                .accessibilityLabel(Text(L10n.text(.moveDown, locale: locale)))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.background.opacity(0.5))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.border.opacity(0.6), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func systemAndGuideSection(locale: AppLocale, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.text(.tabGuide, locale: locale))
                .font(.title2.bold())
                .foregroundStyle(palette.primaryText)

            themedCard(title: "SMC Helper & System Startup", palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    settingToggleRow(
                        icon: "power.circle.fill",
                        title: L10n.text(.launchAtLogin, locale: locale),
                        subtitle: L10n.text(.launchAtLoginDesc, locale: locale),
                        isOn: presenter.state.settings.launchAtLogin,
                        palette: palette
                    ) { presenter.dispatch(.toggleLaunchAtLogin) }

                    settingToggleRow(
                        icon: "bell.badge.fill",
                        title: L10n.text(.smartAlerts, locale: locale),
                        subtitle: L10n.text(.smartAlertsDesc, locale: locale),
                        isOn: presenter.state.settings.alertsEnabled,
                        palette: palette
                    ) { presenter.dispatch(.toggleSmartAlerts) }

                    let helperNeedsUpdate = presenter.state.helperNeedsUpdate || presenter.state.smcBackendMode == .outdatedHelper
                    if helperNeedsUpdate {
                        HStack(spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(palette.warning)
                            Text(L10n.text(.helperOutdatedBanner, locale: locale))
                                .font(.caption)
                                .foregroundStyle(palette.primaryText)
                            Spacer()
                            Button(L10n.text(.updateHelperNow, locale: locale)) {
                                presenter.dispatch(.installHelper)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(palette.warning)
                            .controlSize(.small)
                        }
                        .padding(10)
                        .background(palette.warning.opacity(0.14))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.warning.opacity(0.45), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Circle()
                                .fill(helperNeedsUpdate ? palette.warning : (presenter.state.helperConnected ? palette.accent : palette.warning))
                                .frame(width: 8, height: 8)
                            Text(L10n.text(presenter.state.helperConnected ? .helperConnected : .helperDryRun, locale: locale))
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            if presenter.state.helperConnected && !helperNeedsUpdate {
                                let modeText = presenter.state.smcBackendMode == .adapterMode ? L10n.text(.smcModeAdapter, locale: locale) : (presenter.state.smcBackendMode == .firmwareManaged ? L10n.text(.smcModeFirmware, locale: locale) : L10n.text(.smcModeLegacy, locale: locale))
                                Text(modeText)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(palette.accent.opacity(0.14))
                                    .foregroundStyle(palette.accent)
                                    .clipShape(Capsule())
                            }
                            Spacer()
                        }
                        HStack(spacing: 8) {
                            Button {
                                presenter.dispatch(.testToolbarEvent)
                            } label: {
                                Label(L10n.text(.testToolbarAlert, locale: locale), systemImage: "bell.badge.fill")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .buttonStyle(.bordered)
                            .tint(palette.accent)
                            .controlSize(.small)

                            Spacer()

                            if presenter.state.helperConnected {
                                Button(L10n.text(.uninstallHelper, locale: locale)) {
                                    presenter.dispatch(.uninstallHelper)
                                }
                                .buttonStyle(.bordered)
                                .tint(palette.danger)
                                .controlSize(.small)
                            }
                            Button(L10n.text(helperNeedsUpdate ? .updateHelperNow : .installHelper, locale: locale)) {
                                presenter.dispatch(.installHelper)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(helperNeedsUpdate ? palette.warning : palette.accent)
                            .controlSize(.small)
                        }
                    }
                    .padding(.top, 2)

                    if let err = presenter.state.helperErrorMessage {
                        Text(err).font(.caption).foregroundStyle(palette.danger)
                    }
                }
            }

            let compat = presenter.state.effectiveCompatibility
            let hw = compat.hardwareProfile
            let keysList = compat.writableKeys
            themedCard(title: L10n.text(.compatCardTitle, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Text(L10n.text(.compatCachedBadge, locale: locale))
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(palette.accent.opacity(0.16))
                            .foregroundStyle(palette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                        Text(compat.checkedAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.caption2.monospaced())
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Button(L10n.text(.compatRecheckButton, locale: locale)) {
                            presenter.dispatch(.recheckCompatibility)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        detailMetricCell(label: L10n.text(.compatModelLabel, locale: locale), value: hw.modelIdentifier, palette: palette)
                        detailMetricCell(label: L10n.text(.compatChipOSLabel, locale: locale), value: "\(hw.architecture) · macOS \(hw.macOSVersionString)", palette: palette)
                    }
                    detailMetricCell(
                        label: L10n.text(.compatControlModeLabel, locale: locale),
                        value: keysList.isEmpty ? compat.backendMode.rawValue : "\(compat.backendMode.rawValue) (\(keysList.joined(separator: ", ")))",
                        palette: palette
                    )
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        compatCapabilityBadge(
                            title: L10n.text(.compatFeatureChargeLimit, locale: locale),
                            status: compat.chargeLimit,
                            locale: locale,
                            palette: palette
                        )
                        compatCapabilityBadge(
                            title: L10n.text(.compatFeatureDischarge, locale: locale),
                            status: compat.discharge,
                            locale: locale,
                            palette: palette
                        )
                        compatCapabilityBadge(
                            title: L10n.text(.compatFeatureMagSafe, locale: locale),
                            status: compat.magSafeLED,
                            locale: locale,
                            palette: palette
                        )
                        compatCapabilityBadge(
                            title: L10n.text(.compatFeatureLowPower, locale: locale),
                            status: compat.lowPowerMode,
                            locale: locale,
                            palette: palette
                        )
                    }
                }
            }

            themedCard(title: L10n.text(.diagnosticsTitle, locale: locale), palette: palette) {
                let isScanning = presenter.state.isRunningDiagnostics
                let scanStep = presenter.state.diagnosticsScanStep
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text(L10n.text(.globalHotkeyHint, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Button {
                            presenter.dispatch(.runDiagnostics)
                        } label: {
                            HStack(spacing: 6) {
                                if isScanning {
                                    ProgressView()
                                        .controlSize(.small)
                                        .scaleEffect(0.75)
                                } else {
                                    Image(systemName: "play.circle.fill")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                Text(L10n.text(isScanning ? .diagScanning : .runDiagnostics, locale: locale))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .disabled(isScanning)
                    }

                    if isScanning {
                        VStack(alignment: .leading, spacing: 4) {
                            ProgressView(value: Double(scanStep), total: 8.0)
                                .tint(palette.accent)
                            Text("\(L10n.text(.diagScanning, locale: locale)) (\(min(scanStep + 1, 8))/8)")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(palette.accent)
                        }
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    } else if let diag = presenter.state.diagnostics {
                        let checks = [
                            diag.iokitReadable,
                            diag.appleSMCReadable,
                            diag.temperatureSensorLive,
                            diag.smcHelperConnected,
                            diag.smcHelperUpToDate,
                            diag.launchAtLoginEnabled,
                            diag.alertsEnabled,
                            diag.crashReportCount == 0
                        ]
                        let passedCount = checks.filter { $0 }.count
                        let allPassed = (passedCount == checks.count)
                        HStack(spacing: 8) {
                            Image(systemName: allPassed ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(allPassed ? palette.accent : palette.warning)
                            Text("\(passedCount)/\(checks.count) · \(L10n.text(allPassed ? .diagAllPassed : .diagNeedsAttention, locale: locale))")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(palette.primaryText)
                            Spacer()
                            Text("\(L10n.text(.diagLastChecked, locale: locale)) \(diag.checkedAt.formatted(date: .omitted, time: .standard))")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                                .contentTransition(.numericText())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background((allPassed ? palette.accent : palette.warning).opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder((allPassed ? palette.accent : palette.warning).opacity(0.35), lineWidth: 1))
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }

                    if let diag = presenter.state.diagnostics {
                        if let summary = diag.sensorSummary {
                            HStack(spacing: 6) {
                                Image(systemName: "waveform.path.ecg")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(palette.accent)
                                Text(summary)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(palette.accent.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(palette.accent.opacity(0.35), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        if let tempSummary = diag.temperatureSummary {
                            HStack(spacing: 6) {
                                Image(systemName: "thermometer.medium")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(diag.temperatureSensorLive ? palette.accent : palette.warning)
                                Text(tempSummary)
                                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((diag.temperatureSensorLive ? palette.accent : palette.warning).opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder((diag.temperatureSensorLive ? palette.accent : palette.warning).opacity(0.35), lineWidth: 1))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        diagRow(label: L10n.text(.diagIOKit, locale: locale), ok: diag.iokitReadable, stepIndex: 0, isScanning: isScanning, currentStep: scanStep, palette: palette, locale: locale)
                        diagRow(label: L10n.text(.diagAppleSMCDriver, locale: locale), ok: diag.appleSMCReadable, stepIndex: 1, isScanning: isScanning, currentStep: scanStep, palette: palette, locale: locale)
                        diagRow(label: L10n.text(.diagTempSensor, locale: locale), ok: diag.temperatureSensorLive, stepIndex: 2, isScanning: isScanning, currentStep: scanStep, palette: palette, locale: locale)
                        diagRow(label: L10n.text(.diagHelper, locale: locale), ok: diag.smcHelperConnected, stepIndex: 3, isScanning: isScanning, currentStep: scanStep, palette: palette, locale: locale)
                        diagRow(
                            label: L10n.text(.diagHelperVersion, locale: locale),
                            ok: diag.smcHelperUpToDate,
                            failBadgeKey: .diagUpdateNeeded,
                            stepIndex: 4,
                            isScanning: isScanning,
                            currentStep: scanStep,
                            palette: palette,
                            locale: locale
                        )
                        diagRow(label: L10n.text(.diagLogin, locale: locale), ok: diag.launchAtLoginEnabled, stepIndex: 5, isScanning: isScanning, currentStep: scanStep, palette: palette, locale: locale)
                        diagRow(label: L10n.text(.diagAlerts, locale: locale), ok: diag.alertsEnabled, stepIndex: 6, isScanning: isScanning, currentStep: scanStep, palette: palette, locale: locale)
                        diagRow(
                            label: L10n.text(.diagCrashReporter, locale: locale),
                            ok: diag.crashReportCount == 0,
                            failBadgeKey: .diagCrashDetected,
                            stepIndex: 7,
                            isScanning: isScanning,
                            currentStep: scanStep,
                            palette: palette,
                            locale: locale
                        )
                        if let latestCrash = diag.latestCrashSummary {
                            Text(latestCrash)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(palette.secondaryText)
                                .lineLimit(2)
                        }
                        HStack(spacing: 8) {
                            Button(L10n.text(.openCrashLogs, locale: locale)) {
                                presenter.dispatch(.openCrashLogs)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            if diag.crashReportCount > 0 {
                                Button(L10n.text(.clearCrashLogs, locale: locale)) {
                                    presenter.dispatch(.clearCrashLogs)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    } else if isScanning {
                        let placeholderLabels = [
                            L10n.text(.diagIOKit, locale: locale),
                            L10n.text(.diagAppleSMCDriver, locale: locale),
                            L10n.text(.diagTempSensor, locale: locale),
                            L10n.text(.diagHelper, locale: locale),
                            L10n.text(.diagHelperVersion, locale: locale),
                            L10n.text(.diagLogin, locale: locale),
                            L10n.text(.diagAlerts, locale: locale),
                            L10n.text(.diagCrashReporter, locale: locale)
                        ]
                        ForEach(Array(placeholderLabels.enumerated()), id: \.offset) { index, label in
                            diagRow(label: label, ok: false, stepIndex: index, isScanning: true, currentStep: scanStep, palette: palette, locale: locale)
                        }
                    }
                }
                .animation(.spring(response: 0.28, dampingFraction: 0.85), value: scanStep)
                .animation(.easeInOut(duration: 0.2), value: isScanning)
                .onAppear {
                    if presenter.state.diagnostics == nil && !presenter.state.isRunningDiagnostics {
                        presenter.dispatch(.runDiagnostics)
                    }
                }
            }

            themedCard(title: L10n.text(.healthHistoryTitle, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(String(format: L10n.text(.daysRecordedFormat, locale: locale), presenter.state.healthSnapshots.count))
                            .font(.callout)
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Button(L10n.text(.exportCSV, locale: locale)) {
                            presenter.dispatch(.exportHealthCSV)
                        }
                        .buttonStyle(.bordered)
                    }
                    if presenter.state.csvExportFeedback {
                        Text(L10n.text(.csvCopiedHint, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.accent)
                    }
                    if presenter.state.healthSnapshots.isEmpty {
                        Text(L10n.text(.healthHistoryEmpty, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    } else {
                        ForEach(presenter.state.healthSnapshots.suffix(5).reversed()) { snap in
                            HStack {
                                Text(snap.id).font(.caption.monospaced())
                                Spacer()
                                Text("\(snap.healthPercent)%  |  \(snap.cycleCount) cyc  |  \(String(format: "%.1f C", snap.peakTemperatureCelsius))")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
            }

            themedCard(title: L10n.text(.settingsBackupTitle, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Button(L10n.text(.exportSettings, locale: locale)) {
                            presenter.dispatch(.exportSettingsJSON)
                        }
                        .buttonStyle(.bordered)

                        Button(L10n.text(.importSettings, locale: locale)) {
                            let json = NSPasteboard.general.string(forType: .string) ?? ""
                            presenter.dispatch(.importSettingsJSON(json))
                        }
                        .buttonStyle(.bordered)

                        Spacer()

                        Button(L10n.text(.resetSettings, locale: locale)) {
                            presenter.dispatch(.resetSettingsToDefault)
                        }
                        .buttonStyle(.bordered)
                        .tint(palette.danger)
                    }
                    if let feedback = presenter.state.settingsFeedbackMessage {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(palette.accent)
                    }
                }
            }

            themedCard(title: L10n.text(.activityLogTitle, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 6) {
                    if presenter.state.activityLog.isEmpty {
                        Text(L10n.text(.activityLogEmpty, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    } else {
                        ForEach(presenter.state.activityLog.prefix(8)) { entry in
                            HStack {
                                Text(L10n.text(entry.messageKey, locale: locale))
                                    .font(.caption)
                                    .foregroundStyle(palette.primaryText)
                                Spacer()
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }
                    }
                }
            }

            themedCard(title: L10n.text(.appUpdatesTitle, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "shippingbox.circle.fill")
                                .font(.title3)
                                .foregroundStyle(palette.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VoltGuard v\(AppReleaseInfo.currentVersion) (Build \(AppReleaseInfo.buildNumber))")
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(palette.primaryText)
                                Text(AppReleaseInfo.githubRepo)
                                    .font(.caption.monospaced())
                                    .foregroundStyle(palette.secondaryText)
                            }
                        }

                        Spacer()

                        Button {
                            presenter.dispatch(.checkForUpdates)
                        } label: {
                            HStack(spacing: 6) {
                                if presenter.state.isCheckingUpdates {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Text(L10n.text(presenter.state.isCheckingUpdates ? .checkingUpdates : .checkUpdatesButton, locale: locale))
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                        .disabled(presenter.state.isCheckingUpdates || presenter.state.isInstallingUpdate)

                        Button(L10n.text(.openReleasesPage, locale: locale)) {
                            if let url = URL(string: presenter.state.updateResult?.releaseURL ?? AppReleaseInfo.releasesWebURL) {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    if let update = presenter.state.updateResult {
                        HStack(spacing: 10) {
                            Image(systemName: update.isUpdateAvailable ? "arrow.down.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(update.isUpdateAvailable ? palette.warning : palette.accent)
                            Text(
                                String(
                                    format: L10n.text(update.isUpdateAvailable ? .updateAvailableBanner : .upToDateBanner, locale: locale),
                                    update.latestVersion
                                )
                            )
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(palette.primaryText)
                            Spacer()
                            if update.isUpdateAvailable, update.dmgDownloadURL != nil {
                                Button {
                                    presenter.dispatch(.installUpdate)
                                } label: {
                                    HStack(spacing: 6) {
                                        if presenter.state.isInstallingUpdate {
                                            ProgressView().controlSize(.small)
                                        }
                                        Text(L10n.text(presenter.state.isInstallingUpdate ? .installingUpdate : .installUpdateButton, locale: locale))
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .tint(palette.warning)
                                .disabled(presenter.state.isInstallingUpdate)
                            }
                        }
                        .padding(10)
                        .background((update.isUpdateAvailable ? palette.warning : palette.accent).opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder((update.isUpdateAvailable ? palette.warning : palette.accent).opacity(0.35), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    if let updateFeedback = presenter.state.updateFeedbackMessage {
                        Text(updateFeedback)
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                    }

                    Divider()

                    Text(L10n.text(.changelogLogTitle, locale: locale))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.secondaryText)

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(AppReleaseInfo.changelog) { entry in
                            let isCurrent = entry.version == AppReleaseInfo.currentVersion
                            let title = locale == .id ? entry.titleID : entry.titleEN
                            let highlights = locale == .id ? entry.highlightsID : entry.highlightsEN
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("v\(entry.version)")
                                        .font(.caption.bold().monospacedDigit())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 2)
                                        .background((isCurrent ? palette.accent : palette.secondaryText).opacity(0.16))
                                        .foregroundStyle(isCurrent ? palette.accent : palette.secondaryText)
                                        .clipShape(Capsule())
                                    Text(title)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(palette.primaryText)
                                    Spacer()
                                    Text(entry.date)
                                        .font(.caption2.monospaced())
                                        .foregroundStyle(palette.secondaryText)
                                }
                                ForEach(Array(highlights.enumerated()), id: \.offset) { _, line in
                                    Text("* \(line)")
                                        .font(.caption)
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(palette.background.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                    }
                }
            }

            themedCard(title: L10n.text(.appTitle, locale: locale), palette: palette) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(L10n.text(.userGuideSummary, locale: locale))
                    Divider()
                    Text("Apple Shortcuts: Set VoltGuard Charge Limit, Toggle VoltGuard Discharge, Top Up Battery to 100%, Get VoltGuard Battery Telemetry")
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private func diagRow(
        label: String,
        ok: Bool,
        failBadgeKey: L10nKey = .diagInactive,
        stepIndex: Int,
        isScanning: Bool,
        currentStep: Int,
        palette: ThemePalette,
        locale: AppLocale
    ) -> some View {
        let isChecking = isScanning && stepIndex == currentStep
        let isQueued = isScanning && stepIndex > currentStep
        let badgeColor: Color = isChecking ? palette.accent : (isQueued ? palette.secondaryText : (ok ? palette.accent : palette.warning))
        let badgeKey: L10nKey = isChecking ? .diagChecking : (isQueued ? .diagQueued : (ok ? .diagPass : failBadgeKey))

        HStack {
            if isChecking {
                ProgressView()
                    .controlSize(.small)
                    .scaleEffect(0.68)
                    .frame(width: 14, height: 14)
            } else if isQueued {
                Image(systemName: "circle.dotted")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText.opacity(0.65))
            } else {
                Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(ok ? palette.accent : palette.warning)
                    .transition(.scale.combined(with: .opacity))
            }
            Text(label)
                .font(.system(size: 12, weight: isChecking ? .semibold : .medium))
                .foregroundStyle(isQueued ? palette.secondaryText : palette.primaryText)
            Spacer()
            Text(L10n.text(badgeKey, locale: locale))
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(badgeColor.opacity(0.18))
                .foregroundStyle(badgeColor)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isChecking ? palette.accent.opacity(0.08) : palette.background.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isChecking ? palette.accent.opacity(0.55) : palette.border.opacity(0.6), lineWidth: isChecking ? 1.2 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .opacity(isQueued ? 0.65 : 1.0)
    }

    @ViewBuilder
    private func menuBarBadgeToggleCard(
        title: String,
        icon: String,
        isOn: Bool,
        palette: ThemePalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(isOn ? palette.accent : palette.secondaryText)
                    .frame(width: 22, height: 22)
                    .background(
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(isOn ? palette.accent.opacity(0.16) : palette.surface)
                    )
                Text(title)
                    .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 13))
                    .foregroundStyle(isOn ? palette.accent : palette.secondaryText.opacity(0.5))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isOn ? palette.accent.opacity(0.10) : palette.background.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isOn ? palette.accent.opacity(0.55) : palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .compatFocusEffectDisabled()
    }

    @ViewBuilder
    private func settingToggleRow(
        icon: String,
        title: String,
        subtitle: String,
        isOn: Bool,
        isDisabled: Bool = false,
        palette: ThemePalette,
        onToggle: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(isOn && !isDisabled ? palette.accent : palette.secondaryText)
                .frame(width: 26, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isOn && !isDisabled ? palette.accent.opacity(0.16) : palette.surface)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(isDisabled ? palette.warning : palette.secondaryText)
                    .lineLimit(2)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { isOn && !isDisabled },
                set: { _ in if !isDisabled { onToggle() } }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(isDisabled)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isOn && !isDisabled ? palette.accent.opacity(0.08) : palette.background.opacity(0.5))
        )
        .opacity(isDisabled ? 0.55 : 1.0)
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isOn ? palette.accent.opacity(0.45) : palette.border.opacity(0.65), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onTapGesture {
            onToggle()
        }
    }

    private func ledDotColor(_ mode: MagSafeLEDMode, palette: ThemePalette) -> Color {
        switch mode {
        case .system: return palette.accent
        case .off: return palette.secondaryText.opacity(0.4)
        case .green: return Color(hex: "#22C55E")
        case .amber: return Color(hex: "#F59E0B")
        case .syncWithLimit: return palette.accent
        case .matchBattery:
            if case .loaded(let t, _) = presenter.state.telemetryState {
                if t.temperatureCelsius >= presenter.state.settings.policy.maxTemperatureCelsius || t.percentage <= VoltGuardLimits.lowBatteryAlertThresholdPercent {
                    return Color(hex: "#EF4444")
                }
                if t.percentage < 50 || t.isCharging {
                    return Color(hex: "#F59E0B")
                }
                return Color(hex: "#22C55E")
            }
            return Color(hex: "#10B981")
        }
    }

    private func impactLabel(_ level: EnergyImpactLevel, locale: AppLocale) -> String {
        switch level {
        case .low: return L10n.text(.energyImpactLow, locale: locale)
        case .medium: return L10n.text(.energyImpactMedium, locale: locale)
        case .high: return L10n.text(.energyImpactHigh, locale: locale)
        }
    }

    private func impactColor(_ level: EnergyImpactLevel, palette: ThemePalette) -> Color {
        switch level {
        case .low: return palette.accent
        case .medium: return palette.warning
        case .high: return palette.danger
        }
    }

    private func dashboardVisualMode(_ reason: PolicyReason, telemetry: BatteryTelemetry) -> BatteryVisualMode {
        let activelyCharging = telemetry.isCharging || (telemetry.isPluggedIn && telemetry.amperageAmps > VoltGuardLimits.minETACurrentAmps)
        switch reason {
        case .heatProtectionPaused: return .heatPaused
        case .manualDischarge, .automaticDischarge: return .discharging
        case .calibrationActive: return activelyCharging ? .charging : .discharging
        case .limitReached, .sailingPaused, .sleepingInhibited: return .limitReached
        case .normalCharging, .topUpActive:
            if !telemetry.isPluggedIn { return .onBattery }
            return activelyCharging ? .charging : .limitReached
        }
    }

    private func moduleTitle(_ module: PopoverModuleID, locale: AppLocale) -> String {
        switch module {
        case .chargeControl: return L10n.text(.moduleChargeControl, locale: locale)
        case .powerFlow: return L10n.text(.modulePowerFlow, locale: locale)
        case .quickActions: return L10n.text(.moduleQuickActions, locale: locale)
        case .calibrationAndSchedule: return L10n.text(.moduleCalibrationSchedule, locale: locale)
        case .batteryHealth: return L10n.text(.moduleBatteryHealth, locale: locale)
        }
    }

    private func ledModeTitle(_ mode: MagSafeLEDMode, locale: AppLocale) -> String {
        switch mode {
        case .system: return L10n.text(.ledSystem, locale: locale)
        case .off: return L10n.text(.ledOff, locale: locale)
        case .green: return L10n.text(.ledGreen, locale: locale)
        case .amber: return L10n.text(.ledAmber, locale: locale)
        case .syncWithLimit: return L10n.text(.ledSyncWithLimit, locale: locale)
        case .matchBattery: return L10n.text(.ledMatchBattery, locale: locale)
        }
    }

    private func batteryColorStyleTitle(_ style: BatteryColorStyle, locale: AppLocale) -> String {
        switch style {
        case .adaptiveSpectrum: return L10n.text(.batteryColorSpectrum, locale: locale)
        case .thermalReactive: return L10n.text(.batteryColorThermal, locale: locale)
        case .themeAccent: return L10n.text(.batteryColorAccent, locale: locale)
        }
    }

    private func compatReasonText(_ status: FeatureCapabilityStatus, locale: AppLocale) -> String {
        if status.supported {
            return L10n.text(.compatStatusSupported, locale: locale)
        }
        switch status.reasonCode {
        case "adapter_mode_cuts_magsafe":
            return L10n.text(.compatReasonAdapterMagSafe, locale: locale)
        case "no_magsafe3_hardware":
            return L10n.text(.compatReasonNoMagSafe3, locale: locale)
        case "adapter_mode_hysteresis":
            return L10n.text(.compatReasonAdapterHysteresis, locale: locale)
        case "smc_keys_locked":
            return L10n.text(.compatReasonSMCLocked, locale: locale)
        case "discharge_keys_unavailable":
            return L10n.text(.compatReasonDischargeNA, locale: locale)
        case "low_power_unsupported":
            return L10n.text(.compatReasonLowPowerNA, locale: locale)
        case "no_battery_desktop":
            return L10n.text(.compatReasonDesktop, locale: locale)
        default:
            return L10n.text(.compatStatusUnavailable, locale: locale)
        }
    }

    @ViewBuilder
    private func compatCapabilityBadge(title: String, status: FeatureCapabilityStatus, locale: AppLocale, palette: ThemePalette) -> some View {
        let supported = status.supported
        HStack(spacing: 6) {
            Image(systemName: supported ? "checkmark.circle.fill" : "minus.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(supported ? palette.accent : palette.warning)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
                Text(compatReasonText(status, locale: locale))
                    .font(.system(size: 10))
                    .foregroundStyle(supported ? palette.accent : palette.warning)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(palette.background.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder((supported ? palette.accent : palette.warning).opacity(0.45), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private func scheduleActionTitle(_ action: ScheduleAction, locale: AppLocale) -> String {
        switch action {
        case .setLimit80: return L10n.text(.scheduleSetLimit80, locale: locale)
        case .topUp100: return L10n.text(.scheduleTopUp100, locale: locale)
        case .enableDischarge: return L10n.text(.scheduleEnableDischarge, locale: locale)
        case .disableDischarge: return L10n.text(.scheduleDisableDischarge, locale: locale)
        }
    }

    private func weekdayPairs(locale: AppLocale) -> [(Int, String)] {
        if locale == .id {
            return [(1, "Min"), (2, "Sen"), (3, "Sel"), (4, "Rab"), (5, "Kam"), (6, "Jum"), (7, "Sab")]
        }
        return [(1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"), (5, "Thu"), (6, "Fri"), (7, "Sat")]
    }

    private func themePresetTitle(_ preset: ThemePresetID, locale: AppLocale) -> String {
        switch preset {
        case .obsidianSlate: return L10n.text(.presetObsidianSlate, locale: locale)
        case .paperLight: return L10n.text(.presetPaperLight, locale: locale)
        case .nordicMist: return L10n.text(.presetNordicMist, locale: locale)
        case .midnightAmber: return L10n.text(.presetMidnightAmber, locale: locale)
        }
    }

    private func iconStyleTitle(_ style: MenuBarIconStyle, locale: AppLocale) -> String {
        switch style {
        case .shieldBattery: return L10n.text(.iconStyleShield, locale: locale)
        case .ringGauge: return L10n.text(.iconStyleRing, locale: locale)
        case .percentagePill: return L10n.text(.iconStylePill, locale: locale)
        case .minimalBolt: return L10n.text(.iconStyleBolt, locale: locale)
        }
    }

    private func densityTitle(_ density: PopoverDensity, locale: AppLocale) -> String {
        switch density {
        case .detailed: return L10n.text(.densityDetailed, locale: locale)
        case .compact: return L10n.text(.densityCompact, locale: locale)
        }
    }

    private func customBackgroundFileName(_ path: String?, locale: AppLocale) -> String {
        guard let path, !path.isEmpty else {
            return L10n.text(.bgNoImageSelected, locale: locale)
        }
        return URL(fileURLWithPath: path).lastPathComponent
    }

    private func pickCustomBackgroundImage(currentTheme: ThemeConfig) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK, let url = panel.url {
            var next = currentTheme
            next.customBackgroundPath = url.path
            next.useCustomBackground = true
            presenter.dispatch(.updateTheme(next))
        }
    }

    @ViewBuilder
    private func backgroundModeButton(
        title: String,
        icon: String,
        isSelected: Bool,
        palette: ThemePalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(isSelected ? palette.accent : palette.secondaryText)
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .foregroundStyle(palette.primaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? palette.accent.opacity(0.18) : palette.background.opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? palette.accent : palette.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .compatFocusEffectDisabled()
    }

    @ViewBuilder
    private func themeSwatchCard(
        for preset: ThemePresetID,
        currentTheme: ThemeConfig,
        palette: ThemePalette,
        locale: AppLocale
    ) -> some View {
        let isSelected = currentTheme.preset == preset
        let spec: ThemeHexConstants.PaletteSpec = {
            switch preset {
            case .obsidianSlate: return ThemeHexConstants.obsidianSlate
            case .paperLight: return ThemeHexConstants.paperLight
            case .nordicMist: return ThemeHexConstants.nordicMist
            case .midnightAmber: return ThemeHexConstants.midnightAmber
            }
        }()
        let bgColor = Color(hex: spec.background)
        let railColor = Color(hex: spec.surface)
        let lineColor = Color(hex: spec.secondaryText).opacity(0.45)
        let swatchAccent = Color(hex: (currentTheme.customAccentHex?.isValidHex == true) ? currentTheme.customAccentHex! : spec.accent)

        Button {
            var next = currentTheme
            next.preset = preset
            presenter.dispatch(.updateTheme(next))
        } label: {
            VStack(spacing: 6) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(bgColor)

                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(railColor)
                            .frame(width: 22)
                            .overlay(alignment: .topLeading) {
                                VStack(alignment: .leading, spacing: 3) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(swatchAccent)
                                        .frame(width: 12, height: 3)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(lineColor)
                                        .frame(width: 10, height: 2.5)
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(lineColor)
                                        .frame(width: 12, height: 2.5)
                                }
                                .padding(4)
                            }

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 3) {
                                Circle().fill(lineColor).frame(width: 3, height: 3)
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(lineColor)
                                    .frame(width: 24, height: 2.5)
                                Spacer()
                            }
                            RoundedRectangle(cornerRadius: 2.5)
                                .fill(railColor)
                                .frame(height: 16)
                                .overlay(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 1)
                                        .fill(swatchAccent)
                                        .frame(width: 16, height: 2.5)
                                        .padding(.leading, 4)
                                }
                        }
                        .padding(5)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .frame(height: 46)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isSelected ? palette.accent : palette.border, lineWidth: isSelected ? 1.5 : 1)
                )

                HStack(spacing: 4) {
                    Text(themePresetTitle(preset, locale: locale))
                        .font(.system(size: 11, weight: isSelected ? .semibold : .medium))
                        .foregroundStyle(isSelected ? palette.primaryText : palette.secondaryText)
                        .lineLimit(1)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(palette.accent)
                    }
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelected ? palette.accent.opacity(0.16) : palette.background.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? palette.accent.opacity(0.5) : palette.border, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .compatFocusEffectDisabled()
    }

    private func iconStyleSymbol(_ style: MenuBarIconStyle) -> String {
        switch style {
        case .shieldBattery: return "bolt.shield.fill"
        case .ringGauge: return "gauge.with.dots.needle.67percent"
        case .percentagePill: return "battery.100percent.bolt"
        case .minimalBolt: return "bolt.fill"
        }
    }
}

private struct HealthTrendChartView: View {
    let snapshots: [BatteryHealthSnapshot]
    let palette: ThemePalette

    @State private var hoverRatio: CGFloat?

    var body: some View {
        let recent = Array(snapshots.suffix(30))
        let hoveredSnap: BatteryHealthSnapshot? = {
            guard let ratio = hoverRatio, !recent.isEmpty else { return nil }
            let idx = min(max(Int((ratio * CGFloat(recent.count - 1)).rounded()), 0), recent.count - 1)
            return recent[idx]
        }()

        VStack(alignment: .leading, spacing: 4) {
            if let snap = hoveredSnap {
                Text(String(format: "%@  |  Health %d%%  |  %d cycles  |  Peak %.1f C", snap.id, snap.healthPercent, snap.cycleCount, snap.peakTemperatureCelsius))
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(palette.accent)
            }

            GeometryReader { geo in
                Canvas { graphics, size in
                    guard recent.count >= 2 else { return }
                    let values = recent.map { Double($0.healthPercent) }
                    let minVal = max((values.min() ?? 80) - 2, 0)
                    let maxVal = min((values.max() ?? 100) + 1, 100)
                    let span = max(maxVal - minVal, 1)
                    let stepX = size.width / CGFloat(recent.count - 1)

                    var path = Path()
                    var area = Path()
                    var lastPt: CGPoint = .zero

                    for (idx, val) in values.enumerated() {
                        let x = CGFloat(idx) * stepX
                        let normalized = (val - minVal) / span
                        let y = size.height - CGFloat(normalized) * (size.height - 10) - 5
                        let pt = CGPoint(x: x, y: y)
                        if idx == 0 {
                            path.move(to: pt)
                            area.move(to: CGPoint(x: x, y: size.height))
                            area.addLine(to: pt)
                        } else {
                            path.addLine(to: pt)
                            area.addLine(to: pt)
                        }
                        lastPt = pt
                    }
                    area.addLine(to: CGPoint(x: lastPt.x, y: size.height))
                    area.closeSubpath()

                    graphics.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [palette.accent.opacity(0.30), palette.accent.opacity(0.02)]),
                            startPoint: CGPoint(x: size.width / 2, y: 0),
                            endPoint: CGPoint(x: size.width / 2, y: size.height)
                        )
                    )
                    graphics.stroke(path, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    for (idx, val) in values.enumerated() {
                        let x = CGFloat(idx) * stepX
                        let normalized = (val - minVal) / span
                        let y = size.height - CGFloat(normalized) * (size.height - 10) - 5
                        let dotRect = CGRect(x: x - 2.5, y: y - 2.5, width: 5, height: 5)
                        graphics.fill(Path(ellipseIn: dotRect), with: .color(palette.accent))
                    }

                    if let ratio = hoverRatio {
                        let idx = min(max(Int((ratio * CGFloat(recent.count - 1)).rounded()), 0), recent.count - 1)
                        let hx = CGFloat(idx) * stepX
                        var cursor = Path()
                        cursor.move(to: CGPoint(x: hx, y: 0))
                        cursor.addLine(to: CGPoint(x: hx, y: size.height))
                        graphics.stroke(cursor, with: .color(palette.primaryText.opacity(0.5)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    }
                }
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let loc):
                        hoverRatio = min(max(loc.x / max(geo.size.width, 1), 0), 1)
                    case .ended:
                        hoverRatio = nil
                    }
                }
            }
            .frame(height: 56)
            .padding(8)
            .background(palette.background)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}
