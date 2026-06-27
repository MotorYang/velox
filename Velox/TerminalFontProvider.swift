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
