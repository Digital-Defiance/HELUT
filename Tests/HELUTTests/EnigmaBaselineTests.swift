import Metal
import XCTest
@testable import HELUTCore

final class EnigmaBaselineTests: XCTestCase {

    /// Unmutated TensorLUT Enigma must decrypt a short crib with \(F_{crypto} = 0\).
    func testEnigmaM4KnownGoodStream() throws {
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
        XCTAssertEqual(tensorNetlist.luts.count, 925)
        XCTAssertEqual(tensorNetlist.dffs.count, 49)

        // Derive CT/PT from the same cleartext netlist harness (compiled key: γ/IV-III-VIII,
        // thin B, rings AAAA, identity stecker, Greek window A).
        let left = EnigmaAlphabet.index("A")
        let middle = EnigmaAlphabet.index("A")
        let right = EnigmaAlphabet.index("A")
        let plaintext = "TEST"
        let clearHarness = EnigmaNetlistHarness(netlistPath: path)
        clearHarness.seedGrundstellung(left: left, middle: middle, right: right)
        let ciphertext = clearHarness.process(ciphertext: EnigmaAlphabet.normalize(plaintext))
        // Reciprocal: feed PT letters as "ciphertext" → scrambler emits CT; decrypt CT → PT.
        clearHarness.seedGrundstellung(left: left, middle: middle, right: right)
        let roundTrip = clearHarness.process(ciphertext: ciphertext)
        XCTAssertEqual(EnigmaAlphabet.string(from: roundTrip), plaintext)

        let target = EnigmaStreamBuilder.buildTarget(
            ciphertext: EnigmaAlphabet.string(from: ciphertext),
            plaintext: plaintext,
            left: left,
            middle: middle,
            right: right
        )
        XCTAssertEqual(target.stepCount, plaintext.count)
        XCTAssertEqual(target.inputWireIDs.count, 9) // resetn + 8 CT
        XCTAssertEqual(target.outputWireIDs.count, 5)

        let pipeline = try TensorLUTPipeline(device: device, netlist: tensorNetlist)
        let synthesizer = try AdversarialSynthesizer(device: device)
        let harness = AdversarialHarness(
            device: device,
            pipeline: pipeline,
            synthesizer: synthesizer,
            netlist: tensorNetlist
        )

        var lastStats: AdversarialHarness.GenerationStats?
        let baseline = harness.runStream(
            target: target,
            config: .init(
                populationSize: 1,
                generations: 1,
                eliteCount: 1,
                seedScatter: false,
                rngSeed: 1,
                seedInits: tensorNetlist.packedINITBuffer(),
                polishBinaryAtEnd: false
            ),
            progress: { lastStats = $0 }
        )

        XCTAssertEqual(
            lastStats?.bestCrypto ?? -1,
            0,
            accuracy: 1e-4,
            "TensorLUT stream MSE must be 0 on known-good Enigma crib"
        )
        XCTAssertEqual(
            baseline.fitness,
            0,
            accuracy: 1e-4,
            "Unmutated TensorLUT Enigma failed to decrypt the crib (fitness=\(baseline.fitness))"
        )
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
