import Foundation

enum ArchiveRetention {
    /// Returns archive paths to delete so that at most `keepCount` newest matching archives remain.
    static func archivesToDelete(
        in directory: URL,
        matchingPrefix prefix: String,
        keepCount: Int,
        fileManager: FileManager = .default
    ) -> [URL] {
        guard keepCount > 0 else { return [] }

        let prefixLower = prefix.lowercased()
        guard let entries = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let matching = entries.filter { url in
            url.lastPathComponent.lowercased().hasPrefix(prefixLower)
        }

        let sorted = matching.sorted { lhs, rhs in
            modificationDate(for: lhs, fileManager: fileManager) >
                modificationDate(for: rhs, fileManager: fileManager)
        }

        guard sorted.count > keepCount else { return [] }
        return Array(sorted.dropFirst(keepCount))
    }

    private static func modificationDate(for url: URL, fileManager: FileManager) -> Date {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            return values.contentModificationDate ?? values.creationDate ?? .distantPast
        }
        if let attrs = try? fileManager.attributesOfItem(atPath: url.path),
           let modified = attrs[.modificationDate] as? Date {
            return modified
        }
        return .distantPast
    }
}
