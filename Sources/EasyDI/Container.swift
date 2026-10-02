import Foundation
import Synchronization

/// Every registration, every instance kept, and the selections in effect.
///
/// Resolution happens on the main actor, synchronously, while the owner of an
/// ``Inject`` property is initialised. That is what lets a provider's own
/// dependencies be checked while it is built (cycles, a `.singleton` taking a `.weak`),
/// and what lets ``Injected`` apply a screen's selection while the screen's data is made.
@MainActor
final class Container {
    static let shared = Container()

    /// An instance being built, and what its building asked for.
    private struct Frame {
        /// The provider or mock being built.
        let id: ObjectIdentifier
        let name: String
        let lifetime: Lifetime
        /// Every contract resolved while it was built, its dependencies' too.
        var dependencies: Set<ObjectIdentifier> = []
        /// It took a value only a selection gives, so it can't be shared with the rest of the app.
        var usedSelection = false
    }

    /// Everything registered for a contract. More than one provider is an error,
    /// reported when the contract is first asked for.
    private(set) var registered: [ObjectIdentifier: [AnyProvider]] = [:]
    /// The provider of a contract, once it was asked for and found to be the only one.
    private var providers: [ObjectIdentifier: AnyProvider] = [:]
    private(set) var mocks: [ObjectIdentifier: [AnyMock]] = [:]
    private var contractsByType: [ObjectIdentifier: Set<ObjectIdentifier>] = [:]
    private var recordsRun = 0
    private var building: [Frame] = []
    private var selections: [Injection.Selection] = []

    /// Xcode sets this for the process that renders `#Preview`s.
    let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"

    private init() {
        Registry.start
    }

    // MARK: Registration

    // The same type registered again is the same provider, not a second one: a
    // preview that loads its code again brings that code's records again. The
    // newer record replaces the older.

    func add(_ provider: AnyProvider) {
        var known = registered[provider.contract] ?? []
        if let index = known.firstIndex(where: { $0.type == provider.type }) {
            known[index] = provider
        } else {
            known.append(provider)
        }
        registered[provider.contract] = known
        // Found again on the next request, which checks it is still the only one.
        providers[provider.contract] = nil
        contractsByType[provider.type, default: []].insert(provider.contract)
    }

    func add(_ mock: AnyMock) {
        var known = mocks[mock.contract] ?? []
        if let index = known.firstIndex(where: { $0.name == mock.name && $0.label == mock.label && $0.type == mock.type }) {
            known[index] = mock
        } else {
            known.append(mock)
        }
        mocks[mock.contract] = known
        if let type = mock.type {
            contractsByType[type, default: []].insert(mock.contract)
        }
    }

    /// Runs the records found since the last call.
    func load() {
        guard Registry.found.load(ordering: .acquiring) != recordsRun else { return }
        let addresses = Registry.pending.withLock { pending in
            defer { pending.removeAll() }
            return pending
        }
        recordsRun += addresses.count
        for address in addresses {
            unsafeBitCast(address, to: Registry.Record.self)()
        }
    }

    // MARK: Resolution

    func resolve<Value>(_ type: Value.Type) -> Value {
        load()
        let key = ObjectIdentifier(type)
        if !building.isEmpty {
            for index in building.indices {
                building[index].dependencies.insert(key)
            }
        }
        if let answer = selections.last?.answer(for: key, among: mocks[key] ?? []) {
            markSelectionUsed()
            switch answer {
            case .instance(let value): return cast(value)
            case .mock(let name): return mock(key, named: name)
            }
        }
        if isPreview, mocks[key]?.contains(where: { $0.name == nil }) == true {
            return mock(key, named: nil)
        }
        let provider: Provider<Value> = provider(for: key)
        if provider.lifetime == .weak {
            requireNotCaptive(provider.name)
        }
        return instance(of: provider)
    }

    /// What holds a `.weak` instance must not live for the whole app. A `.transient`
    /// in between doesn't change that: the `.singleton` keeps it, and it keeps the
    /// `.weak` one.
    private func requireNotCaptive(_ name: String) {
        guard let index = building.lastIndex(where: { $0.lifetime != .transient }),
              building[index].lifetime == .singleton else { return }
        let owner = building[index].name
        let between = building[(index + 1)...].map(\.name)
        let through = between.isEmpty ? "" : " through \(between.joined(separator: " → "))"
        assertionFailure(
            "EasyDI: \(owner) is a .singleton, it lives as long as the app, but\(through) it takes \(name), which is .weak: it would never be released. Make \(name) .singleton or \(owner) .weak."
        )
    }

