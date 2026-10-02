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
        #expect(message.contains("Its mocks are used only in previews and under .mock(…)."))
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
        #expect(message.contains(
            "EasyDI: .mock(\"faling\") — no mock is named \"faling\". Named mocks: \"empty\", \"failing\"."
        ))
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
