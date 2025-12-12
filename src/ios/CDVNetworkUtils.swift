import Foundation
import Network

/// Utility class for network connectivity detection
/// Mirrors the Android MusicLibraryService network detection implementation
@objc(CDVNetworkUtils)
class CDVNetworkUtils: NSObject {

    private static let TAG = "[CDVNetworkUtils]"

    /// Shared instance for network monitoring
    @objc static let shared = CDVNetworkUtils()

    private let monitor: NWPathMonitor
    private let monitorQueue = DispatchQueue(label: "com.kuackmedia.carplay.networkmonitor")
    private var isMonitoring = false

    /// Current network availability status
    @objc private(set) var isNetworkAvailable: Bool = true

    /// Callback for network status changes
    var onNetworkStatusChanged: ((Bool) -> Void)?

    private override init() {
        monitor = NWPathMonitor()
        super.init()
    }

    /// Start monitoring network changes
    @objc func startMonitoring() {
        guard !isMonitoring else {
            print("\(CDVNetworkUtils.TAG) Already monitoring network")
            return
        }

        print("\(CDVNetworkUtils.TAG) Starting network monitoring")
        isMonitoring = true

        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            let wasAvailable = self.isNetworkAvailable
            let isNowAvailable = path.status == .satisfied

            // Check for actual internet connectivity (not just local network)
            let hasInternet = path.usesInterfaceType(.wifi) ||
                              path.usesInterfaceType(.cellular) ||
                              path.usesInterfaceType(.wiredEthernet)

            self.isNetworkAvailable = isNowAvailable && hasInternet

            print("\(CDVNetworkUtils.TAG) Network status changed: \(wasAvailable) -> \(self.isNetworkAvailable)")
            print("\(CDVNetworkUtils.TAG) Path status: \(path.status), interfaces: wifi=\(path.usesInterfaceType(.wifi)) cellular=\(path.usesInterfaceType(.cellular)) ethernet=\(path.usesInterfaceType(.wiredEthernet))")

            if wasAvailable != self.isNetworkAvailable {
                DispatchQueue.main.async {
                    self.onNetworkStatusChanged?(self.isNetworkAvailable)
                }
            }
        }

        monitor.start(queue: monitorQueue)

        // Set initial state
        let currentPath = monitor.currentPath
        isNetworkAvailable = currentPath.status == .satisfied &&
                            (currentPath.usesInterfaceType(.wifi) ||
                             currentPath.usesInterfaceType(.cellular) ||
                             currentPath.usesInterfaceType(.wiredEthernet))
        print("\(CDVNetworkUtils.TAG) Initial network state: \(isNetworkAvailable)")
    }

    /// Stop monitoring network changes
    @objc func stopMonitoring() {
        guard isMonitoring else { return }

        print("\(CDVNetworkUtils.TAG) Stopping network monitoring")
        isMonitoring = false
        monitor.cancel()
    }

    /// Check current network availability (static convenience method)
    @objc static func checkNetworkAvailable() -> Bool {
        return shared.isNetworkAvailable
    }
}
