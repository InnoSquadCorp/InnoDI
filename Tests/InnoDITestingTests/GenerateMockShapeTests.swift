import InnoDITesting
import Testing

// Each `@GenerateMock` shape below once expanded to a mock that failed to
// compile, or compiled and misbehaved. Its control, which always compiled,
// sits next to it. This target builds with strict concurrency and warnings as
// errors, so a regression in any expansion fails the build.

// MARK: - `where Self:` refinements (G1)

@GenerateMock
protocol WhereSendableAPI where Self: Sendable {
    func ping() -> Int
}

@GenerateMock
protocol InheritedSendableAPI: Sendable {
    func ping() -> Int
}

@GenerateMock
protocol WhereClassBoundAPI where Self: AnyObject {
    func ping() -> Int
}

// MARK: - Ownership and `sending` parameters on `Sendable` protocols (G2, G3)

@GenerateMock
protocol SendableMoverAPI: Sendable {
    func move(_ from: borrowing String, _ to: consuming String)
    func send(_ value: sending String)
}

@GenerateMock
protocol SendableSingleOwnershipAPI: Sendable {
    func move(_ from: borrowing String, _ to: String)
    func send(_ value: String)
}

@GenerateMock
protocol MoverAPI {
    func move(_ from: borrowing String, _ to: consuming String)
    func send(_ value: sending String)
}

// MARK: - Call records that shadow signature types (G4)

struct ToolCall: Equatable {
    let name: String
}

struct StartCall: Equatable {
    let id: Int
}

struct FetchCall: Equatable {
    let id: Int
}

struct ToolInvocation: Equatable {
    let name: String
}

@GenerateMock
protocol ToolRunnerAPI {
    func tool(named name: String) -> ToolCall
    func start(_ call: StartCall)
    func fetch()
    func log(_ entry: FetchCall)
}

@GenerateMock
protocol ToolInvocationAPI {
    func tool(named name: String) -> ToolInvocation
}

// MARK: - Function types with optional results (G5)

@GenerateMock
protocol LoaderFactoryAPI {
    func loader() -> () -> Int?
    var parse: (String) -> Int? { get set }
    func plain() -> () -> Int
    func optionalLoader() -> (() -> Int)?
}

@GenerateMock
protocol SendableLoaderFactoryAPI: Sendable {
    func loader() -> @Sendable () -> Int?
    var parse: @Sendable (String) -> Int? { get set }
}

// MARK: - Multi-line types (G6)

@GenerateMock
protocol PagerAPI {
    func page() -> (
        items: [Int], // first page
        next: Int?
    )
    var cursor: (
        offset: Int,
        limit: Int
    ) { get set }
    func decode<T>(_ type: T.Type) -> (
        value: T,
        count: Int
    )
    func optionalPage() -> (
        items: [Int],
        next: Int?
    )?
}

// MARK: - Implicitly unwrapped optionals (G7)

@GenerateMock
protocol NamedAPI {
    var name: String! { get set }
    func find() -> String!
    func lookup() throws -> String!
    var optionalName: String? { get set }
    func accept(_ value: String!)
}

// MARK: - Optional spellings (G8)

typealias MaybeInt = Int?

@GenerateMock
protocol OptionalSpellingAPI {
    func sugar() -> Int?
    func named() -> Optional<Int>
    func qualified() -> Swift.Optional<Int>
    func parenthesized() -> (Int?)
    func aliased() -> MaybeInt
    func required() -> Int
}

@GenerateMock
protocol SendableOptionalSpellingAPI: Sendable {
    func named() -> Optional<Int>
    func aliased() -> MaybeInt
}

// MARK: - A nested type named `Error` (G9)

enum MockNetworking {
    enum Error: Swift.Error {
        case offline
    }

    @GenerateMock
    protocol Client {
        func send() throws -> Int
        func ping() throws
    }

    @GenerateMock
    protocol SharedClient: Sendable {
        func send() throws -> Int
        func ping() throws
    }
}

// MARK: - Member availability (G10)

@available(macOS 99, iOS 99, tvOS 99, watchOS 99, visionOS 99, *)
struct FutureThing {}

@available(macOS 99, iOS 99, tvOS 99, watchOS 99, visionOS 99, *)
@GenerateMock
protocol FutureAPI {
    @available(macOS 99, iOS 99, tvOS 99, watchOS 99, visionOS 99, *)
    func make() -> FutureThing
}

@GenerateMock
protocol DeployedAvailabilityAPI {
    @available(macOS 13, iOS 16, *)
    func run() -> Int
    @available(macOS, introduced: 14)
    var title: String { get }
    @available(*, deprecated, message: "Use run()")
    func legacy()
}

