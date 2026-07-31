import CryptoKit
import Foundation

/// Content hashing for duplicate detection. CryptoKit gives
/// hardware-accelerated SHA-256 on Apple Silicon at no dependency cost.
enum HashService {
    /// Streams the file in fixed-size chunks rather than loading it fully
    /// into memory — matters for multi-GB video files.
    static func sha256(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var hasher = SHA256()
        let chunkSize = 1 << 20 // 1 MB
        while true {
            let data = handle.readData(ofLength: chunkSize)
            if data.isEmpty { break }
            hasher.update(data: data)
        }
        return hasher.finalize().compactMap { String(format: "%02x", $0) }.joined()
    }
}
