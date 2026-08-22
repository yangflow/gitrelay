import Foundation

enum MirrorCacheFormatting {
    static func byteCount(_ bytes: Int64, locale: Locale = .current) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB, .useTB]
        formatter.includesUnit = true
        formatter.isAdaptive = true
        formatter.zeroPadsFractionDigits = false
        formatter.locale = locale
        return formatter.string(fromByteCount: bytes)
    }

    static func usageSummary(
        usageBytes: Int64,
        quotaGB: Int?,
        locale: Locale = .current
    ) -> String {
        let usage = byteCount(usageBytes, locale: locale)
        guard let quotaGB else {
            return String(format: String(localized: "%@ used (unlimited quota)"), usage)
        }
        let quota = byteCount(MirrorCacheManager.quotaLimitBytes(for: quotaGB) ?? 0, locale: locale)
        return String(format: String(localized: "%1$@ of %2$@ used"), usage, quota)
    }
}