// MARK: - Rare spellings (G11)

@GenerateMock
protocol RareSpellingAPI {
    func _2fa() -> Bool
    func schedule(await: Bool, `inout`: Int, copy: borrowing String)
}

@GenerateMock
protocol SendableRareSpellingAPI: Sendable {
    func schedule(await: Bool, `inout`: Int, copy: borrowing String)
}

@Suite("GenerateMock shape regressions")
struct GenerateMockShapeTests {
    @Test("A where-clause Sendable refinement selects lock-backed storage")
    func whereSendableUsesConcurrentStorage() async {
        let mock = WhereSendableAPIMock()
        mock.pingReturnValue = 3
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<50 {
                group.addTask { #expect(mock.ping() == 3) }
            }
        }
        #expect(mock.pingCalls.count == 50)

        let control = InheritedSendableAPIMock()
        control.pingReturnValue = 4
        #expect(control.ping() == 4)

        let bound = WhereClassBoundAPIMock()
        bound.pingReturnValue = 5
        #expect(bound.ping() == 5)
    }

    @Test("Sendable mocks copy every ownership and sending argument")
    func sendableOwnershipArgumentsAreRecorded() {
        let mock = SendableMoverAPIMock()
        mock.move("a", "b")
        mock.send("c")
        #expect(mock.moveCalls.map(\.from) == ["a"])
        #expect(mock.moveCalls.map(\.to) == ["b"])
        #expect(mock.sendCalls.map(\.value) == ["c"])

        let single = SendableSingleOwnershipAPIMock()
        single.move("a", "b")
        single.send("c")
        #expect(single.moveCalls.map(\.to) == ["b"])
        #expect(single.sendCalls.map(\.value) == ["c"])

        let plain = MoverAPIMock()
        plain.move("a", "b")
        plain.send("c")
        #expect(plain.moveCalls.map(\.from) == ["a"])
        #expect(plain.sendCalls.map(\.value) == ["c"])
    }

    @Test("Call records do not hide same-named signature types")
    func callRecordsKeepSignatureTypes() {
        let mock = ToolRunnerAPIMock()
        mock.toolReturnValue = ToolCall(name: "stub")
        #expect(mock.tool(named: "x") == ToolCall(name: "stub"))
        #expect(mock.toolCalls.map(\.name) == ["x"])
        mock.start(StartCall(id: 7))
        #expect(mock.startCalls.map(\.call) == [StartCall(id: 7)])
        mock.fetch()
        mock.log(FetchCall(id: 2))
        #expect(mock.fetchCalls.count == 1)
        #expect(mock.logCalls.map(\.entry) == [FetchCall(id: 2)])
        #expect(mock.recordedCallCounts == ["tool": 1, "start": 1, "fetch": 1, "log": 1])

        let control = ToolInvocationAPIMock()
        control.toolReturnValue = ToolInvocation(name: "stub")
        #expect(control.tool(named: "y") == ToolInvocation(name: "stub"))
    }

    @Test("Function-typed stubs with optional results return the stub")
    func functionTypesWithOptionalResults() {
        let mock = LoaderFactoryAPIMock()
        mock.loaderReturnValue = { nil }
        #expect(mock.loader()() == nil)
        mock.parse = { Int($0) }
        #expect(mock.parse("12") == 12)
        mock.plainReturnValue = { 1 }
        #expect(mock.plain()() == 1)
        mock.optionalLoaderReturnValue = nil
        #expect(mock.optionalLoader() == nil)
        #expect(mock.missingStubSelectors.isEmpty)

        let shared = SendableLoaderFactoryAPIMock()
        shared.loaderReturnValue = { 3 }
        #expect(shared.loader()() == 3)
        shared.parse = { _ in nil }
        #expect(shared.parse("x") == nil)
    }

    @Test("Multi-line types keep valid stub storage and messages")
    func multiLineTypes() {
        let mock = PagerAPIMock()
        mock.pageReturnValue = (items: [1], next: 2)
        #expect(mock.page().items == [1])
        mock.cursor = (offset: 1, limit: 2)
        #expect(mock.cursor.limit == 2)
        mock.decodeUnlabeledTTypeHandler = { _ in (value: "v", count: 1) }
        let decoded: (value: String, count: Int) = mock.decode(String.self)
        #expect(decoded.value == "v")
        mock.optionalPageReturnValue = nil
        #expect(mock.optionalPage() == nil)
    }

