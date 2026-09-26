import Foundation

/// Safari's `Cookies.binarycookies`: a big-endian page index, then little-endian
/// pages of cookie records whose strings are NUL-terminated at offsets.
///
/// Limitation: the file lives in Safari's container, which macOS keeps private;
/// Wake reads it only with Full Disk Access.
enum SafariCookies {
    static var file: URL {
        BrowserCatalog.home.appendingPathComponent("Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies")
    }

    static func read() throws -> [ImportedCookie] {
        guard let data = try? Data(contentsOf: file) else { throw ImportFailure.needsFullDiskAccess }
        return parse(data)
    }

    static func parse(_ data: Data) -> [ImportedCookie] {
        let bytes = [UInt8](data)
        guard bytes.count > 8, bytes[0..<4].elementsEqual(Array("cook".utf8)) else { return [] }
        let pageCount = Int(bigEndian32(bytes, 4))
        var pageSizes: [Int] = []
        for index in 0..<pageCount {
            let offset = 8 + index * 4
            guard offset + 4 <= bytes.count else { return [] }
            pageSizes.append(Int(bigEndian32(bytes, offset)))
        }
        var cookies: [ImportedCookie] = []
        let now = Date.now
        var pageStart = 8 + pageCount * 4
        for size in pageSizes {
            defer { pageStart += size }
            guard pageStart + size <= bytes.count, size > 8 else { break }
            let page = Array(bytes[pageStart..<(pageStart + size)])
            let count = Int(littleEndian32(page, 4))
            for index in 0..<count {
                let at = 8 + index * 4
                guard at + 4 <= page.count else { break }
                let start = Int(littleEndian32(page, at))
                guard let cookie = record(page, start: start), cookie.expires.map({ $0 > now }) ?? true else { continue }
                cookies.append(cookie)
            }
        }
        return cookies
    }

    private static func record(_ page: [UInt8], start: Int) -> ImportedCookie? {
        guard start + 56 <= page.count else { return nil }
        let size = Int(littleEndian32(page, start))
        guard size >= 56, start + size <= page.count else { return nil }
        let cookie = Array(page[start..<(start + size)])
        let flags = littleEndian32(cookie, 8)
        func string(at field: Int) -> String? {
            let offset = Int(littleEndian32(cookie, field))
            guard offset < cookie.count, let end = cookie[offset...].firstIndex(of: 0) else { return nil }
            return String(decoding: cookie[offset..<end], as: UTF8.self)
        }
        guard let domain = string(at: 16), let name = string(at: 20) else { return nil }
        let expiry = cookie.withUnsafeBytes { $0.loadUnaligned(fromByteOffset: 40, as: Double.self) }
        return ImportedCookie(
            domain: domain, path: string(at: 24) ?? "/", name: name, value: string(at: 28) ?? "",
            expires: expiry > 0 ? Date(timeIntervalSinceReferenceDate: expiry) : nil,
            isSecure: flags & 1 != 0, isHTTPOnly: flags & 4 != 0, sameSite: nil
        )
    }

    private static func bigEndian32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reduce(0) { $0 << 8 | UInt32($1) }
    }

    private static func littleEndian32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        bytes[offset..<(offset + 4)].reversed().reduce(0) { $0 << 8 | UInt32($1) }
    }
}
