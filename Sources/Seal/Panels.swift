import SwiftUI
import AppKit

// MARK: - Signature overview

struct SignatureCard: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        CardSurface(padding: 22, radius: 30) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) {
                        Eyebrow("Signature")
                        Text("签名状态")
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                    }
                    Spacer()
                    if let signature = store.signature {
                        StatusBadge(
                            text: signature.status.shortTitle,
                            symbol: signature.status.symbol,
                            color: theme.statusColor(signature.status),
                            compact: true
                        )
                    }
                }

                if let signature = store.signature {
                    HStack(spacing: 15) {
                        SignatureOrb(status: signature.status)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(signature.status.title)
                                .font(.system(size: 21, weight: .heavy, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                            Text(signature.status.detail)
                                .font(.system(size: 10.8, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.textSecondary)
                                .lineSpacing(2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    if signature.status != .unsupported {
                        Hairline()

                        VStack(spacing: 8) {
                            InfoRow(label: "Identifier", value: signature.identifier, monospaced: true, copyable: true)
                            InfoRow(label: "Team ID", value: signature.teamID, monospaced: true, copyable: true)
                            InfoRow(label: "Format", value: signature.format)
                            InfoRow(label: "CDHash", value: signature.cdhash, monospaced: true, copyable: true)
                            if let timestamp = signature.timestamp {
                                InfoRow(label: "Timestamp", value: timestamp)
                            }
                            if !signature.flags.isEmpty {
                                InfoRow(label: "Flags", value: signature.flags.joined(separator: " · "), monospaced: true)
                            }
                        }

                        if !signature.authorities.isEmpty {
                            AuthorityChain(authorities: signature.authorities)
                        } else if signature.status == .adHoc {
                            NoticeLine(
                                symbol: "info.circle.fill",
                                tint: Palette.amber,
                                text: "Ad-hoc 签名没有证书链，适合本机运行与测试。"
                            )
                        }

                        Hairline()

                        VerificationLine(signature: signature)
                        GatekeeperLine(gatekeeper: signature.gatekeeper)

                        if let entitlements = signature.entitlements {
                            EntitlementsPreview(text: entitlements)
                        }

                        HStack(spacing: 9) {
                            Button {
                                store.verifySignature()
                            } label: {
                                HStack(spacing: 6) {
                                    if store.isVerifying {
                                        ProgressView().controlSize(.small)
                                    } else {
                                        Image(systemName: "checkmark.shield")
                                    }
                                    Text(LocalizedStringKey(store.isVerifying ? "验证中…" : "再次验证"))
                                }
                            }
                            .buttonStyle(TonalPillStyle(compact: true))
                            .disabled(store.isVerifying || store.isSigning)

                            Button {
                                store.copyReport()
                            } label: {
                                Label("复制报告", systemImage: "doc.on.doc")
                            }
                            .buttonStyle(GhostPillStyle(compact: true))

                            Spacer(minLength: 0)
                        }
                    }
                } else if store.isLoading {
                    VStack(spacing: 13) {
                        ProgressView()
                            .controlSize(.small)
                        Text("正在读取签名…")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 250)
                } else {
                    NoticeLine(
                        symbol: "questionmark.circle",
                        tint: theme.textTertiary,
                        text: "签名信息尚未读取。点击右上角刷新。"
                    )
                }
            }
        }
    }
}

private struct Hairline: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        Rectangle()
            .fill(theme.outline)
            .frame(height: 1)
    }
}

private struct SignatureOrb: View {
    let status: SignatureStatus
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let color = theme.statusColor(status)

        ZStack {
            Circle()
                .stroke(color.opacity(0.12), lineWidth: 8)
                .frame(width: 82, height: 82)

            Circle()
                .trim(from: 0, to: status.isSigned ? 0.8 : 0.48)
                .stroke(
                    AngularGradient(
                        colors: [color, color.opacity(0.35), color],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: 4, lineCap: .round)
                )
                .frame(width: 82, height: 82)
                .rotationEffect(.degrees(-90))

            Circle()
                .fill(color.opacity(theme.isDark ? 0.18 : 0.11))
                .frame(width: 62, height: 62)

            Image(systemName: status.symbol)
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(color)
        }
        .frame(width: 82, height: 82)
    }
}

private struct AuthorityChain: View {
    let authorities: [String]
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow("Authority chain")
                .padding(.bottom, 7)

