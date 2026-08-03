import Foundation
import SystemConfiguration

struct NetworkStatus: Equatable {
    enum AddressSource: Equatable {
        case dhcp
        case manual
        case unavailable
    }

    let interfaceName: String?
    let transportName: String
    let symbolName: String
    let ipv4Address: String?
    let addressSource: AddressSource

    static let unavailable = NetworkStatus(interfaceName: nil,
                                           transportName: "No active interface",
                                           symbolName: "exclamationmark.triangle.fill",
                                           ipv4Address: nil,
                                           addressSource: .unavailable)

    static func current() -> NetworkStatus {
        guard let store = SCDynamicStoreCreate(nil, "NetMon.NetworkStatus" as CFString, nil, nil),
              let globalIPv4 = dictionary(in: store, key: "State:/Network/Global/IPv4"),
              let interfaceName = globalIPv4["PrimaryInterface"] as? String else {
            return .unavailable
        }

        let serviceID = globalIPv4["PrimaryService"] as? String
        let serviceIPv4 = serviceID.flatMap {
            dictionary(in: store, key: "State:/Network/Service/\($0)/IPv4")
        }
        let interfaceIPv4 = dictionary(in: store,
                                       key: "State:/Network/Interface/\(interfaceName)/IPv4")
        let address = firstAddress(in: serviceIPv4) ?? firstAddress(in: interfaceIPv4)

        let serviceInterface = serviceID.flatMap {
            dictionary(in: store, key: "Setup:/Network/Service/\($0)/Interface")
        }
        let hardware = (serviceInterface?["Hardware"] as? String)
            ?? (serviceInterface?["Type"] as? String)
            ?? ""
        let transport = transportDetails(hardware: hardware, interfaceName: interfaceName)

        let hasDHCPLease = serviceID.flatMap {
            dictionary(in: store, key: "State:/Network/Service/\($0)/DHCP")
        } != nil
        let source: AddressSource
        if address == nil {
            source = .unavailable
        } else if hasDHCPLease {
            source = .dhcp
        } else {
            source = .manual
        }

        return NetworkStatus(interfaceName: interfaceName,
                             transportName: transport.name,
                             symbolName: transport.symbol,
                             ipv4Address: address,
                             addressSource: source)
    }

    var helpText: String {
        let interfaceDescription = interfaceName.map { "\(transportName) (\($0))" }
            ?? transportName
        switch (addressSource, ipv4Address) {
        case (.dhcp, let address?):
            return "Active: \(interfaceDescription)\nDHCP: \(address)\nClick to copy address"
        case (.manual, let address?):
            return "Active: \(interfaceDescription)\nManual IPv4: \(address)\nClick to copy address"
        default:
            return "\(interfaceDescription)\nNo IPv4 address acquired"
        }
    }

    private static func dictionary(in store: SCDynamicStore, key: String) -> [String: Any]? {
        SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }

    private static func firstAddress(in dictionary: [String: Any]?) -> String? {
        (dictionary?["Addresses"] as? [String])?.first
    }

    private static func transportDetails(hardware: String,
                                         interfaceName: String) -> (name: String, symbol: String) {
        let normalized = hardware.lowercased()
        if normalized.contains("airport") || normalized.contains("wi-fi") || normalized.contains("wireless") {
            return ("Wi-Fi", "wifi")
        }
        if normalized.contains("ethernet") {
            return ("Ethernet", "cable.connector.horizontal")
        }
        if normalized.contains("vpn") || interfaceName.hasPrefix("utun") {
            return ("VPN", "lock.shield.fill")
        }
        return (interfaceName, "network")
    }
}
