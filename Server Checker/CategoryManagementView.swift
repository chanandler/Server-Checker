import SwiftUI

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ServerStore

    @State private var newCategory: String = ""
    @State private var renamingCategory: String? = nil
    @State private var renameText: String = ""
    @State private var categoryToDelete: String? = nil
    @State private var showDeleteConfirm: Bool = false

    var body: some View {
        NavigationStack {
            List {
                Section("Add Category") {
                    HStack {
                        TextField("Category name", text: $newCategory)
                            .textInputAutocapitalization(.words)
                        Button("Add") { addCategory() }
                            .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Categories") {
                    let cats = store.allCategoriesIncludingEmpty()
                    ForEach(cats, id: \.self) { cat in
                        HStack {
                            if renamingCategory == cat {
                                TextField("New name", text: $renameText)
                                    .textInputAutocapitalization(.words)
                                Spacer()
                                Button("Save") { saveRename(original: cat) }
                                    .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                Button("Cancel") { cancelRename() }
                                    .foregroundStyle(.secondary)
                            } else {
                                VStack(alignment: .leading) {
                                    Text(cat)
                                    Text("\(count(for: cat)) server\(count(for: cat) == 1 ? "" : "s")")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Button("Rename") {
                                    renamingCategory = cat
                                    renameText = cat
                                }
                                .buttonStyle(.borderless)
                                Button(role: .destructive) {
                                    categoryToDelete = cat
                                    showDeleteConfirm = true
                                } label: {
                                    Text("Delete")
                                }
                                .buttonStyle(.borderless)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Delete Category?", isPresented: $showDeleteConfirm, presenting: categoryToDelete) { cat in
                Button("Delete", role: .destructive) { store.deleteCategory(cat) }
                Button("Cancel", role: .cancel) { }
            } message: { cat in
                Text("This will move all servers in \"\(cat)\" to Uncategorised.")
            }
        }
    }

    private func addCategory() {
        let t = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.addCategory(t)
        newCategory = ""
    }

    private func cancelRename() {
        renamingCategory = nil
        renameText = ""
    }

    private func saveRename(original: String) {
        let t = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        store.renameCategory(from: original, to: t)
        cancelRename()
    }

    private func count(for category: String) -> Int {
        store.servers.filter { s in
            let t = s.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return t.caseInsensitiveCompare(category) == .orderedSame
        }.count
    }
}

#Preview {
    CategoryManagementView()
        .environmentObject(ServerStore())
}
