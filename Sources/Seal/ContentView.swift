import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = AppStore()
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.colorScheme) private var colorScheme
    @State private var showSettings = false

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        ZStack(alignment: .bottom) {
            AppBackground()
                .ignoresSafeArea()

            VStack(spacing: 0) {
                TopBar(store: store, onSettings: { showSettings = true })

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 22) {
                        if let error = store.errorMessage {
                            ErrorBanner(message: error) {
                                store.dismissError()
                            }
                            .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        if store.target == nil {
                            EmptyLandingView(store: store)
                                .transition(.opacity.combined(with: .scale(scale: 0.985)))
                        } else {
                            WorkspaceView(store: store)
                                .transition(.opacity.combined(with: .scale(scale: 0.99)))
                        }
                    }
                    .frame(maxWidth: 1440)
                    .padding(.horizontal, 34)
                    .padding(.top, 8)
                    .padding(.bottom, 46)
                    .frame(maxWidth: .infinity)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            if store.isDropTargeted, store.target != nil {
                DropOverlay()
                    .transition(.opacity)
                    .allowsHitTesting(false)
            }

            if let toast = store.toast {
                ToastView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .background(WindowConfigurator())
        .frame(minWidth: 1040, minHeight: 680)
        .preferredColorScheme(nil)
        .animation(.spring(response: 0.42, dampingFraction: 0.82), value: store.target?.url)
        .animation(.spring(response: 0.38, dampingFraction: 0.8), value: store.toast?.id)
        .onDrop(
            of: [UTType.fileURL],
            delegate: FileDropDelegate(
                isTargeted: $store.isDropTargeted,
                onURL: { store.select(url: $0) }
            )
        )
        .onReceive(NotificationCenter.default.publisher(for: .sealOpenPanel)) { _ in
            store.openFilePanel()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sealRefresh)) { _ in
            store.refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sealResign)) { _ in
            store.resign()
        }
        .onReceive(NotificationCenter.default.publisher(for: .sealOpenSettings)) { _ in
            showSettings = true
        }
        .onAppear {
            if CommandLine.arguments.contains("--show-settings") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showSettings = true
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(settings)
        }
        .onReceive(NotificationCenter.default.publisher(for: .sealOpenPath)) { note in
            if let url = note.object as? URL {
                store.select(url: url)
            }
        }
        .confirmationDialog(
            L10n.t("清除全部扩展属性？"),
            isPresented: $store.clearAllConfirmation,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                store.clearAllXattrs()
            } label: {
                Text(L10n.t("清除 %d 项", store.xattrs.count))
            }
            Button(L10n.t("取消"), role: .cancel) {
                store.clearAllConfirmation = false
            }
        } message: {
            Text(L10n.t(store.xattrRecursive
                 ? "会同时清理包内嵌套文件的同名扩展属性。此操作不可撤销。"
                 : "仅清理当前对象顶层的扩展属性。此操作不可撤销。"))
        }
        .background(theme.canvas.opacity(0.001))
    }
}

// MARK: - Drop delegate

struct FileDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onURL: (URL) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.fileURL.identifier])
    }

    func dropEntered(info: DropInfo) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.76)) {
            isTargeted = true
        }
    }

    func dropExited(info: DropInfo) {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            isTargeted = false
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .copy)
    }

    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            isTargeted = false
        }
        guard let provider = info.itemProviders(for: [.fileURL]).first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var url: URL?
            if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let itemURL = item as? URL {
                url = itemURL
            } else if let string = item as? String {
                url = URL(string: string)
            }
            guard let url else { return }
            DispatchQueue.main.async {
                onURL(url)
            }
        }
        return true
    }
}

// MARK: - Top bar

