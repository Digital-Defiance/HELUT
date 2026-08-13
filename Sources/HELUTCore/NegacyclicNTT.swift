import Foundation

// MARK: - Exact negacyclic NTT over Z/2^{32}Z[X]/(X^N+1)
//
// Three 32-bit NTT-friendly primes (2N | p−1 for N≤2^{26}), twisted NTT, CRT.
// Bit-identical to schoolbook `negacyclicPolynomialMultiply` when the exact
// convolution is reduced mod 2^{32}.

package enum NegacyclicNTT {
    /// 15·2^{27}+1, 27·2^{26}+1, 7·2^{26}+1. Product ≈ 2^{90.5} > 2N(2^{32}−1)^2.
    package static let primes: [UInt32] = [2_013_265_921, 1_811_939_329, 469_762_049]
    package static let primeCount = 3

    package struct Modulus: Sendable {
        package var p: UInt32
        package var psi: UInt32
        package var psiInv: UInt32
        package var omega: UInt32
        package var omegaInv: UInt32
        package var nInv: UInt32
        package var logN: Int
        package var n: Int
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var modulusCache: [UInt64: Modulus] = [:]

    package static func modulus(primeIndex: Int, n: Int) -> Modulus {
        precondition(n >= 2 && n.nonzeroBitCount == 1 && n <= 1 << 20)
        precondition((0..<primeCount).contains(primeIndex))
        let key = UInt64(primeIndex) << 32 | UInt64(n)
        lock.lock()
        defer { lock.unlock() }
        if let hit = modulusCache[key] { return hit }
        let p = primes[primeIndex]
        let twoN = 2 * n
        precondition((p - 1) % UInt32(twoN) == 0, "2N must divide p−1")
        let g = generator(p: p)
        let psi = modPow(g, (p - 1) / UInt32(twoN), p)
        precondition(modPow(psi, UInt32(n), p) == p &- 1, "ψ^N ≠ −1")
        let psiInv = modInv(psi, p)
        let omega = modMul(psi, psi, p)
        let omegaInv = modInv(omega, p)
        let nInv = modInv(UInt32(n), p)
        let m = Modulus(
            p: p, psi: psi, psiInv: psiInv,
            omega: omega, omegaInv: omegaInv,
            nInv: nInv, logN: n.trailingZeroBitCount, n: n
        )
        modulusCache[key] = m
        return m
    }

    /// Negacyclic product in `Z/2^{32}Z[X]/(X^N+1)`, bit-identical to schoolbook.
    package static func multiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
        precondition(a.count == b.count)
        let n = a.count
        var residues: [[UInt32]] = []
        residues.reserveCapacity(primeCount)
        for pi in 0..<primeCount {
            let m = modulus(primeIndex: pi, n: n)
            residues.append(multiplyMod(a, b, m))
        }
        return crtToUInt32(residues, n: n)
    }

    /// Twisted forward NTT (output in evaluation domain, natural order).
    package static func forwardTwisted(_ input: [UInt32], _ m: Modulus) -> [UInt32] {
        precondition(input.count == m.n)
        var a = input.map { UInt32(UInt64($0) % UInt64(m.p)) }
        let w = m.psi
        var acc: UInt32 = 1
        for i in 0..<m.n {
            a[i] = modMul(a[i], acc, m.p)
            acc = modMul(acc, w, m.p)
        }
        bitReverse(&a, logN: m.logN)
        nttInPlace(&a, root: m.omega, p: m.p)
        return a
    }

    /// Twiddle banks for Metal: `[prime][psi | psiInv | omega | omegaInv][0..<n]`.
    package static func twiddleTable(n: Int) -> [UInt32] {
        var table = [UInt32](repeating: 0, count: primeCount * 4 * n)
        for pi in 0..<primeCount {
            let m = modulus(primeIndex: pi, n: n)
            let base = pi * 4 * n
            var accPsi: UInt32 = 1
            var accPsiI: UInt32 = 1
            var accW: UInt32 = 1
            var accWI: UInt32 = 1
            for j in 0..<n {
                table[base + j] = accPsi
                table[base + n + j] = accPsiI
                table[base + 2 * n + j] = accW
                table[base + 3 * n + j] = accWI
                accPsi = modMul(accPsi, m.psi, m.p)
                accPsiI = modMul(accPsiI, m.psiInv, m.p)
                accW = modMul(accW, m.omega, m.p)
                accWI = modMul(accWI, m.omegaInv, m.p)
            }
        }
        return table
    }

    package static var crtInvP0ModP1: UInt32 { modInv(primes[0], primes[1]) }
    package static var crtInvP01ModP2: UInt32 {
        let p01 = UInt64(primes[0]) * UInt64(primes[1])
        return modInv(UInt32(p01 % UInt64(primes[2])), primes[2])
    }

    /// Inverse twisted NTT (evaluation domain → coeff domain, values in 0..<p).
    package static func inverseTwisted(_ input: [UInt32], _ m: Modulus) -> [UInt32] {
        precondition(input.count == m.n)
        var a = input
        bitReverse(&a, logN: m.logN)
        nttInPlace(&a, root: m.omegaInv, p: m.p)
        let w = m.psiInv
        var acc: UInt32 = 1
        for i in 0..<m.n {
            a[i] = modMul(modMul(a[i], m.nInv, m.p), acc, m.p)
            acc = modMul(acc, w, m.p)
        }
        return a
    }

    package static func multiplyMod(_ a: [UInt32], _ b: [UInt32], _ m: Modulus) -> [UInt32] {
        let fa = forwardTwisted(a, m)
        let fb = forwardTwisted(b, m)
        var prod = [UInt32](repeating: 0, count: m.n)
        for i in 0..<m.n {
            prod[i] = modMul(fa[i], fb[i], m.p)
        }
        return inverseTwisted(prod, m)
    }

    package static var crtModulusProduct: (hi: UInt64, lo: UInt64) {
        let p01 = UInt64(primes[0]) * UInt64(primes[1])
        return umul64(p01, UInt64(primes[2]))
    }

    package static func crtToUInt32(_ residues: [[UInt32]], n: Int) -> [UInt32] {
        precondition(residues.count == primeCount)
        let p0 = primes[0]
        let p1 = primes[1]
        let p2 = primes[2]
        let invP0ModP1 = modInv(p0, p1)
        let p01 = UInt64(p0) * UInt64(p1)
        let invP01ModP2 = modInv(UInt32(p01 % UInt64(p2)), p2)
        let P = umul64(p01, UInt64(p2))
        let halfP = (hi: P.hi >> 1, lo: (P.lo >> 1) | (P.hi << 63))
        var out = [UInt32](repeating: 0, count: n)
        for i in 0..<n {
            let a0 = residues[0][i]
            let a1 = residues[1][i]
            let a2 = residues[2][i]
            let v1 = modMul(modSub(a1, a0 % p1, p1), invP0ModP1, p1)
            let x01 = UInt64(a0) + UInt64(p0) * UInt64(v1)
            let x01modp2 = UInt32(x01 % UInt64(p2))
            let v2 = modMul(modSub(a2, x01modp2, p2), invP01ModP2, p2)
            var x = umul64(p01, UInt64(v2))
            let (sLo, c0) = x.lo.addingReportingOverflow(x01)
            x.lo = sLo
            if c0 { x.hi &+= 1 }
            if u128Ge(x, halfP) {
                x = u128Sub(x, P)
            }
            out[i] = UInt32(truncatingIfNeeded: x.lo)
        }
        return out
    }
}

