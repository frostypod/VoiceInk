import ApplicationServices
import Foundation
import os

enum FocusedTextInputDetector {
    private static let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "FocusedTextInputDetector")

    enum Result: Equatable {
        case textInput
        case notTextInput
        // The check failed, timed out, or the focused element doesn't tell us enough. Callers should treat
        // this like a text input so apps with poor accessibility support still get pasted into.
        case unknown
    }

    private static let messagingTimeout: Float = 0.15

    private static let textInputRoles: Set<String> = [
        kAXTextFieldRole,
        kAXTextAreaRole,
        kAXComboBoxRole,
        "AXSearchField",
    ]

    // Only roles that clearly can't accept typing. Generic containers (AXWindow, AXGroup, AXWebArea,
    // AXUnknown) stay unknown because custom-drawn apps, games, and Electron apps often report them.
    private static let nonTextInputRoles: Set<String> = [
        kAXButtonRole,
        kAXCheckBoxRole,
        kAXRadioButtonRole,
        kAXPopUpButtonRole,
        kAXMenuButtonRole,
        kAXSliderRole,
        kAXImageRole,
        kAXStaticTextRole,
        kAXListRole,
        kAXOutlineRole,
        kAXTableRole,
        kAXRowRole,
        kAXCellRole,
        kAXColumnRole,
        kAXBrowserRole,
        kAXScrollAreaRole,
        kAXTabGroupRole,
        kAXToolbarRole,
        kAXMenuRole,
        kAXMenuItemRole,
        kAXMenuBarRole,
        kAXMenuBarItemRole,
        kAXDisclosureTriangleRole,
        kAXSplitterRole,
        "AXLink",
    ]

    static func detect() -> Result {
        guard AXIsProcessTrusted() else { return .unknown }

        let systemWide = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(systemWide, messagingTimeout)

        var focusedValue: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide, kAXFocusedUIElementAttribute as CFString, &focusedValue)
        guard focusedError == .success, let focusedValue,
            CFGetTypeID(focusedValue) == AXUIElementGetTypeID()
        else {
            logger.debug("No focused element available (AXError \(focusedError.rawValue, privacy: .public))")
            return .unknown
        }

        let element = focusedValue as! AXUIElement
        AXUIElementSetMessagingTimeout(element, messagingTimeout)

        let role = stringAttribute(kAXRoleAttribute, of: element)
        let subrole = stringAttribute(kAXSubroleAttribute, of: element)

        let result: Result
        if let role, textInputRoles.contains(role) {
            result = .textInput
        } else if subrole == kAXSearchFieldSubrole || subrole == kAXSecureTextFieldSubrole {
            result = .textInput
        } else if hasEditingSignals(element) {
            result = .textInput
        } else if let role, nonTextInputRoles.contains(role) {
            result = .notTextInput
        } else {
            result = .unknown
        }

        logger.debug(
            "Focused element role=\(role ?? "nil", privacy: .public) subrole=\(subrole ?? "nil", privacy: .public) result=\(String(describing: result), privacy: .public)"
        )
        return result
    }

    private static func hasEditingSignals(_ element: AXUIElement) -> Bool {
        if isSettable(kAXValueAttribute, of: element) || isSettable(kAXSelectedTextRangeAttribute, of: element) {
            return true
        }

        // WebKit and Chromium expose this on contenteditable content and its descendants.
        var editableAncestor: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, "AXEditableAncestor" as CFString, &editableAncestor)
            == .success && editableAncestor != nil
    }

    private static func isSettable(_ attribute: String, of element: AXUIElement) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    private static func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
