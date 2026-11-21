enum Networking {
    enum Error: Swift.Error { case offline 
}
    protocol Client {
        func send() throws -> Int
        func ping() throws
    }

    /// Auto-generated mock for `Client` (RFC 0001 stage 2).
    final class ClientMock: Client {
        init() {
        }

        private var __innodiMockGeneration: UInt64 = 0

        struct _InnoDIMockNotStubbed: _InnoDIMockError, CustomStringConvertible {
            let selector: String
            var description: String {
                "InnoDI mock selector '\(selector)' was not stubbed before invocation."
            }
        }

        struct SendCall {
            let generation: UInt64
        }
        private(set) var sendCalls: [SendCall] = []
        private var __innodi_sendIsStubbed = false
        private var __innodi_sendResultStorage: Result<Int, _InnoDIMockError> = .failure(_InnoDIMockNotStubbed(selector: "sendResult"))
        var sendResult: Result<Int, _InnoDIMockError> {
            get {
                __innodi_sendResultStorage
            }
            set {
                __innodi_sendResultStorage = newValue
                __innodi_sendIsStubbed = true
            }
        }
        func send() throws -> Int {
            sendCalls.append(.init(generation: __innodiMockGeneration))
            return try sendResult.get()
        }

        struct PingCall {
            let generation: UInt64
        }
        private(set) var pingCalls: [PingCall] = []
        private var __innodi_pingIsStubbed = false
        private var __innodi_pingThrownErrorStorage: _InnoDIMockError?
        var pingThrownError: _InnoDIMockError? {
            get {
                __innodi_pingThrownErrorStorage
            }
            set {
                __innodi_pingThrownErrorStorage = newValue
                __innodi_pingIsStubbed = true
            }
        }
        func ping() throws {
            pingCalls.append(.init(generation: __innodiMockGeneration))
            if let error = pingThrownError {
                throw error
            }
        }

        var missingStubSelectors: [String] {
            [
                !__innodi_sendIsStubbed ? "send" : nil,
                !__innodi_pingIsStubbed ? "ping" : nil
            ].compactMap {
                $0
            }
        }

        var recordedCallCounts: [String: Int] {
            [
                "send": sendCalls.count,
                "ping": pingCalls.count
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
                    "send": sendCalls.count,
                    "ping": pingCalls.count
                ]
            )
        }

        @discardableResult
        func innoDIReset(_ scope: InnoDIResetScope) -> InnoDICallHistorySnapshot {
            let snapshot = innoDICallHistorySnapshot
            sendCalls.removeAll(keepingCapacity: false)
            pingCalls.removeAll(keepingCapacity: false)
            if scope == .all {
                __innodi_sendResultStorage = .failure(_InnoDIMockNotStubbed(selector: "sendResult"))
                __innodi_sendIsStubbed = false
                __innodi_pingThrownErrorStorage = nil
                __innodi_pingIsStubbed = false
            }
            __innodiMockGeneration &+= 1
            return snapshot
        }
    }
    protocol SharedClient: Sendable {
        func send() throws -> Int
        func ping() throws
    }

    /// Auto-generated mock for `SharedClient` (RFC 0001 stage 2).
    final class SharedClientMock: SharedClient {
        init() {
        }

        private let __innodiMockState = InnoDITesting.DIConcurrentMockState()

        struct _InnoDIMockNotStubbed: _InnoDIMockError, CustomStringConvertible {
            let selector: String
            var description: String {
                "InnoDI mock selector '\(selector)' was not stubbed before invocation."
            }
        }

        struct SendCall: Sendable {
            let generation: UInt64
        }
        private let __innodi_sendCallsBox = InnoDITesting.DIConcurrentValueBox<[SendCall]>([])
        var sendCalls: [SendCall] {
            __innodiMockState.withCriticalRegion { _ in
                __innodi_sendCallsBox.snapshot()
            }
        }
        private let __innodi_sendResultBox = InnoDITesting.DIConcurrentValueBox<Result<Int, _InnoDIMockError>>(.failure(_InnoDIMockNotStubbed(selector: "sendResult")))
        private let __innodi_sendStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
        var sendResult: Result<Int, _InnoDIMockError> {
            get {
                __innodiMockState.withCriticalRegion { _ in
                    __innodi_sendResultBox.snapshot()
                }
            }
            set {
                __innodiMockState.withCriticalRegion { _ in
                    __innodi_sendResultBox.replace(with: newValue)
                    __innodi_sendStubbedBox.replace(with: true)
                }
            }
        }
        func send() throws -> Int {
            let result = __innodiMockState.withCriticalRegion { generation in
                __innodi_sendCallsBox.update {
                    $0.append(.init(generation: generation))
                }
                return __innodi_sendResultBox.snapshot()
            }
            return try result.get()
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
        private let __innodi_pingThrownErrorBox = InnoDITesting.DIConcurrentValueBox<_InnoDIMockError?>(nil)
        private let __innodi_pingStubbedBox = InnoDITesting.DIConcurrentValueBox(false)
        var pingThrownError: _InnoDIMockError? {
            get {
                __innodiMockState.withCriticalRegion { _ in
                    __innodi_pingThrownErrorBox.snapshot()
                }
            }
            set {
                __innodiMockState.withCriticalRegion { _ in
                    __innodi_pingThrownErrorBox.replace(with: newValue)
                    __innodi_pingStubbedBox.replace(with: true)
                }
            }
        }
        func ping() throws {
            let error = __innodiMockState.withCriticalRegion { generation in
                __innodi_pingCallsBox.update {
                    $0.append(.init(generation: generation))
                }
                return __innodi_pingThrownErrorBox.snapshot()
            }
            if let error {
                throw error
            }
        }

        var missingStubSelectors: [String] {
            __innodiMockState.withCriticalRegion { _ in
                [
                    !__innodi_sendStubbedBox.snapshot() ? "send" : nil,
                    !__innodi_pingStubbedBox.snapshot() ? "ping" : nil
                ].compactMap {
                    $0
                }
            }
        }

        var recordedCallCounts: [String: Int] {
            __innodiMockState.withCriticalRegion { _ in
                [
                    "send": __innodi_sendCallsBox.snapshot().count,
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
                    "send": __innodi_sendCallsBox.snapshot().count,
                    "ping": __innodi_pingCallsBox.snapshot().count
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
                    "send": __innodi_sendCallsBox.snapshot().count,
                    "ping": __innodi_pingCallsBox.snapshot().count
                    ]
                )
                __innodi_sendCallsBox.replace(with: [])
                __innodi_pingCallsBox.replace(with: [])
                if scope == .all {
                    __innodi_sendResultBox.replace(with: .failure(_InnoDIMockNotStubbed(selector: "sendResult")))
                    __innodi_sendStubbedBox.replace(with: false)
                    __innodi_pingThrownErrorBox.replace(with: nil)
                    __innodi_pingStubbedBox.replace(with: false)
                }
                return snapshot
            }
        }
    }
}