            ForEach(Array(authorities.enumerated()), id: \.offset) { index, authority in
                HStack(alignment: .top, spacing: 9) {
                    VStack(spacing: 0) {
                        Image(systemName: index == 0 ? "checkmark.seal.fill" : "checkmark")
                            .font(.system(size: index == 0 ? 10 : 8, weight: .bold))
                            .foregroundStyle(index == 0 ? Palette.mint : theme.textTertiary)
                            .frame(width: 16, height: 16)
                            .background(Circle().fill(theme.surfaceLow))
                        if index < authorities.count - 1 {
                            Rectangle()
                                .fill(theme.outline)
                                .frame(width: 1, height: 15)
                        }
                    }

                    Text(authority)
                        .font(.system(size: 10.5, weight: index == 0 ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(index == 0 ? theme.textPrimary : theme.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .padding(.top, 1)
                    Spacer(minLength: 0)
                }
            }
        }
    }
}

private struct NoticeLine: View {
    let symbol: String
    let tint: Color
    let text: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            Text(LocalizedStringKey(text))
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(theme.textSecondary)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(tint.opacity(theme.isDark ? 0.10 : 0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(tint.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct VerificationLine: View {
    let signature: SignatureReport
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let tint = signature.verificationPassed ? Palette.mint : theme.danger
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 7) {
                Image(systemName: signature.verificationSymbol)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(tint)
                Text(signature.verificationTitle)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Spacer(minLength: 0)
            }
            if !signature.verificationOutput.isEmpty, !signature.verificationPassed {
                Text(signature.verificationOutput)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surfaceLow.opacity(0.7))
        )
    }
}

private struct GatekeeperLine: View {
    let gatekeeper: GatekeeperStatus
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let tint: Color = {
            switch gatekeeper {
            case .accepted: return Palette.mint
            case .rejected: return Palette.coral
            case .notAssessed: return theme.textTertiary
            }
        }()

        HStack(alignment: .top, spacing: 7) {
            Image(systemName: gatekeeper.symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 2) {
                Text(gatekeeper.title)
                    .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(gatekeeper.detail)
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.surfaceLow.opacity(0.55))
        )
    }
}

private struct EntitlementsPreview: View {
    let text: String
    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded = false

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "doc.badge.gearshape")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Entitlements")
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)

            if expanded {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(text)
                        .font(.system(size: 8.5, weight: .regular, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(theme.surfaceLow)
                )
            }
        }
    }
}

// MARK: - Re-sign panel

struct ResignPanel: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    private let columns = [
        GridItem(.flexible(), spacing: 9),
        GridItem(.flexible(), spacing: 9)
    ]

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        CardSurface(padding: 22, radius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    SectionTitle(
                        "快速重新签名",
                        subtitle: "选择签名身份后执行 codesign。"
                    )
                    Spacer()
                    StatusBadge(text: "LOCAL CODESIGN", symbol: "lock.fill", color: Palette.violet, compact: true)
                }

                IdentityMenu(store: store)

                if let note = store.identityNote {
                    NoticeLine(
                        symbol: "key.horizontal",
                        tint: Palette.amber,
                        text: note
                    )
                }

                if store.signature?.status == .unsupported {
                    NoticeLine(
                        symbol: "folder.badge.questionmark",
                        tint: Palette.sky,
                        text: "普通文件夹不能直接执行 codesign。你仍然可以在「扩展属性」页查看并清理 xattr。"
                    )
                }

                if let target = store.target, !target.isWritable {
                    NoticeLine(
                        symbol: "lock.fill",
                        tint: Palette.amber,
                        text: "当前对象不可写，codesign 可能失败。请复制到可写目录后再签名。"
                    )
                }

                Hairline()

                HStack {
                    Eyebrow("Signing options")
                    Spacer()
                    Text(store.signatureStateText)
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                }

                LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                    OptionToggle(
                        title: "覆盖签名",
                        subtitle: "--force",
                        symbol: "arrow.triangle.2.circlepath",
                        isOn: $store.options.force
                    )
                    OptionToggle(
                        title: "深度签名",
                        subtitle: "嵌套代码",
                        symbol: "square.stack.3d.down.right",
                        isOn: $store.options.deep,
                        isEnabled: store.target?.isCodeBundle == true
                    )
                    OptionToggle(
                        title: "保留元数据",
                        subtitle: "entitlements · flags",
                        symbol: "archivebox",
                        isOn: $store.options.preserveMetadata,
                        isEnabled: store.hasExistingSignature
                    )
                    OptionToggle(
                        title: "Hardened Runtime",
                        subtitle: "--options runtime",
                        symbol: "shield.lefthalf.filled",
                        isOn: $store.options.hardenedRuntime
                    )
                    OptionToggle(
                        title: "时间戳",
                        subtitle: "需要证书与联网",
                        symbol: "clock.badge.checkmark",
                        isOn: $store.options.timestamp,
                        isEnabled: !store.selectedIdentity.isAdHoc
                    )
                    OptionToggle(
                        title: "移除 quarantine",
                        subtitle: "签名后清理",
                        symbol: "sparkles",
                        isOn: $store.options.removeQuarantine
                    )
                }

                EntitlementsRow(store: store)

                HStack(spacing: 10) {
                    Button {
                        store.resign()
                    } label: {
                        HStack(spacing: 7) {
                            if store.isSigning {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            } else {
                                Image(systemName: "signature")
                            }
                            Text(LocalizedStringKey(store.isSigning ? "正在签名…" : "快速重新签名"))
                        }
                    }
                    .buttonStyle(PrimaryPillStyle())
                    .disabled(!store.canResign)

                    Button {
                        store.verifySignature()
                    } label: {
                        Label("再次验证", systemImage: "checkmark.shield")
                    }
                    .buttonStyle(TonalPillStyle())
                    .disabled(store.isVerifying || store.isSigning || store.signature?.status == .unsupported)

                    Spacer(minLength: 0)

                    if let target = store.target {
                        Text(LocalizedStringKey(target.isCodeBundle ? "包含嵌套组件" : "仅当前对象"))
                            .font(.system(size: 9.5, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textTertiary)
                    }
                }

                CommandPreview(store: store)
            }
        }
    }
}

