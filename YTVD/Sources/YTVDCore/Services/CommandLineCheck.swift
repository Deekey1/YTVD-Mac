import Foundation

/// Печатать прогресс с шагом, а не на каждую строку от yt-dlp.
private final class Throttle: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -100

    func shouldReport(_ percent: Int, step: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard percent >= last + step else { return false }
        last = percent
        return true
    }
}

/// Проверка всего конвейера из терминала — тем же кодом, что работает под интерфейсом.
/// `--analyze` показывает разобранные варианты, `--fetch` ещё и скачивает самый лёгкий.
public enum CommandLineCheck {

    public static func run(url: URL, download: Bool, directory: URL) async -> Int32 {
        let chain = await Toolchain.discover()
        guard chain.isReady else {
            print("✗ yt-dlp не найден — установите: brew install yt-dlp")
            return 1
        }
        print("движок: \(chain.summary)")
        print("площадка: \(MediaSource.detect(url).title)")

        // Берём те же сетевые настройки, что и приложение.
        let network = AppSettings.storedNetwork()
        if !network.arguments.isEmpty {
            print("сеть: \(network.arguments.joined(separator: " "))")
        }

        let service = MediaService(toolchain: chain, network: network)
        let info: MediaInfo
        let resolvedURL: URL
        do {
            let resolved = try await service.fetchInfo(url: url)
            info = resolved.info
            resolvedURL = resolved.url
            if resolved.url != url { print("сработала запасная ссылка: \(resolved.url.absoluteString)") }
        } catch {
            print("✗ разбор не удался: \((error as? YTVDError)?.errorDescription ?? error.localizedDescription)")
            return 1
        }

        print("название: \(info.displayTitle)")
        print("автор: \(info.displayAuthor ?? "—")  длительность: \(Fmt.duration(Int(info.duration ?? 0)))")

        let options = OptionBuilder.build(from: info)
        guard !options.isEmpty else {
            print("✗ нет доступных форматов")
            return 1
        }

        print("\nварианты (\(options.count)):")
        for option in options {
            let badge = option.badge.map { " [\($0)]" } ?? ""
            let group = option.group.title.padding(toLength: 8, withPad: " ", startingAt: 0)
            let title = "\(option.title) \(option.subtitle)"
                .padding(toLength: 18, withPad: " ", startingAt: 0)
            let size = option.sizeText.padding(toLength: 10, withPad: " ", startingAt: 0)
            print("  \(group) \(title) \(size) \(option.plan.selector)\(badge)")
        }

        guard download else { return 0 }

        // Для проверки берём самый лёгкий видеовариант — так быстрее и всё равно проходит склейку.
        guard let target = options.filter({ $0.group == .video }).min(by: { $0.bytes < $1.bytes })
                ?? options.first(where: { $0.group == .audio }) else {
            print("✗ нечего скачивать")
            return 1
        }

        print("\nскачиваю: \(target.title) \(target.subtitle) (\(target.sizeText)) → \(directory.path)")
        let base = Fmt.safeFileName(info.displayTitle) + " [\(target.title)]"
        let throttle = Throttle()

        do {
            let result = try await service.download(
                plan: target.plan, url: resolvedURL, directory: directory, baseName: base,
                onEvent: { event in
                    switch event {
                    case .phase(let phase):
                        print("  этап: \(phase)")
                    case .progress(let progress):
                        guard let fraction = progress.fraction else { return }
                        let percent = Int(fraction * 100)
                        if throttle.shouldReport(percent, step: 25) {
                            let speed = progress.speed.map { Fmt.speed($0) } ?? "—"
                            print("  \(percent) % · \(speed)")
                        }
                    }
                })

            print("✓ файл: \(result.file.path)")
            print("✓ размер: \(Fmt.bytes(result.bytes))")

            // Проверяем, что файл действительно на месте и не пустой.
            let attributes = try FileManager.default.attributesOfItem(atPath: result.file.path)
            let size = (attributes[.size] as? Int64) ?? 0
            guard size > 1024 else {
                print("✗ файл подозрительно мал")
                return 1
            }

            if let coverURL = options.first(where: { $0.group == .cover })?.plan.coverURL,
               let source = URL(string: coverURL) {
                let jpeg = directory.appendingPathComponent(base + ".jpg")
                _ = try await ThumbnailService.saveJPEG(from: source, to: jpeg)
                let coverSize = (try? FileManager.default.attributesOfItem(atPath: jpeg.path)[.size] as? Int64) ?? 0
                print("✓ обложка: \(jpeg.lastPathComponent) (\(Fmt.bytes(coverSize ?? 0)))")
            }
            return 0
        } catch {
            print("✗ скачивание не удалось: \((error as? YTVDError)?.errorDescription ?? error.localizedDescription)")
            return 1
        }
    }
}
