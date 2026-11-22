
protocol Spellings {
    func loader() -> () -> Int?
    var parse: (String) -> Int? { get set }
    func plain() -> () -> Int
    func optionalLoader() -> (() -> Int)?
    var name: String! { get set }
    func find() -> String!
    func lookup() throws -> String!
    func accept(_ value: String!)
    func sugar() -> Int?
    func named() -> Optional<Int>
    func qualified() -> Swift.Optional<Int>
    func parenthesized() -> (Int?)
    func aliased() -> MaybeInt
    var optionalName: Optional<String> { get set }
}

/// Auto-generated mock for `Spellings` (RFC 0001 stage 2).
final class SpellingsMock: Spellings {
    init() {
    }

    private var __innodiMockGeneration: UInt64 = 0

    struct _InnoDIMockNotStubbed: _InnoDIMockError, CustomStringConvertible {
        let selector: String
        var description: String {
            "InnoDI mock selector '\(selector)' was not stubbed before invocation."
        }
    }

    struct LoaderCall {
        let generation: UInt64
    }
    private(set) var loaderCalls: [LoaderCall] = []
    private var __innodi_loaderIsStubbed = false
    private var __innodi_loaderReturnValueStorage: (() -> Int?)?
    var loaderReturnValue: (() -> Int?)? {
        get {
            __innodi_loaderReturnValueStorage
        }
        set {
            __innodi_loaderReturnValueStorage = newValue
            __innodi_loaderIsStubbed = newValue != nil
        }
    }
    func loader() -> () -> Int? {
        loaderCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_loaderIsStubbed else {
            preconditionFailure("loaderReturnValue was not set on \(Self.self) before loader was invoked")
        }
        guard let value = loaderReturnValue else {
            preconditionFailure("Stub storage for () -> Int? was unexpectedly empty")
        }
        return value
    }

    private var __innodi_parse_h0c4e87a7a1f6fd8cStubValue: ((String) -> Int?)?
    private var __innodi_parse_h0c4e87a7a1f6fd8cIsStubbed = false
    var parse: (String) -> Int? {
        get {
            guard __innodi_parse_h0c4e87a7a1f6fd8cIsStubbed else {
                preconditionFailure("parse was not set on \(Self.self) before it was read")
            }
            guard let value = __innodi_parse_h0c4e87a7a1f6fd8cStubValue else {
                preconditionFailure("Stub storage for (String) -> Int? was unexpectedly empty")
            }
            return value
        }
        set {
            __innodi_parse_h0c4e87a7a1f6fd8cStubValue = newValue
            __innodi_parse_h0c4e87a7a1f6fd8cIsStubbed = true
        }
    }

    struct PlainCall {
        let generation: UInt64
    }
    private(set) var plainCalls: [PlainCall] = []
    private var __innodi_plainIsStubbed = false
    private var __innodi_plainReturnValueStorage: (() -> Int)?
    var plainReturnValue: (() -> Int)? {
        get {
            __innodi_plainReturnValueStorage
        }
        set {
            __innodi_plainReturnValueStorage = newValue
            __innodi_plainIsStubbed = newValue != nil
        }
    }
    func plain() -> () -> Int {
        plainCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_plainIsStubbed else {
            preconditionFailure("plainReturnValue was not set on \(Self.self) before plain was invoked")
        }
        guard let value = plainReturnValue else {
            preconditionFailure("Stub storage for () -> Int was unexpectedly empty")
        }
        return value
    }

    struct OptionalLoaderCall {
        let generation: UInt64
    }
    private(set) var optionalLoaderCalls: [OptionalLoaderCall] = []
    private var __innodi_optionalLoaderIsStubbed = false
    private var __innodi_optionalLoaderReturnValueStorage: ((() -> Int)?)?
    var optionalLoaderReturnValue: ((() -> Int)?)? {
        get {
            __innodi_optionalLoaderReturnValueStorage
        }
        set {
            __innodi_optionalLoaderReturnValueStorage = newValue
            __innodi_optionalLoaderIsStubbed = true
        }
    }
    func optionalLoader() -> (() -> Int)? {
        optionalLoaderCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_optionalLoaderIsStubbed else {
            preconditionFailure("optionalLoaderReturnValue was not set on \(Self.self) before optionalLoader was invoked")
        }
        return optionalLoaderReturnValue ?? nil
    }

