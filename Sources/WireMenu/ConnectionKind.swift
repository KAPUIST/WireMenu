import Network
import SystemConfiguration

enum ConnectionKind: Equatable {
    case ethernet
    case wifi
    case hotspot
    case other
    case offline

    static func classify(
        isSatisfied: Bool,
        usesEthernet: Bool,
        usesWiFi: Bool,
        usesCellular: Bool,
        isExpensive: Bool
    ) -> Self {
        guard isSatisfied else { return .offline }
        if usesEthernet { return .ethernet }
        if usesCellular || (usesWiFi && isExpensive) { return .hotspot }
        if usesWiFi { return .wifi }
        return .other
    }

    var title: String {
        switch self {
        case .ethernet: "유선 인터넷 사용 중"
        case .wifi: "Wi‑Fi 사용 중"
        case .hotspot: "개인용 핫스팟 사용 중"
        case .other: "인터넷 연결됨"
        case .offline: "인터넷 연결 끊김"
        }
    }

    var systemSymbolName: String {
        switch self {
        case .ethernet: "display"
        case .wifi: "wifi"
        case .hotspot: "personalhotspot"
        case .other: "network"
        case .offline: "network.slash"
        }
    }
}

struct ConnectionSnapshot: Equatable {
    let kind: ConnectionKind
    let interfaceName: String?

    init(path: NWPath) {
        kind = .classify(
            isSatisfied: path.status == .satisfied,
            usesEthernet: path.usesInterfaceType(.wiredEthernet),
            usesWiFi: path.usesInterfaceType(.wifi),
            usesCellular: path.usesInterfaceType(.cellular),
            isExpensive: path.isExpensive
        )

        let preferredType: NWInterface.InterfaceType? = switch kind {
        case .ethernet: .wiredEthernet
        case .wifi, .hotspot: path.usesInterfaceType(.wifi) ? .wifi : .cellular
        case .other, .offline: nil
        }
        interfaceName = preferredType.flatMap { type in
            let candidates = path.availableInterfaces.filter { $0.type == type }
            if let primary = Self.primaryInterfaceName(), candidates.contains(where: { $0.name == primary }) {
                return primary
            }
            return candidates.first?.name
        }
    }

    private static func primaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "WireMenu" as CFString, nil, nil),
              let state = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any] else {
            return nil
        }
        return state[kSCDynamicStorePropNetPrimaryInterface as String] as? String
    }
}
