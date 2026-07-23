import SwiftUI

// MARK: - Palette
//
// A theme is nothing but a full set of token values. The screens never read a
// palette directly — they read `Color.ppGround` and friends, which resolve
// through `ThemeStore.shared`. This struct is the single place a theme's colours
// are declared, and the only thing the picker's live preview reads explicitly.

/// The resolved colours for one theme. Depth cues (`border`) are stored as
/// finished colours, not opacities, because a light theme rules its hairlines in
/// black where a dark theme rules them in white.
struct Palette: Hashable {
    let ground: Color
    let surface: Color
    let elevated: Color

    let text: Color
    let muted: Color

    /// The loud accent, used for one element per screen and for filled controls.
    let accent: Color
    /// Lighter/darker accent tints. On dark themes these read lighter (accent
    /// text on ink); on light themes they read darker (accent text on paper).
    let accent300: Color
    let accent400: Color
    let accent700: Color
    /// The dim wash behind the hero card — a dark tint of the accent on dark
    /// themes, a pale tint on light ones.
    let accentSection: Color
    /// The mark colour that sits *on top of* the accent (button labels, ticks).
    /// Always the theme's ink, which is the ground on dark themes but the text
    /// colour on light ones — so it can't just be `ground`.
    let onAccent: Color

    let easy: Color
    let medium: Color
    let hard: Color

    let border: Color
    let borderStrong: Color

    /// Drives `preferredColorScheme`, so system controls (keyboard, tab bar
    /// glass, menus) render for the right mode.
    let colorScheme: ColorScheme
}

// MARK: - Themes

/// The four shipped themes. `rawValue` is the persistence key, so don't rename
/// a case once it has shipped.
enum AppTheme: String, CaseIterable, Identifiable, Hashable {
    case amber
    case neon
    case coralDrive = "coral-drive"
    case paperTrail = "paper-trail"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .amber: "Amber"
        case .neon: "Neon"
        case .coralDrive: "Coral Drive"
        case .paperTrail: "Paper Trail"
        }
    }

    var palette: Palette {
        switch self {
        case .amber: Self.amberPalette
        case .neon: Self.neonPalette
        case .coralDrive: Self.coralDrivePalette
        case .paperTrail: Self.paperTrailPalette
        }
    }

    // Hairlines: the one depth cue in the system. White on dark grounds, black
    // on light ones.
    private static let darkBorder = Color.white.opacity(0.08)
    private static let darkBorderStrong = Color.white.opacity(0.16)
    private static let lightBorder = Color.black.opacity(0.10)
    private static let lightBorderStrong = Color.black.opacity(0.18)

    /// Warm dark — the original Ledger palette, unchanged.
    private static let amberPalette = Palette(
        ground: Color(hex: 0x0E0F12),
        surface: Color(hex: 0x17181D),
        elevated: Color(hex: 0x202127),
        text: Color(hex: 0xF2F1EC),
        muted: Color(hex: 0x8E9099),
        accent: Color(hex: 0xE8A33D),
        accent300: Color(hex: 0xF2CD8C),
        accent400: Color(hex: 0xECB55E),
        accent700: Color(hex: 0x8F6320),
        accentSection: Color(hex: 0x261E10),
        onAccent: Color(hex: 0x0E0F12),
        easy: Color(hex: 0x84B394),
        medium: Color(hex: 0xC9A15E),
        hard: Color(hex: 0xC97F74),
        border: darkBorder,
        borderStrong: darkBorderStrong,
        colorScheme: .dark
    )

    /// Cool dark — a bright mint accent on a navy ink ground.
    private static let neonPalette = Palette(
        ground: Color(hex: 0x0F1B2D),
        surface: Color(hex: 0x172536),
        elevated: Color(hex: 0x21324A),
        text: Color(hex: 0xEDF1F5),
        muted: Color(hex: 0x8695A6),
        accent: Color(hex: 0x5FD9A4),
        accent300: Color(hex: 0xA6ECCB),
        accent400: Color(hex: 0x7FE3B6),
        accent700: Color(hex: 0x2E9B78),
        accentSection: Color(hex: 0x102A20),
        onAccent: Color(hex: 0x0F1B2D),
        easy: Color(hex: 0x84B394),
        medium: Color(hex: 0xC9A15E),
        hard: Color(hex: 0xC97F74),
        border: darkBorder,
        borderStrong: darkBorderStrong,
        colorScheme: .dark
    )

    /// Warm light — plum ink and a coral accent on warm paper. Depth inverts:
    /// cards recede a touch below the ground and hairlines rule in black.
    private static let coralDrivePalette = Palette(
        ground: Color(hex: 0xFAF9F6),
        surface: Color(hex: 0xF3F0EA),
        elevated: Color(hex: 0xEBE6DE),
        text: Color(hex: 0x2A1B3D),
        muted: Color(hex: 0x5C6B8A),
        accent: Color(hex: 0xFF6B5B),
        accent300: Color(hex: 0xFF9488),
        accent400: Color(hex: 0xD64C3C),
        accent700: Color(hex: 0xB23F30),
        accentSection: Color(hex: 0xF3D9D4),
        onAccent: Color(hex: 0x2A1B3D),
        easy: Color(hex: 0x3F8A63),
        medium: Color(hex: 0xB07D2F),
        hard: Color(hex: 0xC0503F),
        border: lightBorder,
        borderStrong: lightBorderStrong,
        colorScheme: .light
    )

    /// Cool light — the light sibling of Neon: navy ink and a teal accent on
    /// cool paper.
    private static let paperTrailPalette = Palette(
        ground: Color(hex: 0xF5F7F9),
        surface: Color(hex: 0xEDF0F3),
        elevated: Color(hex: 0xE2E8ED),
        text: Color(hex: 0x0F1B2D),
        muted: Color(hex: 0x5F6B7A),
        accent: Color(hex: 0x2F8FA6),
        accent300: Color(hex: 0x7FBCCB),
        accent400: Color(hex: 0x246E82),
        accent700: Color(hex: 0x1C5566),
        accentSection: Color(hex: 0xDDEBEE),
        onAccent: Color(hex: 0x0F1B2D),
        easy: Color(hex: 0x3F8A63),
        medium: Color(hex: 0xB07D2F),
        hard: Color(hex: 0xC0503F),
        border: lightBorder,
        borderStrong: lightBorderStrong,
        colorScheme: .light
    )
}