    private var __innodi_name_hc4bcadba8e631b86StubValue: (String?)?
    private var __innodi_name_hc4bcadba8e631b86IsStubbed = false
    var name: String! {
        get {
            guard __innodi_name_hc4bcadba8e631b86IsStubbed else {
                preconditionFailure("name was not set on \(Self.self) before it was read")
            }
            return __innodi_name_hc4bcadba8e631b86StubValue ?? nil
        }
        set {
            __innodi_name_hc4bcadba8e631b86StubValue = newValue
            __innodi_name_hc4bcadba8e631b86IsStubbed = true
        }
    }

    struct FindCall {
        let generation: UInt64
    }
    private(set) var findCalls: [FindCall] = []
    private var __innodi_findIsStubbed = false
    private var __innodi_findReturnValueStorage: (String?)?
    var findReturnValue: (String?)? {
        get {
            __innodi_findReturnValueStorage
        }
        set {
            __innodi_findReturnValueStorage = newValue
            __innodi_findIsStubbed = true
        }
    }
    func find() -> String! {
        findCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_findIsStubbed else {
            preconditionFailure("findReturnValue was not set on \(Self.self) before find was invoked")
        }
        return findReturnValue ?? nil
    }

    struct LookupCall {
        let generation: UInt64
    }
    private(set) var lookupCalls: [LookupCall] = []
    private var __innodi_lookupIsStubbed = false
    private var __innodi_lookupResultStorage: Result<String?, _InnoDIMockError> = .failure(_InnoDIMockNotStubbed(selector: "lookupResult"))
    var lookupResult: Result<String?, _InnoDIMockError> {
        get {
            __innodi_lookupResultStorage
        }
        set {
            __innodi_lookupResultStorage = newValue
            __innodi_lookupIsStubbed = true
        }
    }
    func lookup() throws -> String! {
        lookupCalls.append(.init(generation: __innodiMockGeneration))
        return try lookupResult.get()
    }

    struct AcceptCall {
        let generation: UInt64
        let value: String!
    }
    private(set) var acceptCalls: [AcceptCall] = []
    func accept(_ value: String!) {
        acceptCalls.append(.init(generation: __innodiMockGeneration, value: value))
    }

    struct SugarCall {
        let generation: UInt64
    }
    private(set) var sugarCalls: [SugarCall] = []
    private var __innodi_sugarIsStubbed = false
    private var __innodi_sugarReturnValueStorage: (Int?)?
    var sugarReturnValue: (Int?)? {
        get {
            __innodi_sugarReturnValueStorage
        }
        set {
            __innodi_sugarReturnValueStorage = newValue
            __innodi_sugarIsStubbed = true
        }
    }
    func sugar() -> Int? {
        sugarCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_sugarIsStubbed else {
            preconditionFailure("sugarReturnValue was not set on \(Self.self) before sugar was invoked")
        }
        return sugarReturnValue ?? nil
    }

    struct NamedCall {
        let generation: UInt64
    }
    private(set) var namedCalls: [NamedCall] = []
    private var __innodi_namedIsStubbed = false
    private var __innodi_namedReturnValueStorage: Optional<Int>?
    var namedReturnValue: Optional<Int>? {
        get {
            __innodi_namedReturnValueStorage
        }
        set {
            __innodi_namedReturnValueStorage = newValue
            __innodi_namedIsStubbed = true
        }
    }
    func named() -> Optional<Int> {
        namedCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_namedIsStubbed else {
            preconditionFailure("namedReturnValue was not set on \(Self.self) before named was invoked")
        }
        return namedReturnValue ?? nil
    }

