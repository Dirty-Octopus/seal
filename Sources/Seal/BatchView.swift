import SwiftUI
import AppKit

struct BatchWorkspaceView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        VStack(spacing: 20) {
            BatchHeaderCard(store: store)

            if store.batchItems.isEmpty {
                BatchEmptyView(store: store)
            } else {
                ViewThatFits(in: .horizontal) {
                    wideLayout
                    narrowLayout
                }
            }
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 22) {
            BatchQueueCard(store: store)
                .frame(minWidth: 620)
            sideColumn
                .frame(width: 380)
        }
        .frame(minWidth: 1022, alignment: .leading)
    }

    private var narrowLayout: some View {
        VStack(spacing: 18) {
            BatchQueueCard(store: store)
            sideColumn
        }
    }

    private var sideColumn: some View {
        VStack(spacing: 18) {
            BatchOptionsCard(store: store)
            BatchActivityCard(store: store)
        }
    }
}

private struct BatchHeaderCard: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        CardSurface(padding: 22, radius: 30) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 5) {
                        Eyebrow("BATCH")
                        Text(L10n.t("批量签名"))
                            .font(.system(size: 27, weight: .heavy, design: .rounded))
                            .foregroundStyle(theme.textPrimary)
                        Text(L10n.t("检查并重签队列中的多个对象。"))
                            .font(.system(size: 12.5, weight: .medium, design: .rounded))
                            .foregroundStyle(theme.textSecondary)
                    }

                    Spacer(minLength: 10)

                    HStack(spacing: 8) {
                        Button {
                            store.openFilePanel()
                        } label: {
                            Label {
                                Text(L10n.t("添加文件…"))
                            } icon: {
                                Image(systemName: "plus")
                            }
                        }
                        .buttonStyle(GhostPillStyle(compact: true))
                        .disabled(store.batchRunning)

                        Button {
                            store.inspectBatch()
                        } label: {
                            Label {
                                Text(L10n.t("全部检查"))
                            } icon: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                        .buttonStyle(TonalPillStyle(compact: true))
                        .disabled(!store.batchCanInspect)

                        Button {
                            store.signBatch()
                        } label: {
                            Label {
                                Text(L10n.t("全部签名"))
                            } icon: {
                                Image(systemName: "signature")
                            }
                        }
                        .buttonStyle(PrimaryPillStyle(compact: true))
                        .disabled(!store.batchCanSign)

                        if store.batchRunning {
                            Button {
                                store.stopBatch()
                            } label: {
                                Label {
                                    Text(L10n.t("停止"))
                                } icon: {
                                    Image(systemName: "stop.fill")
                                }
                            }
                            .buttonStyle(DestructivePillStyle(compact: true))
                            .disabled(store.batchStopRequested)
                        }
                    }
                }

                if !store.batchItems.isEmpty {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            Text(L10n.t("进度"))
                                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                                .foregroundStyle(theme.textTertiary)
                                .frame(width: 48, alignment: .leading)

                            ProgressView(value: store.batchProgressValue)
                                .progressViewStyle(.linear)
                                .tint(theme.primary)

                            Text("\(Int((store.batchProgressValue * 100).rounded()))%")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(theme.textSecondary)
                                .frame(width: 38, alignment: .trailing)
                        }

                        HStack(spacing: 8) {
                            BatchStat(
                                text: L10n.t("已完成 %d", store.batchSignedCount),
                                symbol: "checkmark.seal.fill",
                                tint: Palette.mint
                            )
                            BatchStat(
                                text: L10n.t("失败 %d", store.batchFailedCount),
                                symbol: "xmark.octagon.fill",
                                tint: theme.danger
                            )
                            BatchStat(
                                text: L10n.t("待处理 %d", store.batchItems.count - store.batchSignedCount - store.batchFailedCount - store.batchSkippedCount),
                                symbol: "clock",
                                tint: theme.textSecondary
                            )
                            if store.batchSkippedCount > 0 {
                                BatchStat(
                                    text: L10n.t("跳过 %d", store.batchSkippedCount),
                                    symbol: "minus.circle",
                                    tint: theme.textTertiary
                                )
                            }
                            Spacer(minLength: 0)
                            Text(L10n.t("依次执行"))
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                }
            }
        }
    }
}

