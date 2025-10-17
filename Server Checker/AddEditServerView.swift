import SwiftUI

struct AddEditServerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var host: String = ""
    @State private var portText: String = "80"

    @State private var selectedCategory: String = ""
    @State private var isCreatingNewCategory: Bool = false
    @State private var newCategoryName: String = ""
    var existingCategories: [String] = []

    var server: Server?
    var onSave: (Server) -> Void

    init(server: Server? = nil, existingCategories: [String] = [], onSave: @escaping (Server) -> Void) {
        self.server = server
        self.existingCategories = existingCategories
        self.onSave = onSave
        _name = State(initialValue: server?.name ?? "")
        _host = State(initialValue: server?.host ?? "")
        _portText = State(initialValue: String(server?.port ?? 80))
        let cat = server?.category ?? ""
        _selectedCategory = State(initialValue: cat)
        _isCreatingNewCategory = State(initialValue: false)
        _newCategoryName = State(initialValue: "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                    TextField("IP or Hostname", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                    HStack {
                        Text("Port")
                        Spacer()
                        TextField("Port", text: $portText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 100)
                            .onChange(of: portText) { old, new in
                                // Keep only digits
                                let filtered = new.filter { $0.isNumber }
                                if filtered != new { portText = filtered }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                // Show hint if out of range
                                if let p = Int(portText), !(1...65535).contains(p) {
                                    Text("1–65535")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                    }
                }
                Section("Category") {
                    Picker("Category", selection: $selectedCategory) {
                        Text("Uncategorised").tag("")
                        ForEach(existingCategories.sorted(), id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                        Text("New Category…").tag("__new__")
                    }
                    .onChange(of: selectedCategory) { old, newValue in
                        isCreatingNewCategory = (newValue == "__new__")
                    }
                    if isCreatingNewCategory {
                        TextField("New category name", text: $newCategoryName)
                            .textInputAutocapitalization(.words)
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
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedHost = host.trimmingCharacters(in: .whitespaces)
        let p = Int(portText) ?? 0
        let creating = isCreatingNewCategory
        let newCatOK = !newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty || !creating
        return !trimmedName.isEmpty && !trimmedHost.isEmpty && (1...65535).contains(p) && newCatOK
    }

    private func save() {
        let p = min(max(Int(portText) ?? 80, 1), 65535)
        let chosenCategory: String? = {
            if isCreatingNewCategory {
                let t = newCategoryName.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            } else {
                let t = selectedCategory.trimmingCharacters(in: .whitespaces)
                return t.isEmpty ? nil : t
            }
        }()
        var result = Server(name: name.trimmingCharacters(in: .whitespaces), host: host.trimmingCharacters(in: .whitespaces), port: p, category: chosenCategory)
        if let existing = server { result.id = existing.id }
        onSave(result)
        dismiss()
    }
}

#Preview {
    AddEditServerView(existingCategories: ["Home", "Office"]) { _ in }
}
