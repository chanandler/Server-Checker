import SwiftUI

struct AddEditServerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var port: Int = 80

    var server: Server?
    var onSave: (Server) -> Void

    init(server: Server? = nil, onSave: @escaping (Server) -> Void) {
        self.server = server
        self.onSave = onSave
        _name = State(initialValue: server?.name ?? "")
        _host = State(initialValue: server?.host ?? "")
        _port = State(initialValue: server?.port ?? 80)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("IP or Hostname", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    Stepper(value: $port, in: 1...65535) {
                        HStack {
                            Text("Port")
                            Spacer()
                            Text("\(port)")
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle(server == nil ? "Add Server" : "Edit Server")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!isValid)
                }
            }
        }
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !host.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private func save() {
        var result = Server(name: name.trimmingCharacters(in: .whitespaces), host: host.trimmingCharacters(in: .whitespaces), port: port)
        if let existing = server { result.id = existing.id }
        onSave(result)
        dismiss()
    }
}

#Preview {
    AddEditServerView { _ in }
}