private struct BatchStat: View {
    let text: String
    let symbol: String
    let tint: Color
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
                .foregroundStyle(theme.textSecondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Capsule().fill(tint.opacity(theme.isDark ? 0.12 : 0.07)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.12), lineWidth: 1))
    }
}

private struct BatchQueueCard: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        CardSurface(padding: 0, radius: 30) {
            VStack(spacing: 0) {
                HStack(alignment: .center, spacing: 12) {
                    SectionTitle(
                        L10n.t("队列"),
                        subtitle: L10n.t("%d 项待管理", store.batchItems.count)
                    )
                    Spacer()
                    Menu {
                        Button {
                            store.clearBatch(completedOnly: true)
                        } label: {
                            Label(L10n.t("清空已完成"), systemImage: "checkmark.circle")
                        }
                        Button(role: .destructive) {
                            store.clearBatch()
                        } label: {
                            Label(L10n.t("清空列表"), systemImage: "trash")
                        }
                    } label: {
                        Label {
                            Text(L10n.t("管理"))
                        } icon: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(store.batchRunning)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)

                Rectangle()
                    .fill(theme.outline)
                    .frame(height: 1)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(store.batchItems) { item in
                            BatchRow(item: item, store: store)
                        }
                    }
                }
                .frame(maxHeight: 560)
            }
        }
    }
}

private struct BatchRow: View {
    let item: BatchItem
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let isWorking = item.state == .inspecting || item.state == .signing

        HStack(spacing: 11) {
            BatchFileIcon(url: item.target.url)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(item.target.displayName)
                        .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(item.target.kindDescription)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                }

                Text(item.target.url.path)
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if item.state == .failed && !item.message.isEmpty {
                    Text(item.message)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.danger)
                        .lineLimit(2)
                } else if !item.message.isEmpty {
                    Text(item.message)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if isWorking {
                ProgressView()
                    .controlSize(.small)
            }

            if let report = item.report {
                StatusBadge(
                    text: report.status.shortTitle,
                    symbol: report.status.symbol,
                    color: theme.statusColor(report.status),
                    compact: true
                )
            }

            BatchStateBadge(state: item.state)

            Menu {
                Button {
                    store.openBatchItemInSingleView(item.id)
                } label: {
                    Label(L10n.t("在单文件中打开"), systemImage: "arrow.up.right.square")
                }
                Button {
                    store.revealBatchItem(item.id)
                } label: {
                    Label(L10n.t("在 Finder 中显示"), systemImage: "folder")
                }
                if item.target.canCodesign, item.state != .skipped {
                    Button {
                        store.signBatchItem(item.id)
                    } label: {
                        Label(L10n.t("签名此项"), systemImage: "signature")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    store.removeBatchItem(item.id)
                } label: {
                    Label(L10n.t("移出队列"), systemImage: "minus.circle")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(theme.surfaceLow))
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(store.batchRunning)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(theme.outline)
                .frame(height: 1)
        }
    }
}

private struct BatchStateBadge: View {
    let state: BatchState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let tint: Color = {
            switch state {
            case .pending: return theme.textSecondary
            case .inspecting, .signing: return theme.primary
            case .ready: return Palette.sky
            case .signed: return Palette.mint
            case .failed: return theme.danger
            case .skipped: return theme.textTertiary
            }
        }()

        HStack(spacing: 4) {
            Image(systemName: state.symbol)
                .font(.system(size: 8.5, weight: .bold))
            Text(state.title)
                .font(.system(size: 9.5, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(Capsule().fill(tint.opacity(theme.isDark ? 0.14 : 0.08)))
    }
}

private struct BatchFileIcon: View {
    let url: URL
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: 28, height: 28)
            .padding(6)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(theme.surfaceLow)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(theme.outline, lineWidth: 1)
            )
    }
}

