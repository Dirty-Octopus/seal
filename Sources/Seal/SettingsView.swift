import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        ZStack {
            AppBackground()
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    AppMark(size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("设置"))
                            .font(.system(size: 22, weight: .heavy, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                        Text("Seal \(appVersion)")
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(theme.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(theme.surfaceLow))
                    }
                    .buttonStyle(.plain)
                }

                settingsSection(title: L10n.t("界面语言"), subtitle: L10n.t("切换后立即生效。")) {
                    HStack(spacing: 10) {
                        languageButton(.en)
                        languageButton(.zhHans)
                    }
                }

                settingsSection(
                    title: L10n.t("界面尺寸"),
                    subtitle: L10n.t("选择预设窗口大小，也可以在窗口右下角自由拉伸。")
                ) {
                    VStack(spacing: 8) {
                        ForEach(WindowPreset.allCases) { preset in
                            WindowPresetRow(
                                preset: preset,
                                isSelected: settings.windowPreset == preset,
                                action: { settings.windowPreset = preset }
                            )
                        }
                    }
                }

                HStack {
                    Button {
                        settings.resetOnboarding()
                        dismiss()
                    } label: {
                        Label(L10n.t("重新显示欢迎页"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(GhostPillStyle(compact: true))

                    Spacer()

                    Text(L10n.t("窗口可通过右下角调整大小"))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                }

                HStack {
                    Text("MIT License")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                    Spacer()
                    Link("GitHub", destination: URL(string: "https://github.com/Dirty-Octopus/seal")!)
                        .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                }
            }
            .padding(26)
        }
        .frame(width: 560)
        .frame(minHeight: 560)
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.1"
    }

    private func settingsSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let theme = Theme(scheme: colorScheme)
        return VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(subtitle)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.surface.opacity(0.78))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(theme.outline, lineWidth: 1)
        )
    }

    private func languageButton(_ language: AppLanguage) -> some View {
        let theme = Theme(scheme: colorScheme)
        let selected = settings.language == language

        return Button {
            settings.language = language
        } label: {
            HStack(spacing: 10) {
                Text(language.shortName)
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(selected ? .white : theme.primary)
                    .frame(width: 34, height: 34)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(selected ? theme.primary : theme.primaryContainer)
                    )
                Text(language.displayName)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.primary)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(selected ? theme.primaryContainer.opacity(0.7) : theme.surfaceLow.opacity(0.55))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? theme.primary.opacity(0.24) : theme.outline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct WindowPresetRow: View {
    let preset: WindowPreset
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: preset.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? theme.primary : theme.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(isSelected ? theme.primaryContainer : theme.surfaceLow))
                VStack(alignment: .leading, spacing: 2) {
                    Text(preset.title)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(preset.sizeText)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(theme.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .fill(isSelected ? theme.primaryContainer.opacity(0.55) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .strokeBorder(isSelected ? theme.primary.opacity(0.20) : theme.outline.opacity(0.7), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
