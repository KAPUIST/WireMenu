import SwiftUI

struct NetworkPanelView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var model: NetworkPanelModel
    let maximumHeight: CGFloat
    @State private var contentHeight: CGFloat = 216
    @State private var footerHeight: CGFloat = 60
    @FocusState private var focusedRow: String?
    @State private var usesKeyboardNavigation = false
    @State private var expandedOtherNetworks = false
    @State private var passwordNetwork: WiFiNetworkItem?
    @State private var password = ""

    var body: some View {
        if #available(macOS 14.0, *) {
            panelContent.focusEffectDisabled(!usesKeyboardNavigation)
        } else {
            panelContent
        }
    }

    private var panelContent: some View {
        VStack(spacing: 0) {
            wifiHeader
            divider
            ScrollViewReader { proxy in
                ScrollView {
                    menuContent
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
                }
                .scrollDisabled(contentHeight <= availableHeight)
                .frame(height: min(contentHeight, availableHeight))
                .onChange(of: focusedRow) { row in
                    if let row { proxy.scrollTo(row) }
                }
            }
            divider
            footer
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { footerHeight = $0 }
        }
        .frame(width: 308)
        .fixedSize(horizontal: false, vertical: true)
        .onMoveCommand { moveFocus($0) }
        .onReceive(NotificationCenter.default.publisher(for: MenuNavigation.keyNotification)) { notification in
            switch notification.object as? UInt16 {
            case 123: moveFocus(.left)
            case 124: moveFocus(.right)
            case 125: moveFocus(.down)
            case 126: moveFocus(.up)
            case 36, 49: activateFocusedRow()
            default: break
            }
        }
    }

    private func moveFocus(_ direction: MoveCommandDirection) {
        usesKeyboardNavigation = true
        switch direction {
        case .up, .down:
            focusedRow = MenuNavigation.next(current: focusedRow, rows: focusableRows, forward: direction == .down)
        case .left:
            if expandedOtherNetworks { expandedOtherNetworks = false; focusedRow = "other" }
        case .right:
            if focusedRow == "other" { expandedOtherNetworks = true }
        default: break
        }
    }

    private func activateFocusedRow() {
        switch focusedRow {
        case "wifi": model.setWiFiEnabled(!model.wifiEnabled)
        case "hotspot", "settings": model.openNetworkSettings()
        case "other": expandedOtherNetworks.toggle()
        case "login": model.setLaunchAtLogin(!model.launchesAtLogin)
        case "quit": model.quit()
        case let row?:
            if let item = (model.knownNetworks + model.otherNetworks).first(where: { "network:" + $0.ssid == row }) { select(item) }
        default: break
        }
    }

    private var availableHeight: CGFloat { max(0, maximumHeight - 45 - footerHeight) }

    private var focusableRows: [String] {
        var rows = ["wifi"]
        if model.wifiEnabled {
            rows += ["hotspot"] + model.knownNetworks.map { "network:" + $0.ssid }
            if !model.otherNetworks.isEmpty {
                rows.append("other")
                if expandedOtherNetworks { rows += model.otherNetworks.map { "network:" + $0.ssid } }
            }
        }
        return rows + ["settings", "login", "quit"]
    }

    private var menuContent: some View {
        VStack(spacing: 0) {
            connectionSection
            if model.wifiEnabled {
                divider
                hotspotSection
                divider
                wifiNetworks
            }
        }
        .frame(width: 308)
        .fixedSize(horizontal: false, vertical: true)
        .alert("Wi‑Fi 연결 오류", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("확인") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "알 수 없는 오류")
        }
        .sheet(item: $passwordNetwork) { item in
            VStack(alignment: .leading, spacing: 16) {
                Text(item.ssid).font(.headline)
                SecureField("암호", text: $password)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { connect(item) }
                HStack {
                    Button("취소") { passwordNetwork = nil; password = "" }
                    Spacer()
                    Button("연결") { connect(item) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(password.isEmpty)
                }
            }
            .padding(20)
            .frame(width: 308)
        }
    }

    private var wifiNetworks: some View {
        VStack(alignment: .leading, spacing: 0) {
            networkSection("알고 있는 네트워크", items: model.knownNetworks)

            if !model.otherNetworks.isEmpty {
                Divider().padding(.horizontal, 14)
                    Button { expandedOtherNetworks.toggle() } label: {
                        HStack {
                            Text("다른 네트워크")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 12))
                                .rotationEffect(.degrees(expandedOtherNetworks ? 90 : 0))
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: expandedOtherNetworks)
                        }
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 14)
                        .frame(height: 33)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MenuRowStyle(isFocused: focusedRow == "other", verticalInset: 5.5, cornerRadius: 11))
                    .focusable()
                    .focused($focusedRow, equals: "other")
                    .id("other")
                    .accessibilityLabel("다른 네트워크")
                    .accessibilityValue(expandedOtherNetworks ? "펼쳐짐" : "접힘")
                    .accessibilityIdentifier("wiremenu.other-networks")
                if expandedOtherNetworks {
                    networkSection(nil, items: model.otherNetworks)
                }
            }

            if model.isScanning && model.knownNetworks.isEmpty && model.otherNetworks.isEmpty {
                HStack(spacing: 7) {
                    ProgressView().controlSize(.small)
                    Text("네트워크 검색 중…")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var hotspotSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("개인용 핫스팟")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            Button { model.openNetworkSettings() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "personalhotspot")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color(nsColor: .secondaryLabelColor))
                        .frame(width: 26, height: 26)
                        .background(Color.secondary.opacity(0.12), in: Circle())
                    Text("핫스팟 연결…")
                        .font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Spacer()
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle(isFocused: focusedRow == "hotspot"))
            .focusable()
            .focused($focusedRow, equals: "hotspot")
            .id("hotspot")
            .accessibilityLabel("핫스팟 연결")
        }
        .padding(.bottom, 4)
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                connectionImage
                    .frame(width: 14, height: 14)
                    .foregroundStyle(model.connection.kind == .offline ? Color.secondary : .white)
                    .frame(width: 26, height: 26)
                    .background(model.connection.kind == .offline ? Color.secondary.opacity(0.12) : Color.accentColor, in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(connectionTitle).font(.system(size: 13))
                        .foregroundStyle(Color(nsColor: .labelColor))
                    Text(connectionDetail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Circle()
                    .fill(model.connection.kind == .offline ? Color.secondary.opacity(0.35) : Color.green)
                    .frame(width: 7, height: 7)
            }

            HStack(spacing: 8) {
                trafficRow("다운로드", symbol: "arrow.down", value: model.downloadBytesPerSecond, keyPath: \.download, color: .blue)
                Divider().frame(height: 34)
                trafficRow("업로드", symbol: "arrow.up", value: model.uploadBytesPerSecond, keyPath: \.upload, color: .purple)
            }
            .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
    }

    private var connectionImage: some View {
        Image(systemName: model.connection.kind.systemSymbolName,
              variableValue: model.connection.kind == .wifi ? model.currentSignalStrength : 1)
            .font(.system(size: 13, weight: .semibold))
    }

    private var connectionTitle: String {
        switch model.connection.kind {
        case .ethernet: "Ethernet"
        case .wifi: model.currentSSID ?? "Wi‑Fi"
        case .hotspot: model.currentSSID ?? "개인용 핫스팟"
        case .offline: "연결 안 됨"
        case .other: "네트워크"
        }
    }

    private var connectionDetail: String {
        switch model.connection.kind {
        case .ethernet:
            [model.ethernetSpeed, model.ipAddress].compactMap { $0 }.joined(separator: " · ")
        case .wifi, .hotspot, .other:
            [model.connection.interfaceName, model.ipAddress].compactMap { $0 }.joined(separator: " · ")
        case .offline:
            "인터넷 연결 없음"
        }
    }

    private var wifiHeader: some View {
        HStack {
            Text("Wi-Fi").font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color(nsColor: .labelColor))
            Spacer()
            Toggle("", isOn: Binding(
                get: { model.wifiEnabled },
                set: { model.setWiFiEnabled($0) }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .accessibilityLabel("Wi-Fi")
            .focusable()
            .focused($focusedRow, equals: "wifi")
        }
        .padding(.horizontal, 14)
        .frame(height: 43)
    }

    private func speed(_ bytesPerSecond: Double) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytesPerSecond), countStyle: .binary) + "/s"
    }

    private func trafficRow(
        _ title: String,
        symbol: String,
        value: Double,
        keyPath: KeyPath<TrafficSample, Double>,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            VStack(alignment: .leading, spacing: 2) {
                Label(title, systemImage: symbol)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(color)
                Text(speed(value))
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            TrafficSparkline(samples: model.trafficSamples, keyPath: keyPath, color: color)
                .frame(height: 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(6)
    }

    private func networkSection(_ title: String?, items: [WiFiNetworkItem]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let title {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.top, 10)
            }

            if items.isEmpty {
                Text("표시할 네트워크가 없습니다")
                    .font(.system(size: 12))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 10)
            } else {
                ForEach(items) { item in
                    Button { select(item) } label: {
                        HStack(spacing: 8) {
                            Image(systemName: item.isCurrent && model.connection.kind == .hotspot ? "personalhotspot" : "wifi",
                                  variableValue: item.isCurrent ? model.currentSignalStrength : item.signalStrength)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.isCurrent ? .white : .primary)
                                .frame(width: 26, height: 26)
                                .background(item.isCurrent ? Color.accentColor : Color.secondary.opacity(0.12), in: Circle())
                            Text(item.ssid)
                                .font(.system(size: 13, weight: .regular))
                                .foregroundStyle(Color(nsColor: .labelColor))
                                .lineLimit(1)
                            Spacer()
                            if item.isSecure {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(MenuRowStyle(isFocused: focusedRow == "network:" + item.ssid))
                    .focusable()
                    .focused($focusedRow, equals: "network:" + item.ssid)
                    .id("network:" + item.ssid)
                    .accessibilityLabel(item.ssid)
                    .accessibilityValue(item.isCurrent ? "연결됨" : "")
                }
            }
        }
        .padding(.bottom, 4)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Button { model.openNetworkSettings() } label: {
                Text("Wi-Fi 설정…")
                    .font(.system(size: 13))
                    .foregroundStyle(Color(nsColor: .labelColor))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .frame(height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(MenuRowStyle(isFocused: focusedRow == "settings"))
            .focusable()
            .focused($focusedRow, equals: "settings")
            .accessibilityLabel("Wi-Fi 설정")

            HStack {
                Toggle("로그인 시 자동 실행", isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
                .toggleStyle(.checkbox)
                .focusable()
                .focused($focusedRow, equals: "login")
                Spacer()
                Button("종료") { model.quit() }.buttonStyle(.plain)
                    .focusable()
                    .focused($focusedRow, equals: "quit")
            }
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
    }

    private var divider: some View {
        Divider().padding(.horizontal, 14)
    }

    private func select(_ item: WiFiNetworkItem) {
        guard !item.isCurrent else { return }
        if item.isSecure && !item.isKnown {
            passwordNetwork = item
        } else {
            model.connect(to: item, password: nil)
        }
    }

    private func connect(_ item: WiFiNetworkItem) {
        model.connect(to: item, password: password)
        passwordNetwork = nil
        password = ""
    }
}

enum MenuNavigation {
    static let keyNotification = Notification.Name("WireMenu.menuKey")
    static func next(current: String?, rows: [String], forward: Bool) -> String? {
        guard !rows.isEmpty else { return nil }
        guard let current, let index = rows.firstIndex(of: current) else { return forward ? rows.first : rows.last }
        return rows[(index + (forward ? 1 : rows.count - 1)) % rows.count]
    }
}

private struct MenuRowStyle: ButtonStyle {
    let isFocused: Bool
    var verticalInset: CGFloat = 0
    var cornerRadius: CGFloat = 9
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .background {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .fill(Color(nsColor: configuration.isPressed ? .tertiaryLabelColor : .quaternaryLabelColor))
                        .opacity(isHovered || isFocused || configuration.isPressed ? 1 : 0)
                        .padding(.horizontal, 7)
                        .padding(.vertical, verticalInset)
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: isHovered)
            }
            .onHover { isHovered = $0 }
    }
}

private struct TrafficSparkline: View {
    let samples: [TrafficSample]
    let keyPath: KeyPath<TrafficSample, Double>
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                areaPath(in: geometry.size)
                    .fill(LinearGradient(colors: [color.opacity(0.24), color.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                linePath(in: geometry.size)
                    .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }

    private func points(in size: CGSize) -> [CGPoint] {
        guard !samples.isEmpty else { return [] }
        let peak = max(samples.map { $0[keyPath: keyPath] }.max() ?? 0, 1)
        let divisor = CGFloat(max(samples.count - 1, 1))
        return samples.enumerated().map { index, sample in
            CGPoint(
                x: size.width * CGFloat(index) / divisor,
                y: size.height * (1 - CGFloat(sample[keyPath: keyPath] / peak))
            )
        }
    }

    private func linePath(in size: CGSize) -> Path {
        let points = points(in: size)
        return Path { path in
            guard let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
        }
    }

    private func areaPath(in size: CGSize) -> Path {
        let points = points(in: size)
        return Path { path in
            guard let first = points.first, let last = points.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            path.addLine(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}
