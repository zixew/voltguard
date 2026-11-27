import Foundation
import VoltGuardDomain

public enum L10nKey: String, CaseIterable, Sendable {
    case appTitle
    case openFullApp
    case statusCharging
    case statusLimitReached
    case statusSailing
    case statusHeatPaused
    case statusManualDischarge
    case statusAutoDischarge
    case statusTopUp
    case statusCalibration
    case statusSleepingInhibited
    case statusOnBattery
    case chargeLimit
    case livePowerFlow
    case adapterInput
    case systemLoad
    case batteryNet
    case quickActions
    case discharge
    case autoDischarge
    case clamshellDischarge
    case heatProtection
    case sailingMode
    case magSafeLED
    case topUp
    case calibrationMode
    case startCalibration
    case stopCalibration
    case calibrationActiveHint
    case schedule
    case addSchedule
    case noSchedulesHint
    case sleepControl
    case stopChargingOnSleep
    case lowPowerOnBattery
    case lowPowerAlways
    case batteryHealth
    case cycles
    case temperature
    case capacity
    case settings
    case quit
    case helperConnected
    case helperDryRun
    case installHelper
    case tabOverview
    case tabCharging
    case tabEnergy
    case tabSchedule
    case tabTheme
    case tabInterface
    case tabGuide
    case energyMonitorTitle
    case energyMonitorSubtitle
    case energyLoading
    case energyEmpty
    case energyRefresh
    case energyQuitApp
    case energyImpactLow
    case energyImpactMedium
    case energyImpactHigh
    case themePreset
    case customAccent
    case cornerRadius
    case surfaceOpacity
    case menuBarStyle
    case showPercentage
    case showWattage
    case showTemperature
    case popoverModules
    case popoverDensity
    case language
    case telemetryLoading
    case telemetryErrorTitle
    case telemetryRetry
    case userGuideSummary
    case recommendedProfilesTitle
    case recommendedBadge
    case applyProfile
    case appliedProfile
    case profileTravelTitle
    case profileTravelDesc
    case profileBalancedTitle
    case profileBalancedDesc
    case profileDeskTitle
    case profileDeskDesc
    case profileMaxLifespanTitle
    case profileMaxLifespanDesc
    case reasonHighTemp
    case reasonClamshell
    case reasonLowBattery
    case reasonDaily
    case minimizeToBackground
    case hideMenuBarIcon
    case launchAtLogin
    case smartAlerts
    case alertHeatTitle
    case alertHeatBody
    case alertTopUpTitle
    case alertTopUpBody
    case alertCalibrationTitle
    case alertCalibrationBody
    case healthHistoryTitle
    case exportCSV
    case csvCopiedHint
    case diagnosticsTitle
    case runDiagnostics
    case diagIOKit
    case diagHelper
    case diagLogin
    case diagAlerts
    case diagPass
    case diagInactive
    case globalHotkeyHint
    case timeRemaining
    case adapterDetails
    case moveUp
    case moveDown
    case uninstallHelper
    case showTimeRemaining
    case etaToEmpty
    case etaToLimit
    case etaLimitReached
    case etaCalculating
    case batteryCondition
    case conditionNormal
    case conditionFair
    case conditionService
    case currentCapacity
    case maxCapacity
    case designCapacity
    case capacityLoss
    case cycleLife
    case batteryChip
    case underpoweredCharger
    case healthTrendTitle
    case healthHistoryEmpty
    case daysRecordedFormat
    case sailingDeltaLabel
    case moduleChargeControl
    case modulePowerFlow
    case moduleQuickActions
    case moduleCalibrationSchedule
    case moduleBatteryHealth
    case ledSystem
    case ledOff
    case ledGreen
    case ledAmber
    case ledSyncWithLimit
    case alertLowBatteryTitle
    case alertLowBatteryBody
    case alertLimitReachedTitle
    case alertLimitReachedBody
    case customProfileTitle
    case customProfileEmpty
    case saveCustomProfile
    case applyCustomProfile
    case settingsBackupTitle
    case exportSettings
    case importSettings
    case resetSettings
    case settingsSavedFeedback
    case settingsResetFeedback
    case settingsImportError
    case calStageChargingTitle
    case calStageChargingDesc
    case calStageHoldingFullTitle
    case calStageHoldingFullDesc
    case calStageDischargingTitle
    case calStageDischargingDesc
    case calStageHoldingLowTitle
    case calStageHoldingLowDesc
    case calStageRestoringTitle
    case calStageRestoringDesc
    case calStageCompletedTitle
    case calNeedsCharger
    case calNeedsHelper
    case scheduleRulePlaceholder
    case scheduleSetLimit80
    case scheduleTopUp100
    case scheduleEnableDischarge
    case scheduleDisableDischarge
    case activityLogTitle
    case activityLogEmpty
    case activityHeatPaused
    case activityLimitReached
    case activityTopUpDone
    case activityCalibrationDone
    case activityLowBattery
    case presetObsidianSlate
    case presetPaperLight
    case presetNordicMist
    case presetMidnightAmber
    case workspaceBackgroundTitle
    case bgSolidTheme
    case bgCustomImage
    case bgChooseImage
    case bgNoImageSelected
    case bgScrimOpacity
    case bgBlur
    case iconStyleShield
    case iconStyleRing
    case iconStylePill
    case iconStyleBolt
    case densityDetailed
    case densityCompact
    case calPurposeTitle
    case calPurposeBody
    case calStage1Duration
    case calStage2Duration
    case calStage3Duration
    case calStage4Duration
    case calStage5Duration
    case calTotalDurationBadge
    case bypassActiveBadge
    case bypassFlowSubtitle
    case bypassCardTitle
    case bypassCardDesc
    case dischargeDesc
    case autoDischargeDesc
    case clamshellDischargeDesc
    case topUpDesc
    case sailingModeDesc
    case heatProtectionDesc
    case sleepControlDesc
    case stopChargingOnSleepDesc
    case lowPowerOnBatteryDesc
    case lowPowerAlwaysDesc
    case magSafeSyncLegend
}

