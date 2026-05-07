# Cluster 3.5 — Visual Calm-Cinema redo (P1, pre-launch polish)

> **For the executing agent:** This is the **upgraded v2** of the Cluster 3 visual redo. v1 is replaced wholesale. Codex's original Cluster 3 microcopy + onboarding cards + simplified preset picker (PR #14, `d5c108d`) **stays** — this layers an opinionated visual identity on top.
>
> Sibling specs in this folder: `1-cluster-2.5-stitch-hotfix.md` (P0 hotfix — must merge first) and `3-cluster-6-snap-mode-multicam.md` (P2 capture-mode feature). Branch off the latest `main` *after* Cluster 2.5 merges. Do not stack PRs.
>
> Walk this with `superpowers:subagent-driven-development` or `superpowers:executing-plans`. TDD red-green-commit per task.

## Goal

Replace the generic "iOS demo app" look with a **Calm Glass + Cinematic Accent** identity that reinforces the user's brand: privacy-first, anti-cloud, on-device, premium. Reference moods: Apple Health, Apple Wallet, Dark Noise, Linear, Tesla in-car UI. Anti-references: Duolingo, Notion, generic SaaS.

The user already chose a B+C blend (Calm Glass foundation + Cinematic empty states) over Brutalist or pure-Cinematic. Do not relitigate. Every decision in this spec is final unless empirical evidence (a build failure, a verified accessibility fail) forces a change — in which case log the deviation in `AI-CHAT-LOG.md` before deviating.

## Branch + tech

- Branch `feat/cluster-3.5-visual-calm-cinema` off `main` after `1-cluster-2.5-stitch-hotfix.md` lands.
- Swift 5.9, SwiftUI, deployment target **iOS 18.0**. Project: `VideoCompressor/VideoCompressor_iOS.xcodeproj`. Scheme `VideoCompressor_iOS`. Default sim: **iPhone 16 Pro**.
- iOS 26 APIs (`.glassEffect()`, advanced `.symbolEffect`) used only behind `#available(iOS 26, *)` gates with `.thickMaterial` fallbacks. Project's older devices (iPhone XS / A12) target iOS 18.
- No new SPM packages. No CoreHaptics. No `AVVideoCompositing`. No edits to `.github/workflows/testflight.yml` or `PRODUCT_BUNDLE_IDENTIFIER` (per AGENTS.md Part 14 + the App identity DO-NOT-RENAME banner).

## Design principles

1. **Calm over loud.** Saturation is HIG-aligned, never neon. Where v1 reached for electric-magenta + electric-cyan as mesh accent points, we use desaturated iris + low-luminance teal so the aurora reads as *quiet light*, not *arcade*.
2. **Per-tab tint identity.** Each of 4 tabs has a distinct accent that survives both light and dark schemes. The user can identify the tab by color alone, but the colors don't fight content.
3. **Materials over fills.** `.thickMaterial` / `.regularMaterial` cards. Lists go `.scrollContentBackground(.hidden)` over a tinted container. Solid `Color` fills only for the empty-state aurora canvas backdrop and for hardware-pinned chrome where materials would fail.
4. **One cinematic surface per tab.** The empty state. Not the populated state. Once the user has content, the chrome recedes.
5. **Restrained motion.** Aurora drift period 14–18s, 30Hz. Scroll transitions ≤ 0.30s `.smooth`. Symbol bounces ≤ 0.40s. No bouncy springs over 0.4s. Absolutely no jiggle.
6. **Reduce Motion is honored.** When `\.accessibilityReduceMotion` is true, MeshGradient stops animating (static midpoint frame). Symbol effects degrade to static.
7. **WCAG AA on materials.** Tints used as text foreground must hit ≥ 4.5:1 against `.thickMaterial` in both schemes. Where they don't, use `.foregroundStyle(.primary)` for text and reserve the tint for SF Symbol palette layers, capsule fills, and stroke accents.
8. **Theme is one-file changeable.** All color values live in `Theme.swift`. Outside that file, accents are referenced as `AppTint.compress(scheme)`, never as raw `Color(red:green:blue:)`.

## Per-tab visual mood (memorize before touching code)

**Compress.** Quiet, focused, almost clinical — this is the *workhorse* tab where users grind through batches before sharing. Iris-violet tint reads as "something tasteful is happening to your media." Empty state aurora drifts slowly behind a single 96pt `wand.and.stars` symbol that pulses once every 4 seconds. Populated state is a 2-column card grid where each card feels like a slim film canister: 16:9 thumbnail on top, monospaced metadata pills below, save-state `GaugePill` bottom-right. The mood echoes how Apple Photos shows your library — just slightly more confident in its own identity.

**Stitch.** Editorial, cinematic, the most "creative" tab. Mint-teal tint at low saturation evokes color-grading panels, not minty-fresh. The horizontal timeline becomes the hero — clip blocks have a darker glass treatment than the rest of the chrome. Drop indicators glow with a 6pt mint capsule that grows from 2pt with a 0.18s `.smooth` ease. The `Stitch & Export` action stays a floating Liquid-Glass capsule (iOS 26) / `.thickMaterial` capsule (iOS 18), centered above the home indicator. Empty state aurora favors the cooler half of the gradient — this tab feels at home in dark mode.

**MetaClean.** Privacy, surgical, slightly serious. Indigo tint — the one that explicitly nods at the "AI Glasses Data" working title. Reading state shows a slow horizontal `Shimmer` sweeping over each row's leading icon, communicating *we're inspecting this carefully*. Strip-complete cards bloom in with `.transition(.scale.combined(with: .opacity))` over 0.28s. The Clean All CTA, when armed for `Replace originals`, gets a subtle red-tinted pulse on the symbol only (never on the whole button) so destructive intent is communicated without drama.

**Settings.** Reserved, near-monochrome graphite tint. This is the *not the show* tab — it must look like it belongs to iOS, not to the app. Form sections sit on `.thinMaterial`. Section headers are caps-small with letter-spacing +0.4. No aurora here — the only accent is the per-row tint of icons that point back to other tabs (Compress row icon tinted iris, etc.) so users feel the cross-link visually.

## Color tokens (canonical — `Theme.swift`)

All colors below are final. **Do not invent new ones; do not pull from v1's palette.** Every tint has explicit light + dark variants.

