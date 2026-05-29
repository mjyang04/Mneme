import Foundation

public enum Vector {
    public static func l2norm(_ vector: [Float]) -> Float {
        sqrt(vector.reduce(0) { $0 + $1 * $1 })
    }

    public static func normalize(_ vector: [Float]) -> [Float] {
        let norm = l2norm(vector)
        guard norm > 0 else { return vector }
        return vector.map { $0 / norm }
    }

    public static func dot(_ lhs: [Float], _ rhs: [Float]) -> Float {
        guard lhs.count == rhs.count else { return 0 }
        return zip(lhs, rhs).reduce(Float(0)) { $0 + $1.0 * $1.1 }
    }

    public static func fnv1a(_ text: String) -> UInt32 {
        var hash: UInt32 = 2_166_136_261
        for byte in text.utf8 {
            hash = (hash ^ UInt32(byte)) &* 16_777_619
        }
        return hash
    }
}

public extension Array where Element == Float {
    var data: Data {
        withUnsafeBufferPointer { Data(buffer: $0) }
    }

    init(data: Data) {
        self = data.withUnsafeBytes { rawBuffer in
            Array(rawBuffer.bindMemory(to: Float.self))
        }
    }
}