private struct BatchOptionsCard: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)

        CardSurface(padding: 20, radius: 30) {
            VStack(alignment: .leading, spacing: 14) {
                SectionTitle(
                    L10n.t("批量选项"),
                    subtitle: L10n.t("应用于队列中的所有项目。")
                )

                IdentityMenu(store: store)
                    .disabled(store.batchRunning)

                VStack(spacing: 8) {
                    OptionToggle(
                        title: L10n.t("覆盖签名"),
                        subtitle: "--force",
                        symbol: "arrow.triangle.2.circlepath",
                        isOn: $store.options.force,
                        isEnabled: !store.batchRunning
                    )
                    OptionToggle(
                        title: L10n.t("深度签名"),
                        subtitle: L10n.t("嵌套代码"),
                        symbol: "square.stack.3d.down.right",
                        isOn: $store.options.deep,
                        isEnabled: !store.batchRunning
                    )
                    OptionToggle(
                        title: L10n.t("保留元数据"),
                        subtitle: "entitlements · flags",
                        symbol: "archivebox",
                        isOn: $store.options.preserveMetadata,
                        isEnabled: !store.batchRunning
                    )
                    OptionToggle(
                        title: "Hardened Runtime",
                        subtitle: "--options runtime",
                        symbol: "shield.lefthalf.filled",
                        isOn: $store.options.hardenedRuntime,
                        isEnabled: !store.batchRunning
                    )
                    OptionToggle(
                        title: L10n.t("时间戳"),
                        subtitle: L10n.t("需要证书与联网"),
                        symbol: "clock.badge.checkmark",
                        isOn: $store.options.timestamp,
                        isEnabled: !store.batchRunning && !store.selectedIdentity.isAdHoc
                    )
                    OptionToggle(
                        title: L10n.t("移除 quarantine"),
                        subtitle: L10n.t("签名后清理"),
                        symbol: "sparkles",
                        isOn: $store.options.removeQuarantine,
                        isEnabled: !store.batchRunning
                    )
                }

                EntitlementsRow(store: store)
                    .disabled(store.batchRunning)

                HStack(spacing: 6) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 9.5, weight: .semibold))
                    Text(L10n.t("不可写的对象会失败；请先复制到可写目录。"))
                        .font(.system(size: 9.5, weight: .medium, design: .rounded))
                }
                .foregroundStyle(theme.textTertiary)
            }
        }
    }
}

private struct BatchActivityCard: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        let entries = Array(store.activity.suffix(4).reversed())

        CardSurface(padding: 18, radius: 30) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    SectionTitle(L10n.t("最近活动"))
                    Spacer()
                    Button {
                        store.copyLog()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(theme.textTertiary)
                            .frame(width: 26, height: 26)
                            .background(Circle().fill(theme.surfaceLow))
                    }
                    .buttonStyle(.plain)
                    .help(L10n.t("复制活动日志"))
                }

                if entries.isEmpty {
                    Text(L10n.t("还没有操作记录"))
                        .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.vertical, 8)
                } else {
                    ForEach(entries) { entry in
                        HStack(alignment: .top, spacing: 7) {
                            Image(systemName: entry.level.symbol)
                                .font(.system(size: 8.5, weight: .semibold))
                                .foregroundStyle(levelColor(entry.level, theme: theme))
                                .padding(.top, 1)
                            Text(entry.message)
                                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                                .foregroundStyle(theme.textSecondary)
                                .lineLimit(2)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
    }

    private func levelColor(_ level: LogLevel, theme: Theme) -> Color {
        switch level {
        case .info: return Palette.sky
        case .success: return Palette.mint
        case .warning: return Palette.amber
        case .error: return theme.danger
        }
    }
}

private struct BatchEmptyView: View {
    @ObservedObject var store: AppStore
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let theme = Theme(scheme: colorScheme)
        CardSurface(padding: 40, radius: 30) {
            VStack(spacing: 15) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(theme.primary)
                    .frame(width: 84, height: 84)
                    .background(Circle().fill(theme.primaryContainer.opacity(0.7)))

                Text(L10n.t("批量队列为空"))
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text(L10n.t("一次拖入多个文件，或点击添加文件。"))
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textSecondary)
                    .multilineTextAlignment(.center)

                Button {
                    store.openFilePanel()
                } label: {
                    Label {
                        Text(L10n.t("添加文件…"))
                    } icon: {
                        Image(systemName: "plus")
                    }
                }
                .buttonStyle(PrimaryPillStyle())
            }
            .frame(maxWidth: .infinity, minHeight: 260)
        }
    }
}
