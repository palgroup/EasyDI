/// Registers a type as the provider of a contract, with no list to keep.
///
/// ```swift
/// @Injectable(as: NoteService.self, .weak)
/// final class LiveNoteService: NoteService {
///     @Inject private var http: any HTTPClient
/// }
/// ```
///
/// Whatever asks for `any NoteService` with ``Inject`` gets a `LiveNoteService`,
/// built with `init()`. The type must conform to the contract; the compiler checks it.
/// One provider per contract: a second one stops the app, naming both, the first
/// time the contract is asked for.
@attached(member, names: named(__easyDIRecord), named(__EasyDIRecord))
public macro Injectable(as contract: Any.Type, _ lifetime: Lifetime = .singleton) =
    #externalMacro(module: "EasyDIMacros", type: "InjectableMacro")

/// Registers a type as the provider of itself: `@Inject private var clock: Clock`.
@attached(member, names: named(__easyDIRecord), named(__EasyDIRecord))
public macro Injectable(_ lifetime: Lifetime = .singleton) =
    #externalMacro(module: "EasyDIMacros", type: "InjectableMacro")

/// Registers a mock of a contract, for previews and tests.
///
/// ```swift
/// @Mock(NoteService.self)                       // the default mock
/// final class MockNoteService: NoteService {
///     @Mock(NoteService.self, "failing")        // a named one
///     static var failing: MockNoteService { MockNoteService(scenario: .failing) }
/// }
/// ```
///
/// A preview with nothing selected uses the default mock (the provider if there is
/// none); `.mock("failing")` picks a named one for a screen and everything it opens.
/// The app never uses a mock unless it is selected.
@attached(peer, names: prefixed(__easyDIMock_), prefixed(__EasyDIMock_))
public macro Mock(_ contract: Any.Type, _ name: String? = nil) =
    #externalMacro(module: "EasyDIMacros", type: "MockMacro")