```swift
import SwiftUI

// MARK: - AppTint
//
// Per-tab accent. Resolve via `AppTint.compress(scheme)` so dark variants
// always get applied. NEVER reference *Light or *Dark directly outside this file.
//
// Light values target ≥ 4.5:1 against .thickMaterial in light mode when used as
// solid foreground text/icon. Dark values target ≥ 4.5:1 against
// .thickMaterial in dark mode. Verified with WCAG OKLCH heuristic before
// shipping (see "Accessibility" below).

enum AppTint {
    // Compress — muted iris violet
    static let compressLight = Color(red: 0.42, green: 0.30, blue: 0.78)  // #6B4DC7
    static let compressDark  = Color(red: 0.66, green: 0.55, blue: 0.95)  // #A88CF2

    // Stitch — desaturated mint-teal (color-grade panel)
    static let stitchLight = Color(red: 0.18, green: 0.50, blue: 0.46)    // #2E8076
    static let stitchDark  = Color(red: 0.42, green: 0.78, blue: 0.70)    // #6BC7B3

    // MetaClean — deep indigo with a hint of cool
    static let metaCleanLight = Color(red: 0.24, green: 0.31, blue: 0.66) // #3D4FA8
    static let metaCleanDark  = Color(red: 0.52, green: 0.60, blue: 0.92) // #8599EB

    // Settings — graphite, near-monochrome
    static let settingsLight = Color(red: 0.36, green: 0.40, blue: 0.45)  // #5C6673
    static let settingsDark  = Color(red: 0.62, green: 0.66, blue: 0.72)  // #9EA8B8

    static func compress(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? compressDark : compressLight
    }
    static func stitch(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? stitchDark : stitchLight
    }
    static func metaClean(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? metaCleanDark : metaCleanLight
    }
    static func settings(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? settingsDark : settingsLight
    }
}

// MARK: - AppMesh
//
// Mesh-gradient aurora palettes for empty states. 9-color 3x3 grid.
// Corners pinned to a low-luminance backdrop; midpoints carry the tint;
// ONE off-axis bloom point carries a warm secondary at low alpha.
// This is the "cinematic spark" — quiet, never neon.

enum AppMesh {
    /// Backdrop — same in all tabs, scheme-dependent. Acts as the canvas.
    static func backdrop(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.05, green: 0.06, blue: 0.09)   // near-black w/ blue cast
            : Color(red: 0.96, green: 0.96, blue: 0.97)   // near-white w/ cool cast
    }

    /// Single bloom accent — warm low-luminance amber. Appears at one
    /// off-axis point per tab, NEVER as a corner.
    static func bloom(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.85, green: 0.55, blue: 0.32).opacity(0.28)  // muted amber
            : Color(red: 0.78, green: 0.50, blue: 0.30).opacity(0.18)
    }

    /// Returns the 9 colors for a 3x3 MeshGradient given a tab tint and scheme.
    /// Layout (row-major):
    ///   bd  tnt(.35)  bd
    ///   tnt(.30)  bd  bloom
    ///   bd  tnt(.25)  bd
    static func palette(tint: Color, scheme: ColorScheme) -> [Color] {
        let bd = backdrop(scheme)
        let bloom = bloom(scheme)
        return [
            bd,                tint.opacity(0.35), bd,
            tint.opacity(0.30), bd,                bloom,
            bd,                tint.opacity(0.25), bd,
        ]
    }
}

// MARK: - AppShape
//
// Corner radii, spacing, stroke widths. Centralized so future adjustments
// are one-line.

enum AppShape {
    static let radiusS: CGFloat = 8
    static let radiusM: CGFloat = 12
    static let radiusL: CGFloat = 20

    static let strokeHairline: CGFloat = 0.5
    static let strokeBorder: CGFloat   = 1.0

    static let cardPaddingH: CGFloat = 14
    static let cardPaddingV: CGFloat = 12

    static let auroraDriftPeriodSeconds: Double = 16   // 14–18s window, midpoint
    static let auroraFrameRate: Double           = 30
    static let scrollTransitionDuration: Double  = 0.30
    static let symbolBounceDuration: Double      = 0.35
}
```

### Tint usage matrix

| Surface | Foreground style | Notes |
|---|---|---|
| Body text, headlines, navigation titles | `.foregroundStyle(.primary)` | Never tinted directly. |
| Secondary text, captions | `.foregroundStyle(.secondary)` | iOS handles material contrast here. |
| Active SF Symbols (toolbar add buttons, save-state checkmarks) | `.foregroundStyle(AppTint.X(scheme))` | Single-color rendering mode, contrast verified. |
| Multi-layer SF Symbols (e.g. `wand.and.stars` in empty state) | `.symbolRenderingMode(.palette)` + `.foregroundStyle(AppTint.X(scheme), .secondary)` | Tint on primary layer only. |
| Selection rings, drop indicators, capsule fills | Tint at 1.0 alpha | Decorative; not text — AA does not apply. |
| Card backgrounds | `.thickMaterial` | Never tinted. Tint shows through subtle 6% overlay if needed. |

## Component blueprints (`VideoCompressor/ios/Theme/*`)

Compileable skeletons. Codex pastes and adapts; do not introduce new dependencies, do not move them outside `Theme/`.

### `MeshAuroraView.swift`

