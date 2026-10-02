# Changelog

All notable changes to EasyDI are documented here.

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
  `.weak`, a dependency cycle, two default mocks and an unknown mock name stop
  the app with a message naming what to fix.
- `Injection.registrations` lists every contract, its provider, its mocks and
  whether an instance is alive.
