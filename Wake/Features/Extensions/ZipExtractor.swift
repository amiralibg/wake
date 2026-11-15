import Compression
import Foundation

/// Unpacks a ZIP archive (an extension's `.zip`, `.xpi`, or a `.crx` payload) into a
/// folder.
///
/// Wake unpacks packages itself instead of handing WebKit the archive: with a ZIP as
/// `resourceBaseURL`, WebKit extracts it to a new temporary folder at every launch,
/// and an extension loaded that way stops answering its own popup after a relaunch
/// (`runtime.sendMessage` from the popup gets no reply from the service worker).
/// The same extension loaded from a folder keeps working. Seen with Dark Reader,
/// uBlock Origin and Tampermonkey on macOS 27.
///
/// Handles stored and deflated entries, which is what extension packages use. ZIP64
/// archives and encrypted entries are refused.
enum ZipExtractor {
    enum Failure: LocalizedError {
        case notAZip, unsupported(String), corrupt, unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .notAZip: "The file isn't a ZIP archive."
            case .unsupported(let what): "The archive uses \(what), which Wake can't unpack."
            case .corrupt: "The archive is damaged."
            case .unsafePath(let path): "The archive has an unsafe file path: \(path)"
            }
        }
    }

    static func extract(_ data: Data, to folder: URL) throws {
        let bytes = [UInt8](data)
        guard let end = endOfCentralDirectory(bytes) else { throw Failure.notAZip }
        let count = Int(u16(bytes, end + 10))
        var offset = Int(u32(bytes, end + 16))
        if count == 0xFFFF || offset == 0xFFFF_FFFF { throw Failure.unsupported("ZIP64") }
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)

        for _ in 0..<count {
            guard offset + 46 <= bytes.count, u32(bytes, offset) == 0x0201_4B50 else { throw Failure.corrupt }
            let flags = u16(bytes, offset + 8)
            let method = u16(bytes, offset + 10)
            let compressedSize = Int(u32(bytes, offset + 20))
            let size = Int(u32(bytes, offset + 24))
            let nameLength = Int(u16(bytes, offset + 28))
            let extraLength = Int(u16(bytes, offset + 30))
            let commentLength = Int(u16(bytes, offset + 32))
            let localOffset = Int(u32(bytes, offset + 42))
            guard offset + 46 + nameLength <= bytes.count else { throw Failure.corrupt }
            let name = String(decoding: bytes[(offset + 46)..<(offset + 46 + nameLength)], as: UTF8.self)
            offset += 46 + nameLength + extraLength + commentLength

            if flags & 1 != 0 { throw Failure.unsupported("encryption") }
            let path = name.replacingOccurrences(of: "\\", with: "/")
            // Nothing may land outside the folder: no absolute paths, no "..".
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            guard !path.hasPrefix("/"), !components.contains(".."), !components.isEmpty else { throw Failure.unsafePath(name) }
            let target = folder.appendingPathComponent(path)
            if path.hasSuffix("/") {
                try fm.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }

            guard localOffset + 30 <= bytes.count, u32(bytes, localOffset) == 0x0403_4B50 else { throw Failure.corrupt }
            let start = localOffset + 30 + Int(u16(bytes, localOffset + 26)) + Int(u16(bytes, localOffset + 28))
            guard start + compressedSize <= bytes.count else { throw Failure.corrupt }
            let payload = data.subdata(in: data.startIndex + start ..< data.startIndex + start + compressedSize)
            let contents: Data
            switch method {
            case 0: contents = payload
            case 8: contents = try inflate(payload, size: size)
            default: throw Failure.unsupported("compression method \(method)")
            }
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: target)
        }
    }

    /// The end-of-central-directory record is in the last 64 KB + 22 bytes.
    private static func endOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        var index = bytes.count - 22
        while index >= lowest {
            if u32(bytes, index) == 0x0605_4B50 { return index }
            index -= 1
        }
        return nil
    }

    /// Raw DEFLATE, which is what Compression's `COMPRESSION_ZLIB` decodes.
    private static func inflate(_ payload: Data, size: Int) throws -> Data {
        if size == 0 { return Data() }
        var output = Data(count: size)
        let written = output.withUnsafeMutableBytes { out in
            payload.withUnsafeBytes { input in
                compression_decode_buffer(
                    out.bindMemory(to: UInt8.self).baseAddress!, size,
                    input.bindMemory(to: UInt8.self).baseAddress!, payload.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard written == size else { throw Failure.corrupt }
        return output
    }

    private static func u16(_ bytes: [UInt8], _ at: Int) -> UInt16 {
        UInt16(bytes[at]) | UInt16(bytes[at + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ at: Int) -> UInt32 {
        UInt32(bytes[at]) | UInt32(bytes[at + 1]) << 8 | UInt32(bytes[at + 2]) << 16 | UInt32(bytes[at + 3]) << 24
    }
}
