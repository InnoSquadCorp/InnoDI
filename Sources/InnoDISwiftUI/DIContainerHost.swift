import SwiftUI

/// The observable lifecycle state of a ``DIContainerHost``.
///
/// A host starts in ``idle``, enters ``loading(identity:)`` only after SwiftUI
/// mounts it, and owns exactly one ready container for its current identity.
/// The failure payload is intentionally not serialized or reflected by InnoDI.
@MainActor
public enum DIContainerHostPhase<Identity, Container> where Identity: Hashable & Sendable {
    case idle
    case loading(identity: Identity)
    case ready(identity: Identity, container: Container)
    case failed(identity: Identity, error: any Error)
}

/// Explicit lifecycle operations supplied to hosted content and failure UI.
///
/// Call ``close()`` from the route, document, or window owner's actual close
/// path. `DIContainerHost` deliberately does not infer permanent closure from
/// `onDisappear`, because a temporary cover or navigation transition can also
/// make a view disappear.
public struct DIContainerHostHandle: Sendable {
    private let closeOperation: @MainActor @Sendable () async -> Void
    private let retryOperation: @MainActor @Sendable () -> Void

    @MainActor
    init(
        close: @escaping @MainActor @Sendable () async -> Void,
        retry: @escaping @MainActor @Sendable () -> Void
    ) {
        closeOperation = close
        retryOperation = retry
    }

    /// Closes the current container and waits for its configured close hook.
    @MainActor
    public func close() async {
        await closeOperation()
    }

    /// Starts a fresh generation for the current identity after a failure.
    @MainActor
    public func retry() {
        retryOperation()
    }
}

/// Main-actor owner used by ``DIContainerHost``.
///
/// The owner is public so lifecycle-heavy applications can test or coordinate
/// it without reverse-engineering SwiftUI's private view tree. Factories are
/// executed only by ``start(identity:factory:close:)``; constructing the owner
/// itself never constructs a child container.
@MainActor
public final class DIContainerHostOwner<Identity, Container>: ObservableObject
where Identity: Hashable & Sendable {
    public typealias Factory = @MainActor @Sendable (Identity) async throws -> Container
    public typealias Close = @MainActor @Sendable (Container) async -> Void

    @Published public private(set) var phase: DIContainerHostPhase<Identity, Container> = .idle

    private var identity: Identity?
    private var generation: UInt64 = 0
    private var operation: Task<Void, Never>?
    private var currentContainer: Container?
    private var currentContainerClose: Close?
    private var factory: Factory?
    private var closeOperation: Close?
    private var cleanupBarrier: Task<Void, Never>?

    public init() {}

    /// Starts the identity if it is not already loading or ready.
    ///
    /// Repeating this call during SwiftUI redraw is a no-op and does not
    /// replace the active generation's factory or close callback. A different
    /// identity first closes the old generation with the callback captured
    /// when that generation started, then creates the new one. All known
    /// cleanup is serialized; a close hook that does not return deliberately
    /// keeps replacement publication pending.
    public func start(
        identity newIdentity: Identity,
        factory newFactory: @escaping Factory,
        close newClose: @escaping Close = { _ in }
    ) {
        if identity == newIdentity {
            switch phase {
            case .loading, .ready:
                return
            case .idle, .failed:
                break
            }
        }

        begin(
            identity: newIdentity,
            factory: newFactory,
            close: newClose
        )
    }

    /// Retries the failed identity in a new generation.
    ///
    /// Calling this method outside the failed phase is a no-op.
    public func retry() {
        guard case let .failed(failedIdentity, _) = phase,
              let factory,
              let closeOperation else { return }
        begin(
            identity: failedIdentity,
            factory: factory,
            close: closeOperation
        )
    }

    /// Cancels an in-flight generation, closes a ready container, and returns
    /// to ``DIContainerHostPhase/idle``. Repeated closes are idempotent.
    public func close() async {
        generation &+= 1
        operation?.cancel()
        operation = nil
        identity = nil

        let container = currentContainer
        let containerClose = currentContainerClose
        currentContainer = nil
        currentContainerClose = nil
        phase = .idle

        if let container, let containerClose {
            await scheduleCleanup(
                container: container,
                close: containerClose
            ).value
        } else {
            await cleanupBarrier?.value
        }
    }

    private func begin(
        identity newIdentity: Identity,
        factory newFactory: @escaping Factory,
        close newClose: @escaping Close
    ) {
        generation &+= 1
        let requestedGeneration = generation
        operation?.cancel()

        let oldContainer = currentContainer
        let oldClose = currentContainerClose
        currentContainer = nil
        currentContainerClose = nil
        identity = newIdentity
        factory = newFactory
        closeOperation = newClose
        phase = .loading(identity: newIdentity)

        let cleanup: Task<Void, Never>?
        if let oldContainer, let oldClose {
            cleanup = scheduleCleanup(
                container: oldContainer,
                close: oldClose
            )
        } else {
            cleanup = cleanupBarrier
        }

        operation = Task { @MainActor [weak self] in
            await cleanup?.value

            guard let self,
                  !Task.isCancelled,
                  requestedGeneration == generation else { return }

            do {
                let candidate = try await newFactory(newIdentity)
                guard !Task.isCancelled, requestedGeneration == generation else {
                    await scheduleCleanup(
                        container: candidate,
                        close: newClose
                    ).value
                    return
                }

                currentContainer = candidate
                currentContainerClose = newClose
                phase = .ready(identity: newIdentity, container: candidate)
            } catch is CancellationError {
                guard requestedGeneration == generation else { return }
                identity = nil
                phase = .idle
            } catch {
                guard requestedGeneration == generation else { return }
                phase = .failed(identity: newIdentity, error: error)
            }
        }
    }

    /// Serializes all known container cleanup. A close hook that never
    /// returns deliberately keeps replacement publication and explicit close
    /// pending: the host cannot prove the previous generation is closed and
    /// does not bypass that ownership boundary. Cancelling a generation never
    /// cancels its already-started cleanup task.
    private func scheduleCleanup(
        container: Container,
        close: @escaping Close
    ) -> Task<Void, Never> {
        let previous = cleanupBarrier
        let cleanup = Task { @MainActor in
            await previous?.value
            await close(container)
        }
        cleanupBarrier = cleanup
        return cleanup
    }
}

