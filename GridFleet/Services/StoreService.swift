import Foundation
import GridFleetCore
import Observation
import StoreKit

/// Things you can buy.
enum Unlock: String, CaseIterable, Identifiable {
    /// Admiral AI, salvo, extra boards and special weapons.
    case admiral
    case oceans
    case hulls
    case blasts

    var id: String { rawValue }
    var productID: String { "com.leejustin.gridfleet.\(rawValue)" }

    var title: String {
        switch self {
        case .admiral: "Admiral's Commission"
        case .oceans: "Ocean Themes"
        case .hulls: "Hull Skins"
        case .blasts: "Blast FX"
        }
    }

    var pitch: String {
        switch self {
        case .admiral: "The Admiral AI, salvo mode, Skirmish and Open Ocean boards, and special weapons."
        case .oceans: "Abyss, Lagoon, Graph Paper and Arctic."
        case .hulls: "Brass, Stealth and Coral hulls."
        case .blasts: "Ink Cloud, Fireworks and 8-Bit explosions."
        }
    }

    var systemImage: String {
        switch self {
        case .admiral: "star.circle.fill"
        case .oceans: "water.waves"
        case .hulls: "paintbrush.pointed.fill"
        case .blasts: "flame.fill"
        }
    }

    /// The price shown when the App Store can't be reached.
    var fallbackPrice: String {
        switch self {
        case .admiral: "$2.99"
        case .oceans: "$1.99"
        case .hulls, .blasts: "$0.99"
        }
    }
}

@MainActor
@Observable
final class StoreService {
    private(set) var products: [Unlock: Product] = [:]
    private(set) var owned: Set<Unlock> = []
    private(set) var isLoading = false
    private(set) var lastError: String?
    /// Debug builds can unlock everything to test gated features.
    var unlockAllForTesting: Bool {
        didSet { UserDefaults.standard.set(unlockAllForTesting, forKey: "unlockAllForTesting") }
    }

    private var updatesTask: Task<Void, Never>?

    init() {
        #if DEBUG
        unlockAllForTesting = UserDefaults.standard.bool(forKey: "unlockAllForTesting")
        #else
        unlockAllForTesting = false
        #endif
    }

    func has(_ unlock: Unlock) -> Bool {
        unlockAllForTesting || owned.contains(unlock)
    }

    func start() async {
        guard updatesTask == nil else { return }
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self?.refreshEntitlements()
                }
            }
        }
        await loadProducts()
        await refreshEntitlements()
    }

    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await Product.products(for: Unlock.allCases.map(\.productID))
            var map: [Unlock: Product] = [:]
            for product in loaded {
                if let unlock = Unlock.allCases.first(where: { $0.productID == product.id }) { map[unlock] = product }
            }
            products = map
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var found: Set<Unlock> = []
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let transaction) = entitlement, transaction.revocationDate == nil,
               let unlock = Unlock.allCases.first(where: { $0.productID == transaction.productID }) {
                found.insert(unlock)
            }
        }
        owned = found
    }

    func price(of unlock: Unlock) -> String {
        products[unlock]?.displayPrice ?? unlock.fallbackPrice
    }

    /// Returns true if the purchase went through.
    @discardableResult
    func purchase(_ unlock: Unlock) async -> Bool {
        lastError = nil
        Analytics.shared.capture("purchase_started", ["item": .string(unlock.rawValue)])
        guard let product = products[unlock] else {
            lastError = "The App Store isn't available right now."
            return false
        }
        do {
            switch try await product.purchase() {
            case .success(let verification):
                guard case .verified(let transaction) = verification else {
                    lastError = "The purchase couldn't be verified."
                    return false
                }
                await transaction.finish()
                await refreshEntitlements()
                Analytics.shared.capture("purchase_completed", ["item": .string(unlock.rawValue)])
                return true
            case .pending, .userCancelled:
                Analytics.shared.capture("purchase_cancelled", ["item": .string(unlock.rawValue)])
                return false
            @unknown default:
                return false
            }
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
        } catch {
            lastError = error.localizedDescription
        }
        await refreshEntitlements()
    }

    // MARK: What each unlock gates

    func allows(_ difficulty: AIDifficulty) -> Bool { difficulty != .hard || has(.admiral) }
    func allows(_ preset: BoardPreset) -> Bool { preset == .classic || has(.admiral) }
    var allowsSalvo: Bool { has(.admiral) }
    var allowsSpecials: Bool { has(.admiral) }

    func allows(_ rules: GameRules) -> Bool {
        allows(rules.preset) && (rules.firing == .single || allowsSalvo) && (!rules.specialWeapons || allowsSpecials)
    }

    func allows(_ theme: Theme.ID) -> Bool { theme == .nightWatch || theme == .daybreak || has(.oceans) }
    func allows(_ skin: ShipSkin.ID) -> Bool { skin == .steel || has(.hulls) }
    func allows(_ blast: BlastStyle) -> Bool { blast == .fireball || has(.blasts) }
}
