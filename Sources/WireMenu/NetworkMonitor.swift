import Foundation
import Network

final class NetworkMonitor {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "WireMenu.NetworkMonitor")

    var onChange: ((ConnectionSnapshot) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let snapshot = ConnectionSnapshot(path: path)
            DispatchQueue.main.async {
                self?.onChange?(snapshot)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
