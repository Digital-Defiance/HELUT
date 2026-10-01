import XCTest
@testable import HELUTCore

final class TFHEPortWeightTests: XCTestCase {
    func testStrideCapAllowsLUT3AtK127() {
        let scale = rotationBooleanScale(polynomialDegree: 1024, mul: 127)
        XCTAssertEqual(booleanScaleFactor(polynomialDegree: 1024, scale: scale), 127)
        let table = [UInt32](repeating: 0, count: 8)
        let poly = TFHETestPolyCache().testPolynomial(
            truthTable: table,
            degree: 1024,
            scale: scale
        )
        XCTAssertEqual(poly.count, 1024)
    }

    func testPortWeightedGateClearsAdderAndRefusesPicoRV() throws {
        let sigma = 637_757.0
        let delta = rotationScale(polynomialDegree: 1024)
        let adder = try loadModule("netlist.json")
        let adderBudgets = TFHENoisyPortWeight.budgets(luts: adder.luts, dffs: adder.dffs)
        let adderCert = TFHENoisyBKGaussianCertificate.forNoisyPorts(
            sigmaBK: sigma,
            nativeDelta: delta,
            booleanK: 7,
            budgets: adderBudgets
        )
        XCTAssertLessThanOrEqual(adderCert.failureLog2, -64, "full adder must still clear")
        XCTAssertTrue(adderCert.isSecure)
        XCTAssertEqual(adderBudgets.reduce(0) { $0 + $1.noisyCount }, 1)

        let pico = try loadModule("Generated/Netlists/PicoRV32/picorv32_lut6_netlist.json")
        let picoBudgets = TFHENoisyPortWeight.budgets(luts: pico.luts, dffs: pico.dffs)
        let picoCert = TFHENoisyBKGaussianCertificate.forNoisyPorts(
            sigmaBK: sigma,
            nativeDelta: delta,
            booleanK: 7,
            budgets: picoBudgets
        )
        XCTAssertGreaterThan(picoCert.failureLog2, 0, "lut6 at k=7 saturates")
        XCTAssertFalse(picoCert.isSecure)
        XCTAssertGreaterThan(picoBudgets.reduce(0) { $0 + $1.noisyCount }, 1000)
    }

    func testRefreshedNativeErrorRoundsPastHalfDelta() {
        let delta: UInt32 = 1 << 21
        XCTAssertEqual(
            refreshedNativeError(phase: 1_205_312, expected: 0, nativeDelta: delta),
            1
        )
        XCTAssertEqual(
            refreshedNativeError(phase: delta / 2 - 1, expected: 0, nativeDelta: delta),
            0
        )
    }

    private func loadModule(_ relative: String) throws -> CleartextNetlistSimulator {
        guard let path = resolveRepoFile(relative) else {
            XCTFail("missing \(relative)")
            throw CocoaError(.fileNoSuchFile)
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (name, module) = netlist.modules.first else {
            XCTFail("empty \(relative)")
            throw CocoaError(.fileReadCorruptFile)
        }
        return CleartextNetlistSimulator(moduleName: name, module: module)
    }

    private func resolveRepoFile(_ name: String) -> String? {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<6 {
            url.deleteLastPathComponent()
            let candidate = url.appendingPathComponent(name).path
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
        }
        return nil
    }
}
