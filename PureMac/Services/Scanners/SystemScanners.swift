import Foundation

struct SystemJunkScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let systemPaths = [
            "/Library/Caches",
            "/Library/Logs",
            "/private/var/log",
            "\(home)/Library/Logs",
            "/tmp",
            "/private/var/tmp",
        ]

        for path in systemPaths {
            let scanned = await ScannerUtils.shared.scanDirectory(path: path, category: .systemJunk, recursive: true, maxDepth: 3, onPath: onPath)
            items.append(contentsOf: scanned)
        }

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .systemJunk, items: items, totalSize: totalSize)
    }
}

struct UserCacheScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default
        let utils = ScannerUtils.shared

        let excludedRootPaths = Set(([
            "\(home)/Library/Caches/Homebrew",
            "\(home)/Library/Caches/com.electron.ollama",
            "\(home)/Library/Caches/ollama",
            "\(home)/Library/Caches/npm",
            "\(home)/Library/Caches/Yarn",
            "\(home)/Library/Caches/dev.kdrag0n.MacVirt",
        ] + ProviderPaths.deniedRoots).map { await utils.normalizePath($0) })

        let cachePath = "\(home)/Library/Caches"
        let scanned = await utils.scanDirectory(
            path: cachePath,
            category: .userCache,
            recursive: false,
            maxDepth: 1,
            excluding: excludedRootPaths,
            onPath: onPath
        )
        items.append(contentsOf: scanned)

        let devCaches = [
            "\(home)/.cache/pip",
            "\(home)/Library/Caches/pip",
        ]

        for path in devCaches {
            if let item = await utils.makeCleanupItem(
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                category: .userCache,
                onPath: onPath
            ) {
                items.append(item)
            }
        }

        let containerRoots = [
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
        ]
        for root in containerRoots {
            guard let containers = try? fileManager.contentsOfDirectory(atPath: root) else { continue }
            let cacheSubpath = root.hasSuffix("Group Containers")
                ? "Library/Caches"
                : "Data/Library/Caches"
            for container in containers {
                let cachePath = (root as NSString)
                    .appendingPathComponent(container)
                    .appending("/" + cacheSubpath)
                let resolvedCachePath = URL(fileURLWithPath: cachePath).resolvingSymlinksInPath().path
                guard await utils.normalizePath(resolvedCachePath) == utils.normalizePath(cachePath) else { continue }
                if let item = await utils.makeCleanupItem(
                    name: "\(container) (sandbox cache)",
                    path: cachePath,
                    category: .userCache,
                    minimumSize: 1024 * 1024,
                    onPath: onPath
                ) {
                    items.append(item)
                }
            }
        }

        let httpStorages = await utils.scanDirectory(
            path: "\(home)/Library/HTTPStorages",
            category: .userCache,
            recursive: false,
            maxDepth: 1,
            isSelected: false,
            onPath: onPath
        )
        items.append(contentsOf: httpStorages)

        let uniqueItems = await utils.deduplicatedItems(items)
        let totalSize = uniqueItems.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .userCache, items: uniqueItems, totalSize: totalSize)
    }
}

struct TrashScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let trashPath = "\(home)/.Trash"
        let scanned = await ScannerUtils.shared.scanDirectory(path: trashPath, category: .trashBins, recursive: false, maxDepth: 1, onPath: onPath)
        items.append(contentsOf: scanned)
        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .trashBins, items: items, totalSize: totalSize)
    }
}

struct LargeFilesScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default
        let defaults = UserDefaults.standard
        let thresholdMB = defaults.object(forKey: "settings.cleaning.largeFileThreshold") as? Int ?? 100
        let oldFileMonths = defaults.object(forKey: "settings.cleaning.oldFileMonths") as? Int ?? 12
        let minSize = Int64(max(1, thresholdMB)) * 1024 * 1024
        let oldCutoff = Calendar.current.date(byAdding: .month, value: -max(1, oldFileMonths), to: Date())
            ?? Date.distantPast

        let excludedFolders = (defaults.stringArray(forKey: "settings.cleaning.largeFileExcludedFolders") ?? [])
            .map { (path: String) -> String in (path as NSString).standardizingPath }
            .filter { !$0.isEmpty }

        let skipHidden = defaults.object(forKey: "settings.cleaning.skipHiddenFiles") as? Bool ?? true
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if skipHidden { enumerationOptions.insert(.skipsHiddenFiles) }

        func isExcluded(_ path: String) -> Bool {
            let normalized = (path as NSString).standardizingPath
            return excludedFolders.contains { normalized == $0 || normalized.hasPrefix($0 + "/") }
        }

        let searchPaths = [
            "\(home)/Downloads",
            "\(home)/Documents",
            "\(home)/Desktop",
        ]

        for basePath in searchPaths {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: basePath),
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: enumerationOptions
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if !excludedFolders.isEmpty, isExcluded(fileURL.path) {
                    enumerator.skipDescendants()
                    continue
                }
                onPath(fileURL.path)
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                      let isFile = resourceValues.isRegularFile, isFile,
                      let fileSize = resourceValues.fileSize
                else { continue }

                let size = Int64(fileSize)
                let modDate = resourceValues.contentModificationDate

                if size > minSize || (modDate != nil && modDate! < oldCutoff && size > 10 * 1024 * 1024) {
                    items.append(CleanableItem(
                        name: fileURL.lastPathComponent,
                        path: fileURL.path,
                        size: size,
                        category: .largeFiles,
                        isSelected: false,
                        lastModified: modDate
                    ))
                }
            }
        }

        items.sort { $0.size > $1.size }
        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .largeFiles, items: items, totalSize: totalSize)
    }
}