```swift
import SwiftUI

/// Animated 3x3 mesh-gradient aurora used as the empty-state backdrop on
/// every tab. Drifts 2 of 9 mesh points by ±0.05 over a 16s sin/cos cycle
/// at 30Hz. Corners pinned. Reduce-motion → static frame. A12/A13 devices
/// (and any < 90Hz display) → `LinearAuroraView` fallback to keep frame budget.
struct MeshAuroraView: View {
    let tint: Color   // already resolved via AppTint.X(scheme) by the caller
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if AuroraBackend.preferred == .mesh {
                meshBody
            } else {
                LinearAuroraView(tint: tint)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var meshBody: some View {
        if #available(iOS 18.0, *) {
            TimelineView(.animation(minimumInterval: 1.0 / AppShape.auroraFrameRate, paused: reduceMotion)) { ctx in
                let t = reduceMotion
                    ? 0
                    : ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: AppShape.auroraDriftPeriodSeconds)
                        / AppShape.auroraDriftPeriodSeconds
                let phase = CGFloat(t) * 2 * .pi
                MeshGradient(
                    width: 3, height: 3,
                    points: meshPoints(phase: phase),
                    colors: AppMesh.palette(tint: tint, scheme: scheme)
                )
            }
        } else {
            // iOS 18 base SDK ships MeshGradient already — this branch is
            // belt-and-suspenders for some future toolchain matrix shift.
            LinearAuroraView(tint: tint)
        }
    }

    /// Animate ONLY index 1 (top-mid) and index 5 (mid-right bloom) by ±0.05.
    /// Corners (0,2,6,8) and the midpoint center (4) stay pinned.
    private func meshPoints(phase: CGFloat) -> [SIMD2<Float>] {
        let dx = Float(cos(phase) * 0.05)
        let dy = Float(sin(phase) * 0.05)
        return [
            SIMD2(0.0,       0.0),
            SIMD2(0.5 + dx,  0.0 + dy),    // animated
            SIMD2(1.0,       0.0),
            SIMD2(0.0,       0.5),
            SIMD2(0.5,       0.5),
            SIMD2(1.0 + dx,  0.5 + dy),    // animated bloom point
            SIMD2(0.0,       1.0),
            SIMD2(0.5,       1.0),
            SIMD2(1.0,       1.0),
        ]
    }
}

/// Dirt-cheap fallback for older silicon — animated `LinearGradient` over
/// the same backdrop+tint. ~1% GPU on A12 vs ~7% for animated MeshGradient.
struct LinearAuroraView: View {
    let tint: Color
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            AppMesh.backdrop(scheme).ignoresSafeArea()
            if reduceMotion {
                LinearGradient(
                    colors: [tint.opacity(0.30), .clear],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { ctx in
                    let t = ctx.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: AppShape.auroraDriftPeriodSeconds)
                        / AppShape.auroraDriftPeriodSeconds
                    let p = CGFloat(t) * 2 * .pi
                    LinearGradient(
                        colors: [tint.opacity(0.32), AppMesh.bloom(scheme), .clear],
                        startPoint: UnitPoint(x: 0.5 + 0.2 * cos(p), y: 0.5 + 0.2 * sin(p)),
                        endPoint:   UnitPoint(x: 0.5 - 0.2 * cos(p), y: 0.5 - 0.2 * sin(p))
                    )
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// Heuristic device class. Anything ≥ 90Hz display = ProMotion = A14+ = mesh OK.
/// Everything else uses the linear fallback.
enum AuroraBackend {
    case mesh, linearAnimated

    static var preferred: AuroraBackend {
        // ProMotion-capable phones (iPhone 13 Pro+) have A15+ silicon.
        // iPhone XS / 11 / 12 / SE3 cap at 60Hz; they get the linear path.
        let maxFPS = await MainActor.run { UIScreen.main.maximumFramesPerSecond }
        return maxFPS >= 90 ? .mesh : .linearAnimated
    }
}
```

> **Note on `AuroraBackend.preferred`:** The `await MainActor.run` above is illustrative — Codex should resolve it via a non-async cached static computed once at app launch (e.g. `static let preferred: AuroraBackend = { ... }()` reading `UIScreen.main.maximumFramesPerSecond` synchronously on main thread). Don't make this async; it's read in `body`.

### `CardStyle.swift`

```swift
import SwiftUI

struct CardStyle: ViewModifier {
    let tint: Color   // resolved by caller
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, AppShape.cardPaddingH)
            .padding(.vertical, AppShape.cardPaddingV)
            .background(.thickMaterial, in: RoundedRectangle(cornerRadius: AppShape.radiusM))
            .overlay(
                RoundedRectangle(cornerRadius: AppShape.radiusM)
                    .strokeBorder(
                        tint.opacity(scheme == .dark ? 0.18 : 0.10),
                        lineWidth: AppShape.strokeHairline
                    )
            )
            .shadow(
                color: .black.opacity(scheme == .dark ? 0.40 : 0.06),
                radius: 6, x: 0, y: 2
            )
    }
}

extension View {
    /// Apply the shared card chrome with a per-tab tint accent on the border.
    func cardStyle(tint: Color) -> some View {
        modifier(CardStyle(tint: tint))
    }
}
```

### `Shimmer.swift`

```swift
import SwiftUI

/// A slow horizontal shimmer used to indicate "we're inspecting this".
/// MetaClean uses this on the row icon while metadata is being read.
/// Reduce-motion fallback: static gradient at midpoint.
struct Shimmer: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .overlay(
                LinearGradient(
                    colors: [.white.opacity(0.0), .white.opacity(0.45), .white.opacity(0.0)],
                    startPoint: .leading, endPoint: .trailing
                )
                .rotationEffect(.degrees(20))
                .offset(x: phase)
                .blendMode(.plusLighter)
                .mask(content)
            )
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 220
                }
            }
    }
}

extension View {
    func shimmer() -> some View { modifier(Shimmer()) }
}
```

### `GaugePill.swift`

Replaces the ad-hoc `ProgressView() / Image` pair in `VideoRowView.saveButton`. One pill, three states (saving / saved / failed), 28pt height.

```swift
import SwiftUI

enum GaugePillState: Equatable {
    case saving(progress: Double)   // 0...1
    case saved
    case failed(message: String)
}

struct GaugePill: View {
    let state: GaugePillState
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 6) {
            icon
            Text(label)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(strokeColor, lineWidth: AppShape.strokeHairline))
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var icon: some View {
        switch state {
        case .saving(let p):
            Gauge(value: p) { EmptyView() }
                .gaugeStyle(.accessoryCircularCapacity)
                .scaleEffect(0.55)
                .frame(width: 18, height: 18)
                .tint(tint)
        case .saved:
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(.green)
                .symbolEffect(.bounce, value: state)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var label: String {
        switch state {
        case .saving:           return "Saving"
        case .saved:            return "Saved"
        case .failed(let msg):  return msg.isEmpty ? "Failed" : msg
        }
    }

    private var strokeColor: Color {
        switch state {
        case .saving: return tint.opacity(0.35)
        case .saved:  return Color.green.opacity(0.35)
        case .failed: return Color.red.opacity(0.35)
        }
    }

    private var accessibilityLabel: String {
        switch state {
        case .saving(let p):    return "Saving, \(Int(p * 100)) percent"
        case .saved:            return "Saved to Photos"
        case .failed(let msg):  return "Save failed: \(msg)"
        }
    }
}
```

## Animation spec (every motion, named + bounded)

