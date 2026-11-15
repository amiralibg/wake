import Foundation

/// What Wake keeps about one installed extension, in `Extensions/extensions.json`.
struct ExtensionRecord: Codable, Identifiable, Equatable {
    /// Also the extension's storage identity and the host of its `webkit-extension://` URL.
    let id: String
    /// The package inside the extension's folder: `extension.zip` or `extension/`.
    var packageName: String
    var isEnabled = true
    /// Shown as its own button in the toolbar (the rest are in the extensions menu).
    var isPinned = true
    var installedAt = Date()
    /// Where it came from, and where its updates come from.
    var source: Source = .file
    /// Firefox Add-ons knows an add-on by slug and by GUID; both are kept so a store
    /// page recognises an add-on imported from Firefox or Zen.
    var storeAliases: [String] = []
    /// When Wake last looked for an update, and what it found.
    var lastUpdateCheck: Date?
    /// Set when an update asks for more access than was granted: it waits for a yes.
    var pendingUpdateVersion: String?
    /// Optional permissions granted after install (requested ones are granted by the
    /// install confirmation and granted again at each launch).
    var grantedPermissions: [String] = []
    var grantedMatchPatterns: [String] = []
    /// Where it may read and change pages without a click (Chrome's "Site access").
    var siteAccess: SiteAccess = .allSites
    /// With `.chosenSites`: the hosts it runs on by itself. Elsewhere it waits for a
    /// click on its button.
    var allowedSites: [String] = []

    enum SiteAccess: String, Codable {
        /// Everything the manifest asks for, granted at install.
        case allSites
        /// Only `allowedSites`, and the page you click it on.
        case chosenSites
    }

    enum Source: Codable, Equatable {
        case file
        case store(ExtensionStore, id: String)
        /// Copied from another browser's profile (and, if it came from a store there,
        /// updated from that store).
        case imported(browser: String, store: ExtensionStore?, id: String?)

        /// The store and item updates come from, if any.
        var storeItem: (store: ExtensionStore, id: String)? {
            switch self {
            case .file: nil
            case .store(let store, let id): (store, id)
            case .imported(_, let store?, let id?): (store, id)
            case .imported: nil
            }
        }

        var label: String? {
            switch self {
            case .file: nil
            case .store(let store, _): store.title
            case .imported(let browser, _, _): "From \(browser)"
            }
        }
    }

    func matches(store: ExtensionStore, id: String) -> Bool {
        guard let item = source.storeItem, item.store == store else { return false }
        return item.id == id || storeAliases.contains(id)
    }

    // Old records and new fields: everything added later decodes as its default.
    init(id: String, packageName: String) {
        self.id = id
        self.packageName = packageName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        packageName = try c.decode(String.self, forKey: .packageName)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        isPinned = try c.decodeIfPresent(Bool.self, forKey: .isPinned) ?? true
        installedAt = try c.decodeIfPresent(Date.self, forKey: .installedAt) ?? Date()
        source = (try? c.decodeIfPresent(Source.self, forKey: .source)) ?? .file
        storeAliases = try c.decodeIfPresent([String].self, forKey: .storeAliases) ?? []
        grantedPermissions = try c.decodeIfPresent([String].self, forKey: .grantedPermissions) ?? []
        grantedMatchPatterns = try c.decodeIfPresent([String].self, forKey: .grantedMatchPatterns) ?? []
        lastUpdateCheck = try c.decodeIfPresent(Date.self, forKey: .lastUpdateCheck)
        pendingUpdateVersion = try c.decodeIfPresent(String.self, forKey: .pendingUpdateVersion)
        siteAccess = (try? c.decodeIfPresent(SiteAccess.self, forKey: .siteAccess)) ?? .allSites
        allowedSites = try c.decodeIfPresent([String].self, forKey: .allowedSites) ?? []
    }
}

/// Copies extension packages into Wake's container, in a form WebKit loads.
///
/// `WKWebExtension(resourceBaseURL:)` takes a folder or a ZIP archive with
/// `manifest.json` at its root. A Firefox `.xpi` is a ZIP already. A Chrome `.crx` is
/// a signed header followed by a ZIP; the header is stripped here, because whether
/// the WebKit in a given macOS version unwraps CRX itself is not documented.
///
/// Limitation: the CRX signature is not verified. Wake treats every package as
/// sideloaded and asks before installing it; Chrome's store signature only proves the
/// file came from Google.
enum ExtensionPackage {
    enum Source {
        case file(URL)
        case download(URL)
        case store(ExtensionStore, id: String)

