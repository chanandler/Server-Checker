import Foundation
import StoreKit
import SwiftUI

#if DEBUG
import StoreKitTest
#endif

@MainActor
final class TipJarViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var lastMessage: String?

    // Replace these with your real product IDs from App Store Connect
    // Example: tip.cookie.199, tip.coffee.299, tip.lunch.499
    let productIDs: [String] = [
        "tip.cookie.199",
        "tip.coffee.299",
        "tip.lunch.499"
    ]

    #if DEBUG
    private var skTestSession: SKTestSession?
    #endif

    init() {
        #if DEBUG
        setupStoreKitTestSession()
        #endif
        Task { await loadProducts() }
        Task { await observeTransactions() }
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let storeProducts = try await Product.products(for: productIDs)
            // Preserve the order of productIDs
            products = productIDs.compactMap { id in storeProducts.first { $0.id == id } }
        } catch {
            lastMessage = "Failed to load tips: \(error.localizedDescription)"
        }
    }

    func buy(_ product: Product) async {
        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    lastMessage = "Thanks for the support! 🎉"
                } else {
                    lastMessage = "Purchase couldn’t be verified."
                }
            case .userCancelled:
                lastMessage = "Purchase cancelled."
            case .pending:
                lastMessage = "Purchase pending."
            @unknown default:
                lastMessage = "Unknown purchase state."
            }
        } catch {
            lastMessage = "Purchase failed: \(error.localizedDescription)"
        }
    }

    func observeTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }

    #if DEBUG
    private func setupStoreKitTestSession() {
        // Attempt to load a StoreKit Configuration named "TipJar" if present in the bundle
        guard let url = Bundle.main.url(forResource: "TipJar", withExtension: "storekit") else {
            // Not fatal: you can still use Sandbox or real products
            return
        }
        do {
            let session = try SKTestSession(configurationFileURL: url)
            // Reset to a clean state for each run
            session.resetToDefaultState()
            // You can tweak these as needed for testing flows
            session.disableDialogs = true
            session.clearTransactions()
            self.skTestSession = session
        } catch {
            // If configuration fails, continue without the test session
            print("SKTestSession setup failed: \(error)")
        }
    }
    #endif
}