    private func provider<Value>(for key: ObjectIdentifier) -> Provider<Value> {
        // A provider is registered under the identifier of its contract's type,
        // so the one found for `Value` is a `Provider<Value>`.
        if let provider = providers[key] {
            return unsafeDowncast(provider, to: Provider<Value>.self)
        }
        let options = registered[key] ?? []
        if options.count > 1 {
            let contract = options[0].contractName
            let names = options.map(\.name).joined(separator: ", ")
            fatalError("EasyDI: \(contract) has \(options.count) providers: \(names). Keep one @Injectable(as: \(contract).self).")
        }
        guard let provider = options.first else {
            let contract = name(of: Value.self)
            let onlyMocks = mocks[key].map { _ in " Its mocks are used only in previews and under .mock(…)." } ?? ""
            fatalError("EasyDI: nothing provides \(contract). Mark the type that does with @Injectable(as: \(contract).self).\(onlyMocks)")
        }
        providers[key] = provider
        return unsafeDowncast(provider, to: Provider<Value>.self)
    }

    private func instance<Value>(of provider: Provider<Value>) -> Value {
        // A selection that replaces a dependency of a kept instance gets one of its
        // own, which isn't kept: the app's instance stays the app's.
        let reached = !selections.isEmpty && selectionReaches(provider.dependencies)
        switch provider.lifetime {
        case .singleton:
            if let kept = provider.kept, !reached { return kept }
            let (value, usedSelection) = build(provider)
            if !usedSelection, !reached { provider.kept = value }
            return value
        case .weak:
            if let shared = provider.shared, !reached { return cast(shared) }
            let (value, usedSelection) = build(provider)
            if !usedSelection, !reached { provider.shared = value as AnyObject }
            return value
        case .transient:
            return build(provider).value
        }
    }

    private func build<Value>(_ provider: Provider<Value>) -> (value: Value, usedSelection: Bool) {
        let frame = building(ObjectIdentifier(provider), named: provider.name, lifetime: provider.lifetime) {
            provider.make()
        }
        // Every contract it was ever seen to ask for: a build that skipped one
        // (an `if` in an initialiser) must not hide it from a later selection.
        if !frame.dependencies.isEmpty {
            provider.dependencies.formUnion(frame.dependencies)
        }
        provider.made += 1
        return (frame.value, frame.usedSelection)
    }

    /// Runs `make` as the innermost thing being built, stopping on a cycle.
    private func building<Value>(
        _ id: ObjectIdentifier,
        named name: String,
        lifetime: Lifetime,
        _ make: () -> Value
    ) -> (value: Value, dependencies: Set<ObjectIdentifier>, usedSelection: Bool) {
        if let start = building.firstIndex(where: { $0.id == id }) {
            let path = (building[start...].map(\.name) + [name]).joined(separator: " → ")
            fatalError("EasyDI: \(path) is a cycle: each one needs the next to be built. Break it, for example by passing one of them in as a parameter.")
        }
        building.append(Frame(id: id, name: name, lifetime: lifetime))
        let value = make()
        let frame = building.removeLast()
        return (value, frame.dependencies, frame.usedSelection)
    }

    private func mock<Value>(_ contract: ObjectIdentifier, named name: String?) -> Value {
        let candidates = (mocks[contract] ?? []).filter { $0.name == name }
        guard let found = candidates.first else {
            preconditionFailure("EasyDI: a mock was resolved without being found first.")
        }
        if candidates.count > 1 {
            let labels = candidates.map(\.label).joined(separator: " and ")
            let what = name.map { "two mocks named \"\($0)\"" } ?? "two default mocks"
            fatalError("EasyDI: \(found.contractName) has \(what): \(labels). Keep one.")
        }
        let mock = unsafeDowncast(found, to: Mock<Value>.self)
        let reached = !selections.isEmpty && selectionReaches(mock.dependencies)
        if let shared = mock.shared, !reached { return cast(shared) }
        // Shared while something holds it, like a `.weak` provider; a value type is made each time.
        let frame = building(ObjectIdentifier(mock), named: mock.label, lifetime: .weak) {
            mock.make()
        }
        if !frame.dependencies.isEmpty {
            mock.dependencies.formUnion(frame.dependencies)
        }
        if !frame.usedSelection, !reached, Swift.type(of: frame.value as Any) is AnyClass {
            mock.shared = frame.value as AnyObject
        }
        return frame.value
    }

    // MARK: Selection

    func with<Result>(_ selection: Injection.Selection, _ build: () -> Result) -> Result {
        guard !selection.isEmpty else { return build() }
        selections.append(selection)
        defer { selections.removeLast() }
        return build()
    }

    var currentSelection: Injection.Selection {
        selections.last ?? Injection.Selection()
    }

    /// Whatever is being built took a selected value: none of it is kept for the app.
    private func markSelectionUsed() {
        for index in building.indices {
            building[index].usedSelection = true
        }
    }

