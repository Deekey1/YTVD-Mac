import UIKit
import UniformTypeIdentifiers
import YTVDAPI

/// «Поделиться → VideoDownloader»: достаёт ссылку, передаёт её приложению и закрывается.
///
/// Ничего не скачивает и не ходит в сеть: расширению дают мало памяти и времени,
/// вся работа — в самом приложении.
final class ShareViewController: UIViewController {

    private let card = UIVisualEffectView(effect: UIBlurEffect(style: .systemMaterial))
    private let icon = UIImageView()
    private let label = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        buildInterface()
        show("Передаю ссылку…", symbol: "arrow.down.circle")
        Task { await handle() }
    }

    private func handle() async {
        guard let url = await extractURL() else {
            show("В том, чем поделились, нет ссылки", symbol: "exclamationmark.triangle")
            finish(after: 1.6)
            return
        }
        let saved = SharedInbox.push(url)
        if openApp(with: url) {
            show("Открываю VideoDownloader…", symbol: "arrow.up.forward.app")
            finish(after: 0.5)
        } else if saved {
            show("Ссылка передана — откройте VideoDownloader", symbol: "checkmark.circle")
            finish(after: 1.6)
        } else {
            show("Не удалось передать ссылку: проверьте App Group в подписи", symbol: "exclamationmark.triangle")
            finish(after: 2.2)
        }
    }

    // MARK: - ссылка

    private func extractURL() async -> URL? {
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let providers = items.flatMap { $0.attachments ?? [] }

        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await load(provider, type: .url), let link = Self.link(from: url) { return link }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = await load(provider, type: .plainText), let link = Self.link(from: text) { return link }
        }
        // Часть приложений кладёт текст прямо в сам элемент, а не во вложение.
        for item in items {
            if let text = item.attributedContentText?.string, let link = Self.link(from: text) { return link }
        }
        return nil
    }

    /// Вложение как строка: ссылка или текст — неважно, дальше разберём одинаково.
    private func load(_ provider: NSItemProvider, type: UTType) async -> String? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type.identifier, options: nil) { item, _ in
                switch item {
                case let url as URL: continuation.resume(returning: url.absoluteString)
                case let text as String: continuation.resume(returning: text)
                case let data as Data: continuation.resume(returning: String(data: data, encoding: .utf8))
                default: continuation.resume(returning: nil)
                }
            }
        }
    }

    /// Поддерживаемую площадку берём в первую очередь, иначе — любую веб-ссылку.
    static func link(from text: String) -> URL? {
        LinkDetector.firstSupportedURL(in: text) ?? SharedInbox.firstWebURL(in: text)
    }

    // MARK: - открыть приложение

    /// Расширениям «Поделиться» не положено открывать приложения напрямую, но UIApplication
    /// хоста доступен по цепочке ответчиков. Не вышло — ссылка всё равно ждёт в общем ящике.
    private func openApp(with url: URL) -> Bool {
        guard let deepLink = SharedInbox.deepLink(for: url) else { return false }
        let selector = sel_registerName("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                typealias Open = @convention(c) (AnyObject, Selector, NSURL, NSDictionary,
                                                 (@convention(block) (Bool) -> Void)?) -> Void
                let open = unsafeBitCast(current.method(for: selector), to: Open.self)
                open(current, selector, deepLink as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }

    // MARK: - интерфейс

    private func buildInterface() {
        view.backgroundColor = .clear
        card.translatesAutoresizingMaskIntoConstraints = false
        card.layer.cornerRadius = 16
        card.clipsToBounds = true
        view.addSubview(card)

        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.tintColor = .tintColor
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(textStyle: .title1)

        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .preferredFont(forTextStyle: .headline)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.spacing = 10
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            card.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            card.widthAnchor.constraint(equalToConstant: 280),
            stack.topAnchor.constraint(equalTo: card.contentView.topAnchor, constant: 22),
            stack.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor, constant: -22),
            stack.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor, constant: 18),
            stack.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor, constant: -18),
        ])
    }

    private func show(_ text: String, symbol: String) {
        label.text = text
        icon.image = UIImage(systemName: symbol)
    }

    private func finish(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }
}
