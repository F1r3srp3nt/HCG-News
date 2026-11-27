import SwiftUI
import UIKit
import CoreText

// HCG News editorial identity, taken from news.hakmicapitalgroup.com.
//
// Two editions, as on the website, each in Light and Dark:
// - Future Edition: the futuristic HCG logo, signal-cyan accents, layered metallic
//   surfaces and the command-centre backdrop.
// - Classic Edition: the classic metallic HCG logo and black-and-white editorial reading.
// The website's colour tokens are its dark appearance; the light appearances use the same
// hues on an inverted neutral scale. Every text colour meets WCAG AA (4.5:1) on every
// surface (body text AAA, 7:1), including Increase Contrast. See docs/DESIGN-SYSTEM.md.

/// The reader's appearance choice. Independent of the edition.
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

/// The website's two editorial editions. Independent of the appearance.
enum EditionChoice: String, CaseIterable, Identifiable {
    case future, classic

    var id: String { rawValue }
    var title: String { self == .future ? "Future" : "Classic" }
    var editionName: String { self == .future ? "Future Edition" : "Classic Edition" }
    var summary: String {
        self == .future
            ? "The futuristic HCG logo, signal accents and the command-centre masthead."
            : "The classic metallic HCG logo and black-and-white editorial reading."
    }
    /// Logo image set (transparent, with Light and Dark variants).
    var logoAsset: String { self == .future ? "HCGFutureLogo" : "HCGClassicLogo" }
    /// Width ÷ height of the logo artwork, so it is never stretched.
    var logoAspectRatio: CGFloat { self == .future ? 1200.0 / 496.0 : 396.0 / 167.0 }
    /// Card corner radius: the website uses 4 px (Future) and 2 px (Classic).
    var cornerRadius: CGFloat { self == .future ? 4 : 2 }

    static let storageKey = "edition"
    /// The website opens in the Future Edition.
    static let defaultEdition = EditionChoice.future
    /// The edition currently selected (read by dynamic colours at resolution time).
    static var current: EditionChoice {
        UserDefaults.standard.string(forKey: storageKey).flatMap(EditionChoice.init(rawValue:)) ?? defaultEdition
    }
}

/// Colour tokens. Values: (light, dark, light + Increase Contrast, dark + Increase Contrast).
enum PaletteToken {
    case background, surface, elevated, primaryText, secondaryText, silver, separator
    case accent, onAccent, breaking, onBreaking, warning, destructive

    func values(_ edition: EditionChoice) -> (UInt32, UInt32, UInt32, UInt32) {
        switch edition {
        case .classic:
            switch self {
            case .background: return (0xFFFFFF, 0x000000, 0xFFFFFF, 0x000000)
            case .surface: return (0xF3F3F5, 0x020203, 0xF3F3F5, 0x020203)
            case .elevated: return (0xFFFFFF, 0x0A0B0D, 0xFFFFFF, 0x0A0B0D)
            case .primaryText: return (0x030304, 0xEDEEF1, 0x000000, 0xFFFFFF)
            case .secondaryText: return (0x46484B, 0x95989D, 0x262829, 0xC5C6C9)
            case .silver: return (0x5C5E61, 0xC7CBCE, 0x37383A, 0xDDE0E2)
            case .separator: return (0xE0E0E0, 0x1F1F1F, 0xB2B2B2, 0x4C4C4C)
            case .accent: return (0x006071, 0x8FCDD8, 0x00434F, 0xB1DCE4)
            case .onAccent: return (0xFBFCFD, 0x0C0D0F, 0xFBFCFD, 0x0C0D0F)
            case .breaking: return (0xC2181D, 0xD4302E, 0xC2181D, 0xD4302E)
            case .onBreaking: return (0xFEFBFB, 0xFCF7F7, 0xFEFBFB, 0xFCF7F7)
            case .warning: return (0x845000, 0xEBB25F, 0x845000, 0xEBB25F)
            case .destructive: return (0xB7191C, 0xED756E, 0xB7191C, 0xED756E)
            }
        case .future:
            switch self {
            case .background: return (0xF5F7F9, 0x050506, 0xF5F7F9, 0x050506)
            case .surface: return (0xE9EBEE, 0x111213, 0xE9EBEE, 0x111213)
            case .elevated: return (0xFFFFFF, 0x1D1F23, 0xFFFFFF, 0x1D1F23)
            case .primaryText: return (0x0E0F11, 0xEDEEF1, 0x000000, 0xFFFFFF)
            case .secondaryText: return (0x505357, 0x95989D, 0x2C2E30, 0xC5C6C9)
            case .silver: return (0x616368, 0xC7CBCE, 0x3A3B3E, 0xDDE0E2)
            case .separator: return (0xDCDEE0, 0x1C1C1C, 0xACADAE, 0x505051)
            case .accent: return (0x006678, 0x8FCDD8, 0x004754, 0xB1DCE4)
            case .onAccent: return (0xFBFCFD, 0x0C0D0F, 0xFBFCFD, 0x0C0D0F)
            case .breaking: return (0xC2181D, 0xD4302E, 0xC2181D, 0xD4302E)
            case .onBreaking: return (0xFEFBFB, 0xFCF7F7, 0xFEFBFB, 0xFCF7F7)
            case .warning: return (0x845000, 0xEBB25F, 0x845000, 0xEBB25F)
            case .destructive: return (0xB7191C, 0xED756E, 0xB7191C, 0xED756E)
            }
        }
    }
}

