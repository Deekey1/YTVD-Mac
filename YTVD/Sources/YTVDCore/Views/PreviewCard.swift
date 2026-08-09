import SwiftUI

/// Обложка и сведения о ролике. По умолчанию компактная, кнопкой разворачивается на всю ширину.
struct PreviewCard: View {
    @ObservedObject var model: AppModel
    var analyzing: Bool

    @State private var hoveringThumb = false
    @State private var coverJustSaved = false

    var body: some View {
        Group {
            if model.bigPreview {
                VStack(alignment: .leading, spacing: 0) {
                    thumbnail
                        .frame(width: Theme.Metrics.windowWidth,
                               height: Theme.Metrics.windowWidth * 9 / 16)
                    Hairline()
                    meta.padding(.horizontal, 11).padding(.top, 9).padding(.bottom, 10)
                }
            } else {
                HStack(alignment: .top, spacing: 10) {
                    thumbnail
                        .frame(width: Theme.Metrics.compactThumb,
                               height: Theme.Metrics.compactThumb * 9 / 16)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                                .strokeBorder(.black.opacity(0.4), lineWidth: 1))
                    meta
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
            }
        }
        .background(Theme.bg2)
    }

    // MARK: - обложка

    private var thumbnail: some View {
        ZStack {
            if let image = model.thumbnail {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [Color(nsColor: NSColor(hex: "3D4551")),
                                        Color(nsColor: NSColor(hex: "24282E")),
                                        Color(nsColor: NSColor(hex: "191C20"))],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                IconView(.filmSlate, size: model.bigPreview ? 52 : 30, lineWidth: 1.4)
                    .foregroundStyle(.white.opacity(0.16))
            }
            Grain.overlay(opacity: 0.12)

            VStack {
                HStack {
                    Tag(text: model.source.title.uppercased(),
                        color: Theme.sourceColor(model.source),
                        big: model.bigPreview)
                    Spacer()
                }
                Spacer()
                HStack(alignment: .bottom) {
                    if hoveringThumb { overlayButtons.transition(.opacity) }
                    Spacer()
                    if let seconds = model.info?.duration, seconds > 0 {
                        Tag(text: Fmt.duration(Int(seconds)), color: .black.opacity(0.85),
                            big: model.bigPreview, mono: true)
                    }
                }
            }
            .padding(model.bigPreview ? 8 : 5)
        }
        .clipped()
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.14)) { hoveringThumb = hovering }
        }
    }

    private var overlayButtons: some View {
        HStack(spacing: 4) {
            if model.coverOption != nil {
                SmallOverlayButton(icon: coverJustSaved ? .check : .image,
                                   text: coverJustSaved ? "Сохранено" : "JPG",
                                   tint: coverJustSaved ? Theme.green : nil,
                                   help: "Сохранить обложку в JPEG") {
                    model.saveCoverNow()
                    withAnimation { coverJustSaved = true }
                    Task {
                        try? await Task.sleep(nanoseconds: 1_800_000_000)
                        withAnimation { coverJustSaved = false }
                    }
                }
            }
            SmallOverlayButton(icon: model.bigPreview ? .minimize : .expand, text: nil, tint: nil,
                               help: model.bigPreview ? "Компактное превью" : "Крупное превью") {
                withAnimation(.easeInOut(duration: 0.18)) { model.bigPreview.toggle() }
            }
        }
    }

    // MARK: - подписи

    private var meta: some View {
        VStack(alignment: .leading, spacing: 0) {
            if analyzing {
                SkeletonLine(width: 190).padding(.bottom, 5)
                SkeletonLine(width: 130).padding(.bottom, 7)
                SkeletonLine(width: 90, height: 8)
            } else {
                Text(model.info?.displayTitle ?? "")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.text)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                if let author = model.info?.displayAuthor, !author.isEmpty {
                    Text(author)
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .padding(.top, 4)
                }
                if !secondLine.isEmpty {
                    Text(secondLine)
                        .font(Theme.Font.meta)
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                        .padding(.top, 2)
                }
            }
        }
    }

    private var secondLine: String {
        var parts: [String] = []
        if let views = model.info?.view_count, views > 0 { parts.append(Fmt.views(views)) }
        if let raw = model.info?.upload_date, let text = Fmt.uploadDate(raw) { parts.append(text) }
        return parts.joined(separator: " · ")
    }
}

/// Метка поверх обложки: площадка и длительность.
private struct Tag: View {
    let text: String
    let color: Color
    var big: Bool = false
    var mono: Bool = false

    var body: some View {
        Text(text)
            .font(.system(size: big ? 10.5 : 9, weight: .bold))
            .tracking(mono ? 0.2 : 0.6)
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, big ? 7 : 5)
            .frame(height: big ? 20 : 16)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .strokeBorder(.black.opacity(0.3), lineWidth: 1))
    }
}

private struct SmallOverlayButton: View {
    let icon: Icon
    let text: String?
    let tint: Color?
    let help: String
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                IconView(icon, size: 12, lineWidth: 2)
                if let text {
                    Text(text).font(.system(size: 9.5, weight: .semibold)).tracking(0.4)
                }
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(tint ?? (hovering ? Theme.steel : Color.black.opacity(0.86)))
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}

/// Серая полоска на время анализа.
struct SkeletonLine: View {
    var width: CGFloat
    var height: CGFloat = 9
    @State private var bright = false

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(Theme.bg3)
            .frame(width: width, height: height)
            .opacity(bright ? 0.95 : 0.45)
            .animation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true), value: bright)
            .onAppear { bright = true }
    }
}