/// A SwiftUI lifecycle boundary for fixed or assisted child containers.
///
/// The container factory is lazy: view initialization and discarded body
/// evaluations do not invoke it. SwiftUI mount starts the owner, repeated
/// redraws reuse the same generation, and a changed `identity` replaces it.
/// Applications retain control over loading, failure, retry, and ready UI.
///
/// ```swift
/// DIContainerHost(
///     identity: route.id,
///     factory: { id in parent.detailFactory(id: id) },
///     close: { container in await container.scope.close() },
///     content: { container, lifecycle in DetailView(container: container) },
///     loading: { ProgressView() },
///     failure: { error, lifecycle in
///         ContentUnavailableView("Could not load", systemImage: "exclamationmark.triangle")
///             .onTapGesture { lifecycle.retry() }
///     }
/// )
/// ```
@MainActor
public struct DIContainerHost<Identity, Container, Content, Loading, Failure>: View
where Identity: Hashable & Sendable, Content: View, Loading: View, Failure: View {
    public typealias Factory = DIContainerHostOwner<Identity, Container>.Factory
    public typealias Close = DIContainerHostOwner<Identity, Container>.Close

    private let identity: Identity
    private let factory: Factory
    private let closeOperation: Close
    private let content: @MainActor (Container, DIContainerHostHandle) -> Content
    private let loading: @MainActor () -> Loading
    private let failure: @MainActor (any Error, DIContainerHostHandle) -> Failure

    @StateObject private var owner = DIContainerHostOwner<Identity, Container>()

    public init(
        identity: Identity,
        factory: @escaping Factory,
        close: @escaping Close = { _ in },
        @ViewBuilder content: @escaping @MainActor (Container, DIContainerHostHandle) -> Content,
        @ViewBuilder loading: @escaping @MainActor () -> Loading,
        @ViewBuilder failure: @escaping @MainActor (any Error, DIContainerHostHandle) -> Failure
    ) {
        self.identity = identity
        self.factory = factory
        closeOperation = close
        self.content = content
        self.loading = loading
        self.failure = failure
    }

    public var body: some View {
        Group {
            switch owner.phase {
            case .idle, .loading:
                loading()
            case let .ready(_, container):
                content(container, handle)
            case let .failed(_, error):
                failure(error, handle)
            }
        }
        .task(id: identity) {
            owner.start(identity: identity, factory: factory, close: closeOperation)
        }
    }

    private var handle: DIContainerHostHandle {
        DIContainerHostHandle(
            close: { [weak owner] in await owner?.close() },
            retry: { [weak owner] in owner?.retry() }
        )
    }
}
