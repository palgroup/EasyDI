extension Injection {
    /// Which mocks and instances answer for their contracts in a scope.
    ///
    /// Made with ``mock(_:)``, ``mock(_:for:)``, ``inject(_:)`` and ``inject(_:as:)``;
    /// SwiftUI's modifiers of the same names put one in the environment.
    public struct Selection: Hashable {
        /// Names for every contract that has a mock by that name; the last one wins.
        private var names: [String] = []
        private var namesByContract: [ObjectIdentifier: String] = [:]
        private(set) var instances: [ObjectIdentifier: Instance] = [:]

        public init() {}

        var isEmpty: Bool {
            names.isEmpty && namesByContract.isEmpty && instances.isEmpty
        }

        /// The mock named `name`, for every contract that has one by that name.
        /// The others keep their provider (or, in a preview, their default mock).
        @MainActor
        public static func mock(_ name: String) -> Selection {
            Container.shared.requireMock(named: name, for: nil, contractName: nil)
            var selection = Selection()
            selection.names = [name]
            return selection
        }

        /// The mock named `name`, for `contract` only.
        @MainActor
        public static func mock<Contract>(_ name: String, for contract: Contract.Type) -> Selection {
            let key = ObjectIdentifier(contract)
            Container.shared.requireMock(named: name, for: key, contractName: Self.name(of: contract))
            var selection = Selection()
            selection.namesByContract[key] = name
            return selection
        }

        /// `value` for the contract its type is registered for, with `@Injectable` or `@Mock`.
        @MainActor
        public static func inject<Value>(_ value: Value) -> Selection {
            var selection = Selection()
            selection.instances[Container.shared.contract(of: value)] = Instance(value)
            return selection
        }

        /// `value` for `contract`.
        public static func inject<Contract>(_ value: Contract, as contract: Contract.Type) -> Selection {
            var selection = Selection()
            selection.instances[ObjectIdentifier(contract)] = Instance(value)
            return selection
        }

        /// `other` on top of this one: its choices win.
        func merging(_ other: Selection) -> Selection {
            var merged = self
            merged.names += other.names
            merged.namesByContract.merge(other.namesByContract) { $1 }
            merged.instances.merge(other.instances) { $1 }
            return merged
        }

        @MainActor
        func mockName(for contract: ObjectIdentifier, among mocks: [AnyMock]) -> String? {
            if let name = namesByContract[contract] { return name }
            return names.last { name in mocks.contains { $0.name == name } }
        }

        @MainActor
        func replaces(_ contract: ObjectIdentifier, among mocks: [AnyMock]) -> Bool {
            instances[contract] != nil || mockName(for: contract, among: mocks) != nil
        }

        private static func name(of type: Any.Type) -> String {
            let name = String(describing: type)
            return name.hasPrefix("any ") ? String(name.dropFirst("any ".count)) : name
        }
    }

    /// An injected value. Two are the same while they are the same object (or, for a
    /// value type, an equal value), so a screen is rebuilt only when it changes.
    struct Instance: Hashable {
        let value: Any
        private let identity: AnyHashable

        init(_ value: Any) {
            self.value = value
            if type(of: value) is AnyClass {
                identity = ObjectIdentifier(value as AnyObject)
            } else if let hashable = value as? AnyHashable {
                identity = hashable
            } else {
                identity = ObjectIdentifier(type(of: value))
            }
        }

        static func == (lhs: Instance, rhs: Instance) -> Bool {
            lhs.identity == rhs.identity
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(identity)
        }
    }
}
