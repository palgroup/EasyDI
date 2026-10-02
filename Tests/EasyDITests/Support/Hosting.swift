import EasyDI
import Foundation
import SwiftUI

#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Puts a SwiftUI view in a window so it is built, laid out and appears, as in an app.
@MainActor
final class Host {
    #if canImport(UIKit)
    private let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    #else
    private let window = NSWindow(
        contentRect: NSRect(x: 0, y: 0, width: 390, height: 844),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    #endif

    init(_ view: some View) {
        #if canImport(UIKit)
        window.rootViewController = UIHostingController(rootView: view)
        window.isHidden = false
        window.layoutIfNeeded()
        #else
        _ = NSApplication.shared
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: view)
        window.orderFrontRegardless()
        window.layoutIfNeeded()
        #endif
    }

    func close() {
        #if canImport(UIKit)
        window.isHidden = true
        window.rootViewController = nil
        #else
        window.contentView = nil
        window.close()
        #endif
    }
}

/// Lets the run loop turn until `condition` holds: SwiftUI updates the view on its turns.
@MainActor
func eventually(timeout: Duration = .seconds(5), _ condition: () -> Bool) -> Bool {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        guard ContinuousClock.now < deadline else { return false }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
    }
    return true
}

/// What `@Inject` gives here: a local wrapper can't sit in a closure.
func resolve<Value>() -> Value {
    @Inject var value: Value
    return value
}
