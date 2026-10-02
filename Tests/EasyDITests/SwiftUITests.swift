import EasyDI
import Observation
import SwiftUI
import Testing

/// Hosting tests share the main run loop, so they run one at a time.
@Suite("SwiftUI: Injected, .mock, .inject", .serialized)
struct SwiftUITests {
    @Test("Injected builds the screen with the selection around it")
    func injected() {
        let seen = Seen()
        let host = Host(Injected { ProbeScreen(data: NotesData(), seen: seen) }.mock("failing"))
        defer { host.close() }
        #expect(eventually { seen.last?.store.scenario == "failing" })
        #expect(seen.last?.weather.forecast == "failing")
    }

    @Test("Without a selection the screen gets the provider")
    func noSelection() {
        let seen = Seen()
        let host = Host(Injected { ProbeScreen(data: NotesData(), seen: seen) })
        defer { host.close() }
        #expect(eventually { seen.last?.store.scenario == "live" })
    }

    @Test("A pushed screen keeps the selection made around the stack")
    func pushedScreen() {
        let seen = Seen()
        let host = Host(PushingRoot(seen: seen).mock("empty"))
        defer { host.close() }
        #expect(eventually { seen.last?.store.scenario == "empty" })
    }

    @Test("A pushed screen keeps an injected instance")
    func pushedScreenInjected() {
        let seen = Seen()
        let mine = MockNoteStore(scenario: "mine")
        let host = Host(PushingRoot(seen: seen).inject(mine))
        defer { host.close() }
        #expect(eventually { seen.last?.store === mine })
    }

    // iOS presents a sheet only from a window in a scene, which a package's test process has none of.
    #if os(macOS)
    @Test("A presented sheet keeps the selection")
    func presentedSheet() {
        let seen = Seen()
        let host = Host(PresentingRoot(seen: seen).mock("failing", for: (any NoteStore).self))
        defer { host.close() }
        #expect(eventually { seen.last?.store.scenario == "failing" })
        #expect(seen.last?.weather.forecast == "live")
    }
    #endif

    @Test("Changing the selection builds the screen again, with new data")
    func selectionChangeRebuilds() {
        let seen = Seen()
        let choice = Choice(name: "empty")
        let host = Host(SwitchingRoot(choice: choice, seen: seen))
        defer { host.close() }
        #expect(eventually { seen.last?.store.scenario == "empty" })
        let first = seen.last

        choice.name = "failing"
        #expect(eventually { seen.last?.store.scenario == "failing" })
        #expect(seen.last !== first)
    }

    @Test("Drawing again with the same selection keeps the screen and its data")
    func sameSelectionKeepsState() {
        let seen = Seen()
        let choice = Choice(name: "empty")
        let host = Host(SwitchingRoot(choice: choice, seen: seen))
        defer { host.close() }
        #expect(eventually { seen.last != nil })

        choice.redraws += 1
        #expect(eventually { choice.drawn >= 2 })
        #expect(seen.appeared.count == 1)
    }
}

/// The screens that appeared, with their data.
@MainActor
final class Seen {
    private(set) var appeared: [NotesData] = []
    var last: NotesData? { appeared.last }

    func record(_ data: NotesData) {
        appeared.append(data)
    }
}

struct ProbeScreen: View {
    @State var data: NotesData
    let seen: Seen

    var body: some View {
        Text(data.store.scenario)
            .onAppear { seen.record(data) }
    }
}

struct PushingRoot: View {
    let seen: Seen
    @State private var path = [1]

    var body: some View {
        NavigationStack(path: $path) {
            Text("Root")
                .navigationDestination(for: Int.self) { _ in
                    Injected { ProbeScreen(data: NotesData(), seen: seen) }
                }
        }
    }
}

struct PresentingRoot: View {
    let seen: Seen
    @State private var isPresented = true

    var body: some View {
        Text("Root")
            .sheet(isPresented: $isPresented) {
                Injected { ProbeScreen(data: NotesData(), seen: seen) }
            }
    }
}

@MainActor
@Observable
final class Choice {
    var name: String
    var redraws = 0
    @ObservationIgnored var drawn = 0

    init(name: String) {
        self.name = name
    }
}

struct SwitchingRoot: View {
    let choice: Choice
    let seen: Seen

    var body: some View {
        let _ = choice.redraws
        let _ = choice.drawn += 1
        Injected { ProbeScreen(data: NotesData(), seen: seen) }
            .mock(choice.name)
    }
}
