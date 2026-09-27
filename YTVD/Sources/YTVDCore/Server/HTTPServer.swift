import Foundation
import Network
import os

/// На каком адресе слушать.
public enum BindAddress: Sendable, Equatable {
    /// Вся локальная сеть — так до Mac достанет iPhone.
    case all
    /// Только этот Mac — для проверки через curl.
    case loopback
    case address(String)

    public init(_ text: String) {
        switch text.trimmingCharacters(in: .whitespaces) {
        case "", "0.0.0.0", "*", "all": self = .all
        case "127.0.0.1", "localhost", "::1", "loopback": self = .loopback
        default: self = .address(text)
        }
    }
}

/// Маленький HTTP/1.1-сервер на Network.framework.
///
/// Зависимостей нет, Bonjour-объявление встроено. Каждое соединение обслуживает один
/// запрос и закрывается — так проще и надёжнее, а URLSession к этому готов.
public final class HTTPServer: @unchecked Sendable {

    public enum State: Sendable, Equatable {
        case stopped
        case starting
        case listening(port: UInt16)
        case failed(String)
    }

    public typealias Handler = @Sendable (HTTPRequest) async -> HTTPResponse

    private let port: UInt16
    private let bind: BindAddress
    private let bonjourName: String?
    private let bonjourTXT: [String: String]
    private let handler: Handler
    private let queue = DispatchQueue(label: "studio.dk.ytvd.http")
    private let log = Logger(subsystem: "studio.dk.ytvd", category: "http")

    private var listener: NWListener?
    private var connections: Set<ObjectIdentifier> = []
    private let stateLock = NSLock()
    private var currentState: State = .stopped

    public var onStateChange: (@Sendable (State) -> Void)?

    public var state: State {
        stateLock.lock(); defer { stateLock.unlock() }
        return currentState
    }

    public init(port: UInt16, bind: BindAddress = .all, bonjourName: String? = nil,
                bonjourTXT: [String: String] = [:], handler: @escaping Handler) {
        self.port = port
        self.bind = bind
        self.bonjourName = bonjourName
        self.bonjourTXT = bonjourTXT
        self.handler = handler
    }

    // MARK: - запуск и остановка

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let listener: NWListener
        switch bind {
        case .all:
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
        case .loopback:
            parameters.requiredInterfaceType = .loopback
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port) ?? .any)
        case .address(let host):
            parameters.requiredLocalEndpoint = .hostPort(host: NWEndpoint.Host(host),
                                                         port: NWEndpoint.Port(rawValue: port) ?? .any)
            listener = try NWListener(using: parameters)
        }

        // Объявляем себя в сети, чтобы iPhone нашёл Mac без ввода адреса.
        if let bonjourName, bind != .loopback {
            listener.service = NWListener.Service(name: bonjourName, type: API.bonjourType,
                                                  txtRecord: Self.txt(bonjourTXT))
        }

        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                let actual = listener.port?.rawValue ?? self.port
                self.log.info("слушаю порт \(actual, privacy: .public)")
                self.setState(.listening(port: actual))
            case .failed(let error):
                self.log.error("сервер упал: \(error.localizedDescription, privacy: .public)")
                self.setState(.failed(Self.describe(error)))
                listener.cancel()
            case .cancelled:
                self.setState(.stopped)
            default:
                break
            }
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }

        self.listener = listener
        setState(.starting)
        listener.start(queue: queue)
    }

    public func stop() {
        listener?.cancel()
        listener = nil
        setState(.stopped)
    }

    private func setState(_ state: State) {
        stateLock.lock(); currentState = state; stateLock.unlock()
        onStateChange?(state)
    }

    // MARK: - соединение

    private func accept(_ connection: NWConnection) {
        let id = ObjectIdentifier(connection)
        connections.insert(id)
        let remote: String? = {
            if case .hostPort(let host, _) = connection.endpoint { return "\(host)" }
            return nil
        }()

        // Кто подключился и молчит — закрываем, чтобы не держать сокеты.
        let idle = DispatchWorkItem { [weak connection] in connection?.cancel() }
        queue.asyncAfter(deadline: .now() + 30, execute: idle)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled:
                idle.cancel()
                self?.connections.remove(id)
            default:
                break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data(), remote: remote, idle: idle)
    }

    private func receive(on connection: NWConnection, buffer: Data, remote: String?, idle: DispatchWorkItem) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            switch HTTPParser.check(buffer) {
            case .needMore:
                if complete || error != nil { connection.cancel(); return }
                self.receive(on: connection, buffer: buffer, remote: remote, idle: idle)
            case .invalid(let status):
                idle.cancel()
                self.send(.error(status, .badRequest), to: connection, method: "GET")
            case .complete:
                idle.cancel()
                guard var request = HTTPParser.parse(buffer) else {
                    self.send(.error(400, .badRequest), to: connection, method: "GET")
                    return
                }
                request.remoteAddress = remote
                let handler = self.handler
                Task {
                    let response = await handler(request)
                    self.queue.async { self.send(response, to: connection, method: request.method) }
                }
            }
        }
    }

    // MARK: - ответ

    private func send(_ response: HTTPResponse, to connection: NWConnection, method: String) {
        let withBody = method != "HEAD"
        let head = response.head()

        switch response.body {
        case .data(let data) where withBody:
            connection.send(content: head + data, completion: .contentProcessed { _ in connection.cancel() })
        case .file(let url, let offset, let length) where withBody:
            connection.send(content: head, completion: .contentProcessed { [weak self] error in
                guard error == nil, let self else { connection.cancel(); return }
                guard let handle = try? FileHandle(forReadingFrom: url) else { connection.cancel(); return }
                do {
                    try handle.seek(toOffset: UInt64(offset))
                } catch {
                    try? handle.close(); connection.cancel(); return
                }
                self.stream(handle, remaining: length, to: connection)
            })
        default:
            connection.send(content: head, completion: .contentProcessed { _ in connection.cancel() })
        }
    }

    /// Отдаёт файл кусками: следующий читаем только когда предыдущий ушёл в сеть,
    /// поэтому память не растёт, как бы велик ни был файл.
    private func stream(_ handle: FileHandle, remaining: Int64, to connection: NWConnection) {
        guard remaining > 0 else {
            try? handle.close()
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true,
                            completion: .contentProcessed { _ in connection.cancel() })
            return
        }
        let chunkSize = Int(min(remaining, 256 * 1024))
        let chunk = (try? handle.read(upToCount: chunkSize)) ?? Data()
        guard !chunk.isEmpty else {
            try? handle.close(); connection.cancel(); return
        }
        connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
            // iPhone прервал загрузку (пауза, обрыв) — прекращаем читать файл.
            guard error == nil, let self else { try? handle.close(); connection.cancel(); return }
            self.queue.async { self.stream(handle, remaining: remaining - Int64(chunk.count), to: connection) }
        })
    }

    // MARK: - вспомогательное

    private static func txt(_ values: [String: String]) -> NWTXTRecord {
        var record = NWTXTRecord()
        for (key, value) in values { record[key] = value }
        return record
    }

    static func describe(_ error: NWError) -> String {
        if case .posix(let code) = error, code == .EADDRINUSE {
            return "Порт занят другой программой"
        }
        if case .posix(let code) = error, code == .EACCES {
            return "Нет прав слушать этот порт"
        }
        return error.localizedDescription
    }
}
