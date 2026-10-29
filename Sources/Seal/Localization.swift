import SwiftUI
import AppKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case en = "en"
    case zhHans = "zh-Hans"

    var id: String { rawValue }

    var locale: Locale {
        Locale(identifier: rawValue)
    }

    var displayName: String {
        switch self {
        case .en: return "English"
        case .zhHans: return "简体中文"
        }
    }

    var shortName: String {
        switch self {
        case .en: return "EN"
        case .zhHans: return "中"
        }
    }
}

enum L10n {
    static var language: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: "app.language"),
           let language = AppLanguage(rawValue: raw) {
            return language
        }
        return .en
    }()

    static var locale: Locale {
        language.locale
    }

    private static var englishBundle: Bundle? = {
        guard let path = Bundle.main.path(forResource: "en", ofType: "lproj") else { return nil }
        return Bundle(path: path)
    }()

    static func t(_ key: String, _ args: CVarArg...) -> String {
        let format: String
        if language == .en, let englishBundle {
            format = englishBundle.localizedString(forKey: key, value: key, table: nil)
        } else {
            format = key
        }
        guard !args.isEmpty else { return format }
        return String(format: format, locale: locale, arguments: args)
    }

    static func byteString(_ bytes: Int64) -> String {
        if bytes < 1024 {
            return t("%d 字节", Int(bytes))
        }
        var value = Double(bytes) / 1024
        let units = ["KB", "MB", "GB", "TB"]
        var unit = units[0]
        for candidate in units {
            unit = candidate
            if value < 1024 { break }
            value /= 1024
        }
        let formatted = value >= 100 ? String(format: "%.0f", value) : String(format: "%.1f", value)
        return "\(formatted) \(unit)"
    }

    static func dateString(
        _ date: Date,
        dateStyle: DateFormatter.Style = .medium,
        timeStyle: DateFormatter.Style = .short
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }
}

enum WindowPreset: String, CaseIterable, Identifiable {
    case compact
    case standard
    case large

    var id: String { rawValue }

    var contentSize: NSSize {
        switch self {
        case .compact: return NSSize(width: 1040, height: 720)
        case .standard: return NSSize(width: 1180, height: 820)
        case .large: return NSSize(width: 1380, height: 920)
        }
    }

    var title: String {
        switch self {
        case .compact: return L10n.t("紧凑")
        case .standard: return L10n.t("标准")
        case .large: return L10n.t("大")
        }
    }

    var sizeText: String {
        "\(Int(contentSize.width)) × \(Int(contentSize.height))"
    }

    var symbol: String {
        switch self {
        case .compact: return "rectangle.compress.vertical"
        case .standard: return "rectangle"
        case .large: return "rectangle.expand.vertical"
        }
    }

    static var saved: WindowPreset {
        let raw = UserDefaults.standard.string(forKey: "window.preset") ?? WindowPreset.standard.rawValue
        return WindowPreset(rawValue: raw) ?? .standard
    }
}

@MainActor
final class WindowManager {
    static let shared = WindowManager()

    weak var window: NSWindow?
    private var attachedWindowID: ObjectIdentifier?

    func attach(_ window: NSWindow) {
        self.window = window
        guard attachedWindowID != ObjectIdentifier(window) else { return }
        attachedWindowID = ObjectIdentifier(window)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.apply(WindowPreset.saved, animated: false)
        }
    }

    func apply(_ preset: WindowPreset, animated: Bool = true) {
        guard let window else { return }
        var size = preset.contentSize
        if let screen = window.screen ?? NSScreen.main {
            let visible = screen.visibleFrame
            size.width = min(size.width, max(1040, visible.width - 80))
            size.height = min(size.height, max(680, visible.height - 100))
        }
        window.setContentSize(size)
        window.center()
    }
}

@MainActor
final class AppSettings: ObservableObject {
    @Published var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "app.language")
            L10n.language = language
        }
    }

    @Published var hasCompletedOnboarding: Bool {
        didSet {
            UserDefaults.standard.set(hasCompletedOnboarding, forKey: "app.onboardingCompleted")
        }
    }

    @Published var windowPreset: WindowPreset {
        didSet {
            UserDefaults.standard.set(windowPreset.rawValue, forKey: "window.preset")
            WindowManager.shared.apply(windowPreset)
        }
    }

    init() {
        let defaults = UserDefaults.standard
        let savedLanguage = defaults.string(forKey: "app.language")
            .flatMap(AppLanguage.init(rawValue:)) ?? .en
        language = savedLanguage
        hasCompletedOnboarding = defaults.bool(forKey: "app.onboardingCompleted")
        windowPreset = WindowPreset.saved
        L10n.language = savedLanguage
    }

    func completeOnboarding(language: AppLanguage) {
        self.language = language
        self.hasCompletedOnboarding = true
    }

    func resetOnboarding() {
        hasCompletedOnboarding = false
    }
}

extension Notification.Name {
    static let sealOpenSettings = Notification.Name("seal.openSettings")
}