| Motion | Where | Curve | Duration | Reduce-motion fallback |
|---|---|---|---|---|
| Aurora drift | All `MeshAuroraView` instances | `TimelineView(.animation)` sin/cos | 16s period @ 30Hz | Static midpoint frame |
| Linear-aurora drift | A12/A13 fallback | `easeInOut` via TimelineView | 16s period @ 30Hz | Static gradient |
| Empty-state symbol pulse | 96pt SF Symbol on `EmptyStateView`, Stitch empty, MetaClean empty | `.symbolEffect(.pulse, options: .repeat(.continuous))` | system-driven (~4s loop) | omit `.symbolEffect` |
| Card scroll-transition | `VideoCardView` in grid | `.scrollTransition(.animated(.smooth(duration: 0.30)))` | 0.30s | identity-only (no scale/opacity change) |
| Drop-indicator grow | Stitch timeline insert capsule | `.smooth(duration: 0.18)` | 0.18s | snap with no animation |
| Save-success bounce | `GaugePill` `.saved` icon | `.symbolEffect(.bounce)` | 0.35s | omit |
| MetaClean shimmer | reading-state row icon | `easeInOut.repeatForever` | 1.4s loop | static |
| Bloom-in result card | MetaClean strip-complete row | `.transition(.scale(scale: 0.92).combined(with: .opacity))` over `.smooth(duration: 0.28)` | 0.28s | `.opacity` only |
| Tab tint cross-fade | `ContentView` selectedTab change | `.animation(.smooth(duration: 0.20), value: selectedTab)` | 0.20s | snap |
| Onboarding card swipe | unchanged from existing `TabView(.page)` | system | system | system |
| Stitch floating CTA appear | `.transition(.move(edge: .bottom).combined(with: .opacity))` | `.smooth(duration: 0.25)` | 0.25s | `.opacity` |

**No motion exceeds 0.40s.** No springs. No bouncy. No jiggle.

## Iconography (every SF Symbol used or replaced)

| Where | Symbol | Rendering mode | Effect | Notes |
|---|---|---|---|---|
| Compress tab bar | `wand.and.stars` | monochrome | none | system-tinted by `.tint(AppTint.compress(scheme))` on the inner `NavigationStack` |
| Compress empty hero | `wand.and.stars` | `.palette` | `.symbolEffect(.pulse, options: .repeat(.continuous))` | 96pt, palette layers `[tint, .secondary]` |
| Compress add button (toolbar) | `plus.circle.fill` | monochrome | none | tinted iris |
| Compress save state | (in `GaugePill`) | n/a | `.bounce` on `.saved` transition | replaces inline icons in `VideoRowView` |
| Stitch tab bar | `square.stack.3d.up` | monochrome | none | tinted mint |
| Stitch empty hero | `film.stack` | `.palette` | `.symbolEffect(.pulse)` | replaces existing `square.stack.3d.up` to differ from tab bar icon |
| Stitch sort menu | `arrow.up.arrow.down.circle` | monochrome | none | unchanged |
| Stitch transition picker labels | `sparkles` | monochrome | none | unchanged |
| Stitch export button | `square.and.arrow.up` | monochrome | none | floating capsule |
| Stitch drop indicator | n/a (Capsule shape) | n/a | `.smooth(duration: 0.18)` | n/a |
| MetaClean tab bar | `eye.slash` | monochrome | none | tinted indigo |
| MetaClean empty hero | `eye.slash.circle` | `.palette` | `.symbolEffect(.pulse)` | larger circle variant |
| MetaClean reading row icon | `magnifyingglass` | monochrome | `.shimmer()` modifier | replaces `Scanning…` label icon |
| MetaClean cleaned row | `checkmark.seal.fill` | monochrome | `.symbolEffect(.bounce, value:)` on transition | green |
| MetaClean Clean-All-Replace pulse | `wand.and.stars` (button label icon) | monochrome | `.symbolEffect(.variableColor.iterative)` only when `replaceOriginalsOnBatch == true` | red tint on symbol only, button stays default |
| Settings tab bar | `gearshape` | monochrome | none | graphite |
| Settings section icons | per-row | monochrome | none | each row links visually back to its tab via tint |
| Onboarding cards | unchanged symbols | `.palette` (NEW) | none | layers `[tabTint, .secondary]` |

## Files affected

