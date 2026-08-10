import AppKit
import SwiftUI

/// Всё окно виджета.
public struct RootView: View {
    @ObservedObject public var model: AppModel
    @FocusState private var urlFocused: Bool
    @Environment(\.ytvdSnapshot) private var snapshot

    public init(model: AppModel) { self.model = model }

    public var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                TitleBar(model: model)
                Hairline()

                urlBar
                Hairline()

                // Ссылку из буфера предлагаем всегда, когда не заняты — в том числе
                // после уже скачанного ролика: следующую ссылку копируют именно тогда.
                if let pending = model.clipboardSuggestion,
                   model.stage != .analyzing, model.stage != .downloading {
                    ClipboardStrip(url: pending,
                                   accept: { model.acceptClipboardSuggestion() },
                                   dismiss: { model.dismissClipboardSuggestion() })
                    Hairline()
                }

                if model.info == nil, model.stage == .idle || model.stage == .failed {
                    SourcesStrip()
                    Hairline()
                }

                // Без ffmpeg доступны только готовые файлы со звуком — предупреждаем сразу,
                // а не после неудачной попытки скачать.
                if model.toolchain.isReady, let missing = model.missingTool {
                    WarningStrip(message: missing.message,
                                 action: model.engineUpdating ? "Качаю…" : "Скачать",
                                 keepLabel: true) {
                        model.installMissingTool()
                    }
                    Hairline()
                }

                // Появляется только после сбоя, похожего на устаревший движок.
                if let update = model.engineUpdate {
                    WarningStrip(message: "Похоже, движок устарел — площадки его сломали. "
                                 + "Вышла версия \(update.latest).",
                                 action: model.engineUpdating ? "Обновляю…" : "Обновить",
                                 keepLabel: true) {
                        model.updateEngine()
                    }
                    Hairline()
                }

                if let note = model.engineNote {
                    HStack(spacing: 8) {
                        IconView(.check, size: 14).foregroundStyle(Theme.green)
                        Text(note).font(.system(size: 11.5)).foregroundStyle(Theme.text)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 11).padding(.vertical, 8)
                    .background(Theme.green.opacity(0.16))
                    Hairline()
                }

                if let error = model.errorText {
                    ErrorStrip(message: error,
                               // Варианты уже есть — повторяем саму загрузку, а не разбор.
                               retry: { model.options.isEmpty ? model.submitTypedURL() : model.download() },
                               canRetry: !model.urlText.isEmpty && model.toolchain.isReady)
                    Hairline()
                }

                if model.info != nil || model.stage == .analyzing {
                    PreviewCard(model: model, analyzing: model.stage == .analyzing)
                    Hairline()
                }

                switch model.stage {
                case .analyzing:
                    SkeletonTracks()
                case .ready:
                    TrackListView(model: model)
                case .downloading, .done:
                    JobSection(model: model)
                case .idle, .failed:
                    EmptyView()
                }

                Footer(model: model)
                if model.settings.showKeyboardHints {
                    Hairline()
                    HintBar()
                }
            }

            if model.panel == .settings {
                SettingsPanel(model: model)
                    .padding(.top, Theme.Metrics.titleBar)
                    .transition(.move(edge: .bottom))
            }
            if model.panel == .history {
                HistoryPanel(model: model)
                    .padding(.top, Theme.Metrics.titleBar)
                    .transition(.move(edge: .bottom))
            }
        }
        .frame(width: Theme.Metrics.windowWidth)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.windowRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Metrics.windowRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.07), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: model.stage)
        .animation(.easeInOut(duration: 0.22), value: model.panel)
    }

    // MARK: - строка ссылки

    private var urlBar: some View {
        HStack(spacing: 8) {
            IconView(.linkAlt, size: 15).foregroundStyle(Theme.muted)

            if snapshot {
                // ImageRenderer не умеет рисовать TextField — в снимке показываем тот же текст статично.
                Text(model.urlText.isEmpty ? "Вставьте ссылку — анализ начнётся сам" : model.urlText)
                    .font(.system(size: 13))
                    .foregroundStyle(model.urlText.isEmpty ? Theme.muted : Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                TextField("Вставьте ссылку — анализ начнётся сам", text: $model.urlText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.text)
                    .focused($urlFocused)
                    .onSubmit { model.submitTypedURL() }
                    .onChange(of: model.urlText) { _, newValue in
                        // Ссылку почти всегда вставляют целиком — начинаем сразу.
                        guard model.stage != .analyzing, model.stage != .downloading else { return }
                        guard newValue.count > 12, let url = LinkDetector.firstSupportedURL(in: newValue),
                              url.absoluteString != model.currentAnalyzed else { return }
                        model.analyze(url, autoStart: model.settings.autoDownload)
                    }
            }

            if model.stage == .analyzing {
                ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 16, height: 16)
            } else if !model.urlText.isEmpty {
                Button { model.reset(); urlFocused = true } label: {
                    IconView(.close, size: 12, lineWidth: 2).foregroundStyle(Theme.muted)
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Очистить")
            } else {
                Text("⌘V")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.hair, lineWidth: 1))
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.Metrics.urlBar)
        .background(Theme.bg2)
    }
}