private func umul64(_ a: UInt64, _ b: UInt64) -> (hi: UInt64, lo: UInt64) {
    let a0 = a & 0xFFFF_FFFF
    let a1 = a >> 32
    let b0 = b & 0xFFFF_FFFF
    let b1 = b >> 32
    let p00 = a0 * b0
    let p01 = a0 * b1
    let p10 = a1 * b0
    let p11 = a1 * b1
    var mid = (p00 >> 32) + (p01 & 0xFFFF_FFFF) + (p10 & 0xFFFF_FFFF)
    let lo = (p00 & 0xFFFF_FFFF) | (mid << 32)
    mid >>= 32
    let hi = p11 + (p01 >> 32) + (p10 >> 32) + mid
    return (hi, lo)
}

private func u128Ge(_ a: (hi: UInt64, lo: UInt64), _ b: (hi: UInt64, lo: UInt64)) -> Bool {
    a.hi != b.hi ? a.hi > b.hi : a.lo >= b.lo
}

private func u128Sub(
    _ a: (hi: UInt64, lo: UInt64),
    _ b: (hi: UInt64, lo: UInt64)
) -> (hi: UInt64, lo: UInt64) {
    let (lo, borrow) = a.lo.subtractingReportingOverflow(b.lo)
    var hi = a.hi &- b.hi
    if borrow { hi &-= 1 }
    return (hi, lo)
}

