@testable import EasyDI
import Darwin
import Foundation
import Synchronization
import Testing

@Suite("Battle")
struct BattleTests {
    @Test("Records found on other threads all run, once each, on the main actor")
    func recordsFromOtherThreads() async {
        let address = unsafeBitCast(countRun, to: UInt.self)
        let threads = 8
        let perThread = 1_000
        let before = recordsRun.load(ordering: .relaxed)
        let done = Atomic<Bool>(false)
        let collecting = Task.detached {
            DispatchQueue.concurrentPerform(iterations: threads) { _ in
                for _ in 0..<perThread {
                    Registry.collect([address])
                }
            }
        }
        Task.detached {
            await collecting.value
            done.store(true, ordering: .releasing)
        }
        while !done.load(ordering: .acquiring) {
            Container.shared.load()
            await Task.yield()
        }
        Container.shared.load()
        #expect(recordsRun.load(ordering: .relaxed) - before == threads * perThread)
    }

    #if os(macOS)
    @Test("100,000 resolutions leave memory where it was", .disabled(if: runsWithSanitizer, sanitizerNote))
    func manyResolutions() async {
        let result = await #expect(processExitsWith: .success, observing: [\.standardOutputContent]) {
            let growth = await MainActor.run {
                resolveMixed(1_000)
                let before = footprint()
                resolveMixed(100_000)
                return footprint() - before
            }
            print("footprint growth after 100,000 resolutions: \(growth) bytes")
            exit(growth < memoryLimit ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        print(text(result?.standardOutputContent))
    }

    @Test("10,000 .weak build-and-release cycles: each one released, memory where it was", .disabled(if: runsWithSanitizer, sanitizerNote))
    func weakCycles() async {
        let result = await #expect(processExitsWith: .success, observing: [\.standardOutputContent]) {
            let (growth, made, alive) = await MainActor.run {
                cycleWeak(1_000)
                let madeBefore = Injection.registrations.first { $0.contract == "Cycled" }!.made
                let before = footprint()
                cycleWeak(10_000)
                let growth = footprint() - before
                let after = Injection.registrations.first { $0.contract == "Cycled" }!
                return (growth, after.made - madeBefore, after.isAlive)
            }
            print("footprint growth after 10,000 .weak cycles: \(growth) bytes; built \(made), alive after: \(alive)")
            exit(growth < memoryLimit && made == 10_000 && !alive ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        print(text(result?.standardOutputContent))
    }
    #endif
}

/// The sanitizers keep freed memory (quarantine, shadow), so the footprint grows with every allocation.
nonisolated let runsWithSanitizer = ["__asan_init", "__tsan_init"].contains { (symbol: String) in
    dlsym(UnsafeMutableRawPointer(bitPattern: -2), symbol) != nil
}

nonisolated let sanitizerNote: Comment = "A sanitizer keeps freed memory, so the footprint says nothing here."

/// 1 MB: leaking even 16 bytes per resolution would come to 1.6 MB over 100,000.
nonisolated let memoryLimit = 1_048_576

nonisolated let recordsRun = Atomic<Int>(0)

nonisolated let countRun: @convention(c) () -> Void = {
    recordsRun.add(1, ordering: .relaxed)
}

/// `count` resolutions, a third each of .singleton, .weak and .transient, and a selection every tenth.
func resolveMixed(_ count: Int) {
    for index in 0..<count {
        switch index % 3 {
        case 0:
            @Inject var value: any SingletonService
            _ = value
        case 1:
            @Inject var value: any WeakService
            _ = value
        default:
            @Inject var value: any TransientService
            _ = value
        }
        if index.isMultiple(of: 10) {
            _ = Injection.with(.mock("failing")) { NotesData() }
        }
    }
}

func cycleWeak(_ count: Int) {
    for _ in 0..<count {
        @Inject var value: any Cycled
        _ = value
    }
}

/// What the system counts against the app: `phys_footprint`, the number Xcode's memory gauge shows.
nonisolated func footprint() -> Int {
    var info = task_vm_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) {
        $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
            task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
        }
    }
    return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
}
