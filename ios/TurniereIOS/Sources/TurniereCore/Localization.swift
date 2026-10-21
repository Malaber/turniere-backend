import Foundation

/// Semantic keys live in Resources/<language>.lproj/Localizable.strings.
/// Bundle lookup follows the device's preferred languages, with English fallback.
public enum L10n {
    public static func text(_ key: String) -> String {
        Bundle.module.localizedString(forKey: key, value: nil, table: nil)
    }

    public static func format(_ key: String, _ arguments: CVarArg...) -> String {
        String(format: text(key), locale: Locale.current, arguments: arguments)
    }

    public static func message(for error: Error) -> String {
        if let error = error as? APIError { return error.errorDescription ?? text("error.generic") }
        if error is URLError { return text("error.network") }
        return text("error.generic")
    }
}
