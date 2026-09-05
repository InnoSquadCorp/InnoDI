/// An explicitly ordered collection contract that can be exported by one
/// module and composed by another without runtime registration or discovery.
public struct DICollectionGroup<Element>: RandomAccessCollection {
    public typealias Index = Int

    private let elements: [Element]

    /// Passing `[]` is an explicit empty contribution.
    public init(_ elements: [Element]) { self.elements = elements }

    public static var empty: Self { Self([]) }
    public var startIndex: Int { elements.startIndex }
    public var endIndex: Int { elements.endIndex }
    public subscript(position: Int) -> Element { elements[position] }

    /// Combines explicitly named module outputs from left to right.
    public static func compose(_ groups: [Self]) -> Self {
        Self(groups.flatMap(\.elements))
    }
}

extension DICollectionGroup: Sendable where Element: Sendable {}

public struct DIKeyedCollectionDuplicateError<Key>: Error, Equatable, Sendable
where Key: Hashable & Sendable {
    public let key: Key
    public init(key: Key) { self.key = key }
}

/// A deterministic keyed collection with source-order iteration and O(1)
/// lookup. Unlike `Dictionary`, iteration order is part of this contract.
public struct DIKeyedCollection<Key, Element>: RandomAccessCollection
where Key: Hashable & Sendable {
    public struct Entry {
        public let key: Key
        public let value: Element

        public init(key: Key, value: Element) {
            self.key = key
            self.value = value
        }
    }

    public typealias Index = Int
    private let entries: [Entry]
    private let indicesByKey: [Key: Int]

    public init(_ entries: [Entry]) throws {
        var indicesByKey: [Key: Int] = [:]
        for (index, entry) in entries.enumerated() {
            guard indicesByKey.updateValue(index, forKey: entry.key) == nil else {
                throw DIKeyedCollectionDuplicateError(key: entry.key)
            }
        }
        self.entries = entries
        self.indicesByKey = indicesByKey
    }

    public static var empty: Self {
        Self(validatedEntries: [], indicesByKey: [:])
    }
    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }
    public subscript(position: Int) -> Entry { entries[position] }

    public subscript(key key: Key) -> Element? {
        guard let index = indicesByKey[key] else { return nil }
        return entries[index].value
    }

    public static func compose(_ groups: [Self]) throws -> Self {
        try Self(groups.flatMap(\.entries))
    }

    private init(validatedEntries: [Entry], indicesByKey: [Key: Int]) {
        entries = validatedEntries
        self.indicesByKey = indicesByKey
    }
}

extension DIKeyedCollection.Entry: Sendable where Element: Sendable {}
extension DIKeyedCollection: Sendable where Element: Sendable {}

/// An ordered collection of provider closures. Reading one index resolves
/// only that provider, leaving every unselected on-demand dependency untouched.
public struct DIProviderCollection<Element>: RandomAccessCollection {
    public typealias Index = Int
    public typealias Provider = () -> Element
    private let providers: [Provider]

    public init(_ providers: [Provider]) { self.providers = providers }
    public static var empty: Self { Self([]) }
    public var startIndex: Int { providers.startIndex }
    public var endIndex: Int { providers.endIndex }
    public subscript(position: Int) -> Element { providers[position]() }

    public static func compose(_ groups: [Self]) -> Self {
        Self(groups.flatMap(\.providers))
    }
}

/// A deterministic keyed provider collection that resolves values on selection.
public struct DIKeyedProviderCollection<Key, Element>: RandomAccessCollection
where Key: Hashable & Sendable {
    public struct Entry {
        public let key: Key
        private let provider: () -> Element

        public init(key: Key, provider: @escaping () -> Element) {
            self.key = key
            self.provider = provider
        }

        public func callAsFunction() -> Element { provider() }
    }

    public typealias Index = Int
    private let entries: [Entry]
    private let indicesByKey: [Key: Int]

    public init(_ entries: [Entry]) throws {
        var indicesByKey: [Key: Int] = [:]
        for (index, entry) in entries.enumerated() {
            guard indicesByKey.updateValue(index, forKey: entry.key) == nil else {
                throw DIKeyedCollectionDuplicateError(key: entry.key)
            }
        }
        self.entries = entries
        self.indicesByKey = indicesByKey
    }

    public static var empty: Self {
        Self(validatedEntries: [], indicesByKey: [:])
    }
    public var startIndex: Int { entries.startIndex }
    public var endIndex: Int { entries.endIndex }
    public subscript(position: Int) -> Entry { entries[position] }

    public subscript(key key: Key) -> Element? {
        guard let index = indicesByKey[key] else { return nil }
        return entries[index]()
    }

    public static func compose(_ groups: [Self]) throws -> Self {
        try Self(groups.flatMap(\.entries))
    }

    private init(validatedEntries: [Entry], indicesByKey: [Key: Int]) {
        entries = validatedEntries
        self.indicesByKey = indicesByKey
    }
}
