import AppKit
import ImageIO
import SwiftUI
import VoltGuardDomain

public extension View {
    @ViewBuilder
    func compatFocusEffectDisabled() -> some View {
        if #available(macOS 14.0, *) {
            self.focusEffectDisabled()
        } else {
            self
        }
    }

    @ViewBuilder
    func compatOnChange<V: Equatable>(of value: V, perform action: @escaping (V) -> Void) -> some View {
        if #available(macOS 14.0, *) {
            self.onChange(of: value) { _, newValue in
                action(newValue)
            }
        } else {
            self.onChange(of: value, perform: action)
        }
    }
}

public extension Text {
    func compatTextColor(_ color: Color) -> Text {
        if #available(macOS 14.0, *) {
            return self.foregroundStyle(color)
        } else {
            return self.foregroundColor(color)
        }
    }
}

public enum BatteryVisualMode: Equatable {
    case charging
    case discharging
    case limitReached
    case heatPaused
    case onBattery
}

public struct LiquidBatteryCellView: View {
    public let percentage: Int
    public let limitPercent: Int
    public let sailingDeltaPercent: Int?
    public let temperatureCelsius: Double
    public let colorStyle: BatteryColorStyle
    public let mode: BatteryVisualMode
    public let palette: ThemePalette
    public let isVisible: Bool
    public let width: CGFloat
    public let height: CGFloat
    public let onLimitChange: ((Int) -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isDraggingLimit = false

    public init(
        percentage: Int,
        limitPercent: Int,
        sailingDeltaPercent: Int? = nil,
        temperatureCelsius: Double = 30.0,
        colorStyle: BatteryColorStyle = .adaptiveSpectrum,
        mode: BatteryVisualMode,
        palette: ThemePalette,
        isVisible: Bool = true,
        width: CGFloat = LiquidBatteryConstants.cellWidth,
        height: CGFloat = LiquidBatteryConstants.cellHeight,
        onLimitChange: ((Int) -> Void)? = nil
    ) {
        self.percentage = min(max(percentage, 0), 100)
        self.limitPercent = min(max(limitPercent, VoltGuardLimits.minLimitPercent), VoltGuardLimits.maxLimitPercent)
        self.sailingDeltaPercent = sailingDeltaPercent
        self.temperatureCelsius = temperatureCelsius
        self.colorStyle = colorStyle
        self.mode = mode
        self.palette = palette
        self.isVisible = isVisible
        self.width = width
        self.height = height
        self.onLimitChange = onLimitChange
    }

    public var body: some View {
        let isActiveFlow = (mode == .charging || mode == .discharging)
        let shouldAnimate = isVisible && !reduceMotion
        let interval = isActiveFlow ? MotionConstants.flowFrameInterval : LiquidBatteryConstants.calmFlowFrameInterval
        let cycleSeconds = isActiveFlow ? LiquidBatteryConstants.waveCycleSeconds : LiquidBatteryConstants.calmWaveCycleSeconds
        let amplitude: CGFloat = shouldAnimate ? (isActiveFlow ? LiquidBatteryConstants.waveAmplitude : LiquidBatteryConstants.calmWaveAmplitude) : 0
        let fillColors = resolvedGradientColors
        let fillColor = fillColors.first ?? resolvedFillColor

        TimelineView(.animation(minimumInterval: interval, paused: !shouldAnimate)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase: Double = shouldAnimate
                ? (time.truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds) * (.pi * 2)
                : 0

            Canvas { graphics, size in
                drawBatteryCanvas(
                    graphics: &graphics,
                    size: size,
                    time: time,
                    phase: phase,
                    amplitude: amplitude,
                    isActiveFlow: isActiveFlow,
                    shouldAnimate: shouldAnimate,
                    fillColors: fillColors,
                    fillColor: fillColor
                )
            }
            .overlay(alignment: .center) {
                centerOverlay(time: time, shouldAnimate: shouldAnimate, fillColor: fillColor)
            }
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 2)
                .onChanged { value in
                    guard let onLimitChange else { return }
                    isDraggingLimit = true
                    let normalized = 1.0 - min(max(value.location.y / height, 0), 1)
                    let newLimit = Int((normalized * 100.0).rounded())
                    onLimitChange(min(max(newLimit, VoltGuardLimits.minLimitPercent), VoltGuardLimits.maxLimitPercent))
                }
                .onEnded { _ in
                    isDraggingLimit = false
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(percentage)% / \(limitPercent)%"))
    }

    private func drawBatteryCanvas(
        graphics: inout GraphicsContext,
        size: CGSize,
        time: TimeInterval,
        phase: Double,
        amplitude: CGFloat,
        isActiveFlow: Bool,
        shouldAnimate: Bool,
        fillColors: [Color],
        fillColor: Color
    ) {
        let capHeight: CGFloat = 6
        let capWidth: CGFloat = size.width * 0.36
        let capRect = CGRect(x: (size.width - capWidth) / 2, y: 0, width: capWidth, height: capHeight)
        graphics.fill(Path(roundedRect: capRect, cornerRadius: 3), with: .color(palette.border))

        let bodyRect = CGRect(x: 2, y: capHeight + 2, width: size.width - 4, height: size.height - capHeight - 4)
        let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 12)
        graphics.fill(bodyPath, with: .color(palette.background))

        graphics.drawLayer { layer in
            let innerRect = bodyRect.insetBy(dx: 3, dy: 3)
            layer.clip(to: Path(roundedRect: innerRect, cornerRadius: 9))
            drawLiquidInner(
                layer: &layer,
                innerRect: innerRect,
                time: time,
                phase: phase,
                amplitude: amplitude,
                isActiveFlow: isActiveFlow,
                shouldAnimate: shouldAnimate,
                fillColors: fillColors,
                fillColor: fillColor
            )
        }

        let isHighlightedRim = shouldAnimate && (mode == .charging || mode == .limitReached)
        let pulseRate = mode == .charging ? 3.2 : 1.8
        let pulse: Double = isHighlightedRim ? (0.50 + 0.45 * (0.5 + 0.5 * sin(time * pulseRate))) : 0.0
        let rimColor: Color = isDraggingLimit ? palette.accent : (isHighlightedRim ? fillColor.opacity(pulse) : palette.border)
        let rimWidth: CGFloat = (isDraggingLimit || isHighlightedRim) ? 2.0 : 1.5
        graphics.stroke(bodyPath, with: .color(rimColor), lineWidth: rimWidth)
    }

    private func drawLiquidInner(
        layer: inout GraphicsContext,
        innerRect: CGRect,
        time: TimeInterval,
        phase: Double,
        amplitude: CGFloat,
        isActiveFlow: Bool,
        shouldAnimate: Bool,
        fillColors: [Color],
        fillColor: Color
    ) {
        let levelFraction = CGFloat(percentage) / 100.0
        let surfaceY = innerRect.maxY - (innerRect.height * levelFraction)
        let direction: Double = mode == .discharging ? -phase : phase
        let stepCount = 28

        var backWavePath = Path()
        backWavePath.move(to: CGPoint(x: innerRect.minX, y: innerRect.maxY))
        backWavePath.addLine(to: CGPoint(x: innerRect.minX, y: surfaceY))
        for step in 0...stepCount {
            let t = CGFloat(step) / CGFloat(stepCount)
            let x = innerRect.minX + t * innerRect.width
            let yOffset = sin(Double(t) * .pi * 2 * LiquidBatteryConstants.waveCycles - direction * 0.8 + 1.2) * Double(amplitude * 0.82)
            backWavePath.addLine(to: CGPoint(x: x, y: surfaceY + CGFloat(yOffset) - 1.5))
        }
        backWavePath.addLine(to: CGPoint(x: innerRect.maxX, y: innerRect.maxY))
        backWavePath.closeSubpath()
        layer.fill(backWavePath, with: .color(fillColor.opacity(0.42)))

        var wavePath = Path()
        var crestPath = Path()
        wavePath.move(to: CGPoint(x: innerRect.minX, y: innerRect.maxY))
        for step in 0...stepCount {
            let t = CGFloat(step) / CGFloat(stepCount)
            let x = innerRect.minX + t * innerRect.width
            let yOffset = sin(Double(t) * .pi * 2 * LiquidBatteryConstants.waveCycles + direction) * Double(amplitude)
            let pt = CGPoint(x: x, y: surfaceY + CGFloat(yOffset))
            wavePath.addLine(to: pt)
            if step == 0 { crestPath.move(to: pt) } else { crestPath.addLine(to: pt) }
        }
        wavePath.addLine(to: CGPoint(x: innerRect.maxX, y: innerRect.maxY))
        wavePath.closeSubpath()

        let liquidGradient = Gradient(colors: [
            (fillColors.first ?? fillColor).opacity(0.96),
            (fillColors.last ?? fillColor).opacity(0.74)
        ])
        layer.fill(
            wavePath,
            with: .linearGradient(
                liquidGradient,
                startPoint: CGPoint(x: innerRect.midX, y: surfaceY),
                endPoint: CGPoint(x: innerRect.midX, y: innerRect.maxY)
            )
        )
        layer.stroke(crestPath, with: .color(Color.white.opacity(0.45)), lineWidth: 1.3)

        if shouldAnimate && isActiveFlow {
            let pCount = 8
            for idx in 0..<pCount {
                let speed = 0.38 + Double(idx % 3) * 0.11
                let progress = ((time * speed) + Double(idx) / Double(pCount)).truncatingRemainder(dividingBy: 1.0)
                let directed = mode == .discharging ? progress : (1.0 - progress)
                let baseX: CGFloat = 0.16 + 0.68 * CGFloat((idx * 37 + 13) % 11) / 10.0
                let wobble = CGFloat(sin(progress * .pi * 2.4 + Double(idx) * 1.3)) * 3.2
                let px = innerRect.minX + innerRect.width * baseX + wobble
                let py = surfaceY + (innerRect.maxY - surfaceY) * CGFloat(directed)
                if py >= surfaceY + 2 && py <= innerRect.maxY - 2 {
                    let radius: CGFloat = 1.6 + CGFloat(idx % 3) * 0.75
                    let fade = min(min(progress * 4.0, (1.0 - progress) * 3.5), 1.0)
                    let pRect = CGRect(x: px - radius, y: py - radius, width: radius * 2, height: radius * 2)
                    layer.fill(Path(ellipseIn: pRect), with: .color(Color.white.opacity(0.55 * fade)))
                }
            }
        }

        let limitFraction = CGFloat(limitPercent) / 100.0
        let limitY = innerRect.maxY - (innerRect.height * limitFraction)
        if let delta = sailingDeltaPercent, delta > 0 {
            let floorFraction = CGFloat(max(limitPercent - delta, VoltGuardLimits.minSailingFloorPercent)) / 100.0
            let floorY = innerRect.maxY - (innerRect.height * floorFraction)
            let bandRect = CGRect(x: innerRect.minX, y: limitY, width: innerRect.width, height: max(floorY - limitY, 0))
            layer.fill(Path(bandRect), with: .color(palette.primaryText.opacity(0.12)))
        }

        var gatePath = Path()
        gatePath.move(to: CGPoint(x: innerRect.minX, y: limitY))
        gatePath.addLine(to: CGPoint(x: innerRect.maxX, y: limitY))
        layer.stroke(
            gatePath,
            with: .color(isDraggingLimit ? palette.primaryText : palette.primaryText.opacity(0.75)),
            style: StrokeStyle(lineWidth: isDraggingLimit ? 2 : 1.5, dash: [4, 3])
        )
        if limitPercent < VoltGuardLimits.maxLimitPercent {
            let tag = Text("\(limitPercent)%")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .compatTextColor(palette.primaryText.opacity(0.85))
            let tagY = max(limitY - 7, innerRect.minY + 6)
            layer.draw(tag, at: CGPoint(x: innerRect.maxX - 13, y: tagY))
        }
    }

    @ViewBuilder
    private func centerOverlay(time: TimeInterval, shouldAnimate: Bool, fillColor: Color) -> some View {
        VStack(spacing: 1) {
            Text("\(percentage)%")
                .font(.system(size: width * 0.24, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(palette.primaryText)
                .shadow(color: palette.background.opacity(0.6), radius: 2, y: 1)

            if mode == .charging || mode == .discharging {
                let iconPulse: Double = shouldAnimate ? (0.72 + 0.28 * (0.5 + 0.5 * sin(time * 4.0))) : 1.0
                Image(systemName: mode == .charging ? "bolt.fill" : "arrow.down")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(palette.primaryText.opacity(iconPulse))
                    .shadow(color: fillColor.opacity(shouldAnimate ? 0.7 : 0), radius: 3)
                    .accessibilityHidden(true)
            } else if mode == .limitReached {
                let shieldPulse: Double = shouldAnimate ? (0.68 + 0.32 * (0.5 + 0.5 * sin(time * 2.2))) : 0.9
                Image(systemName: "checkmark.shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(palette.primaryText.opacity(shieldPulse))
                    .shadow(color: fillColor.opacity(shouldAnimate ? 0.6 : 0), radius: 3)
                    .accessibilityHidden(true)
            }
        }
    }

    private var resolvedGradientColors: [Color] {
        if mode == .heatPaused {
            return [Color(hex: "#EF4444"), Color(hex: "#B91C1C")]
        }
        switch colorStyle {
        case .themeAccent:
            let base = resolvedFillColor
            return [base, base.opacity(0.75)]
        case .thermalReactive:
            if temperatureCelsius >= 40.0 {
                return [Color(hex: "#F97316"), Color(hex: "#EF4444")]
            }
            if temperatureCelsius >= 35.0 {
                return [Color(hex: "#FBBF24"), Color(hex: "#F59E0B")]
            }
            if temperatureCelsius >= 30.0 {
                return [Color(hex: "#34D399"), Color(hex: "#10B981")]
            }
            return [Color(hex: "#38BDF8"), Color(hex: "#0EA5E9")]
        case .adaptiveSpectrum:
            if percentage <= VoltGuardLimits.lowBatteryAlertThresholdPercent {
                return [Color(hex: "#F87171"), Color(hex: "#EF4444")]
            }
            if percentage < 50 {
                return [Color(hex: "#FBBF24"), Color(hex: "#F59E0B")]
            }
            if mode == .limitReached {
                return [Color(hex: "#10B981"), Color(hex: "#06B6D4")]
            }
            if percentage >= 80 {
                return [Color(hex: "#34D399"), Color(hex: "#10B981")]
            }
            return [Color(hex: "#38BDF8"), Color(hex: "#0EA5E9")]
        }
    }

    private var resolvedFillColor: Color {
        if mode == .heatPaused || percentage <= VoltGuardLimits.lowBatteryAlertThresholdPercent {
            return palette.danger
        }
        if percentage < 50 {
            return palette.warning
        }
        return palette.accent
    }
}

public struct PowerTopologyCardView: View {
    public let telemetry: BatteryTelemetry
    public let flow: PowerFlowMetrics
    public let palette: ThemePalette
    public let locale: AppLocale
    public let batteryETA: BatteryETA?
    public let isVisible: Bool

    @State private var isExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        telemetry: BatteryTelemetry,
        flow: PowerFlowMetrics,
        palette: ThemePalette,
        locale: AppLocale,
        batteryETA: BatteryETA? = nil,
        isVisible: Bool = true
    ) {
        self.telemetry = telemetry
        self.flow = flow
        self.palette = palette
        self.locale = locale
        self.batteryETA = batteryETA
        self.isVisible = isVisible
    }

    public var body: some View {
        let isBypassing = telemetry.isPluggedIn
            && !telemetry.isCharging
            && abs(flow.batteryNetWatts) < MotionConstants.activeFlowWattThreshold
        let isSteppingDown = telemetry.isPluggedIn
            && !telemetry.isCharging
            && flow.batteryNetWatts <= -MotionConstants.activeFlowWattThreshold
        let maxRefWatts = max(flow.adapterInputWatts, flow.systemLoadWatts, abs(flow.batteryNetWatts), 30.0)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(telemetry.isPluggedIn ? (isSteppingDown ? palette.warning : palette.accent) : palette.warning)
                        .frame(width: 7, height: 7)
                    Text(L10n.text(.livePowerFlow, locale: locale))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.primaryText)
                }
                if isBypassing {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.shield.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(L10n.text(.bypassActiveBadge, locale: locale))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(palette.accent.opacity(0.18))
                    .foregroundStyle(palette.accent)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                } else if isSteppingDown {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .accessibilityHidden(true)
                        Text(L10n.text(.adapterStepDownBadge, locale: locale))
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(palette.warning.opacity(0.18))
                    .foregroundStyle(palette.warning)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }
                Spacer()
                HStack(spacing: 6) {
                    Text(String(format: "%.1fV  %.2fA", telemetry.voltageVolts, telemetry.amperageAmps))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                    Image(systemName: isExpanded ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isExpanded ? palette.accent : palette.secondaryText)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                    isExpanded.toggle()
                }
            }

            if isBypassing {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.text(.bypassShieldHoldHint, locale: locale))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(palette.accent)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82)) {
                        isExpanded.toggle()
                    }
                }
            } else if isSteppingDown {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.right.circle.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(L10n.text(.adapterStepDownSubtitle, locale: locale))
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(palette.warning)
            }

            HStack(spacing: 8) {
                topologyNode(
                    icon: "powerplug.fill",
                    label: L10n.text(.adapterInput, locale: locale),
                    watts: flow.adapterInputWatts,
                    ratio: min(max(flow.adapterInputWatts / maxRefWatts, 0), 1),
                    tone: telemetry.isPluggedIn ? palette.accent : palette.secondaryText,
                    active: telemetry.isPluggedIn
                )
                topologyNode(
                    icon: "laptopcomputer",
                    label: L10n.text(.systemLoad, locale: locale),
                    watts: flow.systemLoadWatts,
                    ratio: min(max(flow.systemLoadWatts / maxRefWatts, 0.08), 1),
                    tone: palette.accent,
                    active: true
                )
                topologyNode(
                    icon: isBypassing ? "checkmark.shield.fill" : (flow.batteryNetWatts < -0.5 ? "arrow.down.circle.fill" : "battery.100percent.bolt"),
                    label: L10n.text(.batteryNet, locale: locale),
                    watts: flow.batteryNetWatts,
                    ratio: min(max(abs(flow.batteryNetWatts) / maxRefWatts, 0), 1),
                    tone: isBypassing ? Color(hex: "#10B981") : (flow.batteryNetWatts < -0.5 ? palette.warning : palette.accent),
                    active: isBypassing || abs(flow.batteryNetWatts) >= MotionConstants.activeFlowWattThreshold
                )
            }

            LivePowerFlowStreamView(
                isPluggedIn: telemetry.isPluggedIn,
                isBypassing: isBypassing,
                adapterInputWatts: flow.adapterInputWatts,
                batteryNetWatts: flow.batteryNetWatts,
                palette: palette,
                isVisible: isVisible
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        telemetryPill(icon: "bolt.circle", text: String(format: "%.2f V", telemetry.voltageVolts), palette: palette)
                        telemetryPill(icon: "waveform.path.ecg", text: String(format: "%+.2f A", telemetry.amperageAmps), palette: palette)
                        telemetryPill(icon: "thermometer.medium", text: String(format: "%.1f C", telemetry.temperatureCelsius), palette: palette)
                        if let pdV = telemetry.adapterVoltageVolts, let pdA = telemetry.adapterCurrentAmps {
                            telemetryPill(icon: "cable.connector", text: String(format: "%.0fV/%.1fA", pdV, pdA), palette: palette)
                        }
                    }
                    let etaLabel = BatteryETAFormatter.text(for: batteryETA, locale: locale)
                    if telemetry.isPluggedIn || etaLabel != nil {
                        HStack {
                            if let adapter = telemetry.adapterName {
                                Text("\(L10n.text(.adapterDetails, locale: locale)): \(adapter) (\(Int(telemetry.adapterWatts))W)")
                            } else if telemetry.isPluggedIn {
                                Text("\(L10n.text(.adapterDetails, locale: locale)): \(Int(telemetry.adapterWatts))W")
                            }
                            Spacer()
                            if let etaLabel {
                                Text("\(L10n.text(.timeRemaining, locale: locale)): \(etaLabel)")
                                    .foregroundStyle(palette.accent)
                            }
                        }
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                    }
                }
                .padding(.top, 2)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous).strokeBorder(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
    }

    @ViewBuilder
    private func telemetryPill(icon: String, text: String, palette: ThemePalette) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(palette.accent)
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(palette.primaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(palette.background.opacity(0.75))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(palette.border.opacity(0.7), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    @ViewBuilder
    private func topologyNode(icon: String, label: String, watts: Double, ratio: Double, tone: Color, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(active ? tone : palette.secondaryText)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(String(format: "%.1f W", watts))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .contentTransition(.numericText())
                .foregroundStyle(active ? palette.primaryText : palette.secondaryText)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(palette.border.opacity(0.45))
                    Capsule()
                        .fill(active ? tone : palette.secondaryText.opacity(0.35))
                        .frame(width: max(geo.size.width * CGFloat(ratio), active ? 6 : 2))
                }
            }
            .frame(height: 3.5)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(palette.background.opacity(0.78))
        .overlay(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(active ? tone.opacity(0.45) : palette.border.opacity(0.55), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
    }
}

public struct TelemetrySparklineView: View {
    public let samples: [TelemetrySample]
    public let palette: ThemePalette

    @State private var hoverRatio: CGFloat?

    public init(samples: [TelemetrySample], palette: ThemePalette) {
        self.samples = samples
        self.palette = palette
    }

    public var body: some View {
        let wattsList = samples.map(\.watts)
        let peakW = wattsList.max() ?? 0
        let avgW = wattsList.isEmpty ? 0 : (wattsList.reduce(0, +) / Double(wattsList.count))
        let hoveredSample: TelemetrySample? = {
            guard let ratio = hoverRatio, !samples.isEmpty else { return nil }
            let idx = min(max(Int((ratio * CGFloat(samples.count - 1)).rounded()), 0), samples.count - 1)
            return samples[idx]
        }()

        VStack(alignment: .leading, spacing: 4) {
            HStack {
                if let hoveredSample {
                    Text(String(format: "Live Sample: %.1f W  |  %.1f C", hoveredSample.watts, hoveredSample.temperatureCelsius))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(palette.accent)
                } else {
                    Text(String(format: "Avg %.1f W  |  Peak %.1f W", avgW, peakW))
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(palette.secondaryText)
                }
                Spacer()
            }

            GeometryReader { geo in
                Canvas { graphics, size in
                    guard samples.count >= 2 else { return }
                    let maxW = max(samples.map(\.watts).max() ?? 10, 10) * 1.08
                    let stepX = size.width / CGFloat(samples.count - 1)

                    var line = Path()
                    var area = Path()
                    var lastPt: CGPoint = .zero

                    for (idx, sample) in samples.enumerated() {
                        let x = CGFloat(idx) * stepX
                        let y = size.height - (CGFloat(sample.watts / maxW) * (size.height - 8)) - 4
                        let pt = CGPoint(x: x, y: y)
                        if idx == 0 {
                            line.move(to: pt)
                            area.move(to: CGPoint(x: x, y: size.height))
                            area.addLine(to: pt)
                        } else {
                            line.addLine(to: pt)
                            area.addLine(to: pt)
                        }
                        lastPt = pt
                    }
                    area.addLine(to: CGPoint(x: lastPt.x, y: size.height))
                    area.closeSubpath()

                    graphics.fill(
                        area,
                        with: .linearGradient(
                            Gradient(colors: [palette.accent.opacity(0.32), palette.accent.opacity(0.02)]),
                            startPoint: CGPoint(x: size.width / 2, y: 0),
                            endPoint: CGPoint(x: size.width / 2, y: size.height)
                        )
                    )
                    graphics.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                    // Live endpoint dot
                    let liveHalo = CGRect(x: lastPt.x - 5, y: lastPt.y - 5, width: 10, height: 10)
                    let liveCore = CGRect(x: lastPt.x - 2.5, y: lastPt.y - 2.5, width: 5, height: 5)
                    graphics.fill(Path(ellipseIn: liveHalo), with: .color(palette.accent.opacity(0.28)))
                    graphics.fill(Path(ellipseIn: liveCore), with: .color(palette.accent))

                    // Hover crosshair and marker
                    if let ratio = hoverRatio {
                        let idx = min(max(Int((ratio * CGFloat(samples.count - 1)).rounded()), 0), samples.count - 1)
                        let hx = CGFloat(idx) * stepX
                        let hy = size.height - (CGFloat(samples[idx].watts / maxW) * (size.height - 8)) - 4
                        var cursorLine = Path()
                        cursorLine.move(to: CGPoint(x: hx, y: 0))
                        cursorLine.addLine(to: CGPoint(x: hx, y: size.height))
                        graphics.stroke(cursorLine, with: .color(palette.primaryText.opacity(0.45)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))

                        let marker = CGRect(x: hx - 3.5, y: hy - 3.5, width: 7, height: 7)
                        graphics.fill(Path(ellipseIn: marker), with: .color(palette.primaryText))
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
            .frame(height: 46)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(palette.background.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .accessibilityHidden(true)
    }
}

public struct LivePowerFlowStreamView: View {
    public let isPluggedIn: Bool
    public let isBypassing: Bool
    public let adapterInputWatts: Double
    public let batteryNetWatts: Double
    public let palette: ThemePalette
    public let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isPluggedIn: Bool,
        isBypassing: Bool = false,
        adapterInputWatts: Double = 0,
        batteryNetWatts: Double,
        palette: ThemePalette,
        isVisible: Bool = true
    ) {
        self.isPluggedIn = isPluggedIn
        self.isBypassing = isBypassing
        self.adapterInputWatts = adapterInputWatts
        self.batteryNetWatts = batteryNetWatts
        self.palette = palette
        self.isVisible = isVisible
    }

    public var body: some View {
        let hasAdapterFlow = (isPluggedIn && adapterInputWatts >= MotionConstants.activeFlowWattThreshold) || isBypassing
        let hasBatteryFlow = abs(batteryNetWatts) >= MotionConstants.activeFlowWattThreshold
        let isActiveFlow = hasAdapterFlow || hasBatteryFlow || isBypassing
        let shouldAnimate = isVisible && !reduceMotion && isActiveFlow
        let isDischarging = batteryNetWatts < -MotionConstants.activeFlowWattThreshold
        let batteryFlowColor = isDischarging ? palette.warning : palette.accent
        let bypassColor = Color(hex: "#10B981")

        let maxWatts = max(adapterInputWatts, abs(batteryNetWatts), 10.0)
        let speedMultiplier = min(max(maxWatts / 25.0, 0.75), 2.2)
        let effectiveCycle = MotionConstants.flowCycleSeconds / speedMultiplier

        TimelineView(.animation(minimumInterval: MotionConstants.flowFrameInterval, paused: !shouldAnimate)) { context in
            let phase = !shouldAnimate
                ? 0
                : (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: effectiveCycle) / effectiveCycle)

            Canvas { graphics, size in
                let y = size.height / 2
                let startX: CGFloat = 8
                let midX: CGFloat = size.width / 2
                let endX: CGFloat = size.width - 8
                let leftSpan = max(midX - startX - 8, 1)
                let rightSpan = max(endX - (midX + 8), 1)
                let leftTone = isBypassing ? bypassColor : palette.accent

                var leftTrack = Path()
                leftTrack.move(to: CGPoint(x: startX, y: y))
                leftTrack.addLine(to: CGPoint(x: midX - 7, y: y))
                graphics.stroke(leftTrack, with: .color(hasAdapterFlow ? leftTone.opacity(0.38) : palette.border.opacity(0.6)), style: StrokeStyle(lineWidth: isBypassing ? 3.5 : 3, lineCap: .round))

                var rightTrack = Path()
                rightTrack.move(to: CGPoint(x: midX + 7, y: y))
                rightTrack.addLine(to: CGPoint(x: endX, y: y))
                graphics.stroke(
                    rightTrack,
                    with: .color(hasBatteryFlow ? batteryFlowColor.opacity(0.32) : palette.border.opacity(0.45)),
                    style: StrokeStyle(lineWidth: isBypassing ? 2 : 3, lineCap: .round, dash: isBypassing ? [4, 4] : [])
                )

                // Central Mac Hub Node with outer pulse ring
                let pulseRingExtra: CGFloat = (isBypassing && shouldAnimate) ? CGFloat(sin(phase * .pi * 2)) * 1.5 + 1.5 : 0
                let hubOuter = CGRect(x: midX - 6 - pulseRingExtra, y: y - 6 - pulseRingExtra, width: 12 + pulseRingExtra * 2, height: 12 + pulseRingExtra * 2)
                let hubInner = CGRect(x: midX - 3, y: y - 3, width: 6, height: 6)
                graphics.fill(Path(ellipseIn: hubOuter), with: .color((isBypassing ? bypassColor : (hasAdapterFlow ? palette.accent : batteryFlowColor)).opacity(0.24)))
                graphics.fill(Path(ellipseIn: hubInner), with: .color(isBypassing ? bypassColor : (hasAdapterFlow || hasBatteryFlow ? palette.accent : palette.secondaryText)))

                if hasAdapterFlow {
                    let dotCount = isBypassing ? 5 : 4
                    for index in 0..<dotCount {
                        let offset = (phase + Double(index) / Double(dotCount)).truncatingRemainder(dividingBy: 1.0)
                        let x = startX + CGFloat(offset) * leftSpan
                        let haloRect = CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11)
                        let coreRect = CGRect(x: x - 2.8, y: y - 2.8, width: 5.6, height: 5.6)
                        graphics.fill(Path(ellipseIn: haloRect), with: .color(leftTone.opacity(0.26)))
                        graphics.fill(Path(ellipseIn: coreRect), with: .color(leftTone))
                    }
                }

                if hasBatteryFlow {
                    let dotCount = 4
                    for index in 0..<dotCount {
                        let rawOffset = (phase + Double(index) / Double(dotCount)).truncatingRemainder(dividingBy: 1.0)
                        let directed = isDischarging ? (1.0 - rawOffset) : rawOffset
                        let x = (midX + 8) + CGFloat(directed) * rightSpan
                        let haloRect = CGRect(x: x - 5.5, y: y - 5.5, width: 11, height: 11)
                        let coreRect = CGRect(x: x - 2.8, y: y - 2.8, width: 5.6, height: 5.6)
                        graphics.fill(Path(ellipseIn: haloRect), with: .color(batteryFlowColor.opacity(0.24)))
                        graphics.fill(Path(ellipseIn: coreRect), with: .color(batteryFlowColor))
                    }
                } else if isBypassing {
                    // Isolated stationary rest node on battery rail
                    let restOuter = CGRect(x: endX - 5, y: y - 5, width: 10, height: 10)
                    let restInner = CGRect(x: endX - 2.5, y: y - 2.5, width: 5, height: 5)
                    graphics.fill(Path(ellipseIn: restOuter), with: .color(bypassColor.opacity(0.22)))
                    graphics.fill(Path(ellipseIn: restInner), with: .color(bypassColor))
                }
            }
            .frame(height: 16)
        }
        .accessibilityHidden(true)
    }
}

public struct InteractiveCardButtonStyle: ButtonStyle {
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? MotionConstants.pressedScale : 1.0)
            .brightness(isHovered ? 0.04 : 0)
            .animation(
                reduceMotion ? nil : .easeOut(duration: MotionConstants.hoverTransitionDuration),
                value: configuration.isPressed
            )
            .animation(
                reduceMotion ? nil : .easeOut(duration: MotionConstants.hoverTransitionDuration),
                value: isHovered
            )
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

public struct CalibrationProgressView: View {
    public let session: CalibrationSession
    public let currentPercentage: Int?
    public let palette: ThemePalette
    public let locale: AppLocale
    public let compact: Bool
    public let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let stages: [CalibrationStage] = [
        .chargingToFull,
        .holdingFull,
        .dischargingToLow,
        .holdingLow,
        .restoringLimit
    ]

    public init(
        session: CalibrationSession,
        currentPercentage: Int?,
        palette: ThemePalette,
        locale: AppLocale,
        compact: Bool = false,
        isVisible: Bool = true
    ) {
        self.session = session
        self.currentPercentage = currentPercentage
        self.palette = palette
        self.locale = locale
        self.compact = compact
        self.isVisible = isVisible
    }

    public var body: some View {
        let activeIdx = Self.stages.firstIndex(of: session.stage)
        let shouldAnimate = isVisible && !reduceMotion && session.isActive
        VStack(alignment: .leading, spacing: compact ? 6 : 10) {
            if session.isActive || session.stage == .completed {
                TimelineView(.animation(minimumInterval: LiquidBatteryConstants.calmFlowFrameInterval, paused: !shouldAnimate)) { context in
                    let phase = !shouldAnimate
                        ? 0.5
                        : (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8)

                    HStack(spacing: 4) {
                        ForEach(Array(Self.stages.enumerated()), id: \.element) { idx, _ in
                            GeometryReader { geo in
                                let isCompleted = session.stage == .completed || (activeIdx != nil && idx < activeIdx!)
                                let isCurrent = session.stage != .completed && activeIdx == idx
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(palette.border.opacity(0.45))
                                    if isCompleted {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(palette.accent)
                                    } else if isCurrent {
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(palette.warning.opacity(0.35))
                                        RoundedRectangle(cornerRadius: 3)
                                            .fill(palette.warning)
                                            .frame(width: max(geo.size.width * (reduceMotion ? 0.6 : (0.25 + 0.75 * phase)), 6))
                                    }
                                }
                            }
                            .frame(height: 5)
                        }
                    }
                }

                HStack {
                    Text(stageTitle(session.stage))
                        .font(.system(size: compact ? 11 : 12, weight: .semibold))
                        .foregroundStyle(session.stage == .completed ? palette.accent : palette.warning)
                    Spacer()
                    if let remaining = session.remainingHoldSeconds() {
                        let mins = Int(remaining) / 60
                        let secs = Int(remaining) % 60
                        Text(String(format: "%02d:%02d", mins, secs))
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.warning)
                    } else if let pct = currentPercentage, session.isActive {
                        Text("\(pct)%")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                    }
                }

                if compact, let desc = stageDescription(session.stage) {
                    Text(desc)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.secondaryText)
                }
            }

            if !compact {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Label(L10n.text(.calPurposeTitle, locale: locale), systemImage: "info.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                        Spacer()
                        Text(L10n.text(.calTotalDurationBadge, locale: locale))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(palette.accent.opacity(0.16))
                            .foregroundStyle(palette.accent)
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                    Text(L10n.text(.calPurposeBody, locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(10)
                .background(palette.background.opacity(0.65))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(palette.border.opacity(0.8), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(spacing: 6) {
                    ForEach(Array(Self.stages.enumerated()), id: \.element) { idx, stage in
                        let isDone = session.stage == .completed || (activeIdx != nil && idx < activeIdx!)
                        let isCurrent = session.stage != .completed && activeIdx == idx
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: isDone ? "checkmark.circle.fill" : (isCurrent ? "clock.fill" : "\(idx + 1).circle"))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(isDone ? palette.accent : (isCurrent ? palette.warning : palette.secondaryText))
                                .frame(width: 18, alignment: .center)
                                .padding(.top, 1)

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(stageTitle(stage))
                                        .font(.system(size: 12, weight: isCurrent ? .bold : .semibold))
                                        .foregroundStyle(isCurrent ? palette.warning : (isDone ? palette.primaryText : palette.secondaryText))
                                    Spacer()
                                    if isCurrent, let remaining = session.remainingHoldSeconds() {
                                        let mins = Int(remaining) / 60
                                        let secs = Int(remaining) % 60
                                        Text(String(format: "%02d:%02d", mins, secs))
                                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(palette.warning.opacity(0.2))
                                            .foregroundStyle(palette.warning)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    } else {
                                        Text(stageDuration(stage))
                                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(palette.surface)
                                            .foregroundStyle(palette.secondaryText)
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                if let desc = stageDescription(stage) {
                                    Text(desc)
                                        .font(.system(size: 11))
                                        .foregroundStyle(palette.secondaryText)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(isCurrent ? palette.warning.opacity(0.10) : palette.background.opacity(0.45))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(isCurrent ? palette.warning.opacity(0.6) : palette.border.opacity(0.5), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
    }

    private func stageDuration(_ stage: CalibrationStage) -> String {
        switch stage {
        case .chargingToFull: return L10n.text(.calStage1Duration, locale: locale)
        case .holdingFull: return L10n.text(.calStage2Duration, locale: locale)
        case .dischargingToLow: return L10n.text(.calStage3Duration, locale: locale)
        case .holdingLow: return L10n.text(.calStage4Duration, locale: locale)
        case .restoringLimit: return L10n.text(.calStage5Duration, locale: locale)
        case .idle, .completed: return ""
        }
    }

    private func stageTitle(_ stage: CalibrationStage) -> String {
        switch stage {
        case .idle: return L10n.text(.calibrationMode, locale: locale)
        case .chargingToFull: return L10n.text(.calStageChargingTitle, locale: locale)
        case .holdingFull: return L10n.text(.calStageHoldingFullTitle, locale: locale)
        case .dischargingToLow: return L10n.text(.calStageDischargingTitle, locale: locale)
        case .holdingLow: return L10n.text(.calStageHoldingLowTitle, locale: locale)
        case .restoringLimit: return L10n.text(.calStageRestoringTitle, locale: locale)
        case .completed: return L10n.text(.calStageCompletedTitle, locale: locale)
        }
    }

    private func stageDescription(_ stage: CalibrationStage) -> String? {
        switch stage {
        case .chargingToFull: return L10n.text(.calStageChargingDesc, locale: locale)
        case .holdingFull: return L10n.text(.calStageHoldingFullDesc, locale: locale)
        case .dischargingToLow: return L10n.text(.calStageDischargingDesc, locale: locale)
        case .holdingLow: return L10n.text(.calStageHoldingLowDesc, locale: locale)
        case .restoringLimit: return L10n.text(.calStageRestoringDesc, locale: locale)
        case .idle, .completed: return nil
        }
    }
}

@MainActor
public final class CustomBackgroundImageCache {
    public static let shared = CustomBackgroundImageCache()
    private var cachedPath: String?
    private var cachedImage: NSImage?

    private init() {}

    public func image(for path: String?) -> NSImage? {
        guard let path, !path.isEmpty else {
            cachedPath = nil
            cachedImage = nil
            return nil
        }
        if cachedPath == path, let cachedImage {
            return cachedImage
        }
        guard FileManager.default.fileExists(atPath: path) else {
            cachedPath = nil
            cachedImage = nil
            return nil
        }
        let img = Self.loadDownsampledImage(atPath: path, maxPixelSize: 1920)
        cachedPath = path
        cachedImage = img
        return img
    }

    private static func loadDownsampledImage(atPath path: String, maxPixelSize: CGFloat) -> NSImage? {
        let url = URL(fileURLWithPath: path) as CFURL
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithURL(url, sourceOptions as CFDictionary) else {
            return NSImage(contentsOfFile: path)
        }
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else {
            return NSImage(contentsOfFile: path)
        }
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}

public struct CustomBackgroundLayer: View {
    public let theme: ThemeConfig
    public let palette: ThemePalette

    public init(theme: ThemeConfig, palette: ThemePalette) {
        self.theme = theme
        self.palette = palette
    }

    public var body: some View {
        ZStack {
            palette.background

            if theme.useCustomBackground, let nsImage = CustomBackgroundImageCache.shared.image(for: theme.customBackgroundPath) {
                GeometryReader { geo in
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: geo.size.width, height: geo.size.height)
                        .blur(radius: theme.backgroundBlurRadius)
                        .clipped()
                }
                palette.background.opacity(theme.backgroundScrimOpacity)
            }
        }
        .ignoresSafeArea()
    }
}

public struct ToolbarEventToastView: View {
    @ObservedObject var presenter: VoltGuardPresenter

    public init(presenter: VoltGuardPresenter) {
        self.presenter = presenter
    }

    public var body: some View {
        let state = presenter.state
        let palette = state.palette
        let locale = state.settings.locale

        if let event = state.activeToolbarEvent {
            let sevColor = severityColor(event.severity, palette: palette)
            HStack(alignment: .center, spacing: 11) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(sevColor.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Image(systemName: event.icon)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(sevColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.text(event.titleKey, locale: locale))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(palette.primaryText)
                        .lineLimit(1)
                    Text(L10n.text(event.bodyKey, locale: locale))
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                if let actionTitleKey = event.actionTitleKey, let action = event.action {
                    Button {
                        presenter.dispatch(.triggerToolbarEventAction(action))
                    } label: {
                        Text(L10n.text(actionTitleKey, locale: locale))
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(sevColor)
                            .foregroundStyle(palette.isDark ? Color.black : Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .compatFocusEffectDisabled()
                }

                Button {
                    presenter.dispatch(.dismissToolbarEvent)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.secondaryText)
                        .frame(width: 22, height: 22)
                        .background(palette.background.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .compatFocusEffectDisabled()
            }
            .padding(12)
            .frame(width: 340)
            .background(palette.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(sevColor.opacity(0.65), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(0.45), radius: 14, y: 6)
        }
    }

    private func severityColor(_ severity: ToolbarEventSeverity, palette: ThemePalette) -> Color {
        switch severity {
        case .accent: return palette.accent
        case .warning: return palette.warning
        case .danger: return palette.danger
        }
    }
}

public struct InteractiveThermalZoneCard: View {
    public let telemetry: BatteryTelemetry
    public let maxAllowedTemp: Double
    public let heatProtectionEnabled: Bool
    public let locale: AppLocale
    public let palette: ThemePalette
    public let isVisible: Bool
    public let onAdjustMaxTemp: (Double) -> Void
    public let onToggleHeatProtection: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded: Bool = false
    @State private var isHovering: Bool = false

    public init(
        telemetry: BatteryTelemetry,
        maxAllowedTemp: Double,
        heatProtectionEnabled: Bool,
        locale: AppLocale,
        palette: ThemePalette,
        isVisible: Bool,
        onAdjustMaxTemp: @escaping (Double) -> Void,
        onToggleHeatProtection: @escaping () -> Void
    ) {
        self.telemetry = telemetry
        self.maxAllowedTemp = maxAllowedTemp
        self.heatProtectionEnabled = heatProtectionEnabled
        self.locale = locale
        self.palette = palette
        self.isVisible = isVisible
        self.onAdjustMaxTemp = onAdjustMaxTemp
        self.onToggleHeatProtection = onToggleHeatProtection
    }

    public var body: some View {
        let temp = telemetry.temperatureCelsius
        let normalized = min(max((temp - 20.0) / 25.0, 0.04), 1.0)
        let limitNorm = min(max((maxAllowedTemp - 20.0) / 25.0, 0.1), 0.96)
        let isHot = temp >= maxAllowedTemp
        let isWarm = !isHot && temp >= (maxAllowedTemp - 2.5)
        let tempColor: Color = isHot ? palette.danger : (isWarm ? palette.warning : palette.accent)
        let statusKey: L10nKey = isHot ? .thermalHotStatus : (isWarm ? .thermalWarmStatus : .thermalCoolStatus)
        let animate = isVisible && !reduceMotion

        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.84)) {
                    isExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        ZStack {
                            if animate {
                                Circle()
                                    .fill(tempColor.opacity(0.28))
                                    .frame(width: 14, height: 14)
                                    .scaleEffect(isHot ? 1.35 : (isWarm ? 1.18 : 1.0))
                            }
                            Circle()
                                .fill(tempColor)
                                .frame(width: 7, height: 7)
                        }
                        Text(L10n.text(.temperature, locale: locale))
                            .font(.caption)
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Text(L10n.text(statusKey, locale: locale))
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(tempColor.opacity(0.15))
                            .foregroundStyle(tempColor)
                            .clipShape(Capsule())
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(palette.secondaryText)
                            .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(String(format: "%.1f C", temp))
                            .font(.title3.bold().monospacedDigit())
                            .contentTransition(.numericText())
                            .foregroundStyle(tempColor)
                        Spacer()
                        Text("Max \(Int(maxAllowedTemp)) C")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(palette.secondaryText)
                    }

                    TimelineView(.animation(minimumInterval: 1.0 / 24.0, paused: !animate)) { timeline in
                        let phase = animate
                            ? (timeline.date.timeIntervalSinceReferenceDate * (isHot ? 1.4 : 0.7)).truncatingRemainder(dividingBy: 1.0)
                            : 0.5
                        GeometryReader { geo in
                            let fillWidth = max(geo.size.width * CGFloat(normalized), 8)
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
                                    .frame(width: fillWidth)
                                    .overlay(
                                        Group {
                                            if animate {
                                                Capsule()
                                                    .fill(
                                                        LinearGradient(
                                                            colors: [.clear, Color.white.opacity(isHot ? 0.45 : 0.28), .clear],
                                                            startPoint: .leading,
                                                            endPoint: .trailing
                                                        )
                                                    )
                                                    .frame(width: max(fillWidth * 0.35, 16))
                                                    .offset(x: CGFloat(phase) * max(fillWidth - 16, 1) - (fillWidth * 0.17))
                                            }
                                        }
                                    )
                                    .clipShape(Capsule())
                                Rectangle()
                                    .fill(palette.primaryText)
                                    .frame(width: 2, height: 11)
                                    .offset(x: geo.size.width * CGFloat(limitNorm))
                            }
                        }
                        .frame(height: 7)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .compatFocusEffectDisabled()

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Divider()

                    HStack(spacing: 6) {
                        Text(L10n.text(.thermalMultiSensorTitle, locale: locale))
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Text(telemetry.temperatureSensorSource)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(telemetry.isTemperatureSensorLive ? palette.accent : palette.warning)
                    }

                    HStack(spacing: 6) {
                        let sensors = telemetry.batteryThermalSensors.isEmpty
                            ? [telemetry.temperatureCelsius]
                            : telemetry.batteryThermalSensors
                        ForEach(Array(sensors.prefix(3).enumerated()), id: \.offset) { idx, val in
                            VStack(spacing: 2) {
                                Text("TB\(idx)T")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.secondaryText)
                                Text(String(format: "%.1f C", val))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.primaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(palette.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }

                        if let palm = telemetry.palmRestTemperatureCelsius {
                            VStack(spacing: 2) {
                                Text("Ts0P")
                                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(palette.secondaryText)
                                Text(String(format: "%.1f C", palm))
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(palette.primaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 4)
                            .background(palette.background.opacity(0.7))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        }
                    }

                    HStack(spacing: 8) {
                        Text(L10n.text(.thermalThresholdInline, locale: locale))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.secondaryText)
                        Spacer()
                        Button {
                            let next = max(maxAllowedTemp - 1.0, VoltGuardLimits.minTemperatureCelsius)
                            onAdjustMaxTemp(next)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(palette.background)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .compatFocusEffectDisabled()

                        Text("\(Int(maxAllowedTemp)) C")
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(palette.primaryText)
                            .frame(minWidth: 38)

                        Button {
                            let next = min(maxAllowedTemp + 1.0, VoltGuardLimits.maxTemperatureCelsius)
                            onAdjustMaxTemp(next)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(palette.background)
                                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .compatFocusEffectDisabled()
                    }

                    HStack {
                        Text(L10n.text(.heatProtection, locale: locale))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(palette.primaryText)
                        Spacer()
                        Toggle("", isOn: Binding(
                            get: { heatProtectionEnabled },
                            set: { _ in onToggleHeatProtection() }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.mini)
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .background(palette.surface)
        .overlay(
            RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous)
                .strokeBorder(isHovering || isExpanded ? tempColor.opacity(0.6) : palette.border, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius, style: .continuous))
        .scaleEffect(isHovering ? 1.01 : 1.0)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: isHovering)
        .onHover { hovering in
            isHovering = hovering
        }
    }
}
