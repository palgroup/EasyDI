/// Choosing mocks or instances, and what is registered.
public enum Injection {
    /// Builds `build` with `selections` in effect: what it injects, and what that
    /// injects in turn, comes from the selected mocks and instances.
    ///
    /// ```swift
    /// let data = Injection.with(.mock("failing")) { NoteListData() }
    /// ```
    ///
    /// A preview host builds its screen this way, so the screen's data gets the
    /// mock the preview names.
    @MainActor
    public static func with<Result>(_ selections: Selection..., build: () -> Result) -> Result {
        let container = Container.shared
        var selection = container.currentSelection
        for added in selections {
            selection = selection.merging(added)
        }
        return container.with(selection, build)
    }

    /// Whether a contract with a default mock gets it when nothing is selected for
    /// it. On in previews. Turn it on at launch, before anything is resolved, for UI
    /// tests that should see the mocks instead of the real services.
    @MainActor
    public static var usesDefaultMocks: Bool {
        get { Container.shared.usesDefaultMocks }
        set { Container.shared.usesDefaultMocks = newValue }
    }

    /// Every registered contract with its provider and mocks, sorted by contract.
    @MainActor
    public static var registrations: [Registration] {
        let container = Container.shared
        container.load()
        let contracts = Set(container.registered.keys).union(container.mocks.keys)
        return contracts.flatMap { contract -> [Registration] in
            let mocks = (container.mocks[contract] ?? []).map { $0.name ?? "default" }.sorted()
            let providers = container.registered[contract] ?? []
            guard !providers.isEmpty else {
                let name = container.mocks[contract]?.first?.contractName ?? "?"
                return [Registration(contract: name, provider: nil, lifetime: nil, mocks: mocks, isAlive: false, made: 0)]
            }
            return providers.map { provider in
                Registration(
                    contract: provider.contractName,
                    provider: provider.name,
                    lifetime: provider.lifetime,
                    mocks: mocks,
                    isAlive: provider.isAlive,
                    made: provider.made
                )
            }
        }
        .sorted { ($0.contract, $0.provider ?? "") < ($1.contract, $1.provider ?? "") }
    }
}

/// A registered contract: who provides it, how long the instance lives, and whether one is alive.
public struct Registration: Identifiable, Hashable, Sendable {
    public let contract: String
    /// `nil` when the contract has only mocks.
    public let provider: String?
    public let lifetime: Lifetime?
    /// `"default"` for the default mock, then the named ones.
    public let mocks: [String]
    /// An instance is kept right now: a built `.singleton`, or a `.weak` one something still holds.
    public let isAlive: Bool
    /// How many instances the provider has built so far.
    public let made: Int

    public var id: String { "\(contract)/\(provider ?? "")" }
}
