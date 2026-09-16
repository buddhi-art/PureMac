import Foundation

struct XcodeJunkScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default

        let xcodePaths = [
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/Archives",
            "\(home)/Library/Developer/CoreSimulator/Caches",
            "\(home)/Library/Caches/com.apple.dt.Xcode",
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/watchOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/tvOS DeviceSupport",
            "\(home)/Library/Developer/XCTestDevices",
            "\(home)/Library/Developer/Xcode/UserData/Previews",
            "\(home)/Library/Caches/org.swift.swiftpm",
            "\(home)/Library/org.swift.swiftpm",
        ]

        for path in xcodePaths {
            if fileManager.fileExists(atPath: path) {
                let size = await ScannerUtils.shared.directorySize(path: path)
                if size > 0 {
                    onPath(path)
                    items.append(CleanableItem(
                        name: URL(fileURLWithPath: path).lastPathComponent,
                        path: path,
                        size: size,
                        category: .xcodeJunk,
                        isSelected: true,
                        lastModified: nil
                    ))
                }
            }
        }

        items.append(contentsOf: scanSimulatorRuntimes(onPath: onPath))

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .xcodeJunk, items: items, totalSize: totalSize)
    }
    
    private func scanSimulatorRuntimes(onPath: @escaping @Sendable (String) -> Void) -> [CleanableItem] {
        guard SimulatorRuntimeSupport.isXcrunAvailable() else {
            Logger.shared.log(SimulatorRuntimeSupport.missingXcrunMessage, level: .info)
            return []
        }
        guard let runtimes = listSimulatorRuntimes() else { return [] }
        let items = SimulatorRuntimeSupport.makeCleanableItems(from: runtimes)
        for item in items {
            onPath(item.name)
        }
        return items
    }
    
    private func listSimulatorRuntimes() -> [SimulatorRuntimeSupport.RuntimeInfo]? {
        let result = SimulatorRuntimeSupport.runXcrun(["simctl", "runtime", "list", "-j"])
        guard result.status == 0, !result.stdout.isEmpty else {
            if !result.stderr.isEmpty {
                Logger.shared.log("simctl runtime list failed: \(result.stderr)", level: .warning)
            }
            return nil
        }
        guard let runtimes = SimulatorRuntimeSupport.parseRuntimeListJSON(result.stdout) else {
            Logger.shared.log("simctl runtime list: could not parse JSON", level: .warning)
            return nil
        }
        return runtimes
    }
}

struct BrewCacheScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default

        var brewCachePaths = [
            "\(home)/Library/Caches/Homebrew",
        ]

        let knownBrewRoots = [
            "\(home)/Library/Caches/Homebrew",
            "/opt/homebrew/Library/Caches",
            "/usr/local/Homebrew/Library/Caches",
            "/Library/Caches/Homebrew",
        ]

        let brewBinPaths = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
        var detectedCustomCache = false
        for brewBin in brewBinPaths {
            guard fileManager.fileExists(atPath: brewBin) else { continue }
            var sanitizedEnv = ProcessInfo.processInfo.environment
            for key in Array(sanitizedEnv.keys) where key.hasPrefix("HOMEBREW_") {
                sanitizedEnv.removeValue(forKey: key)
            }
            do {
                let result = try await BrewProcessRunner.run(
                    executableURL: URL(fileURLWithPath: brewBin),
                    arguments: ["--cache"],
                    timeout: 10,
                    environment: sanitizedEnv
                )
                if result.status == 0,
                   let output = String(data: result.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !output.isEmpty {
                    let normalized = ScannerUtils.shared.normalizePath(output)
                    let isKnown = knownBrewRoots.contains { root in
                        normalized == root || normalized.hasPrefix(root + "/")
                    }
                    guard isKnown else {
                        Logger.shared.log("Refusing suspicious brew cache path: \(output)", level: .warning)
                        break
                    }
                    if !brewCachePaths.map({ ScannerUtils.shared.normalizePath($0) }).contains(normalized) {
                        brewCachePaths.append(output)
                    }
                    detectedCustomCache = true
                }
            } catch is CancellationError {
                return CategoryResult(category: .brewCache, items: items, totalSize: 0)
            } catch {
                Logger.shared.log("Failed to run \(brewBin) --cache: \(error.localizedDescription)", level: .warning)
            }
            break
        }

        if !detectedCustomCache {
            Logger.shared.log("Homebrew not found at standard paths; scanning default cache location only", level: .info)
        }

        for path in brewCachePaths {
            if fileManager.fileExists(atPath: path) {
                let size = await ScannerUtils.shared.directorySize(path: path)
                if size > 0 {
                    onPath(path)
                    items.append(CleanableItem(
                        name: URL(fileURLWithPath: path).lastPathComponent,
                        path: path,
                        size: size,
                        category: .brewCache,
                        isSelected: true,
                        lastModified: nil
                    ))
                }
            }
        }

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .brewCache, items: items, totalSize: totalSize)
    }
}

