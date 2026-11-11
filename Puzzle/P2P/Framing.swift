import Foundation

/// One unit on the wire: a kind byte plus its payload.
struct RawFrame: Equatable {
    static let kindControl: UInt8 = 0
    static let kindImage: UInt8 = 1

    let kind: UInt8
    let payload: Data
}

enum FramingError: Error { case frameTooLarge }

/// Wire format: 4-byte big-endian length (kind + payload), 1 kind byte, payload.
/// Frames larger than `maxFrameBytes` are refused on both ends.
enum Framing {
    static let maxFrameBytes = 8 * 1024 * 1024

    static func encode(_ frame: RawFrame) throws -> Data {
        let length = frame.payload.count + 1
        guard length <= maxFrameBytes else { throw FramingError.frameTooLarge }
        var out = Data(capacity: 4 + length)
        out.append(UInt8(truncatingIfNeeded: length >> 24))
        out.append(UInt8(truncatingIfNeeded: length >> 16))
        out.append(UInt8(truncatingIfNeeded: length >> 8))
        out.append(UInt8(truncatingIfNeeded: length))
        out.append(frame.kind)
        out.append(frame.payload)
        return out
    }

    /// Reassembles frames from arbitrary TCP chunks. Not thread-safe; use from one reader.
    final class Decoder {
        private var buffer = [UInt8]()

        func feed(_ chunk: Data) throws -> [RawFrame] {
            if !chunk.isEmpty { buffer.append(contentsOf: chunk) }
            var frames: [RawFrame] = []
            var offset = 0
            while buffer.count - offset >= 4 {
                let length = Int(buffer[offset]) << 24 | Int(buffer[offset + 1]) << 16 | Int(buffer[offset + 2]) << 8 | Int(buffer[offset + 3])
                guard (1...Framing.maxFrameBytes).contains(length) else { throw FramingError.frameTooLarge }
                if buffer.count - offset - 4 < length { break }
                let kind = buffer[offset + 4]
                frames.append(RawFrame(kind: kind, payload: Data(buffer[(offset + 5)..<(offset + 4 + length)])))
                offset += 4 + length
            }
            if offset > 0 { buffer.removeFirst(offset) }
            return frames
        }
    }
}
