import SwiftData
import SwiftUI
import YTVDAPI
import YTVDIcons

/// Главный экран: ссылка, превью, качество, загрузки. Устроен как окно YTVD на Mac.
struct DownloadView: View {
    @Bindable var model: DownloadModel
    @Environment(Connection.self) private var connection
    @Environment(TransferService.self) private var transfers
    @Environment(\.modelContext) private var context
    @FocusState private var fieldFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(title: "Скачать") {
                    if model.state != .idle {
                        IconToolButton(icon: .close, label: "Очистить") { model.clear() }
                    }
                }
                ScrollView {
                    VStack(spacing: 0) {
                        ConnectionBanner()
                        linkPanel
                        stateContent
                        if !transfers.transfers.isEmpty { transfersSection }
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .background(Theme.bg)
            .toolbar(.hidden, for: .navigationBar)
            .ytvdTabBar()
            .confirmationDialog("Видео уже находится в библиотеке", isPresented: duplicateShown,
                                titleVisibility: .visible, presenting: model.duplicate) { duplicate in
                Button("Смотреть") { PlaybackController.shared.play(duplicate.existing) }
                Button("Скачать в другом качестве") {
                    model.start(video: duplicate.video, format: duplicate.format, replacing: nil, transfers: transfers)
                }
                Button("Заменить", role: .destructive) {
                    model.start(video: duplicate.video, format: duplicate.format,
                                replacing: duplicate.existing.id, transfers: transfers)
                }
                Button("Отмена", role: .cancel) {}
            } message: { duplicate in
                Text("Уже скачано: \(duplicate.existing.summary). Сейчас выбрано: \(duplicate.format.label).")
            }
            .alert("Не получилось", isPresented: alertShown) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.alert ?? "")
            }
        }
    }

    // MARK: - ссылка

    /// Строка ссылки — как на Mac: значок, поле и справа то, что уместно сейчас.
    /// Пусто — «Вставить»; есть неразобранная ссылка — «Загрузить»; идёт разбор — индикатор.
    private var linkPanel: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                IconView(.linkAlt, size: 20, lineWidth: 1.8).foregroundStyle(Theme.muted)
                TextField("", text: $model.text,
                          prompt: Text("Вставьте ссылку на видео").foregroundStyle(Theme.muted),
                          axis: .vertical)
                    .lineLimit(1...3)
                    .font(.body)
                    .foregroundStyle(Theme.text)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.go)
                    .focused($fieldFocused)
                    .onSubmit(resolve)
                linkAccessory
            }
            .padding(.leading, 14)
            .padding(.trailing, 10)
            .frame(minHeight: 58)
            // Ссылку читать не нужно — строка растёт до разумного предела, кнопки в ней тоже.
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .animation(.easeInOut(duration: 0.15), value: model.text.isEmpty)
            .animation(.easeInOut(duration: 0.15), value: model.needsResolve)
            if model.clipboardHasLink, model.text.isEmpty {
                Text("В буфере обмена есть ссылка — нажмите «Вставить».")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Metrics.gutter)
                    .padding(.bottom, 10)
            }
            Hairline()
        }
        .background(Theme.bg2)
    }

    @ViewBuilder
    private var linkAccessory: some View {
        if model.state == .resolving {
            ProgressView().tint(Theme.dim).frame(width: 34, height: 34)
        } else if model.text.isEmpty {
            // Системная кнопка: вставляет без вопроса «Разрешить вставку?».
            PasteButton(supportedContentTypes: [.url, .plainText]) { providers in
                model.paste(providers, connection: connection)
            }
            .labelStyle(.titleAndIcon)
            .buttonBorderShape(.roundedRectangle(radius: 8))
            .tint(Theme.steel)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        } else {
            Button { model.text = "" } label: {
                IconView(.close, size: 16, lineWidth: 2).foregroundStyle(Theme.muted)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Стереть ссылку")
            if model.needsResolve {
                Button(action: resolve) {
                    HStack(spacing: 6) {
                        IconView(.arrowRight, size: 16, lineWidth: 2.2)
                        Text("Загрузить")
                    }
                }
                .buttonStyle(PrimaryButtonStyle(height: 38, expand: false))
                .fixedSize()
                .transition(.opacity)
            }
        }
    }

    // MARK: - состояние разбора

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .idle:
            if transfers.transfers.isEmpty {
                EmptyState(icon: .download, title: "Готов к загрузке",
                           detail: "Поделитесь ссылкой из YouTube, Vimeo, Rutube или VK Видео — или вставьте её сюда.")
            }
        case .resolving:
            ResolvingCard()
        case .failed(let message):
            WarningBanner(title: "Не получилось", detail: message)
        case .ready(let video):
            VideoPreviewSections(video: video, selection: $model.selectedFormatId,
                                 isStarting: model.isStarting) {
                model.download(context: context, transfers: transfers)
            }
        }
    }

    private var transfersSection: some View {
        VStack(spacing: 0) {
            GroupHeader(title: "Загрузки", trailing: "\(transfers.transfers.count)")
            ForEach(transfers.transfers) { transfer in
                TransferRow(transfer: transfer)
            }
        }
    }

    private func resolve() {
        fieldFocused = false
        guard model.canResolve else { return }
        model.resolve(connection: connection)
    }

    private var duplicateShown: Binding<Bool> {
        Binding(get: { model.duplicate != nil }, set: { if !$0 { model.duplicate = nil } })
    }

    private var alertShown: Binding<Bool> {
        Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })
    }
}

