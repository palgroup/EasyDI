import EasyDI
import Foundation
import Observation

// Each test reads its own contracts: tests run in parallel and share one container.

// MARK: Registration and resolution

protocol Greeter: AnyObject {
    func greet() -> String
}

@Injectable(as: Greeter.self)
final class EnglishGreeter: Greeter {
    func greet() -> String { "Hello" }
}

/// Provides itself.
@Injectable
final class Clock {
    let started = Date()
}

protocol HTTPClient: AnyObject {}

@Injectable(as: HTTPClient.self)
final class URLSessionHTTPClient: HTTPClient {}

protocol Storage: AnyObject {
    var http: any HTTPClient { get }
}

@Injectable(as: Storage.self)
final class RemoteStorage: Storage {
    @Inject var http: any HTTPClient
}

/// Not registered: a consumer, like a screen's data.
final class Repository {
    @Inject var storage: any Storage
}

protocol Settings {
    var theme: String { get }
}

@Injectable(as: Settings.self)
struct DefaultSettings: Settings {
    var theme = "light"
}

protocol Counter: Actor {
    func next() -> Int
}

@Injectable(as: Counter.self)
actor LiveCounter: Counter {
    private var value = 0

    func next() -> Int {
        value += 1
        return value
    }
}

protocol Session: AnyObject {
    var user: String? { get set }
}

@Injectable(as: Session.self)
@Observable
final class LiveSession: Session {
    var user: String?
}

enum Outer {
    @Injectable(as: Nested.self)
    final class NestedProvider: Nested {}
}

protocol Nested: AnyObject {}

// MARK: Lifetimes

protocol SingletonService: AnyObject {}

@Injectable(as: SingletonService.self, .singleton)
final class SingletonServiceImpl: SingletonService {}

protocol DefaultLifetimeService: AnyObject {}

@Injectable(as: DefaultLifetimeService.self)
final class DefaultLifetimeServiceImpl: DefaultLifetimeService {}

protocol WeakService: AnyObject {}

@Injectable(as: WeakService.self, .weak)
final class WeakServiceImpl: WeakService {}

protocol TransientService: AnyObject {}

@Injectable(as: TransientService.self, .transient)
final class TransientServiceImpl: TransientService {}

/// A `.weak` provider only the cycling tests use, so its count is theirs.
protocol Cycled: AnyObject {}

@Injectable(as: Cycled.self, .weak)
final class CycledImpl: Cycled {}

// MARK: Mocks

protocol NoteStore: AnyObject {
    var scenario: String { get }
}

@Injectable(as: NoteStore.self, .weak)
final class LiveNoteStore: NoteStore {
    let scenario = "live"
}

@Mock(NoteStore.self)
final class MockNoteStore: NoteStore {
    let scenario: String

    init() {
        scenario = "seeded"
    }

    init(scenario: String) {
        self.scenario = scenario
    }

    @Mock(NoteStore.self, "empty")
    static var empty: MockNoteStore { MockNoteStore(scenario: "empty") }

    @Mock(NoteStore.self, "failing")
    static var failing: MockNoteStore { MockNoteStore(scenario: "failing") }
}

/// A second contract with a "failing" mock, to show a name reaching every contract that has it.
protocol Weather: AnyObject {
    var forecast: String { get }
}

@Injectable(as: Weather.self)
final class LiveWeather: Weather {
    let forecast = "live"
}

extension LiveWeather {
    @Mock(Weather.self, "failing")
    static var failing: any Weather { StubWeather(forecast: "failing") }
}

final class StubWeather: Weather {
    let forecast: String

    init(forecast: String) {
        self.forecast = forecast
    }
}

@MainActor
@Observable
final class NotesData {
    @ObservationIgnored @Inject var store: any NoteStore
    @ObservationIgnored @Inject var weather: any Weather
}

/// Built with whatever `NoteStore` is in effect; kept by the app only without a selection.
protocol Feed: AnyObject {
    var store: any NoteStore { get }
}

@Injectable(as: Feed.self, .weak)
final class LiveFeed: Feed {
    @Inject var store: any NoteStore
}

protocol Inbox: AnyObject {
    var store: any NoteStore { get }
}

@Injectable(as: Inbox.self, .weak)
final class LiveInbox: Inbox {
    @Inject var store: any NoteStore
}

/// A chain of `.singleton`s, to check that selections in sequence never replace the app's.
protocol ChainTop: AnyObject {
    var repo: any ChainRepo { get }
}

protocol ChainRepo: AnyObject {
    var storage: any ChainStorage { get }
}

protocol ChainStorage: AnyObject {
    var http: any ChainHTTP { get }
}

protocol ChainHTTP: AnyObject {
    var mode: String { get }
}

@Injectable(as: ChainTop.self)
final class ChainTopImpl: ChainTop {
    @Inject var repo: any ChainRepo
}

