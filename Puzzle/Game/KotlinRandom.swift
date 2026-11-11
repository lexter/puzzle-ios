/// Bit-exact port of Kotlin's `kotlin.random.Random(seed: Long)` (XorWow).
///
/// Both players build the race board from the host's seed, so iOS and Android must draw the
/// very same numbers. Only the operations the puzzle uses are ported.
struct KotlinRandom {
    private var x: UInt32
    private var y: UInt32
    private var z: UInt32
    private var w: UInt32
    private var v: UInt32
    private var addend: UInt32

    init(seed: Int64) {
        self.init(seed1: UInt32(truncatingIfNeeded: seed), seed2: UInt32(truncatingIfNeeded: seed >> 32))
    }

    init(seed: Int) { self.init(seed: Int64(seed)) }

    private init(seed1: UInt32, seed2: UInt32) {
        x = seed1
        y = seed2
        z = 0
        w = 0
        v = ~seed1
        addend = (seed1 << 10) ^ (seed2 >> 4)
        // Some trivial seeds give several values with zeroes in the upper bits, so the first 64 are discarded.
        for _ in 0..<64 { _ = nextInt() }
    }

    mutating func nextInt() -> Int32 {
        var t = x
        t = t ^ (t >> 2)
        x = y
        y = z
        z = w
        let v0 = v
        w = v0
        t = (t ^ (t << 1)) ^ v0 ^ (v0 << 4)
        v = t
        addend = addend &+ 362_437
        return Int32(bitPattern: t &+ addend)
    }

    /// `Random.nextInt(until)`: uniform in `0..<until`.
    mutating func nextInt(until n: Int) -> Int {
        precondition(n > 0, "bound must be positive")
        let bound = Int32(n)
        if bound & -bound == bound {
            return Int(nextBits(31 - bound.leadingZeroBitCount))
        }
        var bits: Int32
        var value: Int32
        repeat {
            bits = Int32(bitPattern: UInt32(bitPattern: nextInt()) >> 1)
            value = bits % bound
        } while bits &- value &+ (bound - 1) < 0
        return Int(value)
    }

    mutating func nextFloat() -> Float {
        Float(nextBits(24)) / Float(1 << 24)
    }

    private mutating func nextBits(_ bitCount: Int) -> Int32 {
        let raw = UInt32(bitPattern: nextInt())
        guard bitCount > 0 else { return 0 }
        return Int32(bitPattern: raw >> UInt32(32 - bitCount))
    }
}

extension Array {
    /// Kotlin's `MutableList.shuffle(random)`: Fisher–Yates from the end.
    mutating func kotlinShuffle(using random: inout KotlinRandom) {
        guard count > 1 else { return }
        for i in stride(from: count - 1, through: 1, by: -1) {
            swapAt(i, random.nextInt(until: i + 1))
        }
    }
}
