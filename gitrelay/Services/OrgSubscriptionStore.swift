import Foundation

@MainActor
final class OrgSubscriptionStore {
    private let defaults: UserDefaults
    private let preferencesKey = "OrgSubscription.preferences"
    private let subscriptionsKey = "OrgSubscription.subscriptions"

    var preferences: OrgSubscriptionPreferences {
        didSet {
            guard preferences != oldValue else { return }
            persistPreferences()
            onPreferencesChange?(preferences)
        }
    }

    private(set) var subscriptions: [OrgSubscription] {
        didSet {
            guard subscriptions != oldValue else { return }
            persistSubscriptions()
            onSubscriptionsChange?(subscriptions)
        }
    }

    var onPreferencesChange: ((OrgSubscriptionPreferences) -> Void)?
    var onSubscriptionsChange: (([OrgSubscription]) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: preferencesKey),
           let decoded = try? JSONDecoder().decode(OrgSubscriptionPreferences.self, from: data) {
            preferences = decoded
        } else {
            preferences = .default
        }
        if let data = defaults.data(forKey: subscriptionsKey),
           let decoded = try? JSONDecoder().decode([OrgSubscription].self, from: data) {
            subscriptions = decoded
        } else {
            subscriptions = []
        }
    }

    func add(_ subscription: OrgSubscription) {
        subscriptions.append(subscription)
    }

    func update(_ subscription: OrgSubscription) {
        guard let index = subscriptions.firstIndex(where: { $0.id == subscription.id }) else { return }
        subscriptions[index] = subscription
    }

    func remove(id: UUID) {
        subscriptions.removeAll { $0.id == id }
        deleteTargetToken(for: id)
    }

    func subscription(id: UUID) -> OrgSubscription? {
        subscriptions.first { $0.id == id }
    }

    func markChecked(id: UUID, at date: Date = Date()) {
        guard let index = subscriptions.firstIndex(where: { $0.id == id }) else { return }
        subscriptions[index].lastCheckedAt = date
    }

    static func targetTokenTag(for subscriptionID: UUID) -> String {
        "org-subscription-\(subscriptionID.uuidString)-target"
    }

    func saveTargetToken(_ token: String, for subscriptionID: UUID) throws {
        try KeychainService.saveToken(token, tag: Self.targetTokenTag(for: subscriptionID))
    }

    func loadTargetToken(for subscriptionID: UUID) -> String? {
        try? KeychainService.loadToken(tag: Self.targetTokenTag(for: subscriptionID))
    }

    func deleteTargetToken(for subscriptionID: UUID) {
        try? KeychainService.deleteToken(tag: Self.targetTokenTag(for: subscriptionID))
    }

    private func persistPreferences() {
        guard let data = try? JSONEncoder().encode(preferences) else { return }
        defaults.set(data, forKey: preferencesKey)
    }

    private func persistSubscriptions() {
        guard let data = try? JSONEncoder().encode(subscriptions) else { return }
        defaults.set(data, forKey: subscriptionsKey)
    }
}