    struct QualifiedCall {
        let generation: UInt64
    }
    private(set) var qualifiedCalls: [QualifiedCall] = []
    private var __innodi_qualifiedIsStubbed = false
    private var __innodi_qualifiedReturnValueStorage: Swift.Optional<Int>?
    var qualifiedReturnValue: Swift.Optional<Int>? {
        get {
            __innodi_qualifiedReturnValueStorage
        }
        set {
            __innodi_qualifiedReturnValueStorage = newValue
            __innodi_qualifiedIsStubbed = true
        }
    }
    func qualified() -> Swift.Optional<Int> {
        qualifiedCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_qualifiedIsStubbed else {
            preconditionFailure("qualifiedReturnValue was not set on \(Self.self) before qualified was invoked")
        }
        return qualifiedReturnValue ?? nil
    }

    struct ParenthesizedCall {
        let generation: UInt64
    }
    private(set) var parenthesizedCalls: [ParenthesizedCall] = []
    private var __innodi_parenthesizedIsStubbed = false
    private var __innodi_parenthesizedReturnValueStorage: (Int?)?
    var parenthesizedReturnValue: (Int?)? {
        get {
            __innodi_parenthesizedReturnValueStorage
        }
        set {
            __innodi_parenthesizedReturnValueStorage = newValue
            __innodi_parenthesizedIsStubbed = true
        }
    }
    func parenthesized() -> (Int?) {
        parenthesizedCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_parenthesizedIsStubbed else {
            preconditionFailure("parenthesizedReturnValue was not set on \(Self.self) before parenthesized was invoked")
        }
        return parenthesizedReturnValue ?? nil
    }

    struct AliasedCall {
        let generation: UInt64
    }
    private(set) var aliasedCalls: [AliasedCall] = []
    private var __innodi_aliasedIsStubbed = false
    private var __innodi_aliasedReturnValueStorage: MaybeInt?
    var aliasedReturnValue: MaybeInt? {
        get {
            __innodi_aliasedReturnValueStorage
        }
        set {
            __innodi_aliasedReturnValueStorage = newValue
            __innodi_aliasedIsStubbed = newValue != nil
        }
    }
    func aliased() -> MaybeInt {
        aliasedCalls.append(.init(generation: __innodiMockGeneration))
        guard __innodi_aliasedIsStubbed else {
            preconditionFailure("aliasedReturnValue was not set on \(Self.self) before aliased was invoked")
        }
        guard let value = aliasedReturnValue else {
            preconditionFailure("Stub storage for MaybeInt was unexpectedly empty")
        }
        return value
    }

    private var __innodi_optionalName_he0c73da7730900f2StubValue: Optional<String>?
    private var __innodi_optionalName_he0c73da7730900f2IsStubbed = false
    var optionalName: Optional<String> {
        get {
            guard __innodi_optionalName_he0c73da7730900f2IsStubbed else {
                preconditionFailure("optionalName was not set on \(Self.self) before it was read")
            }
            guard let value = __innodi_optionalName_he0c73da7730900f2StubValue else {
                preconditionFailure("Stub storage for Optional<String> was unexpectedly empty")
            }
            return value
        }
        set {
            __innodi_optionalName_he0c73da7730900f2StubValue = newValue
            __innodi_optionalName_he0c73da7730900f2IsStubbed = true
        }
    }

    var missingStubSelectors: [String] {
        [
            !__innodi_loaderIsStubbed ? "loader" : nil,
            !__innodi_parse_h0c4e87a7a1f6fd8cIsStubbed ? "parse" : nil,
            !__innodi_plainIsStubbed ? "plain" : nil,
            !__innodi_optionalLoaderIsStubbed ? "optionalLoader" : nil,
            !__innodi_name_hc4bcadba8e631b86IsStubbed ? "name" : nil,
            !__innodi_findIsStubbed ? "find" : nil,
            !__innodi_lookupIsStubbed ? "lookup" : nil,
            !__innodi_sugarIsStubbed ? "sugar" : nil,
            !__innodi_namedIsStubbed ? "named" : nil,
            !__innodi_qualifiedIsStubbed ? "qualified" : nil,
            !__innodi_parenthesizedIsStubbed ? "parenthesized" : nil,
            !__innodi_aliasedIsStubbed ? "aliased" : nil,
            !__innodi_optionalName_he0c73da7730900f2IsStubbed ? "optionalName" : nil
        ].compactMap {
            $0
        }
    }

