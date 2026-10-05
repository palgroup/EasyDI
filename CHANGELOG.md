# Changelog

All notable changes to EasyDI are documented here.

## [2.1.0] — 2026-10-05

### Added

- `Injection.Selection.defaultMocks`: every contract's default mock, for screens
  built inside the running app (debug screens that show mocked screens), where
  no preview gives them by itself and `usesDefaultMocks` can no longer change.
  A named mock selected after it wins for the contracts that have one.

## [2.0.1] — 2026-10-03

### Changed

- Changing `Injection.usesDefaultMocks` after a provider or mock was built now
  stops the app, naming what was built. Before, a kept `.singleton` went on
  handing out what it was built with, so the app mixed mocks and real services.
  Set it first thing in the app's init. Tests that turned it on and off per
  test stop now: pick mocks with `Injection.with(.mock(…))` or hand in
  instances with `.inject(…)` instead.

### Fixed

- `.inject(instance)` in a preview looks for records the canvas loaded late, as
  a provider or mock lookup already did, before stopping with "isn't marked
  @Injectable or @Mock".

### Documentation

- Why `@State @Inject` doesn't compile, and what to write instead.

## [2.0.0] — 2026-10-03

### Breaking

- **`Injected` and the `.mock(_:)`, `.mock(_:for:)`, `.inject(_:)` and
  `.inject(_:as:)` view modifiers are removed.** Every screen's builder had to
  wrap its content in `Injected { }` so a selection in the environment could
  reach the screen's data. Previews don't navigate and apps don't select
  mocks, so one place is enough: the preview host builds the screen inside
  `Injection.with(.mock("failing")) { … }`.
- `Injection.Selection` is no longer `Hashable`: it only told `Injected` when
  to build its content again.

### Added

- `Injection.usesDefaultMocks`: contracts with a default mock get it when
  nothing is selected, as in a preview. Turn it on at launch for UI tests that
  should see the mocks.

### Migration

    // 1.x
    static func build() -> some View { Injected { NoteListScreen(data: NoteListData()) } }
    #Preview { NoteListBuilder.build().mock("failing") }

    // 2.0
    static func build() -> some View { NoteListScreen(data: NoteListData()) }
    #Preview { Injection.with(.mock("failing")) { NoteListBuilder.build() } }

## [1.0.1] — 2026-10-02

### Fixed

- **Nothing was registered in Xcode's canvas**, so every preview that
  injected something stopped with "nothing provides …". The canvas loads the
  app's code with its own JIT linker, which dyld doesn't see, so the
  `__DATA,__easydi` section was never read. The macros now also write each
  record as a class; in a preview EasyDI finds those classes through the
  Objective-C runtime. The app outside previews still reads the section.

## [1.0.0] — 2026-10-02

First release.

- `@Injectable(as:_:)` registers a provider with no central list: the macro
  places a record in the binary, found through dyld on the first resolution.
- Lifetimes `.singleton` (default), `.weak` and `.transient`.
- `@Inject` resolves a dependency by its protocol when its owner is initialised.
- `@Mock(_:_:)` registers a default mock and named mocks, on a type or a static
  property. Previews use the default mock by themselves.
- `Injected { … }` with `.mock(_:)`, `.mock(_:for:)`, `.inject(_:)` and
  `.inject(_:as:)` choose mocks and instances for a screen and the screens it
  opens. `Injection.with(_:build:)` does the same outside SwiftUI.
- Two providers for one contract, a missing provider, a `.singleton` taking a
  `.weak` (directly or through `.transient`s), a cycle of providers or mocks,
  two mocks with one name and an unknown mock name stop the app with a message
  naming what to fix.
- `Injection.registrations` lists every contract, its provider, its mocks and
  whether an instance is alive.
