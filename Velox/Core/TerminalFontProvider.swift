import AppKit

enum TerminalFontProvider {
    private static let preferredPostScriptNames = [
        "JetBrainsMonoNF-Regular",
        "MesloLGS-NF-Regular",
        "MesloLGM-NF-Regular",
        "MesloLGL-NF-Regular",
        "HackNerdFont-Regular",
        "FiraCodeNerdFont-Regular",
        "CaskaydiaCoveNerdFont-Regular",
        "SauceCodeProNerdFont-Regular"
    ]

    static func availableMonospacedFonts() -> [NSFont] {
        let fixedPitchFonts = NSFontManager.shared.availableFonts.compactMap {
            NSFont(name: $0, size: 13)
        }
        .filter { $0.fontDescriptor.symbolicTraits.contains(.monoSpace) }

        let names = Dictionary(grouping: fixedPitchFonts, by: { $0.fontName }).compactMap { $0.value.first }
        return names.sorted {
            ($0.displayName ?? $0.fontName) < ($1.displayName ?? $1.fontName)
        }
    }

    static func defaultFontName() -> String {
        preferredFont().fontName
    }

    static func font(named fontName: String, size: Double) -> NSFont {
        if let font = NSFont(name: fontName, size: CGFloat(size)) {
            return font
        }

        return preferredFont(size: CGFloat(size))
    }

    static func preferredFont(size: CGFloat = 13) -> NSFont {
        for name in preferredPostScriptNames {
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }

        if let userFont = NSFont.userFixedPitchFont(ofSize: size) {
            return userFont
        }

        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
