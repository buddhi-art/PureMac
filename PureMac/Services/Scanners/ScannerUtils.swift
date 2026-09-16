import Foundation

actor ScannerUtils {
    static let shared = ScannerUtils()
    private let fileManager = FileManager.default
    private let home = FileManager.default.homeDirectoryForCurrentUser.path

    func scanDirectory(
        path: String,
        category: CleaningCategory,
        recursive: Bool,
        maxDepth: Int,
        isSelected: Bool = true,
        excluding excludedPaths: Set<String> = [],
        onPath: @escaping @Sendable (String) -> Void
    ) async -> [CleanableItem] {
        var items: [CleanableItem] = []
        guard fileManager.fileExists(atPath: path),
              fileManager.isReadableFile(atPath: path) else { return [] }

        do {
            let contents = try fileManager.contentsOfDirectory(atPath: path)
            for item in contents {
                await Task.yield()
                if Task.isCancelled { break }
                let fullPath = (path as NSString).appendingPathComponent(item)
                onPath(fullPath)
                if excludedPaths.contains(normalizePath(fullPath)) {
                    continue
                }

                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

                if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                   let fileType = attrs[.type] as? FileAttributeType,
                   fileType == .typeSymbolicLink {
                    continue
                }

                if FileProtection.isProtectedFromDeletion(path: fullPath) {
                    continue
                }

                if isDir.boolValue {
                    let size = await directorySize(path: fullPath)
                    if size > 1024 {
                        items.append(CleanableItem(
                            name: item,
                            path: fullPath,
                            size: size,
                            category: category,
                            isSelected: isSelected,
                            lastModified: fileModDate(path: fullPath)
                        ))
                    }
                } else {
                    if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int64, size > 1024 {
                        items.append(CleanableItem(
                            name: item,
                            path: fullPath,
                            size: size,
                            category: category,
                            isSelected: isSelected,
                            lastModified: attrs[.modificationDate] as? Date
                        ))
                    }
                }
            }
        } catch {
            Logger.shared.log("Cannot enumerate \(path): \(error.localizedDescription)", level: .warning)
        }
        return items
    }

    func makeCleanupItem(
        name: String,
        path: String,
        category: CleaningCategory,
        isSelected: Bool = true,
        minimumSize: Int64 = 1024,
        onPath: @escaping @Sendable (String) -> Void
    ) async -> CleanableItem? {
        onPath(path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              fileManager.isReadableFile(atPath: path) else { return nil }

        if isDirectory.boolValue {
            let size = await directorySize(path: path)
            guard size > minimumSize else { return nil }
            return CleanableItem(
                name: name,
                path: path,
                size: size,
                category: category,
                isSelected: isSelected,
                lastModified: fileModDate(path: path)
            )
        }

        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              size > minimumSize else { return nil }

        return CleanableItem(
            name: name,
            path: path,
            size: size,
            category: category,
            isSelected: isSelected,
            lastModified: attrs[.modificationDate] as? Date
        )
    }

    func deduplicatedItems(_ items: [CleanableItem]) -> [CleanableItem] {
        var seenPaths: Set<String> = []
        var uniqueItems: [CleanableItem] = []
        for item in items {
            let normalized = normalizePath(item.path)
            if seenPaths.insert(normalized).inserted {
                uniqueItems.append(item)
            }
        }
        return uniqueItems
    }

    func directorySize(path: String) async -> Int64 {
        var size: Int64 = 0
        guard let enumerator = fileManager.enumerator(atPath: path) else { return 0 }
        
        var count = 0
        while let file = enumerator.nextObject() as? String {
            count += 1
            if count % 100 == 0 { await Task.yield() }
            if Task.isCancelled { break }
            let fullPath = (path as NSString).appendingPathComponent(file)
            if let attrs = try? fileManager.attributesOfItem(atPath: fullPath),
               let type = attrs[.type] as? FileAttributeType,
               type != .typeSymbolicLink,
               let fileSize = attrs[.size] as? Int64 {
                size += fileSize
            }
        }
        return size
    }

    func normalizePath(_ path: String) -> String {
        return (path as NSString).standardizingPath
    }

    func fileModDate(path: String) -> Date? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: path) else { return nil }
        return attrs[.modificationDate] as? Date
    }

    struct CleanupTarget {
        let name: String
        let path: String
        let isSelected: Bool
        let minimumSize: Int64

        init(name: String, path: String, isSelected: Bool = true, minimumSize: Int64 = 1024) {
            self.name = name
            self.path = path
            self.isSelected = isSelected
            self.minimumSize = minimumSize
        }
    }
    
    struct DiskInfo {
        var totalSpace: Int64 = 0
        var freeSpace: Int64 = 0
        var usedSpace: Int64 = 0
        var purgeableSpace: Int64 = 0
    }

    func getDiskInfo() -> DiskInfo {
        var info = DiskInfo()
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

    struct SnapshotInfo {
        let name: String
        let size: Int64
        let date: Date?
    }

    func getLocalSnapshots() -> [SnapshotInfo] {
        var snapshots: [SnapshotInfo] = []

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/tmutil")
        task.arguments = ["listlocalsnapshots", "/"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return [] }

            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"

            for line in output.components(separatedBy: "\n") {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, trimmed.contains("TimeMachine") else { continue }

                var snapshotDate: Date?
                let parts = trimmed.components(separatedBy: ".")
                for part in parts {
                    if let date = dateFormatter.date(from: part) {
                        snapshotDate = date
                        break
                    }
                }

                let sizeBytes = getSnapshotSize(name: trimmed)
                if sizeBytes > 0 {
                    snapshots.append(SnapshotInfo(
                        name: trimmed,
                        size: sizeBytes,
                        date: snapshotDate
                    ))
                }
            }
        } catch {
            Logger.shared.log("tmutil listlocalsnapshots failed: \(error.localizedDescription)", level: .info)
        }

        return snapshots
    }

    func getSnapshotSize(name: String) -> Int64 {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = ["apfs", "listSnapshots", "/", "-plist"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                  let snapshots = plist["Snapshots"] as? [[String: Any]] else {
                Logger.shared.log("Could not parse APFS snapshot plist for \(name)", level: .info)
                return 0
            }

            for snapshot in snapshots {
                if let snapshotName = snapshot["SnapshotName"] as? String,
                   snapshotName == name,
                   let dataSize = snapshot["DataSize"] as? Int64 {
                    return dataSize
                }
            }
            Logger.shared.log("Snapshot \(name) not found in APFS listing", level: .info)
        } catch {
            Logger.shared.log("diskutil apfs listSnapshots failed: \(error.localizedDescription)", level: .warning)
        }
        return 0
    }
}
