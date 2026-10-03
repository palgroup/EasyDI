# EasyDI

Dependency injection for Swift apps with no container to fill in. Mark the
type that provides a protocol, ask for the protocol where you need it:

```swift
import EasyDI

@Injectable(as: NoteService.self, .weak)
final class LiveNoteService: NoteService {
    @Inject private var http: any HTTPClient
}

@MainActor @Observable
final class NoteListData {
    @ObservationIgnored @Inject private var notes: any NoteService
}
```

There is no registration list. `@Injectable` leaves a record in the binary,
and EasyDI finds every record the first time something is resolved. Previews
use mocks without any setup, and a preview can name the mock it wants:

```swift
@Mock(NoteService.self)
final class MockNoteService: NoteService {
    @Mock(NoteService.self, "failing")
    static var failing: MockNoteService { MockNoteService(scenario: .failing) }
}

#Preview("Error") {
    Injection.with(.mock("failing")) { NoteListScreen(data: NoteListData()) }
}
```

Requires Swift 6.3 or later (the first with `@section`), iOS 18 or macOS 15.
Other platforms aren't supported.

## Installation

```swift
.package(url: "https://github.com/palgroup/EasyDI.git", from: "2.0.0")
```

Add the `EasyDI` product to your target. The first build asks Xcode to trust
the package's macros.

## Providers

```swift
@Injectable(as: NoteService.self)              // provides NoteService, one for the app
@Injectable(as: NoteService.self, .weak)       // shared while used, then released
@Injectable(as: NoteService.self, .transient)  // a new one for every request
@Injectable                                    // provides itself: @Inject var clock: Clock
```

- The type is built with `init()`; without one the expansion doesn't compile.
  Its own `@Inject` properties are resolved while it is built, so dependencies
  of dependencies just work.
- The compiler checks that the type conforms to the contract.
- Classes, structs and actors can be providers. `.weak` needs a class.
- A type provides one contract.
- A class that needs parameters isn't a provider: give it an `init(…)` with
  them and its own `@Inject` properties, and build it yourself.

| Lifetime | Instance | Use it for |
|---|---|---|
| `.singleton` (default) | One for the whole app, made on first use | HTTP client, session, settings |
| `.weak` | Shared while something holds it; released after the last holder, made again on the next request | A feature's service: it lives while its screens are open |
| `.transient` | New for every request | Formatters, small helpers |

## Consumers

```swift
@MainActor @Observable
final class NoteListData {
    @ObservationIgnored @Inject private var notes: any NoteService
}
```

- `@Inject` resolves when the owner is initialised, on the main actor.
- In an `@Observable` class the property needs `@ObservationIgnored`: it never
  changes.
- `@Injectable` and `@Observable` can sit on the same class. Everyone gets the
  same instance, and observation works through the protocol.

### `@State @Inject` doesn't compile

```swift
@State @Inject private var draft: Draft   // doesn't compile: nothing builds the State
```

Property wrappers stacked without an initial value are built with the outer
one's `init()`, and `State` has one only for an optional value. What to write
instead:

- In a screen's `@Observable` data, `@Inject` the shared object and let the
  view read it through the data. SwiftUI observes what `body` reads, however
  it got there.
- In a view, `@Inject` alone: `@Inject private var counter: any Counter`. It
  resolves each time the view is initialised; a `.singleton` or `.weak`
  provider hands out the same instance, and the view observes what it reads.
- For an instance the view owns (a `.transient` one), give `@State` an initial
  value: `@State private var draft = Inject<Draft>().wrappedValue`. As with any
  `@State` holding a class, that runs whenever the view is initialised and
  SwiftUI keeps the first. `$draft.text` binds to it.

## Mocks

```swift
@Mock(NoteService.self)                     // the default mock: a type, built with init()
final class MockNoteService: NoteService {
    @Mock(NoteService.self, "empty")        // named mocks: static properties
    static var empty: MockNoteService { MockNoteService(scenario: .empty) }

    @Mock(NoteService.self, "failing")
    static var failing: MockNoteService { MockNoteService(scenario: .failing) }
}
```

Which one a request gets:

