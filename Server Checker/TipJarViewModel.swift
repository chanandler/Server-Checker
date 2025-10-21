import Foundation
import StoreKit
import SwiftUI
import Combine

#if canImport(UIKit)
import UIKit
#endif

@MainActor
final class TipJarViewModel: ObservableObject {
    @Published var products: [Product] = []
    @Published var isLoading = false
    @Published var lastMessage: String?
    @Published var purchasingProductID: String?

    // Replace these with your real product IDs from App Store Connect
    // Example: tip.cookie.199, tip.coffee.299, tip.lunch.499
    let productIDs: [String] = [
        "tip.coffee.299"
    ]

    init() {
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
        // Prevent duplicate taps
        if purchasingProductID != nil { return }
        purchasingProductID = product.id
        lastMessage = nil
        defer { purchasingProductID = nil }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    #if canImport(UIKit)
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    #endif
                    lastMessage = "Thanks for the support! 🎉"
                } else {
                    lastMessage = "Purchase couldn’t be verified."
                }
            case .userCancelled:
                lastMessage = nil // User cancelled, no message needed
            case .pending:
                lastMessage = "Purchase pending."
            @unknown default:
                lastMessage = "Unknown purchase state."
            }
        } catch {
            lastMessage = "We couldn’t complete the purchase. Please try again in a moment."
        }
    }

    func observeTransactions() async {
        for await result in Transaction.updates {
            if case .verified(let transaction) = result {
                await transaction.finish()
            }
        }
    }
}

