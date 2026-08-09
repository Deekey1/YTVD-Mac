import SwiftUI

/// Список вариантов в виде дорожек: длина плашки = вес файла.
struct TrackListView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ruler
            ForEach(DownloadOption.Group.allCases, id: \.self) { group in
                let items = model.options.filter {
                    $0.group == group && (model.showAlternatives || !$0.isAlternative)
                }
                if !items.isEmpty || group == .video {
                    GroupHeader(group: group,
                                count: items.count,
                                open: model.openGroups.contains(group)) {
                        model.toggleGroup(group)
                    }
                    Hairline()
                    if model.openGroups.contains(group) {
                        ForEach(items) { option in
                            OptionRow(model: model, option: option)
                            Hairline()
                        }
                        if group == .video, model.hiddenAlternatives > 0 {
                            MoreRow(label: model.alternativesLabel) {
                                withAnimation(.easeOut(duration: 0.16)) { model.showAlternatives = true }
                            }
                            Hairline()
                        }
                    }
                }
            }
        }
        .background(Theme.bg)
    }

    private var ruler: some View {
        HStack(spacing: 0) {
            Text("РАЗМЕР")
                .font(Theme.Font.group)
                .tracking(1)
                .foregroundStyle(Theme.muted)
                .padding(.leading, 11)
                .frame(width: Theme.Metrics.headerColumn - 1, height: 20, alignment: .leading)
            Theme.sep.frame(width: 1, height: 20)
            ZStack(alignment: .topLeading) {
                Color.clear
                ForEach(model.rulerTicks(), id: \.label) { tick in
                    let flip = tick.x > Theme.Metrics.lane - 48
                    HStack(spacing: 0) {
                        Theme.hair.frame(width: 1, height: 20)
                        Text(tick.label)
                            .font(.system(size: 9.5))
                            .foregroundStyle(Theme.muted)
                            .fixedSize()
                            .padding(.leading, flip ? 0 : 4)
                            .offset(x: flip ? -46 : 0)
                    }
                    .offset(x: tick.x)
                }
            }
            .frame(height: 20)
            .padding(.leading, Theme.Metrics.laneLeading)
            .padding(.trailing, Theme.Metrics.laneTrailing)
            .clipped()
        }
        .frame(height: 21)
        .background(Theme.bg)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

// MARK: - заголовок группы

private struct GroupHeader: View {
    let group: DownloadOption.Group
    let count: Int
    let open: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 5) {
                IconView(.chevronDown, size: 11, lineWidth: 2)
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(open ? 0 : -90))
                Text(group.title.uppercased())
                    .font(Theme.Font.group)
                    .tracking(1.1)
                    .foregroundStyle(Theme.dim)
            }
            .padding(.leading, 7)
            .frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.groupHeight, alignment: .leading)

            Theme.sep.frame(width: 1, height: Theme.Metrics.groupHeight)

            Spacer(minLength: 0)
            Text(countText)
                .font(.system(size: 9.5))
                .foregroundStyle(Theme.muted)
                .padding(.trailing, Theme.Metrics.laneTrailing)
        }
        .frame(height: Theme.Metrics.groupHeight)
        .background(Theme.bg2)
        .contentShape(Rectangle())
        .onTapGesture(perform: toggle)
    }

    private var countText: String {
        group == .cover
            ? Fmt.plural(count, "файл", "файла", "файлов")
            : Fmt.plural(count, "вариант", "варианта", "вариантов")
    }
}

// MARK: - строка варианта

private struct OptionRow: View {
    @ObservedObject var model: AppModel
    let option: DownloadOption

    @State private var hovering = false