// MARK: - шапка окна

private struct TitleBar: View {
    @ObservedObject var model: AppModel
    @State private var hoveringMark = false

    private var atStart: Bool { model.stage == .idle && model.info == nil }

    var body: some View {
        HStack(spacing: 8) {
            // Логотип работает как «начать заново».
            Button { model.reset() } label: {
                HStack(spacing: 7) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.sourceColor(model.info == nil ? .other : model.source))
                        .frame(width: 9, height: 9)
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(.black.opacity(0.35), lineWidth: 1))
                    Text("YTVD")
                        .font(.system(size: 11, weight: .semibold))
                        .tracking(1.3)
                        .foregroundStyle(hoveringMark && !atStart ? Theme.text : Theme.dim)
                }
                .padding(.horizontal, 5)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(hoveringMark && !atStart ? Theme.bg3 : .clear)
                )
            }
            .buttonStyle(.plain)
            .disabled(atStart)
            .onHover { hoveringMark = $0 }
            .help("Начать заново")

            Spacer()
            IconButton(.pinAlt, active: model.settings.floatOnTop, help: "Поверх всех окон") {
                model.settings.floatOnTop.toggle()
            }
            IconButton(.history, active: model.panel == .history, help: "История ⌘Y") {
                model.panel = model.panel == .history ? nil : .history
            }
            IconButton(.settings, active: model.panel == .settings, help: "Настройки ⌘,") {
                model.panel = model.panel == .settings ? nil : .settings
            }
            IconButton(.close, help: "Скрыть ⎋") {
                NSApp.hide(nil)
            }
        }
        .padding(.leading, 6)
        .padding(.trailing, 8)
        .frame(height: Theme.Metrics.titleBar)
        .background(Theme.chrome)
        .background(WindowDragArea())
    }
}

/// Позволяет таскать окно за шапку.
private struct WindowDragArea: NSViewRepresentable {
    final class DragView: NSView {
        override func mouseDown(with event: NSEvent) {
            window?.performDrag(with: event)
        }
        override var mouseDownCanMoveWindow: Bool { true }
    }
    func makeNSView(context: Context) -> NSView { DragView() }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - полоски состояний

private struct ClipboardStrip: View {
    let url: URL
    let accept: () -> Void
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            IconView(.clipboardCheck, size: 14)
                .foregroundStyle(Theme.blue)
                .help("Ссылка в буфере обмена")
            Text(short)
                .font(.system(size: 12))
                .foregroundStyle(Theme.dim)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            MiniButton(title: "Вставить", action: accept)
            Button(action: dismiss) {
                IconView(.close, size: 12, lineWidth: 2)
                    .foregroundStyle(Theme.muted)
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Скрыть подсказку")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Theme.blue.opacity(0.16))
    }

    /// Обрезку делает сам Text по середине — здесь только убираем шум из начала ссылки.
    private var short: String {
        url.absoluteString
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "www.", with: "")
    }
}