1. A selection around it (`Injection.with`): `.inject(instance)` or `.mock("name")`.
2. In a preview, or with `Injection.usesDefaultMocks` on, the contract's
   default mock.
3. The `@Injectable` provider.

The app never uses a mock unless it is selected or `usesDefaultMocks` is on. A selected mock is shared
while something holds it, like a `.weak` provider. Tests that run in parallel
and count calls on a mock should inject their own instance instead:
`.inject(spy, as: (any NoteService).self)`.

Mock types ship in release builds unless you wrap them in `#if DEBUG`.

## Choosing mocks

Screens stay plain; a preview names the mock it wants, and one preview host
applies it while it builds the screen:

```swift
enum NoteListBuilder {
    static func build() -> some View {
        NoteListScreen(data: NoteListData())
    }

    static func mock(_ name: String? = nil) -> some View {
        PreviewHost(mock: name) { build() }
    }
}

struct PreviewHost<Content: View>: View {
    let mock: String?
    @ViewBuilder let content: () -> Content

    var body: some View {
        if let mock {
            Injection.with(.mock(mock)) { content() }
        } else {
            content()
        }
    }
}

#Preview("Loaded") { NoteListBuilder.mock() }             // the default mock
#Preview("Empty") { NoteListBuilder.mock("empty") }
#Preview("Error") { NoteListBuilder.mock("failing") }
```

`Injection.with` builds what its closure returns with the selection in effect;
everything that closure initialises, and their own `@Inject` properties, get
the selected mocks.

- `.mock("failing")` picks the mock named "failing" for every contract that
  has one. Contracts without one keep their provider, or their default mock
  where default mocks are used (previews, `Injection.usesDefaultMocks`).
- `.mock("failing", for: (any NoteService).self)` picks it for one contract.
- `.inject(instance)` uses that instance for the contract its type is
  registered for. For a type registered nowhere, use
  `.inject(instance, as: (any NoteService).self)`.
- `Injection.with(.mock("failing"), .mock("empty")) { … }`: for each contract
  the later choice wins, and a nested `Injection.with` wins over the outer one.
- The selection reaches what is initialised inside the closure. A view that
  builds its own data later, when SwiftUI draws it, is outside it: in a
  preview it gets the default mock.
- A provider built inside a selection, with a selected mock in it, isn't
  kept for the rest of the app. A kept provider whose dependency the selection
  replaces is built again for the selection.

The same in a unit test:

```swift
let data = Injection.with(.mock("failing")) { NoteListData() }
let other = Injection.with(.inject(spy, as: (any NoteService).self)) { NoteListData() }
```

UI tests that should see the mocks instead of the real services turn the
default mocks on at launch, before anything is resolved. Changing it after a
provider or mock was built stops the app: what was built keeps what it got.
So unit tests don't switch it per test; they pick mocks with
`Injection.with(.mock(…))` or hand in instances with `.inject(…)`.

```swift
// in the app's init, when a launch argument the UI test passes is present
Injection.usesDefaultMocks = true
```

## Mistakes stop the app, naming what to fix

Each of these stops the app. The provider and mock mistakes stop when that
contract is first asked for; an unknown mock name stops where `.mock(…)` is
written, and a late `usesDefaultMocks` where it is set.

| Mistake | Message |
|---|---|
| Two providers for one contract | `NoteService has 2 providers: LiveNoteService, OtherNoteService. Keep one @Injectable(as: NoteService.self).` |
| Nothing provides it | `nothing provides NoteService. Mark the type that does with @Injectable(as: NoteService.self).` |
| A `.singleton` takes a `.weak`, directly or through `.transient`s (debug builds) | `AppSession is a .singleton, it lives as long as the app, but it takes LiveNoteService, which is .weak: it would never be released. Make LiveNoteService .singleton or AppSession .weak.` |
| Providers or mocks that need each other | `LiveA → LiveB → LiveA is a cycle: each one needs the next to be built.` |
| Two default mocks, or two mocks with one name | `NoteService has two default mocks: MockA and MockB. Keep one.` |
| `.mock("faling")` | `no mock is named "faling". Named mocks: "empty", "failing".` |
| `usesDefaultMocks` changed after something was built | `Injection.usesDefaultMocks was turned on after AppSession and LiveNoteService were built, and what is built keeps what it got.` |

