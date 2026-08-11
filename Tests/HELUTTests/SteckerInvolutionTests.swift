import Metal
import XCTest
@testable import HELUTCore

final class SteckerInvolutionTests: XCTestCase {

    func testInvolutionLegalityUnderMutateAndCrossover() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<40 {
            var a = SteckerInvolution.random(maxPairs: 10, rng: &rng)
            XCTAssertTrue(SteckerInvolution.isValid(a.pairs))
            a = a.mutated(maxPairs: 10, rng: &rng)
            XCTAssertTrue(SteckerInvolution.isValid(a.pairs))
            let b = SteckerInvolution.random(maxPairs: 10, rng: &rng)
            let child = SteckerInvolution.crossover(a, b, maxPairs: 10, rng: &rng)
            XCTAssertTrue(SteckerInvolution.isValid(child.pairs))
            XCTAssertLessThanOrEqual(child.pairCount, 10)
        }
    }

    func testIOProjectionBitWidths() {
        XCTAssertEqual(SteckerIOProjection.ciphertextBits(25).count, 8)
        XCTAssertEqual(SteckerIOProjection.plaintextBits(25).count, 5)
        XCTAssertEqual(SteckerIOProjection.ciphertextBits(0), [0, 0, 0, 0, 0, 0, 0, 0])
        XCTAssertEqual(SteckerIOProjection.plaintextBits(0b10101), [1, 0, 1, 0, 1])
    }

    func testMapTableIsSelfInverse() {
        let s = SteckerInvolution(pairs: [(0, 1), (2, 25)])
        let map = s.mapTable()
        for i in 0..<26 {
            XCTAssertEqual(map[map[i]], i)
        }
        XCTAssertEqual(s.apply(0), 1)
        XCTAssertEqual(s.apply(1), 0)
        XCTAssertEqual(s.apply(5), 5)
    }

    /// Identity stecker on the known-good crib must yield \(F_{crypto}=0\).
    func testIdentitySandwichZeroCrypto() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        guard let path = resolveNetlistPath("enigma_m4_netlist.json") else {
            throw XCTSkip("enigma_m4_netlist.json not found")
        }

        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty enigma_m4 netlist")
        }
        let tensorNetlist = TensorLUTCompiler.compile(module: module)
        let left = EnigmaAlphabet.index("A")
        let middle = EnigmaAlphabet.index("A")
        let right = EnigmaAlphabet.index("A")
        let plaintext = "TEST"
        let clearHarness = EnigmaNetlistHarness(netlistPath: path)
        clearHarness.seedGrundstellung(left: left, middle: middle, right: right)
        let ciphertext = clearHarness.process(ciphertext: EnigmaAlphabet.normalize(plaintext))

        let pipeline = try TensorLUTPipeline(device: device, netlist: tensorNetlist)
        let synthesizer = try AdversarialSynthesizer(device: device)
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: tensorNetlist
        )

        var last: AdversarialHarness.SteckerGenerationStats?
        let best = harness.runSteckerInvolution(
            ciphertext: EnigmaAlphabet.string(from: ciphertext),
            plaintext: plaintext,
            left: left,
            middle: middle,
            right: right,
            config: .init(
                populationSize: 1,
                generations: 1,
                eliteCount: 1,
                maxPairs: 10,
                rngSeed: 1,
                seedStecker: .identity()
            ),
            progress: { last = $0 }
        )

        XCTAssertEqual(last?.bestFitness ?? -1, 0, accuracy: 1e-4)
        XCTAssertEqual(best.fitness, 0, accuracy: 1e-4)
        XCTAssertEqual(best.pairCount, 0)
    }

    /// Blind rediscovery on a short crib with one identifiable pair.
    func testBlindRediscoverActiveMapShortCrib() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        guard let path = resolveNetlistPath("enigma_m4_netlist.json") else {
            throw XCTSkip("enigma_m4_netlist.json not found")
        }

        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty enigma_m4 netlist")
        }
        let tensorNetlist = TensorLUTCompiler.compile(module: module)
        let left = EnigmaAlphabet.index("A")
        let middle = EnigmaAlphabet.index("A")
        let right = EnigmaAlphabet.index("A")
        let plaintext = "TEST"
        let ptLetters = EnigmaAlphabet.normalize(plaintext)
        // D appears in fabricated CT; CD is the identifiable plug on this crib.
        let truth = SteckerInvolution(pairs: [(2, 3)]) // CD
        let clearHarness = EnigmaNetlistHarness(netlistPath: path)
        let ctLetters = SteckerInvolution.fabricateCiphertext(
            plaintext: ptLetters,
            stecker: truth,
            harness: clearHarness,
            left: left,
            middle: middle,
            right: right
        )

        let pipeline = try TensorLUTPipeline(device: device, netlist: tensorNetlist)
        let synthesizer = try AdversarialSynthesizer(device: device)
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: tensorNetlist
        )

        let best = harness.runSteckerInvolution(
            ciphertext: EnigmaAlphabet.string(from: ctLetters),
            plaintext: plaintext,
            left: left,
            middle: middle,
            right: right,
            config: .init(
                populationSize: 32,
                generations: 40,
                eliteCount: 4,
                maxPairs: 2,
                rngSeed: 0xB11D_0002,
                seedStecker: nil,
                immigrantFraction: 0.2,
                parsimony: true,
                growPairs: true,
                growPlateauGens: 3,
                freezeElitePairs: true
            )
        )

        XCTAssertEqual(best.fitness, 0, accuracy: 1e-4)
        let active = Set(ctLetters + ptLetters)
        XCTAssertTrue(
            best.agrees(with: truth, on: active),
            "active map mismatch: got \(best.descriptionPairs()) want \(truth.descriptionPairs())"
        )
        XCTAssertEqual(best.pairCount, 1)
        XCTAssertEqual(best.pairs.first?.0, 2)
        XCTAssertEqual(best.pairs.first?.1, 3)
    }

    /// Longer crib + denser stecker: blind search recovers the full involution.
    func testBlindRediscoverScaledCrib() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        guard let path = resolveNetlistPath("enigma_m4_netlist.json") else {
            throw XCTSkip("enigma_m4_netlist.json not found")
        }

        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty enigma_m4 netlist")
        }
        let tensorNetlist = TensorLUTCompiler.compile(module: module)
        let left = EnigmaAlphabet.index("A")
        let middle = EnigmaAlphabet.index("A")
        let right = EnigmaAlphabet.index("A")
        let plaintext = "ABCDEFGHIJKLMN"
        let ptLetters = EnigmaAlphabet.normalize(plaintext)
        let truth = SteckerInvolution(pairs: [
            (0, 1), (2, 3), (4, 5) // AB CD EF
        ])
        let clearHarness = EnigmaNetlistHarness(netlistPath: path)
        let ctLetters = SteckerInvolution.fabricateCiphertext(
            plaintext: ptLetters,
            stecker: truth,
            harness: clearHarness,
            left: left,
            middle: middle,
            right: right
        )

        let pipeline = try TensorLUTPipeline(device: device, netlist: tensorNetlist)
        let synthesizer = try AdversarialSynthesizer(device: device)
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: tensorNetlist
        )

        let best = harness.runSteckerInvolution(
            ciphertext: EnigmaAlphabet.string(from: ctLetters),
            plaintext: plaintext,
            left: left,
            middle: middle,
            right: right,
            config: .init(
                populationSize: 48,
                generations: 120,
                eliteCount: 6,
                maxPairs: 3,
                rngSeed: 0x5CA1_ED02,
                seedStecker: nil,
                immigrantFraction: 0.25,
                parsimony: true,
                growPairs: true,
                growPlateauGens: 3,
                freezeElitePairs: true
            )
        )

        XCTAssertEqual(best.fitness, 0, accuracy: 1e-4)
        let active = Set(ctLetters + ptLetters)
        XCTAssertTrue(
            best.agrees(with: truth, on: active),
            "active map mismatch: got \(best.descriptionPairs()) want \(truth.descriptionPairs())"
        )
        XCTAssertEqual(best.pairs.map { [$0.0, $0.1] }, truth.pairs.map { [$0.0, $0.1] })
    }

    /// Fabricate CT under a known stecker; GA seeded near-truth should recover it.
    func testRediscoverKnownSteckerPairs() throws {
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw XCTSkip("Metal device not available")
        }
        guard let path = resolveNetlistPath("enigma_m4_netlist.json") else {
            throw XCTSkip("enigma_m4_netlist.json not found")
        }

        let yosys = loadYosysNetlist(from: path)
        guard let (_, module) = yosys.modules.first else {
            return XCTFail("empty enigma_m4 netlist")
        }
        let tensorNetlist = TensorLUTCompiler.compile(module: module)
        let left = EnigmaAlphabet.index("A")
        let middle = EnigmaAlphabet.index("A")
        let right = EnigmaAlphabet.index("A")
        let plaintext = "TEST"
        let ptLetters = EnigmaAlphabet.normalize(plaintext)
        let truth = SteckerInvolution(pairs: [(0, 1), (2, 3)]) // AB CD
        let map = truth.mapTable()

        let clearHarness = EnigmaNetlistHarness(netlistPath: path)
        clearHarness.seedGrundstellung(left: left, middle: middle, right: right)
        let midCT = clearHarness.process(ciphertext: ptLetters.map { map[$0] })
        let ctLetters = midCT.map { map[$0] }

        let pipeline = try TensorLUTPipeline(device: device, netlist: tensorNetlist)
        let synthesizer = try AdversarialSynthesizer(device: device)
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: tensorNetlist
        )

        let best = harness.runSteckerInvolution(
            ciphertext: EnigmaAlphabet.string(from: ctLetters),
            plaintext: plaintext,
            left: left,
            middle: middle,
            right: right,
            config: .init(
                populationSize: 24,
                generations: 40,
                eliteCount: 4,
                maxPairs: 4,
                rngSeed: 0xAB_CD,
                seedStecker: truth
            )
        )

        XCTAssertEqual(best.fitness, 0, accuracy: 1e-4)
        XCTAssertEqual(Set(best.pairs.map { [$0.0, $0.1] }), Set(truth.pairs.map { [$0.0, $0.1] }))
    }
}

private func resolveNetlistPath(_ filename: String) -> String? {
    let fileManager = FileManager.default
    let cwd = fileManager.currentDirectoryPath
    let candidates = [
        filename,
        "../\(filename)",
        "../../\(filename)",
        "../../../\(filename)"
    ]
    for relative in candidates {
        let path = (cwd as NSString).appendingPathComponent(relative)
        if fileManager.fileExists(atPath: path) { return path }
    }
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<5 {
        url.deleteLastPathComponent()
        let candidate = url.appendingPathComponent(filename).path
        if fileManager.fileExists(atPath: candidate) { return candidate }
    }
    return nil
}
