# Development

puipui is a Swift package with an AppKit window shell, a SwiftUI dashboard, and an embedded Ghostty terminal. The build script assembles the executable and SwiftPM resource bundles into a signed `.app`.

## Source layout

| File or directory | Responsibility |
| --- | --- |
| `Sources/Puipui/main.swift` | Menu bar item, anchored and detached windows, terminal drawer, login-item registration, and runtime checks. |
| `Sources/Puipui/Dashboard.swift` | Metric readings, scan state, controls, and the scan-details popover. |
| `Sources/Puipui/MetricChart.swift` | Timestamp-based charts over a 300-second window. |
| `Sources/Puipui/Metrics.swift` | System sampling, history, memory-pressure events, and scan scheduling. |
| `Sources/Puipui/MoleScanner.swift` | Executable discovery, version checks, dry-run execution, and preview validation. |
| `Sources/Puipui/TerminalSession.swift`, `Sources/TerminalPTY/` | Terminal session lifecycle and PTY integration. |
| `Resources/` | App metadata, icon artwork, and design studies. |

The Swift package and module retain the internal name `Puipui`; the app bundle, executable inside it, and user-facing name are `puipui`.

## Metric and scan contracts

CPU percentages come from interval deltas of Mach CPU ticks. User includes nice time. User and System form a stacked graph on a fixed 0–100% axis. The first sample and counter resets produce missing readings, not zeroes.

The memory area chart shows usage derived from VM statistics. The Pressure label reports OS memory-pressure events; it is not the plotted value. Network rates come from counter deltas on the primary interface. Receive is above zero and send below it, with a shared scale derived from visible samples. The charts leave gaps when data is missing or samples are more than three seconds apart.

The scanner runs only `mo clean --dry-run`. It requires a successful process exit and a fresh regular preview file owned by the current user, with no group or world write permission. Unrecognized rows and unmeasured candidates invalidate the estimate. In Mole 1.59 previews, rows marked `counted under` are excluded because their parent already includes them. Sizes use Mole's decimal units.

The scanner currently accepts Mole 1.53.x and 1.59.x. To support another version, inspect its dry-run behavior and preview format before changing the version gate. Keep executable-fixture tests for rejected versions and parser tests for accounting changes.

## Verification

Run the regression tests with the selected Xcode toolchain:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
```

After building with `sh scripts/build-app.sh`, run the checks appropriate to the change:

```sh
build/puipui.app/Contents/MacOS/puipui --check-window
build/puipui.app/Contents/MacOS/puipui --check-metrics
build/puipui.app/Contents/MacOS/puipui --check-storage
build/puipui.app/Contents/MacOS/puipui --check-terminal
```

These checks need a logged-in macOS desktop session. The window check exercises detachment, reopening, and popover dismissal. The metrics check samples the real machine. The storage check inspects capacity, Mole compatibility, and an existing preview; it does not run a new scan. The terminal check starts a shell and verifies input and cleanup.

The terminal check's `drawerUnfolding` assertion samples an animation at a fixed delay and can fail under scheduling load. Inspect the other assertions and the actual animation before treating that result as a terminal regression.

Run a real scan separately when changing Mole integration:

```sh
build/puipui.app/Contents/MacOS/puipui --check-scan
```

This updates Mole's preview and operation logs. It does not delete cleanup candidates. Check for `scan=true` and a successful exit status.

## Screenshots and artwork

The README dashboard image was captured from the installed app on 2026-10-15, and the terminal view on 2026-10-16. Both show actual app windows; the terminal image omits unused space below the windows. To capture development windows through the built-in renderer:

```sh
build/puipui.app/Contents/MacOS/puipui --check-window --render-window
```

This writes `build/window-anchored.png`, `build/scan-details.png`, and `build/window-preview.png`. It starts a fresh app session, so the history is short and the startup scan may still be running. Inspect images before publishing them.

`Resources/AppIcon.svg` is the application artwork; `Resources/AppIcon.icns` contains the macOS raster sizes. The menu bar uses `Sources/Puipui/Resources/Icons/app-mark.pdf`, a vector conversion of the selected [24px symbol](../Resources/AppIconConcepts/guinea-pig-c.svg). Render that PDF at 18pt as an `NSImage` template so macOS supplies the foreground color.

The three interface glyphs have separate [Lucide provenance and license notes](../Sources/Puipui/Resources/Icons/README.md).