public struct L10n {
    public static func text(_ key: L10nKey, locale: AppLocale) -> String {
        switch locale {
        case .en: return en[key] ?? key.rawValue
        case .id: return id[key] ?? key.rawValue
        }
    }

    public static let en: [L10nKey: String] = [
        .appTitle: "VoltGuard",
        .openFullApp: "Open App",
        .statusCharging: "Charging",
        .statusLimitReached: "Bypass Charging (Limit Reached)",
        .statusSailing: "Sailing Mode",
        .statusHeatPaused: "Paused (Thermal Guard)",
        .statusManualDischarge: "Discharging",
        .statusAutoDischarge: "Auto Discharging",
        .statusTopUp: "Topping Up to 100%",
        .statusCalibration: "Calibrating Battery",
        .statusSleepingInhibited: "Sleep Charge Blocked",
        .statusOnBattery: "On Battery",
        .chargeLimit: "Charge Limit",
        .livePowerFlow: "Live Power Flow",
        .adapterInput: "Adapter In",
        .systemLoad: "System Draw",
        .batteryNet: "Battery Net",
        .quickActions: "Power Controls",
        .discharge: "Discharge",
        .autoDischarge: "Auto Discharge",
        .clamshellDischarge: "Clamshell Discharge",
        .heatProtection: "Heat Protection",
        .sailingMode: "Sailing Mode",
        .magSafeLED: "MagSafe LED",
        .topUp: "Top Up 100%",
        .calibrationMode: "Calibration",
        .startCalibration: "Start Calibration",
        .stopCalibration: "Stop Calibration",
        .calibrationActiveHint: "Guided 5-stage cycle in progress",
        .schedule: "Schedule",
        .addSchedule: "Add Rule",
        .noSchedulesHint: "No schedule rules yet. Add one to automate Top Up or 80% limits.",
        .sleepControl: "Keep Awake on Discharge",
        .stopChargingOnSleep: "Stop Charging on Sleep",
        .lowPowerOnBattery: "Low Power on Battery",
        .lowPowerAlways: "Always Low Power",
        .batteryHealth: "Battery Health",
        .cycles: "Cycles",
        .temperature: "Temp",
        .capacity: "Capacity",
        .settings: "Settings",
        .quit: "Quit VoltGuard",
        .helperConnected: "SMC Helper Active",
        .helperDryRun: "Read-Only",
        .installHelper: "Install SMC Helper",
        .tabOverview: "Overview",
        .tabCharging: "Power & Limits",
        .tabEnergy: "Energy Monitor",
        .tabSchedule: "Calibration & Schedule",
        .tabTheme: "Appearance",
        .tabInterface: "Bar & Layout",
        .tabGuide: "System & Guide",
        .energyMonitorTitle: "Apps Using Significant Energy",
        .energyMonitorSubtitle: "Active macOS apps ranked by CPU draw. Quit heavy apps safely to reduce battery drain.",
        .energyLoading: "Sampling running applications...",
        .energyEmpty: "No high-draw user apps detected right now.",
        .energyRefresh: "Refresh",
        .energyQuitApp: "Quit",
        .energyImpactLow: "Low",
        .energyImpactMedium: "Medium",
        .energyImpactHigh: "High",
        .themePreset: "Theme Preset",
        .customAccent: "Accent Color",
        .cornerRadius: "Corner Radius",
        .surfaceOpacity: "Surface Opacity",
        .menuBarStyle: "Menu Bar Icon",
        .showPercentage: "Show Percentage",
        .showWattage: "Show Live Watts",
        .showTemperature: "Show Temperature",
        .popoverModules: "Visible Popover Modules",
        .popoverDensity: "Popover Density",
        .language: "Language",
        .telemetryLoading: "Reading battery telemetry...",
        .telemetryErrorTitle: "Unable to read battery sensor",
        .telemetryRetry: "Retry",
        .userGuideSummary: "VoltGuard caps charge at your target percentage, monitors temperature, and lets you discharge or calibrate safely from the menu bar or full window. Install the SMC Helper in System & Guide to enable hardware write controls.",
        .recommendedProfilesTitle: "Recommended Profiles",
        .recommendedBadge: "Recommended",
        .applyProfile: "Apply",
        .appliedProfile: "Active",
        .profileTravelTitle: "Travel",
        .profileTravelDesc: "100% cap, Low Power on battery, ready for long trips.",
        .profileBalancedTitle: "Balanced",
        .profileBalancedDesc: "80% cap, Sailing 5%, Thermal Guard 35 C for daily use.",
        .profileDeskTitle: "Desk Docked",
        .profileDeskDesc: "75% cap, Auto & Clamshell Discharge for plugged-in work.",
        .profileMaxLifespanTitle: "Max Lifespan",
        .profileMaxLifespanDesc: "60% cap, Sailing 8%, Thermal Guard 32 C for lowest wear.",
        .reasonHighTemp: "Battery is warm. Max Lifespan lowers heat stress.",
        .reasonClamshell: "Lid is closed on AC power. Desk Docked fits this setup.",
        .reasonLowBattery: "Battery is low on mobile use. Travel unlocks full charge.",
        .reasonDaily: "Balanced protects daily battery health with 80% cap.",
        .minimizeToBackground: "Minimize",
        .hideMenuBarIcon: "Hide Icon",
        .launchAtLogin: "Launch at Login",
        .smartAlerts: "Smart Thermal & Completion Alerts",
        .alertHeatTitle: "Thermal Guard Active",
        .alertHeatBody: "Charging paused because battery temperature reached your limit.",
        .alertTopUpTitle: "Top Up Complete",
        .alertTopUpBody: "Battery reached 100%. Charge limit restored.",
        .alertCalibrationTitle: "Calibration Complete",
        .alertCalibrationBody: "Battery calibration cycle finished.",
        .healthHistoryTitle: "Battery Health History",
        .exportCSV: "Copy CSV",
        .csvCopiedHint: "CSV copied to clipboard",
        .diagnosticsTitle: "System Diagnostics",
        .runDiagnostics: "Run Self-Test",
        .diagIOKit: "IOKit Battery Sensor",
        .diagHelper: "SMC Privileged Helper",
        .diagLogin: "Launch at Login",
        .diagAlerts: "Smart Alerts",
        .diagPass: "OK",
        .diagInactive: "Inactive",
        .globalHotkeyHint: "Global Shortcut: Cmd+Option+V toggles menu bar popover",
        .timeRemaining: "Time Left",
        .adapterDetails: "Adapter",
        .moveUp: "Move Up",
        .moveDown: "Move Down",
        .uninstallHelper: "Uninstall Helper",
        .showTimeRemaining: "Show Time Estimate",
        .etaToEmpty: "until empty",
        .etaToLimit: "to %d%% full",
        .etaLimitReached: "%d%% limit (Bypass Active)",
        .etaCalculating: "Calculating time...",
        .batteryCondition: "Condition",
        .conditionNormal: "Normal",
        .conditionFair: "Fair",
        .conditionService: "Service Recommended",
        .currentCapacity: "Current",
        .maxCapacity: "Max Capacity",
        .designCapacity: "Design",
        .capacityLoss: "Wear",
        .cycleLife: "Cycle Life",
        .batteryChip: "Controller",
        .underpoweredCharger: "Adapter wattage is lower than system load; battery may drain.",
        .healthTrendTitle: "Health Trend",
        .healthHistoryEmpty: "No health history recorded yet. Daily snapshots appear here automatically.",
        .daysRecordedFormat: "%d days recorded",
        .sailingDeltaLabel: "Sailing Delta",
        .moduleChargeControl: "Charge Control",
        .modulePowerFlow: "Power Flow",
        .moduleQuickActions: "Quick Actions",
        .moduleCalibrationSchedule: "Calibration & Schedule",
        .moduleBatteryHealth: "Battery Health",
        .ledSystem: "System",
        .ledOff: "Off",
        .ledGreen: "Green",
        .ledAmber: "Amber",
        .ledSyncWithLimit: "Sync",
        .alertLowBatteryTitle: "Low Battery",
        .alertLowBatteryBody: "Battery dropped below 20%. Connect your charger soon.",
        .alertLimitReachedTitle: "Charge Limit Reached",
        .alertLimitReachedBody: "Battery reached your target charge limit.",
        .customProfileTitle: "Custom Profile",
        .customProfileEmpty: "Save your current limit, sailing delta, and max temperature as a custom preset.",
        .saveCustomProfile: "Save Current",
        .applyCustomProfile: "Apply Custom",
        .settingsBackupTitle: "Settings Backup & Reset",
        .exportSettings: "Copy Settings JSON",
        .importSettings: "Paste Settings JSON",
        .resetSettings: "Reset to Default",
        .settingsSavedFeedback: "Settings JSON copied to clipboard.",
        .settingsResetFeedback: "Settings restored to defaults.",
        .settingsImportError: "Clipboard does not contain valid VoltGuard JSON.",
        .calStageChargingTitle: "1. Charging to 100%",
        .calStageChargingDesc: "Charging battery to full capacity before hold phase.",
        .calStageHoldingFullTitle: "2. Holding at 100%",
        .calStageHoldingFullDesc: "Holding full charge to stabilize cell voltage.",
        .calStageDischargingTitle: "3. Discharging to 15%",
        .calStageDischargingDesc: "Controlled discharge to calibrate low-end gauge.",
        .calStageHoldingLowTitle: "4. Holding at 15%",
        .calStageHoldingLowDesc: "Resting at low charge so fuel gauge resets baseline.",
        .calStageRestoringTitle: "5. Restoring Limit",
        .calStageRestoringDesc: "Recharging back to your saved charge limit.",
        .calStageCompletedTitle: "Calibration Complete",
        .calNeedsCharger: "Connect power adapter to run battery calibration.",
        .calNeedsHelper: "Install SMC Helper in System & Guide so controlled discharge works.",
        .scheduleRulePlaceholder: "Rule name",
        .scheduleSetLimit80: "Set 80% Limit",
        .scheduleTopUp100: "Top Up 100%",
        .scheduleEnableDischarge: "Enable Discharge",
        .scheduleDisableDischarge: "Disable Discharge",
        .activityLogTitle: "Activity Log",
        .activityLogEmpty: "No power events recorded in this session yet.",
        .activityHeatPaused: "Charging paused due to heat protection",
        .activityLimitReached: "Charge limit reached",
        .activityTopUpDone: "Top Up 100% completed, limit restored",
        .activityCalibrationDone: "Battery calibration cycle completed",
        .activityLowBattery: "Battery dropped below 20%",
        .presetObsidianSlate: "Obsidian",
        .presetPaperLight: "Paper Light",
        .presetNordicMist: "Nordic Mist",
        .presetMidnightAmber: "Midnight",
        .workspaceBackgroundTitle: "Workspace Background",
        .bgSolidTheme: "Solid Theme",
        .bgCustomImage: "Custom Image",
        .bgChooseImage: "Choose Custom Image...",
        .bgNoImageSelected: "No image selected",
        .bgScrimOpacity: "Scrim Opacity",
        .bgBlur: "Blur",
        .iconStyleShield: "Shield Battery",
        .iconStyleRing: "Ring Gauge",
        .iconStylePill: "Percentage Pill",
        .iconStyleBolt: "Minimal Bolt",
        .densityDetailed: "Detailed",
        .densityCompact: "Compact",
        .calPurposeTitle: "Purpose & Estimated Duration",
        .calPurposeBody: "Keeping a battery capped at 60%-80% slows chemical aging, but over time the fuel-gauge controller (bq40z651) drifts. A full 100% -> 15% -> Limit cycle recalibrates the upper and lower voltage anchor points so macOS reports accurate percentage and Maximum Capacity. Run once every 1-3 months.",
        .calStage1Duration: "~30-90 min",
        .calStage2Duration: "60 min hold",
        .calStage3Duration: "~1-3 hours",
        .calStage4Duration: "60 min hold",
        .calStage5Duration: "~30-60 min",
        .calTotalDurationBadge: "Total: ~3.5 - 6 Hours",
        .bypassActiveBadge: "Bypass Active",
        .bypassFlowSubtitle: "Direct Adapter -> Mac power (Battery bypassed at 0 W)",
        .bypassCardTitle: "Automatic Bypass Charging at Limit",
        .bypassCardDesc: "When battery reaches your target limit (e.g. 80%), VoltGuard automatically switches to hardware Bypass Charging: your Mac runs 100% directly from the power adapter while the battery rests at 0.0 W.",
        .dischargeDesc: "Run on battery power even while the power adapter is connected.",
        .autoDischargeDesc: "Automatically drain battery down to your limit when plugged in above cap.",
        .clamshellDischargeDesc: "Allow battery discharge while MacBook lid is closed in clamshell mode.",
        .topUpDesc: "Charge to 100% once before travel, then restore your daily limit.",
        .sailingModeDesc: "Let battery drop by a few percent before recharging to prevent micro-cycles.",
        .heatProtectionDesc: "Pause charging automatically when battery temperature exceeds your threshold.",
        .sleepControlDesc: "Prevent macOS from sleeping while active discharge or calibration is running.",
        .stopChargingOnSleepDesc: "Block battery charging whenever your Mac enters sleep mode.",
        .lowPowerOnBatteryDesc: "Enable macOS Low Power Mode automatically whenever unplugged.",
        .lowPowerAlwaysDesc: "Keep macOS Low Power Mode active on both battery and power adapter.",
        .magSafeSyncLegend: "Sync Mode: Charging = Amber  |  Limit Reached (Bypass) = Green  |  Discharging = LED Off"
    ]

