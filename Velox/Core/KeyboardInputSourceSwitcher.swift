import Carbon
import Foundation

enum KeyboardInputSourceSwitcher {
    private static let preferredEnglishInputSourceIDs = [
        "com.apple.keylayout.ABC",
        "com.apple.keylayout.US"
    ]

    @MainActor
    static func switchToEnglish() {
        for inputSourceID in preferredEnglishInputSourceIDs where selectInputSource(id: inputSourceID) {
            return
        }

        selectFirstASCIICapableInputSource()
    }

    @discardableResult
    private static func selectInputSource(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID: id] as CFDictionary
        guard let inputSources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }

        for inputSource in inputSources where TISSelectInputSource(inputSource) == noErr {
            return true
        }

        return false
    }

    @discardableResult
    private static func selectFirstASCIICapableInputSource() -> Bool {
        let filter = [kTISPropertyInputSourceIsASCIICapable: true] as CFDictionary
        guard let inputSources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource] else {
            return false
        }

        for inputSource in inputSources where TISSelectInputSource(inputSource) == noErr {
            return true
        }

        return false
    }
}
