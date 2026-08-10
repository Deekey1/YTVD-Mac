import Foundation

/// Ошибки, которые показываем пользователю.
public enum YTVDError: LocalizedError, Equatable {
    case toolMissing(String)
    case tool(String)
    /// То же сообщение, но сбой похож на устаревший движок — стоит предложить обновление.
    case engineStale(String)
    case cancelled
    case network(String)

    public var errorDescription: String? {
        switch self {
        case .toolMissing(let name): "Не найден \(name)"
        case .tool(let message): message
        case .engineStale(let message): message
        case .cancelled: "Отменено"
        case .network(let message): message
        }
    }
}

/// Запущенный процесс — можно прервать.
public final class RunningProcess: @unchecked Sendable {
    private let process: Process
    init(_ process: Process) { self.process = process }

    public var isRunning: Bool { process.isRunning }

    public func terminate() {
        guard process.isRunning else { return }
        process.terminate()
    }
}

public enum ProcessRunner {

    public struct Output: Sendable {
        public let status: Int32
        public let stdout: String
        public let stderr: String
        public var succeeded: Bool { status == 0 }
    }

    /// Запуск с ожиданием результата целиком.
    public static func run(_ tool: URL, _ args: [String],
                           environment: [String: String]? = nil) async throws -> Output {
        var out = ""
        var err = ""
        let status = try await stream(tool, args, environment: environment,
                                      onStdout: { out += $0 + "\n" },
                                      onStderr: { err += $0 + "\n" })
        return Output(status: status, stdout: out, stderr: err)
    }

    /// Запуск с построчной выдачей. `started` отдаёт ручку для отмены.
    @discardableResult
    public static func stream(_ tool: URL, _ args: [String],
                              environment: [String: String]? = nil,
                              started: ((RunningProcess) -> Void)? = nil,
                              onStdout: @escaping (String) -> Void,
                              onStderr: @escaping (String) -> Void = { _ in }) async throws -> Int32 {

        let process = Process()
        process.executableURL = tool
        process.arguments = args
        if let environment { process.environment = environment }

        let outPipe = Pipe(), errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        // Дожидаемся и конца обоих потоков, и завершения процесса — иначе теряются хвосты вывода.
        let state = StreamState()

        func attach(_ pipe: Pipe, isStdout: Bool) {
            let buffer = LineBuffer()
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    for line in buffer.flush() { isStdout ? onStdout(line) : onStderr(line) }
                    handle.readabilityHandler = nil
                    state.finish(isStdout ? .stdout : .stderr)
                    return
                }
                for line in buffer.append(data) { isStdout ? onStdout(line) : onStderr(line) }
            }
        }
        attach(outPipe, isStdout: true)
        attach(errPipe, isStdout: false)

        return try await withCheckedThrowingContinuation { continuation in
            state.onComplete = { status in continuation.resume(returning: status) }

            process.terminationHandler = { finished in
                state.finish(.process(finished.terminationStatus))
            }

            do {
                try process.run()
                started?(RunningProcess(process))
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(throwing: YTVDError.tool(
                    "Не удалось запустить \(tool.lastPathComponent): \(error.localizedDescription)"))
            }
        }
    }
}

/// Собирает поток байтов в строки.
private final class LineBuffer {
    private var pending = Data()

    func append(_ data: Data) -> [String] {
        pending.append(data)
        var lines: [String] = []
        // yt-dlp с --newline печатает \n, но на всякий случай режем и по \r.
        while let index = pending.firstIndex(where: { $0 == 0x0A || $0 == 0x0D }) {
            let chunk = pending[pending.startIndex..<index]
            pending.removeSubrange(pending.startIndex...index)
            if let text = String(data: chunk, encoding: .utf8), !text.isEmpty { lines.append(text) }
        }
        return lines
    }

    func flush() -> [String] {
        defer { pending.removeAll() }
        guard !pending.isEmpty, let text = String(data: pending, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return [text]
    }
}

/// Синхронизация «оба потока закрылись и процесс завершился».
private final class StreamState: @unchecked Sendable {
    enum Event { case stdout, stderr, process(Int32) }

    private let lock = NSLock()
    private var stdoutDone = false
    private var stderrDone = false
    private var exitStatus: Int32?
    private var completed = false

    var onComplete: ((Int32) -> Void)?

    func finish(_ event: Event) {
        var fire: Int32?
        lock.lock()
        switch event {
        case .stdout: stdoutDone = true
        case .stderr: stderrDone = true
        case .process(let status): exitStatus = status
        }
        if let status = exitStatus, stdoutDone, stderrDone, !completed {
            completed = true
            fire = status
        }
        lock.unlock()
        if let fire { onComplete?(fire) }
    }
}