| Path | Action | Responsibility |
|---|---|---|
| `VideoCompressor/ios/Theme/Theme.swift` | **Create** | `AppTint` (light/dark per tab + resolver), `AppMesh.palette(tint:scheme:)`, `AppShape` (radii/spacing/durations). Single source of color truth. |
| `VideoCompressor/ios/Theme/MeshAuroraView.swift` | **Create** | `MeshAuroraView`, `LinearAuroraView`, `AuroraBackend`. |
| `VideoCompressor/ios/Theme/CardStyle.swift` | **Create** | `CardStyle` ViewModifier + `.cardStyle(tint:)` extension. |
| `VideoCompressor/ios/Theme/Shimmer.swift` | **Create** | `Shimmer` modifier + `.shimmer()` extension. |
| `VideoCompressor/ios/Theme/GaugePill.swift` | **Create** | `GaugePill` with `GaugePillState` enum. |
| `VideoCompressor/ios/ContentView.swift` | **Modify** | Apply `.tint(AppTint.X(scheme))` *inside each tab's root view* (not on `TabView`). Add `.toolbarBackground(.thinMaterial, for: .tabBar)`. Wrap selected-tab tint change in `.animation(.smooth(duration: 0.20), value: selectedTab)`. |
| `VideoCompressor/ios/Views/EmptyStateView.swift` | **Modify** | Replace inner `CenteredEmptyState` content with `ZStack` over `MeshAuroraView(tint: AppTint.compress(scheme))`. 96pt `wand.and.stars` palette + pulse. Material CTA pill. |
| `VideoCompressor/ios/Views/VideoListView.swift` | **Modify** | Replace `List` populated path with `LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)])`. Apply `.scrollTransition` per card. Replace inline `ProgressView` linear-bar in row state with `Gauge(value:).gaugeStyle(.accessoryCircularCapacity).tint(AppTint.compress(scheme))` overlaid on thumbnail. Save-state moves into `GaugePill`. |
| `VideoCompressor/ios/Views/VideoRowView.swift` | **Replace name → `VideoCardView.swift`** | Convert to card layout: 16:9 thumbnail top, name + meta-pill row below, `GaugePill` bottom-right, swipe-to-delete via context menu (long-press). Keep model-binding identical. **Do NOT change the `VideoFile` model.** |
| `VideoCompressor/ios/Views/StitchTab/StitchTabView.swift` | **Modify** | Mint tint via `.tint(AppTint.stitch(scheme))` on `NavigationStack`. Empty-state body wrapped in `MeshAuroraView`. Bottom action bar's "Stitch & Export" button becomes a floating capsule with `.glassEffect()` (iOS 26) / `.thickMaterial` (iOS 18). Drop-indicator capsule already exists in `StitchTimelineView` — see that file. |
| `VideoCompressor/ios/Views/StitchTab/ClipBlockView.swift` | **Modify** | Apply `.cardStyle(tint: AppTint.stitch(scheme))` to the row container. Thumbnail strip corner radius bumps from 6 → `AppShape.radiusS` (8). Selection ring color follows tint, not `.accentColor`. |
| `VideoCompressor/ios/Views/StitchTab/StitchTimelineView.swift` | **Modify** | Drop-indicator capsule color: `AppTint.stitch(scheme)`. Animation duration: `0.18s` `.smooth`. Drop-indicator height grows from `2pt` → `6pt` width when targeted. Selection ring color → tint. |
| `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanTabView.swift` | **Modify** | Indigo tint. Empty state wrapped in `MeshAuroraView`. List rows wrapped in `.cardStyle(tint:)`. `batchControls` bottom bar moves to `.thinMaterial` instead of `.bar`. The Clean-All-Replace symbol gets `.symbolEffect(.variableColor.iterative)` only when `replaceOriginalsOnBatch == true`. |
| `VideoCompressor/ios/Views/MetaCleanTab/MetaCleanRowView.swift` | **Modify** | Reading state: `magnifyingglass` icon with `.shimmer()`. Cleaned state: `.transition(.scale(scale: 0.92).combined(with: .opacity))` from initial render. Use indigo tint for the leading icon. |
| `VideoCompressor/ios/Views/SettingsTabView.swift` | **Modify** | Graphite tint. `.scrollContentBackground(.hidden)`. Section headers given `.textCase(.uppercase)` + `.tracking(0.4)` + `.font(.caption.weight(.medium))`. Per-row leading icons referencing other tabs are tinted with that tab's color. **No aurora here.** |
| `VideoCompressor/ios/Views/Onboarding/OnboardingView.swift` | **Modify** | Keep `TabView(.page)`. Restyle `card(symbol:title:body:)`: each card gets a `MeshAuroraView` background tinted to the tab the card represents. Page 0 (MetaClean) → indigo; Page 1 (Compress) → iris; Page 2 (Stitch) → mint. The 68pt symbol becomes palette mode with the same tint. Get-started button uses tint of the page it sits on. |
| `VideoCompressor/ios/Views/PresetPickerView.swift` | **Modify** | Apply `.tint(AppTint.compress(scheme))` to the inner `NavigationStack`. Selected-row checkmark uses tint. **No structural changes** — Codex's Cluster 3 simplification stays. |
| `VideoCompressor/ios/Views/StitchTab/StitchExportSheet.swift` | **Modify** | Apply `.tint(AppTint.stitch(scheme))` to the inner `NavigationStack`. Cluster 2.5's post-save `Done — start a new project` CTA stays — just adopt the tint. |
| `VideoCompressor/VideoCompressorTests/ThemeSnapshotTests.swift` | **Create** | `ImageRenderer`-based snapshot smoke tests for light + dark of: `EmptyStateView`, `VideoCardView`, `MetaCleanRowView` reading/cleaned, Stitch empty, Settings root. Asserts non-zero PNG bytes + renderable, no pixel-perfect diff. |

### Files Codex must NOT touch (enforced)

- `VideoCompressor/VideoCompressorApp.swift` — entry point, do not modify
- `VideoCompressor/ios/Item.swift` — model
- `VideoCompressor/ios/Services/*` — every file
- `VideoCompressor/ios/Models/*` — every file
- `VideoCompressor/ios/Resources/*`
- `VideoCompressor/ios/PrivacyInfo.xcprivacy`
- `Haptics.swift` (already wired to `UISelectionFeedbackGenerator`; no CoreHaptics)
- `.github/workflows/testflight.yml`
- Any `project.pbxproj` line containing `PRODUCT_BUNDLE_IDENTIFIER`

If a file in this no-touch list needs to change for the spec to compile, **STOP** — log a `[BLOCKED]` line in `AI-CHAT-LOG.md` and surface to the user. Do not refactor your way around it.

## Tasks (TDD red-green-commit per task; 8 tasks plus PR)

Same task discipline as `1-cluster-2.5-stitch-hotfix.md`. Each task: red → implement → green → commit. Reviewer subagent timeouts: 1-strike static-diff fallback policy.

### Task 1 — Theme tokens