/// Подсказка, если Mac не выбран, не сопряжён или недоступен.
struct ConnectionBanner: View {
    @Environment(Connection.self) private var connection

    var body: some View {
        switch connection.status {
        case .online, .checking:
            EmptyView()
        case .notConfigured:
            WarningBanner(title: "Выберите Mac в настройках",
                          detail: "На Mac: YTVD → Настройки → «Сервер для iPhone».", icon: .tv)
        case .unpaired:
            WarningBanner(title: "Нужно сопряжение с Mac",
                          detail: "Введите код с Mac во вкладке «Настройки».", icon: .lock)
        case .offline(let message):
            WarningBanner(title: "Mac недоступен", detail: message)
        }
    }
}

/// Пока Mac разбирает ссылку — серые заготовки на месте обложки и названия.
private struct ResolvingCard: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                    .fill(Theme.bg3)
                    .frame(width: 150, height: 84)
                    .overlay(ProgressView().tint(Theme.dim))
                VStack(alignment: .leading, spacing: 8) {
                    SkeletonLine(width: 170)
                    SkeletonLine(width: 120)
                    Text("Mac разбирает ссылку…").font(.footnote).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Metrics.gutter)
            .background(Theme.bg2)
            Hairline()
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Mac разбирает ссылку")
    }
}

struct SkeletonLine: View {
    let width: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.bg3)
            .frame(maxWidth: width)
            .frame(height: 11)
    }
}

// MARK: - превью и качество

/// Обложка и сведения о ролике — как карточка превью на Mac.
struct PreviewCard: View {
    let video: VideoInfo
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
        VStack(spacing: 0) {
            layout {
                if typeSize.isAccessibilitySize {
                    ThumbnailView(remote: video.thumbnail, platform: video.platform, duration: video.duration)
                        .aspectRatio(16 / 9, contentMode: .fit)
                        .frame(maxWidth: .infinity)
                } else {
                    ThumbnailView(remote: video.thumbnail, platform: video.platform, duration: video.duration)
                        .frame(width: 150, height: 150 * 9 / 16)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(video.title)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.text)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                    if let channel = video.channel {
                        Text(channel).font(Theme.Font.meta).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                    Text(Theme.source(video.platform).title)
                        .font(Theme.Font.meta).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
            }
            .padding(Theme.Metrics.gutter)
            .background(Theme.bg2)
            Hairline()
        }
    }
}

/// Превью ролика и выбор качества.
struct VideoPreviewSections: View {
    let video: VideoInfo
    @Binding var selection: String?
    let isStarting: Bool
    let onDownload: () -> Void

    @State private var showDetails = false

    private var selected: VideoFormat? { video.formats.first { $0.id == selection } }
    private var maxSize: Int64 { video.formats.compactMap(\.estimatedSize).max() ?? 0 }

    var body: some View {
        VStack(spacing: 0) {
            PreviewCard(video: video)
            GroupHeader(title: "Качество",
                        trailing: Fmt.plural(video.formats.count, "вариант", "варианта", "вариантов"))
            ForEach(video.formats) { format in
                FormatRow(format: format, isSelected: format.id == selection,
                          isRecommended: format.id == video.recommendedFormatId, maxSize: maxSize) {
                    selection = format.id
                }
            }
            if selected?.needsTranscode == true {
                hint("Выше 1080p YouTube отдаёт только VP9 или AV1 — Mac перекодирует видео в HEVC. Это дольше, чем просто скачать.")
            }
            detailsToggle
            if showDetails { details }

            VStack(spacing: 0) {
                Button(action: onDownload) {
                    HStack(spacing: 8) {
                        if isStarting {
                            ProgressView().tint(.white)
                        } else {
                            IconView(.download, size: 19, lineWidth: 2.1)
                            Text(downloadTitle)
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selection == nil || isStarting)
                .padding(Theme.Metrics.gutter)
                Hairline()
            }
            .background(Theme.bg2)
        }
    }

    /// «Скачать 1080p60 · 318 МБ» — как на кнопке Mac.
    private var downloadTitle: String {
        guard let selected else { return "Скачать" }
        return ["Скачать \(selected.label)", selected.sizeText].compactMap { $0 }.joined(separator: " · ")
    }

    private func hint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            IconView(.sparkles, size: 15, lineWidth: 1.8).foregroundStyle(Theme.muted)
            Text(text).font(.footnote).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 10)
        .background(Theme.lane)
        .overlay(alignment: .bottom) { Hairline() }
    }

