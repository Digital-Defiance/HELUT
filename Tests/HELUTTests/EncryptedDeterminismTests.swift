import XCTest

@testable import HELUTCore

/// Regression tests for encrypted-path determinism.
///
/// Background. Until 2026-08-15 `EncryptedNetlistSimulator.tick` encrypted the
/// primary inputs while iterating `inputs` as a `Dictionary`, drawing from the
/// shared serial RNG inside the loop. Swift randomises Dictionary hash seeds per
/// process, so each run handed a different mask vector to a different wire. The
/// ciphertexts and the noise realisation differed run to run, and wherever the
/// margin was thin the decode became a coin toss: the n=512 covering-b2 adder
/// SING alternated between PASS and a `sum mismatch` fatalError with every seed
/// fixed and an identical measured B_bk.
///
/// The reason no existing test caught it is worth stating, because it shapes
/// these tests. Within a single process the hash seed is constant, so the naive
/// check — run the same tick twice and compare — passes with or without the bug.
/// The property that actually broke is *invariance of the result to the order in
/// which the input dictionary happens to be walked*, and that is what
/// `testEncryptedTickIsInvariantToInputDictionaryOrder` exercises.
final class EncryptedDeterminismTests: XCTestCase {

    /// Local copy: the helper in TFHESeamTests.swift is file-private.
    private func repoFile(_ name: String) -> String? {
        let fm = FileManager.default
        let cwd = fm.currentDirectoryPath
        for relative in [name, "../\(name)", "../../\(name)", "../../../\(name)"] {
            let path = URL(fileURLWithPath: cwd).appendingPathComponent(relative).path
            if fm.fileExists(atPath: path) { return path }
        }
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(name).path
            if fm.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }

    private func loadAdder() -> (String, YosysModule)? {
        guard let path = repoFile("netlist.json") else { return nil }
        let netlist = loadYosysNetlist(from: path)
        return netlist.modules.first.map { ($0.key, $0.value) }
    }

    private func makeSim(_ moduleName: String, _ module: YosysModule) -> EncryptedNetlistSimulator {
        let params = GGSWParams.booleanTrivial(degree: 8)
        let secret = TFHESecretKey.random(params: params.tfhe, seed: 0xD371)
        return EncryptedNetlistSimulator(
            moduleName: moduleName,
            module: module,
            secret: secret,
            params: params,
            backend: .blindRotate,
            seed: 0xD372
        )
    }

    /// Why this asserts on the INPUT fingerprint, not the outputs.
    ///
    /// The fault was in input encryption, so that is where it is observable.
    /// Two dead ends, recorded so nobody repeats them:
    ///
    ///  - Under an e=0 bootstrap key, blind rotation cancels the input mask
    ///    exactly (the accumulator is `X^(b - <a,s>) . testPoly` = `X^message .
    ///    testPoly`), so permuting the input order leaves every *output*
    ///    ciphertext byte-identical. An output-fingerprint test passes with the
    ///    bug still in place — I verified that by reintroducing it.
    ///  - Injecting enough BK noise to make masks matter downstream pushes
    ///    `booleanPublicMS` past δ/2 (`B_bk 134218072, decodable false`) and
    ///    traps before the assertion runs.
    ///
    /// Fingerprinting the freshly encrypted inputs avoids both.

    /// The real regression guard.
    ///
    /// Keys that do not name a port are skipped by the `guard let portBits`
    /// without consuming the RNG, but their presence changes the Dictionary's
    /// internal layout and therefore the order in which the *real* ports are
    /// visited. Under the old code that permuted which wire received which mask
    /// and the fingerprint moved. Under sorted iteration the real ports are
    /// always visited in the same relative order, so every variant must produce
    /// byte-identical output ciphertexts.
    func testEncryptedTickIsInvariantToInputDictionaryOrder() throws {
        guard let (moduleName, module) = loadAdder() else {
            return XCTFail("netlist.json not found")
        }

        let real: [String: [UInt8]] = ["a": [1], "b": [0], "cin": [1]]
        // Several decoy sets, to make it very likely at least one permutes the
        // iteration order of the three real keys.
        let decoySets: [[String: [UInt8]]] = [
            [:],
            ["zzz_decoy": [0]],
            ["aaa_decoy": [1], "mmm_decoy": [0]],
            ["q": [0], "r": [1], "s": [0], "t": [1]],
            ["decoy_0": [0], "decoy_1": [1], "decoy_2": [0], "decoy_3": [1], "decoy_4": [0]]
        ]

        var fingerprints: [UInt64] = []
        var outputs: [[String: [UInt8]]] = []

        for decoys in decoySets {
            let sim = makeSim(moduleName, module)
            var inputs = real
            for (k, v) in decoys { inputs[k] = v }
            let got = try sim.tick(inputs: inputs)
            fingerprints.append(sim.lastInputFingerprint)
            outputs.append(got)
        }

        XCTAssertFalse(fingerprints.contains(0), "input fingerprint was never set")
        for (i, fp) in fingerprints.enumerated().dropFirst() {
            XCTAssertEqual(
                fp, fingerprints[0],
                """
                Input ciphertexts changed when unrelated keys were added to \
                the input dictionary (variant \(i)). Input encryption is walking \
                the dictionary in hash order while consuming the shared RNG, so \
                mask vectors are being assigned to wires nondeterministically. \
                Iterate ports in sorted order.
                """
            )
            XCTAssertEqual(outputs[i], outputs[0], "decoded outputs diverged (variant \(i))")
        }
    }

