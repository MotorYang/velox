import AppKit
import Combine
import SwiftUI

enum VeloxAppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

@MainActor
final class VeloxSettings: ObservableObject {
    static let shared = VeloxSettings()

    @Published var terminalFontName: String {
        didSet { defaults.set(terminalFontName, forKey: Keys.terminalFontName) }
    }

    @Published var terminalFontSize: Double {
        didSet { defaults.set(clamp(terminalFontSize, min: 9, max: 32), forKey: Keys.terminalFontSize) }
    }

    @Published var defaultWindowWidth: Double {
        didSet { defaults.set(clamp(defaultWindowWidth, min: 720, max: 2200), forKey: Keys.defaultWindowWidth) }
    }

    @Published var defaultWindowHeight: Double {
        didSet { defaults.set(clamp(defaultWindowHeight, min: 420, max: 1400), forKey: Keys.defaultWindowHeight) }
    }

    @Published var appearanceMode: VeloxAppearanceMode {
        didSet { defaults.set(appearanceMode.rawValue, forKey: Keys.appearanceMode) }
    }

    @Published var isTransparent: Bool {
        didSet { defaults.set(isTransparent, forKey: Keys.isTransparent) }
    }

    @Published var transparency: Double {
        didSet { defaults.set(clamp(transparency, min: 0.05, max: 0.55), forKey: Keys.transparency) }
    }

    private let defaults: UserDefaults

    private init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        terminalFontName = defaults.string(forKey: Keys.terminalFontName) ?? TerminalFontProvider.defaultFontName()

        let savedFontSize = defaults.double(forKey: Keys.terminalFontSize)
        terminalFontSize = savedFontSize == 0 ? 13 : savedFontSize

        let savedWidth = defaults.double(forKey: Keys.defaultWindowWidth)
        defaultWindowWidth = savedWidth == 0 ? 940 : savedWidth

        let savedHeight = defaults.double(forKey: Keys.defaultWindowHeight)
        defaultWindowHeight = savedHeight == 0 ? 580 : savedHeight

        let savedAppearance = defaults.string(forKey: Keys.appearanceMode)
        appearanceMode = VeloxAppearanceMode(rawValue: savedAppearance ?? "") ?? .dark
        isTransparent = defaults.object(forKey: Keys.isTransparent) as? Bool ?? false

        let savedTransparency = defaults.double(forKey: Keys.transparency)
        transparency = savedTransparency == 0 ? 0.18 : savedTransparency
    }

    var terminalFont: NSFont {
        TerminalFontProvider.font(named: terminalFontName, size: clamp(terminalFontSize, min: 9, max: 32))
    }

    var windowSize: NSSize {
        NSSize(
            width: clamp(defaultWindowWidth, min: 720, max: 2200),
            height: clamp(defaultWindowHeight, min: 420, max: 1400)
        )
    }

    var effectiveAlpha: CGFloat {
        isTransparent ? CGFloat(1 - transparency) : 1
    }

    var terminalBackgroundColor: NSColor {
        switch appearanceMode {
        case .light:
            return NSColor(calibratedRed: 0.955, green: 0.957, blue: 0.95, alpha: effectiveAlpha)
        case .system, .dark:
            return NSColor(calibratedRed: 0.035, green: 0.038, blue: 0.04, alpha: effectiveAlpha)
        }
    }

    var terminalForegroundColor: NSColor {
        switch appearanceMode {
        case .light:
            return NSColor(calibratedWhite: 0.16, alpha: 1)
        case .system, .dark:
            return NSColor(calibratedWhite: 0.86, alpha: 1)
        }
    }

    var backgroundGradientColors: [Color] {
        switch appearanceMode {
        case .light:
            return [
                Color(red: 0.955, green: 0.957, blue: 0.95).opacity(effectiveAlpha),
                Color(red: 0.89, green: 0.91, blue: 0.9).opacity(effectiveAlpha)
            ]
        case .system, .dark:
            return [
                Color(red: 0.035, green: 0.038, blue: 0.04).opacity(effectiveAlpha),
                Color(red: 0.055, green: 0.058, blue: 0.056).opacity(effectiveAlpha)
            ]
        }
    }

    var foregroundStyle: Color {
        appearanceMode == .light ? Color.black.opacity(0.84) : Color.white.opacity(0.9)
    }

    func apply(to window: NSWindow?, resize: Bool = false) {
        guard let window else { return }
        window.appearance = appearanceMode.nsAppearance
        window.isOpaque = !isTransparent
        window.backgroundColor = terminalBackgroundColor

        if isTransparent {
            window.titlebarAppearsTransparent = true
            window.alphaValue = 1
        } else {
            window.titlebarAppearsTransparent = false
        }

        if resize {
            window.setContentSize(windowSize)
        }
    }

    private func clamp(_ value: Double, min minValue: Double, max maxValue: Double) -> Double {
        min(max(value, minValue), maxValue)
    }
}

private enum Keys {
    static let terminalFontName = "Velox.Settings.terminalFontName"
    static let terminalFontSize = "Velox.Settings.terminalFontSize"
    static let defaultWindowWidth = "Velox.Settings.defaultWindowWidth"
    static let defaultWindowHeight = "Velox.Settings.defaultWindowHeight"
    static let appearanceMode = "Velox.Settings.appearanceMode"
    static let isTransparent = "Velox.Settings.isTransparent"
    static let transparency = "Velox.Settings.transparency"
}
