import Darwin
import Foundation

public enum IPCError: Error {
    case socket
    case pathTooLong
    case send
}

private func socketAddress(path: String) throws -> (sockaddr_un, socklen_t) {
    guard path.utf8.count < MemoryLayout.size(ofValue: sockaddr_un().sun_path) else {
        throw IPCError.pathTooLong
    }

    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    let pathCapacity = 104
    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: pathCapacity) {
            _ = strlcpy($0, path, pathCapacity)
        }
    }
    return (address, socklen_t(MemoryLayout<sockaddr_un>.size))
}

public final class IPCServer {
    private var descriptor: Int32 = -1
    private var source: DispatchSourceRead?
    private let handler: @MainActor (PanelCommand) -> Void

    public init(handler: @escaping @MainActor (PanelCommand) -> Void) {
        self.handler = handler
    }

    public func start() throws {
        unlink(IPCPath.socket)
        descriptor = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw IPCError.socket }

        var (address, length) = try socketAddress(path: IPCPath.socket)
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, length)
            }
        }
        guard result == 0 else { throw IPCError.socket }
        chmod(IPCPath.socket, S_IRUSR | S_IWUSR)

        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: .global(qos: .userInitiated))
        source.setEventHandler { [weak self] in self?.receive() }
        source.setCancelHandler { [descriptor] in close(descriptor) }
        self.source = source
        source.resume()
    }

    private func receive() {
        var bytes = [UInt8](repeating: 0, count: 4096)
        let count = recv(descriptor, &bytes, bytes.count, 0)
        guard count > 0,
              let command = try? JSONDecoder().decode(PanelCommand.self, from: Data(bytes.prefix(count)))
        else { return }
        Task { @MainActor in handler(command) }
    }

    deinit {
        source?.cancel()
        unlink(IPCPath.socket)
    }
}

public enum IPCClient {
    public static func send(_ command: PanelCommand) throws {
        let descriptor = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { throw IPCError.socket }
        defer { close(descriptor) }

        var (address, length) = try socketAddress(path: IPCPath.socket)
        let data = try JSONEncoder().encode(command)
        let sent = data.withUnsafeBytes { dataPointer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, dataPointer.baseAddress, data.count, 0, $0, length)
                }
            }
        }
        guard sent == data.count else { throw IPCError.send }
    }
}
