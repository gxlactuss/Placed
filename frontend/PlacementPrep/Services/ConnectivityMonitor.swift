import Foundation
import Network
import Observation

/// Whether the device has a usable network path. Quizzes and company lists are bundled and work
/// offline; interviews, resume review, sign-in and progress sync need the network.
@MainActor
@Observable
final class ConnectivityMonitor {

    /// Optimistically true until the first path arrives, so launch never flashes the offline banner.
    private(set) var isOnline: Bool

    @ObservationIgnored private let monitor = NWPathMonitor()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.placementprep.connectivity", qos: .utility)
    @ObservationIgnored private var isStarted = false

    init(startMonitoring: Bool = true, isOnline: Bool = true) {
        self.isOnline = isOnline
        if startMonitoring { start() }
    }

    deinit {
        monitor.cancel()
    }

    /// Starts watching the network path. Safe to call more than once; only the first call starts.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor [weak self] in
                guard let self, self.isOnline != online else { return }
                self.isOnline = online
            }
        }
        monitor.start(queue: queue)
    }

    static func preview(isOnline: Bool = true) -> ConnectivityMonitor {
        ConnectivityMonitor(startMonitoring: false, isOnline: isOnline)
    }
}
