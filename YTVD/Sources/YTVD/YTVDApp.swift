import AppKit
import Carbon.HIToolbox
import SwiftUI
import YTVDCore

@main
enum YTVDApp {
    static func main() {
        let app = NSApplication.shared

        // Служебный режим: рисует окно во всех состояниях в PNG и выходит.
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "--render") {
            let directory = index + 1 < arguments.count
                ? URL(fileURLWithPath: arguments[index + 1])
                : URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            MainActor.assumeIsolated {
                let files = SnapshotRenderer.renderAll(to: directory)
                print(files.map(\.lastPathComponent).joined(separator: "\n"))
            }
            exit(0)
        }

        // Самодиагностика: что приложение видит на этой машине.
        if arguments.contains("--doctor") {
            let semaphore = DispatchSemaphore(value: 0)
            // Именно detached: обычный Task унаследовал бы главный актор и заблокировался бы
            // на семафоре вместе с главным потоком.
            Task.detached {
                let chain = await Toolchain.discover()
                print("yt-dlp: \(chain.ytdlp?.path ?? "не найден")  версия: \(chain.ytdlpVersion ?? "—")")
                print("ffmpeg: \(chain.ffmpeg?.path ?? "не найден")  версия: \(chain.ffmpegVersion ?? "—")")
                print("готово к работе: \(chain.isReady ? "да" : "нет")  склейка дорожек: \(chain.canMerge ? "да" : "нет")")
                semaphore.signal()
            }
            semaphore.wait()
            exit(0)
        }

        // Сквозная проверка конвейера без интерфейса:
        //   --analyze <ссылка>            разобрать и показать варианты
        //   --fetch <ссылка> [каталог]    скачать самый лёгкий вариант целиком
        if let index = arguments.firstIndex(where: { $0 == "--analyze" || $0 == "--fetch" }),
           index + 1 < arguments.count,
           let url = LinkDetector.normalize(arguments[index + 1]) {
            let download = arguments[index] == "--fetch"
            let directory = index + 2 < arguments.count
                ? URL(fileURLWithPath: arguments[index + 2])
                : FileManager.default.temporaryDirectory.appendingPathComponent("ytvd-check")
            let semaphore = DispatchSemaphore(value: 0)
            var code: Int32 = 0
            Task.detached {
                code = await CommandLineCheck.run(url: url, download: download, directory: directory)
                semaphore.signal()
            }
            semaphore.wait()
            exit(code)
        }

        let delegate = AppDelegate()
        app.delegate = delegate
        // Виджет живёт в меню-баре, а не в Dock.
        app.setActivationPolicy(.accessory)
        app.run()
    }
}

