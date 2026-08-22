import Foundation

enum MirrorCacheFormatting {
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        return formatter
    }()

    static func byteCount(_ bytes: Int64) -> String {
        byteCountFormatter.string(fromByteCount: bytes)
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