// MARK: - Store

/// The single source of truth for the active theme.
///
/// A singleton because the `Color.pp*` tokens are static and have no view to
/// read an environment from — they resolve through `shared`. It is still
/// `@Observable`, so any view body that touches a token (directly or via a
/// `PP*` component) re-renders when the theme changes. Selection and the dynamic
/// flag persist in `UserDefaults`, matching `SolvedStore`/`QuizProgressStore`.
///
/// Two knobs the UI drives, and one derived value everything else reads:
/// - `selection` — the theme the user picked by hand.
/// - `isDynamic` — when on, the theme follows the clock instead of `selection`
///   (Coral Drive by day, Amber after dark).
/// - `activeTheme` — what's actually applied, and what the tokens resolve
///   through. Stored rather than computed so a clock-driven flip repaints.
@Observable
final class ThemeStore {

    static let shared = ThemeStore()

    private static let selectionKey = "selectedTheme"
    private static let dynamicKey = "dynamicTheme"

    /// Boundary hours for the dynamic schedule: Coral Drive in `[day, night)`,
    /// Amber otherwise.
    private static let dayHour = 7
    private static let nightHour = 19

    /// The hand-picked theme. Ignored while `isDynamic` is on, but remembered so
    /// turning dynamic back off restores it.
    var selection: AppTheme {
        didSet {
            guard selection != oldValue else { return }
            UserDefaults.standard.set(selection.rawValue, forKey: Self.selectionKey)
            refresh()
        }
    }

    /// When on, `activeTheme` tracks the time of day rather than `selection`.
    var isDynamic: Bool {
        didSet {
            guard isDynamic != oldValue else { return }
            UserDefaults.standard.set(isDynamic, forKey: Self.dynamicKey)
            refresh()
            scheduleNextFlip()
        }
    }

    /// The theme actually in effect — every `Color.pp*` token resolves through
    /// this.
    private(set) var activeTheme: AppTheme = .amber

    /// Cancels a pending scheduled flip when the schedule changes.
    private var flipGeneration = 0

    init() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: Self.selectionKey)
        selection = raw.flatMap(AppTheme.init(rawValue:)) ?? .amber
        isDynamic = defaults.bool(forKey: Self.dynamicKey)
        activeTheme = Self.resolve(selection: selection, isDynamic: isDynamic)
        scheduleNextFlip()
    }

    /// Recomputes the active theme now. Cheap and idempotent — call it on app
    /// foreground so a boundary crossed while suspended is picked up.
    func refresh() {
        let resolved = Self.resolve(selection: selection, isDynamic: isDynamic)
        guard resolved != activeTheme else { return }
        activeTheme = resolved
        // The tab/nav bars are UIKit appearance proxies, not SwiftUI, so they
        // don't observe the token change — reapply them by hand.
        PPAppearance.configure()
    }

    private static func resolve(selection: AppTheme, isDynamic: Bool) -> AppTheme {
        isDynamic ? themeForNow() : selection
    }

    /// Coral Drive from 07:00 up to 19:00, Amber the rest of the day.
    static func themeForNow(date: Date = Date(), calendar: Calendar = .current) -> AppTheme {
        let hour = calendar.component(.hour, from: date)
        return (dayHour..<nightHour).contains(hour) ? .coralDrive : .amber
    }

    /// Schedules a single refresh at the next 07:00/19:00 boundary, which then
    /// chains the following one — no periodic polling, nothing kept awake. The
    /// generation token invalidates any flip still pending from an old schedule.
    private func scheduleNextFlip() {
        flipGeneration &+= 1
        guard isDynamic else { return }
        let generation = flipGeneration
        let delay = Self.secondsUntilNextBoundary()
        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1) { [weak self] in
            guard let self, generation == self.flipGeneration, self.isDynamic else { return }
            self.refresh()
            self.scheduleNextFlip()
        }
    }

    static func secondsUntilNextBoundary(from date: Date = Date(), calendar: Calendar = .current) -> TimeInterval {
        for addedDays in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: addedDays, to: date) else { continue }
            for hour in [dayHour, nightHour] {
                if let boundary = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day),
                   boundary > date {
                    return boundary.timeIntervalSince(date)
                }
            }
        }
        return 3600
    }
}
