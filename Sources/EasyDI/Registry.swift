import Darwin
import MachO
import Synchronization

/// The records `@Injectable` and `@Mock` leave in the `__DATA,__easydi` section.
///
/// dyld calls `imageAdded` for every image already loaded when the callback is
/// registered, and later for each image loaded after it (a framework opened with
/// `dlopen`, the code a preview loads). The callback only collects the records'
/// addresses; they run on the main actor, the first time something is resolved after.
enum Registry {
    typealias Record = @convention(c) () -> Void

    static let pending = Mutex<[UInt]>([])
    /// How many records were found so far; the container compares it with how many it ran.
    static let found = Atomic<Int>(0)

    static let start: Void = {
        _dyld_register_func_for_add_image(imageAdded)
    }()

    /// Called on whatever thread dyld loads an image on.
    static func collect(_ addresses: [UInt]) {
        pending.withLock { $0 += addresses }
        found.add(addresses.count, ordering: .releasing)
    }
}

private func imageAdded(_ header: UnsafePointer<mach_header>?, _ slide: Int) {
    guard let header else { return }
    var size: UInt = 0
    let section = header.withMemoryRebound(to: mach_header_64.self, capacity: 1) {
        getsectiondata($0, "__DATA", "__easydi", &size)
    }
    guard let section, size > 0 else { return }
    let stride = MemoryLayout<Registry.Record>.stride
    var addresses: [UInt] = []
    for offset in Swift.stride(from: 0, to: Int(size), by: stride) {
        let slot = UnsafeRawPointer(section + offset)
        if Sanitizer.isPoisoned(slot, stride) { continue }
        let address = slot.load(as: UInt.self)
        if address != 0 { addresses.append(address) }
    }
    Registry.collect(addresses)
}

/// AddressSanitizer pads every global with a poisoned redzone, the records in the
/// section too, so a build with it has gaps between them that must not be read.
private enum Sanitizer {
    typealias RegionIsPoisoned = @convention(c) (UnsafeRawPointer, Int) -> UnsafeRawPointer?

    /// `__asan_region_is_poisoned`, when the process runs with AddressSanitizer
    /// (looked up in every loaded image: `-2` is `RTLD_DEFAULT`).
    static let regionIsPoisoned: UInt? = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "__asan_region_is_poisoned").map {
        UInt(bitPattern: $0)
    }

    static func isPoisoned(_ start: UnsafeRawPointer, _ count: Int) -> Bool {
        guard let regionIsPoisoned else { return false }
        return unsafeBitCast(regionIsPoisoned, to: RegionIsPoisoned.self)(start, count) != nil
    }
}

/// What a record registers: called by the code `@Injectable` generates.
public nonisolated func __register<Contract>(
    _ contract: Contract.Type,
    provider: Any.Type,
    contractName: String,
    providerName: String,
    lifetime: Lifetime,
    make: @escaping @MainActor @Sendable () -> Contract
) {
    let contract = ObjectIdentifier(contract)
    let type = ObjectIdentifier(provider)
    MainActor.assumeIsolated {
        Container.shared.add(
            Provider(contract: contract, contractName: contractName, type: type, name: providerName, lifetime: lifetime, make: make)
        )
    }
}

/// What a record registers: called by the code `@Mock` generates.
public nonisolated func __registerMock<Contract>(
    _ contract: Contract.Type,
    name: String?,
    type: Any.Type?,
    contractName: String,
    label: String,
    make: @escaping @MainActor @Sendable () -> Contract
) {
    let contract = ObjectIdentifier(contract)
    let type = type.map(ObjectIdentifier.init)
    MainActor.assumeIsolated {
        Container.shared.add(
            Mock(contract: contract, contractName: contractName, name: name, type: type, label: label, make: make)
        )
    }
}