    var recordedCallCounts: [String: Int] {
        [
            "loader": loaderCalls.count,
            "plain": plainCalls.count,
            "optionalLoader": optionalLoaderCalls.count,
            "find": findCalls.count,
            "lookup": lookupCalls.count,
            "accept": acceptCalls.count,
            "sugar": sugarCalls.count,
            "named": namedCalls.count,
            "qualified": qualifiedCalls.count,
            "parenthesized": parenthesizedCalls.count,
            "aliased": aliasedCalls.count
        ]
    }

    enum InnoDIResetScope: Sendable {
        case calls
        case all
    }

    struct InnoDICallHistorySnapshot: Equatable, Sendable {
        let generation: UInt64
        let recordedCallCounts: [String: Int]
    }

    var innoDICallHistoryGeneration: UInt64 {
        __innodiMockGeneration
    }

    var innoDICallHistorySnapshot: InnoDICallHistorySnapshot {
        .init(
            generation: __innodiMockGeneration,
            recordedCallCounts: [
                "loader": loaderCalls.count,
                "plain": plainCalls.count,
                "optionalLoader": optionalLoaderCalls.count,
                "find": findCalls.count,
                "lookup": lookupCalls.count,
                "accept": acceptCalls.count,
                "sugar": sugarCalls.count,
                "named": namedCalls.count,
                "qualified": qualifiedCalls.count,
                "parenthesized": parenthesizedCalls.count,
                "aliased": aliasedCalls.count
            ]
        )
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        let snapshot = innoDICallHistorySnapshot
        loaderCalls.removeAll(keepingCapacity: false)
        plainCalls.removeAll(keepingCapacity: false)
        optionalLoaderCalls.removeAll(keepingCapacity: false)
        findCalls.removeAll(keepingCapacity: false)
        lookupCalls.removeAll(keepingCapacity: false)
        acceptCalls.removeAll(keepingCapacity: false)
        sugarCalls.removeAll(keepingCapacity: false)
        namedCalls.removeAll(keepingCapacity: false)
        qualifiedCalls.removeAll(keepingCapacity: false)
        parenthesizedCalls.removeAll(keepingCapacity: false)
        aliasedCalls.removeAll(keepingCapacity: false)
        if scope == .all {
            __innodi_loaderReturnValueStorage = nil
            __innodi_loaderIsStubbed = false
            __innodi_parse_h0c4e87a7a1f6fd8cStubValue = nil
            __innodi_parse_h0c4e87a7a1f6fd8cIsStubbed = false
            __innodi_plainReturnValueStorage = nil
            __innodi_plainIsStubbed = false
            __innodi_optionalLoaderReturnValueStorage = nil
            __innodi_optionalLoaderIsStubbed = false
            __innodi_name_hc4bcadba8e631b86StubValue = nil
            __innodi_name_hc4bcadba8e631b86IsStubbed = false
            __innodi_findReturnValueStorage = nil
            __innodi_findIsStubbed = false
            __innodi_lookupResultStorage = .failure(_InnoDIMockNotStubbed(selector: "lookupResult"))
            __innodi_lookupIsStubbed = false
            __innodi_sugarReturnValueStorage = nil
            __innodi_sugarIsStubbed = false
            __innodi_namedReturnValueStorage = nil
            __innodi_namedIsStubbed = false
            __innodi_qualifiedReturnValueStorage = nil
            __innodi_qualifiedIsStubbed = false
            __innodi_parenthesizedReturnValueStorage = nil
            __innodi_parenthesizedIsStubbed = false
            __innodi_aliasedReturnValueStorage = nil
            __innodi_aliasedIsStubbed = false
            __innodi_optionalName_he0c73da7730900f2StubValue = nil
            __innodi_optionalName_he0c73da7730900f2IsStubbed = false
        }
        __innodiMockGeneration &+= 1
        return snapshot
    }
}
protocol SharedSpellings: Sendable {
    func loader() -> @Sendable () -> Int?
    var parse: @Sendable (String) -> Int? { get set }
    func named() -> Optional<Int>
    func aliased() -> MaybeInt
}

