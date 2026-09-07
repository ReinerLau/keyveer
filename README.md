# Keyveer

Keyveer is a personal macOS 14+ menu-bar utility for controlling the pointer with the keyboard in **自由模式** (free mode). It is intentionally local-only and has no App Sandbox.

## Build

Install [XcodeGen](https://github.com/yonaskolb/XcodeGen), make sure the local certificate `Keyveer Local Development` exists in the login keychain, and run:

```sh
./Scripts/build-and-run.sh
```

To produce the reproducible signed daily-use candidate, including the runtime
test suite, Release build, designated-requirement check, and candidate manifest:

```sh
./Scripts/candidate-build.sh
```

The build-and-run script generates the Xcode project from `project.yml`, builds with the fixed bundle identifier `com.reinerlau.keyveer`, verifies the designated requirement and Hardened Runtime, then launches the menu-bar agent. The signature/TCC smoke-test conclusion is recorded in `docs/adr/0001-use-a-fixed-local-signing-identity.md`; the interactive TCC checks are documented in the prototype branch referenced there.

Run the deterministic runtime suite with:

```sh
swift test
```

On first launch, use Request Permissions and grant Accessibility access. The menu offers Help for the current key bindings, Recheck Permissions, Open System Settings, Reload Configuration, diagnostics, and Quit.

Copy Diagnostic Summary copies only version/build identity, capability state, configuration and event-tap
status, plus aggregate callback, frame, recovery and effect counters. It does not include input,
application, window or pointer history. In Debug builds, callback latency is also aggregated without
recording individual events.

The first launch creates `~/Library/Application Support/Keyveer/config.json`. Edit only the
documented JSON fields, then choose Reload Configuration from the menu. Invalid files are rejected
without replacing the last valid runtime configuration. The interactive real-app check is
`./Scripts/configuration-smoke-test.sh`.

The optional `visual` block controls the free-mode marker and lightning trail without changing
`schemaVersion`:

For a field-by-field explanation of all bindings, movement, scrolling, and visual settings, see
[`docs/configuration.md`](docs/configuration.md).

```json
"visual": {
  "marker": {
    "coreDiameter": 7,
    "glowRadius": 9,
    "coreColor": "#FFFFFF",
    "outerGlowColor": "#008FEF",
    "outerGlowOpacity": 0.60,
    "glowStrength": 1.0
  },
  "trail": {
    "coreWidth": 3.5,
    "bendSpacingMin": 24,
    "bendSpacingMax": 36,
    "bendOffsetDistanceMin": 6,
    "bendOffsetDistanceMax": 24,
    "bendOffsetDirectionMin": -90,
    "bendOffsetDirectionMax": 90,
    "arcLengthMin": 80,
    "arcLengthMax": 180,
    "arcGapMin": 24,
    "arcGapMax": 72,
    "arcHoldMin": 0.20,
    "arcHoldMax": 0.50,
    "blurRadius": 16,
    "coreColor": "#FFFFFF",
    "outerGlowColor": "#008FEF",
    "outerGlowOpacity": 1.0,
    "glowStrength": 1.0
  }
}
```

All visual fields are optional and use the values above when omitted. `bendSpacingMin` and
`bendSpacingMax` define the random distance range between major bends in points: larger values make
the lightning less dense, smaller values make it more angular. Trail bend offset distances are in
points; direction limits are relative to the current path direction (0° forward, positive angles
turn left, negative angles turn right, 180° backward) and are expressed in degrees. The marker and trail outer
glows use Gaussian blur controlled by `glowRadius` and `blurRadius`. Colors use `#RRGGBB`;
numeric limits are validated during reload.

A continuous movement grows one complete lightning trunk from its exact starting point to the
marker. The trunk has no artificial length limit and stays fully visible until movement stops.
During keyboard movement, the default and precision-slow speed hide the prominent trunk while
retaining the subtle companion arc; holding any configured fast-speed key shows the trunk again.
Physical mouse movement is not gated by these keyboard speed keys.
For keyboard movement, releasing the final movement key triggers dissipation immediately; physical
pointer-only movement retains the brief stationary timeout fallback.
It then remains fixed and opaque while independently timed sections shrink and break apart in
place for 0.45 seconds. The effect has no directional wipe, full-width branches, or flying sparks;
its companion arcs are independent thin polylines. Each arc grows to its own randomized length,
then remains for its own randomized hold time before disappearing. New arcs are generated at
random path-distance gaps, and there is no simultaneous-count limit. Companion arcs can remain
visible after the trunk has dissipated.

For lock-screen, sleep, permission-loss, and event-tap recovery checks, run
`./Scripts/recovery-smoke-test.sh`. These cases require system interaction and are recorded as an
operator checklist; after each fault, free mode must remain off until explicitly re-enabled.

The complete Issue #11 feature, performance, and seven-day operator record is
`docs/candidate-acceptance.md`. After building a candidate, measure its idle,
continuous-movement CPU, and resident memory budgets with:

```sh
./Scripts/performance-smoke-test.sh build/candidate/Build/Products/Release/Keyveer.app
```

Callback latency is checked from a Debug diagnostic summary with
`./Scripts/diagnostic-budget-check.sh`; the Release candidate's fixed identity
and TCC prerequisites are checked by `candidate-build.sh` and `tcc-smoke-test.sh`.
