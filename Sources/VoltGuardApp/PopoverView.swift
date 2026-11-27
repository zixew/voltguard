import SwiftUI
import VoltGuardDomain

public struct PopoverView: View {
    @ObservedObject var presenter: VoltGuardPresenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHealthExpanded = false

    public init(presenter: VoltGuardPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        let state = presenter.state
        let palette = state.palette
        let locale = state.settings.locale
        let compact = state.settings.popoverLayout.density == .compact

        VStack(spacing: compact ? 8 : 12) {
            headerBar(state: state, palette: palette, locale: locale)

            if state.activeToolbarEvent != nil {
                ToolbarEventToastView(presenter: presenter)
                    .frame(maxWidth: .infinity)
            }

            switch state.telemetryState {
            case .loading:
                VStack(spacing: 8) {
                    ProgressView()
                    Text(L10n.text(.telemetryLoading, locale: locale))
                        .font(.callout)
                        .foregroundStyle(palette.secondaryText)
                }
                .frame(maxWidth: .infinity, minHeight: 160)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))

            case .error(let msg):
                VStack(spacing: 8) {
                    Image(systemName: state.hardwareProfile.isDesktopMac ? "desktopcomputer" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.hardwareProfile.isDesktopMac ? palette.accent : palette.warning)
                        .font(.title2)
                        .accessibilityHidden(true)
                    Text(L10n.text(state.hardwareProfile.isDesktopMac ? .desktopMacTitle : .telemetryErrorTitle, locale: locale))
                        .font(.headline)
                        .foregroundStyle(palette.primaryText)
                    Text(state.hardwareProfile.isDesktopMac ? L10n.text(.desktopMacBody, locale: locale) : msg)
                        .font(.caption)
                        .foregroundStyle(palette.secondaryText)
                        .multilineTextAlignment(.center)
                    if !state.hardwareProfile.isDesktopMac {
                        Button(L10n.text(.telemetryRetry, locale: locale)) {
                            presenter.dispatch(.refreshTelemetry)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(palette.accent)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity)
                .background(palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))

            case .loaded(let telemetry, let flow):
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: compact ? 8 : 12) {
                        ForEach(state.settings.popoverLayout.visibleModules) { module in
                            moduleView(
                                module,
                                telemetry: telemetry,
                                flow: flow,
                                state: state,
                                palette: palette,
                                locale: locale,
                                compact: compact
                            )
                        }
                    }
                }
            }

            footerBar(state: state, palette: palette, locale: locale)
        }
        .padding(compact ? 10 : 14)
        .frame(
            width: AppLayoutConstants.popoverWidth,
            height: compact ? AppLayoutConstants.popoverCompactHeight : AppLayoutConstants.popoverHeight
        )
        .background {
            CustomBackgroundLayer(theme: state.settings.theme, palette: palette)
        }
        .preferredColorScheme(palette.isDark ? .dark : .light)
    }

    @ViewBuilder
    private func headerBar(state: VoltGuardViewState, palette: ThemePalette, locale: AppLocale) -> some View {
        HStack(spacing: 8) {
            BrandLogoView(size: 24, accentColor: palette.accent)

            Text(L10n.text(.appTitle, locale: locale))
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(palette.primaryText)

            Spacer()

            Button {
                let nextLocale: AppLocale = locale == .en ? .id : .en
                presenter.dispatch(.updateLocale(nextLocale))
            } label: {
                Text(locale.rawValue.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(palette.surface)
                    .foregroundStyle(palette.primaryText)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(palette.border, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .compatFocusEffectDisabled()
            .accessibilityLabel(Text(L10n.text(.language, locale: locale)))

            Button {
                presenter.dispatch(.openFullApp)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "macwindow")
                        .font(.system(size: 11, weight: .semibold))
                        .accessibilityHidden(true)
                    Text(L10n.text(.openFullApp, locale: locale))
                        .font(.system(size: 11, weight: .semibold))
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(palette.accent)
                .foregroundStyle(palette.isDark ? Color.black : Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .compatFocusEffectDisabled()
            .accessibilityLabel(Text(L10n.text(.openFullApp, locale: locale)))
        }
    }

    @ViewBuilder
    private func moduleView(
        _ module: PopoverModuleID,
        telemetry: BatteryTelemetry,
        flow: PowerFlowMetrics,
        state: VoltGuardViewState,
        palette: ThemePalette,
        locale: AppLocale,
        compact: Bool
    ) -> some View {
        switch module {
        case .chargeControl:
            chargeControlCard(telemetry: telemetry, flow: flow, state: state, palette: palette, locale: locale, compact: compact)
        case .powerFlow:
            powerFlowCard(telemetry: telemetry, flow: flow, batteryETA: state.batteryETA, isVisible: state.isUIVisible, palette: palette, locale: locale, compact: compact)
        case .quickActions:
            quickActionsCard(state: state, palette: palette, locale: locale)
        case .calibrationAndSchedule:
            calibrationAndScheduleCard(state: state, palette: palette, locale: locale)
        case .batteryHealth:
            batteryHealthCard(telemetry: telemetry, palette: palette, locale: locale)
        }
    }

    @ViewBuilder
    private func chargeControlCard(
        telemetry: BatteryTelemetry,
        flow: PowerFlowMetrics,
        state: VoltGuardViewState,
        palette: ThemePalette,
        locale: AppLocale,
        compact: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: compact ? 8 : 10) {
            HStack(spacing: 14) {
                LiquidBatteryCellView(
                    percentage: telemetry.percentage,
                    limitPercent: state.settings.policy.limitPercent,
                    sailingDeltaPercent: state.settings.policy.sailingModeEnabled ? state.settings.policy.sailingDeltaPercent : nil,
                    temperatureCelsius: telemetry.temperatureCelsius,
                    colorStyle: state.settings.theme.batteryColorStyle,
                    mode: visualMode(state.lastReason, telemetry: telemetry),
                    palette: palette,
                    isVisible: state.isUIVisible,
                    width: 64,
                    height: 92
                ) { newLimit in
                    presenter.dispatch(.setChargeLimit(newLimit))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(statusTitle(state.lastReason, isPluggedIn: telemetry.isPluggedIn, locale: locale))
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                    if let etaText = BatteryETAFormatter.text(for: state.batteryETA, locale: locale) {
                        Text(etaText)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .contentTransition(.numericText())
                            .foregroundStyle(palette.accent)
                    }
                    Text("\(L10n.text(.chargeLimit, locale: locale)): \(state.settings.policy.limitPercent)%")
                        .font(.system(size: 12))
                        .contentTransition(.numericText())
                        .foregroundStyle(palette.secondaryText)

                    Slider(
                        value: Binding(
                            get: { Double(state.settings.policy.limitPercent) },
                            set: { presenter.dispatch(.setChargeLimit(Int($0.rounded()))) }
                        ),
                        in: Double(VoltGuardLimits.minLimitPercent)...Double(VoltGuardLimits.maxLimitPercent)
                    )
                    .tint(palette.accent)
                    .accessibilityLabel(Text(L10n.text(.chargeLimit, locale: locale)))

                    HStack(spacing: 6) {
                        ForEach(VoltGuardLimits.quickPresets, id: \.self) { preset in
                            let isSelected = state.settings.policy.limitPercent == preset
                            Button {
                                presenter.dispatch(.setChargeLimit(preset))
                            } label: {
                                Text("\(preset)%")
                                    .font(.system(size: 11, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 6)
                                    .foregroundStyle(isSelected ? (palette.isDark ? Color.black : Color.white) : palette.primaryText)
                                    .background(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .fill(isSelected ? palette.accent : palette.background.opacity(0.65))
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(isSelected ? Color.clear : palette.border.opacity(0.65), lineWidth: 1)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                                    .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .compatFocusEffectDisabled()
                        }
                    }
                }
            }

            if telemetry.isPluggedIn && !telemetry.isCharging && state.lastReason == .normalCharging && telemetry.percentage < state.settings.policy.limitPercent && flow.batteryNetWatts < -3.0 {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.warning)
                        .accessibilityHidden(true)
                    Text(L10n.text(.underpoweredCharger, locale: locale))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.warning)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(palette.background)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.warning.opacity(0.6), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            if let rec = state.liveRecommendation, !rec.isAlreadyApplied {
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(L10n.text(.recommendedBadge, locale: locale)): \(tierTitle(rec.tier, locale: locale))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                        Text(reasonText(rec.reason, locale: locale))
                            .font(.system(size: 10))
                            .foregroundStyle(palette.secondaryText)
                            .lineLimit(2)
                    }
                    Spacer()
                    Button(L10n.text(.applyProfile, locale: locale)) {
                        presenter.dispatch(.applyProfileTier(rec.tier))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                    .controlSize(.small)
                }
                .padding(8)
                .background(palette.accent.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(compact ? 10 : 12)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    @ViewBuilder
    private func powerFlowCard(
        telemetry: BatteryTelemetry,
        flow: PowerFlowMetrics,
        batteryETA: BatteryETA?,
        isVisible: Bool,
        palette: ThemePalette,
        locale: AppLocale,
        compact: Bool
    ) -> some View {
        PowerTopologyCardView(telemetry: telemetry, flow: flow, palette: palette, locale: locale, batteryETA: batteryETA, isVisible: isVisible)
    }

    @ViewBuilder
    private func flowMetric(label: String, watts: Double, palette: ThemePalette) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryText)
                .lineLimit(1)
            Text(String(format: "%.1f W", watts))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
                .foregroundStyle(palette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func quickActionsCard(state: VoltGuardViewState, palette: ThemePalette, locale: AppLocale) -> some View {
        let policy = state.settings.policy
        let compat = state.effectiveCompatibility
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.text(.quickActions, locale: locale))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(palette.primaryText)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                actionToggleButton(
                    title: L10n.text(.discharge, locale: locale),
                    icon: "arrow.down.circle",
                    active: policy.manualDischarge,
                    disabled: !compat.discharge.supported,
                    palette: palette
                ) { presenter.dispatch(.toggleManualDischarge) }

                actionToggleButton(
                    title: L10n.text(.topUp, locale: locale),
                    icon: "bolt.fill",
                    active: policy.topUpActive,
                    disabled: !compat.chargeLimit.supported,
                    palette: palette
                ) { presenter.dispatch(.toggleTopUp) }

                actionToggleButton(
                    title: L10n.text(.sailingMode, locale: locale),
                    icon: "wind",
                    active: policy.sailingModeEnabled,
                    disabled: !compat.chargeLimit.supported,
                    palette: palette
                ) { presenter.dispatch(.toggleSailingMode) }

                actionToggleButton(
                    title: L10n.text(.heatProtection, locale: locale),
                    icon: "thermometer.medium",
                    active: policy.heatProtectionEnabled,
                    disabled: !compat.chargeLimit.supported,
                    palette: palette
                ) { presenter.dispatch(.toggleHeatProtection) }
            }
        }
        .padding(12)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    @ViewBuilder
    private func actionToggleButton(
        title: String,
        icon: String,
        active: Bool,
        disabled: Bool = false,
        palette: ThemePalette,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .accessibilityHidden(true)
                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .lineLimit(1)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(active && !disabled ? palette.accent : palette.primaryText)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active && !disabled ? palette.accent.opacity(0.18) : palette.background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(active && !disabled ? palette.accent : palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .compatFocusEffectDisabled()
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1.0)
    }

    @ViewBuilder
    private func calibrationAndScheduleCard(state: VoltGuardViewState, palette: ThemePalette, locale: AppLocale) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text(.calibrationMode, locale: locale))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                if state.calibration.isActive {
                    Button(L10n.text(.stopCalibration, locale: locale)) {
                        presenter.dispatch(.stopCalibration)
                    }
                    .buttonStyle(.bordered)
                    .tint(palette.danger)
                } else {
                    Button(L10n.text(.startCalibration, locale: locale)) {
                        presenter.dispatch(.startCalibration)
                    }
                    .buttonStyle(.bordered)
                    .tint(palette.accent)
                }
            }

            if state.calibration.isActive || state.calibration.stage == .completed {
                let pct: Int? = {
                    if case .loaded(let t, _) = state.telemetryState { return t.percentage }
                    return nil
                }()
                CalibrationProgressView(
                    session: state.calibration,
                    currentPercentage: pct,
                    palette: palette,
                    locale: locale,
                    compact: true,
                    isVisible: state.isUIVisible
                )
            } else if case .loaded(let t, _) = state.telemetryState {
                if !t.isPluggedIn {
                    Text(L10n.text(.calNeedsCharger, locale: locale))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.secondaryText)
                } else if !state.helperConnected {
                    Text(L10n.text(.calNeedsHelper, locale: locale))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.warning)
                }
            }
        }
        .padding(12)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    @ViewBuilder
    private func batteryHealthCard(telemetry: BatteryTelemetry, palette: ThemePalette, locale: AppLocale) -> some View {
        let designCap = Double(max(telemetry.designCapacityMah, 1))
        let maxCapRatio = min(max(Double(telemetry.maxCapacityMah) / designCap, 0.05), 1.0)
        let curMah = Double(telemetry.currentCapacityMah ?? Int(Double(telemetry.maxCapacityMah) * Double(telemetry.percentage) / 100.0))
        let curRatio = min(max(curMah / designCap, 0.02), maxCapRatio)

        VStack(spacing: 8) {
            HStack(spacing: 8) {
                healthCell(label: L10n.text(.batteryHealth, locale: locale), value: "\(telemetry.healthPercent)%", palette: palette)
                healthCell(label: L10n.text(.cycles, locale: locale), value: "\(telemetry.cycleCount)", palette: palette)
                healthCell(label: L10n.text(.temperature, locale: locale), value: String(format: "%.1f°C", telemetry.temperatureCelsius), palette: palette)
                Image(systemName: isHealthExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isHealthExpanded ? palette.accent : palette.secondaryText)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                    isHealthExpanded.toggle()
                }
            }

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(palette.background)
                    Capsule()
                        .fill(palette.secondaryText.opacity(0.28))
                        .frame(width: geo.size.width * CGFloat(maxCapRatio))
                    Capsule()
                        .fill(palette.accent)
                        .frame(width: geo.size.width * CGFloat(curRatio))
                }
            }
            .frame(height: 4.5)

            if isHealthExpanded {
                Divider()
                VStack(spacing: 4) {
                    healthDetailRow(
                        label: L10n.text(.batteryCondition, locale: locale),
                        value: conditionLabel(telemetry.batteryCondition, locale: locale),
                        valueColor: conditionColor(telemetry.batteryCondition, palette: palette),
                        palette: palette
                    )
                    if let currentMah = telemetry.currentCapacityMah {
                        healthDetailRow(
                            label: L10n.text(.currentCapacity, locale: locale),
                            value: "\(currentMah) mAh",
                            valueColor: palette.primaryText,
                            palette: palette
                        )
                    }
                    healthDetailRow(
                        label: L10n.text(.maxCapacity, locale: locale),
                        value: "\(telemetry.maxCapacityMah) / \(telemetry.designCapacityMah) mAh",
                        valueColor: palette.primaryText,
                        palette: palette
                    )
                    let wearMah = max(telemetry.designCapacityMah - telemetry.maxCapacityMah, 0)
                    healthDetailRow(
                        label: L10n.text(.capacityLoss, locale: locale),
                        value: "-\(wearMah) mAh",
                        valueColor: palette.secondaryText,
                        palette: palette
                    )
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(10)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func healthDetailRow(label: String, value: String, valueColor: Color, palette: ThemePalette) -> some View {
        HStack {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryText)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(valueColor)
        }
    }

    private func conditionLabel(_ condition: BatteryCondition, locale: AppLocale) -> String {
        switch condition {
        case .normal: return L10n.text(.conditionNormal, locale: locale)
        case .fair: return L10n.text(.conditionFair, locale: locale)
        case .serviceRecommended: return L10n.text(.conditionService, locale: locale)
        }
    }

    private func conditionColor(_ condition: BatteryCondition, palette: ThemePalette) -> Color {
        switch condition {
        case .normal: return palette.accent
        case .fair: return palette.warning
        case .serviceRecommended: return palette.danger
        }
    }

    @ViewBuilder
    private func healthCell(label: String, value: String, palette: ThemePalette) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10))
                .foregroundStyle(palette.secondaryText)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.primaryText)
        }
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func footerBar(state: VoltGuardViewState, palette: ThemePalette, locale: AppLocale) -> some View {
        let needsUpdate = state.helperNeedsUpdate || state.smcBackendMode == .outdatedHelper
        VStack(alignment: .leading, spacing: 6) {
            if needsUpdate {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.warning)
                    Text(L10n.text(.helperOutdatedBanner, locale: locale))
                        .font(.system(size: 10))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Button(L10n.text(.updateHelperNow, locale: locale)) {
                        presenter.dispatch(.installHelper)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.warning)
                    .controlSize(.mini)
                }
                .padding(8)
                .background(palette.warning.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.warning.opacity(0.45), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 8) {
                Circle()
                    .fill(needsUpdate ? palette.warning : (state.helperConnected ? palette.accent : palette.warning))
                    .frame(width: 7, height: 7)
                    .accessibilityHidden(true)
                Text(helperStatusLabel(state: state, locale: locale))
                    .font(.system(size: 11))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                Spacer()
                Button(L10n.text(.minimizeToBackground, locale: locale)) {
                    presenter.dispatch(.minimizeToBackground)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.secondaryText)

                Button(L10n.text(.quit, locale: locale)) {
                    presenter.dispatch(.quitApp)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(palette.danger)
            }
        }
    }

    private func helperStatusLabel(state: VoltGuardViewState, locale: AppLocale) -> String {
        if state.helperNeedsUpdate || state.smcBackendMode == .outdatedHelper {
            return L10n.text(.diagUpdateNeeded, locale: locale)
        }
        guard state.helperConnected else {
            return L10n.text(.helperDryRun, locale: locale)
        }
        switch state.smcBackendMode {
        case .adapterMode:
            return "\(L10n.text(.helperConnected, locale: locale)) · CHIE"
        case .firmwareManaged:
            return "\(L10n.text(.helperConnected, locale: locale)) · bfF0"
        default:
            return L10n.text(.helperConnected, locale: locale)
        }
    }

    private func visualMode(_ reason: PolicyReason, telemetry: BatteryTelemetry) -> BatteryVisualMode {
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

    private func statusColor(_ reason: PolicyReason, palette: ThemePalette) -> Color {
        switch reason {
        case .heatProtectionPaused: return palette.danger
        case .manualDischarge, .automaticDischarge, .calibrationActive: return palette.warning
        default: return palette.accent
        }
    }

    private func statusTitle(_ reason: PolicyReason, isPluggedIn: Bool, locale: AppLocale) -> String {
        if !isPluggedIn && reason == .normalCharging {
            return L10n.text(.statusOnBattery, locale: locale)
        }
        switch reason {
        case .normalCharging: return L10n.text(.statusCharging, locale: locale)
        case .limitReached: return L10n.text(.statusLimitReached, locale: locale)
        case .sailingPaused: return L10n.text(.statusSailing, locale: locale)
        case .heatProtectionPaused: return L10n.text(.statusHeatPaused, locale: locale)
        case .manualDischarge: return L10n.text(.statusManualDischarge, locale: locale)
        case .automaticDischarge: return L10n.text(.statusAutoDischarge, locale: locale)
        case .topUpActive: return L10n.text(.statusTopUp, locale: locale)
        case .calibrationActive: return L10n.text(.statusCalibration, locale: locale)
        case .sleepingInhibited: return L10n.text(.statusSleepingInhibited, locale: locale)
        }
    }

    private func tierTitle(_ tier: BatteryProfileTier, locale: AppLocale) -> String {
        switch tier {
        case .travel: return L10n.text(.profileTravelTitle, locale: locale)
        case .balanced: return L10n.text(.profileBalancedTitle, locale: locale)
        case .deskDocked: return L10n.text(.profileDeskTitle, locale: locale)
        case .maxLifespan: return L10n.text(.profileMaxLifespanTitle, locale: locale)
        }
    }

    private func reasonText(_ reason: RecommendationReason, locale: AppLocale) -> String {
        switch reason {
        case .highTemperature: return L10n.text(.reasonHighTemp, locale: locale)
        case .clamshellDocked: return L10n.text(.reasonClamshell, locale: locale)
        case .lowBatteryUnplugged: return L10n.text(.reasonLowBattery, locale: locale)
        case .dailyBalanced: return L10n.text(.reasonDaily, locale: locale)
        }
    }
}
