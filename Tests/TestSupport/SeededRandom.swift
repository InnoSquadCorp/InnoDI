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

    /// `options` 중 하나를 균등 확률로 선택해 반환한다.
    public mutating func nextChoice<T>(_ options: [T]) -> T {
        precondition(!options.isEmpty, "nextChoice requires a non-empty options array")
        return options[nextInt(upperBound: options.count)]
    }

    /// 테스트용 공백 조합 하나를 선택한다. 스페이스, 탭, 줄바꿈, 혼합 형태를 포함한다.
    public mutating func nextWhitespace() -> String {
        nextChoice([" ", "  ", "\t", " \t", "\n", "\n    ", " // trailing comment\n", " /* inline */ "])
    }
}
