import Foundation

protocol CategoryScannerProtocol: Sendable {
    func scan(onPath: @escaping @Sendable (String) -> Void) async -> CategoryResult
}
