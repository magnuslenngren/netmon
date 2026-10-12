import SwiftUI

struct NetworkDetailsView: View {
    let status: NetworkStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network Details").font(.headline)
            Label(status.transportName, systemImage: status.symbolName)
                .font(.caption).foregroundStyle(.secondary)
            Divider()
            if let interface = status.interfaceName {
                detail("Interface", value: interface)
            }
            if let address = status.ipv4Address {
                detail("IPv4 Address", value: address)
                detail("Configuration", value: status.addressSource == .dhcp ? "DHCP" : "Manual")
            } else {
                Text("No IPv4 address acquired").foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 310, alignment: .leading)
    }

    private func detail(_ label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Text(value).monospacedDigit()
        }
    }
}

struct NetworkBadgeFrame: PreferenceKey {
    static var defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let frame = nextValue()
        // Siblings without an icon contribute the empty default. Preserve the
        // measured badge instead of allowing those defaults to erase its hit area.
        if !frame.isEmpty { value = frame }
    }
}