private struct TopBar: View {
    @ObservedObject var store: AppStore
    let onSettings: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        HStack(spacing: 13) {
            AppMark(size: 36)

            VStack(alignment: .leading, spacing: 1) {
                Text("Seal")
                    .font(.system(size: 21, weight: .heavy, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text("CODESIGN / XATTR")
                    .font(.system(size: 8.5, weight: .bold, design: .rounded))
                    .tracking(1.5)
                    .foregroundStyle(theme.textTertiary)
            }

            if let target = store.target {
                Text("/")
                    .font(.system(size: 17, weight: .light, design: .rounded))
                    .foregroundStyle(theme.textTertiary.opacity(0.5))
                    .padding(.horizontal, 2)
                Text(target.displayName)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 220, alignment: .leading)
            }

            Spacer(minLength: 12)

            if let signature = store.signature {
                StatusBadge(
                    text: signature.status.shortTitle,
                    symbol: signature.status.symbol,
                    color: theme.statusColor(signature.status),
                    compact: true
                )
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }

            HStack(spacing: 5) {
                LiveDot(color: Palette.mint)
                Text("LOCAL")
                    .font(.system(size: 9.5, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(theme.textSecondary)
            }
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(theme.surface.opacity(0.72)))
            .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 1))

            Button {
                store.openFilePanel()
            } label: {
                Label("打开文件", systemImage: "folder")
            }
            .buttonStyle(TonalPillStyle(compact: true))

            IconCircleButton(symbol: "arrow.clockwise", help: "刷新检查", size: 34) {
                store.refresh()
            }
            .disabled(store.target == nil)
            .opacity(store.target == nil ? 0.45 : 1)

            IconCircleButton(symbol: "gearshape", help: "设置", size: 34, action: onSettings)

            if store.target != nil {
                IconCircleButton(symbol: "xmark", help: "关闭当前文件", size: 34) {
                    store.clearSelection()
                }
            }
        }
        .padding(.leading, 92)
        .padding(.trailing, 28)
        .padding(.top, 18)
        .padding(.bottom, 12)
        .background {
            ZStack(alignment: .bottom) {
                theme.surface
                Rectangle()
                    .fill(theme.outline)
                    .frame(height: 1)
                WindowDragArea()
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}

// MARK: - Empty landing

private struct EmptyLandingView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        VStack(spacing: 28) {
            VStack(spacing: 13) {
                Eyebrow("SIGNATURE INSPECTOR")
                Text("检查并重签本地文件。")
                    .font(.system(size: 48, weight: .heavy, design: .rounded))
                    .tracking(-1.2)
                    .foregroundStyle(theme.textPrimary)
                    .multilineTextAlignment(.center)

                Text("拖入 App、Framework、插件或 Mach-O 二进制，读取签名、验证状态与扩展属性。")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .lineSpacing(3)
                    .frame(maxWidth: 610)
            }
            .padding(.top, 12)

            DropZoneCard(store: store)

            HStack(spacing: 14) {
                FeatureCard(
                    symbol: "checkmark.seal.fill",
                    tint: Palette.mint,
                    title: "签名信息",
                    subtitle: "Authority / Team / CDHash"
                )
                FeatureCard(
                    symbol: "tag.fill",
                    tint: Palette.coral,
                    title: "扩展属性",
                    subtitle: "quarantine / FinderInfo"
                )
                FeatureCard(
                    symbol: "terminal.fill",
                    tint: Palette.violet,
                    title: "系统工具",
                    subtitle: "使用 codesign 与 xattr"
                )
            }

            HStack(spacing: 7) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 10, weight: .semibold))
                Text("操作通过系统 codesign 与 xattr 在本机执行。")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
            }
            .foregroundStyle(theme.textTertiary)
        }
        .frame(maxWidth: 960)
    }
}