    private var detailsToggle: some View {
        Button { withAnimation(.easeOut(duration: 0.15)) { showDetails.toggle() } } label: {
            HStack(spacing: 8) {
                IconView(.chevronRight, size: 13, lineWidth: 2)
                    .foregroundStyle(Theme.muted)
                    .rotationEffect(.degrees(showDetails ? 90 : 0))
                Text("Подробности").font(.subheadline).foregroundStyle(Theme.dim)
                Spacer()
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .frame(minHeight: 44)
            .background(Theme.bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityValue(showDetails ? "Развёрнуто" : "Свёрнуто")
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(video.formats) { format in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(format.label) — \(format.codecTitle), \(format.container.uppercased())")
                        .font(.footnote.weight(.medium)).foregroundStyle(Theme.text)
                    if let details = format.details {
                        Text(details).font(.caption).foregroundStyle(Theme.muted)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Metrics.gutter)
        .padding(.vertical, 10)
        .background(Theme.lane)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

/// Строка варианта: цветной квадратик, подпись и плашка размера — как в списке на Mac.
struct FormatRow: View {
    let format: VideoFormat
    let isSelected: Bool
    let isRecommended: Bool
    let maxSize: Int64
    let action: () -> Void

    @ScaledMetric(relativeTo: .body) private var labelWidth: CGFloat = 112

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                HStack(spacing: 10) {
                    Swatch(color: format.tint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(format.label).font(Theme.Font.row).foregroundStyle(Theme.text)
                        if let subtitle {
                            Text(subtitle).font(.caption).foregroundStyle(Theme.muted)
                        }
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    Spacer(minLength: 0)
                }
                .padding(.leading, Theme.Metrics.gutter)
                .frame(width: labelWidth + 34, alignment: .leading)

                Theme.sep.frame(width: 1)

                SizeBar(fraction: fraction, color: format.tint, text: format.sizeText ?? "размер ?",
                        selected: isSelected)
                    .padding(.leading, 8)
                    .padding(.trailing, Theme.Metrics.gutter)
            }
            .frame(minHeight: 50)
            .background(isSelected ? Theme.bg3 : Theme.bg)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Hairline() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel([format.displayTitle, subtitle, format.sizeText].compactMap { $0 }.joined(separator: ", "))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    /// «Full HD», «4K · HEVC на Mac», «рекомендуется», «M4A» — одной короткой строкой.
    private var subtitle: String? {
        if !format.hasVideo { return format.container.uppercased() }
        if format.needsTranscode {
            return [format.classTitle, "HEVC на Mac"].compactMap { $0 }.joined(separator: " · ")
        }
        return isRecommended ? "рекомендуется" : format.classTitle
    }

    /// Длина плашки — по размеру файла, с корнем: маленькие варианты не превращаются в точку.
    private var fraction: Double {
        guard let size = format.estimatedSize, size > 0, maxSize > 0 else { return 0.2 }
        return 0.2 + 0.8 * (Double(size) / Double(maxSize)).squareRoot()
    }
}

/// Фактурная плашка размера. Выбранная — с белой рамкой и галочкой.
struct SizeBar: View {
    let fraction: Double
    let color: Color
    let text: String
    let selected: Bool

    var body: some View {
        GeometryReader { geometry in
            let width = max(44, geometry.size.width * min(1, fraction))
            let inside = fraction >= 0.5
            HStack(spacing: 8) {
                ZStack {
                    BlockBackground(color: color)
                    HStack(spacing: 5) {
                        if selected { IconView(.check, size: 14, lineWidth: 2.4).foregroundStyle(.white) }
                        Spacer(minLength: 0)
                        if inside {
                            Text(text)
                                .font(Theme.Font.block)
                                .foregroundStyle(.white)
                                .shadow(color: .black.opacity(0.28), radius: 0.5, y: 1)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, 8)
                }
                .frame(width: width, height: Theme.Metrics.blockHeight)
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Metrics.radius + 1.5, style: .continuous)
                        .strokeBorder(Theme.focus, lineWidth: selected ? 2 : 0)
                        .padding(-1.5)
                )
                if !inside {
                    Text(text)
                        .font(.system(.footnote, weight: .medium)).monospacedDigit()
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                Spacer(minLength: 0)
            }
            .frame(height: geometry.size.height)
        }
        .frame(height: Theme.Metrics.blockHeight + 8)
        .animation(.easeOut(duration: 0.14), value: selected)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

extension VideoFormat {
    /// Цвет варианта — как на Mac: синий — H.264 как есть, оранжевый — Mac перекодирует,
    /// красный — только звук.
    var tint: Color {
        if !hasVideo { return Theme.red }
        return needsTranscode ? Theme.orange : Theme.blue
    }

    /// «4K», «Full HD», «HD».
    var classTitle: String? {
        guard hasVideo else { return nil }
        switch classHeight {
        case 4320...: return "8K"
        case 2160...: return "4K"
        case 1440...: return "2K"
        case 1080...: return "Full HD"
        case 720...: return "HD"
        default: return nil
        }
    }
}
