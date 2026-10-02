import EasyDI
import Testing

@Suite("Lifetimes")
struct LifetimeTests {
    @Test(".singleton: one instance everywhere, kept for the app")
    func singleton() {
        @Inject var first: any SingletonService
        @Inject var second: any SingletonService
        #expect(first === second)
        #expect(registration("SingletonService").isAlive)
    }

    @Test(".singleton is the default")
    func singletonIsDefault() {
        @Inject var first: any DefaultLifetimeService
        @Inject var second: any DefaultLifetimeService
        #expect(first === second)
        #expect(registration("DefaultLifetimeService").lifetime == .singleton)
    }

    @Test(".weak: shared while held, released after the last holder, then made again")
    func weak() {
        weak var released: (any WeakService)?
        do {
            @Inject var first: any WeakService
            @Inject var second: any WeakService
            #expect(first === second)
            #expect(registration("WeakService").isAlive)
            released = first
        }
        #expect(released == nil)
        #expect(!registration("WeakService").isAlive)

        let madeBefore = registration("WeakService").made
        @Inject var again: any WeakService
        #expect(registration("WeakService").made == madeBefore + 1)
        #expect(registration("WeakService").isAlive)
        _ = again
    }

    @Test(".transient: a new instance for every request")
    func transient() {
        @Inject var first: any TransientService
        @Inject var second: any TransientService
        #expect(first !== second)
        #expect(!registration("TransientService").isAlive)
    }

    private func registration(_ contract: String) -> Registration {
        Injection.registrations.first { $0.contract == contract }!
    }
}
