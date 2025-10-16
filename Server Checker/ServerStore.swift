import Foundation
import Combine
import Network

@MainActor
final class ServerStore: ObservableObject {
    @Published private(set) var servers: [Server] = []
    @Published var statuses: [UUID: ServerStatus] = [:]

    private let storageKey = "saved_servers_v1"
    private var lastRefreshAt: Date = .distantPast

    init() {
        load()
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
        attemptCheck(server: server, attempt: 1)
    }

    private func attemptCheck(server: Server, attempt: Int) {
        let params = NWParameters.tcp
        let endpoint = NWEndpoint.hostPort(
            host: .init(server.host),
            port: .init(integerLiteral: NWEndpoint.Port.IntegerLiteralType(server.port))
        )
        let conn = NWConnection(to: endpoint, using: params)

        let timeout: TimeInterval = 5
        var didResolve = false

        conn.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                guard let self else { return }
                switch state {
                case .ready:
                    didResolve = true
                    self.statuses[server.id] = .online
                    conn.cancel()
                case .failed, .cancelled:
                    // Only mark offline if we're out of retries
                    if attempt >= 2 && !didResolve {
                        self.statuses[server.id] = .offline
                    }
                default:
                    break
                }
            }
        }

        conn.start(queue: .global(qos: .utility))

        // Timeout handler
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                if !didResolve {
                    conn.cancel()
                    if attempt < 2 {
                        // Retry with small backoff
                        DispatchQueue.global().asyncAfter(deadline: .now() + 0.8) { [weak self] in
                            self?.attemptCheck(server: server, attempt: attempt + 1)
                        }
                    } else {
                        self.statuses[server.id] = .offline
                    }
                }
            }
        }
    }
}
