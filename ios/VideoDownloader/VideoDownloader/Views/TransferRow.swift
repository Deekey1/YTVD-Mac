import SwiftUI

/// Карточка загрузки: этап, прогресс, байты, скорость, время.
struct TransferRow: View {
    let transfer: Transfer
    @Environment(TransferService.self) private var transfers

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ThumbnailView(local: transfer.thumbnailURL, remote: transfer.video.thumbnail)
                .frame(width: 96, height: 54)
            VStack(alignment: .leading, spacing: 6) {
                Text(transfer.video.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                HStack(spacing: 6) {
                    if transfer.isActive, transfer.fraction == nil {
                        ProgressView().controlSize(.mini)
                    }
                    Text("\(transfer.format.label) · \(transfer.stageTitle)")
                        .font(.caption)
                        .foregroundStyle(transfer.phase == .failed ? .red : .secondary)
                }
                if let fraction = transfer.fraction {
                    ProgressView(value: fraction)
                }
                if let line = transfer.detailLine {
                    Text(line).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                if transfer.phase == .failed {
                    if let error = transfer.error {
                        Text(error).font(.caption).foregroundStyle(.red)
                    }
                    HStack {
                        Button("Повторить") { Task { await transfers.retry(transfer.id) } }
                        Button("Убрать", role: .destructive) { transfers.remove(transfer.id) }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding(.vertical, 2)
        .swipeActions {
            if transfer.isActive {
                Button("Отменить", role: .destructive) { Task { await transfers.cancel(transfer.id) } }
            } else {
                Button("Убрать", role: .destructive) { transfers.remove(transfer.id) }
            }
        }
    }
}

/// Обложка: своя копия с диска, иначе из сети, иначе заглушка.
struct ThumbnailView: View {
    var local: URL?
    var remote: String?

    private static let cache = NSCache<NSString, UIImage>()

    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            if let image = localImage {
                Image(uiImage: image).resizable().scaledToFill()
            } else if let remote, let url = URL(string: remote) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityHidden(true)
    }

    private var placeholder: some View {
        Image(systemName: "film").foregroundStyle(.secondary)
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
