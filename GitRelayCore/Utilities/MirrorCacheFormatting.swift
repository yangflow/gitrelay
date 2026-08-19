import Foundation

enum MirrorCacheFormatting {
    static func byteCount(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func usageSummary(usageBytes: Int64, quotaGB: Int?) -> String {
        let usage = byteCount(usageBytes)
        guard let quotaGB else {
            return String(format: String(localized: "%@ used (unlimited quota)"), usage)
        }
        let quota = byteCount(MirrorCacheManager.quotaLimitBytes(for: quotaGB) ?? 0)
        return String(format: String(localized: "%1$@ of %2$@ used"), usage, quota)
    }
}
