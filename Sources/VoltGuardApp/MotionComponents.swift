import AppKit
import ImageIO
import SwiftUI
import VoltGuardDomain

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
        let amplitude = shouldAnimate ? (isActiveFlow ? LiquidBatteryConstants.waveAmplitude : LiquidBatteryConstants.calmWaveAmplitude) : 0
        let fillColor = resolvedFillColor

        TimelineView(.animation(minimumInterval: interval, paused: !shouldAnimate)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let phase = shouldAnimate
                ? (time.truncatingRemainder(dividingBy: cycleSeconds) / cycleSeconds) * (.pi * 2)
                : 0

            Canvas { graphics, size in
                let capHeight: CGFloat = 6
                let capWidth: CGFloat = size.width * 0.36
                let capRect = CGRect(
                    x: (size.width - capWidth) / 2,
                    y: 0,
                    width: capWidth,
                    height: capHeight
                )
                graphics.fill(
                    Path(roundedRect: capRect, cornerRadius: 3),
                    with: .color(palette.border)
                )

                let bodyRect = CGRect(x: 2, y: capHeight + 2, width: size.width - 4, height: size.height - capHeight - 4)
                let bodyPath = Path(roundedRect: bodyRect, cornerRadius: 12)
                graphics.fill(bodyPath, with: .color(palette.background))

                // Clip inner liquid and particles to battery chamber
                graphics.drawLayer { layer in
                    let innerRect = bodyRect.insetBy(dx: 3, dy: 3)
                    layer.clip(to: Path(roundedRect: innerRect, cornerRadius: 9))

                    let levelFraction = CGFloat(percentage) / 100.0
                    let surfaceY = innerRect.maxY - (innerRect.height * levelFraction)
                    let direction = mode == .discharging ? -phase : phase
                    let stepCount = 28

                    // Back parallax wave layer for liquid depth
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

                    // Front wave layer with vertical depth gradient and meniscus crest
                    var wavePath = Path()
                    var crestPath = Path()
                    wavePath.move(to: CGPoint(x: innerRect.minX, y: innerRect.maxY))
                    for step in 0...stepCount {
                        let t = CGFloat(step) / CGFloat(stepCount)
                        let x = innerRect.minX + t * innerRect.width
                        let yOffset = sin(Double(t) * .pi * 2 * LiquidBatteryConstants.waveCycles + direction) * Double(amplitude)
                        let pt = CGPoint(x: x, y: surfaceY + CGFloat(yOffset))
                        wavePath.addLine(to: pt)
                        if step == 0 {
                            crestPath.move(to: pt)
                        } else {
                            crestPath.addLine(to: pt)
                        }
                    }

                    wavePath.addLine(to: CGPoint(x: innerRect.maxX, y: innerRect.maxY))
                    wavePath.closeSubpath()

                    let liquidGradient = Gradient(colors: [
                        fillColor.opacity(0.96),
                        fillColor.opacity(0.72)
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
                            let baseX = 0.16 + 0.68 * CGFloat((idx * 37 + 13) % 11) / 10.0
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

                    // Sailing hysteresis buffer band below Target Limit
                    let limitFraction = CGFloat(limitPercent) / 100.0
                    let limitY = innerRect.maxY - (innerRect.height * limitFraction)
                    if let delta = sailingDeltaPercent, delta > 0 {
                        let floorFraction = CGFloat(max(limitPercent - delta, VoltGuardLimits.minSailingFloorPercent)) / 100.0
                        let floorY = innerRect.maxY - (innerRect.height * floorFraction)
                        let bandRect = CGRect(x: innerRect.minX, y: limitY, width: innerRect.width, height: max(floorY - limitY, 0))
                        layer.fill(Path(bandRect), with: .color(palette.primaryText.opacity(0.12)))
                    }

                    // Target Limit Gate horizontal line
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
                            .foregroundStyle(palette.primaryText.opacity(0.85))
                        let tagY = max(limitY - 7, innerRect.minY + 6)
                        layer.draw(tag, at: CGPoint(x: innerRect.maxX - 13, y: tagY))
                    }
                }

                let pulse = (shouldAnimate && mode == .charging) ? (0.55 + 0.45 * (0.5 + 0.5 * sin(time * 3.2))) : 0.0
                let rimColor = isDraggingLimit
                    ? palette.accent
                    : (mode == .charging && shouldAnimate ? fillColor.opacity(pulse) : palette.border)
                let rimWidth: CGFloat = (isDraggingLimit || (mode == .charging && shouldAnimate)) ? 2.0 : 1.5
                graphics.stroke(bodyPath, with: .color(rimColor), lineWidth: rimWidth)
            }
            .overlay(alignment: .center) {
                VStack(spacing: 1) {
                    Text("\(percentage)%")
                        .font(.system(size: width * 0.24, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(palette.primaryText)
                        .shadow(color: palette.background.opacity(0.6), radius: 2, y: 1)

                    if mode == .charging || mode == .discharging {
                        let iconPulse = shouldAnimate ? (0.72 + 0.28 * (0.5 + 0.5 * sin(time * 4.0))) : 1.0
                        Image(systemName: mode == .charging ? "bolt.fill" : "arrow.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(palette.primaryText.opacity(iconPulse))
                            .shadow(color: fillColor.opacity(shouldAnimate ? 0.7 : 0), radius: 3)
                            .accessibilityHidden(true)
                    }
                }
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
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(L10n.text(.livePowerFlow, locale: locale))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(palette.primaryText)
                Spacer()
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: MotionConstants.uiTransitionDuration)) {
                        isExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Toggle telemetry details"))
            }

            HStack(spacing: 8) {
                topologyNode(
                    icon: "powerplug.fill",
                    label: L10n.text(.adapterInput, locale: locale),
                    watts: flow.adapterInputWatts,
                    active: telemetry.isPluggedIn
                )
                topologyNode(
                    icon: "laptopcomputer",
                    label: L10n.text(.systemLoad, locale: locale),
                    watts: flow.systemLoadWatts,
                    active: true
                )
                topologyNode(
                    icon: "battery.100percent",
                    label: L10n.text(.batteryNet, locale: locale),
                    watts: flow.batteryNetWatts,
                    active: abs(flow.batteryNetWatts) >= MotionConstants.activeFlowWattThreshold
                )
            }

            LivePowerFlowStreamView(
                isPluggedIn: telemetry.isPluggedIn,
                adapterInputWatts: flow.adapterInputWatts,
                batteryNetWatts: flow.batteryNetWatts,
                palette: palette,
                isVisible: isVisible
            )

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(String(format: "%.2f V", telemetry.voltageVolts))
                        Spacer()
                        Text(String(format: "%.2f A", telemetry.amperageAmps))
                        Spacer()
                        Text(String(format: "%.1f C", telemetry.temperatureCelsius))
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
                            }
                        }
                    }
                }
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(palette.secondaryText)
                .padding(.top, 2)
                .transition(.opacity)
            }
        }
        .padding(12)
        .background(palette.surface)
        .overlay(RoundedRectangle(cornerRadius: palette.cornerRadius).stroke(palette.border, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: palette.cornerRadius))
    }

    @ViewBuilder
    private func topologyNode(icon: String, label: String, watts: Double, active: Bool) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(active ? palette.accent : palette.secondaryText)
                    .accessibilityHidden(true)
                Text(label)
                    .font(.system(size: 10))
                    .foregroundStyle(palette.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            Text(String(format: "%.1f W", watts))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .contentTransition(.numericText())
                .foregroundStyle(palette.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(palette.background)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

public struct TelemetrySparklineView: View {
    public let samples: [TelemetrySample]
    public let palette: ThemePalette

    public init(samples: [TelemetrySample], palette: ThemePalette) {
        self.samples = samples
        self.palette = palette
    }

    public var body: some View {
        Canvas { graphics, size in
            guard samples.count >= 2 else { return }
            let maxW = max(samples.map(\.watts).max() ?? 10, 10)
            let stepX = size.width / CGFloat(samples.count - 1)

            var line = Path()
            for (idx, sample) in samples.enumerated() {
                let x = CGFloat(idx) * stepX
                let y = size.height - (CGFloat(sample.watts / maxW) * (size.height - 6)) - 3
                if idx == 0 {
                    line.move(to: CGPoint(x: x, y: y))
                } else {
                    line.addLine(to: CGPoint(x: x, y: y))
                }
            }
            graphics.stroke(line, with: .color(palette.accent), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
        .frame(height: 48)
        .accessibilityHidden(true)
    }
}

public struct LivePowerFlowStreamView: View {
    public let isPluggedIn: Bool
    public let adapterInputWatts: Double
    public let batteryNetWatts: Double
    public let palette: ThemePalette
    public let isVisible: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        isPluggedIn: Bool,
        adapterInputWatts: Double = 0,
        batteryNetWatts: Double,
        palette: ThemePalette,
        isVisible: Bool = true
    ) {
        self.isPluggedIn = isPluggedIn
        self.adapterInputWatts = adapterInputWatts
        self.batteryNetWatts = batteryNetWatts
        self.palette = palette
        self.isVisible = isVisible
    }

    public var body: some View {
        let hasAdapterFlow = isPluggedIn && adapterInputWatts >= MotionConstants.activeFlowWattThreshold
        let hasBatteryFlow = abs(batteryNetWatts) >= MotionConstants.activeFlowWattThreshold
        let isActiveFlow = hasAdapterFlow || hasBatteryFlow
        let shouldAnimate = isVisible && !reduceMotion && isActiveFlow
        let isDischarging = batteryNetWatts < -MotionConstants.activeFlowWattThreshold
        let batteryFlowColor = isDischarging ? palette.warning : palette.accent

        let maxWatts = max(adapterInputWatts, abs(batteryNetWatts), 10.0)
        let speedMultiplier = min(max(maxWatts / 25.0, 0.75), 2.2)
        let effectiveCycle = MotionConstants.flowCycleSeconds / speedMultiplier

        TimelineView(.animation(minimumInterval: MotionConstants.flowFrameInterval, paused: !shouldAnimate)) { context in
            let phase = !shouldAnimate
                ? 0
                : (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: effectiveCycle) / effectiveCycle)

            Canvas { graphics, size in
                let y = size.height / 2
                let startX: CGFloat = 6
                let midX: CGFloat = size.width / 2
                let endX: CGFloat = size.width - 6
                let leftSpan = max(midX - startX - 6, 1)
                let rightSpan = max(endX - (midX + 6), 1)

                var leftTrack = Path()
                leftTrack.move(to: CGPoint(x: startX, y: y))
                leftTrack.addLine(to: CGPoint(x: midX - 5, y: y))
                graphics.stroke(leftTrack, with: .color(hasAdapterFlow ? palette.accent.opacity(0.35) : palette.border), lineWidth: 2)

                var rightTrack = Path()
                rightTrack.move(to: CGPoint(x: midX + 5, y: y))
                rightTrack.addLine(to: CGPoint(x: endX, y: y))
                graphics.stroke(rightTrack, with: .color(hasBatteryFlow ? batteryFlowColor.opacity(0.35) : palette.border), lineWidth: 2)

                let hubRect = CGRect(x: midX - 3, y: y - 3, width: 6, height: 6)
                graphics.fill(Path(ellipseIn: hubRect), with: .color(palette.secondaryText.opacity(0.6)))

                if hasAdapterFlow {
                    let dotCount = 3
                    for index in 0..<dotCount {
                        let offset = (phase + Double(index) / Double(dotCount)).truncatingRemainder(dividingBy: 1.0)
                        let x = startX + CGFloat(offset) * leftSpan
                        let dotRect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                        graphics.fill(Path(ellipseIn: dotRect), with: .color(palette.accent))
                    }
                }

                if hasBatteryFlow {
                    let dotCount = 3
                    for index in 0..<dotCount {
                        let rawOffset = (phase + Double(index) / Double(dotCount)).truncatingRemainder(dividingBy: 1.0)
                        let directed = isDischarging ? (1.0 - rawOffset) : rawOffset
                        let x = (midX + 6) + CGFloat(directed) * rightSpan
                        let dotRect = CGRect(x: x - 3, y: y - 3, width: 6, height: 6)
                        graphics.fill(Path(ellipseIn: dotRect), with: .color(batteryFlowColor))
                    }
                }
            }
            .frame(height: 12)
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
        let activeIdx = Self.stages.firstIndex(of: session.stage) ?? 0
        let shouldAnimate = isVisible && !reduceMotion && session.isActive
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            TimelineView(.animation(minimumInterval: LiquidBatteryConstants.calmFlowFrameInterval, paused: !shouldAnimate)) { context in
                let phase = !shouldAnimate
                    ? 0.5
                    : (context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.8) / 1.8)

                HStack(spacing: 4) {
                    ForEach(Array(Self.stages.enumerated()), id: \.element) { idx, _ in
                        GeometryReader { geo in
                            let isCompleted = session.stage == .completed || idx < activeIdx
                            let isCurrent = session.stage != .completed && idx == activeIdx
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

            if !compact, let desc = stageDescription(session.stage) {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(palette.secondaryText)
            }
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