struct NodeCacheScanner: CategoryScannerProtocol {
    enum NodeCacheManager: String, CaseIterable {
        case npm
        case yarn
        case pnpm
    }

    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        struct ManagerCache {
            let name: String
            let manager: NodeCacheManager
            let detectionCommand: (cli: String, args: [String])?
        }

        let managers: [ManagerCache] = [
            ManagerCache(
                name: String(localized: "npm cache"),
                manager: .npm,
                detectionCommand: (cli: "npm", args: ["config", "get", "cache"])
            ),
            ManagerCache(
                name: String(localized: "yarn classic cache"),
                manager: .yarn,
                detectionCommand: (cli: "yarn", args: ["cache", "dir"])
            ),
            ManagerCache(
                name: String(localized: "pnpm content-addressable store"),
                manager: .pnpm,
                detectionCommand: (cli: "pnpm", args: ["store", "path"])
            ),
        ]

        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default

        let cliSearchPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.volta/bin",
            "\(home)/.nvm/versions/node",
        ]

        for manager in managers {
            if Task.isCancelled { break }
            var paths = approvedNodeCacheRoots(for: manager.manager, home: home)
                .compactMap {
                    validatedNodeCachePath($0, manager: manager.manager, home: home)
                }

            if let cmd = manager.detectionCommand,
               let cliPath = locateExecutable(named: cmd.cli, searchPaths: cliSearchPaths),
               let detected = await runCommandReadingStdout(executable: cliPath, args: cmd.args) {
                if let validated = validatedNodeCachePath(
                    detected,
                    manager: manager.manager,
                    home: home
                ) {
                    if !paths.contains(validated) {
                        paths.append(validated)
                    }
                } else {
                    Logger.shared.log(
                        "Refusing untrusted \(manager.manager.rawValue) cache path",
                        level: .warning
                    )
                }
            }

            if Task.isCancelled { break }
            paths = prunedNodeCachePaths(paths)

            for path in paths {
                guard fileManager.fileExists(atPath: path) else { continue }
                let size = await ScannerUtils.shared.directorySize(path: path)
                guard size > 0 else { continue }
                onPath(path)
                items.append(CleanableItem(
                    name: manager.name,
                    path: path,
                    size: size,
                    category: .nodeCache,
                    isSelected: true,
                    lastModified: nil
                ))
            }
        }

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .nodeCache, items: items, totalSize: totalSize)
    }

    private func approvedNodeCacheRoots(for manager: NodeCacheManager, home: String) -> [String] {
        let normalizedHome = ScannerUtils.shared.normalizePath(home)
        switch manager {
        case .npm:
            return [
                "\(normalizedHome)/.npm",
                "\(normalizedHome)/Library/Caches/npm",
            ]
        case .yarn:
            return [
                "\(normalizedHome)/Library/Caches/Yarn",
                "\(normalizedHome)/.cache/yarn",
            ]
        case .pnpm:
            return [
                "\(normalizedHome)/Library/pnpm/store",
                "\(normalizedHome)/.local/share/pnpm/store",
                "\(normalizedHome)/.pnpm-store",
                "\(normalizedHome)/.cache/pnpm",
            ]
        }
    }

    private func validatedNodeCachePath(_ candidate: String, manager: NodeCacheManager, home: String) -> String? {
        let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.hasPrefix("/"),
              !trimmed.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }

        let standardized = ScannerUtils.shared.normalizePath(trimmed)
        let resolved = URL(fileURLWithPath: standardized, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL.path
        let approvedRoots = approvedNodeCacheRoots(for: manager, home: home)
            .map { ScannerUtils.shared.normalizePath($0) }

        guard approvedRoots.contains(where: { root in
            resolved == root || resolved.hasPrefix(root + "/")
        }) else { return nil }

        return resolved
    }

    private func prunedNodeCachePaths(_ paths: [String]) -> [String] {
        var kept: [String] = []
        for path in paths.sorted(by: {
            if $0.count != $1.count { return $0.count < $1.count }
            return $0.localizedStandardCompare($1) == .orderedAscending
        }) {
            if kept.contains(where: { path == $0 || path.hasPrefix($0 + "/") }) {
                continue
            }
            kept.append(path)
        }
        return kept
    }

    private func locateExecutable(named name: String, searchPaths: [String]) -> String? {
        let fileManager = FileManager.default
        for dir in searchPaths {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: candidate) {
                return candidate
            }
            if dir.hasSuffix("/.nvm/versions/node"),
               let versions = try? fileManager.contentsOfDirectory(atPath: dir) {
                for v in versions {
                    let nested = (dir as NSString).appendingPathComponent("\(v)/bin/\(name)")
                    if fileManager.isExecutableFile(atPath: nested) {
                        return nested
                    }
                }
            }
        }
        return nil
    }

    private func runCommandReadingStdout(executable: String, args: [String]) async -> String? {
        do {
            let result = try await BrewProcessRunner.run(
                executableURL: URL(fileURLWithPath: executable),
                arguments: args,
                timeout: 10
            )
            guard result.status == 0 else { return nil }
            return String(data: result.stdout, encoding: .utf8)
        } catch is CancellationError {
            return nil
        } catch {
            Logger.shared.log("\(executable) \(args.joined(separator: " ")) failed: \(error.localizedDescription)", level: .warning)
            return nil
        }
    }
}