private struct DropZoneCard: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let targeted = store.isDropTargeted

        ZStack {
            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .fill(theme.softGradient)
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(
                            theme.outlineStrong,
                            style: StrokeStyle(lineWidth: 1.2, dash: [9, 7])
                        )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 36, style: .continuous)
                        .strokeBorder(theme.expressiveGradient, lineWidth: targeted ? 3 : 0)
                )
                .shadow(color: theme.shadow, radius: targeted ? 34 : 24, x: 0, y: 18)

            VStack(spacing: 17) {
                ZStack {
                    Circle()
                        .stroke(theme.primary.opacity(0.13), style: StrokeStyle(lineWidth: 1.4, dash: [6, 7]))
                        .frame(width: targeted ? 184 : 164, height: targeted ? 184 : 164)
                        .rotationEffect(.degrees(targeted ? 12 : 0))
                    Circle()
                        .fill(theme.primaryContainer.opacity(0.65))
                        .frame(width: 132, height: 132)
                        .blur(radius: 0.2)
                    Circle()
                        .fill(theme.primaryGradient)
                        .frame(width: 106, height: 106)
                        .shadow(color: Palette.violet.opacity(0.3), radius: 18, x: 0, y: 10)
                        .overlay(
                            Image(systemName: targeted ? "arrow.down.circle.fill" : "arrow.down.doc.fill")
                                .font(.system(size: 42, weight: .semibold))
                                .foregroundStyle(.white)
                                .symbolRenderingMode(.hierarchical)
                                .scaleEffect(targeted ? 1.08 : 1)
                        )
                    Circle().fill(Palette.coral).frame(width: 10, height: 10).offset(x: 76, y: -54)
                    Circle().fill(Palette.mint).frame(width: 7, height: 7).offset(x: -86, y: 36)
                    Circle().fill(Palette.amber).frame(width: 6, height: 6).offset(x: 54, y: 76)
                }
                .animation(.spring(response: 0.42, dampingFraction: 0.72), value: targeted)

                VStack(spacing: 5) {
                    Text(LocalizedStringKey(targeted ? "松开即可检查" : "把文件拖到这里"))
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                    Text("App / Framework / 插件 / Mach-O 二进制 / 普通文件")
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textSecondary)
                }

                Button {
                    store.openFilePanel()
                } label: {
                    Label("选择文件…", systemImage: "folder.fill")
                }
                .buttonStyle(PrimaryPillStyle(compact: false))

                Text("拖入后立即读取签名与扩展属性")
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.vertical, 24)

            MonoChip(text: "codesign -dvvv", tint: Palette.violet)
                .rotationEffect(.degrees(-4))
                .offset(x: -330, y: -120)
                .allowsHitTesting(false)
            MonoChip(text: "xattr -l", tint: Palette.coral)
                .rotationEffect(.degrees(3.5))
                .offset(x: 350, y: -100)
                .allowsHitTesting(false)
            MonoChip(text: "spctl --assess", tint: Palette.mint)
                .rotationEffect(.degrees(-2.5))
                .offset(x: 320, y: 128)
                .allowsHitTesting(false)
        }
        .frame(height: 392)
        .scaleEffect(targeted ? 1.012 : 1)
        .animation(.spring(response: 0.4, dampingFraction: 0.78), value: targeted)
        .contentShape(RoundedRectangle(cornerRadius: 36, style: .continuous))
        .onTapGesture {
            store.openFilePanel()
        }
    }
}

private struct FeatureCard: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(Circle().fill(tint.opacity(theme.isDark ? 0.16 : 0.11)))

            VStack(alignment: .leading, spacing: 3) {
                Text(LocalizedStringKey(title))
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(LocalizedStringKey(subtitle))
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(theme.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(theme.outline, lineWidth: 1)
        )
    }
}

// MARK: - Workspace

private struct WorkspaceView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 20) {
            FileHeroCard(store: store)

            ViewThatFits(in: .horizontal) {
                wideLayout
                narrowLayout
            }
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 22) {
            SignatureCard(store: store)
                .frame(width: 372)

            detailPane
                .frame(minWidth: 620, maxWidth: .infinity)
        }
        .frame(minWidth: 1014, alignment: .leading)
    }

    private var narrowLayout: some View {
        VStack(spacing: 18) {
            SignatureCard(store: store)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity, alignment: .leading)
            detailPane
        }
    }

    private var detailPane: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                SegmentedTabs(selection: $store.activeTab)
                Spacer()
                if store.isLoading || store.isSigning || store.isVerifying {
                    HStack(spacing: 7) {
                        ProgressView()
                            .controlSize(.small)
                        Text(LocalizedStringKey(store.isSigning ? "正在签名" : (store.isVerifying ? "正在验证" : "正在读取")))
                            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(Theme(scheme: colorScheme).textTertiary)
                    }
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, 2)

            Group {
                switch store.activeTab {
                case .resign:
                    ResignPanel(store: store)
                case .xattrs:
                    XattrPanel(store: store)
                case .activity:
                    ActivityPanel(store: store)
                }
            }
            .id(store.activeTab)
            .transition(.opacity.combined(with: .move(edge: .trailing)))
        }
        .frame(maxWidth: .infinity)
    }
}

