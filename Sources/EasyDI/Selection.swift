extension Injection {
    /// Which mocks and instances answer for their contracts while something is built
    /// with ``Injection/with(_:build:)``.
    ///
    /// Made with ``mock(_:)``, ``mock(_:for:)``, ``inject(_:)`` and ``inject(_:as:)``.
    /// For each contract the innermost choice that applies to it wins.
    public struct Selection {
        private enum Choice {
            /// The mock with this name, for every contract that has one.
            case everywhere(String)
            /// The mock with this name, for one contract.
            case named(String, contract: ObjectIdentifier)
            case instance(Any, contract: ObjectIdentifier)
            /// The default mock, for every contract that has one.
            case defaults
        }

        /// What a selection gives for a contract.
        enum Answer {
            case instance(Any)
            /// `nil`: the contract's default mock.
            case mock(String?)
        }

        /// In the order they were made: outer first, so the last that applies wins.
        private var choices: [Choice] = []

        public init() {}

        /// Every contract's default mock, where it has one; the others keep their
        /// provider. What a preview gets by itself, for screens built inside the
        /// running app — a debug screen that shows mocked screens.
        @MainActor
        public static var defaultMocks: Selection {
            Selection(choices: [.defaults])
        }

        var isEmpty: Bool { choices.isEmpty }

        /// The mock named `name`, for every contract that has one by that name.
        /// The others keep their provider (or their default mock, where those are used).
        @MainActor
        public static func mock(_ name: String) -> Selection {
            Container.shared.requireMock(named: name, for: nil, contractName: nil)
            return Selection(choices: [.everywhere(name)])
        }

        /// The mock named `name`, for `contract` only.
        @MainActor
        public static func mock<Contract>(_ name: String, for contract: Contract.Type) -> Selection {
            let key = ObjectIdentifier(Contract.self)
            Container.shared.requireMock(named: name, for: key, contractName: Self.name(of: Contract.self))
            return Selection(choices: [.named(name, contract: key)])
        }

        /// `value` for the contract its type is registered for, with `@Injectable` or `@Mock`.
        @MainActor
        public static func inject<Value>(_ value: Value) -> Selection {
            Selection(choices: [.instance(value, contract: Container.shared.contract(of: value))])
        }

        /// `value` for `contract`.
        public static func inject<Contract>(_ value: Contract, as contract: Contract.Type) -> Selection {
            Selection(choices: [.instance(value, contract: ObjectIdentifier(Contract.self))])
        }

        private init(choices: [Choice]) {
            self.choices = choices
        }

        /// `other` inside this one: where both choose for a contract, `other` wins.
        func merging(_ other: Selection) -> Selection {
            Selection(choices: choices + other.choices)
        }

        @MainActor
        func answer(for contract: ObjectIdentifier, among mocks: [AnyMock]) -> Answer? {
            for choice in choices.reversed() {
                switch choice {
                case .instance(let value, contract):
                    return .instance(value)
                case .named(let name, contract):
                    return .mock(name)
                case .everywhere(let name) where mocks.contains(where: { $0.name == name }):
                    return .mock(name)
                case .defaults where mocks.contains(where: { $0.name == nil }):
                    return .mock(nil)
                default:
                    continue
                }
            }
            return nil
        }

        private static func name(of type: Any.Type) -> String {
            let name = String(describing: type)
            return name.hasPrefix("any ") ? String(name.dropFirst("any ".count)) : name
        }
    }
}
