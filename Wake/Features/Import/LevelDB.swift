import Foundation

/// Just enough LevelDB to read Chromium's "Local Storage/leveldb" folder: every table
/// file (`.ldb`/`.sst`) and write-ahead log (`.log`), newest sequence number winning.
/// The manifest is ignored; LevelDB deletes obsolete files promptly, and sequence
/// numbers order whatever is left.
enum LevelDB {
    /// The live key/value pairs in `folder`.
    static func read(_ folder: URL) -> [Data: Data] {
        var latest: [Data: (sequence: UInt64, value: Data?)] = [:]
        func apply(_ key: Data, _ sequence: UInt64, _ value: Data?) {
            if let known = latest[key], known.sequence > sequence { return }
            latest[key] = (sequence, value)
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            guard let data = try? Data(contentsOf: file) else { continue }
            switch file.pathExtension {
            case "ldb", "sst": Table.entries(data, apply)
            case "log": Log.entries(data, apply)
            default: continue
            }
        }
        var result: [Data: Data] = [:]
        for (key, entry) in latest { if let value = entry.value { result[key] = value } }
        return result
    }

    // MARK: Tables

    private enum Table {
        static func entries(_ data: Data, _ emit: (Data, UInt64, Data?) -> Void) {
            let bytes = [UInt8](data)
            // Footer: metaindex and index handles, padding, 8-byte magic.
            guard bytes.count >= 48, bytes.suffix(8).elementsEqual([0x57, 0xFB, 0x80, 0x8B, 0x24, 0x75, 0x47, 0xDB]) else { return }
            var reader = Reader(bytes: bytes, at: bytes.count - 48)
            guard reader.varint() != nil, reader.varint() != nil,
                  let indexOffset = reader.varint(), let indexSize = reader.varint(),
                  let index = block(bytes, offset: Int(indexOffset), size: Int(indexSize))
            else { return }
            for (_, handle) in entries(of: index) {
                var handleReader = Reader(bytes: handle, at: 0)
                guard let offset = handleReader.varint(), let size = handleReader.varint(),
                      let block = block(bytes, offset: Int(offset), size: Int(size))
                else { continue }
                for (internalKey, value) in entries(of: block) where internalKey.count >= 8 {
                    // The last 8 bytes: sequence << 8 | type (1 = value, 0 = deletion).
                    let tag = internalKey.suffix(8).reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
                    let key = Data(internalKey.dropLast(8))
                    emit(key, tag >> 8, tag & 0xFF == 1 ? Data(value) : nil)
                }
            }
        }

        /// A block's contents, decompressed; the 5-byte trailer (type, CRC) follows it.
        private static func block(_ bytes: [UInt8], offset: Int, size: Int) -> [UInt8]? {
            guard offset >= 0, size >= 0, offset + size + 5 <= bytes.count else { return nil }
            let contents = Array(bytes[offset..<(offset + size)])
            switch bytes[offset + size] {
            case 0: return contents
            case 1: return Snappy.decompress(contents)
            default: return nil
            }
        }

        /// Prefix-compressed entries, followed by restart offsets and their count.
        private static func entries(of block: [UInt8]) -> [([UInt8], [UInt8])] {
            guard block.count >= 4 else { return [] }
            let restarts = Int(block.suffix(4).reversed().reduce(UInt32(0)) { $0 << 8 | UInt32($1) })
            let end = block.count - 4 - restarts * 4
            guard end >= 0 else { return [] }
            var reader = Reader(bytes: block, at: 0)
            var key: [UInt8] = []
            var result: [([UInt8], [UInt8])] = []
            while reader.position < end {
                guard let shared = reader.varint(), let unshared = reader.varint(), let valueLength = reader.varint(),
                      Int(shared) <= key.count,
                      let delta = reader.take(Int(unshared)), let value = reader.take(Int(valueLength))
                else { break }
                key = Array(key.prefix(Int(shared))) + delta
                result.append((key, value))
            }
            return result
        }
    }

    // MARK: Logs

