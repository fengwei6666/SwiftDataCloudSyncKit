import Foundation
import Network
import Combine

public final class NetworkReachabilityMonitor: ObservableObject {

    public static let shared = NetworkReachabilityMonitor()

    @Published public private(set) var isConnected: Bool = true
    @Published public private(set) var connectionType: NWInterface.InterfaceType?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkReachabilityMonitor")

    public init(autoStart: Bool = true) {
        if autoStart {
            startMonitoring()
        }
    }

    public func startMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                self?.isConnected = path.status == .satisfied
                self?.connectionType = path.availableInterfaces.first?.type
            }
        }
        monitor.start(queue: queue)
    }

    public func stopMonitoring() {
        monitor.cancel()
    }
}
