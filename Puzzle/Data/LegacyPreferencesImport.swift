import Foundation

/// One-time import of settings and scores saved by the previous (Kotlin Multiplatform) build,
/// which kept them in a Jetpack DataStore file, `Documents/puzzle.preferences_pb`.
enum LegacyPreferencesImport {
    static let fileName = "puzzle.preferences_pb"
    private static let doneKey = "legacyPreferencesImported"

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: doneKey) else { return }
        defer { defaults.set(true, forKey: doneKey) }
        guard
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
            let data = try? Data(contentsOf: documents.appendingPathComponent(fileName))
        else { return }
        for (key, value) in decode(data) where defaults.object(forKey: key) == nil {
            switch value {
            case .int(let number): defaults.set(number, forKey: key)
            case .string(let text): defaults.set(text, forKey: key)
            }
        }
    }

    enum Value: Equatable {
        case int(Int)
        case string(String)
    }

    /// Reads the `PreferenceMap` protobuf: `map<string, Value> preferences = 1`, where
    /// `Value` holds `integer = 3`, `long = 4` or `string = 5` for the keys this app writes.
    static func decode(_ data: Data) -> [String: Value] {
        var result: [String: Value] = [:]
        var reader = ProtoReader(Array(data))
        while let (field, wire) = reader.tag() {
            guard field == 1, wire == 2, let entryBytes = reader.lengthDelimited() else {
                guard reader.skip(wire) else { break }
                continue
            }
            var entry = ProtoReader(entryBytes)
            var key: String?
            var value: Value?
            while let (entryField, entryWire) = entry.tag() {
                if entryField == 1, entryWire == 2, let bytes = entry.lengthDelimited() {
                    key = String(decoding: bytes, as: UTF8.self)
                } else if entryField == 2, entryWire == 2, let bytes = entry.lengthDelimited() {
                    value = decodeValue(bytes)
                } else if !entry.skip(entryWire) {
                    break
                }
            }
            if let key, let value { result[key] = value }
        }
        return result
    }

    private static func decodeValue(_ bytes: [UInt8]) -> Value? {
        var reader = ProtoReader(bytes)
        while let (field, wire) = reader.tag() {
            switch (field, wire) {
            case (3, 0), (4, 0):
                guard let raw = reader.varint() else { return nil }
                return .int(field == 3 ? Int(Int32(truncatingIfNeeded: raw)) : Int(Int64(bitPattern: raw)))
            case (5, 2):
                guard let text = reader.lengthDelimited() else { return nil }
                return .string(String(decoding: text, as: UTF8.self))
            default:
                guard reader.skip(wire) else { return nil }
            }
        }
        return nil
    }
}

private struct ProtoReader {
    private let bytes: [UInt8]
    private var position = 0

    init(_ bytes: [UInt8]) { self.bytes = bytes }

    mutating func tag() -> (field: Int, wire: Int)? {
        guard position < bytes.count, let raw = varint() else { return nil }
        return (Int(raw >> 3), Int(raw & 0x7))
    }

    mutating func varint() -> UInt64? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        while position < bytes.count, shift < 64 {
            let byte = bytes[position]
            position += 1
            result |= UInt64(byte & 0x7F) << shift
            if byte & 0x80 == 0 { return result }
            shift += 7
        }
        return nil
    }

    mutating func lengthDelimited() -> [UInt8]? {
        guard let length = varint(), length <= UInt64(bytes.count - position) else { return nil }
        let end = position + Int(length)
        defer { position = end }
        return Array(bytes[position..<end])
    }

    mutating func skip(_ wire: Int) -> Bool {
        switch wire {
        case 0: return varint() != nil
        case 1: return advance(8)
        case 2: return lengthDelimited() != nil
        case 5: return advance(4)
        default: return false
        }
    }

    private mutating func advance(_ count: Int) -> Bool {
        guard position + count <= bytes.count else { return false }
        position += count
        return true
    }
}
