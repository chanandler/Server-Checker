import SwiftUI

struct ServerListView: View {
    @StateObject private var store = ServerStore()
    @State private var showingAdd = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Tap the + to add a server. To delete a server, swipe the entry t the left and choose delete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                ForEach(store.servers) { server in
                    ServerRow(server: server, status: store.statuses[server.id] ?? .unknown)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            store.checkStatus(for: server)
                        }
                }
                .onDelete(perform: store.remove)
                .onMove(perform: store.move)
            }
            .overlay {
                if store.servers.isEmpty {
                    ContentUnavailableView("No Servers", systemImage: "server.rack", description: Text("Add a server to begin"))
                }
            }
            .navigationTitle("Servers")
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
                        store.refreshAllStatuses()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .accessibilityLabel("Refresh")
                }
            }
            .onAppear {
                store.refreshAllStatuses()
            }
            .sheet(isPresented: $showingAdd) {
                AddEditServerView { newServer in
                    store.add(newServer)
                }
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
                .frame(width: 12, height: 12)
            VStack(alignment: .leading) {
                Text(server.name).font(.headline)
                Text("\(server.host):\(server.port)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if status == .unknown {
                ProgressView().controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }

    private func color(for status: ServerStatus) -> Color {
        switch status {
        case .online: return .green
        case .offline: return .red
        case .unknown: return .gray
        }
    }
}

#Preview {
    ServerListView()
}
