import EasyDI

protocol SingletonService: AnyObject {}

@MainActor
@Injectable(as: SingletonService.self)
final class LiveSingleton: SingletonService {}

protocol WeakService: AnyObject {}

@MainActor
@Injectable(as: WeakService.self, .weak)
final class LiveWeak: WeakService {}

protocol TransientService: AnyObject {}

@MainActor
@Injectable(as: TransientService.self, .transient)
final class LiveTransient: TransientService {}

@MainActor
func resolve<Value>() -> Value {
    @Inject var value: Value
    return value
}

/// Keeps the optimiser from dropping a resolution whose result nothing reads.
@inline(never)
func use(_ value: AnyObject) -> Int {
    ObjectIdentifier(value).hashValue
}

@MainActor
func measure(_ name: String, iterations: Int, _ body: () -> Int) {
    var checksum = 0
    let elapsed = ContinuousClock().measure {
        for _ in 0..<iterations {
            checksum &+= body()
        }
    }
    let nanoseconds = Double(elapsed.components.attoseconds) / 1e9 + Double(elapsed.components.seconds) * 1e9
    print("\(name): \(Int((nanoseconds / Double(iterations)).rounded())) ns each (\(iterations) runs, checksum \(checksum & 0xff))")
}

// The first resolution registers with dyld, reads the section of every loaded
// image and runs the records it finds.
let first = ContinuousClock().measure {
    let _: any Service000 = resolve()
}
let registered = Injection.registrations.count
print("first resolution, \(registered) providers registered: \(first)")

let singleton: any SingletonService = resolve()
let weak: any WeakService = resolve()
measure(".singleton, already built", iterations: 1_000_000) { use(resolve() as any SingletonService) }
measure(".weak, held elsewhere", iterations: 1_000_000) { use(resolve() as any WeakService) }
measure(".transient", iterations: 1_000_000) { use(resolve() as any TransientService) }
_ = (singleton, weak)

protocol CycledService: AnyObject {}

@MainActor
@Injectable(as: CycledService.self, .weak)
final class LiveCycled: CycledService {}

measure(".weak, built and released", iterations: 100_000) { use(resolve() as any CycledService) }