private struct IdentityMenu: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        Menu {
            ForEach(store.identities) { identity in
                Button {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        store.selectedIdentityID = identity.id
                    }
                } label: {
                    HStack {
                        Text(identity.name)
                        if identity.id == store.selectedIdentityID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
            Divider()
            Button("刷新证书列表") {
                store.refreshIdentities()
            }
        } label: {
            HStack(spacing: 11) {
                Image(systemName: store.selectedIdentity.isAdHoc ? "scribble.variable" : "checkmark.seal.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(store.selectedIdentity.isAdHoc ? Palette.amber : Palette.mint)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle().fill(
                            (store.selectedIdentity.isAdHoc ? Palette.amber : Palette.mint)
                                .opacity(theme.isDark ? 0.16 : 0.10)
                        )
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(store.selectedIdentity.displayName)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text(LocalizedStringKey(store.selectedIdentity.isAdHoc
                         ? "无需证书 · 仅在本机有效"
                         : "SHA-1 \(store.selectedIdentity.id.prefix(12))…"))
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }

                Spacer(minLength: 10)

                if store.isLoadingIdentities {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .fill(theme.surfaceLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .strokeBorder(theme.outline, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct EntitlementsRow: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        HStack(spacing: 11) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.sky)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Palette.sky.opacity(theme.isDark ? 0.15 : 0.09)))

            VStack(alignment: .leading, spacing: 2) {
                Text("Entitlements")
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(store.options.entitlementsPath?.lastPathComponent ?? L10n.t("未选择 · 保留现有 entitlements"))
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 6)

            if store.options.entitlementsPath != nil {
                Button("清除") {
                    store.clearEntitlements()
                }
                .buttonStyle(GhostPillStyle(compact: true))
            }

            Button("选择…") {
                store.chooseEntitlements()
            }
            .buttonStyle(TonalPillStyle(compact: true, tint: Palette.sky))
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(theme.surfaceLow.opacity(0.55))
        )
    }
}

private struct CommandPreview: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Eyebrow("Command preview")
                Spacer()
                Button {
                    store.copyCommand()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(GhostPillStyle(compact: true))
                .disabled(store.commandPreview == nil)
            }

            Text(store.commandPreview ?? "—")
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(theme.surfaceLow)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .strokeBorder(theme.outline, lineWidth: 1)
                )
        }
    }
}

// MARK: - xattr panel

