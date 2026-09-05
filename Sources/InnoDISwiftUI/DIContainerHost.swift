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
    private var factory: Factory?
    private var closeOperation: Close?

    public init() {}

    /// Starts the identity if it is not already loading or ready.
    ///
    /// Repeating this call during SwiftUI redraw is a no-op. A different
    /// identity first closes the old generation and then creates the new one.
    public func start(
        identity newIdentity: Identity,
        factory newFactory: @escaping Factory,
        close newClose: @escaping Close = { _ in }
    ) {
        factory = newFactory
        closeOperation = newClose

        if identity == newIdentity {
            switch phase {
            case .loading, .ready:
                return
            case .idle, .failed:
                break
            }
        }

        begin(identity: newIdentity)
    }

    /// Retries the failed identity in a new generation.
    ///
    /// Calling this method outside the failed phase is a no-op.
    public func retry() {
        guard case let .failed(failedIdentity, _) = phase else { return }
        begin(identity: failedIdentity)
    }

    /// Cancels an in-flight generation, closes a ready container, and returns
    /// to ``DIContainerHostPhase/idle``. Repeated closes are idempotent.
    public func close() async {
        generation &+= 1
        operation?.cancel()
        operation = nil
        identity = nil

        let container = currentContainer
        currentContainer = nil
        phase = .idle

        if let container, let closeOperation {
            await closeOperation(container)
        }
    }

    private func begin(identity newIdentity: Identity) {
        generation &+= 1
        let requestedGeneration = generation
        operation?.cancel()

        let oldContainer = currentContainer
        let oldClose = closeOperation
        currentContainer = nil
        identity = newIdentity
        phase = .loading(identity: newIdentity)

        precondition(factory != nil && closeOperation != nil)
        let factory = factory.unsafelyUnwrapped
        let close = closeOperation.unsafelyUnwrapped

        operation = Task { @MainActor [weak self] in
            if let oldContainer, let oldClose {
                await oldClose(oldContainer)
            }

            guard let self, requestedGeneration == generation else { return }

            do {
                let candidate = try await factory(newIdentity)
                guard !Task.isCancelled, requestedGeneration == generation else {
                    await close(candidate)
                    return
                }

                currentContainer = candidate
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