struct PurgeableSpaceScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        var totalSize: Int64 = 0

        let diskInfo = await ScannerUtils.shared.getDiskInfo()
        if diskInfo.purgeableSpace > 0 {
            items.append(CleanableItem(
                name: "APFS Purgeable Space",
                path: "",
                size: diskInfo.purgeableSpace,
                category: .purgeableSpace,
                isSelected: true,
                lastModified: nil,
                actionTarget: .purgeableSpace
            ))
            totalSize = diskInfo.purgeableSpace
        }

        let snapshots = await ScannerUtils.shared.getLocalSnapshots()
        for snapshot in snapshots {
            let snapshotSize = snapshot.size > 0 ? snapshot.size : 0
            if snapshotSize > 0 {
                items.append(CleanableItem(
                    name: "TM Snapshot: \(snapshot.name)",
                    path: snapshot.name,
                    size: snapshotSize,
                    category: .purgeableSpace,
                    isSelected: false,
                    lastModified: snapshot.date
                ))
            }
        }

        return CategoryResult(category: .purgeableSpace, items: items, totalSize: totalSize)
    }
}
struct LargeFilesScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default
        let defaults = UserDefaults.standard
        let thresholdMB = defaults.object(forKey: "settings.cleaning.largeFileThreshold") as? Int ?? 100
        let oldFileMonths = defaults.object(forKey: "settings.cleaning.oldFileMonths") as? Int ?? 12
        let minSize = Int64(max(1, thresholdMB)) * 1024 * 1024
        let oldCutoff = Calendar.current.date(byAdding: .month, value: -max(1, oldFileMonths), to: Date())
            ?? Date.distantPast

        let excludedFolders = (defaults.stringArray(forKey: "settings.cleaning.largeFileExcludedFolders") ?? [])
            .map { (path: String) -> String in (path as NSString).standardizingPath }
            .filter { !$0.isEmpty }

        let skipHidden = defaults.object(forKey: "settings.cleaning.skipHiddenFiles") as? Bool ?? true
        var enumerationOptions: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if skipHidden { enumerationOptions.insert(.skipsHiddenFiles) }

        func isExcluded(_ path: String) -> Bool {
            let normalized = (path as NSString).standardizingPath
            return excludedFolders.contains { normalized == $0 || normalized.hasPrefix($0 + "/") }
        }

        let searchPaths = [
            "\(home)/Downloads",
            "\(home)/Documents",
            "\(home)/Desktop",
        ]

        for basePath in searchPaths {
            guard let enumerator = fileManager.enumerator(
                at: URL(fileURLWithPath: basePath),
                includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey],
                options: enumerationOptions
            ) else { continue }

            for case let fileURL as URL in enumerator {
                if !excludedFolders.isEmpty, isExcluded(fileURL.path) {
                    enumerator.skipDescendants()
                    continue
                }
                onPath(fileURL.path)
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]),
                      let isFile = resourceValues.isRegularFile, isFile,
                      let fileSize = resourceValues.fileSize
                else { continue }

                let size = Int64(fileSize)
                let modDate = resourceValues.contentModificationDate

                if size > minSize || (modDate != nil && modDate! < oldCutoff && size > 10 * 1024 * 1024) {
                    items.append(CleanableItem(
                        name: fileURL.lastPathComponent,
                        path: fileURL.path,
                        size: size,
                        category: .largeFiles,
                        isSelected: false,
                        lastModified: modDate
                    ))
                }
            }
        }

        items.sort { $0.size > $1.size }
        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .largeFiles, items: items, totalSize: totalSize)
    }
}

struct PurgeableSpaceScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        var totalSize: Int64 = 0

        let diskInfo = await ScannerUtils.shared.getDiskInfo()
        if diskInfo.purgeableSpace > 0 {
            items.append(CleanableItem(
                name: "APFS Purgeable Space",
                path: "",
                size: diskInfo.purgeableSpace,
                category: .purgeableSpace,
                isSelected: true,
                lastModified: nil,
                actionTarget: .purgeableSpace
            ))
            totalSize = diskInfo.purgeableSpace
        }

        let snapshots = await ScannerUtils.shared.getLocalSnapshots()
        for snapshot in snapshots {
            let snapshotSize = snapshot.size > 0 ? snapshot.size : 0
            if snapshotSize > 0 {
                items.append(CleanableItem(
                    name: "TM Snapshot: \(snapshot.name)",
                    path: snapshot.name,
                    size: snapshotSize,
                    category: .purgeableSpace,
                    isSelected: false,
                    lastModified: snapshot.date
                ))
            }
        }

        return CategoryResult(category: .purgeableSpace, items: items, totalSize: totalSize)
    }
}