struct XattrPanel: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let quarantine = store.xattrs.first(where: { $0.isQuarantine })

        CardSurface(padding: 24, radius: 30) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    SectionTitle(
                        "扩展属性",
                        subtitle: L10n.t("%d 项 · 顶层 xattr", store.xattrs.count)
                    )
                    Spacer()
                    if quarantine != nil {
                        Button {
                            store.removeQuarantine()
                        } label: {
                            Label("移除隔离", systemImage: "sparkles")
                        }
                        .buttonStyle(TonalPillStyle(compact: true, tint: Palette.amber))
                        .disabled(store.isWorkingXattrs)
                    }
                    Button {
                        store.clearAllConfirmation = true
                    } label: {
                        Label("全部清除", systemImage: "trash")
                    }
                    .buttonStyle(DestructivePillStyle(compact: true))
                    .disabled(store.xattrs.isEmpty || store.isWorkingXattrs)
                }

                if let quarantine {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "exclamationmark.shield.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Palette.amber)
                            .padding(.top, 1)
                        VStack(alignment: .leading, spacing: 3) {
                            Text("检测到 quarantine")
                                .font(.system(size: 11.5, weight: .bold, design: .rounded))
                                .foregroundStyle(theme.textPrimary)
                            Text(L10n.t("%@。移除后 macOS 不会再对该对象显示“已下载”的隔离提示。", quarantine.summary))
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.textSecondary)
                                .lineSpacing(2)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Palette.amber.opacity(theme.isDark ? 0.11 : 0.07))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Palette.amber.opacity(0.16), lineWidth: 1)
                    )
                }

                if store.xattrs.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(theme.textTertiary)
                        Text("没有扩展属性")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                        Text("此对象没有 quarantine、FinderInfo 或其他 xattr。")
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    VStack(spacing: 0) {
                        ForEach(store.xattrs) { item in
                            XattrRow(item: item, store: store)
                        }
                    }
                }

                if store.target?.isDirectory == true {
                    HStack {
                        OptionToggle(
                            title: "递归清除",
                            subtitle: "包含包内嵌套文件",
                            symbol: "square.stack.3d.down.right",
                            isOn: $store.xattrRecursive
                        )
                        Spacer(minLength: 12)
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text("移除 FinderInfo 或资源分支可能影响 Finder 展示与旧资源数据，请按需操作。")
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

private struct XattrRow: View {
    let item: XattrItem
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var expanded = false

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 11) {
                    Image(systemName: item.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(item.isQuarantine ? Palette.amber : theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(
                                (item.isQuarantine ? Palette.amber : theme.textSecondary)
                                    .opacity(theme.isDark ? 0.14 : 0.07)
                            )
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name)
                            .font(.system(size: 10.2, weight: .semibold, design: .monospaced))
                            .foregroundStyle(theme.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(item.summary)
                            .font(.system(size: 10.5, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }

                    Spacer(minLength: 8)

                    Text(item.byteCountText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)

                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(theme.textTertiary)
                        .frame(width: 18)
                }
                .padding(.vertical, 9)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(Array(item.details.enumerated()), id: \.offset) { _, detail in
                        Text(detail)
                            .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                            .foregroundStyle(theme.textSecondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    HStack(spacing: 8) {
                        Button {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(item.copyText, forType: .string)
                            store.showToast(L10n.t("已复制 xattr 内容"), style: .info)
                        } label: {
                            Label("复制", systemImage: "doc.on.doc")
                        }
                        .buttonStyle(GhostPillStyle(compact: true))

                        Button(role: .destructive) {
                            store.removeXattr(item)
                        } label: {
                            Label("移除", systemImage: "trash")
                        }
                        .buttonStyle(DestructivePillStyle(compact: true))
                        .disabled(store.isWorkingXattrs)

                        Spacer(minLength: 0)
                    }
                }
                .padding(11)
                .background(
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(theme.surfaceLow)
                )
                .padding(.bottom, 9)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Rectangle()
                .fill(theme.outline)
                .frame(height: 1)
        }
    }
}

// MARK: - Activity

struct ActivityPanel: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        CardSurface(padding: 24, radius: 30) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    SectionTitle(
                        "活动日志",
                        subtitle: "记录本机执行的命令与结果。"
                    )
                    Spacer()
                    Button {
                        store.copyLog()
                    } label: {
                        Label("复制日志", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(GhostPillStyle(compact: true))
                }

                Hairline()

                if store.activity.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.alignleft")
                            .font(.system(size: 26, weight: .light))
                            .foregroundStyle(theme.textTertiary)
                        Text("还没有操作记录")
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 260)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(store.activity) { entry in
                                ActivityRow(entry: entry)
                            }
                        }
                    }
                    .frame(minHeight: 300, maxHeight: 520)
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let entry: LogEntry
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let tint: Color = {
            switch entry.level {
            case .info: return Palette.sky
            case .success: return Palette.mint
            case .warning: return Palette.amber
            case .error: return Palette.coral
            }
        }()

        HStack(alignment: .top, spacing: 10) {
            VStack(spacing: 0) {
                Image(systemName: entry.level.symbol)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 18, height: 18)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text(AppStore.timeFormatter.string(from: entry.date))
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                    Text(entry.message)
                        .font(.system(size: 10.8, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(3)
                    Spacer(minLength: 0)
                }

                if let command = entry.command {
                    Text(command)
                        .font(.system(size: 8.8, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(3)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .padding(7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(theme.surfaceLow)
                        )
                }
            }
        }
        .padding(.vertical, 9)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.outline)
                .frame(height: 1)
        }
    }
}