struct DockerCacheScanner: CategoryScannerProtocol {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult {
        var items: [CleanableItem] = []
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let fileManager = FileManager.default

        let dockerDataDirs = [
            "\(home)/Library/Containers/com.docker.docker/Data/cache",
            "\(home)/Library/Containers/com.docker.docker/Data/log",
            "\(home)/Library/Containers/com.docker.docker/Data/tmp",
            "\(home)/Library/Group Containers/group.com.docker/Caches",
            "\(home)/.docker/cli-plugins/.cache",
            "\(home)/.docker/buildx/cache",
            "\(home)/.orbstack/log",
            "\(home)/Library/Caches/dev.kdrag0n.MacVirt",
            "\(home)/Library/Logs/OrbStack",
        ]

        for path in dockerDataDirs {
            guard fileManager.fileExists(atPath: path) else { continue }
            let size = await ScannerUtils.shared.directorySize(path: path)
            guard size > 0 else { continue }
            onPath(path)
            items.append(CleanableItem(
                name: URL(fileURLWithPath: path).lastPathComponent,
                path: path,
                size: size,
                category: .dockerCache,
                isSelected: true,
                lastModified: nil
            ))
        }

        let dockerBinPaths = ["/usr/local/bin/docker", "/opt/homebrew/bin/docker"]
        for dockerBin in dockerBinPaths where fileManager.fileExists(atPath: dockerBin) {
            if Task.isCancelled { break }
            if let reclaimable = await reclaimableDockerSpace(dockerBin: dockerBin), reclaimable > 0 {
                items.append(CleanableItem(
                    name: String(localized: "Docker prune (stopped containers, dangling images, build cache)"),
                    path: "",
                    size: reclaimable,
                    category: .dockerCache,
                    isSelected: false,
                    lastModified: nil,
                    actionTarget: .dockerSystem
                ))
            }
            break
        }

        let totalSize = items.reduce(0) { $0 + $1.size }
        return CategoryResult(category: .dockerCache, items: items, totalSize: totalSize)
    }

    private func reclaimableDockerSpace(dockerBin: String) async -> Int64? {
        let result: BrewProcessOutput
        do {
            result = try await BrewProcessRunner.run(
                executableURL: URL(fileURLWithPath: dockerBin),
                arguments: ["system", "df", "--format", "{{.Reclaimable}}"],
                timeout: 10
            )
        } catch is CancellationError {
            return nil
        } catch {
            Logger.shared.log("docker system df failed: \(error.localizedDescription)", level: .warning)
            return nil
        }
        guard result.status == 0,
              let output = String(data: result.stdout, encoding: .utf8)
        else { return nil }
        
        var total: Int64 = 0
        for line in output.split(separator: "\n") {
            let raw = line.split(separator: " ").first.map(String.init) ?? ""
            if let bytes = parseHumanBytes(raw) {
                total += bytes
            }
        }
        return total
    }

    private func parseHumanBytes(_ s: String) -> Int64? {
        let trimmed = s.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let units: [(String, Double)] = [
            ("TB", 1_000_000_000_000),
            ("GB", 1_000_000_000),
            ("MB", 1_000_000),
            ("kB", 1_000),
            ("KB", 1_000),
            ("B", 1),
        ]
        for (suffix, multiplier) in units {
            if trimmed.hasSuffix(suffix) {
                let numberPart = String(trimmed.dropLast(suffix.count))
                if let value = Double(numberPart) {
                    return Int64(value * multiplier)
                }
            }
        }
        return nil
    }
}
