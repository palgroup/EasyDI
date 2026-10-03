#if os(macOS)
import EasyDI
import Foundation
import Testing

/// Each stop runs in a child process (an exit test): it ends the process, and the
/// fixtures that cause it would stop every other test too.
@Suite("Stops, naming what to fix")
struct StopTests {
    @Test("Two providers for one contract")
    func duplicateProviders() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { let _: any Duplicated = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: Duplicated has 2 providers:"))
        #expect(message.contains("FirstDuplicate") && message.contains("SecondDuplicate"))
    }

    @Test("Nothing provides the contract")
    func missingProvider() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { let _: any Unprovided = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains(
            "EasyDI: nothing provides Unprovided. Mark the type that does with @Injectable(as: Unprovided.self)."
        ))
    }

    @Test("Only mocks provide the contract, outside a preview")
    func onlyMocks() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { let _: any OnlyMocked = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("Its mocks are used only in previews, under Injection.with(.mock(…)) and with Injection.usesDefaultMocks."))
    }

    @Test("A .singleton takes something .weak")
    func singletonTakesWeak() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { let _: any AppWide = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains(
            "EasyDI: AppWideImpl is a .singleton, it lives as long as the app, but it takes CaptiveImpl, which is .weak: it would never be released. Make CaptiveImpl .singleton or AppWideImpl .weak."
        ))
    }

    @Test("A .singleton takes something .weak through a .transient")
    func singletonTakesWeakThroughTransient() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { let _: any FarOwner = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains(
            "EasyDI: FarOwnerImpl is a .singleton, it lives as long as the app, but through MiddleImpl it takes FarWeakImpl, which is .weak"
        ))
    }

    @Test("Mocks that need each other")
    func mockCycle() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
            await MainActor.run { let _: any MockCycleA = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: MockCycleAImpl → MockCycleBImpl → MockCycleAImpl is a cycle"))
    }

    @Test("Two mocks with one name for one contract")
    func duplicateNamedMocks() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { let _: any Named = Injection.with(.mock("same")) { resolve() } }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: Named has two mocks named \"same\": "))
        #expect(message.contains("FirstNamed.same") && message.contains("SecondNamed.same"))
    }

    @Test(".mock(_:for:) with a name that contract has no mock by")
    func unknownMockNameForContract() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { _ = Injection.with(.mock("nope", for: (any NoteStore).self)) { 0 } }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains(
            "EasyDI: .mock(\"nope\") — no mock for NoteStore is named \"nope\". Named mocks for NoteStore: \"empty\", \"failing\"."
        ))
    }

    @Test(".inject with an instance of a type registered for two contracts")
    func injectAmbiguous() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { _ = Injection.with(.inject(DoubleDuty())) { 0 } }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: .inject(DoubleDuty) — DoubleDuty stands for 2 contracts. Name the contract"))
    }

    @Test("Providers that need each other")
    func cycle() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run { let _: any CycleA = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: CycleAImpl → CycleBImpl → CycleAImpl is a cycle"))
    }

    @Test("Two default mocks for one contract")
    func duplicateMocks() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
            await MainActor.run { let _: any DoubleMocked = resolve() }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: DoubleMocked has two default mocks:"))
        #expect(message.contains("FirstMock") && message.contains("SecondMock"))
    }

    @Test(".mock with a name no mock has")
    func unknownMockName() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run {
                _ = Injection.with(.mock("faling")) { 0 }
            }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: .mock(\"faling\") — no mock is named \"faling\". Named mocks: "))
        #expect(message.contains("\"empty\", ") && message.contains("\"failing\", "))
    }

    @Test(".inject with an instance of a type registered nowhere")
    func injectUnregistered() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run {
                _ = Injection.with(.inject(Unregistered())) { 0 }
            }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains(
            "EasyDI: .inject(Unregistered) — Unregistered isn't marked @Injectable or @Mock"
        ))
    }
}

@Suite("Previews")
struct PreviewTests {
    @Test("usesDefaultMocks gives the default mocks outside a preview, as UI tests want")
    func defaultMocksOnRequest() async {
        await #expect(processExitsWith: .success) {
            let passed = await MainActor.run {
                let offByDefault = !Injection.usesDefaultMocks
                Injection.usesDefaultMocks = true
                let data = NotesData()
                let selected = Injection.with(.mock("failing")) { NotesData() }
                // Setting the value it already has changes nothing, so it doesn't stop.
                Injection.usesDefaultMocks = true
                return offByDefault
                    && data.store.scenario == "seeded"
                    && data.weather.forecast == "live"
                    && selected.store.scenario == "failing"
            }
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    @Test("Turning usesDefaultMocks on after something was built")
    func defaultMocksTurnedOnLate() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run {
                _ = NotesData()
                Injection.usesDefaultMocks = true
            }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains(
            "EasyDI: Injection.usesDefaultMocks was turned on after LiveNoteStore and LiveWeather were built, and what is built keeps what it got. Set it before anything is resolved: first thing in the app's init."
        ))
    }

    @Test("Turning usesDefaultMocks on after one provider was built")
    func defaultMocksTurnedOnAfterOne() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run {
                let _: any Weather = resolve()
                Injection.usesDefaultMocks = true
            }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: Injection.usesDefaultMocks was turned on after LiveWeather was built, and what is built keeps what it got."))
    }

    @Test("Turning usesDefaultMocks off after a mock was built")
    func defaultMocksTurnedOffLate() async {
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) {
            await MainActor.run {
                Injection.usesDefaultMocks = true
                _ = NotesData()
                Injection.usesDefaultMocks = false
            }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: Injection.usesDefaultMocks was turned off after LiveWeather and MockNoteStore were built"))
    }

    @Test("In a preview, a contract gets its default mock, or its provider when it has none")
    func previewUsesDefaultMock() async {
        await #expect(processExitsWith: .success) {
            setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
            let passed = await MainActor.run {
                let data = NotesData()
                let selected = Injection.with(.mock("failing")) { NotesData() }
                return data.store.scenario == "seeded"
                    && data.weather.forecast == "live"
                    && selected.store.scenario == "failing"
            }
            exit(passed ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }
}

func text(_ bytes: [UInt8]?) -> String {
    String(decoding: bytes ?? [], as: UTF8.self)
}
#endif