    /// Same seed, two fresh simulators, identical ciphertexts.
    ///
    /// This does not catch hash-order dependence (see the class comment) but it
    /// does catch any future nondeterminism that is *not* hash-seed related —
    /// an unsynchronised cache, or a race introduced into the wavefront.
    func testTwoSimulatorsWithSameSeedAgreeBitForBit() throws {
        guard let (moduleName, module) = loadAdder() else {
            return XCTFail("netlist.json not found")
        }
        let inputs: [String: [UInt8]] = ["a": [1], "b": [1], "cin": [0]]

        let simA = makeSim(moduleName, module)
        let simB = makeSim(moduleName, module)
        let outA = try simA.tick(inputs: inputs)
        let outB = try simB.tick(inputs: inputs)

        XCTAssertEqual(outA, outB)
        XCTAssertNotEqual(simA.lastInputFingerprint, 0)
        XCTAssertEqual(
            simA.lastInputFingerprint, simB.lastInputFingerprint,
            "two simulators with the same seed produced different ciphertexts"
        )
    }

    /// Repeated ticks on one simulator must stay self-consistent against the
    /// cleartext oracle. The RNG advances between ticks, so ciphertexts differ
    /// by design; the decoded result must not.
    func testRepeatedTicksMatchCleartextAcrossRNGAdvance() throws {
        guard let (moduleName, module) = loadAdder() else {
            return XCTFail("netlist.json not found")
        }
        let sim = makeSim(moduleName, module)
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)

        var seenFingerprints = Set<UInt64>()
        for round in 0..<3 {
            for a in 0...1 {
                for b in 0...1 {
                    let inputs: [String: [UInt8]] = ["a": [UInt8(a)], "b": [UInt8(b)], "cin": [0]]
                    let want = clear.tick(inputs: inputs)
                    let got = try sim.tick(inputs: inputs)
                    XCTAssertEqual(got["sum"], want["sum"], "round \(round) a=\(a) b=\(b)")
                    XCTAssertEqual(got["cout"], want["cout"], "round \(round) a=\(a) b=\(b)")
                    seenFingerprints.insert(sim.lastInputFingerprint)
                }
            }
        }
        // Fresh randomness per tick: fingerprints should not all collapse to one
        // value, which would mean the RNG was not advancing.
        XCTAssertGreaterThan(seenFingerprints.count, 1, "ciphertexts never changed across ticks")
    }

    /// The fingerprint must not depend on Swift's per-process `Hasher` seed, or
    /// it cannot be compared across runs.
    func testFingerprintIsStableAcrossDictionaryConstruction() {
        let ct = LWECiphertext(a: [1, 2, 3, 4], b: 5)
        let wires: [Int: LWECiphertext] = [7: ct]
        let portsA: [String: [YosysBit]] = ["out": [.net(7)]]
        var portsB: [String: [YosysBit]] = [:]
        portsB["out"] = [.net(7)]
        XCTAssertEqual(
            EncryptedNetlistSimulator.fingerprint(wires: wires, ports: portsA),
            EncryptedNetlistSimulator.fingerprint(wires: wires, ports: portsB)
        )
        // And it must actually depend on the ciphertext.
        let other: [Int: LWECiphertext] = [7: LWECiphertext(a: [1, 2, 3, 4], b: 6)]
        XCTAssertNotEqual(
            EncryptedNetlistSimulator.fingerprint(wires: wires, ports: portsA),
            EncryptedNetlistSimulator.fingerprint(wires: other, ports: portsA)
        )
    }
}
