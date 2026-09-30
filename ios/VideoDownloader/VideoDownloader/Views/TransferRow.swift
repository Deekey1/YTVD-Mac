import SwiftUI
import YTVDIcons

/// Карточка загрузки — как блок «Загрузка» на Mac: этап, полоса хода, скорость и время.
struct TransferRow: View {
    let transfer: Transfer
    @Environment(TransferService.self) private var transfers

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .top, spacing: 10) {
                    ThumbnailView(local: transfer.thumbnailURL, remote: transfer.video.thumbnail)
                        .frame(width: 72, height: 40.5)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(transfer.video.title)
                            .font(.system(.subheadline, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        HStack(spacing: 6) {
                            Swatch(color: transfer.format.tint, size: 9)
                            Text("\(transfer.format.label) · \(transfer.stageTitle)")
                                .font(.caption)
                                .foregroundStyle(transfer.phase == .failed ? Theme.red : Theme.dim)
                                .lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }

                if transfer.isActive {
                    ProgressTrack(fraction: transfer.fraction,
                                  label: transfer.fraction.map(Fmt.percent) ?? transfer.stageTitle,
                                  color: transfer.format.tint)
                }
                if let line = transfer.detailLine {
                    Text(line).font(.caption.monospacedDigit()).foregroundStyle(Theme.muted)
                }
                if transfer.phase == .failed, let error = transfer.error {
                    Text(error).font(.caption).foregroundStyle(Theme.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 8) {
                    Spacer()
                    if transfer.phase == .failed {
                        Button("Повторить") { Task { await transfers.retry(transfer.id) } }
                            .buttonStyle(MiniButtonStyle())
                    }
                    if transfer.isActive {
                        Button("Отменить") { Task { await transfers.cancel(transfer.id) } }
                            .buttonStyle(MiniButtonStyle(tint: Theme.red))
                    } else {
                        Button("Убрать") { transfers.remove(transfer.id) }
                            .buttonStyle(MiniButtonStyle())
                    }
                }
            }
            .padding(Theme.Metrics.gutter)
            .background(Theme.bg)
            Hairline()
        }
    }
}

/// Обложка: своя копия с диска, иначе из сети, иначе заглушка — как на Mac: тёмный
/// градиент с зерном. Поверх — площадка, длительность и сколько уже просмотрено.
struct ThumbnailView: View {
    var local: URL?
    var remote: String?
    var platform: String?
    var duration: Double?
    /// Доля просмотренного — синяя полоса по низу.
    var progress: Double?
    var audioOnly = false

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        // Размер задаёт тот, кто ставит обложку (frame или aspectRatio). Картинка лежит
        // поверх и обрезается по нему — иначе scaledToFill раздувает весь блок.
        Color.clear
            .overlay { placeholder }
            .overlay {
                if let image = localImage {
                    Image(uiImage: image).resizable().scaledToFill()
                } else if let remote, let url = URL(string: remote) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image { image.resizable().scaledToFill() }
                    }
                }
            }
            .overlay { tags }
            .overlay(alignment: .bottom) {
            if let progress {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.black.opacity(0.55))
                        Rectangle().fill(Theme.blue).frame(width: geometry.size.width * min(1, max(0, progress)))
                    }
                }
                .frame(height: 3)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
            .strokeBorder(.black.opacity(0.4), lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x3D4551), Color(hex: 0x24282E), Color(hex: 0x191C20)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            IconView(audioOnly ? .headphones : .filmSlate, size: 26, lineWidth: 1.4)
                .foregroundStyle(.white.opacity(0.18))
            Grain.overlay(opacity: 0.12)
        }
    }

    private var tags: some View {
        VStack {
            HStack {
                if let platform {
                    let source = Theme.source(platform)
                    Tag(text: source.title.uppercased(), color: Theme.sourceColor(source))
                }
                Spacer(minLength: 0)
            }
            Spacer(minLength: 0)
            HStack {
                Spacer(minLength: 0)
                if let duration, duration > 0 {
                    Tag(text: Fmt.duration(duration), color: .black.opacity(0.85), mono: true)
                }
            }
        }
        .padding(4)
    }

    private var localImage: UIImage? {
        guard let local else { return nil }
        let key = local.path as NSString
        if let cached = Self.cache.object(forKey: key) { return cached }
        guard let image = UIImage(contentsOfFile: local.path) else { return nil }
        Self.cache.setObject(image, forKey: key)
        return image
    }
}
