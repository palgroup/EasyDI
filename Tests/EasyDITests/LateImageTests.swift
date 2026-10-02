// Compiling a library at test time needs the toolchain, which only macOS has.
#if os(macOS)
import Darwin
import EasyDI
import Foundation
import Testing

@Suite("Images loaded later")
struct LateImageTests {
    @Test("A library opened after the first resolution, on another thread: its providers are found")
    func libraryOpenedLater() async throws {
        // The first resolution has already read every image loaded so far.
        let _: any Greeter = resolve()

        let library = try buildPlugin(named: "Late", source: lateSource)
        let opened = await Task.detached {
            dlopen(library.path, RTLD_NOW).map { UInt(bitPattern: $0) }
        }.value
        let handle = try #require(opened.flatMap(UnsafeMutableRawPointer.init(bitPattern:)), "\(String(cString: dlerror()))")
        let symbol = try #require(dlsym(handle, "easydi_late_resolves"))
        let resolves = unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)

        #expect(resolves())
        #expect(Injection.registrations.contains { $0.contract == "LateContract" && $0.provider == "LateProvider" })
    }

    // Xcode's canvas loads the app's code with its own JIT linker: dyld sees no
    // section in it, only the Objective-C runtime sees its classes. A library whose
    // only record is a class stands for that code.
    @Test("In a preview, records found only as classes are registered, before and after the first resolution")
    func previewFindsRecordClasses() async throws {
        let library = try buildPlugin(named: "ClassOnly", source: classOnlySource).path
        await #expect(processExitsWith: .success) { [library = library as String] in
            setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
            let resolved = await MainActor.run { () -> Bool in
                let _: any Greeter = resolve()
                guard let handle = dlopen(library, RTLD_NOW), let symbol = dlsym(handle, "easydi_class_only_resolves") else {
                    return false
                }
                return unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)()
            }
            exit(resolved ? EXIT_SUCCESS : EXIT_FAILURE)
        }
        await #expect(processExitsWith: .success) { [library = library as String] in
            setenv("XCODE_RUNNING_FOR_PREVIEWS", "1", 1)
            let resolved = await MainActor.run { () -> Bool in
                guard let handle = dlopen(library, RTLD_NOW), let symbol = dlsym(handle, "easydi_class_only_resolves") else {
                    return false
                }
                return unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)()
            }
            exit(resolved ? EXIT_SUCCESS : EXIT_FAILURE)
        }
    }

    @Test("Outside a preview, a record that is only a class isn't used")
    func recordClassesOnlyInPreviews() async throws {
        let library = try buildPlugin(named: "ClassOnly", source: classOnlySource).path
        let result = await #expect(processExitsWith: .failure, observing: [\.standardErrorContent]) { [library = library as String] in
            let _ = await MainActor.run { () -> Bool in
                guard let handle = dlopen(library, RTLD_NOW), let symbol = dlsym(handle, "easydi_class_only_resolves") else {
                    return false
                }
                return unsafeBitCast(symbol, to: (@convention(c) () -> Bool).self)()
            }
        }
        let message = text(result?.standardErrorContent)
        #expect(message.contains("EasyDI: nothing provides ClassOnlyContract."))
    }
}

/// A record written as the macros write their class, with no section record.
private let classOnlySource = """
import EasyDI

public protocol ClassOnlyContract: AnyObject {}

@MainActor
final class ClassOnlyProvider: ClassOnlyContract {}

nonisolated final class __EasyDIRecordClassOnly: EasyDI.__PreviewRecord {
    override class func register() {
        EasyDI.__register(
            (any ClassOnlyContract).self,
            provider: ClassOnlyProvider.self,
            contractName: "ClassOnlyContract",
            providerName: "ClassOnlyProvider",
            lifetime: .singleton
        ) {
            ClassOnlyProvider()
        }
    }
}

@MainActor
func resolvesClassOnly() -> Bool {
    @Inject var value: any ClassOnlyContract
    return value is ClassOnlyProvider
}

@_cdecl("easydi_class_only_resolves")
public func classOnlyResolves() -> Bool {
    MainActor.assumeIsolated { resolvesClassOnly() }
}
"""

/// A library with its own contract and `@Injectable` provider.
private let lateSource = """
import EasyDI

public protocol LateContract: AnyObject {}

@MainActor
@Injectable(as: LateContract.self)
final class LateProvider: LateContract {}

@MainActor
func resolvesLate() -> Bool {
    @Inject var late: any LateContract
    return late is LateProvider
}

@_cdecl("easydi_late_resolves")
public func lateResolves() -> Bool {
    MainActor.assumeIsolated { resolvesLate() }
}
"""

/// Compiles `source` into a library with this test's EasyDI module and macro
/// plugin; the library takes EasyDI's symbols from this process.
private func buildPlugin(named name: String, source code: String) throws -> URL {
    let build = try buildDirectory()
    let directory = FileManager.default.temporaryDirectory.appending(path: "easydi-\(name)-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let source = directory.appending(path: "\(name).swift")
    let library = directory.appending(path: "lib\(name).dylib")
    try code.write(to: source, atomically: true, encoding: .utf8)

    let compiler = Process()
    compiler.executableURL = URL(filePath: "/usr/bin/xcrun")
    compiler.arguments = [
        "swiftc", "-emit-library", "-parse-as-library", "-swift-version", "6", "-module-name", name,
        "-I", build.appending(path: "Modules").path,
        "-load-plugin-executable", build.appending(path: "EasyDIMacros-tool").path + "#EasyDIMacros",
        "-Xlinker", "-undefined", "-Xlinker", "dynamic_lookup",
        source.path, "-o", library.path,
    ]
    let output = Pipe()
    compiler.standardOutput = output
    compiler.standardError = output
    try compiler.run()
    let log = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    compiler.waitUntilExit()
    guard compiler.terminationStatus == 0 else {
        throw PluginBuildFailed(log: log)
    }
    return library
}

/// Where SwiftPM put this test bundle: `<build>/EasyDIPackageTests.xctest/Contents/MacOS/…`.
private func buildDirectory() throws -> URL {
    var info = Dl_info()
    guard dladdr(unsafeBitCast(countRun, to: UnsafeRawPointer.self), &info) != 0, let name = info.dli_fname else {
        throw PluginBuildFailed(log: "can't find the test bundle")
    }
    return URL(filePath: String(cString: name))
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct PluginBuildFailed: Error, CustomStringConvertible {
    let log: String
    var description: String { "the late library didn't build:\n\(log)" }
}
#endif
