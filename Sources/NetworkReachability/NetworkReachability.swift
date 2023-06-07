//import SystemConfiguration
import Network
import Foundation

public extension Notification.Name {
	static let reachabilityChanged = Notification.Name("reachabilityChanged")
}

public class NetworkReachability {
	
	public typealias NetworkReachable = (NetworkReachability) -> ()
	public typealias NetworkUnreachable = (NetworkReachability) -> ()
	
	public enum Connection: CustomStringConvertible {
		case unavailable, wifi, cellular, wired
		public var description: String {
			switch self {
				case .cellular: return "Cellular"
				case .wifi: return "WiFi"
				case .wired: return "Wired"
				case .unavailable: return "No Connection"
			}
		}
	}
	
	public var notifierRunning = false
	
	public var whenReachable: NetworkReachable?
	public var whenUnreachable: NetworkUnreachable?
	
	/// Set to `false` to force Reachability.connection to .none when on cellular connection (default value `true`)
	public var allowsCellularConnection: Bool = true
	
	// The notification center on which "reachability changed" events are being posted
	public var notificationCenter: NotificationCenter = NotificationCenter.default
	
	public var connection: Connection {
		if let path = path {
			if path.status == .satisfied {
				let type = path.interfaceType
				switch type {
					case .cellular:
						return .cellular
					case .wifi:
						return .wifi
					case .wiredEthernet:
						return .wired
					case .other:
						return .wired
					default:
						return .unavailable
				}
			}
		}
		return .unavailable
	}
	
	public var path: NWPath? {
		didSet {
			guard path != oldValue else { return }
			notifyReachabilityChanged()
		}
	}
	
	public var monitor: NWPathMonitor
	
	fileprivate var isRunningOnDevice: Bool = {
#if targetEnvironment(simulator)
		return false
#else
		return true
#endif
	}()
	
	fileprivate let notificationQueue: DispatchQueue?
	fileprivate let reachabilitySerialQueue: DispatchQueue
	
	required public init(queueQoS: DispatchQoS = .default,
											 targetQueue: DispatchQueue? = nil,
											 notificationQueue: DispatchQueue? = .main) throws {
		self.monitor = NWPathMonitor()
		self.reachabilitySerialQueue = DispatchQueue(label: "com.llsc12.NetworkReachability", qos: queueQoS, target: targetQueue)
		self.notificationQueue = notificationQueue
		self.path = nil
	}
	
	deinit {
		stopNotifier()
	}
}

public extension NetworkReachability {
	
	// MARK: - *** Notifier methods ***
	func startNotifier(queue: DispatchQueue = .main) throws {
		guard !notifierRunning else { return }
		
		self.monitor.start(queue: queue)
		
		// Perform an initial check
		try setReachabilityFlags()
		
		notifierRunning = true
	}
	
	func stopNotifier() {
		defer { notifierRunning = false }
		
		self.monitor.cancel()
	}
	
	// MARK: - *** Connection test methods ***
	@available(*, deprecated, message: "Please use `connection != .none`")
	var isReachable: Bool {
		return connection != .unavailable
	}
	
	@available(*, deprecated, message: "Please use `connection == .cellular`")
	var isReachableViaWWAN: Bool {
		// Check we're not on the simulator, we're REACHABLE and check we're on WWAN
		return connection == .cellular
	}
	
	@available(*, deprecated, message: "Please use `connection == .wifi`")
	var isReachableViaWiFi: Bool {
		return connection == .wifi
	}
	
	var description: String {
		return self.monitor.currentPath.debugDescription
	}
}

fileprivate extension NetworkReachability {
	
	func setReachabilityFlags() throws {
		self.path = monitor.currentPath
	}
	
	
	func notifyReachabilityChanged() {
		let notify = { [weak self] in
			guard let self = self else { return }
			self.connection != .unavailable ? self.whenReachable?(self) : self.whenUnreachable?(self)
			self.notificationCenter.post(name: .reachabilityChanged, object: self)
		}
		
		// notify on the configured `notificationQueue`, or the caller's (i.e. `reachabilitySerialQueue`)
		notificationQueue?.async(execute: notify) ?? notify()
	}
}

extension NWPath {
	public var interfaceType: NWInterface.InterfaceType {
		var type: NWInterface.InterfaceType = .other
		if self.usesInterfaceType(.cellular) { type = .cellular }
		else if self.usesInterfaceType(.loopback) { type = .loopback }
		else if self.usesInterfaceType(.other) { type = .other }
		else if self.usesInterfaceType(.wifi) { type = .wifi }
		else if self.usesInterfaceType(.wiredEthernet) { type = .wiredEthernet }
		return type
	}
}
