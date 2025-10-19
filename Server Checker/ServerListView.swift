import SwiftUI
import Combine
import Network
import UniformTypeIdentifiers

final class NetworkStatusObserver: ObservableObject {
    @Published var interfaceDescription: String = "Unknown"

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkStatusObserver")

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let desc: String
            if path.usesInterfaceType(.wifi) {
                desc = "Wi‑Fi" // SSID requires extra permissions/APIs
            } else if path.usesInterfaceType(.cellular) {
                desc = "Cellular"
            } else if path.usesInterfaceType(.wiredEthernet) {
                desc = "Ethernet"
            } else if path.status == .satisfied {
                desc = "Connected"
            } else {
                desc = "Offline"
            }
            DispatchQueue.main.async {
                self?.interfaceDescription = desc
            }
        }
        monitor.start(queue: queue)
    }

    deinit { monitor.cancel() }
}

struct ServerListView: View {
    @EnvironmentObject private var store: ServerStore
    @State private var showingAdd = false
    @State private var showingAbout = false
    @State private var showingSettings = false
    @State private var showingCategoryManagement = false
    @StateObject private var networkObserver = NetworkStatusObserver()
    
    private var networkIconName: String {
        switch networkObserver.interfaceDescription {
        case "Wi‑Fi": return "wifi"
        case "Cellular": return "antenna.radiowaves.left.and.right"
        case "Ethernet": return "network"
        case "Connected": return "network"
        case "Offline": return "xmark.circle"
        default: return "network"
        }
    }

    private func counts() -> (online: Int, notResponding: Int, unknown: Int) {
        let online = store.servers.filter { (store.statuses[$0.id] ?? .unknown) == .online }.count
        let unknown = store.servers.filter { (store.statuses[$0.id] ?? .unknown) == .unknown }.count
        let notResponding = store.servers.filter { let s = (store.statuses[$0.id] ?? .unknown); return s == .offline || s == .unknown }.count
        return (online, notResponding, unknown)
    }

    private var groupedServers: [(category: String?, items: [Server])] {
        let groups = Dictionary(grouping: store.servers) { (s: Server) -> String? in
            let t = s.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        }
        // Sort categories: named first alphabetically, then nil (Uncategorised)
        let sortedKeys = groups.keys.sorted { a, b in
            switch (a, b) {
            case let (l?, r?): return l.localizedCaseInsensitiveCompare(r) == .orderedAscending
            case (nil, _?): return false
            case (_?, nil): return true
            default: return false
            }
        }
        return sortedKeys.map { key in
            let items = groups[key] ?? []
            return (key, items)
        }
    }

    private var onlineCount: Int {
        store.servers.reduce(0) { partial, s in
            partial + ((store.statuses[s.id] ?? .unknown) == .online ? 1 : 0)
        }
    }

    private var unknownCount: Int {
        store.servers.reduce(0) { partial, s in
            partial + ((store.statuses[s.id] ?? .unknown) == .unknown ? 1 : 0)
        }
    }

    private var notRespondingCount: Int {
        store.servers.reduce(0) { partial, s in
            let st = (store.statuses[s.id] ?? .unknown)
            return partial + ((st == .offline || st == .unknown) ? 1 : 0)
        }
    }

    private var isChecking: Bool {
        for s in store.servers {
            if (store.statuses[s.id] ?? .unknown) == .unknown { return true }
        }
        return false
    }

    private var lastUpdatedText: String? {
        if let last = store.lastUpdated {
            return last.formatted(date: .omitted, time: .standard)
        }
        return nil
    }
    
    private func stableCategoryID(_ category: String?) -> String {
        let t = (category ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? "UNCAT" : t
    }

    private func handleDrop(to category: String?, providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { item, _ in
                let str: String?
                if let s = item as? String {
                    str = s
                } else if let data = item as? Data, let s = String(data: data, encoding: .utf8) {
                    str = s
                } else if let url = item as? URL {
                    str = url.absoluteString
                } else if let ns = item as? NSString {
                    str = ns as String
                } else {
                    str = nil
                }
                if let str, let id = UUID(uuidString: str.trimmingCharacters(in: .whitespacesAndNewlines)) {
                    Task { @MainActor in
                        store.assign(serverID: id, toCategory: category)
                    }
                }
            }
            return true
        }
        return false
    }

