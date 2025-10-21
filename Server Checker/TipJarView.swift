import SwiftUI
import StoreKit

struct TipJarView: View {
    @StateObject private var model = TipJarViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Support the App")
                    .font(.title.bold())
                    .padding(.top)

                Text("If you enjoy using this app, consider leaving a tip. It helps keep the lights on and is much appreciated!")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                if model.isLoading {
                    ProgressView()
                        .padding(.vertical)
                } else if model.products.isEmpty {
                    ContentUnavailableView("Tips unavailable", systemImage: "cart", description: Text("Couldn’t load products. Please try again later."))
                } else {
                    VStack(spacing: 12) {
                        ForEach(model.products, id: \.id) { product in
                            Button {
                                Task { await model.buy(product) }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: iconName(for: product))
                                        .font(.title2)
                                        .frame(width: 28)

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(product.displayName)
                                            .font(.headline)
                                        Text(product.description)
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(product.displayPrice)
                                        .font(.headline)
                                }
                                .padding()
                                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                }

                if let msg = model.lastMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                        .transition(.opacity)
                }

                Spacer(minLength: 24)
            }
            .padding(.horizontal)
        }
        .navigationTitle("Tip Jar")
        .toolbarTitleDisplayMode(.inline)
    }

    private func iconName(for product: Product) -> String {
        switch product.id {
        case "tip.cookie.199": return "cookie"
        case "tip.coffee.299": return "cup.and.saucer.fill"
        case "tip.lunch.499": return "fork.knife"
        default: return "gift"
        }
    }
}

#Preview {
    NavigationStack {
        TipJarView()
    }
}