/// Auto-generated mock for `SharedSpellings` (RFC 0001 stage 2).
final class SharedSpellingsMock: SharedSpellings {
    init() {
    }

    private let __innodiMockState = InnoDITesting.DIConcurrentMockState()

    struct LoaderCall: Sendable {
        let generation: UInt64
    }
    private let __innodi_loaderCallsBox = InnoDITesting.DIConcurrentValueBox<[LoaderCall]>([])
    var loaderCalls: [LoaderCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_loaderCallsBox.snapshot()
        }
    }
    private let __innodi_loaderReturnValueBox = InnoDITesting.DIConcurrentValueBox<(@Sendable () -> Int?)?>(nil)
    private let __innodi_loaderStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var loaderReturnValue: (@Sendable () -> Int?)? {
        get {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_loaderReturnValueBox.snapshot()
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_loaderReturnValueBox.replace(with: newValue)
                __innodi_loaderStubbedBox.replace(with: newValue != nil)
            }
        }
    }
    func loader() -> @Sendable () -> Int? {
        return __innodiMockState.withCriticalRegion { generation in
            __innodi_loaderCallsBox.update {
                $0.append(.init(generation: generation))
            }
            guard __innodi_loaderStubbedBox.snapshot() else {
                preconditionFailure("loaderReturnValue was not set on \(Self.self) before loader was invoked")
            }
            guard let value = __innodi_loaderReturnValueBox.snapshot() else {
                preconditionFailure("Stub storage for @Sendable () -> Int? was unexpectedly empty")
            }
            return value
        }
    }

    private let __innodi_parse_h0c4e87a7a1f6fd8cStubValueBox = InnoDITesting.DIConcurrentValueBox<(@Sendable (String) -> Int?)?>(nil)
    private let __innodi_parse_h0c4e87a7a1f6fd8cIsStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var parse: @Sendable (String) -> Int? {
        get {
            return __innodiMockState.withCriticalRegion { _ in
                guard __innodi_parse_h0c4e87a7a1f6fd8cIsStubbedBox.snapshot() else {
                    preconditionFailure("parse was not set on \(Self.self) before it was read")
                }
                guard let value = __innodi_parse_h0c4e87a7a1f6fd8cStubValueBox.snapshot() else {
                    preconditionFailure("Stub storage for @Sendable (String) -> Int? was unexpectedly empty")
                }
                return value
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_parse_h0c4e87a7a1f6fd8cStubValueBox.replace(with: newValue)
                __innodi_parse_h0c4e87a7a1f6fd8cIsStubbedBox.replace(with: true)
            }
        }
    }

    struct NamedCall: Sendable {
        let generation: UInt64
    }
    private let __innodi_namedCallsBox = InnoDITesting.DIConcurrentValueBox<[NamedCall]>([])
    var namedCalls: [NamedCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_namedCallsBox.snapshot()
        }
    }
    private let __innodi_namedReturnValueBox = InnoDITesting.DIConcurrentValueBox<Optional<Int>?>(nil)
    private let __innodi_namedStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var namedReturnValue: Optional<Int>? {
        get {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_namedReturnValueBox.snapshot()
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_namedReturnValueBox.replace(with: newValue)
                __innodi_namedStubbedBox.replace(with: true)
            }
        }
    }
    func named() -> Optional<Int> {
        return __innodiMockState.withCriticalRegion { generation in
            __innodi_namedCallsBox.update {
                $0.append(.init(generation: generation))
            }
            guard __innodi_namedStubbedBox.snapshot() else {
                preconditionFailure("namedReturnValue was not set on \(Self.self) before named was invoked")
            }
            return __innodi_namedReturnValueBox.snapshot() ?? nil
        }
    }

    struct AliasedCall: Sendable {
        let generation: UInt64
    }
    private let __innodi_aliasedCallsBox = InnoDITesting.DIConcurrentValueBox<[AliasedCall]>([])
    var aliasedCalls: [AliasedCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_aliasedCallsBox.snapshot()
        }
    }
    private let __innodi_aliasedReturnValueBox = InnoDITesting.DIConcurrentValueBox<MaybeInt?>(nil)
    private let __innodi_aliasedStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var aliasedReturnValue: MaybeInt? {
        get {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_aliasedReturnValueBox.snapshot()
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_aliasedReturnValueBox.replace(with: newValue)
                __innodi_aliasedStubbedBox.replace(with: newValue != nil)
            }
        }
    }
    func aliased() -> MaybeInt {
        return __innodiMockState.withCriticalRegion { generation in
            __innodi_aliasedCallsBox.update {
                $0.append(.init(generation: generation))
            }
            guard __innodi_aliasedStubbedBox.snapshot() else {
                preconditionFailure("aliasedReturnValue was not set on \(Self.self) before aliased was invoked")
            }
            guard let value = __innodi_aliasedReturnValueBox.snapshot() else {
                preconditionFailure("Stub storage for MaybeInt was unexpectedly empty")
            }
            return value
        }
    }

    var missingStubSelectors: [String] {
        __innodiMockState.withCriticalRegion { _ in
            [
                !__innodi_loaderStubbedBox.snapshot() ? "loader" : nil,
                !__innodi_parse_h0c4e87a7a1f6fd8cIsStubbedBox.snapshot() ? "parse" : nil,
                !__innodi_namedStubbedBox.snapshot() ? "named" : nil,
                !__innodi_aliasedStubbedBox.snapshot() ? "aliased" : nil
            ].compactMap {
                $0
            }
        }
    }

    var recordedCallCounts: [String: Int] {
        __innodiMockState.withCriticalRegion { _ in
            [
                "loader": __innodi_loaderCallsBox.snapshot().count,
                "named": __innodi_namedCallsBox.snapshot().count,
                "aliased": __innodi_aliasedCallsBox.snapshot().count
            ]
        }
    }

    enum InnoDIResetScope: Sendable {
        case calls
        case all
    }

    struct InnoDICallHistorySnapshot: Equatable, Sendable {
        let generation: UInt64
        let recordedCallCounts: [String: Int]
    }

    var innoDICallHistoryGeneration: UInt64 {
        __innodiMockState.withCriticalRegion {
            $0
        }
    }

    var innoDICallHistorySnapshot: InnoDICallHistorySnapshot {
        __innodiMockState.withCriticalRegion { generation in
            .init(
                generation: generation,
                recordedCallCounts: [
                "loader": __innodi_loaderCallsBox.snapshot().count,
                "named": __innodi_namedCallsBox.snapshot().count,
                "aliased": __innodi_aliasedCallsBox.snapshot().count
                ]
            )
        }
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        __innodiMockState.reset { generation in
            let snapshot: InnoDICallHistorySnapshot = .init(
                generation: generation,
                recordedCallCounts: [
                "loader": __innodi_loaderCallsBox.snapshot().count,
                "named": __innodi_namedCallsBox.snapshot().count,
                "aliased": __innodi_aliasedCallsBox.snapshot().count
                ]
            )
            __innodi_loaderCallsBox.replace(with: [])
            __innodi_namedCallsBox.replace(with: [])
            __innodi_aliasedCallsBox.replace(with: [])
            if scope == .all {
                __innodi_loaderReturnValueBox.replace(with: nil)
                __innodi_loaderStubbedBox.replace(with: false)
                __innodi_parse_h0c4e87a7a1f6fd8cStubValueBox.replace(with: nil)
                __innodi_parse_h0c4e87a7a1f6fd8cIsStubbedBox.replace(with: false)
                __innodi_namedReturnValueBox.replace(with: nil)
                __innodi_namedStubbedBox.replace(with: false)
                __innodi_aliasedReturnValueBox.replace(with: nil)
                __innodi_aliasedStubbedBox.replace(with: false)
            }
            return snapshot
        }
    }
}