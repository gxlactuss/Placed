import SwiftUI

struct Palette: Hashable {
    let ground: Color
    let surface: Color
    let elevated: Color

    let text: Color
    let muted: Color

    let accent: Color
    let accent300: Color
    let accent400: Color
    let accent700: Color
    let accentSection: Color
    let onAccent: Color

    let easy: Color
    let medium: Color
    let hard: Color

    let border: Color
    let borderStrong: Color

    let colorScheme: ColorScheme
}

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

    private static let darkBorder = Color.white.opacity(0.08)
    private static let darkBorderStrong = Color.white.opacity(0.16)
    private static let lightBorder = Color.black.opacity(0.10)
    private static let lightBorderStrong = Color.black.opacity(0.18)

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
        onAccent: Color(hex: 0x090A0D),
        easy: Color(hex: 0x84B394),
        medium: Color(hex: 0xC9A15E),
        hard: Color(hex: 0xC97F74),
        border: darkBorder,
        borderStrong: darkBorderStrong,
        colorScheme: .dark
    )

    private static let neonPalette = Palette(
        ground: Color(hex: 0x0F1B2D),
        surface: Color(hex: 0x172536),
        elevated: Color(hex: 0x21324A),
        text: Color(hex: 0xEDF1F5),
        muted: Color(hex: 0x8C9BAC),
        accent: Color(hex: 0x5FD9A4),
        accent300: Color(hex: 0xA6ECCB),
        accent400: Color(hex: 0x7FE3B6),
        accent700: Color(hex: 0x2E9B78),
        accentSection: Color(hex: 0x102A20),
        onAccent: Color(hex: 0x081425),
        easy: Color(hex: 0x84B394),
        medium: Color(hex: 0xC9A15E),
        hard: Color(hex: 0xD78C81),
        border: darkBorder,
        borderStrong: darkBorderStrong,
        colorScheme: .dark
    )

    private static let coralDrivePalette = Palette(
        ground: Color(hex: 0xFAF9F6),
        surface: Color(hex: 0xF3F0EA),
        elevated: Color(hex: 0xEBE6DE),
        text: Color(hex: 0x2A1B3D),
        muted: Color(hex: 0x596786),
        accent: Color(hex: 0xE35144),
        accent300: Color(hex: 0xA4433B),
        accent400: Color(hex: 0xAA1E13),
        accent700: Color(hex: 0xB23F30),
        accentSection: Color(hex: 0xF3D9D4),
        onAccent: Color(hex: 0x221334),
        easy: Color(hex: 0x1C6B46),
        medium: Color(hex: 0x815505),
        hard: Color(hex: 0xA53728),
        border: lightBorder,
        borderStrong: lightBorderStrong,
        colorScheme: .light
    )

    private static let paperTrailPalette = Palette(
        ground: Color(hex: 0xF5F7F9),
        surface: Color(hex: 0xEDF0F3),
        elevated: Color(hex: 0xE2E8ED),
        text: Color(hex: 0x0F1B2D),
        muted: Color(hex: 0x5C6877),
        accent: Color(hex: 0x2F8FA6),
        accent300: Color(hex: 0x33707E),
        accent400: Color(hex: 0x19667A),
        accent700: Color(hex: 0x1C5566),
        accentSection: Color(hex: 0xDDEBEE),
        onAccent: Color(hex: 0x0F1B2D),
        easy: Color(hex: 0x1A6A45),
        medium: Color(hex: 0x815505),
        hard: Color(hex: 0xA53728),
        border: lightBorder,
        borderStrong: lightBorderStrong,
        colorScheme: .light
    )
}

@Observable
final class ThemeStore {

    static let shared = ThemeStore()

    private static let selectionKey = "selectedTheme"
    private static let dynamicKey = "dynamicTheme"

    private static let dayHour = 7
    private static let nightHour = 19

    var selection: AppTheme {
        didSet {
            guard selection != oldValue else { return }
            UserDefaults.standard.set(selection.rawValue, forKey: Self.selectionKey)
            refresh()
        }
    }

    var isDynamic: Bool {
        didSet {
            guard isDynamic != oldValue else { return }
            UserDefaults.standard.set(isDynamic, forKey: Self.dynamicKey)
            refresh()
            scheduleNextFlip()
        }
    }

    private(set) var activeTheme: AppTheme = .amber

    private var flipGeneration = 0

    init() {
        let defaults = UserDefaults.standard
        let raw = defaults.string(forKey: Self.selectionKey)
        selection = raw.flatMap(AppTheme.init(rawValue:)) ?? .amber
        isDynamic = defaults.bool(forKey: Self.dynamicKey)
        activeTheme = Self.resolve(selection: selection, isDynamic: isDynamic)
        scheduleNextFlip()
    }

    func refresh() {
        let resolved = Self.resolve(selection: selection, isDynamic: isDynamic)
        guard resolved != activeTheme else { return }
        activeTheme = resolved
        PPAppearance.configure()
    }

    private static func resolve(selection: AppTheme, isDynamic: Bool) -> AppTheme {
        isDynamic ? themeForNow() : selection
    }

    static func themeForNow(date: Date = Date(), calendar: Calendar = .current) -> AppTheme {
        let hour = calendar.component(.hour, from: date)
        return (dayHour..<nightHour).contains(hour) ? .coralDrive : .amber
    }

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
