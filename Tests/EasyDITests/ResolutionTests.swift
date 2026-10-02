import EasyDI
import Observation
import Synchronization
import Testing

@Suite("Registration and resolution")
struct ResolutionTests {
    @Test("@Injectable types register themselves, with no list to keep")
    func registersItself() {
        let registrations = Injection.registrations
        #expect(registrations.contains { $0.contract == "Greeter" && $0.provider == "EnglishGreeter" && $0.lifetime == .singleton })
        #expect(registrations.contains { $0.contract == "NoteStore" && $0.provider == "LiveNoteStore" && $0.lifetime == .weak })
        #expect(registrations.contains { $0.contract == "Nested" && $0.provider == "NestedProvider" })
    }

    @Test("@Inject finds the provider by the protocol it asks for")
    func resolvesByProtocol() {
        @Inject var greeter: any Greeter
        #expect(greeter is EnglishGreeter)
        #expect(greeter.greet() == "Hello")
    }

    @Test("A type registered without `as:` provides itself")
    func providesItself() {
        @Inject var first: Clock
        @Inject var second: Clock
        #expect(first === second)
    }

    @Test("A provider's own dependencies are injected while it is built")
    func nestedDependencies() {
        let repository = Repository()
        #expect(repository.storage is RemoteStorage)
        #expect(repository.storage.http is URLSessionHTTPClient)
        #expect(Repository().storage.http === repository.storage.http)
    }

    @Test("A struct can provide a contract")
    func structProvider() {
        @Inject var settings: any Settings
        #expect(settings.theme == "light")
    }

    @Test("An actor can provide a contract")
    func actorProvider() async {
        @Inject var counter: any Counter
        @Inject var same: any Counter
        #expect(await counter.next() == 1)
        #expect(await same.next() == 2)
    }

    @Test("A type nested in another registers like any other")
    func nestedType() {
        @Inject var nested: any Nested
        #expect(nested is Outer.NestedProvider)
    }

    @Test("The same type registered again, as a preview reloading its code does, is one provider")
    func registeredAgain() {
        for _ in 0..<2 {
            EasyDI.__register(
                (any Reloaded).self,
                provider: ReloadedImpl.self,
                contractName: "Reloaded",
                providerName: "ReloadedImpl",
                lifetime: .singleton
            ) {
                ReloadedImpl()
            }
        }
        @Inject var reloaded: any Reloaded
        #expect(reloaded is ReloadedImpl)
        #expect(Injection.registrations.filter { $0.contract == "Reloaded" }.count == 1)
    }

    @Test("@Injectable and @Observable work on the same class")
    func observable() {
        @Inject var session: any Session
        @Inject var sameSession: any Session
        #expect(session === sameSession)

        let changed = Flag()
        withObservationTracking {
            _ = session.user
        } onChange: {
            changed.raise()
        }
        sameSession.user = "ada"
        #expect(changed.isRaised)
        #expect(session.user == "ada")
    }
}

nonisolated final class Flag: Sendable {
    private let raised = Atomic<Bool>(false)

    var isRaised: Bool { raised.load(ordering: .acquiring) }

    func raise() {
        raised.store(true, ordering: .releasing)
    }
}