    private var selected: Bool {
        option.group == .cover ? model.coverSelected : model.selectedID == option.id
    }
    private var expanded: Bool { model.expandedID == option.id }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                header
                Theme.sep.frame(width: 1, height: Theme.Metrics.rowHeight)
                lane
            }
            .frame(height: Theme.Metrics.rowHeight)
            .background(selected ? Theme.bg3 : (hovering ? Theme.bg2 : Theme.bg))
            .contentShape(Rectangle())
            .onTapGesture { model.select(option) }
            .onHover { hovering = $0 }

            if expanded { details }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            IconView(.chevronRight, size: 11, lineWidth: 2)
                .foregroundStyle(Theme.muted)
                .rotationEffect(.degrees(expanded ? 90 : 0))
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeOut(duration: 0.14)) { model.toggleExpanded(option) } }

            RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .fill(Theme.tint(option.tint))
                .frame(width: 11, height: 11)
                .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .strokeBorder(.black.opacity(0.4), lineWidth: 1))

            HStack(spacing: 4) {
                Text(option.title)
                    .font(Theme.Font.row)
                    .foregroundStyle(Theme.text)
                if !option.subtitle.isEmpty {
                    Text(option.subtitle)
                        .font(Theme.Font.rowSub)
                        .foregroundStyle(Theme.muted)
                }
            }
            .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.leading, 7)
        .padding(.trailing, 8)
        .frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.rowHeight)
    }

    private var lane: some View {
        let width = model.blockWidth(for: option)
        let showBadgeInside = option.badge != nil && width >= 104
        let showSizeInside = width >= (showBadgeInside ? 104 : 76)

        return HStack(spacing: 7) {
            block(width: width, badgeInside: showBadgeInside, sizeInside: showSizeInside)
            if !showSizeInside || (option.badge != nil && !showBadgeInside) {
                HStack(spacing: 5) {
                    if let badge = option.badge, !showBadgeInside {
                        BadgeView(text: badge, outside: true)
                    }
                    if !showSizeInside {
                        Text(option.sizeText)
                            .font(.system(size: 10.5, weight: .medium))
                            .foregroundStyle(Theme.dim)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, Theme.Metrics.laneLeading)
        .padding(.trailing, Theme.Metrics.laneTrailing)
        .frame(height: Theme.Metrics.rowHeight)
        .clipped()
    }

    private func block(width: CGFloat, badgeInside: Bool, sizeInside: Bool) -> some View {
        ZStack {
            BlockBackground(color: Theme.tint(option.tint))
            HStack(spacing: 5) {
                if selected {
                    IconView(.check, size: 12, lineWidth: 2.4).foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                if badgeInside, let badge = option.badge { BadgeView(text: badge, outside: false) }
                if sizeInside {
                    Text(option.sizeText)
                        .font(Theme.Font.block)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.28), radius: 0.5, y: 1)
                }
            }
            .padding(.horizontal, 7)
        }
        .frame(width: width, height: Theme.Metrics.blockHeight)
        .brightness(hovering ? 0.06 : 0)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.radius + 1.5, style: .continuous)
                .strokeBorder(Theme.focus, lineWidth: selected ? 2 : 0)
                .padding(-1.5)
        )
        .animation(.easeOut(duration: 0.14), value: selected)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(option.detail)
                .font(Theme.Font.detail)
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
            if !option.hint.isEmpty {
                HStack(spacing: 5) {
                    IconView(.sparkles, size: 12, lineWidth: 1.8).foregroundStyle(Theme.muted)
                    Text(option.hint)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 25)
        .padding(.trailing, 11)
        .padding(.vertical, 7)
        .background(Theme.lane)
        .overlay(alignment: .top) { Hairline() }
    }
}

private struct BadgeView: View {
    let text: String
    let outside: Bool

    var body: some View {
        Text(text)
            .font(Theme.Font.badge)
            .tracking(0.6)
            .foregroundStyle(outside ? Theme.muted : .white.opacity(0.92))
            .padding(.horizontal, 5)
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(outside ? Theme.bg3 : Color.black.opacity(0.26))
            )
    }
}

// MARK: - «ещё N вариантов»

private struct MoreRow: View {
    let label: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.groupHeight)
            Theme.sep.frame(width: 1, height: Theme.Metrics.groupHeight)
            HStack(spacing: 5) {
                IconView(.add, size: 11, lineWidth: 2)
                Text(label)
                    .font(.system(size: 10.5))
                    .lineLimit(1)
            }
            .foregroundStyle(hovering ? Theme.dim : Theme.muted)
            .padding(.leading, Theme.Metrics.laneLeading)
            Spacer(minLength: 0)
        }
        .frame(height: Theme.Metrics.groupHeight)
        .background(hovering ? Theme.bg2 : Theme.bg)
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .onHover { hovering = $0 }
    }
}

