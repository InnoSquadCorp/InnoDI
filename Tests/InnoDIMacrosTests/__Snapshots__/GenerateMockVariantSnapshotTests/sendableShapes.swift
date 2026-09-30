enum SharedFailure: Error { case unavailable 
}
protocol SharedAPI: Sendable {
    var title: String { get set }
    func load() throws(SharedFailure) -> String
    func refresh(id: Int) async throws
    func ping()
}

/// Auto-generated mock for `SharedAPI` (RFC 0001 stage 2).
final class SharedAPIMock: SharedAPI {
    init() {
    }

    private let __innodiMockState = InnoDITesting.DIConcurrentMockState()

    private let __innodi_title_hda31296c0c1b6029StubValueBox = InnoDITesting.DIConcurrentValueBox<String?>(nil)
    private let __innodi_title_hda31296c0c1b6029IsStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var title: String {
        get {
            return __innodiMockState.withCriticalRegion { _ in
                guard __innodi_title_hda31296c0c1b6029IsStubbedBox.snapshot() else {
                    preconditionFailure("title was not set on \(Self.self) before it was read")
                }
                guard let value = __innodi_title_hda31296c0c1b6029StubValueBox.snapshot() else {
                    preconditionFailure("Stub storage for String was unexpectedly empty")
                }
                return value
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_title_hda31296c0c1b6029StubValueBox.replace(with: newValue)
                __innodi_title_hda31296c0c1b6029IsStubbedBox.replace(with: true)
            }
        }
    }

    struct LoadCall: Sendable {
        let generation: UInt64
    }
    private let __innodi_loadCallsBox = InnoDITesting.DIConcurrentValueBox<[LoadCall]>([])
    var loadCalls: [LoadCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_loadCallsBox.snapshot()
        }
    }
    private let __innodi_loadResultBox = InnoDITesting.DIConcurrentValueBox<Result<String, SharedFailure>?>(nil)
    private let __innodi_loadStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var loadResult: Result<String, SharedFailure>? {
        get {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_loadResultBox.snapshot()
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_loadResultBox.replace(with: newValue)
                __innodi_loadStubbedBox.replace(with: newValue != nil)
            }
        }
    }
    func load() throws(SharedFailure) -> String {
        let result = __innodiMockState.withCriticalRegion { generation in
            __innodi_loadCallsBox.update {
                $0.append(.init(generation: generation))
            }
            return __innodi_loadResultBox.snapshot()
        }
        guard let result else {
            preconditionFailure("loadResult was not set on \(Self.self) before load was invoked")
        }
        return try result.get()
    }

    struct RefreshCall: Sendable {
        let generation: UInt64
        let id: Int
    }
    private let __innodi_refreshCallsBox = InnoDITesting.DIConcurrentValueBox<[RefreshCall]>([])
    var refreshCalls: [RefreshCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_refreshCallsBox.snapshot()
        }
    }
    private let __innodi_refreshThrownErrorBox = InnoDITesting.DIConcurrentValueBox<Error?>(nil)
    private let __innodi_refreshStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
    var refreshThrownError: Error? {
        get {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_refreshThrownErrorBox.snapshot()
            }
        }
        set {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_refreshThrownErrorBox.replace(with: newValue)
                __innodi_refreshStubbedBox.replace(with: true)
            }
        }
    }
    func refresh(id: Int) async throws {
        let error = __innodiMockState.withCriticalRegion { generation in
            __innodi_refreshCallsBox.update {
                $0.append(.init(generation: generation, id: id))
            }
            return __innodi_refreshThrownErrorBox.snapshot()
        }
        if let error {
            throw error
        }
    }

    struct PingCall: Sendable {
        let generation: UInt64
    }
    private let __innodi_pingCallsBox = InnoDITesting.DIConcurrentValueBox<[PingCall]>([])
    var pingCalls: [PingCall] {
        __innodiMockState.withCriticalRegion { _ in
            __innodi_pingCallsBox.snapshot()
        }
    }
    func ping() {
        __innodiMockState.withCriticalRegion { generation in
            __innodi_pingCallsBox.update {
                $0.append(.init(generation: generation))
            }
        }
    }

    var missingStubSelectors: [String] {
        __innodiMockState.withCriticalRegion { _ in
            [
                !__innodi_title_hda31296c0c1b6029IsStubbedBox.snapshot() ? "title" : nil,
                !__innodi_loadStubbedBox.snapshot() ? "load" : nil,
                !__innodi_refreshStubbedBox.snapshot() ? "refresh" : nil
            ].compactMap {
                $0
            }
        }
    }

    var recordedCallCounts: [String: Int] {
        __innodiMockState.withCriticalRegion { _ in
            [
                "load": __innodi_loadCallsBox.snapshot().count,
                "refresh": __innodi_refreshCallsBox.snapshot().count,
                "ping": __innodi_pingCallsBox.snapshot().count
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
                "load": __innodi_loadCallsBox.snapshot().count,
                "refresh": __innodi_refreshCallsBox.snapshot().count,
                "ping": __innodi_pingCallsBox.snapshot().count
                ]
            )
        }
    }

    @discardableResult
    func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
        __innodiMockState.reset { generation in
            let snapshot = InnoDICallHistorySnapshot(
                generation: generation,
                recordedCallCounts: [
                "load": __innodi_loadCallsBox.snapshot().count,
                "refresh": __innodi_refreshCallsBox.snapshot().count,
                "ping": __innodi_pingCallsBox.snapshot().count
                ]
            )
            __innodi_loadCallsBox.replace(with: [])
            __innodi_refreshCallsBox.replace(with: [])
            __innodi_pingCallsBox.replace(with: [])
            if scope == .all {
                __innodi_title_hda31296c0c1b6029StubValueBox.replace(with: nil)
                __innodi_title_hda31296c0c1b6029IsStubbedBox.replace(with: false)
                __innodi_loadResultBox.replace(with: nil)
                __innodi_loadStubbedBox.replace(with: false)
                __innodi_refreshThrownErrorBox.replace(with: nil)
                __innodi_refreshStubbedBox.replace(with: false)
            }
            return snapshot
        }
    }
}