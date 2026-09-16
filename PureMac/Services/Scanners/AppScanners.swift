import Foundation

struct AiAppsScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let targets = [
            (name: String(localized: "Ollama Logs"), path: "\(home)/.ollama/logs", isSelected: true, minSize: Int64(1024)),
            (name: String(localized: "Ollama Cache"), path: "\(home)/Library/Caches/ollama", isSelected: true, minSize: Int64(1024)),
            (name: String(localized: "Ollama Electron Cache"), path: "\(home)/Library/Caches/com.electron.ollama", isSelected: true, minSize: Int64(1024)),
            (name: String(localized: "Ollama WebKit Data"), path: "\(home)/Library/WebKit/com.electron.ollama", isSelected: true, minSize: Int64(1024)),
            (name: String(localized: "Ollama Saved State"), path: "\(home)/Library/Saved Application State/com.electron.ollama.savedState", isSelected: true, minSize: Int64(1024)),
            (name: String(localized: "Ollama CLI Prompt History (Optional)"), path: "\(home)/.ollama/history", isSelected: false, minSize: Int64(0)),
            (name: String(localized: "LM Studio Server Logs"), path: "\(home)/.lmstudio/server-logs", isSelected: true, minSize: Int64(1024)),
            (name: String(localized: "LM Studio Conversations (Optional)"), path: "\(home)/.lmstudio/conversations", isSelected: false, minSize: Int64(0)),
        ]

        var items: [CleanableItem] = []
        for target in targets {
            if let item = await makeCleanupItem(name: target.name, path: target.path, category: .aiApps, isSelected: target.isSelected, minimumSize: target.minSize, onPath: onPath) {
                items.append(item)
            }
        }

        let uniqueItems = await ScannerUtils.shared.deduplicatedItems(items)
        let totalSize = uniqueItems.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .aiApps, items: uniqueItems.sorted { $0.size > $1.size }, totalSize: totalSize)
    }

    private func makeCleanupItem(name: String, path: String, category: CleaningCategory, isSelected: Bool, minimumSize: Int64, onPath: @Sendable (String) -> Void) async -> CleanableItem? {
        onPath(path)
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
              fileManager.isReadableFile(atPath: path) else { return nil }

        if isDirectory.boolValue {
            let size = await ScannerUtils.shared.directorySize(path: path)
            guard size > minimumSize else { return nil }
            return CleanableItem(name: name, path: path, size: size, category: category, isSelected: isSelected, lastModified: fileModDate(path: path))
        }

        guard let attrs = try? fileManager.attributesOfItem(atPath: path),
              let size = attrs[.size] as? Int64,
              size > minimumSize else { return nil }

        return CleanableItem(name: name, path: path, size: size, category: category, isSelected: isSelected, lastModified: attrs[.modificationDate] as? Date)
    }

    private func fileModDate(path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}

struct MailAttachmentsScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        let mailPaths = [
            "\(home)/Library/Mail Downloads",
            "\(home)/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        ]

        for path in mailPaths {
            let scanned = await ScannerUtils.shared.scanDirectory(path: path, category: .mailAttachments, recursive: true, maxDepth: 3, isSelected: true, excluding: [], onPath: onPath)
            items.append(contentsOf: scanned)
        }

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .mailAttachments, items: items, totalSize: totalSize)
    }
}

struct UniversalBinariesCategoryScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let findings = UniversalBinaryScanner().scan()
        for finding in findings {
            onPath(finding.appPath)
            items.append(CleanableItem(
                name: "\(finding.appName) (\(finding.removableArchs.joined(separator: ", ")))",
                path: finding.appPath,
                size: finding.reclaimableBytes,
                category: .universalBinaries,
                isSelected: false,
                lastModified: fileModDate(path: finding.appPath)
            ))
        }

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .universalBinaries, items: items, totalSize: totalSize)
    }

    private func fileModDate(path: String) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }
}

struct LanguageFilesCategoryScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        let scanner = LanguageFilesScanner()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let findings = scanner.scan(applicationDirs: ["/Applications", "\(home)/Applications"])
        let items = scanner.flatten(findings).map { entry in
            onPath(entry.path)
            return CleanableItem(
                name: entry.name,
                path: entry.path,
                size: entry.size,
                category: .languageFiles,
                isSelected: false,
                lastModified: nil
            )
        }

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .languageFiles, items: items, totalSize: totalSize)
    }
}
