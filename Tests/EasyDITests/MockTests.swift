import EasyDI
import Testing

@Suite("Mocks and selection")
struct MockTests {
    @Test("@Mock registers the default and the named mocks by themselves")
    func registersMocks() {
        let store = Injection.registrations.first { $0.contract == "NoteStore" }
        #expect(store?.mocks == ["default", "empty", "failing"])
        let weather = Injection.registrations.first { $0.contract == "Weather" }
        #expect(weather?.mocks == ["failing"])
    }

    @Test("Outside a preview the app gets the provider, not the default mock")
    func appUsesProvider() {
        let data = NotesData()
        #expect(data.store.scenario == "live")
    }

    @Test(".mock(name) picks that mock for every contract that has one by that name")
    func namedMock() {
        let data = Injection.with(.mock("failing")) { NotesData() }
        #expect(data.store.scenario == "failing")
        #expect(data.weather.forecast == "failing")
    }

    @Test("A contract without a mock by that name keeps its provider")
    func namedMockFallsBack() {
        let data = Injection.with(.mock("empty")) { NotesData() }
        #expect(data.store.scenario == "empty")
        #expect(data.weather.forecast == "live")
    }

    @Test(".mock(name, for:) picks it for one contract only")
    func namedMockForOneContract() {
        let data = Injection.with(.mock("failing", for: (any Weather).self)) { NotesData() }
        #expect(data.store.scenario == "live")
        #expect(data.weather.forecast == "failing")
    }

    @Test("The later selection wins")
    func laterWins() {
        let data = Injection.with(.mock("failing"), .mock("empty")) { NotesData() }
        #expect(data.store.scenario == "empty")
        #expect(data.weather.forecast == "failing")
    }

    @Test(".inject(instance) answers for the contract its type is registered for")
    func injectInstance() {
        let mine = MockNoteStore(scenario: "mine")
        let data = Injection.with(.inject(mine)) { NotesData() }
        #expect(data.store === mine)
    }

    @Test(".inject(instance, as:) for a type registered nowhere")
    func injectAs() {
        let stub = Unregistered()
        let data = Injection.with(.inject(stub, as: (any NoteStore).self)) { NotesData() }
        #expect(data.store === stub)
    }

    @Test("A selected mock is shared while held, like a .weak provider")
    func mockShared() {
        let first = Injection.with(.mock("failing")) { NotesData() }
        let second = Injection.with(.mock("failing")) { NotesData() }
        #expect(first.store === second.store)
    }

    @Test("A provider built with a selected mock inside isn't kept for the app")
    func selectionDoesNotLeak() {
        let selected: any Inbox = Injection.with(.mock("empty")) { resolve() }
        @Inject var app: any Inbox
        #expect(selected.store.scenario == "empty")
        #expect(app.store.scenario == "live")
        #expect(selected !== app)
    }

    @Test("A kept provider is built again when a selection replaces one of its dependencies")
    func selectionReachesKeptProvider() {
        @Inject var app: any Feed
        let selected: any Feed = Injection.with(.mock("failing")) { resolve() }
        @Inject var appAgain: any Feed
        #expect(app.store.scenario == "live")
        #expect(selected.store.scenario == "failing")
        #expect(appAgain === app)
    }
}
