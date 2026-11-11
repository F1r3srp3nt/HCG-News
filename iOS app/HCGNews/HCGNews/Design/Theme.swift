import SwiftUI
import UIKit

/// The two reading styles.
/// - Future: dark navy/black, restrained cyan accents, serif headlines. Always dark.
/// - Classic: quieter, highly readable; follows the system light/dark appearance.
enum ReaderStyle: String, CaseIterable, Identifiable {
    case future
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .future: "Future"
        case .classic: "Classic"
        }
    }

    var summary: String {
        switch self {
        case .future: "Dark navy, cyan accents and serif headlines."
        case .classic: "Quiet and highly readable. Follows Light or Dark Mode."
        }
    }

    /// Future is a dark design; Classic respects the system appearance.
    var forcedColorScheme: ColorScheme? {
        self == .future ? .dark : nil
    }
}

/// Colours for the current style, contrast setting and appearance.
struct Palette {
    let background: Color
    let surface: Color
    let primaryText: Color
    let secondaryText: Color
    let accent: Color
    let separator: Color
    /// Text/icon colour used on top of `accent`.
    let onAccent: Color

    static func make(style: ReaderStyle, contrast: ColorSchemeContrast) -> Palette {
        let increased = contrast == .increased
        switch style {
        case .future:
            return Palette(
                background: Color(red: 0.020, green: 0.031, blue: 0.059),             // #05080F
                surface: Color(red: 0.043, green: 0.071, blue: 0.125),                // #0B1220
                primaryText: Color(red: 0.925, green: 0.945, blue: 0.969),            // #ECF1F7
                secondaryText: increased
                    ? Color(red: 0.820, green: 0.855, blue: 0.900)
                    : Color(red: 0.635, green: 0.690, blue: 0.765),                   // #A2B0C3 (≥ 7:1 on background)
                accent: increased
                    ? Color(red: 0.470, green: 0.900, blue: 0.960)
                    : Color(red: 0.247, green: 0.816, blue: 0.878),                   // #3FD0E0
                separator: Color.white.opacity(increased ? 0.30 : 0.12),
                onAccent: Color(red: 0.020, green: 0.031, blue: 0.059))
        case .classic:
            return Palette(
                background: Color(uiColor: .systemBackground),
                surface: Color(uiColor: .secondarySystemBackground),
                primaryText: Color(uiColor: .label),
                secondaryText: Color(uiColor: .secondaryLabel),
                accent: Color("AccentColor"),
                separator: Color(uiColor: .separator),
                onAccent: Color(uiColor: .systemBackground))
        }
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = Palette.make(style: .classic, contrast: .standard)
}

private struct ReaderStyleKey: EnvironmentKey {
    static let defaultValue = ReaderStyle.classic
}

extension EnvironmentValues {
    var palette: Palette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }

    var readerStyle: ReaderStyle {
        get { self[ReaderStyleKey.self] }
        set { self[ReaderStyleKey.self] = newValue }
    }
}

/// Typography. Every style is a Dynamic Type text style, so system text size and
/// accessibility sizes always apply.
enum Typography {
    static func headline(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static func body(for readerStyle: ReaderStyle) -> Font {
        readerStyle == .classic ? .system(.body, design: .serif) : .system(.body, design: .default)
    }

    static let kicker = Font.system(.caption, design: .default, weight: .semibold)
    static let meta = Font.system(.footnote)
}

/// Article reading size, applied on top of the system Dynamic Type size.
enum ReadingSize {
    static let storageKey = "readingSizeStep"
    static let range = -2...3

    /// Offsets the reader's system size by `step` positions, clamped to the
    /// supported Dynamic Type sizes (including accessibility sizes).
    static func adjusted(_ base: DynamicTypeSize, step: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: base) else { return base }
        let target = min(max(index + step, 0), all.count - 1)
        return all[target]
    }

    static func label(for step: Int) -> String {
        switch step {
        case 0: "System size"
        case let s where s < 0: "Smaller (\(s))"
        default: "Larger (+\(step))"
        }
    }
}

/// Applies the reader style: background, tint, palette and colour scheme.
struct ThemedRoot: ViewModifier {
    @AppStorage("readerStyle") private var styleRaw = ReaderStyle.future.rawValue
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        let style = ReaderStyle(rawValue: styleRaw) ?? .future
        let palette = Palette.make(style: style, contrast: contrast)
        content
            .environment(\.readerStyle, style)
            .environment(\.palette, palette)
            .tint(palette.accent)
            .preferredColorScheme(style.forcedColorScheme)
    }
}

extension View {
    func hcgThemed() -> some View { modifier(ThemedRoot()) }

    /// Standard screen background for the current style.
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}

private struct ScreenBackground: ViewModifier {
    @Environment(\.palette) private var palette

    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(palette.background.ignoresSafeArea())
    }
}

/// Date formatting used across the app.
enum NewsDate {
    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().hour().minute())
    }

    static func short(_ date: Date, now: Date = Date()) -> String {
        if now.timeIntervalSince(date) < 24 * 3600, now.timeIntervalSince(date) >= 0 {
            return date.formatted(.relative(presentation: .named))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}
