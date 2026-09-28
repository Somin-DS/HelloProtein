import Foundation
import CryptoKit

/// Stable SHA-256 over the canonical JSON of a capture. The capture time is
/// not part of the input, so re-reading the same source gives the same digest.
public enum LegacyFingerprint {
    public static func sha256Hex(of capture: LegacyCapture) throws -> String {
        sha256Hex(of: try canonicalData(capture))
    }

    public static func canonicalData(_ capture: LegacyCapture) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(LegacySnapshotBuilder.instantString(date))
        }
        return try encoder.encode(capture)
    }

    public static func sha256Hex(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
