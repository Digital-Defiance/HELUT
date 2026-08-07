import Foundation
import Network

// MARK: - TCP transport for Enigma256FrameTransport (Network.framework / Apple Silicon)
//
// HELUT host-only: two `helut` processes on localhost (or LAN) speak E2W1 frames.
// SoftBus decrypt stays on the receiver after ECDH.

package enum Enigma256TCPError: Error, Equatable {
    case badPort
    case listenFailed(String)
    case connectFailed(String)
    case notReady
    case sendFailed
    case timedOut
}

package final class Enigma256TCPTransport: Enigma256FrameTransport, @unchecked Sendable {
    private let connection: NWConnection
    private let condition = NSCondition()
    private var inbox = Data()
    private var ready = false
    private var closed = false
    private var startError: String?

    private init(connection: NWConnection) {
        self.connection = connection
    }

    /// Outbound client.
    package static func connect(
        host: String,
        port: UInt16,
        timeout: TimeInterval = 15
    ) throws -> Enigma256TCPTransport {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw Enigma256TCPError.badPort }
        let conn = NWConnection(host: NWEndpoint.Host(host), port: nwPort, using: .tcp)
        let transport = Enigma256TCPTransport(connection: conn)
        try transport.start(timeout: timeout)
        return transport
    }

    /// Inbound: listen until one TCP client connects, then return that session.
    package static func accept(
        port: UInt16,
        timeout: TimeInterval = 60
    ) throws -> Enigma256TCPTransport {
        guard let nwPort = NWEndpoint.Port(rawValue: port) else { throw Enigma256TCPError.badPort }
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: nwPort)
        } catch {
            throw Enigma256TCPError.listenFailed(String(describing: error))
        }

        final class AcceptBox: @unchecked Sendable {
            let gate = NSCondition()
            var connection: NWConnection?
            var error: String?
        }
        let box = AcceptBox()

        listener.stateUpdateHandler = { state in
            if case let .failed(err) = state {
                box.gate.lock()
                box.error = err.localizedDescription
                box.gate.signal()
                box.gate.unlock()
            }
        }
        listener.newConnectionHandler = { conn in
            box.gate.lock()
            if box.connection == nil {
                box.connection = conn
                listener.newConnectionHandler = nil
                listener.cancel()
                box.gate.signal()
            } else {
                conn.cancel()
            }
            box.gate.unlock()
        }
        listener.start(queue: .global(qos: .userInitiated))

        box.gate.lock()
        let deadline = Date().addingTimeInterval(timeout)
        while box.connection == nil && box.error == nil {
            if !box.gate.wait(until: deadline) { break }
        }
        let conn = box.connection
        let err = box.error
        box.gate.unlock()

        if let err {
            listener.cancel()
            throw Enigma256TCPError.listenFailed(err)
        }
        guard let conn else {
            listener.cancel()
            throw Enigma256TCPError.timedOut
        }

        let transport = Enigma256TCPTransport(connection: conn)
        try transport.start(timeout: timeout)
        return transport
    }

    private func start(timeout: TimeInterval) throws {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.condition.lock()
            switch state {
            case .ready:
                self.ready = true
                self.condition.signal()
            case .failed(let err):
                self.startError = err.localizedDescription
                self.closed = true
                self.condition.signal()
            case .cancelled:
                self.closed = true
                self.condition.signal()
            default:
                break
            }
            self.condition.unlock()
        }
        connection.start(queue: .global(qos: .userInitiated))
        pumpReceive()

        condition.lock()
        let deadline = Date().addingTimeInterval(timeout)
        while !ready && !closed && startError == nil {
            if !condition.wait(until: deadline) { break }
        }
        let ok = ready
        let err = startError
        condition.unlock()

        if let err { throw Enigma256TCPError.connectFailed(err) }
        guard ok else { throw Enigma256TCPError.timedOut }
    }

    private func pumpReceive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            self.condition.lock()
            if let data, !data.isEmpty {
                self.inbox.append(data)
                self.condition.signal()
            }
            if isComplete || error != nil {
                self.closed = true
                self.condition.signal()
            }
            self.condition.unlock()
            if error == nil && isComplete == false {
                self.pumpReceive()
            }
        }
    }

    package func send(_ frame: Enigma256Frame) throws {
        condition.lock()
        let isReady = ready && !closed
        condition.unlock()
        guard isReady else { throw Enigma256TCPError.notReady }

        let payload = frame.encode()
        final class SendBox: @unchecked Sendable {
            var ok = false
            let gate = DispatchSemaphore(value: 0)
        }
        let box = SendBox()
        connection.send(
            content: payload,
            contentContext: .defaultMessage,
            isComplete: false,
            completion: .contentProcessed { error in
                box.ok = (error == nil)
                box.gate.signal()
            }
        )
        if box.gate.wait(timeout: .now() + 15) == .timedOut || !box.ok {
            throw Enigma256TCPError.sendFailed
        }
    }

    package func receive() throws -> Enigma256Frame {
        condition.lock()
        defer { condition.unlock() }
        let deadline = Date().addingTimeInterval(60)
        while true {
            do {
                if let frame = try Enigma256Frame.parse(from: &inbox) {
                    return frame
                }
            } catch {
                throw error
            }
            if closed {
                throw Enigma256WireError.closed
            }
            if !condition.wait(until: deadline) {
                throw Enigma256WireError.truncated
            }
        }
    }

    package func close() {
        condition.lock()
        closed = true
        condition.unlock()
        connection.cancel()
    }
}