extension UIColor {
    /// A colour that follows the edition, Light/Dark and Increase Contrast.
    convenience init(token: PaletteToken) {
        self.init { traits in
            let (light, dark, lightHC, darkHC) = token.values(EditionChoice.current)
            let high = traits.accessibilityContrast == .high
            let value = traits.userInterfaceStyle == .dark ? (high ? darkHC : dark) : (high ? lightHC : light)
            return UIColor(red: CGFloat((value >> 16) & 0xff) / 255, green: CGFloat((value >> 8) & 0xff) / 255,
                           blue: CGFloat(value & 0xff) / 255, alpha: 1)
        }
    }
}

/// Semantic colours (edition- and appearance-aware).
enum Palette {
    static let background = Color(uiColor: UIColor(token: .background))
    static let surface = Color(uiColor: UIColor(token: .surface))
    static let elevated = Color(uiColor: UIColor(token: .elevated))
    static let primaryText = Color(uiColor: UIColor(token: .primaryText))
    static let secondaryText = Color(uiColor: UIColor(token: .secondaryText))
    /// Silver / metal: rules, hairlines, category eyebrows and quiet labels.
    static let silver = Color(uiColor: UIColor(token: .silver))
    static let separator = Color(uiColor: UIColor(token: .separator))
    /// The website's signal colour: actions, links and status only.
    static let accent = Color(uiColor: UIColor(token: .accent))
    /// Text on an accent-filled control.
    static let onAccent = Color(uiColor: UIColor(token: .onAccent))
    /// The breaking-news bar.
    static let breaking = Color(uiColor: UIColor(token: .breaking))
    static let onBreaking = Color(uiColor: UIColor(token: .onBreaking))
    static let warning = Color(uiColor: UIColor(token: .warning))
    static let destructive = Color(uiColor: UIColor(token: .destructive))
    /// The masthead sits on the page background (no black band behind the logo).
    static let masthead = background
}

// MARK: - Fonts

/// The website's typefaces, bundled under the SIL Open Font License (Resources/Fonts):
/// Newsreader (serif headlines, the italic "News" wordmark, article text) and Manrope
/// (labels and metadata). If a font can't be loaded, the system serif or sans is used.
enum BrandFonts {
    @MainActor private static var registered = false

