import Foundation

actor ScanEngine {
    private let fileManager = FileManager.default

    /// Live path reporter for the dashboard's scanning ticker. Throttled so
    /// a directory with thousands of entries doesn't flood the main actor.
    private var onPath: (@Sendable (String) -> Void)?
    private var lastReport = Date.distantPast

    private let scanners: [CleaningCategory: CategoryScannerProtocol] = [
        .systemJunk: SystemJunkScanner(),
        .userCache: UserCacheScanner(),
        .aiApps: AiAppsScanner(),
        .mailAttachments: MailAttachmentsScanner(),
        .trashBins: TrashScanner(),
        .largeFiles: LargeFilesScanner(),
        .purgeableSpace: PurgeableSpaceScanner(),
        .xcodeJunk: XcodeJunkScanner(),
        .brewCache: BrewCacheScanner(),
        .nodeCache: NodeCacheScanner(),
        .dockerCache: DockerCacheScanner(),
        .universalBinaries: UniversalBinariesCategoryScanner(),
        .languageFiles: LanguageFilesCategoryScanner()
    ]

    /// `path` is an autoclosure so the String is only materialized after the
    /// throttle gate passes — a deep home-directory walk enumerates hundreds
    /// of thousands of entries and only ~12/sec are ever displayed.
    private func report(_ path: @autoclosure () -> String) {
        guard let onPath else { return }
        let now = Date()
        guard now.timeIntervalSince(lastReport) > 0.1 else { return }
        lastReport = now
        onPath(path())
    }

    // MARK: - Public API

    func scanCategory(
        _ category: CleaningCategory,
        onPath: (@Sendable (String) -> Void)? = nil
    ) async -> CategoryResult {
        self.onPath = onPath
        defer { self.onPath = nil }

        if category == .smartScan {
            return CategoryResult(category: category, items: [], totalSize: 0)
        }

        guard let scanner = scanners[category] else {
            return CategoryResult(category: category, items: [], totalSize: 0)
        }

        return await scanner.scan { [weak self] path in
            Task { [weak self] in
                await self?.report(path)
            }
        }
    }

    func getDiskInfo() -> ScannerUtils.DiskInfo {
        var info = ScannerUtils.DiskInfo()
        do {
            let attrs = try fileManager.attributesOfFileSystem(forPath: "/")
            if let total = attrs[.systemSize] as? Int64 {
                info.totalSpace = total
            }
            if let free = attrs[.systemFreeSize] as? Int64 {
                info.freeSpace = free
            }
            info.usedSpace = info.totalSpace - info.freeSpace

            let rootURL = URL(fileURLWithPath: "/")
            let values = try rootURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeAvailableCapacityKey
            ])
            if let importantCapacity = values.volumeAvailableCapacityForImportantUsage,
               let freeCapacity = values.volumeAvailableCapacity {
                let purgeable = importantCapacity - Int64(freeCapacity)
                if purgeable > 10 * 1024 * 1024 {
                    info.purgeableSpace = purgeable
                }
            }
        } catch {
            Logger.shared.log("Disk info unavailable: \(error.localizedDescription)", level: .warning)
        }
        return info
    }
}
