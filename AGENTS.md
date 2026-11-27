# AGENTS.md

## Project Overview
This project is a native macOS desktop application with a modern full GUI (SwiftUI) and a dynamic top menu bar status item (`AppKit` `NSStatusItem`) built for **Hackintosh** environments.

Key capabilities:
1. **EFI & ACPI Inspection:** Reads ACPI files (`.aml`, `.dsl`, etc.) from a user-selected or auto-detected EFI folder (such as `EFI/OC/ACPI`), indexes tables/devices/methods related to battery, Embedded Controller (EC), thermal zones, and fans, and reports what is detectable vs. writable at runtime on macOS.
2. **Charge Threshold Control:** Provides UI controls to view and configure battery charge start/stop thresholds safely, using available macOS/Hackintosh interfaces (such as SMC / YogaSMC / exposed ACPI/EC interfaces) with explicit fallback and clear diagnostics when direct ACPI EC writes are restricted by macOS/firmware.
3. **Dynamic Menu Bar Telemetry:**
   - Uses `menu_bar.png` for the compact top menu bar icon.
   - **When charger is connected (AC power):** Displays **Voltage (`V`)**, **Amperage (`A`)**, and **Wattage (`W`)** in the menu bar.
   - **When charger is disconnected (Battery power):** Displays **CPU usage (`%`)**, **RAM usage (`%`)**, **Fan speed (`RPM`)**, and **Temperature (`°C`)** in the menu bar.
4. **App Identity & Assets:** Uses `icon.png` as the application icon and branding asset.

## Tech Stack & Conventions
- **Language & Frameworks:** Swift, SwiftUI (Full GUI), AppKit (`NSStatusItem`, `NSPopover`, `NSWorkspace`, `NSOpenPanel`).
- **Architecture:** Separate UI views, telemetry collectors, ACPI/EFI parsers/scanners, and power/threshold controllers into clean, decoupled modules/services (e.g., `Models/`, `Services/ACPI/`, `Services/Telemetry/`, `Services/Threshold/`, `Views/`).
- **Formatting & Units:**
  - Voltage: `V` (e.g., `19.5V` or `12.4V`)
  - Amperage: `A` (e.g., `2.15A` or `-1.40A`)
  - Wattage: `W` (e.g., `41.9W` or `17.4W`)
  - CPU & RAM: integer or 1-decimal `%` (keep menu bar string compact so it never truncates or crowds the notch/menu bar)
  - Fan: `RPM` (e.g., `2400 RPM`)
  - Temperature: `°C` (e.g., `52°C`)

## Rules & Guardrails for Agents
1. **Never Hardcode Fake Telemetry as Real Data:** Clearly label mock/preview/unavailable sensors when a real sensor or ACPI write path is not present on the current machine. Never silently pretend a threshold write succeeded if the underlying interface returned an error or is unsupported.
2. **Respect EFI & System Safety:** Treat the EFI folder as read-first during inspection. Do not modify or overwrite user `.aml`/`.dsl` EFI files unless explicitly requested by the user.
3. **Handle Missing Assets Gracefully:** Check the workspace for `icon.png` and `menu_bar.png`. If either file is missing or in a subfolder, locate it cleanly and avoid crashing if an asset path changes.
4. **Keep Menu Bar Text Concise:** Menu bar strings update periodically; avoid heavy synchronous work or main-thread blocking inside timer callbacks. Keep formatting crisp so AC mode (`V A W`) and Battery mode (`CPU% RAM% RPM °C`) stay readable.
5. **Explain Assumptions & Limitations:** Hackintosh ACPI EC layouts vary by OEM and DSDT/SSDT patches. Document any assumptions about ACPI paths, SMC keys, or privileges clearly in code comments and responses.

## Working Style
- Inspect existing files and assets in the repository before making edits.
- Keep changes modular, idiomatic, and well-structured.
- Summarize what was implemented, how EFI/ACPI scanning and threshold control behave, and how to build/run or test the app.