The macros report at compile time: `.weak` on a value type, a generic type,
`@Mock` on an instance property.

## What is registered, and what is alive

```swift
for registration in Injection.registrations {
    // contract, provider, lifetime, mocks, isAlive, made
}
```

Each `Registration` names the contract, its provider and lifetime, and its
mocks (`"default"` and the named ones). `isAlive` says whether an instance is
kept right now; `made` counts the instances built so far. A debug screen listing these shows `.weak` services
being released when their screens close.

## How it works

`@Injectable` and `@Mock` add a static constant to the type, placed in the
`__DATA,__easydi` section of the binary with `@section` and `@used`
(SE-0492). The constant is a C function pointer that registers the type.
On the first resolution, EasyDI registers a dyld callback. dyld calls it for
every image already loaded and for each one loaded later, such as a framework
opened with `dlopen` or the code a preview loads. The callback reads the
section, and the records run on the main actor.

Xcode's canvas doesn't load the app's code through dyld: its JIT linker maps
the code, and dyld only sees an empty placeholder for it. So the macros also
write every record as a small class. In a preview (`XCODE_RUNNING_FOR_PREVIEWS`
is set), EasyDI finds those classes through the Objective-C runtime on the
first resolution, which takes about 0.15 s with the 80,000 classes of a preview
process. If a contract is still missing, it looks again before stopping.

Resolution is synchronous, on the main actor, while the owner is initialised.
That is why a provider's dependencies can be checked as it is built, and why
`Injection.with` can apply a selection while a screen's data is made.

## Performance

Measured on an Apple M2 Pro, macOS 26.3, Swift 6.3.3, release build
(`Benchmarks/`, run with `swift run -c release`):

| | Time |
|---|---|
| First resolution, 1,000 providers registered | 3.2–3.6 ms; 24–27 ms on the first launch after a build |
| `.singleton`, already built | 110–125 ns |
| `.transient` (builds an empty class) | 240–250 ns |
| `.weak`, held elsewhere | 320–335 ns |
| `.weak`, built and released | 400 ns |

Memory, measured by the tests as `phys_footprint`, the number Xcode's memory
gauge shows:

- After 100,000 resolutions (a third `.singleton`, a third `.weak`, a third
  `.transient`, a selection every tenth): growth of 0–16 KB. The limit is 1 MB.
- After 10,000 `.weak` build-and-release cycles: every instance released and
  growth of 0–32 KB.

The tests pass under `leaks` (0 leaks) and under Address and Thread
Sanitizer. They run on macOS with Swift 6.3.3 and 6.4.0 (62 tests), and on the
iOS Simulator (28: the stops, the memory measurements, the macro expansions and
the libraries compiled during the test need macOS).

## Limits

- Resolution is on the main actor. `@Inject` can't be used in an actor or in
  a `nonisolated` type. In a module whose default isolation isn't
  `MainActor` (most packages), mark providers and the classes that `@Inject`
  with `@MainActor`.
- A contract is a protocol. A class named in `as:` or `@Mock` fails with
  "'any' has no effect on concrete type". A concrete type registered without
  `as:` is its own contract and can't have mocks; give it a protocol to mock it.
- iOS and macOS only: the records are found through dyld.
- The records must reach the app's binary. SwiftPM and Xcode targets link
  every object file, so they do. A static library (`.a`) drops the object files
  nothing refers to, and an `@Injectable` type is exactly that: link it with
  `-force_load` (or Bazel's `alwayslink`), or as a dynamic framework.
- With Swift 7 or ExistentialAny on, a protocol's metatype in your own code
  is `(any NoteService).self`. Inside `@Injectable(as:)` and `@Mock(…)`,
  `NoteService.self` works either way.

## Tests

```bash
swift test                                         # macOS
xcodebuild test -scheme EasyDI -destination 'platform=iOS Simulator,name=<device>' -skipMacroValidation
ASAN_OPTIONS=strip_env=0 swift test --sanitize=address
TSAN_OPTIONS=strip_env=0 swift test --sanitize=thread
```

`strip_env=0` keeps the sanitizer in the child processes that test the stops
(Swift Testing's exit tests). Those, and the macro tests, run on macOS only.
