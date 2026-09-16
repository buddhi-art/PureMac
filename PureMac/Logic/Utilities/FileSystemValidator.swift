import Foundation

struct FileSystemValidator {
    static let shared = FileSystemValidator()
    private let fileManager = FileManager.default

    func isSafeToDelete(resolvedPath: String) -> Bool {
        if ProviderPaths.isProviderOwned(resolvedPath) {
            Logger.shared.log("Refusing to delete cloud provider state: \(resolvedPath)", level: .warning)
            return false
        }

        let home = fileManager.homeDirectoryForCurrentUser.path
        let allowedRoots = [
            "\(home)/Library/Caches",
            "\(home)/Library/Logs",
            "\(home)/Library/Saved Application State",
            "\(home)/Library/HTTPStorages",
            "\(home)/Library/WebKit",
            "\(home)/Library/Containers",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Application Support",
            "\(home)/Library/Preferences",
            "\(home)/Library/LaunchAgents",
            "\(home)/Library/Mail Downloads",
            "\(home)/Library/Developer/Xcode/DerivedData",
            "\(home)/Library/Developer/Xcode/Archives",
            "\(home)/Library/Developer/CoreSimulator/Caches",
            "\(home)/Library/Developer/Xcode/iOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/watchOS DeviceSupport",
            "\(home)/Library/Developer/Xcode/tvOS DeviceSupport",
            "\(home)/Library/Developer/XCTestDevices",
            "\(home)/Library/Developer/Xcode/UserData/Previews",
            "\(home)/Library/org.swift.swiftpm",
            "\(home)/Library/pnpm/store",
            "\(home)/.Trash",
            "\(home)/.npm",
            "\(home)/.pnpm-store",
            "\(home)/.cache",
            "\(home)/.local/share/pnpm/store",
            "\(home)/Library/Containers/com.docker.docker",
            "\(home)/.docker/cli-plugins/.cache",
            "\(home)/.docker/buildx/cache",
            "\(home)/.orbstack/log",
            "/Library/Caches",
            "/Library/Logs",
            "/opt/homebrew/Library/Caches",
            "/usr/local/Homebrew/Library/Caches",
            "/private/var/log",
            "/private/var/tmp",
            "/private/tmp",
            "/var/log",
            "/var/tmp",
            "/tmp"
        ]
        
        let normalized = (resolvedPath as NSString).standardizingPath
        return allowedRoots.contains { root in
            if normalized == root { return true }
            let rootWithSeparator = root.hasSuffix("/") ? root : root + "/"
            return normalized.hasPrefix(rootWithSeparator)
        }
    }

    func isExplicitSingleFileDeletable(resolvedPath: String) -> Bool {
        let home = fileManager.homeDirectoryForCurrentUser.path
        let perFileRoots = [
            "\(home)/Downloads/",
            "\(home)/Documents/",
            "\(home)/Desktop/"
        ]
        let normalized = (resolvedPath as NSString).standardizingPath
        return perFileRoots.contains { normalized.hasPrefix($0) }
    }

    func hasUnexpectedSymlink(in path: String) -> Bool {
        var url = URL(fileURLWithPath: path).standardizedFileURL
        while url.path != "/" {
            let current = url.path
            let type = (try? fileManager.attributesOfItem(atPath: current)[.type]) as? FileAttributeType
            if type == .typeSymbolicLink, current != "/tmp", current != "/var" {
                return true
            }
            let parent = url.deletingLastPathComponent()
            if parent.path == current { break }
            url = parent
        }
        return false
    }

    func isInside(_ path: String, root: String) -> Bool {
        let normalizedRoot = (root as NSString).standardizingPath
        if path == normalizedRoot { return true }
        let rootWithSeparator = normalizedRoot.hasSuffix("/") ? normalizedRoot : normalizedRoot + "/"
        return path.hasPrefix(rootWithSeparator)
    }
}