@Injectable(as: ChainRepo.self)
final class ChainRepoImpl: ChainRepo {
    @Inject var storage: any ChainStorage
}

@Injectable(as: ChainStorage.self)
final class ChainStorageImpl: ChainStorage {
    @Inject var http: any ChainHTTP
}

@Injectable(as: ChainHTTP.self)
final class LiveChainHTTP: ChainHTTP {
    let mode = "live"
}

extension LiveChainHTTP {
    @Mock(ChainHTTP.self, "chain-offline")
    static var offline: any ChainHTTP { StubChainHTTP(mode: "offline") }
}

final class StubChainHTTP: ChainHTTP {
    let mode: String

    init(mode: String) {
        self.mode = mode
    }
}

final class FakeChainStorage: ChainStorage {
    let http: any ChainHTTP = StubChainHTTP(mode: "fake")
}

/// A mock with a dependency of its own: a later selection that replaces it gets a new mock.
protocol Gadget: AnyObject {
    var part: any Part { get }
}

protocol Part: AnyObject {
    var kind: String { get }
}

@Injectable(as: Part.self)
final class LivePart: Part {
    let kind = "live"
}

extension LivePart {
    @Mock(Part.self, "special-part")
    static var special: any Part { StubPart(kind: "special") }
}

final class StubPart: Part {
    let kind: String

    init(kind: String) {
        self.kind = kind
    }
}

final class MockGadget: Gadget {
    @Inject var part: any Part

    @Mock(Gadget.self, "gadget")
    static var mock: MockGadget { MockGadget() }
}

/// Registered by hand, twice, the way a preview that reloads its code would.
protocol Reloaded: AnyObject {}

final class ReloadedImpl: Reloaded {}

// MARK: Stops — resolved only inside exit tests

protocol Duplicated {}

@Injectable(as: Duplicated.self)
struct FirstDuplicate: Duplicated {}

@Injectable(as: Duplicated.self)
struct SecondDuplicate: Duplicated {}

protocol Unprovided {}

protocol OnlyMocked: AnyObject {}

@Mock(OnlyMocked.self)
final class MockOnly: OnlyMocked {}

protocol Captive: AnyObject {}

@Injectable(as: Captive.self, .weak)
final class CaptiveImpl: Captive {}

protocol AppWide: AnyObject {}

@Injectable(as: AppWide.self)
final class AppWideImpl: AppWide {
    @Inject var captive: any Captive
}

protocol CycleA: AnyObject {}

protocol CycleB: AnyObject {}

@Injectable(as: CycleA.self, .transient)
final class CycleAImpl: CycleA {
    @Inject var b: any CycleB
}

@Injectable(as: CycleB.self, .transient)
final class CycleBImpl: CycleB {
    @Inject var a: any CycleA
}

protocol DoubleMocked {}

@Mock(DoubleMocked.self)
struct FirstMock: DoubleMocked {}

@Mock(DoubleMocked.self)
struct SecondMock: DoubleMocked {}

/// Registered nowhere: `.inject` can't tell what it stands for.
final class Unregistered: NoteStore {
    let scenario = "unregistered"
}

protocol MockCycleA: AnyObject {}

protocol MockCycleB: AnyObject {}

@Mock(MockCycleA.self)
final class MockCycleAImpl: MockCycleA {
    @Inject var b: any MockCycleB
}

@Mock(MockCycleB.self)
final class MockCycleBImpl: MockCycleB {
    @Inject var a: any MockCycleA
}

/// A `.singleton` holding a `.weak` through a `.transient` it keeps.
protocol FarOwner: AnyObject {}

protocol Middle: AnyObject {}

protocol FarWeak: AnyObject {}

@Injectable(as: FarOwner.self)
final class FarOwnerImpl: FarOwner {
    @Inject var middle: any Middle
}

@Injectable(as: Middle.self, .transient)
final class MiddleImpl: Middle {
    @Inject var far: any FarWeak
}

@Injectable(as: FarWeak.self, .weak)
final class FarWeakImpl: FarWeak {}

/// One type registered for two contracts: `.inject` can't tell which.
protocol Twice: AnyObject {}

final class DoubleDuty: Greeter, Twice {
    func greet() -> String { "Hi" }

    @Mock(Greeter.self, "double-greeter")
    static var greeter: DoubleDuty { DoubleDuty() }

    @Mock(Twice.self, "double-twice")
    static var twice: DoubleDuty { DoubleDuty() }
}

/// Two mocks with one name for one contract.
protocol Named: AnyObject {}

final class FirstNamed: Named {
    @Mock(Named.self, "same")
    static var same: FirstNamed { FirstNamed() }
}

final class SecondNamed: Named {
    @Mock(Named.self, "same")
    static var same: SecondNamed { SecondNamed() }
}
