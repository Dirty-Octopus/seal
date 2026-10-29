import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        Group {
            if settings.hasCompletedOnboarding {
                ContentView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: settings.hasCompletedOnboarding)
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        ZStack {
            AppBackground()
                .ignoresSafeArea()

            VStack(spacing: 26) {
                Spacer(minLength: 36)

                AppMark(size: 104)

                VStack(spacing: 12) {
                    Text("Choose your language")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text("选择你的语言")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)

                    Text("Seal will use this language across the app. You can change it later in Settings.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                        .multilineTextAlignment(.center)
                    Text("Seal 会使用此语言显示界面，之后可在设置中修改。")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: 620)

                HStack(spacing: 18) {
                    LanguageCard(
                        code: "EN",
                        title: "English",
                        subtitle: "Continue in English",
                        action: { settings.completeOnboarding(language: .en) }
                    )
                    LanguageCard(
                        code: "中",
                        title: "简体中文",
                        subtitle: "使用中文界面",
                        action: { settings.completeOnboarding(language: .zhHans) }
                    )
                }
                .frame(maxWidth: 680)

                Text("You can switch languages and window size later in Settings.")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textTertiary)

                Spacer(minLength: 36)
            }
            .padding(.horizontal, 40)
        }
        .frame(minWidth: 1040, minHeight: 680)
    }
}

private struct LanguageCard: View {
    let code: String
    let title: String
    let subtitle: String
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var hover = false

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        Button(action: action) {
            VStack(spacing: 16) {
                Text(code)
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(theme.expressiveGradient)
                    )
                    .shadow(color: Palette.violet.opacity(0.24), radius: 12, x: 0, y: 7)

                VStack(spacing: 4) {
                    Text(title)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 26)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .strokeBorder(
                        hover ? theme.primary.opacity(0.45) : theme.outline,
                        lineWidth: hover ? 1.8 : 1
                    )
            )
            .shadow(color: theme.shadow, radius: hover ? 24 : 18, x: 0, y: 12)
            .scaleEffect(hover ? 1.018 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.spring(response: 0.3, dampingFraction: 0.78)) {
                hover = inside
            }
        }
    }
}
