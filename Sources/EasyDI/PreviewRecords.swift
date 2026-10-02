import Darwin
import ObjectiveC

/// What `@Injectable` and `@Mock` also generate for every record: a class whose
/// `register()` registers it.
///
/// Xcode's canvas doesn't load the app's code through dyld: its JIT linker maps
/// it, and dyld only sees an empty placeholder for it, so the `__DATA,__easydi`
/// section can't be found there. The JIT does register the code's classes with
/// the Objective-C runtime, so in a preview the records are found as subclasses
/// of this one.
open class __PreviewRecord {
    public init() {}

    open class func register() {}
}

enum PreviewRecords {
    /// Runs every record class loaded so far. Registering one again is harmless:
    /// the same provider or mock registered twice is kept once.
    @MainActor
    static func run() {
        var count: UInt32 = 0
        guard let list = objc_copyClassList(&count) else { return }
        defer { free(UnsafeMutableRawPointer(list)) }
        // Read as addresses: loading an element as `AnyClass` casts it, and some
        // system classes can't take that.
        let classes = UnsafeRawPointer(list).bindMemory(to: UInt.self, capacity: Int(count))
        for index in 0..<Int(count) {
            let candidate: AnyClass = unsafeBitCast(classes[index], to: AnyClass.self)
            // The name check is cheap and skips nearly every class before the
            // superclass, which can make the runtime set a class up, is read.
            guard strstr(class_getName(candidate), "EasyDI") != nil,
                  class_getSuperclass(candidate) == __PreviewRecord.self,
                  let record = candidate as? __PreviewRecord.Type else { continue }
            record.register()
        }
    }
}
