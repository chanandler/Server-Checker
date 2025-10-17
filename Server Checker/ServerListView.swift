import SwiftUI

struct ServerListView: View {
    @StateObject private var store = ServerStore()
    @State private var showingAdd = false
    @State private var showingAbout = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 6) {
                        HStack {
                            Text("Devices Responding")
                            Spacer()
                            Text("\(store.servers.filter { (store.statuses[$0.id] ?? .unknown) == .online }.count)")
                                .bold()
                                .foregroundStyle(.green)
                        }
                        HStack {
                            Text("Devices Not Responding")
                            Spacer()
                            HStack(spacing: 6) {
                                Text("\(store.servers.filter { let s = (store.statuses[$0.id] ?? .unknown); return s == .offline || s == .unknown }.count)")
                                    .bold()
                                    .foregroundStyle(.red)
                                let unknownCount = store.servers.filter { (store.statuses[$0.id] ?? .unknown) == .unknown }.count
                                if unknownCount > 0 {
                                    Text("\(unknownCount) unk")
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
                    .font(.subheadline)
                    .padding(.vertical, 6)
                }
                Section {
                    Text("Tap the + to add a server. To delete a server, swipe the entry to the left and choose delete.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .padding(.vertical, 4)
                }
                ForEach(store.servers) { server in
                    ServerRow(
                        server: server,
                        status: store.statuses[server.id] ?? .unknown
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        store.checkStatus(for: server)
                    }
                }
                .onDelete(perform: store.remove)
                .onMove(perform: store.move)
            }
            .listStyle(.plain)
            .listRowSpacing(4)
            .environment(\.defaultMinListRowHeight, 34)
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
                        showingAbout = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("About")
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
            .sheet(isPresented: $showingAbout) {
                let shortVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? ""
                let versionText = build.isEmpty ? shortVersion : "\(shortVersion) (\(build))"
                VStack(spacing: 16) {
                    Text("Server Monitor v\(versionText)")
                        .font(.headline)
                    Text("A small utlity that lets you quickly check whether a device is active and online on the network that your device is currently connected to.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("The application will automatically refresh itself every 15 seconds. We will be adding more feature to the app in the future, if you have anything you'd like to suggest, please open an issue on [GitHub](https://github.com/b3ll/ServerMonitor)")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                    Text("The app is free, if you like it, consider giving a star on GitHub!")
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

#Preview {
    ServerListView()
}