    /// Whether the current selection replaces one of `dependencies`.
    private func selectionReaches(_ dependencies: Set<ObjectIdentifier>) -> Bool {
        guard let selection = selections.last, !dependencies.isEmpty else { return false }
        return dependencies.contains { selection.answer(for: $0, among: mocks[$0] ?? []) != nil }
    }

    func requireMock(named name: String, for contract: ObjectIdentifier?, contractName: String?) {
        load()
        let candidates = contract.map { mocks[$0] ?? [] } ?? mocks.values.flatMap { $0 }
        guard !candidates.contains(where: { $0.name == name }) else { return }
        let known = Set(candidates.compactMap(\.name)).sorted().map { "\"\($0)\"" }
        let scope = contractName.map { " for \($0)" } ?? ""
        let list = known.isEmpty ? "There are no named mocks\(scope)." : "Named mocks\(scope): \(known.joined(separator: ", "))."
        fatalError("EasyDI: .mock(\"\(name)\") — no mock\(scope) is named \"\(name)\". \(list)")
    }

    func contract(of value: Any) -> ObjectIdentifier {
        load()
        let type = Swift.type(of: value)
        let contracts = contractsByType[ObjectIdentifier(type)] ?? []
        guard contracts.count == 1, let contract = contracts.first else {
            let reason = contracts.isEmpty
                ? "\(type) isn't marked @Injectable or @Mock, so it isn't known what it stands for"
                : "\(type) stands for \(contracts.count) contracts"
            fatalError("EasyDI: .inject(\(type)) — \(reason). Name the contract: .inject(value, as: Contract.self).")
        }
        return contract
    }

    private func cast<Value>(_ value: Any) -> Value {
        guard let value = value as? Value else {
            fatalError("EasyDI: \(Swift.type(of: value)) was given for \(name(of: Value.self)) but isn't one.")
        }
        return value
    }

    private func name(of type: Any.Type) -> String {
        let name = String(describing: type)
        return name.hasPrefix("any ") ? String(name.dropFirst("any ".count)) : name
    }
}

/// A registered provider, without the type of its contract.
@MainActor
class AnyProvider {
    let contract: ObjectIdentifier
    let contractName: String
    let type: ObjectIdentifier
    let name: String
    let lifetime: Lifetime
    /// Every contract resolved while it was last built, its dependencies' too.
    var dependencies: Set<ObjectIdentifier> = []
    var made = 0

    var isAlive: Bool { false }

    init(contract: ObjectIdentifier, contractName: String, type: ObjectIdentifier, name: String, lifetime: Lifetime) {
        self.contract = contract
        self.contractName = contractName
        self.type = type
        self.name = name
        self.lifetime = lifetime
    }
}

/// A provider and the instance it keeps, typed as the contract: a kept instance
/// is handed out with no cast.
@MainActor
final class Provider<Contract>: AnyProvider {
    let make: @MainActor @Sendable () -> Contract
    /// The `.singleton` instance.
    var kept: Contract?
    /// The `.weak` instance, while something holds it.
    weak var shared: AnyObject?

    override var isAlive: Bool { kept != nil || shared != nil }

    init(
        contract: ObjectIdentifier,
        contractName: String,
        type: ObjectIdentifier,
        name: String,
        lifetime: Lifetime,
        make: @escaping @MainActor @Sendable () -> Contract
    ) {
        self.make = make
        super.init(contract: contract, contractName: contractName, type: type, name: name, lifetime: lifetime)
    }
}

/// A registered mock, without the type of its contract.
@MainActor
class AnyMock {
    let contract: ObjectIdentifier
    let contractName: String
    /// `nil` for the default mock.
    let name: String?
    /// The mock's type, when it is known, so `.inject(instance)` can find the contract.
    let type: ObjectIdentifier?
    /// How a message names it: `MockNoteService` or `MockNoteService.failing`.
    let label: String
    /// Every contract resolved while it was built, its dependencies' too.
    var dependencies: Set<ObjectIdentifier> = []

    init(contract: ObjectIdentifier, contractName: String, name: String?, type: ObjectIdentifier?, label: String) {
        self.contract = contract
        self.contractName = contractName
        self.name = name
        self.type = type
        self.label = label
    }
}

@MainActor
final class Mock<Contract>: AnyMock {
    let make: @MainActor @Sendable () -> Contract
    weak var shared: AnyObject?

    init(
        contract: ObjectIdentifier,
        contractName: String,
        name: String?,
        type: ObjectIdentifier?,
        label: String,
        make: @escaping @MainActor @Sendable () -> Contract
    ) {
        self.make = make
        super.init(contract: contract, contractName: contractName, name: name, type: type, label: label)
    }
}
