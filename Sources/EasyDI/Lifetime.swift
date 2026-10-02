/// How long the instance a provider makes is kept.
public enum Lifetime: Sendable, Hashable, CustomStringConvertible {
    /// One instance for the whole app, made the first time it is asked for. The default.
    case singleton
    /// One instance shared while something holds it; after the last holder goes
    /// away it is released, and the next request makes a new one. Classes only.
    case weak
    /// A new instance for every request.
    case transient

    public var description: String {
        switch self {
        case .singleton: "singleton"
        case .weak: "weak"
        case .transient: "transient"
        }
    }
}