    /// Registers the bundled fonts for this process (called once at launch, before any view).
    @MainActor static func register() {
        guard !registered else { return }
        registered = true
        let urls = (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? [])
            + (Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? [])
        for url in urls where url.lastPathComponent.hasPrefix("Newsreader") || url.lastPathComponent.hasPrefix("Manrope") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// The bundled font names that loaded, checked once (after `register()`, at first use).
    private static let loadedNames: Set<String> = {
        let names = [Font.Weight.regular, .medium, .semibold, .bold].flatMap {
            [newsreader($0), newsreader($0, italic: true), manrope($0)]
        }
        return Set(names.filter { UIFont(name: $0, size: 12) != nil })
    }()

    static func available(_ name: String) -> Bool { loadedNames.contains(name) }

    static func newsreader(_ weight: Font.Weight, italic: Bool = false) -> String {
        let family = italic ? "NewsreaderItalic" : "NewsreaderRoman"
        switch weight {
        case .bold, .heavy, .black: return family + "-Bold"
        case .semibold: return family + "-SemiBold"
        case .medium: return family + "-Medium"
        default: return family + "-Regular"
        }
    }

    static func manrope(_ weight: Font.Weight) -> String {
        switch weight {
        case .bold, .heavy, .black: return "Manrope-Bold"
        case .semibold: return "Manrope-SemiBold"
        case .medium: return "Manrope-Medium"
        default: return "Manrope-Regular"
        }
    }

    /// Default point sizes of the text styles at the standard Dynamic Type size.
    static func baseSize(_ style: Font.TextStyle) -> CGFloat {
        switch style {
        case .largeTitle: 34
        case .title: 28
        case .title2: 22
        case .title3: 20
        case .headline, .body: 17
        case .callout: 16
        case .subheadline: 15
        case .footnote: 13
        case .caption: 12
        case .caption2: 11
        @unknown default: 17
        }
    }
}

/// Typography. Every style scales with Dynamic Type (`relativeTo:`).
enum Typography {
    /// Editorial serif headline (Newsreader).
    static func headline(_ style: Font.TextStyle, weight: Font.Weight = .semibold) -> Font {
        let name = BrandFonts.newsreader(weight)
        guard BrandFonts.available(name) else { return .system(style, design: .serif, weight: weight) }
        return .custom(name, size: BrandFonts.baseSize(style), relativeTo: style)
    }

    /// Italic serif, as in the website's "News" wordmark and taglines.
    static func serifItalic(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let name = BrandFonts.newsreader(weight, italic: true)
        guard BrandFonts.available(name) else { return .system(style, design: .serif, weight: weight).italic() }
        return .custom(name, size: BrandFonts.baseSize(style), relativeTo: style)
    }

    /// Manrope, the website's interface face.
    static func sans(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        let name = BrandFonts.manrope(weight)
        guard BrandFonts.available(name) else { return .system(style, weight: weight) }
        return .custom(name, size: BrandFonts.baseSize(style), relativeTo: style)
    }

    static func body(_ typeface: ArticleTypeface) -> Font {
        typeface == .serif ? headline(.body, weight: .regular) : sans(.body)
    }

    /// The website's uppercase "eyebrow" label (category, edition, BREAKING).
    static var kicker: Font { sans(.caption, weight: .semibold) }
    static var meta: Font { sans(.footnote) }
    static var sectionTitle: Font { sans(.footnote, weight: .bold) }
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
    @AppStorage(EditionChoice.storageKey) private var editionRaw = EditionChoice.defaultEdition.rawValue

    func body(content: Content) -> some View {
        content
            // Colours resolve the edition when drawn; a new identity redraws everything
            // (navigation state lives in the Router, so it is kept).
            .id(editionRaw)
            .environment(\.edition, EditionChoice(rawValue: editionRaw) ?? .defaultEdition)
            .tint(Palette.accent)
            .preferredColorScheme((AppearanceChoice(rawValue: appearanceRaw) ?? .system).colorScheme)
    }
}

private struct EditionKey: EnvironmentKey {
    static let defaultValue = EditionChoice.defaultEdition
}

extension EnvironmentValues {
    /// The selected editorial edition.
    var edition: EditionChoice {
        get { self[EditionKey.self] }
        set { self[EditionKey.self] = newValue }
    }
}

extension View {
    func hcgThemed() -> some View { modifier(ThemedRoot()) }

    func screenBackground() -> some View {
        scrollContentBackground(.hidden).background(Palette.background.ignoresSafeArea())
    }

    /// A quiet card surface with a hairline border.
    func cardSurface(cornerRadius: CGFloat = 8) -> some View {
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
    /// The website's article date: "27 Nov 2026" (day, short month, year).
    static func article(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year())
    }

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