    public static let id: [L10nKey: String] = [
        .appTitle: "VoltGuard",
        .openFullApp: "Buka Aplikasi",
        .statusCharging: "Mengisi Daya",
        .statusLimitReached: "Bypass Charging (Batas Tercapai)",
        .statusSailing: "Mode Sailing",
        .statusHeatPaused: "Dijeda (Pelindung Panas)",
        .statusManualDischarge: "Menguras Baterai",
        .statusAutoDischarge: "Kuras Otomatis",
        .statusTopUp: "Isi Penuh 100%",
        .statusCalibration: "Kalibrasi Baterai",
        .statusSleepingInhibited: "Isi Saat Tidur Diblokir",
        .statusOnBattery: "Menggunakan Baterai",
        .chargeLimit: "Batas Pengisian",
        .livePowerFlow: "Aliran Daya Langsung",
        .adapterInput: "Masuk Adapter",
        .systemLoad: "Beban Sistem",
        .batteryNet: "Arus Baterai",
        .quickActions: "Kontrol Daya",
        .discharge: "Discharge",
        .autoDischarge: "Discharge Otomatis",
        .clamshellDischarge: "Discharge Clamshell",
        .heatProtection: "Pelindung Panas",
        .sailingMode: "Mode Sailing",
        .magSafeLED: "LED MagSafe",
        .topUp: "Isi Penuh 100%",
        .calibrationMode: "Kalibrasi",
        .startCalibration: "Mulai Kalibrasi",
        .stopCalibration: "Hentikan Kalibrasi",
        .calibrationActiveHint: "Siklus terpandu 5 tahap sedang berjalan",
        .schedule: "Jadwal",
        .addSchedule: "Tambah Aturan",
        .noSchedulesHint: "Belum ada jadwal. Tambahkan aturan untuk Top Up atau batas 80% otomatis.",
        .sleepControl: "Cegah Tidur Saat Discharge",
        .stopChargingOnSleep: "Hentikan Isi Saat Tidur",
        .lowPowerOnBattery: "Hemat Daya di Baterai",
        .lowPowerAlways: "Selalu Hemat Daya",
        .batteryHealth: "Kesehatan Baterai",
        .cycles: "Siklus",
        .temperature: "Suhu",
        .capacity: "Kapasitas",
        .settings: "Pengaturan",
        .quit: "Keluar VoltGuard",
        .helperConnected: "Helper SMC Aktif",
        .helperDryRun: "Baca-Saja",
        .installHelper: "Pasang Helper SMC",
        .tabOverview: "Ringkasan",
        .tabCharging: "Daya & Batas",
        .tabEnergy: "Monitor Energi",
        .tabSchedule: "Kalibrasi & Jadwal",
        .tabTheme: "Tampilan & Tema",
        .tabInterface: "Bar & Tata Letak",
        .tabGuide: "Sistem & Panduan",
        .energyMonitorTitle: "Aplikasi Konsumsi Energi Tinggi",
        .energyMonitorSubtitle: "Daftar aplikasi aktif berdasarkan beban CPU. Tutup aplikasi berat untuk menghemat baterai.",
        .energyLoading: "Memindai aplikasi yang sedang berjalan...",
        .energyEmpty: "Tidak ada aplikasi pengguna dengan beban tinggi saat ini.",
        .energyRefresh: "Segarkan",
        .energyQuitApp: "Tutup",
        .energyImpactLow: "Rendah",
        .energyImpactMedium: "Sedang",
        .energyImpactHigh: "Tinggi",
        .themePreset: "Preset Tema",
        .customAccent: "Warna Aksen",
        .cornerRadius: "Radius Sudut",
        .surfaceOpacity: "Opasitas Latar",
        .menuBarStyle: "Ikon Menu Bar",
        .showPercentage: "Tampilkan Persentase",
        .showWattage: "Tampilkan Watt Langsung",
        .showTemperature: "Tampilkan Suhu",
        .popoverModules: "Modul Popover Aktif",
        .popoverDensity: "Kepadatan Popover",
        .language: "Bahasa",
        .telemetryLoading: "Membaca sensor baterai...",
        .telemetryErrorTitle: "Gagal membaca sensor baterai",
        .telemetryRetry: "Coba Lagi",
        .userGuideSummary: "VoltGuard membatasi pengisian sesuai target persentase, memantau suhu, serta mendukung discharge dan kalibrasi dari menu bar maupun jendela penuh. Pasang Helper SMC di Sistem & Panduan untuk mengaktifkan kontrol perangkat keras.",
        .recommendedProfilesTitle: "Rekomendasi Profil",
        .recommendedBadge: "Disarankan",
        .applyProfile: "Terapkan",
        .appliedProfile: "Aktif",
        .profileTravelTitle: "Travel",
        .profileTravelDesc: "Batas 100%, Hemat Daya di baterai, siap bepergian.",
        .profileBalancedTitle: "Balanced",
        .profileBalancedDesc: "Batas 80%, Sailing 5%, Pelindung Panas 35 C untuk harian.",
        .profileDeskTitle: "Desk Docked",
        .profileDeskDesc: "Batas 75%, Discharge Otomatis & Clamshell saat colok daya.",
        .profileMaxLifespanTitle: "Max Lifespan",
        .profileMaxLifespanDesc: "Batas 60%, Sailing 8%, Pelindung Panas 32 C paling awet.",
        .reasonHighTemp: "Suhu baterai hangat. Max Lifespan mengurangi panas.",
        .reasonClamshell: "Laptop tertutup dengan charger. Desk Docked paling cocok.",
        .reasonLowBattery: "Baterai rendah saat mobilitas. Travel membuka isi penuh.",
        .reasonDaily: "Balanced menjaga baterai harian tetap awet di batas 80%.",
        .minimizeToBackground: "Sembunyikan",
        .hideMenuBarIcon: "Sembunyikan Ikon",
        .launchAtLogin: "Jalankan Saat Login",
        .smartAlerts: "Notifikasi Panas & Pengisian Selesai",
        .alertHeatTitle: "Pelindung Panas Aktif",
        .alertHeatBody: "Pengisian dijeda karena suhu baterai melewati batas aman.",
        .alertTopUpTitle: "Top Up 100% Selesai",
        .alertTopUpBody: "Baterai mencapai 100%. Batas pengisian dipulihkan.",
        .alertCalibrationTitle: "Kalibrasi Selesai",
        .alertCalibrationBody: "Siklus kalibrasi baterai telah selesai.",
        .healthHistoryTitle: "Riwayat Kesehatan Baterai",
        .exportCSV: "Salin CSV",
        .csvCopiedHint: "CSV disalin ke clipboard",
        .diagnosticsTitle: "Diagnostik Sistem",
        .runDiagnostics: "Jalankan Uji Mandiri",
        .diagIOKit: "Sensor Baterai IOKit",
        .diagHelper: "Helper SMC Root",
        .diagLogin: "Jalankan Saat Login",
        .diagAlerts: "Notifikasi Cerdas",
        .diagPass: "OK",
        .diagInactive: "Nonaktif",
        .globalHotkeyHint: "Pintasan Global: Cmd+Option+V untuk buka/tutup popover",
        .timeRemaining: "Sisa Waktu",
        .adapterDetails: "Adapter",
        .moveUp: "Naik",
        .moveDown: "Turun",
        .uninstallHelper: "Hapus Helper",
        .showTimeRemaining: "Tampilkan Sisa Waktu",
        .etaToEmpty: "sampai habis",
        .etaToLimit: "sampai penuh %d%%",
        .etaLimitReached: "Batas %d%% (Bypass Aktif)",
        .etaCalculating: "Menghitung sisa waktu...",
        .batteryCondition: "Kondisi",
        .conditionNormal: "Normal",
        .conditionFair: "Menurun",
        .conditionService: "Perlu Servis",
        .currentCapacity: "Saat Ini",
        .maxCapacity: "Kapasitas Maks",
        .designCapacity: "Desain",
        .capacityLoss: "Aus",
        .cycleLife: "Siklus Pakai",
        .batteryChip: "Chip Baterai",
        .underpoweredCharger: "Daya adaptor lebih kecil dari beban sistem; baterai tetap berkurang.",
        .healthTrendTitle: "Tren Kesehatan",
        .healthHistoryEmpty: "Belum ada riwayat kesehatan. Snapshot harian otomatis tersimpan di sini.",
        .daysRecordedFormat: "%d hari tercatat",
        .sailingDeltaLabel: "Delta Sailing",
        .moduleChargeControl: "Kontrol Pengisian",
        .modulePowerFlow: "Aliran Daya",
        .moduleQuickActions: "Aksi Cepat",
        .moduleCalibrationSchedule: "Kalibrasi & Jadwal",
        .moduleBatteryHealth: "Kesehatan Baterai",
        .ledSystem: "Sistem",
        .ledOff: "Mati",
        .ledGreen: "Hijau",
        .ledAmber: "Amber",
        .ledSyncWithLimit: "Sinkron",
        .alertLowBatteryTitle: "Baterai Lemah",
        .alertLowBatteryBody: "Baterai di bawah 20%. Segera hubungkan pengisi daya.",
        .alertLimitReachedTitle: "Batas Pengisian Tercapai",
        .alertLimitReachedBody: "Baterai sudah mencapai batas target pengisian.",
        .customProfileTitle: "Profil Kustom",
        .customProfileEmpty: "Simpan batas, delta sailing, dan batas suhu saat ini sebagai profil kustom.",
        .saveCustomProfile: "Simpan Saat Ini",
        .applyCustomProfile: "Terapkan Kustom",
        .settingsBackupTitle: "Cadangan & Reset Pengaturan",
        .exportSettings: "Salin JSON Pengaturan",
        .importSettings: "Tempel JSON Pengaturan",
        .resetSettings: "Reset ke Default",
        .settingsSavedFeedback: "JSON pengaturan disalin ke clipboard.",
        .settingsResetFeedback: "Pengaturan dikembalikan ke bawaan.",
        .settingsImportError: "Clipboard tidak berisi JSON VoltGuard yang valid.",
        .calStageChargingTitle: "1. Mengisi ke 100%",
        .calStageChargingDesc: "Mengisi baterai sampai penuh sebelum tahap tahan.",
        .calStageHoldingFullTitle: "2. Menahan di 100%",
        .calStageHoldingFullDesc: "Menahan penuh agar tegangan sel baterai stabil.",
        .calStageDischargingTitle: "3. Mengosongkan ke 15%",
        .calStageDischargingDesc: "Pengosongan terkontrol untuk kalibrasi batas bawah.",
        .calStageHoldingLowTitle: "4. Menahan di 15%",
        .calStageHoldingLowDesc: "Istirahat di daya rendah agar sensor baterai reset.",
        .calStageRestoringTitle: "5. Memulihkan Batas",
        .calStageRestoringDesc: "Mengisi kembali sesuai batas pengisian tersimpan.",
        .calStageCompletedTitle: "Kalibrasi Selesai",
        .calNeedsCharger: "Hubungkan adaptor daya untuk menjalankan kalibrasi baterai.",
        .calNeedsHelper: "Pasang Helper SMC di Sistem & Panduan agar pengosongan terkontrol aktif.",
        .scheduleRulePlaceholder: "Nama jadwal",
        .scheduleSetLimit80: "Atur Batas 80%",
        .scheduleTopUp100: "Isi Penuh 100%",
        .scheduleEnableDischarge: "Aktifkan Pengosongan",
        .scheduleDisableDischarge: "Matikan Pengosongan",
        .activityLogTitle: "Log Aktivitas",
        .activityLogEmpty: "Belum ada peristiwa daya tercatat di sesi ini.",
        .activityHeatPaused: "Pengisian dijeda oleh pelindung panas",
        .activityLimitReached: "Batas pengisian tercapai",
        .activityTopUpDone: "Isi Penuh 100% selesai, batas dipulihkan",
        .activityCalibrationDone: "Siklus kalibrasi baterai selesai",
        .activityLowBattery: "Baterai turun di bawah 20%",
        .presetObsidianSlate: "Obsidian",
        .presetPaperLight: "Terang",
        .presetNordicMist: "Nordic Mist",
        .presetMidnightAmber: "Midnight",
        .workspaceBackgroundTitle: "Latar Belakang",
        .bgSolidTheme: "Tema Solid",
        .bgCustomImage: "Gambar Kustom",
        .bgChooseImage: "Pilih Gambar...",
        .bgNoImageSelected: "Belum ada gambar",
        .bgScrimOpacity: "Opasitas Scrim",
        .bgBlur: "Blur",
        .iconStyleShield: "Perisai Baterai",
        .iconStyleRing: "Cincin Meter",
        .iconStylePill: "Kapsul Persen",
        .iconStyleBolt: "Petir Minimal",
        .densityDetailed: "Detail",
        .densityCompact: "Ringkas",
        .calPurposeTitle: "Tujuan & Estimasi Durasi",
        .calPurposeBody: "Membatasi baterai di 60%-80% memperlambat penuaan kimia, namun seiring waktu pembacaan chip sensor (bq40z651) dapat bergeser. Siklus penuh 100% -> 15% -> Batas memulihkan titik acuan tegangan atas dan bawah agar persentase serta Kapasitas Maksimum akurat. Cukup jalankan 1-3 bulan sekali.",
        .calStage1Duration: "~30-90 mnt",
        .calStage2Duration: "Tahan 60 mnt",
        .calStage3Duration: "~1-3 jam",
        .calStage4Duration: "Tahan 60 mnt",
        .calStage5Duration: "~30-60 mnt",
        .calTotalDurationBadge: "Total: ~3,5 - 6 Jam",
        .bypassActiveBadge: "Bypass Aktif",
        .bypassFlowSubtitle: "Daya langsung Adaptor -> Mac (Baterai di-bypass 0 W)",
        .bypassCardTitle: "Bypass Charging Otomatis Saat Batas Tercapai",
        .bypassCardDesc: "Saat baterai mencapai batas target (misal 80%), VoltGuard otomatis beralih ke Bypass Charging: seluruh daya MacBook disuplai langsung dari adaptor sementara baterai beristirahat di 0.0 W.",
        .dischargeDesc: "Gunakan daya baterai meskipun adaptor charger tetap terpasang.",
        .autoDischargeDesc: "Kuras baterai otomatis ke batas target saat tercolok di atas batas.",
        .clamshellDischargeDesc: "Izinkan pengosongan baterai saat layar MacBook tertutup.",
        .topUpDesc: "Isi penuh ke 100% satu kali sebelum bepergian, lalu pulihkan batas harian.",
        .sailingModeDesc: "Biarkan baterai turun beberapa persen sebelum isi ulang untuk cegah siklus pendek.",
        .heatProtectionDesc: "Jeda pengisian otomatis saat suhu baterai melewati batas aman.",
        .sleepControlDesc: "Cegah macOS tidur saat pengosongan baterai atau kalibrasi sedang berjalan.",
        .stopChargingOnSleepDesc: "Hentikan pengisian daya baterai setiap kali Mac masuk mode tidur.",
        .lowPowerOnBatteryDesc: "Aktifkan Mode Hemat Daya macOS otomatis saat menggunakan baterai.",
        .lowPowerAlwaysDesc: "Pertahankan Mode Hemat Daya macOS baik di baterai maupun adaptor.",
        .magSafeSyncLegend: "Mode Sinkron: Mengisi = Amber  |  Batas Tercapai (Bypass) = Hijau  |  Discharge = LED Mati"
    ]
}

public enum BatteryETAFormatter {
    public static func text(for eta: BatteryETA?, locale: AppLocale) -> String? {
        guard let eta else { return nil }
        switch eta.kind {
        case .steady:
            return String(format: L10n.text(.etaLimitReached, locale: locale), eta.targetPercent)
        case .toEmpty:
            guard let mins = eta.minutes else {
                return L10n.text(.etaCalculating, locale: locale)
            }
            return "\(formatDuration(mins, locale: locale)) \(L10n.text(.etaToEmpty, locale: locale))"
        case .toTargetLimit:
            guard let mins = eta.minutes else {
                return L10n.text(.etaCalculating, locale: locale)
            }
            let suffix = String(format: L10n.text(.etaToLimit, locale: locale), eta.targetPercent)
            return "\(formatDuration(mins, locale: locale)) \(suffix)"
        }
    }

    public static func formatDuration(_ mins: Int, locale: AppLocale) -> String {
        let hourUnit = locale == .id ? "j" : "h"
        if mins >= 60 {
            return "\(mins / 60)\(hourUnit) \(String(format: "%02d", mins % 60))m"
        }
        return "\(mins)m"
    }
}
