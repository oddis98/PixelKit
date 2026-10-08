import Foundation

/// What the editor and a game it runs say to each other. The editor listens on a Unix socket and puts its path in
/// the game's `PIXELKIT_EDITOR` environment variable; the game connects and sends its frames there instead of
/// opening a window.
public enum Message: Equatable, Sendable {
    /// Game to editor, every frame: the canvas as BGRA bytes, row by row.
    case frame(width: Int, height: Int, pixels: Data)
    /// Editor to game: key codes held down in the preview.
    case keys([Int])
    /// Editor to game: stop updating, carry on, or run one update while paused.
    case pause, resume, step

    public static let environmentKey = "PIXELKIT_EDITOR"
}

extension Message {
    /// A length (UInt32), a tag byte, then the payload. Numbers are little-endian.
    public var encoded: Data {
        var payload = Data()
        func append<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { payload.append(contentsOf: $0) } }
        let tag: UInt8
        switch self {
        case let .frame(width, height, pixels):
            tag = 1
            append(UInt16(width))
            append(UInt16(height))
            payload.append(pixels)
        case let .keys(keys):
            tag = 2
            keys.forEach { append(UInt16($0)) }
        case .pause: tag = 3
        case .resume: tag = 4
        case .step: tag = 5
        }
        var data = Data()
        withUnsafeBytes(of: UInt32(payload.count + 1).littleEndian) { data.append(contentsOf: $0) }
        data.append(tag)
        return data + payload
    }

    /// Removes every complete message from the front of `buffer` and returns them. A partial one stays for later.
    public static func take(from buffer: inout Data) -> [Message] {
        var messages: [Message] = []
        while buffer.count >= 4 {
            let length = Int(buffer.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(as: UInt32.self)) })
            guard buffer.count >= 4 + length else { break }
            let body = Data(buffer.dropFirst(4).prefix(length))
            buffer = Data(buffer.dropFirst(4 + length))
            if let message = Message(body) { messages.append(message) }
        }
        return messages
    }

    init?(_ body: Data) {
        guard let tag = body.first else { return nil }
        let payload = Data(body.dropFirst())
        func number(at offset: Int) -> Int {
            Int(payload.withUnsafeBytes { UInt16(littleEndian: $0.loadUnaligned(fromByteOffset: offset, as: UInt16.self)) })
        }
        switch tag {
        case 1 where payload.count >= 4: self = .frame(width: number(at: 0), height: number(at: 2), pixels: Data(payload.dropFirst(4)))
        case 2: self = .keys(stride(from: 0, to: payload.count - 1, by: 2).map(number))
        case 3: self = .pause
        case 4: self = .resume
        case 5: self = .step
        default: return nil
        }
    }
}

/// One end of the editor–game connection: sends messages, and hands over the ones that arrive.
public final class Channel: @unchecked Sendable { // `buffer` is only touched on the read handler's queue
    let handle: FileHandle
    var buffer = Data()

    init(_ socket: Int32) {
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size)) // hang-ups are errors, not crashes
        handle = FileHandle(fileDescriptor: socket, closeOnDealloc: true)
    }

    /// Connects to an editor listening at `path`.
    public static func connect(to path: String) -> Channel? {
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = unixAddress(path)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard socket >= 0, connected == 0 else {
            Darwin.close(socket)
            return nil
        }
        return Channel(socket)
    }

    public func send(_ message: Message) { try? handle.write(contentsOf: message.encoded) }

    /// Calls `received` for each message, on a background queue, and `closed` once the other side hangs up.
    public func listen(_ received: @escaping @Sendable (Message) -> Void, closed: @escaping @Sendable () -> Void) {
        handle.readabilityHandler = { [self] handle in
            let data = handle.availableData
            guard !data.isEmpty else {
                handle.readabilityHandler = nil
                closed()
                return
            }
            buffer.append(data)
            Message.take(from: &buffer).forEach(received)
        }
    }

    public func close() {
        handle.readabilityHandler = nil
        try? handle.close()
    }
}

/// A Unix socket the editor listens on. The first game to connect gets a `Channel`.
public final class Listener: @unchecked Sendable {
    let socket: Int32
    public let path: String

    public init(path: String, connected: @escaping @Sendable (Channel) -> Void) throws {
        unlink(path)
        let socket = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        var address = unixAddress(path)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(socket, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard socket >= 0, bound == 0, Darwin.listen(socket, 1) == 0 else {
            Darwin.close(socket)
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        (self.socket, self.path) = (socket, path)
        Thread.detachNewThread { // accept() waits; close() wakes it up
            let client = accept(socket, nil, nil)
            if client >= 0 { connected(Channel(client)) }
        }
    }

    public func close() {
        Darwin.close(socket)
        unlink(path)
    }
}

func unixAddress(_ path: String) -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)
    withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: path.utf8.prefix($0.count - 1)) }
    return address
}
