# VoltGuard

Native macOS menu bar battery and power management utility built with Swift, SwiftUI, AppKit, Clean Architecture, VIPER, and Unidirectional State Management.

## Features

1. **Charge Limiter**: Set a target charge cap from 20% to 100% with quick presets (60%, 80%, 90%, 100%).
2. **Discharge**: Force battery discharge while connected to AC power.
3. **Automatic Discharge**: Automatically discharge when current charge exceeds `limit + 2%`.
4. **Discharge in Clamshell Mode**: Allow controlled discharge with the MacBook lid closed.
5. **Heat Protection**: Pause charging above a configurable temperature threshold (default 35 C) with a 2 C hysteresis band.
6. **Sailing Mode**: Allow battery level to drift down by a configurable delta before resuming charge.
7. **Control MagSafe LED**: System, Off, Green, Amber, or Sync with Limit.
8. **Top Up**: Temporarily charge to 100% and automatically revert to your saved limit.
9. **Calibration Mode**: Guided 4-stage calibration cycle (charge to 100%, hold, discharge to 15%, hold, restore limit).
10. **Schedule**: Weekday and time-based automation rules for Top Up, 80% limit, and Discharge.
11. **Sleep Control**: Prevent system sleep during active Discharge or Calibration.
12. **Stop Charging when Sleeping**: Inhibit charging when macOS enters sleep.
13. **Low Power Mode Control**: Automatically toggle macOS Low Power Mode on battery or always.
14. **Apple Shortcuts Support**: `AppIntents` for Set Charge Limit, Toggle Discharge, Top Up 100%, and Get Battery Telemetry.
15. **Customizable Menu Bar Icons**: 4 icon styles with optional percentage, live wattage, and temperature badges.
16. **Customizable Popover**: Reorder or hide modules and switch between Detailed and Compact density.
17. **Live Power Flow Telemetry**: Real-time Adapter Input (W), System Load (W), Battery Net (W), Voltage (V), Current (A), and 2-segment wattage-proportional energy conduit animation.
18. **Theme Editor, Custom Background & Localization**: 4 WCAG AA verified theme presets (`Obsidian`, `Paper Light`, `Nordic Mist`, `Midnight`) with visual mini-window swatches, Custom Image Background (`Solid Theme` vs `Custom Image` with `Scrim Opacity` and `Blur`), custom accent color, corner radius, surface opacity, and instant English / Bahasa Indonesia switching.
19. **Stabilized Time-Aware Battery ETA**: Smooth time-to-empty and time-to-limit estimates powered by a 60s time-aware EMA, `AppleRawCurrentCapacity` coulomb readings, and hysteresis rate limiting.
20. **Detailed Battery Diagnostics & Health Trend**: Apple Silicon `BatteryData` nominal/raw/design capacity (`mAh`), capacity wear, cycle count, condition badge (`Normal`, `Fair`, `Service Recommended`), daily health trend chart, custom profile preset, JSON settings backup/reset, and session activity log.

## Architecture

- **`VoltGuardDomain`**: Pure Swift entities, gateway protocols, and use cases (`EvaluateChargePolicyUseCase`, `CalibrationMachineUseCase`, `ScheduleEvaluatorUseCase`, `PowerFlowCalculator`).
- **`VoltGuardData`**: `IOKitBatteryReader`, `DualModeSMCGateway` (privileged daemon + safe read-only fallback), `SystemPowerGateway`, and `JSONSettingsRepository`.
- **`VoltGuardApp`**: VIPER presentation (`VoltGuardInteractor`, `VoltGuardPresenter`, `VoltGuardAppDelegate` router, SwiftUI views, `AppIntents`).
- **`VoltGuardHelper`**: Privileged `AppleSMC` daemon (`voltguard-helper`) communicating over `/var/run/voltguard-helper.sock`.

## Panduan Singkat (Bahasa Indonesia)

1. Buka **VoltGuard** dari menu bar kanan atas (sejajar ikon baterai).
2. Atur **Batas Pengisian** (misal 80%) untuk menjaga umur baterai saat laptop sering terhubung ke charger.
3. Aktifkan **Pelindung Panas** dan **Mode Sailing** untuk mengurangi keausan sel baterai.
4. Gunakan **Isi Penuh 100% (Top Up)** sebelum bepergian; batas akan kembali ke 80% secara otomatis setelah penuh.
5. Buka **Pengaturan > Helper SMC > Pasang Helper SMC** untuk mengaktifkan kontrol tulis perangkat keras AppleSMC (tanpa helper, aplikasi berjalan aman dalam mode baca-saja).
6. Ubah tema, warna aksen, tata letak popover, dan bahasa (**EN / ID**) langsung dari popover atau jendela Pengaturan.

## Build and Test

```bash
swift test
swift build -c release
bash scripts/package_dmg.sh
```
