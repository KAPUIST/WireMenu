import AppKit
import CoreLocation
import CoreWLAN
import Darwin
import ServiceManagement

struct TrafficSample: Identifiable {
    let id = UUID()
    let date: Date
    let download: Double
    let upload: Double
}

enum TrafficRate {
    static func calculate(previous: UInt64, current: UInt64, seconds: TimeInterval) -> Double {
        guard current >= previous, seconds > 0 else { return 0 }
        return Double(current - previous) / seconds
    }
}

struct WiFiNetworkItem: Identifiable {
    let network: CWNetwork
    let ssid: String
    let isKnown: Bool
    let isCurrent: Bool

    var id: String { network.bssid ?? ssid }
    var isSecure: Bool { !network.supportsSecurity(.none) }
    var signalStrength: Double { WiFiSignal.strength(for: network.rssiValue) }
}

enum WiFiSignal {
    static func strength(for rssi: Int) -> Double {
        guard rssi < 0 else { return 0 }
        switch rssi {
        // ponytail: calibrated against the native menu; Apple's exact thresholds aren't public.
        case (-65)...: return 1
        case (-75)...: return 2.0 / 3.0
        default: return 1.0 / 3.0
        }
    }
}

final class NetworkPanelModel: NSObject, ObservableObject, CLLocationManagerDelegate, CWEventDelegate {
    @Published private(set) var connection = ConnectionSnapshot(kind: .offline, interfaceName: nil)
    @Published private(set) var ethernetSpeed: String?
    @Published private(set) var ipAddress: String?
    @Published private(set) var wifiEnabled = false
    @Published private(set) var currentSSID: String?
    @Published private(set) var currentSignalStrength = 0.0
    var onSignalChange: (() -> Void)?
    @Published private(set) var knownNetworks: [WiFiNetworkItem] = []
    @Published private(set) var otherNetworks: [WiFiNetworkItem] = []
    @Published private(set) var trafficSamples: [TrafficSample] = []
    @Published private(set) var downloadBytesPerSecond = 0.0
    @Published private(set) var uploadBytesPerSecond = 0.0
    @Published private(set) var isScanning = false
    @Published private(set) var launchesAtLogin = false
    @Published var errorMessage: String?

    private let wifi = CWWiFiClient.shared().interface()
    private let locationManager = CLLocationManager()
    private let workQueue = DispatchQueue(label: "WireMenu.WiFi", qos: .userInitiated)
    private let metadataQueue = DispatchQueue(label: "WireMenu.Metadata", qos: .utility)
    private var trafficTimer: Timer?
    private var previousTraffic: (interface: String, received: UInt64, sent: UInt64, date: Date)?
    private var scanGeneration = 0
    private var metadataGeneration = 0

    override init() {
        super.init()
        locationManager.delegate = self
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        let client = CWWiFiClient.shared()
        client.delegate = self
        do { try client.startMonitoringEvent(with: .linkQualityDidChange) }
        catch { NSLog("WireMenu: Wi-Fi signal monitoring unavailable: %@", error.localizedDescription) }
    }

    deinit { trafficTimer?.invalidate() }