    @Test("Implicitly unwrapped optional requirements store optional stubs")
    func implicitlyUnwrappedOptionals() throws {
        let mock = NamedAPIMock()
        mock.name = nil
        #expect(mock.name == nil)
        mock.name = "Ada"
        #expect(mock.name == "Ada")
        mock.findReturnValue = nil
        #expect(mock.find() == nil)
        mock.findReturnValue = "x"
        #expect(mock.find() == "x")
        mock.lookupResult = .success(nil)
        #expect(try mock.lookup() == nil)
        mock.optionalName = nil
        mock.accept(nil)
        #expect(mock.acceptCalls.count == 1)
        #expect(mock.missingStubSelectors.isEmpty)
    }

    @Test("Optional<T> stubs a nil result like T?, and stub validation agrees with the call")
    func optionalSpellings() throws {
        let mock = OptionalSpellingAPIMock()
        #expect(Set(mock.missingStubSelectors) == [
            "sugar", "named", "qualified", "parenthesized", "aliased", "required",
        ])

        mock.sugarReturnValue = nil
        mock.namedReturnValue = nil
        mock.qualifiedReturnValue = nil
        mock.parenthesizedReturnValue = nil
        #expect(Set(mock.missingStubSelectors) == ["aliased", "required"])
        #expect(mock.sugar() == nil)
        #expect(mock.named() == nil)
        #expect(mock.qualified() == nil)
        #expect(mock.parenthesized() == nil)

        // A typealias hides the optional from the macro: a bare `nil` leaves
        // the stub missing, so validation fails before the call would trap.
        mock.aliasedReturnValue = nil
        mock.requiredReturnValue = nil
        #expect(Set(mock.missingStubSelectors) == ["aliased", "required"])
        #expect(throws: DIMissingStubError.self) {
            try DIStubValidation.requireAllStubbed(mock.missingStubSelectors)
        }

        // `.some(nil)` stubs the aliased optional's nil result explicitly.
        mock.aliasedReturnValue = .some(nil)
        mock.requiredReturnValue = 4
        try DIStubValidation.requireAllStubbed(mock.missingStubSelectors)
        #expect(mock.aliased() == nil)
        #expect(mock.required() == 4)

        mock.innoDIReset(.all)
        #expect(mock.missingStubSelectors.count == 6)

        let shared = SendableOptionalSpellingAPIMock()
        shared.namedReturnValue = nil
        shared.aliasedReturnValue = nil
        #expect(shared.missingStubSelectors == ["aliased"])
        #expect(shared.named() == nil)
        shared.aliasedReturnValue = .some(nil)
        #expect(shared.missingStubSelectors.isEmpty)
        #expect(shared.aliased() == nil)
    }

    @Test("Generated mocks keep Swift's Error next to a nested type named Error")
    func nestedErrorTypeDoesNotCaptureMocks() throws {
        struct Failure: Swift.Error {}

        let mock = MockNetworking.ClientMock()
        mock.sendResult = .failure(Failure())
        #expect(throws: Failure.self) { try mock.send() }
        mock.pingThrownError = MockNetworking.Error.offline
        #expect(throws: MockNetworking.Error.self) { try mock.ping() }
        mock.sendResult = .success(1)
        #expect(try mock.send() == 1)

        let shared = MockNetworking.SharedClientMock()
        #expect(throws: (any Swift.Error).self) { try shared.send() }
        shared.pingThrownError = Failure()
        #expect(throws: Failure.self) { try shared.ping() }
    }

    @Test("Member availability within InnoDI's platforms keeps the mock")
    func deployedMemberAvailability() {
        let mock = DeployedAvailabilityAPIMock()
        mock.runReturnValue = 1
        mock.title = "t"
        #expect(mock.run() == 1)
        #expect(mock.title == "t")
        mock.legacy()
        #expect(mock.legacyCalls.count == 1)
        #expect(FutureAPIMock.self == FutureAPIMock.self)
    }

    @Test("Rare identifier spellings expand to valid helpers")
    func rareSpellings() {
        let mock = RareSpellingAPIMock()
        mock._2faReturnValue = true
        #expect(mock._2fa())
        #expect(mock._2faCalls.count == 1)
        mock.schedule(await: true, `inout`: 2, copy: "c")
        #expect(mock.scheduleCalls.first?.await == true)
        #expect(mock.scheduleCalls.first?.`inout` == 2)
        #expect(mock.scheduleCalls.first?.copy == "c")

        let shared = SendableRareSpellingAPIMock()
        shared.schedule(await: false, `inout`: 3, copy: "d")
        #expect(shared.scheduleCalls.first?.copy == "d")
    }
}
