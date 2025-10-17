import Foundation
import Combine
import Network
import SwiftUI

@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published var statuses: [UUID: ServerStatus] = [:]

    private let storageKey = "saved_servers_v1"
    private var lastRefreshAt: Date = .distantPast
    private var refreshTimer: Timer?

    init() {
        load()
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

    func refreshAllStatuses() {
        let now = Date()
        if now.timeIntervalSince(lastRefreshAt) < 1 { return }
        lastRefreshAt = now
        for server in servers {
            checkStatus(for: server)
        }
    }

    func checkStatus(for server: Server) {
        statuses[server.id] = .unknown
        tcpAttempt(server: server, attempt: 1)
    }

    private func tcpAttempt(server: Server, attempt: Int) {
        // Validate port safely
        guard let port = NWEndpoint.Port(rawValue: UInt16(server.port)) else {
            statuses[server.id] = .offline
            return
        }

        let params = NWParameters.tcp
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
                        }
                    }
                    conn.cancel()
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .utility))

        // Timeout after 3 seconds, rescheduling on main actor
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !didResolve {
                conn.cancel()
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    self.tcpAttempt(server: server, attempt: attempt + 1)
                } else {
                    self.statuses[server.id] = .offline
                }
            }
        }
    }
}