/// Безрамочное окно должно уметь становиться главным — иначе не работает поле ввода.
final class WidgetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var window: WidgetWindow!
    private var statusItem: NSStatusItem!
    private var model: AppModel!
    private var hotKey: GlobalHotKey?
    private var keyMonitor: Any?
    private var floatObserver: NSObjectProtocol?

    /// Верхний левый угол, за который «держится» окно: содержимое меняет высоту,
    /// а шапка должна оставаться на месте.
    private var pinnedTopLeft: NSPoint = .zero
    private var adjustingFrame = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        buildMainMenu()
        buildWindow()
        buildStatusItem()
        installKeyMonitor()
        installHotKey()

        Task { @MainActor in
            await model.bootstrap()
        }

        showWindow()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        hotKey = nil
    }

    // MARK: - окно

    private func buildWindow() {
        let controller = NSHostingController(rootView: RootView(model: model))
        controller.sizingOptions = [.preferredContentSize]

        window = WidgetWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
                              styleMask: [.borderless, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.contentViewController = controller
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        // Окно должно таскаться за любую точку: своя полоса перетаскивания лежит под
        // содержимым шапки, и SwiftUI забирает нажатия себе — до неё они не доходят.
        window.isMovableByWindowBackground = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.setFrameAutosaveName("YTVDWidget")
        // Восстанавливаем сохранённое положение явно: если положиться на AppKit,
        // он сделает это позже и перебьёт подгонку под экран.
        let restored = window.setFrameUsingName("YTVDWidget")
        applyFloatingLevel()

        if !restored || window.frame.origin == .zero, let screen = NSScreen.main {
            let visible = screen.visibleFrame
            window.setFrameTopLeftPoint(NSPoint(x: visible.maxX - 440, y: visible.maxY - 40))
        }
        // Рамка от прошлой сессии могла уехать за край экрана.
        window.setFrame(clampToScreen(window.frame), display: false)
        pinnedTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.keepTopLeftAnchored() }
        }
        NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.rememberTopLeft() }
        }

        // Уровень окна следует за настройкой «поверх всех окон».
        floatObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.applyFloatingLevel() }
        }
    }

    /// Пользователь подвинул окно — запоминаем новую точку привязки.
    private func rememberTopLeft() {
        guard !adjustingFrame else { return }
        pinnedTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
    }

    /// Содержимое изменило высоту — возвращаем шапку на прежнее место
    /// и следим, чтобы окно осталось на экране.
    private func keepTopLeftAnchored() {
        guard !adjustingFrame else { return }
        var frame = window.frame
        frame.origin.x = pinnedTopLeft.x
        frame.origin.y = pinnedTopLeft.y - frame.height

        let target = clampToScreen(frame)
        guard target != window.frame else { return }

        adjustingFrame = true
        window.setFrame(target, display: true)
        adjustingFrame = false
        // Если подгонка сдвинула окно, дальше держимся уже за новую точку.
        pinnedTopLeft = NSPoint(x: target.minX, y: target.maxY)
        window.invalidateShadow()
    }

    /// Не даём окну уйти за пределы видимой области экрана.
    private func clampToScreen(_ frame: NSRect) -> NSRect {
        guard let screen = window.screen ?? NSScreen.main else { return frame }
        let visible = screen.visibleFrame
        var result = frame

        let maxX = max(visible.minX, visible.maxX - result.width - 8)
        result.origin.x = min(max(result.origin.x, visible.minX + 8), maxX)

        // Шапка важнее подвала: сначала не пускаем верх под строку меню,
        // потом — по возможности — поднимаем низ над кромкой экрана.
        if result.maxY > visible.maxY { result.origin.y = visible.maxY - result.height }
        if result.minY < visible.minY + 8 {
            result.origin.y = min(visible.minY + 8, visible.maxY - result.height)
        }
        return result
    }

    private func applyFloatingLevel() {
        window.level = model.settings.floatOnTop ? .floating : .normal
    }

    private func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        // Показ мог применить сохранённую рамку — проверяем её ещё раз.
        let target = clampToScreen(window.frame)
        if target != window.frame {
            adjustingFrame = true
            window.setFrame(target, display: true)
            adjustingFrame = false
        }
        pinnedTopLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.invalidateShadow()
    }

    private func toggleWindow() {
        if window.isVisible && NSApp.isActive {
            NSApp.hide(nil)
        } else {
            showWindow()
        }
    }

    // MARK: - главное меню

    /// Приложение без иконки в Dock своего меню не показывает, но главное меню всё равно
    /// нужно: без пунктов «Правка» AppKit не доставляет ⌘V, ⌘C, ⌘X и ⌘A в текстовое поле.
    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Настройки…", action: #selector(menuSettings), keyEquivalent: ",")
            .target = self
        appMenu.addItem(withTitle: "История", action: #selector(menuHistory), keyEquivalent: "y")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Скрыть YTVD", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Выйти из YTVD", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Правка")
        editMenu.addItem(withTitle: "Отменить", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Повторить", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Вырезать", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Копировать", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Вставить", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Выбрать всё", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - меню-бар

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = Icon.download.templateImage(size: 17, lineWidth: 2)
        statusItem.button?.toolTip = "YTVD — скачать видео (⌥⌘D)"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusItemClicked() {
        guard let event = NSApp.currentEvent else { toggleWindow(); return }
        if event.type == .rightMouseUp {
            showMenu()
        } else {
            toggleWindow()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Показать окно", action: #selector(menuShow), keyEquivalent: "")
            .target = self
        menu.addItem(withTitle: "Настройки…", action: #selector(menuSettings), keyEquivalent: ",")
            .target = self
        menu.addItem(withTitle: "История", action: #selector(menuHistory), keyEquivalent: "y")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Папка загрузок", action: #selector(menuFolder), keyEquivalent: "")
            .target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Выйти", action: #selector(menuQuit), keyEquivalent: "q").target = self

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil                       // возвращаем обычное нажатие
    }

    @objc private func menuShow() { showWindow() }
    @objc private func menuSettings() { showWindow(); model.panel = .settings }
    @objc private func menuHistory() { showWindow(); model.panel = .history }
    @objc private func menuFolder() { model.openDownloadDirectory() }
    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - клавиатура

    private func installKeyMonitor() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            return MainActor.assumeIsolated { self.handle(event) } ? nil : event
        }
    }

    /// Возвращает true, если событие обработано и дальше его пускать не надо.
    private func handle(_ event: NSEvent) -> Bool {
        let editing = window.firstResponder is NSTextView
        let command = event.modifierFlags.contains(.command)

        if command, let characters = event.charactersIgnoringModifiers?.lowercased() {
            switch characters {
            case ",":
                model.panel = model.panel == .settings ? nil : .settings
                return true
            case "y":
                model.panel = model.panel == .history ? nil : .history
                return true
            case "v":
                if editing {
                    // Вставляем сами: так поведение не зависит от того, дошло ли
                    // сочетание до пункта меню «Правка → Вставить».
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else if let text = NSPasteboard.general.string(forType: .string) {
                    if let url = LinkDetector.firstSupportedURL(in: text) {
                        model.analyze(url, autoStart: model.settings.autoDownload)
                    } else if let other = LinkDetector.normalize(
                        text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                        // Ссылка с другой площадки — пробуем всё равно, yt-dlp знает многие.
                        model.analyze(other, autoStart: model.settings.autoDownload)
                    }
                    // Если в буфере не ссылка, молчим: сбрасывать разобранный ролик не за что.
                }
                return true
            case "w":
                NSApp.hide(nil)
                return true
            default:
                return false
            }
        }

        switch Int(event.keyCode) {
        case kVK_Escape:
            if model.panel != nil { model.panel = nil } else { NSApp.hide(nil) }
            return true
        case kVK_UpArrow where !editing && model.stage == .ready:
            model.moveSelection(by: -1)
            return true
        case kVK_DownArrow where !editing && model.stage == .ready:
            model.moveSelection(by: 1)
            return true
        case kVK_Return where !editing:
            if model.stage == .ready { model.download(); return true }
            return false
        default:
            return false
        }
    }

    // MARK: - глобальное сочетание ⌥⌘D

    private func installHotKey() {
        hotKey = GlobalHotKey(keyCode: UInt32(kVK_ANSI_D),
                              modifiers: UInt32(cmdKey | optionKey)) { [weak self] in
            Task { @MainActor in self?.toggleWindow() }
        }
    }
}

/// Обёртка над Carbon-хоткеем: работает без прав универсального доступа.
final class GlobalHotKey {
    private var reference: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let callback: () -> Void
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1

    init?(keyCode: UInt32, modifiers: UInt32, callback: @escaping () -> Void) {
        self.callback = callback

        let id = Self.nextID
        Self.nextID += 1
        Self.registry[id] = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            GlobalHotKey.registry[hotKeyID.id]?.callback()
            return noErr
        }, 1, &eventType, nil, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x59545644), id: id)   // 'YTVD'
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &reference)
        if status != noErr {
            Self.registry[id] = nil
            return nil
        }
    }

    deinit {
        if let reference { UnregisterEventHotKey(reference) }
        if let handler { RemoveEventHandler(handler) }
    }
}
