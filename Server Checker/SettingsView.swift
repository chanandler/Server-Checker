import SwiftUI

struct TimeoutSettingsView: View {
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
                    Text("How long to wait for a server to respond before marking it offline. Shorter timeouts make the app feel snappier; longer timeouts may help on slow networks.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Connection Timeout")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    TimeoutSettingsView()
        .environmentObject(ServerStore())
}
