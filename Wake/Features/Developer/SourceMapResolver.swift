import Foundation

/// Maps a position in served JavaScript back to the original source file, using the
/// script's source map (a `//# sourceMappingURL=` comment: inline `data:` or a URL).
/// Vite, Next and webpack all serve these in development.
enum SourceMapResolver {
    struct Original: Sendable {
        /// As written in the map, e.g. "webpack://app/./src/App.tsx" or "/src/App.tsx".
        let source: String
        let line: Int
        let column: Int

        /// The source as a path inside the project: prefixes and queries stripped.
        var projectRelativePath: String {
            var path = source
            if let range = path.range(of: #"^[a-z-]+://[^/]*/"#, options: .regularExpression) { path.removeSubrange(range) }
            if let query = path.firstIndex(of: "?") { path = String(path[..<query]) }
            while path.hasPrefix("./") || path.hasPrefix("../") {
                path = String(path.drop(while: { $0 == "." }).dropFirst())
            }
            if path.hasPrefix("/@fs/") { path = String(path.dropFirst(4)) }  // Vite: absolute path outside root
            return path
        }
    }

    static func resolve(_ location: SourceLocation, session: URLSession = .shared) async -> Original? {
        guard let (scriptData, _) = try? await session.data(from: location.url) else { return nil }
        let script = String(decoding: scriptData, as: UTF8.self)
        guard let reference = script.matches(of: #/[#@] sourceMappingURL=(\S+)/#).last.map({ String($0.1) }),
              let mapData = await loadMap(reference, relativeTo: location.url, session: session),
              let map = try? JSONDecoder().decode(SourceMap.self, from: mapData) else { return nil }
        return map.original(line: location.line - 1, column: location.column - 1)
    }

    private static func loadMap(_ reference: String, relativeTo scriptURL: URL, session: URLSession) async -> Data? {
        if reference.hasPrefix("data:") {
            guard let comma = reference.firstIndex(of: ",") else { return nil }
            let payload = String(reference[reference.index(after: comma)...])
            return reference[..<comma].contains("base64") ? Data(base64Encoded: payload) : payload.removingPercentEncoding.map { Data($0.utf8) }
        }
        guard let url = URL(string: reference, relativeTo: scriptURL) else { return nil }
        return try? await session.data(from: url).0
    }
}

/// Source map v3: https://sourcemaps.info/spec.html
private struct SourceMap: Decodable {
    let sources: [String]
    let sourceRoot: String?
    let mappings: String

    /// Finds the segment covering a 0-based generated line and column.
    func original(line targetLine: Int, column targetColumn: Int) -> SourceMapResolver.Original? {
        // Source index, original line and column are deltas across the whole file;
        // the generated column resets on each line.
        var source = 0, originalLine = 0, originalColumn = 0
        var best: (source: Int, line: Int, column: Int)?
        for (lineIndex, lineText) in mappings.split(separator: ";", omittingEmptySubsequences: false).enumerated() {
            guard lineIndex <= targetLine else { break }
            var generatedColumn = 0
            for segment in lineText.split(separator: ",") {
                let values = Self.decodeVLQ(segment)
                guard !values.isEmpty else { continue }
                generatedColumn += values[0]
                if values.count >= 4 {
                    source += values[1]
                    originalLine += values[2]
                    originalColumn += values[3]
                    if lineIndex == targetLine, generatedColumn <= targetColumn {
                        best = (source, originalLine, originalColumn)
                    }
                }
            }
        }
        guard let best, sources.indices.contains(best.source) else { return nil }
        let root = sourceRoot.map { $0.hasSuffix("/") || $0.isEmpty ? $0 : $0 + "/" } ?? ""
        return .init(source: root + sources[best.source], line: best.line + 1, column: best.column + 1)
    }

    private static let base64: [Character: Int] = Dictionary(
        uniqueKeysWithValues: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".enumerated().map { ($1, $0) }
    )

    static func decodeVLQ(_ segment: Substring) -> [Int] {
        var values: [Int] = []
        var value = 0, shift = 0
        for character in segment {
            guard let digit = base64[character] else { return values }
            value += (digit & 31) << shift
            if digit & 32 != 0 {
                shift += 5
            } else {
                values.append(value & 1 == 1 ? -(value >> 1) : value >> 1)
                value = 0
                shift = 0
            }
        }
        return values
    }
}