    private enum Log {
        static func entries(_ data: Data, _ emit: (Data, UInt64, Data?) -> Void) {
            let bytes = [UInt8](data)
            let blockSize = 32_768
            var position = 0
            var pending: [UInt8] = []
            while position + 7 <= bytes.count {
                let left = blockSize - position % blockSize
                if left < 7 { position += left; continue }
                let length = Int(bytes[position + 4]) | Int(bytes[position + 5]) << 8
                let type = bytes[position + 6]
                let start = position + 7
                guard start + length <= bytes.count else { break }
                let fragment = bytes[start..<(start + length)]
                position = start + length
                switch type {
                case 1: batch(Array(fragment), emit)
                case 2: pending = Array(fragment)
                case 3: pending += fragment
                case 4:
                    pending += fragment
                    batch(pending, emit)
                    pending = []
                default: continue
                }
            }
        }

        /// A write batch: 8-byte sequence, 4-byte count, then tagged puts and deletes.
        private static func batch(_ record: [UInt8], _ emit: (Data, UInt64, Data?) -> Void) {
            guard record.count >= 12 else { return }
            let sequence = record[0..<8].reversed().reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            var reader = Reader(bytes: record, at: 12)
            var index: UInt64 = 0
            while reader.position < record.count {
                guard let tag = reader.byte(), let keyLength = reader.varint(), let key = reader.take(Int(keyLength)) else { return }
                if tag == 1 {
                    guard let valueLength = reader.varint(), let value = reader.take(Int(valueLength)) else { return }
                    emit(Data(key), sequence + index, Data(value))
                } else {
                    emit(Data(key), sequence + index, nil)
                }
                index += 1
            }
        }
    }

    struct Reader {
        let bytes: [UInt8]
        var position: Int

        init(bytes: [UInt8], at position: Int) {
            self.bytes = bytes
            self.position = position
        }

        mutating func byte() -> UInt8? {
            guard position < bytes.count else { return nil }
            defer { position += 1 }
            return bytes[position]
        }

        mutating func varint() -> UInt64? {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while shift < 64, let byte = byte() {
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
            }
            return nil
        }

        mutating func take(_ count: Int) -> [UInt8]? {
            guard count >= 0, position + count <= bytes.count else { return nil }
            defer { position += count }
            return Array(bytes[position..<(position + count)])
        }
    }
}

/// Raw (unframed) Snappy, as LevelDB and Firefox's storage use it.
enum Snappy {
    static func decompress(_ input: [UInt8]) -> [UInt8]? {
        var reader = LevelDB.Reader(bytes: input, at: 0)
        guard let length = reader.varint(), length < 256 * 1_024 * 1_024 else { return nil }
        var output: [UInt8] = []
        output.reserveCapacity(Int(length))
        while let tag = reader.byte() {
            switch tag & 0x03 {
            case 0:
                var count = Int(tag >> 2)
                if count >= 60 {
                    let extra = count - 59
                    guard let bytes = reader.take(extra) else { return nil }
                    count = bytes.reversed().reduce(0) { $0 << 8 | Int($1) }
                }
                guard let literal = reader.take(count + 1) else { return nil }
                output += literal
            case 1:
                guard let next = reader.byte() else { return nil }
                let count = 4 + Int((tag >> 2) & 0x07)
                let offset = Int(tag >> 5) << 8 | Int(next)
                guard copy(&output, offset: offset, count: count) else { return nil }
            case 2:
                guard let bytes = reader.take(2) else { return nil }
                guard copy(&output, offset: Int(bytes[0]) | Int(bytes[1]) << 8, count: Int(tag >> 2) + 1) else { return nil }
            default:
                guard let bytes = reader.take(4) else { return nil }
                let offset = bytes.reversed().reduce(0) { $0 << 8 | Int($1) }
                guard copy(&output, offset: offset, count: Int(tag >> 2) + 1) else { return nil }
            }
        }
        return output.count == Int(length) ? output : nil
    }

    /// Copies byte by byte: the source may overlap what's being written (runs).
    private static func copy(_ output: inout [UInt8], offset: Int, count: Int) -> Bool {
        guard offset > 0, offset <= output.count else { return false }
        let start = output.count - offset
        for index in 0..<count { output.append(output[start + index]) }
        return true
    }
}