        /// Matches what store pages are told is in progress.
        var key: String {
            switch self {
            case .file(let url), .download(let url): url.absoluteString
            case .store(_, let id): id
            }
        }
    }

    enum Failure: LocalizedError {
        case unreadable, notAnExtension, download(String)

        var errorDescription: String? {
            switch self {
            case .unreadable: "Wake couldn't read that file."
            case .notAnExtension: "That isn't a browser extension (no manifest.json, or not a .crx, .xpi or .zip)."
            case .download(let reason): "The extension couldn't be downloaded: \(reason)"
            }
        }
    }

    static var root: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Extensions", isDirectory: true)
    }

    static func folder(for id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true)
    }

    static func packageURL(for record: ExtensionRecord) -> URL {
        folder(for: record.id).appendingPathComponent(record.packageName, isDirectory: record.packageName == "extension")
    }

    /// Copies `file` (a folder or an archive) into a new extension folder and returns
    /// the package's name in it.
    static func stage(_ file: URL, id: String) throws -> String {
        try stage(file, into: folder(for: id))
    }

    /// Copies or unpacks `file` into `folder` as `extension/`. Archives are unpacked
    /// rather than handed to WebKit as ZIPs: see `ZipExtractor` for why.
    static func stage(_ file: URL, into folder: URL) throws -> String {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: file.path, isDirectory: &isDirectory) else { throw Failure.unreadable }
        if isDirectory.boolValue {
            guard fm.fileExists(atPath: file.appendingPathComponent("manifest.json").path) else { throw Failure.notAnExtension }
            let target = folder.appendingPathComponent("extension", isDirectory: true)
            try fm.copyItem(at: file, to: target)
            return "extension"
        }
        let data = try Data(contentsOf: file, options: .mappedIfSafe)
        guard let zip = zipPayload(of: data) else { throw Failure.notAnExtension }
        return try unpack(zip, into: folder)
    }

    /// Unpacks a ZIP into `folder/extension`, replacing what was there.
    private static func unpack(_ zip: Data, into folder: URL) throws -> String {
        let fm = FileManager.default
        let target = folder.appendingPathComponent("extension", isDirectory: true)
        let scratch = folder.appendingPathComponent("unpacking-\(UUID().uuidString)", isDirectory: true)
        defer { try? fm.removeItem(at: scratch) }
        try ZipExtractor.extract(zip, to: scratch)
        guard fm.fileExists(atPath: scratch.appendingPathComponent("manifest.json").path) else { throw Failure.notAnExtension }
        try? fm.removeItem(at: target)
        try fm.moveItem(at: scratch, to: target)
        return "extension"
    }

    /// Packages installed by earlier versions of Wake were kept as `extension.zip`.
    /// Unpacks one in place and returns the new package name, or nil if it stays.
    static func unpackLegacyArchive(of record: ExtensionRecord) -> String? {
        guard record.packageName == "extension.zip" else { return nil }
        let folder = folder(for: record.id)
        let archive = folder.appendingPathComponent("extension.zip")
        do {
            let name = try unpack(try Data(contentsOf: archive, options: .mappedIfSafe), into: folder)
            try? FileManager.default.removeItem(at: archive)
            return name
        } catch {
            NSLog("Wake: couldn't unpack \(record.id): \(error.localizedDescription)")
            return nil
        }
    }

    /// The ZIP inside a `.zip`, `.xpi` or `.crx` (CRX2 and CRX3), or nil.
    static func zipPayload(of data: Data) -> Data? {
        let bytes = [UInt8](data.prefix(16))
        if bytes.starts(with: [0x50, 0x4B, 0x03, 0x04]) { return data }
        guard bytes.count >= 12, bytes.starts(with: Array("Cr24".utf8)) else { return nil }
        func uint32(at offset: Int) -> Int {
            Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3]) << 24
        }
        let start: Int
        switch uint32(at: 4) {
        case 3: start = 12 + uint32(at: 8)
        case 2 where bytes.count >= 16: start = 16 + uint32(at: 8) + uint32(at: 12)
        default: return nil
        }
        guard start < data.count else { return nil }
        let zip = data.subdata(in: data.startIndex + start ..< data.endIndex)
        return zip.starts(with: [0x50, 0x4B]) ? zip : nil
    }

    /// Downloads a package to a temporary file.
    static func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("application/x-chrome-extension, application/x-xpinstall, application/zip, */*", forHTTPHeaderField: "Accept")
        let (file, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw Failure.download("the server answered \(http.statusCode)")
        }
        let target = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.moveItem(at: file, to: target)
        return target
    }
}