- [ ] **Step 1:** Create `VideoCompressor/ios/Theme/Theme.swift` with the canonical `AppTint`, `AppMesh`, `AppShape` enums from the "Color tokens" section above. Verbatim values.
- [ ] **Step 2:** Create `VideoCompressor/VideoCompressorTests/ThemeContrastTests.swift`. For each of the 4 tab tints in light + dark, assert the OKLCH-derived luminance contrast against a synthesized `.thickMaterial` color (use `Color(red: 0.92, green: 0.92, blue: 0.94)` for light and `Color(red: 0.16, green: 0.16, blue: 0.18)` for dark as the material's effective midpoint) is ≥ 4.5:1. Use a simple WCAG luminance formula — pure unit math, no SwiftUI rendering.
- [ ] **Step 3:** `mcp__xcodebuildmcp__test_sim` — TDD red. The new test class must compile (since `AppTint` exists) but fail if any tint underperforms. If a tint fails: bump L\* in OKLCH by 0.05 and retry. Log every adjustment in the commit message.
- [ ] **Step 4:** `test_sim` green.
- [ ] **Step 5:** `build_sim` clean.
- [ ] **Commit:** `feat(theme): add canonical color + shape tokens with WCAG AA contrast`

### Task 2 — Shared components: `MeshAuroraView`, `CardStyle`, `Shimmer`, `GaugePill`

- [ ] **Step 1:** Create the four files in `VideoCompressor/ios/Theme/` with the skeletons from "Component blueprints". Resolve `AuroraBackend.preferred` synchronously: `static let preferred: AuroraBackend = UIScreen.main.maximumFramesPerSecond >= 90 ? .mesh : .linearAnimated`.
- [ ] **Step 2:** Create `VideoCompressor/VideoCompressorTests/ThemeComponentTests.swift`. Smoke tests:
    - `MeshAuroraView(tint: .red)` renders to non-empty image at 200×200 via `ImageRenderer` in both schemes.
    - `GaugePill(state: .saving(progress: 0.5), tint: .blue)` renders.
    - `GaugePill(state: .saved, tint: .blue)` renders.
    - `GaugePill(state: .failed(message: "boom"), tint: .blue)` renders.
    - `Text("hi").shimmer()` renders.
    - `Text("hi").cardStyle(tint: .green)` renders.
- [ ] **Step 3:** `test_sim` — red (files don't exist or don't compile).
- [ ] **Step 4:** Build until green.
- [ ] **Commit:** `feat(theme): add MeshAuroraView, CardStyle, Shimmer, GaugePill`

### Task 3 — Empty states adopt the mesh aurora hero

- [ ] **Step 1:** Modify `EmptyStateView.swift`. Wrap the existing `CenteredEmptyState` body in a `ZStack` with `MeshAuroraView(tint: AppTint.compress(scheme))` behind. Symbol becomes `wand.and.stars` at 96pt with `.symbolRenderingMode(.palette)` + `.foregroundStyle(AppTint.compress(scheme), .secondary)` + `.symbolEffect(.pulse, options: .repeat(.continuous))`. Replace `.buttonStyle(.borderedProminent)` on the `PhotosPicker` label with a custom material pill: `.padding(.horizontal, 22).padding(.vertical, 12).background(.thickMaterial, in: Capsule()).overlay(Capsule().strokeBorder(AppTint.compress(scheme).opacity(0.3), lineWidth: 1))`. iOS 26 `.glassEffect()` gate via `#available`.
- [ ] **Step 2:** Apply the same pattern in `StitchTabView.swift` empty branch (tint: `AppTint.stitch(scheme)`, symbol: `film.stack`) and `MetaCleanTabView.swift` empty branch (tint: `AppTint.metaClean(scheme)`, symbol: `eye.slash.circle`).
- [ ] **Step 3:** `mcp__xcodebuildmcp__build_run_sim`, then `mcp__xcodebuildmcp__screenshot` of each empty state in light + dark. Save under `.agents/work-sessions/2026-05-04/snapshots/cluster-3.5/`.
- [ ] **Step 4:** `test_sim` green (existing 252+ tests untouched).
- [ ] **Commit:** `feat(theme): aurora-mesh empty states across all 3 user tabs`

### Task 4 — Compress tab grid restyle

- [ ] **Step 1:** Rename `VideoRowView.swift` → `VideoCardView.swift` via `git mv`. Restructure to a card: 16:9 thumbnail top (use the existing `kind == .still` decision logic, decoded by ImageIO for stills + AVAssetImageGenerator first frame for videos — implement only if no thumbnail loader exists locally; otherwise reuse what's there). Filename + monospaced meta pills below. `GaugePill` bottom-right corner. The save action moves to a context-menu `Button` invoked by long-press. `.cardStyle(tint: AppTint.compress(scheme))`.
- [ ] **Step 2:** In `VideoListView.swift`, replace `populatedList`'s `List { ForEach ... }` with:
    ```swift
    ScrollView {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 168), spacing: 12)], spacing: 12) {
            ForEach(library.videos) { video in
                VideoCardView(video: video)
                    .scrollTransition(.animated(.smooth(duration: AppShape.scrollTransitionDuration))) { content, phase in
                        content
                            .opacity(phase.isIdentity ? 1.0 : 0.5)
                            .scaleEffect(phase.isIdentity ? 1.0 : 0.96)
                    }
                    .contextMenu {
                        Button(role: .destructive) {
                            library.remove(video.id)
                        } label: { Label("Remove", systemImage: "trash") }
                        if case .finished = video.jobState {
                            Button {
                                Task { await library.saveOutputToPhotos(for: video.id) }
                            } label: { Label("Save to Photos", systemImage: "square.and.arrow.down") }
                        }
                    }
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
    }
    .scrollContentBackground(.hidden)
    ```
- [ ] **Step 3:** `actionBar` retains shape but `.background(.thinMaterial)` instead of `.bar` and tint follows `AppTint.compress(scheme)` for the prominent button.
- [ ] **Step 4:** `build_run_sim`, `screenshot` populated-state in light + dark. Verify 2 columns on iPhone, 3 on iPad (the adaptive minimum will handle this).
- [ ] **Step 5:** `test_sim` green. Existing tests reference `VideoRowView` only via UIKit identifiers — search the test target and update any `VideoRowView` typename references; the `accessibilityIdentifier`s on cells stay the same.
- [ ] **Commit:** `feat(theme): convert Compress list to card grid with circular gauge`

### Task 5 — Stitch tab: tint, floating CTA, fluid drop indicator, mood

- [ ] **Step 1:** In `StitchTabView.swift`, apply `.tint(AppTint.stitch(scheme))` to the `NavigationStack`. `aspectModePicker` and `transitionPicker` icons + selected-segment color follow tint via system. The bottom `stitchActionBar` is removed; its "Stitch & Export" button moves to a `.safeAreaInset(edge: .bottom)` overlay rendering a floating capsule:
    ```swift
    Button { showExportSheet = true } label: {
        Label("Stitch & Export", systemImage: "square.and.arrow.up")
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 22).padding(.vertical, 14)
    }
    .background(.thickMaterial, in: Capsule())
    .overlay(Capsule().strokeBorder(AppTint.stitch(scheme).opacity(0.3), lineWidth: 1))
    .padding(.bottom, 12)
    .glassEffectIfAvailable()  // helper that no-ops on iOS 18 and applies on iOS 26
    .disabled(!project.canExport)
    .transition(.move(edge: .bottom).combined(with: .opacity))
    .animation(.smooth(duration: 0.25), value: project.clips.isEmpty)
    ```
    Add the helper in `Theme.swift`:
    ```swift
    extension View {
        @ViewBuilder
        func glassEffectIfAvailable() -> some View {
            if #available(iOS 26.0, *) {
                self.glassEffect()
            } else {
                self
            }
        }
    }
    ```
- [ ] **Step 2:** In `StitchTimelineView.swift`, drop-indicator: change `Color.accentColor` → `AppTint.stitch(scheme)`. Width animation curve `.smooth(duration: 0.18)` (was `.easeInOut(duration: 0.20)`). Selection ring stroke color → tint. Width values: 2pt baseline → 6pt when targeted.
- [ ] **Step 3:** In `ClipBlockView.swift`, wrap the row content in `.cardStyle(tint: AppTint.stitch(scheme))` instead of `.padding(.vertical, 4)`. Thumbnail corner radius 6 → `AppShape.radiusS` (8). Tinted "Edited" label.
- [ ] **Step 4:** `build_run_sim`. Manual verify: import 2 clips, drag one — drop indicator should glow mint and animate 0.18s. Floating Export capsule should sit above home indicator.
- [ ] **Step 5:** `test_sim` green.
- [ ] **Commit:** `feat(theme): Stitch mint identity + floating glass CTA + fluid drop indicator`

### Task 6 — MetaClean tab: tint + scanner shimmer + bloom-in cards

- [ ] **Step 1:** `MetaCleanTabView.swift` — `.tint(AppTint.metaClean(scheme))` on `NavigationStack`. Wrap `List` rows in `.cardStyle(tint: AppTint.metaClean(scheme))` via a `.listRowBackground(Color.clear)` + `.listRowSeparator(.hidden)` + `.cardStyle(...)` on the row content. Switch `List` to `.listStyle(.plain)` and `.scrollContentBackground(.hidden)`.
- [ ] **Step 2:** `batchControls` bottom region: `.background(.thinMaterial)` instead of `.bar`. The Clean-All-Replace `wand.and.stars` icon gets `.symbolEffect(.variableColor.iterative)` only when `queue.replaceOriginalsOnBatch == true`. Button stays the standard `.borderedProminent` shape — no red background, only the symbol is tinted red via a foreground modifier on the icon.
- [ ] **Step 3:** `MetaCleanRowView.swift` — leading icon changes:
    - `tags.isEmpty && cleanResult == nil && scanError == nil` (reading) → `Image(systemName: "magnifyingglass").shimmer().foregroundStyle(AppTint.metaClean(scheme))`
    - `cleanResult != nil` (cleaned) → `Image(systemName: "checkmark.seal.fill").foregroundStyle(.green).symbolEffect(.bounce, value: item.cleanResult != nil)`
    - default → `Image(systemName: "film").foregroundStyle(AppTint.metaClean(scheme))`
- [ ] **Step 4:** Add `.transition(.scale(scale: 0.92).combined(with: .opacity))` to the row when the cleaned-state branch becomes active (use a separate `Group` keyed on `item.cleanResult != nil` with `.animation(.smooth(duration: 0.28), value: item.cleanResult != nil)` on the `MetaCleanRowView` body).
- [ ] **Step 5:** `build_run_sim`. Capture `screenshot` of empty + populated + cleaning states in both schemes.
- [ ] **Step 6:** `test_sim` green.
- [ ] **Commit:** `feat(theme): MetaClean indigo identity + scanner shimmer + bloom cards`

### Task 7 — Settings restyle + Onboarding per-tab tints

- [ ] **Step 1:** `SettingsTabView.swift` — `.tint(AppTint.settings(scheme))` on `NavigationStack`. Add `.scrollContentBackground(.hidden)` to the `Form`. `Form` background: a subtle `.thinMaterial` over `AppMesh.backdrop(scheme)` (NOT an aurora — Settings stays calm). Section headers wrapped:
    ```swift
    Text("What MetaClean does")
        .font(.caption.weight(.medium))
        .textCase(.uppercase)
        .tracking(0.4)
        .foregroundStyle(.secondary)
    ```
    Use `Section { ... } header: { headerStyle("…") }` pattern via a small private builder.
- [ ] **Step 2:** Per-row leading icons referencing other tab functionality use that tab's tint. Add icons where currently absent (e.g. an `eye.slash` icon next to "What MetaClean does" header). Storage section's `Clear cache` keeps its destructive role + red tint via `.foregroundStyle(.red)`.
- [ ] **Step 3:** `OnboardingView.swift` — keep the `TabView(.page)` structure. Restructure `card(symbol:title:body:)` to:
    ```swift
    private func card(symbol: String, title: String, body: String, tint: Color) -> some View {
        ZStack {
            MeshAuroraView(tint: tint)
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: symbol)
                    .font(.system(size: 68, weight: .light))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(tint, .secondary)
                Text(title).font(.title.weight(.semibold))
                Text(body).font(.body).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal, 32)
                Spacer()
            }
        }
    }
    ```
    Pass: page 0 (MetaClean) → `AppTint.metaClean(scheme)`; page 1 (Compress) → `AppTint.compress(scheme)`; page 2 (Stitch) → `AppTint.stitch(scheme)`. The "Get started" / "Next" button uses `.tint(currentPageTint)` — Codex computes via the page index.
- [ ] **Step 4:** `build_run_sim`, capture each onboarding card in both schemes.
- [ ] **Step 5:** `test_sim` green.
- [ ] **Commit:** `feat(theme): Settings graphite calm + Onboarding per-tab aurora previews`

### Task 8 — Per-tab system tint + snapshot tests + verification

- [ ] **Step 1:** `ContentView.swift` — apply `.tint(AppTint.X(scheme))` *inside each individual tab's root `NavigationStack`*, not on the parent `TabView`. The `TabView` itself still gets a `.tint(AppTint.compress(scheme))` only for the tab-bar selected indicator, recomputed via:
    ```swift
    private func tabBarTint(_ scheme: ColorScheme) -> Color {
        switch selectedTab {
        case .compress:  return AppTint.compress(scheme)
        case .stitch:    return AppTint.stitch(scheme)
        case .metaClean: return AppTint.metaClean(scheme)
        case .settings:  return AppTint.settings(scheme)
        }
    }
    ```
    Wrap the whole `TabView` in `.animation(.smooth(duration: 0.20), value: selectedTab)`. Add `.toolbarBackground(.thinMaterial, for: .tabBar)`.
- [ ] **Step 2:** Create `VideoCompressor/VideoCompressorTests/ThemeSnapshotTests.swift`. Smoke tests using `ImageRenderer`:
    - `EmptyStateView` light + dark — non-empty PNG bytes
    - `VideoCardView(video: .preview())` light + dark
    - `MetaCleanRowView` reading + cleaned states, both schemes
    - Stitch empty `CenteredEmptyState` wrapped variant, both schemes
    - `OnboardingView` rendered at index 0, 1, 2 — non-empty PNG
    File-size delta only — no pixel compare. Each test asserts `data.count > 1024` (non-trivial render).
- [ ] **Step 3:** `mcp__xcodebuildmcp__test_sim` final pass — expect 252+ existing green + ~10 new green = 262+ total.
- [ ] **Step 4:** `mcp__xcodebuildmcp__build_sim` clean.
- [ ] **Step 5:** Capture `screenshot` of all 4 tabs in both schemes (8 images) plus all 3 onboarding cards (6 images). Save to `.agents/work-sessions/2026-05-04/snapshots/cluster-3.5/`. List file paths in the AI-CHAT-LOG entry for this task.
- [ ] **Commit:** `feat(theme): per-tab tint follows active tab + snapshot smoke tests`

### Task 9 — PR

- [ ] **Step 1:** Append a `[BLOCKED]` line to today's `AI-CHAT-LOG.md` matching Cluster 2.5's format exactly:
    ```
    [YYYY-MM-DD HH:MM SAST] [solo/codex/<model>] [BLOCKED] Cluster 3.5 visual redo ready for real-device verification — install latest TestFlight, walk through Compress empty + populated, Stitch empty + drag-drop with mint indicator, MetaClean reading shimmer + cleaned bloom, Onboarding 3-card flow, all 4 tab transitions in light + dark. Will not merge until user confirms via [DECISION] line.
    ```
- [ ] **Step 2:** Open PR. Title: `feat(theme): Calm-Cinema visual identity v2`. Body sections:
    - Summary (1 sentence)
    - 8 task-commit references with bullet summary
    - Per-tab screenshot grid (light + dark)
    - Real-device verification checklist (mirroring the `[BLOCKED]` line)
    - Acceptance-criteria checklist
- [ ] **Step 3:** Wait for the user's `[DECISION]` line before merging. If user reports failure, do NOT auto-merge — file findings into AI-CHAT-LOG and pivot to fix.

## Performance budget

| Surface | Device class | Target | Backend |
|---|---|---|---|
| Empty-state aurora | iPhone 13 Pro / A15 / ProMotion | 60fps minimum, 30Hz drift | `MeshGradient` via `TimelineView(.animation(minimumInterval: 1/30))` |
| Empty-state aurora | iPhone 11 / A13, iPhone XS / A12, SE3 | 60fps display, 30Hz drift | `LinearAuroraView` (LinearGradient + animated UnitPoints) |
| Scroll grid | A12+ | 60fps, no dropped frames during fling | `LazyVGrid` + `.scrollTransition` (system-optimized) |
| MetaClean shimmer | A12+ | 60fps | `LinearGradient` overlay with `.mask` — cheap |
| GaugePill | A12+ | n/a | `Gauge` is system-rendered |

`AuroraBackend.preferred` resolves once at process start via `UIScreen.main.maximumFramesPerSecond >= 90`. ProMotion-capable phones (A15+) get the mesh path; everything older gets the linear path. **Both paths run at 30Hz, not 60.** Aurora animation is decorative — full display refresh is wasted GPU.

If `\.accessibilityReduceMotion` is true, the `TimelineView` is paused and renders the midpoint frame statically. This is required for App Store accessibility review.

## Accessibility

- **Dynamic Type:** Every `Text` uses semantic font tokens (`.body`, `.caption`, `.subheadline`). Card layouts must remain readable at the largest accessibility size — the `LazyVGrid` adaptive minimum of 168pt accommodates this with one line of metadata; if labels overflow at AX5, allow `.lineLimit(2)` and let cards grow vertically.
- **Reduce Motion:** Honor `\.accessibilityReduceMotion` on:
    - `MeshAuroraView` (paused)
    - `LinearAuroraView` (paused)
    - `Shimmer` (no-op on appear)
    - `.symbolEffect(.pulse)` — wrap in `if !reduceMotion { ... }` or a custom modifier that strips the effect
- **Reduce Transparency:** Where `\.accessibilityReduceTransparency` is true, swap `.thickMaterial` → `Color(.systemBackground)` and `.thinMaterial` → `Color(.secondarySystemBackground)` via a small `.materialOrSolid()` helper. Defer this to a follow-up if time-boxed; minimum: aurora views still work because backdrop is solid.
- **Contrast:** Task 1 enforces ≥ 4.5:1 for every tint against `.thickMaterial`. Foreground text never uses tint color — `.foregroundStyle(.primary)` for body, `.secondary` for captions. Tints are restricted to symbols, capsule fills, stroke borders, and selection rings.
- **VoiceOver:** Aurora views set `.accessibilityHidden(true)` (decorative). `GaugePill` provides explicit accessibilityLabel per state (saving + percent, saved, failed + reason).
- **Hit targets:** All buttons remain ≥ 44×44pt — capsule CTAs already exceed this. Card grid items are ≥ 168×168pt.

## Acceptance criteria

- [ ] All 4 tabs visually distinct via tint in both light and dark
- [ ] All 3 user-facing empty states use animated `MeshAuroraView` (or LinearAurora fallback on A12/A13)
- [ ] Compress tab is a 2-column adaptive `LazyVGrid` of cards, NOT a `List`
- [ ] Floating "Stitch & Export" capsule on Stitch tab uses `.thickMaterial` with `.glassEffect()` on iOS 26
- [ ] No accent color is hard-coded outside `Theme.swift`
- [ ] Light + dark mode both render acceptably at every screen — no white-on-white, no unreadable contrast
- [ ] All animations honor `\.accessibilityReduceMotion`
- [ ] Snapshot tests pass; `262+` total tests green; existing 252+ tests still green
- [ ] No file in the "Files Codex must NOT touch" list was modified
- [ ] PR open with `[BLOCKED]` line; user has confirmed real-device pass via `[DECISION]` before merge

## Notes for the executing agent

- This spec assumes Cluster 2.5 has merged to main. If it has not, **stop and walk Cluster 2.5 first.**
- Reviewer subagents tend to time out on this codebase. Same 1-strike-then-static-diff fallback policy as Cluster 2.5.
- Keep commits atomic per task. Eight commits + the PR. No squashing inside the PR.
- If you discover that any color in `AppTint` fails WCAG AA on `.thickMaterial`, the response is to bump L\* in OKLCH by 0.05 increments until it passes — *not* to lower the contrast bar. Log every adjustment in the commit message that adds the test.
- Do **not** introduce CoreHaptics for any new feedback. The existing `Haptics.swift` (UISelectionFeedbackGenerator) covers everything in the existing UI. New views in this spec do not require new haptic events — system controls (button press, segmented picker change) handle their own.
- Do **not** introduce a custom `AVVideoCompositing`. Nothing in this spec needs one.
- iOS 26 `.glassEffect()` — only used in two places (Stitch floating CTA, optionally the Compress empty CTA). Both are gated. Do not propagate it elsewhere as "polish."
- The `MetaCleanQueueView` name in older drafts refers to `MetaCleanTabView.swift` — that is the actual filename and the view internally hosts the queue list. Use the real filename.
- When in doubt about whether to split a commit, split. Eight tasks → eight commits, no exceptions.