// MARK: - идёт загрузка

struct JobSection: View {
    @ObservedObject var model: AppModel

    var body: some View {
        let done = model.stage == .done
        let option = model.selectedOption

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    IconView(.chevronDown, size: 11, lineWidth: 2).foregroundStyle(Theme.muted)
                    Text(done ? "ЗАГРУЖЕНО" : "ЗАГРУЗКА")
                        .font(Theme.Font.group).tracking(1.1).foregroundStyle(Theme.dim)
                }
                .padding(.leading, 7)
                .frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.groupHeight, alignment: .leading)
                Theme.sep.frame(width: 1, height: Theme.Metrics.groupHeight)
                Spacer(minLength: 0)
                Text(queueText)
                    .font(.system(size: 9.5))
                    .foregroundStyle(Theme.muted)
                    .padding(.trailing, Theme.Metrics.laneTrailing)
            }
            .frame(height: Theme.Metrics.groupHeight)
            .background(Theme.bg2)
            Hairline()

            HStack(spacing: 0) {
                HStack(spacing: 6) {
                    IconView(.chevronRight, size: 11, lineWidth: 2).foregroundStyle(Theme.muted)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(Theme.tint(option?.tint ?? .blue))
                        .frame(width: 11, height: 11)
                        .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .strokeBorder(.black.opacity(0.4), lineWidth: 1))
                    HStack(spacing: 4) {
                        Text(option?.title ?? "Файл").font(Theme.Font.row).foregroundStyle(Theme.text)
                        if let subtitle = option?.subtitle, !subtitle.isEmpty {
                            Text(subtitle).font(Theme.Font.rowSub).foregroundStyle(Theme.muted)
                        }
                    }
                    .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 7)
                .frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.rowHeight)

                Theme.sep.frame(width: 1, height: Theme.Metrics.rowHeight)

                ProgressTrack(fraction: done ? 1 : (model.progress?.fraction ?? 0),
                              label: done ? Fmt.bytes(model.finished?.bytes ?? 0) : percentText,
                              color: done ? Theme.green : Theme.tint(option?.tint ?? .blue),
                              indeterminate: !done && model.progress?.fraction == nil)
                    .padding(.leading, Theme.Metrics.laneLeading)
                    .padding(.trailing, Theme.Metrics.laneTrailing)
            }
            .frame(height: Theme.Metrics.rowHeight)
            .background(Theme.bg3)
            Hairline()

            if done {
                HStack(spacing: 8) {
                    IconView(.checkDouble, size: 14, lineWidth: 2).foregroundStyle(Theme.green)
                    Text(doneText)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 8)
                .background(Theme.green.opacity(0.16))
                Hairline()
            } else {
                HStack(spacing: 0) {
                    Text(model.phaseText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.muted)
                        .padding(.leading, 25)
                        .frame(width: Theme.Metrics.headerColumn - 1, alignment: .leading)
                    Theme.sep.frame(width: 1)
                    Text(statsText)
                        .font(.system(size: 10.5))
                        .monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .padding(.leading, Theme.Metrics.laneLeading)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .frame(height: 18)
                .padding(.bottom, 5)
                .background(Theme.bg)
                Hairline()

                ForEach(model.queue) { item in
                    QueueRow(item: item)
                    Hairline()
                }
            }
        }
    }

    private var percentText: String {
        guard let fraction = model.progress?.fraction else { return "…" }
        return "\(Int((fraction * 100).rounded())) %"
    }

    private var queueText: String {
        model.queue.isEmpty ? "1 из 1" : "1 из \(model.queue.count + 1)"
    }

    private var doneText: String {
        let path = model.settings.directoryDisplayPath
        let seconds = model.finished?.seconds ?? 0
        return seconds > 0 ? "Сохранено в \(path) — за \(Fmt.elapsed(seconds))" : "Сохранено в \(path)"
    }

    private var statsText: String {
        guard let progress = model.progress else { return "—" }
        var parts: [String] = []
        if let speed = progress.speed { parts.append(Fmt.speed(speed)) }
        if let eta = progress.eta, eta > 0 { parts.append(Fmt.eta(eta)) }
        if let total = progress.total, total > 0 {
            parts.append(Fmt.progressBytes(done: progress.downloaded, total: total))
        } else if progress.downloaded > 0 {
            parts.append(Fmt.bytes(progress.downloaded))
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

/// Полоса прогресса на всю ширину дорожки.
private struct ProgressTrack: View {
    let fraction: Double
    let label: String
    let color: Color
    var indeterminate: Bool = false

    @State private var shimmer = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                    .fill(Theme.lane)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                        .strokeBorder(.black.opacity(0.4), lineWidth: 1))

                BlockBackground(color: color)
                    .frame(width: max(indeterminate ? 26 : 0, geometry.size.width * fraction))
                    .offset(x: indeterminate ? (shimmer ? geometry.size.width - 26 : 0) : 0)
                    .animation(.linear(duration: 0.3), value: fraction)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shimmer)

                HStack {
                    Spacer()
                    Text(label)
                        .font(Theme.Font.block)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.5), radius: 1, y: 1)
                        .padding(.trailing, 7)
                }
            }
        }
        .frame(height: Theme.Metrics.blockHeight)
        .onAppear { if indeterminate { shimmer = true } }
    }
}

