import Foundation
import Combine
import Network
import SwiftUI

@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published var statuses: [UUID: ServerStatus] = [:]
    @Published var lastUpdated: Date? = nil
    @Published var timeoutSeconds: Int = 3 {
        didSet { UserDefaults.standard.set(timeoutSeconds, forKey: "timeout_seconds_v1") }
    }

    private let storageKey = "saved_servers_v1"
    private var lastRefreshAt: Date = .distantPast
    private var refreshTimer: Timer?
    
    private let categoriesKey = "saved_categories_v1"
    @Published private(set) var categories: [String] = [] // Persisted list including empty categories

    private func updateLastUpdatedIfComplete() {
        // Only consider complete if we have servers; if none, set lastUpdated now.
        if servers.isEmpty {
            lastUpdated = Date()
            return
        }
        // When all known servers have a non-unknown status, mark as updated.
        let allResolved = servers.allSatisfy { server in
            (statuses[server.id] ?? .unknown) != .unknown
        }
        if allResolved {
            lastUpdated = Date()
        }
    }
    
    // Debounce guard to avoid spamming refreshes when multiple triggers fire close together
    private var lastResumeHandledAt: Date = .distantPast
    private let resumeDebounceInterval: TimeInterval = 2

    init() {
        load()
        if let data = UserDefaults.standard.data(forKey: categoriesKey),
           let decoded = try? JSONDecoder().decode([String].self, from: data) {
            self.categories = decoded
        }
        if let stored = UserDefaults.standard.object(forKey: "timeout_seconds_v1") as? Int {
            self.timeoutSeconds = max(1, min(10, stored))
        }
        // Schedule the timer on the main run loop using target-selector to avoid capturing self in a long-lived closure.
        refreshTimer = Timer.scheduledTimer(timeInterval: 15.0, target: self, selector: #selector(handleRefreshTimer(_:)), userInfo: nil, repeats: true)
        RunLoop.main.add(refreshTimer!, forMode: .common)
    }
    
    deinit {
        refreshTimer?.invalidate()
    }

    @objc private func handleRefreshTimer(_ timer: Timer) {
        // We are already on @MainActor due to the class annotation
        refreshAllStatuses()
    }

    func add(_ server: Server) {
        servers.append(server)
        save()
        checkStatus(for: server)
    }

    func update(_ server: Server) {
        guard let idx = servers.firstIndex(where: { $0.id == server.id }) else { return }
        servers[idx] = server
        save()
        checkStatus(for: server)
    }

    func remove(at offsets: IndexSet) {
        let sorted = offsets.sorted(by: >)
        for index in sorted {
            if servers.indices.contains(index) {
                servers.remove(at: index)
            }
        }
        save()
        updateLastUpdatedIfComplete()
    }

    func move(from source: IndexSet, to destination: Int) {
        let moving = source.sorted()
        var temp = servers
        let items = moving.map { temp[$0] }
        // Remove in reverse order to keep indices valid
        for index in moving.reversed() {
            temp.remove(at: index)
        }
        let insertIndex = min(max(destination, 0), temp.count)
        temp.insert(contentsOf: items, at: insertIndex)
        servers = temp
        save()
        updateLastUpdatedIfComplete()
    }
    
    func assign(serverID: UUID, toCategory category: String?) {
        guard let idx = servers.firstIndex(where: { $0.id == serverID }) else { return }
        servers[idx].category = category
        save()
    }

    func moveWithinCategory(_ category: String?, from source: IndexSet, to destination: Int) {
        // Filter servers by category to get their indices
        let filteredIndices = servers.enumerated().compactMap { (i, s) -> Int? in
            let cat = (s.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? s.category : nil
            return cat == category ? i : nil
        }
        var indices = filteredIndices
        var items: [Server] = []
        for i in source.sorted() {
            if i < indices.count {
                items.append(servers[indices[i]])
            }
        }
        // Remove selected items from servers using their original indices in reverse
        for i in source.sorted(by: >) {
            let originalIndex = indices[i]
            servers.remove(at: originalIndex)
            indices.remove(at: i)
        }
        // Compute the insertion index in the full servers array
        let insertInFiltered = min(max(destination, 0), indices.count)
        let insertOriginalIndex: Int = insertInFiltered < indices.count ? indices[insertInFiltered] : (indices.last.map { $0 + 1 } ?? servers.endIndex)
        servers.insert(contentsOf: items, at: insertOriginalIndex)
        save()
    }

    func load() {
        if let data = UserDefaults.standard.data(forKey: storageKey) {
            do {
                let decoded = try JSONDecoder().decode([Server].self, from: data)
                self.servers = decoded
            } catch {
                print("Failed to decode servers: \(error)")
                self.servers = []
            }
        }
    }

    func save() {
        do {
            let data = try JSONEncoder().encode(servers)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("Failed to encode servers: \(error)")
        }
    }
    
    private func saveCategories() {
        if let data = try? JSONEncoder().encode(categories) {
            UserDefaults.standard.set(data, forKey: categoriesKey)
        }
    }
    
    /// Returns true if the given host string looks like a private IPv4 address (RFC1918)
    private func isPrivateIPv4(_ host: String) -> Bool {
        // quick IPv4 check
        let parts = host.split(separator: ".")
        guard parts.count == 4, parts.allSatisfy({ Int($0) != nil }) else { return false }
        if host.hasPrefix("10.") { return true }
        if host.hasPrefix("192.168.") { return true }
        if parts.first == "172", let second = Int(parts.dropFirst().first ?? "") {
            return (16...31).contains(second)
        }
        return false
    }
    
    /// Call this when the app becomes active (e.g., from scenePhase == .active)
    func handleAppDidBecomeActive() {
        let now = Date()
        // Debounce: ignore if we handled a resume very recently
        if now.timeIntervalSince(lastResumeHandledAt) < resumeDebounceInterval { return }
        lastResumeHandledAt = now

        // Mark private LAN hosts as unknown to avoid showing stale "online" when off-LAN
        for server in servers {
            if isPrivateIPv4(server.host) {
                statuses[server.id] = .unknown
            }
        }
        // Trigger a fresh round of checks
        refreshAllStatuses()
    }

    func refreshAllStatuses() {
        let now = Date()
        if now.timeIntervalSince(lastRefreshAt) < 1 { return }
        lastRefreshAt = now
        for server in servers {
            checkStatus(for: server)
        }
        updateLastUpdatedIfComplete()
    }

    func checkStatus(for server: Server) {
        statuses[server.id] = .unknown
        updateLastUpdatedIfComplete()
        tcpAttempt(server: server, attempt: 1)
    }

    private func tcpAttempt(server: Server, attempt: Int) {
        // Validate port safely
        guard let port = NWEndpoint.Port(rawValue: UInt16(server.port)) else {
            statuses[server.id] = .offline
            updateLastUpdatedIfComplete()
            return
        }

        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.connectionTimeout = Int(timeoutSeconds)
        tcpOptions.enableFastOpen = false
        let params = NWParameters(tls: nil, tcp: tcpOptions)

        let endpoint = NWEndpoint.hostPort(host: .init(server.host), port: port)
        let conn = NWConnection(to: endpoint, using: params)

        // This flag is only accessed on the main actor via Task { @MainActor in }
        var didResolve = false

        conn.stateUpdateHandler = { state in
            Task { @MainActor in
                switch state {
                case .ready:
                    didResolve = true
                    self.statuses[server.id] = .online
                    self.updateLastUpdatedIfComplete()
                    conn.cancel()
                case .failed, .cancelled:
                    if !didResolve {
                        if attempt < 2 {
                            // retry once after short backoff on main actor context
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 500_000_000)
                                self.tcpAttempt(server: server, attempt: attempt + 1)
                            }
                        } else {
                            self.statuses[server.id] = .offline
                            self.updateLastUpdatedIfComplete()
                        }
                    }
                    conn.cancel()
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .utility))

        // Timeout after timeoutSeconds seconds, rescheduling on main actor
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds) * 1_000_000_000)
            if !didResolve {
                conn.cancel()
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self.tcpAttempt(server: server, attempt: attempt + 1)
                } else {
                    self.statuses[server.id] = .offline
                    self.updateLastUpdatedIfComplete()
                }
            }
        }
    }
    
    func allCategoriesIncludingEmpty() -> [String] {
        let inUse = Set(servers.compactMap { s -> String? in
            let t = s.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.isEmpty ? nil : t
        })
        let union = Set(categories).union(inUse)
        return Array(union).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func addCategory(_ name: String) {
        let t = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        if !categories.contains(where: { $0.caseInsensitiveCompare(t) == .orderedSame }) {
            categories.append(t)
            categories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            saveCategories()
        }
    }

    func renameCategory(from old: String, to new: String) {
        let newT = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newT.isEmpty else { return }
        // Update list
        if let idx = categories.firstIndex(of: old) {
            categories[idx] = newT
            categories.sort { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            saveCategories()
        } else {
            addCategory(newT)
        }
        // Update servers
        for i in servers.indices {
            let t = servers[i].category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty && t.caseInsensitiveCompare(old) == .orderedSame {
                servers[i].category = newT
            }
        }
        save()
    }

    func deleteCategory(_ name: String) {
        // Remove from list
        categories.removeAll { $0.caseInsensitiveCompare(name) == .orderedSame }
        saveCategories()
        // Move servers to Uncategorised (nil)
        for i in servers.indices {
            let t = servers[i].category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !t.isEmpty && t.caseInsensitiveCompare(name) == .orderedSame {
                servers[i].category = nil
            }
        }
        save()
    }
}
