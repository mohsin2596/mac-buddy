import AppKit
import SwiftUI

// MARK: - Color helpers

struct RGB: Equatable {
    var r: Double, g: Double, b: Double

    init(r: Double, g: Double, b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init?(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        r = Double((v >> 16) & 0xFF) / 255
        g = Double((v >> 8) & 0xFF) / 255
        b = Double(v & 0xFF) / 255
    }

    init(_ color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .orange
        r = Double(ns.redComponent); g = Double(ns.greenComponent); b = Double(ns.blueComponent)
    }

    var hex: String {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255).rounded()) }
        return String(format: "%02X%02X%02X", c(r), c(g), c(b))
    }

    var color: Color { Color(red: r, green: g, blue: b) }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r: r + (other.r - r) * t, g: g + (other.g - g) * t, b: b + (other.b - b) * t)
    }

    static let white = RGB(r: 1, g: 1, b: 1)
}

struct ColorPreset: Identifiable {
    let name: String
    let body: String
    let limb: String
    var id: String { name }

    static let all = [
        ColorPreset(name: "Claude", body: "DE7D5C", limb: "B85C40"),
        ColorPreset(name: "Mint", body: "7DD3B0", limb: "4FA585"),
        ColorPreset(name: "Sky", body: "7DB8F0", limb: "4F86C0"),
        ColorPreset(name: "Grape", body: "B38BE8", limb: "8560BA"),
        ColorPreset(name: "Bubblegum", body: "F59AC4", limb: "C66A95"),
        ColorPreset(name: "Lemon", body: "F2D45C", limb: "C4A530"),
        ColorPreset(name: "Forest", body: "6FA86A", limb: "487A44"),
        ColorPreset(name: "Snow", body: "EDEFF4", limb: "AEB4C2"),
        ColorPreset(name: "Midnight", body: "4A5070", limb: "2E3348"),
    ]
}

enum Accessory: String, CaseIterable, Identifiable {
    case none, partyHat, topHat, crown, bow, flower, headphones, glasses

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: "None"
        case .partyHat: "Party Hat"
        case .topHat: "Top Hat"
        case .crown: "Crown"
        case .bow: "Bow"
        case .flower: "Flower"
        case .headphones: "Headphones"
        case .glasses: "Glasses"
        }
    }
}

/// Everything about how the character is drawn.
struct BuddyStyle {
    var body = RGB(hex: "DE7D5C")!
    var limb = RGB(hex: "B85C40")!
    var accessory = Accessory.none
    var antenna = true
    var cheeks = true
    var pupilScale = 1.0
    var roundness = 36.0
    /// Pupil offset toward the cursor, or nil when cursor-following is off.
    var look: CGSize?

    var bodyLight: Color { body.mixed(with: .white, 0.3).color }
}

/// Maps a vector from the eyes to the cursor (SwiftUI orientation, y down) to a pupil offset.
func lookOffset(dx: Double, dy: Double, reach: Double) -> CGSize {
    let dist = hypot(dx, dy)
    guard dist > 0.5 else { return .zero }
    let k = min(1, dist / reach)
    return CGSize(width: dx / dist * 4 * k, height: dy / dist * 3.5 * k)
}

// MARK: - Settings store

@MainActor
final class BuddySettings: ObservableObject {
    // Appearance
    @Published var scale = 1.0 { didSet { save(scale, "scale") } }
    @Published var opacity = 1.0 { didSet { save(opacity, "opacity") } }
    @Published var bodyHex = "DE7D5C" { didSet { save(bodyHex, "bodyHex") } }
    @Published var limbHex = "B85C40" { didSet { save(limbHex, "limbHex") } }
    @Published var accessory = Accessory.none { didSet { save(accessory.rawValue, "accessory") } }
    @Published var showAntenna = true { didSet { save(showAntenna, "showAntenna") } }
    @Published var showCheeks = true { didSet { save(showCheeks, "showCheeks") } }
    @Published var pupilScale = 1.0 { didSet { save(pupilScale, "pupilScale") } }
    @Published var roundness = 36.0 { didSet { save(roundness, "roundness") } }

    // Behavior
    @Published var followCursor = false { didSet { save(followCursor, "followCursor") } }
    @Published var animationSpeed = 1.0 { didSet { save(animationSpeed, "animationSpeed") } }
    @Published var clickReactions = true { didSet { save(clickReactions, "clickReactions") } }
    @Published var customPhrases = "" { didSet { save(customPhrases, "customPhrases") } }
    @Published var sleepEnabled = true { didSet { save(sleepEnabled, "sleepEnabled") } }
    @Published var sleepMinutes = 10.0 { didSet { save(sleepMinutes, "sleepMinutes") } }
    @Published var alwaysOnTop = true { didSet { save(alwaysOnTop, "alwaysOnTop") } }
    @Published var allSpaces = true { didSet { save(allSpaces, "allSpaces") } }

    // Claude Code
    @Published var showBubble = true { didSet { save(showBubble, "showBubble") } }
    @Published var showProject = true { didSet { save(showProject, "showProject") } }
    @Published var celebrate = true { didSet { save(celebrate, "celebrate") } }
    @Published var hideWhenIdle = false { didSet { save(hideWhenIdle, "hideWhenIdle") } }
    @Published var projectFilter = "" { didSet { save(projectFilter, "projectFilter") } }

    private static let prefix = "buddy."

    init() { load() }

    private func load() {
        let d = UserDefaults.standard
        func v<T>(_ key: String, _ fallback: T) -> T { d.object(forKey: Self.prefix + key) as? T ?? fallback }
        scale = v("scale", 1.0)
        opacity = v("opacity", 1.0)
        bodyHex = v("bodyHex", "DE7D5C")
        limbHex = v("limbHex", "B85C40")
        accessory = Accessory(rawValue: v("accessory", "none")) ?? .none
        showAntenna = v("showAntenna", true)
        showCheeks = v("showCheeks", true)
        pupilScale = v("pupilScale", 1.0)
        roundness = v("roundness", 36.0)
        followCursor = v("followCursor", false)
        animationSpeed = v("animationSpeed", 1.0)
        clickReactions = v("clickReactions", true)
        customPhrases = v("customPhrases", "")
        sleepEnabled = v("sleepEnabled", true)
        sleepMinutes = v("sleepMinutes", 10.0)
        alwaysOnTop = v("alwaysOnTop", true)
        allSpaces = v("allSpaces", true)
        showBubble = v("showBubble", true)
        showProject = v("showProject", true)
        celebrate = v("celebrate", true)
        hideWhenIdle = v("hideWhenIdle", false)
        projectFilter = v("projectFilter", "")
    }

    func resetToDefaults() {
        let d = UserDefaults.standard
        for key in d.dictionaryRepresentation().keys where key.hasPrefix(Self.prefix) {
            d.removeObject(forKey: key)
        }
        load()
    }

    private func save(_ value: Any, _ key: String) {
        UserDefaults.standard.set(value, forKey: Self.prefix + key)
    }

    // MARK: Derived

    var body: RGB { RGB(hex: bodyHex) ?? RGB(hex: "DE7D5C")! }
    var limb: RGB { RGB(hex: limbHex) ?? RGB(hex: "B85C40")! }

    var phrases: [String] {
        customPhrases.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    func style(look: CGSize?) -> BuddyStyle {
        BuddyStyle(body: body, limb: limb, accessory: accessory, antenna: showAntenna,
                   cheeks: showCheeks, pupilScale: pupilScale, roundness: roundness,
                   look: followCursor ? look : nil)
    }
}
