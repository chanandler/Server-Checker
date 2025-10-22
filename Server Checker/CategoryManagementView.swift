import SwiftUI

struct CategoryManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: ServerStore
    @Environment(\.horizontalSizeClass) private var hSize

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
                            .submitLabel(.done)
                            .onSubmit { addCategory() }
                            .textFieldStyle(.roundedBorder)
                        Button(action: addCategory) { Text("Add") }
                            .buttonStyle(.borderedProminent)
                            .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }

                Section("Categories") {
                    let cats = store.allCategoriesIncludingEmpty()
                    ForEach(cats, id: \.self) { cat in
                        VStack(alignment: .leading, spacing: 8) {
                            if renamingCategory == cat {
                                VStack(alignment: .leading, spacing: 8) {
                                    TextField("New name", text: $renameText)
                                        .textInputAutocapitalization(.words)
                                        .textFieldStyle(.roundedBorder)
                                    HStack(spacing: 12) {
                                        Button("Save") { saveRename(original: cat) }
                                            .buttonStyle(.borderedProminent)
                                            .disabled(renameText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                        Button("Cancel") { cancelRename() }
                                            .buttonStyle(.bordered)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            } else {
                                VStack(alignment: .leading, spacing: 8) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(cat)
                                            .font(.body)
                                            .lineLimit(nil)
                                            .multilineTextAlignment(.leading)
                                            .minimumScaleFactor(0.9)
                                        Text("\(count(for: cat)) server\(count(for: cat) == 1 ? "" : "s")")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 12) {
                                        Button("Rename") {
                                            renamingCategory = cat
                                            renameText = cat
                                        }
                                        .buttonStyle(.bordered)
                                        Button(role: .destructive) {
                                            categoryToDelete = cat
                                            showDeleteConfirm = true
                                        } label: {
                                            Text("Delete")
                                        }
                                        .buttonStyle(.bordered)
                                    }
                                }
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                        .contentShape(Rectangle())
                    }
                }
            }
            .navigationTitle("Categories")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .environment(\.defaultMinListRowHeight, 52)
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