    private func mappedIndexes(for groupItems: [Server]) -> IndexSet {
        let ids = groupItems.map { $0.id }
        let indices = ids.compactMap { id in store.servers.firstIndex(where: { $0.id == id }) }
        return IndexSet(indices)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    SummaryHeaderView(
                        online: onlineCount,
                        notResponding: notRespondingCount,
                        unknown: unknownCount,
                        lastUpdatedText: lastUpdatedText,
                        isChecking: isChecking
                    )
                }
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Network Is")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(networkObserver.interfaceDescription)
                                .font(.headline)
                        }
                        Spacer()
                        Image(systemName: networkIconName)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 6)
                }
                Section {
                    Text("Tap the + to add a server. To delete a server, swipe the entry to the left and choose delete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                ForEach(groupedServers.map { ($0, stableCategoryID($0.category)) }, id: \.1) { pair in
                    let group = pair.0
                    Section(
                        header: CategoryHeaderView(
                            title: group.category ?? "Uncategorised",
                            onDrop: { providers in
                                handleDrop(to: group.category, providers: providers)
                            }
                        )
                    ) {
                        ForEach(group.items) { server in
                            ServerRow(
                                server: server,
                                status: store.statuses[server.id] ?? .unknown
                            )
                            .padding(.leading, 12)
                            .contentShape(Rectangle())
                            .onTapGesture { store.checkStatus(for: server) }
                            .onDrag { NSItemProvider(object: server.id.uuidString as NSString) }
                        }
                        .onDelete { _ in
                            let indexes = mappedIndexes(for: group.items)
                            store.remove(at: indexes)
                        }
                        .onMove { source, destination in
                            store.moveWithinCategory(group.category, from: source, to: destination)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .listRowSpacing(4)
            .environment(\.defaultMinListRowHeight, 34)
            .refreshable {
                store.refreshAllStatuses()
            }
            .overlay {
                if store.servers.isEmpty {
                    ContentUnavailableView("No Servers", systemImage: "server.rack", description: Text("Add a server to begin"))
                }
            }
            .navigationTitle("Servers")
            .task {
                // Perform an initial refresh with a small delay, but avoid doing so while any sheet is shown
                // to keep sheet presentation responsive.
                while showingAdd || showingSettings || showingAbout || showingCategoryManagement {
                    try? await Task.sleep(nanoseconds: 200_000_000) // wait 200ms and check again
                }
                try? await Task.sleep(nanoseconds: 200_000_000) // small debounce after appear
                store.refreshAllStatuses()
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAdd = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Add Server")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("About") { showingAbout = true }
                        Button("Category Management") { showingCategoryManagement = true }
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Options")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 150_000_000) // 150ms debounce
                            store.refreshAllStatuses()
                        }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .sheet(isPresented: $showingAdd) {
                AddEditServerView(existingCategories: store.servers.compactMap { s in
                    let t = s.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    return t.isEmpty ? nil : t
                }.uniqued()) { newServer in
                    store.add(newServer)
                }
            }
            .sheet(isPresented: $showingAbout) {
                let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                let versionText = build.isEmpty ? shortVersion : "\(shortVersion) (\(build))"
                VStack(spacing: 16) {
                    Text("Server Monitor v\(versionText)")
                        .font(.headline)
                    Text("A small utlity that lets you quickly check whether a device is active and online, on the network that your device is currently connected to.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("The application will automatically refresh itself. We will be adding more feature to the app in the future, if you have anything you'd like to suggest, please open an issue through the support link.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Button("Close") {
                        showingAbout = false
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding()
                .presentationDetents([.medium])
            }
            .sheet(isPresented: $showingCategoryManagement) {
                CategoryManagementView()
                    .environmentObject(store)
            }
            .sheet(isPresented: $showingSettings) {
                SettingsView()
                    .environmentObject(store)
            }
        }
    }
}

struct ServerRow: View {
    let server: Server
    let status: ServerStatus

    var body: some View {
        HStack {
            Circle()
                .fill(color(for: status))
                .frame(width: 10, height: 10)
            VStack(alignment: .leading) {
                Text(server.name).font(.subheadline).lineLimit(1)
                Text("\(server.host):\(server.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if status == .unknown {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }

    private func color(for status: ServerStatus) -> Color {
        switch status {
        case .online: return .green
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}

struct CategoryHeaderView: View {
    let title: String
    let onDropHandler: ([NSItemProvider]) -> Bool

    init(title: String, onDrop: @escaping ([NSItemProvider]) -> Bool) {
        self.title = title
        self.onDropHandler = onDrop
    }

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
            Spacer()
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.text], isTargeted: nil, perform: onDropHandler)
    }
}

private struct UnknownBadge: View {
    let count: Int
    var body: some View {
        Group {
            if count > 0 {
                Text("\(count) unk")
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.gray.opacity(0.15))
                    .foregroundStyle(.secondary)
                    .clipShape(Capsule())
            }
        }
    }
}

private struct SummaryHeaderView: View {
    let online: Int
    let notResponding: Int
    let unknown: Int
    let lastUpdatedText: String?
    let isChecking: Bool

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Devices Responding")
                Spacer()
                Text("\(online)")
                    .bold()
                    .foregroundStyle(.green)
            }
            HStack {
                Text("Devices Not Responding")
                Spacer()
                HStack(spacing: 6) {
                    Text("\(notResponding)")
                        .bold()
                        .foregroundStyle(.red)
                    UnknownBadge(count: unknown)
                }
            }
        }
        HStack(spacing: 8) {
            if let text = lastUpdatedText {
                Text("Last updated \(text)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            if isChecking {
                Text("Checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView()
                    .controlSize(.mini)
            }
        }
        .padding(.vertical, 6)
        .font(.subheadline)
    }
}

#Preview {
    ServerListView()
        .environmentObject(ServerStore())
}

// Fallback SettingsView in case the separate file isn't included in the target
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ServerStore

    var body: some View {
        NavigationStack {
            Form {
                Section("Connection Timeout") {
                    Stepper(value: $store.timeoutSeconds, in: 1...10) {
                        HStack {
                            Text("Timeout")
                            Spacer()
                            Text("\(store.timeoutSeconds) s")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text("How long to wait before marking a server offline.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen = Set<Element>()
        return self.filter { seen.insert($0).inserted }
    }
}

