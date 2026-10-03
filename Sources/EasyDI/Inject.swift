/// A dependency, resolved by its type when the owner is initialised.
///
/// ```swift
/// @MainActor @Observable
/// final class NoteListData {
///     @ObservationIgnored @Inject private var notes: any NoteService
/// }
/// ```
///
/// The value comes from the selection in effect (``Injection/with(_:build:)``), then
/// from the default mock where those are used (previews, ``Injection/usesDefaultMocks``),
/// then from the `@Injectable` provider.
/// In an `@Observable` class the property needs `@ObservationIgnored`: it never changes.
@MainActor
@propertyWrapper
public struct Inject<Value> {
    public let wrappedValue: Value

    public init() {
        wrappedValue = Container.shared.resolve(Value.self)
    }
}
