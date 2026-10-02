/// A dependency, resolved by its type when the owner is initialised.
///
/// ```swift
/// @MainActor @Observable
/// final class NoteListData {
///     @ObservationIgnored @Inject private var notes: any NoteService
/// }
/// ```
///
/// The value comes from the selection in effect (``Injected``, ``Injection/with(_:build:)``),
/// then, in a preview, from the default mock, then from the `@Injectable` provider.
/// In an `@Observable` class the property needs `@ObservationIgnored`: it never changes.
@MainActor
@propertyWrapper
public struct Inject<Value> {
    public let wrappedValue: Value

    public init() {
        wrappedValue = Container.shared.resolve(Value.self)
    }
}
