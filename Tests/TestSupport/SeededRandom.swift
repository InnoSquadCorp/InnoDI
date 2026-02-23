public struct SeededRandom {
    private var state: UInt64

    public init(seed: UInt64) {
        self.state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    public mutating func nextUInt64() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    public mutating func nextBool() -> Bool {
        (nextUInt64() & 1) == 1
    }

    public mutating func nextInt(upperBound: Int) -> Int {
        guard upperBound > 0 else { return 0 }
        return Int(nextUInt64() % UInt64(upperBound))
    }

    public mutating func shuffled<T>(_ source: [T]) -> [T] {
        var values = source
        guard values.count > 1 else { return values }
        for index in stride(from: values.count - 1, through: 1, by: -1) {
            let randomIndex = nextInt(upperBound: index + 1)
            if randomIndex != index {
                values.swapAt(index, randomIndex)
            }
        }
        return values
    }
}