private struct SourcesStrip: View {
    var body: some View {
        HStack(spacing: 13) {
            ForEach([MediaSource.youtube, .vimeo, .rutube, .vk], id: \.self) { source in
                HStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(Theme.sourceColor(source))
                        .frame(width: 9, height: 9)
                        .overlay(RoundedRectangle(cornerRadius: 2)
                            .strokeBorder(.black.opacity(0.4), lineWidth: 1))
                    Text(source.title).font(.system(size: 11)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 9)
        .background(Theme.bg)
    }
}

/// Предупреждение: работать можно, но с оговорками.
private struct WarningStrip: View {
    let message: String
    let action: String
    /// Кнопка сообщает о ходе дела сама — подменять её подпись на «Скопировано» не нужно.
    var keepLabel: Bool = false
    let onAction: () -> Void

    @State private var copied = false

    var body: some View {
        HStack(spacing: 8) {
            IconView(.warningTriangle, size: 14).foregroundStyle(Theme.orange)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            MiniButton(title: copied && !keepLabel ? "Скопировано" : action) {
                onAction()
                guard !keepLabel else { return }
                withAnimation { copied = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    withAnimation { copied = false }
                }
            }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Theme.orange.opacity(0.18))
    }
}

private struct ErrorStrip: View {
    let message: String
    let retry: () -> Void
    let canRetry: Bool

    var body: some View {
        HStack(spacing: 8) {
            IconView(.warningTriangle, size: 14).foregroundStyle(Theme.red)
            Text(message)
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.text)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if canRetry { MiniButton(title: "Повторить", action: retry) }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .background(Theme.red.opacity(0.18))
    }
}

// MARK: - подвал

private struct Footer: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 8) {
            Button { model.chooseDirectory() } label: {
                HStack(spacing: 6) {
                    IconView(.folderDownload, size: 13).foregroundStyle(Theme.muted)
                    Text(model.settings.directoryLabel)
                        .font(.system(size: 11.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                    IconView(.chevronRight, size: 11, lineWidth: 2).foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, 8)
                .frame(width: 104, height: 34)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.bg))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.hair, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help(model.settings.directoryDisplayPath)

            buttons
        }
        .padding(.horizontal, 10)
        .padding(.top, 9)
        .padding(.bottom, 10)
        .background(Theme.bg2)
        .overlay(alignment: .top) { Hairline() }
    }

    @ViewBuilder private var buttons: some View {
        switch model.stage {
        case .downloading:
            PrimaryButton(title: "Отменить", icon: .close, style: .ghost) { model.cancel() }
        case .done:
            PrimaryButton(title: "В Finder", icon: .folder, style: .ghost) { model.revealInFinder() }
            PrimaryButton(title: "Открыть", icon: .play, style: .filled) { model.openFile() }
        case .ready:
            PrimaryButton(title: downloadTitle, icon: .download, style: .filled) { model.download() }
                .disabled(model.selectedOption == nil && !model.coverSelected)
        case .analyzing:
            PrimaryButton(title: "Анализирую…", icon: nil, style: .filled, enabled: false) {}
        case .idle, .failed:
            PrimaryButton(title: model.toolchain.isReady ? "Вставьте ссылку" : "Нужен yt-dlp",
                          icon: nil, style: .filled, enabled: false) {}
        }
    }

    private var downloadTitle: String {
        guard let option = model.selectedOption else { return "Скачать обложку" }
        // Размер показываем, только если он известен: «Скачать M4A · —» читается плохо.
        let size = model.selectionBytes > 0 ? " · \(Fmt.bytes(model.selectionBytes))" : ""
        let cover = model.coverSelected ? " + JPG" : ""
        return "Скачать \(option.title)\(size)\(cover)"
    }
}

enum ButtonStyleKind { case filled, ghost }

struct PrimaryButton: View {
    let title: String
    let icon: Icon?
    let style: ButtonStyleKind
    var enabled: Bool = true
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let icon { IconView(icon, size: 15, lineWidth: 2) }
                Text(title).font(Theme.Font.button).lineLimit(1)
            }
            .foregroundStyle(style == .filled ? Color.white : Theme.text)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background {
                if style == .filled {
                    BlockBackground(color: Theme.blue, radius: 6)
                } else {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Theme.bg3)
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .strokeBorder(Theme.hair, lineWidth: 1))
                }
            }
            .brightness(hovering && enabled ? 0.07 : 0)
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .onHover { hovering = $0 }
    }
}

struct MiniButton: View {
    let title: String
    var icon: Icon?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if let icon { IconView(icon, size: 12, lineWidth: 2) }
                Text(title).font(.system(size: 11))
            }
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 9)
            .frame(height: 22)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(hovering ? Theme.bg2 : Theme.bg3))
            .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(hovering ? Theme.dim : Theme.hair, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

private struct HintBar: View {
    private let hints: [(String, String)] = [
        ("⌘V", "вставить"), ("↑↓", "выбрать"), ("⏎", "скачать"), ("⌘,", "настройки"), ("⎋", "скрыть"),
    ]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(hints, id: \.0) { key, label in
                HStack(spacing: 3) {
                    Text(key).font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.dim)
                    Text(label).font(.system(size: 10)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 6)
        .background(Theme.chrome)
    }
}

extension AppModel {
    /// Ссылка, которую уже разбираем — чтобы не запускать анализ повторно на каждый символ.
    var currentAnalyzed: String? { info != nil || stage == .analyzing ? urlText : nil }
}