private struct QueueRow: View {
    let item: AppModel.QueueItem

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                IconView(.chevronRight, size: 11, lineWidth: 2).foregroundStyle(Theme.muted)
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Theme.sourceColor(item.source))
                    .frame(width: 11, height: 11)
                Text(item.source.title).font(Theme.Font.row).foregroundStyle(Theme.text).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.leading, 7)
            .frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.rowHeight)
            Theme.sep.frame(width: 1, height: Theme.Metrics.rowHeight)
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous).fill(Theme.bg3)
                Text("в очереди").font(Theme.Font.block).foregroundStyle(Theme.muted)
            }
            .frame(width: 118, height: Theme.Metrics.blockHeight)
            .padding(.leading, Theme.Metrics.laneLeading)
            Spacer(minLength: 0)
        }
        .frame(height: Theme.Metrics.rowHeight)
        .background(Theme.bg)
        .opacity(0.62)
    }
}

/// Скелет на время анализа — те же дорожки, только серые.
struct SkeletonTracks: View {
    private let widths: [CGFloat] = [0.85, 0.55, 0.68, 0.34, 0.22, 0.44]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 5) {
                    IconView(.chevronDown, size: 11, lineWidth: 2).foregroundStyle(Theme.muted)
                    Text("АНАЛИЗ ССЫЛКИ").font(Theme.Font.group).tracking(1.1).foregroundStyle(Theme.dim)
                }
                .padding(.leading, 7)
                .frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.groupHeight, alignment: .leading)
                Theme.sep.frame(width: 1, height: Theme.Metrics.groupHeight)
                Spacer(minLength: 0)
                Text("yt-dlp").font(.system(size: 9.5)).foregroundStyle(Theme.muted)
                    .padding(.trailing, Theme.Metrics.laneTrailing)
            }
            .frame(height: Theme.Metrics.groupHeight)
            .background(Theme.bg2)
            Hairline()

            ForEach(Array(widths.enumerated()), id: \.offset) { _, factor in
                HStack(spacing: 0) {
                    HStack(spacing: 6) {
                        Color.clear.frame(width: 11, height: 11)
                        RoundedRectangle(cornerRadius: 2.5).fill(Theme.bg3).frame(width: 11, height: 11)
                        SkeletonLine(width: 40 + factor * 46)
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, 7)
                    .frame(width: Theme.Metrics.headerColumn - 1, height: Theme.Metrics.rowHeight)
                    Theme.sep.frame(width: 1, height: Theme.Metrics.rowHeight)
                    SkeletonLine(width: factor * Theme.Metrics.lane, height: Theme.Metrics.blockHeight)
                        .padding(.leading, Theme.Metrics.laneLeading)
                    Spacer(minLength: 0)
                }
                .frame(height: Theme.Metrics.rowHeight)
                .background(Theme.bg)
                Hairline()
            }
        }
    }
}
