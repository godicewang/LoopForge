import Foundation

/// Locale-free hexadecimal encoding for digest construction. This avoids
/// Foundation's validated variadic formatter, whose per-byte stack use can
/// overflow Swift cooperative threads at deeply composed authority boundaries.
enum KernelHex {
    private static let digits = Array("0123456789abcdef".utf8)

    static func byte(_ value: UInt8) -> String {
        String(decoding: [
            digits[Int(value >> 4)],
            digits[Int(value & 0x0f)]
        ], as: UTF8.self)
    }

    static func encode<S: Sequence>(_ bytes: S) -> String
        where S.Element == UInt8 {
        bytes.map(byte).joined()
    }
}