    func startTrafficMonitoring() {
        guard trafficTimer == nil else { return }
        previousTraffic = nil
        trafficSamples = []
        downloadBytesPerSecond = 0
        uploadBytesPerSecond = 0
        updateTraffic()

        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in self?.updateTraffic() }
        RunLoop.main.add(timer, forMode: .common)
        trafficTimer = timer
    }

    func stopTrafficMonitoring(clearHistory: Bool = true) {
        trafficTimer?.invalidate()
        trafficTimer = nil
        previousTraffic = nil
        if clearHistory {
            trafficSamples = []
            otherNetworks = []
        }
    }

    func updateConnection(_ snapshot: ConnectionSnapshot) {
        connection = snapshot
        ethernetSpeed = nil
        ipAddress = nil
        metadataGeneration += 1
        let generation = metadataGeneration
        guard let interface = snapshot.interfaceName else { return }

        metadataQueue.async { [weak self] in
            let speed = snapshot.kind == .ethernet ? Self.interfaceValue(interface, argument: "media") : nil
            let address = Self.ipAddress(for: interface)
            DispatchQueue.main.async {
                guard let self, self.metadataGeneration == generation else { return }
                self.ethernetSpeed = speed
                self.ipAddress = address
            }
        }
    }

    func refresh() {
        wifiEnabled = wifi?.powerOn() ?? false
        currentSSID = wifi?.ssid()
        refreshSignalStrength()
        if wifiEnabled, let wifi {
            let cached = (wifi.cachedScanResults() ?? []).union(knownNetworks.map(\.network))
            applyNetworks(cached, knownSSIDs: Self.knownSSIDs(for: wifi), currentSSID: currentSSID)
        } else {
            scanGeneration += 1
            isScanning = false
            knownNetworks = []
            otherNetworks = []
        }
        requestLocationIfNeeded()
        scan()
    }

    func refreshSignalStrength() {
        updateSignalStrength(wifi?.rssiValue() ?? 0)
    }

    private func updateSignalStrength(_ rssi: Int) {
        let strength = WiFiSignal.strength(for: rssi)
        guard strength != currentSignalStrength else { return }
        currentSignalStrength = strength
        onSignalChange?()
    }

    func linkQualityDidChangeForWiFiInterface(withName interfaceName: String, rssi: Int, transmitRate: Double) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wifi?.interfaceName == interfaceName else { return }
            self.updateSignalStrength(rssi)
        }
    }

    func setWiFiEnabled(_ enabled: Bool) {
        do {
            try wifi?.setPower(enabled)
            wifiEnabled = enabled
            if enabled { scan() }
            else {
                scanGeneration += 1
                isScanning = false
                currentSSID = nil
                knownNetworks = []
                otherNetworks = []
            }
        } catch {
            errorMessage = error.localizedDescription
            wifiEnabled = wifi?.powerOn() ?? false
        }
    }

    func connect(to item: WiFiNetworkItem, password: String?) {
        isScanning = true
        workQueue.async { [weak self] in
            guard let self, let wifi = self.wifi else { return }
            do {
                try wifi.associate(to: item.network, password: password ?? self.savedPassword(for: item.network))
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.refresh()
                }
            } catch {
                DispatchQueue.main.async {
                    self.isScanning = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            launchesAtLogin = enabled
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openNetworkSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.wifi-settings-extension") else { return }
        NSWorkspace.shared.open(url)
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorized || manager.authorizationStatus == .authorizedAlways {
            refresh()
        }
    }

    private func requestLocationIfNeeded() {
        if locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
    }

    private func scan() {
        guard wifiEnabled, !isScanning, let wifi else { return }
        isScanning = true
        scanGeneration += 1
        let generation = scanGeneration
        workQueue.async { [weak self] in
            guard let self else { return }
            do {
                let scanned = try wifi.scanForNetworks(withName: nil)
                let knownSSIDs = Self.knownSSIDs(for: wifi)
                let currentSSID = wifi.ssid()
                DispatchQueue.main.async {
                    guard self.scanGeneration == generation, self.wifiEnabled else { return }
                    self.applyNetworks(scanned, knownSSIDs: knownSSIDs, currentSSID: currentSSID)
                    self.isScanning = false
                }
            } catch {
                DispatchQueue.main.async {
                    guard self.scanGeneration == generation else { return }
                    self.isScanning = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func knownSSIDs(for wifi: CWInterface) -> Set<String> {
        Set((wifi.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []).compactMap(\.ssid))
    }

    private func applyNetworks(_ networks: Set<CWNetwork>, knownSSIDs: Set<String>, currentSSID: String?) {
        let strongest = Dictionary(grouping: networks.compactMap { network -> WiFiNetworkItem? in
            guard let ssid = network.ssid, !ssid.isEmpty else { return nil }
            return WiFiNetworkItem(network: network, ssid: ssid,
                                   isKnown: knownSSIDs.contains(ssid), isCurrent: ssid == currentSSID)
        }, by: \.ssid).compactMap { _, items in
            items.max { $0.network.rssiValue < $1.network.rssiValue }
        }.sorted { $0.network.rssiValue > $1.network.rssiValue }
        self.currentSSID = currentSSID
        knownNetworks = strongest.filter { $0.isKnown || $0.isCurrent }
        otherNetworks = strongest.filter { !$0.isKnown && !$0.isCurrent }
    }

    private func savedPassword(for network: CWNetwork) -> String? {
        guard let ssidData = network.ssidData else { return nil }
        for domain in [CWKeychainDomain.user, .system] {
            var password: NSString?
            if CWKeychainFindWiFiPassword(domain, ssidData, &password) == errSecSuccess {
                return password as String?
            }
        }
        return nil
    }

    private static func ipAddress(for interface: String) -> String? {
        run("/usr/sbin/ipconfig", ["getifaddr", interface])
    }

    private static func interfaceValue(_ interface: String, argument: String) -> String? {
        guard let output = run("/sbin/ifconfig", [interface]),
              let line = output.split(separator: "\n").first(where: { $0.contains("\(argument):") }) else { return nil }
        let value = line.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces)
        if argument == "media", let start = value?.firstIndex(of: "("), let end = value?.firstIndex(of: ")") {
            return String(value![value!.index(after: start)..<end]).replacingOccurrences(of: "baseTX <full-duplex>", with: " Mbps")
        }
        return value
    }

    private static func run(_ executable: String, _ arguments: [String]) -> String? {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func updateTraffic() {
        guard let interface = connection.interfaceName,
              let counters = Self.trafficCounters(for: interface) else {
            previousTraffic = nil
            trafficSamples = []
            downloadBytesPerSecond = 0
            uploadBytesPerSecond = 0
            return
        }

        let now = Date()
        if let previous = previousTraffic, previous.interface == interface {
            let elapsed = now.timeIntervalSince(previous.date)
            downloadBytesPerSecond = TrafficRate.calculate(previous: previous.received, current: counters.received, seconds: elapsed)
            uploadBytesPerSecond = TrafficRate.calculate(previous: previous.sent, current: counters.sent, seconds: elapsed)
            trafficSamples.append(TrafficSample(date: now, download: downloadBytesPerSecond, upload: uploadBytesPerSecond))
            if trafficSamples.count > 60 { trafficSamples.removeFirst(trafficSamples.count - 60) }
        } else {
            trafficSamples = []
        }
        previousTraffic = (interface, counters.received, counters.sent, now)
    }

    private static func trafficCounters(for interface: String) -> (received: UInt64, sent: UInt64)? {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0, let first else { return nil }
        defer { freeifaddrs(first) }

        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let pointer = current {
            let item = pointer.pointee
            if String(cString: item.ifa_name) == interface,
               let address = item.ifa_addr,
               address.pointee.sa_family == UInt8(AF_LINK),
               let rawData = item.ifa_data {
                let data = rawData.assumingMemoryBound(to: if_data.self).pointee
                return (UInt64(data.ifi_ibytes), UInt64(data.ifi_obytes))
            }
            current = item.ifa_next
        }
        return nil
    }
}

extension ConnectionSnapshot {
    init(kind: ConnectionKind, interfaceName: String?) {
        self.kind = kind
        self.interfaceName = interfaceName
    }
}
