// The macro plugin builds for the machine that compiles, so these run on macOS only.
#if canImport(EasyDIMacros)
import EasyDIMacros
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing

private let macros: [String: MacroSpec] = [
    "Injectable": MacroSpec(type: InjectableMacro.self),
    "Mock": MacroSpec(type: MockMacro.self),
]

@Suite("Macro expansion")
struct MacroExpansionTests {
    @Test("@Injectable(as:_:) leaves a section record that builds the type as the contract")
    func injectable() {
        expand(
            """
            @Injectable(as: NoteService.self, .weak)
            final class LiveNoteService: NoteService {
            }
            """,
            into: """
            final class LiveNoteService: NoteService {

                @section("__DATA,__easydi") @used
                nonisolated static let __easyDIRecord: @convention(c) () -> Void = {
                    EasyDI.__register((any NoteService).self, provider: LiveNoteService.self, contractName: "NoteService", providerName: "LiveNoteService", lifetime: .weak) {
                        LiveNoteService()
                    }
                }
            }
            """
        )
    }

    @Test("@Injectable with no arguments: the type provides itself, as a singleton")
    func injectableItself() {
        expand(
            """
            @Injectable
            struct Clock {
            }
            """,
            into: """
            struct Clock {

                @section("__DATA,__easydi") @used
                nonisolated static let __easyDIRecord: @convention(c) () -> Void = {
                    EasyDI.__register(Clock.self, provider: Clock.self, contractName: "Clock", providerName: "Clock", lifetime: .singleton) {
                        Clock()
                    }
                }
            }
            """
        )
    }

    @Test("@Mock on a type: a file-level record")
    func mockType() {
        expand(
            """
            @Mock(NoteService.self)
            final class MockNoteService: NoteService {
            }
            """,
            into: """
            final class MockNoteService: NoteService {
            }

            @section("__DATA,__easydi") @used
            nonisolated let __easyDIMock_MockNoteService: @convention(c) () -> Void = {
                EasyDI.__registerMock((any NoteService).self, name: nil, type: MockNoteService.self, contractName: "NoteService", label: "MockNoteService") {
                    MockNoteService()
                }
            }
            """
        )
    }

    @Test("@Mock on a static property: a static record next to it")
    func mockProperty() {
        expand(
            """
            extension MockNoteService {
                @Mock(NoteService.self, "failing")
                static var failing: MockNoteService { MockNoteService(scenario: .failing) }
            }
            """,
            into: """
            extension MockNoteService {
                static var failing: MockNoteService { MockNoteService(scenario: .failing) }

                @section("__DATA,__easydi") @used
                nonisolated static let __easyDIMock_failing: @convention(c) () -> Void = {
                    EasyDI.__registerMock((any NoteService).self, name: "failing", type: MockNoteService.self, contractName: "NoteService", label: "MockNoteService.failing") {
                        MockNoteService.failing
                    }
                }
            }
            """
        )
    }

    @Test("@Mock on a property typed `any Contract`: no type to find it by")
    func mockExistentialProperty() {
        expand(
            """
            enum Mocks {
                @Mock(NoteService.self, "empty")
                static var empty: any NoteService { EmptyNotes() }
            }
            """,
            into: """
            enum Mocks {
                static var empty: any NoteService { EmptyNotes() }

                @section("__DATA,__easydi") @used
                nonisolated static let __easyDIMock_empty: @convention(c) () -> Void = {
                    EasyDI.__registerMock((any NoteService).self, name: "empty", type: nil, contractName: "NoteService", label: "Mocks.empty") {
                        Mocks.empty
                    }
                }
            }
            """
        )
    }

    @Test(".weak on a value type is an error")
    func weakStruct() {
        expectError(
            "@Injectable(.weak) struct Cache {}",
            expanded: "struct Cache {}",
            "@Injectable(.weak) keeps one instance while something holds it, which needs a class; Cache is a value type. Use .singleton or .transient."
        )
    }

    @Test("A generic type is an error")
    func genericType() {
        expectError(
            "@Injectable final class Box<Value> {}",
            expanded: "final class Box<Value> {}",
            "@Injectable can't register the generic type Box: there is no one type to build. Register a concrete type."
        )
    }

    @Test("Inside a generic type is an error")
    func insideGenericType() {
        expectError(
            """
            struct Outer<T> {
                @Injectable final class Inner {}
            }
            """,
            expanded: """
            struct Outer<T> {
                final class Inner {}
            }
            """,
            "@Injectable can't be used inside a generic type.",
            line: 2,
            column: 5
        )
    }

    @Test("@Injectable on an enum is an error")
    func injectableEnum() {
        expectError("@Injectable enum Mode {}", expanded: "enum Mode {}", "@Injectable goes on a class, struct or actor.")
    }

    @Test("@Mock on an instance property is an error")
    func mockInstanceProperty() {
        expectError(
            """
            struct Mocks {
                @Mock(NoteService.self) var notes: MockNoteService
            }
            """,
            expanded: """
            struct Mocks {
                var notes: MockNoteService
            }
            """,
            "@Mock goes on a type or on a static property of a type.",
            line: 2,
            column: 5
        )
    }

    private func expand(_ source: String, into expanded: String, sourceLocation: SourceLocation = #_sourceLocation) {
        assertMacroExpansion(source, expandedSource: expanded, macroSpecs: macros) { failure in
            Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
        }
    }

    private func expectError(
        _ source: String,
        expanded: String,
        _ message: String,
        line: Int = 1,
        column: Int = 1,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        assertMacroExpansion(
            source,
            expandedSource: expanded,
            diagnostics: [DiagnosticSpec(message: message, line: line, column: column)],
            macroSpecs: macros
        ) { failure in
            Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
        }
    }
}
#endif