package func modMul(_ a: UInt32, _ b: UInt32, _ p: UInt32) -> UInt32 {
    UInt32((UInt64(a) * UInt64(b)) % UInt64(p))
}

package func modAdd(_ a: UInt32, _ b: UInt32, _ p: UInt32) -> UInt32 {
    let s = a &+ b
    return s >= p ? s &- p : s
}

package func modSub(_ a: UInt32, _ b: UInt32, _ p: UInt32) -> UInt32 {
    a >= b ? a &- b : (p &- (b &- a))
}

package func modPow(_ base: UInt32, _ exp: UInt32, _ p: UInt32) -> UInt32 {
    var result: UInt32 = 1
    var b = base % p
    var e = exp
    while e > 0 {
        if e & 1 != 0 { result = modMul(result, b, p) }
        b = modMul(b, b, p)
        e >>= 1
    }
    return result
}

package func modInv(_ a: UInt32, _ p: UInt32) -> UInt32 {
    modPow(a, p &- 2, p)
}

private func generator(p: UInt32) -> UInt32 {
    let pm1 = p - 1
    var n = pm1
    var factors: [UInt32] = []
    if n % 2 == 0 {
        factors.append(2)
        while n % 2 == 0 { n /= 2 }
    }
    var f: UInt32 = 3
    while f &* f <= n {
        if n % f == 0 {
            factors.append(f)
            while n % f == 0 { n /= f }
        }
        f += 2
    }
    if n > 1 { factors.append(n) }
    var g: UInt32 = 2
    while g < p {
        var ok = true
        for q in factors {
            if modPow(g, pm1 / q, p) == 1 {
                ok = false
                break
            }
        }
        if ok { return g }
        g += 1
    }
    preconditionFailure("no generator for p=\(p)")
}

private func bitReverse(_ a: inout [UInt32], logN: Int) {
    let n = a.count
    for i in 0..<n {
        let j = Int(bitReverse(UInt32(i), logN: logN))
        if i < j { a.swapAt(i, j) }
    }
}

package func bitReverse(_ x: UInt32, logN: Int) -> UInt32 {
    var r: UInt32 = 0
    var v = x
    for _ in 0..<logN {
        r = (r << 1) | (v & 1)
        v >>= 1
    }
    return r
}

private func nttInPlace(_ a: inout [UInt32], root: UInt32, p: UInt32) {
    let n = a.count
    var len = 2
    while len <= n {
        let wlen = modPow(root, UInt32(n / len), p)
        var start = 0
        while start < n {
            var w: UInt32 = 1
            let half = len / 2
            for j in 0..<half {
                let u = a[start + j]
                let v = modMul(a[start + j + half], w, p)
                a[start + j] = modAdd(u, v, p)
                a[start + j + half] = modSub(u, v, p)
                w = modMul(w, wlen, p)
            }
            start += len
        }
        len <<= 1
    }
}
