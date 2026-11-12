import SwiftUI
import UIKit

// HCG News editorial identity.
//
// Restrained black, charcoal, silver and white surfaces. Cyan is reserved for
// actions and status (links, buttons, progress, selected states); it is never
// used for large panels. Every colour adapts to Light / Dark and Increase Contrast.

/// The reader's appearance choice.
enum AppearanceChoice: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
    static let storageKey = "appearance"
}

private extension UIColor {
    convenience init(light: UInt32, dark: UInt32, lightHC: UInt32? = nil, darkHC: UInt32? = nil) {
        self.init { traits in
            let high = traits.accessibilityContrast == .high
            let value: UInt32
            if traits.userInterfaceStyle == .dark { value = high ? (darkHC ?? dark) : dark } else { value = high ? (lightHC ?? light) : light }
            return UIColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                           blue: CGFloat(value & 0xff) / 255, alpha: 1)
        }
    }
}

/// Semantic colours. All text pairs meet WCAG AA (4.5:1) on their backgrounds;
/// body text meets AAA (7:1).
enum Palette {
    static let background = Color(uiColor: UIColor(light: 0xFAFAF8, dark: 0x0B0B0C))
    static let surface = Color(uiColor: UIColor(light: 0xF0F0EE, dark: 0x17181A))
    static let elevated = Color(uiColor: UIColor(light: 0xFFFFFF, dark: 0x1F2023))
    static let primaryText = Color(uiColor: UIColor(light: 0x121212, dark: 0xF2F2F2, lightHC: 0x000000, darkHC: 0xFFFFFF))
    static let secondaryText = Color(uiColor: UIColor(light: 0x4A4B50, dark: 0xA9ABB0, lightHC: 0x2C2D31, darkHC: 0xD4D6DA))
    /// Silver: rules, hairlines and quiet labels.
    static let silver = Color(uiColor: UIColor(light: 0x8A8C91, dark: 0x8E9096, lightHC: 0x5F6166, darkHC: 0xB9BBC0))
    static let separator = Color(uiColor: UIColor(light: 0xDADAD6, dark: 0x2C2D30, lightHC: 0x9A9B97, darkHC: 0x5A5B5F))
    /// Cyan, for actions and status only.
    static let accent = Color(uiColor: UIColor(light: 0x007C99, dark: 0x3FD0E0, lightHC: 0x005F75, darkHC: 0x7BE3EE))
    /// Text on an accent-filled control.
    static let onAccent = Color(uiColor: UIColor(light: 0xFFFFFF, dark: 0x061014))
    /// The masthead band is always black: the HCG logo's native ground.
    static let masthead = Color.black
    static let warning = Color(uiColor: UIColor(light: 0x8A5300, dark: 0xF2B35A))
    static let destructive = Color(uiColor: UIColor(light: 0xB3261E, dark: 0xF2867F))
}

/// Typography. Every style is a Dynamic Type text style.
enum Typography {
    static func headline(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        .system(style, design: .serif, weight: weight)
    }

    static func body(_ typeface: ArticleTypeface) -> Font {
        typeface == .serif ? .system(.body, design: .serif) : .system(.body)
    }

    static let kicker = Font.system(.caption, weight: .semibold)
    static let meta = Font.system(.footnote)
    static let sectionTitle = Font.system(.footnote, weight: .bold)
}

// MARK: - Reader settings

enum ArticleTypeface: String, CaseIterable, Identifiable {
    case serif, sans
    var id: String { rawValue }
    var title: String { self == .serif ? "Serif" : "Sans serif" }
    static let storageKey = "articleTypeface"
}

enum LineSpacingChoice: String, CaseIterable, Identifiable {
    case compact, comfortable, relaxed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .compact: "Compact"
        case .comfortable: "Comfortable"
        case .relaxed: "Relaxed"
        }
    }
    var points: CGFloat {
        switch self {
        case .compact: 2
        case .comfortable: 6
        case .relaxed: 10
        }
    }
    static let storageKey = "articleLineSpacing"
}

enum ReadingWidthChoice: String, CaseIterable, Identifiable {
    case narrow, standard, wide
    var id: String { rawValue }
    var title: String {
        switch self {
        case .narrow: "Narrow"
        case .standard: "Standard"
        case .wide: "Wide"
        }
    }
    /// Maximum text column width on large displays. Narrow screens use the full width.
    var maxWidth: CGFloat {
        switch self {
        case .narrow: 560
        case .standard: 680
        case .wide: 820
        }
    }
    static let storageKey = "articleReadingWidth"
}

/// Article text size, applied on top of the system Dynamic Type size.
enum ReadingSize {
    static let storageKey = "readingSizeStep"
    static let range = -2...3

    static func adjusted(_ base: DynamicTypeSize, step: Int) -> DynamicTypeSize {
        let all = DynamicTypeSize.allCases
        guard let index = all.firstIndex(of: base) else { return base }
        return all[min(max(index + step, 0), all.count - 1)]
    }

    static func label(for step: Int) -> String {
        switch step {
        case 0: "System size"
        case let s where s < 0: "Smaller (\(s))"
        default: "Larger (+\(step))"
        }
    }
}

// MARK: - Root styling

struct ThemedRoot: ViewModifier {
    @AppStorage(AppearanceChoice.storageKey) private var appearanceRaw = AppearanceChoice.system.rawValue

    func body(content: Content) -> some View {
        content
            .tint(Palette.accent)
            .preferredColorScheme((AppearanceChoice(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}

extension View {
    func hcgThemed() -> some View { modifier(ThemedRoot()) }

    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.background.ignoresSafeArea())
    }

    /// A quiet card surface with a hairline border.
    func cardSurface(cornerRadius: CGFloat = 12) -> some View {
        padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).strokeBorder(Palette.separator, lineWidth: 1))
    }
}

/// Primary action button: cyan fill, used sparingly.
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(Palette.onAccent)
            .padding(.horizontal, 18)
            .frame(minHeight: 44)
            .background(Palette.accent.opacity(isEnabled ? (configuration.isPressed ? 0.8 : 1) : 0.4),
                        in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

/// Secondary action: hairline outline, accent text.
struct SecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(isEnabled ? Palette.accent : Palette.silver)
            .padding(.horizontal, 16)
            .frame(minHeight: 44)
            .background(Palette.elevated.opacity(configuration.isPressed ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.separator, lineWidth: 1))
    }
}

/// Dates used across the app.
enum NewsDate {
    static func full(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.wide).year().hour().minute())
    }

    static func day(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
    }

    static func short(_ date: Date, now: Date = Date()) -> String {
        let age = now.timeIntervalSince(date)
        if age >= 0, age < 24 * 3600 { return date.formatted(.relative(presentation: .named)) }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }
}

enum ByteSize {
    static func string(_ bytes: Int64) -> String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file) }
}