private struct FileHeroCard: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        guard let target = store.target else { return AnyView(EmptyView()) }

        return AnyView(
            CardSurface(padding: 20, radius: 30) {
                HStack(spacing: 18) {
                    FileIcon(url: target.url, size: 70)

                    VStack(alignment: .leading, spacing: 7) {
                        HStack(spacing: 9) {
                            Text(target.displayName)
                                .font(.system(size: 25, weight: .heavy, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            if let signature = store.signature {
                                StatusBadge(
                                    text: signature.status.title,
                                    symbol: signature.status.symbol,
                                    color: theme.statusColor(signature.status),
                                    compact: false
                                )
                            }
                        }

                        HStack(spacing: 7) {
                            Image(systemName: "folder")
                                .font(.system(size: 9, weight: .semibold))
                            Text(target.url.path)
                                .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .textSelection(.enabled)
                        }
                        .foregroundStyle(theme.textTertiary)

                        HStack(spacing: 8) {
                            MetaChip(symbol: target.kind.symbol, text: target.kindDescription)
                            MetaChip(symbol: "internaldrive", text: target.sizeText)
                            if let modified = target.modified {
                                MetaChip(symbol: "clock", text: Self.dateFormatter.string(from: modified))
                            }
                            if let bundleID = target.bundleID {
                                MetaChip(symbol: "number", text: bundleID)
                            }
                            if !target.isWritable {
                                MetaChip(symbol: "lock", text: L10n.t("只读"))
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 10) {
                        HStack(spacing: 8) {
                            Button {
                                store.revealInFinder()
                            } label: {
                                Label("Finder", systemImage: "arrow.up.forward.app")
                            }
                            .buttonStyle(GhostPillStyle(compact: true))

                            Button {
                                store.refresh()
                            } label: {
                                Label("刷新", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(TonalPillStyle(compact: true))
                        }
                        Text("拖入其他文件即可切换")
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textTertiary)
                    }
                }
            }
        )
    }

    static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = L10n.locale
        formatter.dateFormat = "yyyy/MM/dd HH:mm"
        return formatter
    }
}

private struct FileIcon: View {
    let url: URL
    let size: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 5)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(theme.surfaceLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(theme.outline, lineWidth: 1)
            )
    }
}

struct MetaChip: View {
    let symbol: String
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        HStack(spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 8.5, weight: .semibold))
            Text(text)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(theme.textSecondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(theme.surfaceLow))
        .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 1))
    }
}

// MARK: - Error / toast / overlay

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(theme.danger)
                .frame(width: 34, height: 34)
                .background(Circle().fill(theme.danger.opacity(0.11)))

            VStack(alignment: .leading, spacing: 3) {
                Text("操作未完成")
                    .font(.system(size: 12.5, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(message)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(4)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(theme.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(theme.surfaceLow))
            }
            .buttonStyle(.plain)
        }
        .padding(13)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(theme.danger.opacity(theme.isDark ? 0.10 : 0.055))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(theme.danger.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ToastView: View {
    let toast: ToastMessage
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let tint: Color = {
            switch toast.style {
            case .success: return Palette.mint
            case .info: return Palette.violet
            case .error: return Palette.coral
            }
        }()

        HStack(spacing: 9) {
            Image(systemName: toast.style.symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
            Text(toast.text)
                .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 18)
        .frame(height: 44)
        .background(Capsule().fill(theme.surface))
        .overlay(Capsule().strokeBorder(tint.opacity(0.22), lineWidth: 1))
        .shadow(color: theme.shadow, radius: 20, x: 0, y: 10)
    }
}

private struct DropOverlay: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        ZStack {
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(theme.expressiveGradient, style: StrokeStyle(lineWidth: 3, dash: [11, 8]))
                .padding(12)

            VStack(spacing: 10) {
                Image(systemName: "arrow.down.doc.fill")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Circle().fill(theme.primaryGradient))
                Text("松开以检查这个文件")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 9)
                    .background(Capsule().fill(theme.surface))
                    .overlay(Capsule().strokeBorder(theme.outline, lineWidth: 1))
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(theme.canvas.opacity(0.72))
            )
        }
        .background(theme.canvas.opacity(0.38).ignoresSafeArea())
    }
}

struct MonoChip: View {
    let text: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        Text(text)
            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Capsule().fill(theme.surface.opacity(0.84)))
            .overlay(Capsule().strokeBorder(tint.opacity(0.18), lineWidth: 1))
            .shadow(color: theme.shadow, radius: 8, x: 0, y: 3)
    }
}
