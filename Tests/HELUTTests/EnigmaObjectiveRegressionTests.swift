import CryptoKit
import Foundation
import XCTest
@testable import HELUTCore
@testable import HELUTToolKit

final class EnigmaObjectiveRegressionTests: XCTestCase {
    private let denseRecoveredNonsense =
        "LLLWOHLARGULATTUSZITSPAMIROOOLOSTIKETTOLZFFNLIKDIBAKRJLDNRITZAUDHEMZEKKS"

    private func deterministicRandomSample(_ sampleIndex: Int) -> [Int] {
        let domain = Array("HELUT dense bigram calibration v2".utf8)
        var sample: [Int] = []
        var blockIndex = 0
        while sample.count < 72 {
            var payload = Data(domain)
            payload.append(0)
            for value in [sampleIndex, blockIndex] {
                let integer = UInt32(value)
                payload.append(UInt8(truncatingIfNeeded: integer >> 24))
                payload.append(UInt8(truncatingIfNeeded: integer >> 16))
                payload.append(UInt8(truncatingIfNeeded: integer >> 8))
                payload.append(UInt8(truncatingIfNeeded: integer))
            }
            for byte in SHA256.hash(data: payload) where byte < 234 {
                sample.append(Int(byte) % 26)
                if sample.count == 72 { break }
            }
            blockIndex += 1
        }
        return sample
    }

    private func populationStats(_ values: [Double]) -> (mean: Double, deviation: Double) {
        var total = 0.0
        for value in values { total = total + value }
        let mean = total / Double(values.count)
        var squaredTotal = 0.0
        for value in values {
            let delta = value - mean
            squaredTotal = squaredTotal + delta * delta
        }
        return (mean, sqrt(squaredTotal / Double(values.count)))
    }

    private func populationCovariance(
        _ lhs: [Double],
        lhsMean: Double,
        _ rhs: [Double],
        rhsMean: Double
    ) -> Double {
        precondition(lhs.count == rhs.count)
        var total = 0.0
        for (lhsValue, rhsValue) in zip(lhs, rhs) {
            total = total + (lhsValue - lhsMean) * (rhsValue - rhsMean)
        }
        return total / Double(lhs.count)
    }

    private func knownShell() -> (ciphertext: [Int], truth: [Int], baseKey: EnigmaM4Key) {
        let ciphertext = Array(EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext).prefix(72))
        let positions = EnigmaM4Key.positions(fromLetters: "VYAA")
        var trueMachine = EnigmaM4Machine(
            key: EnigmaM4Key.potsdam1May1945(positions: positions)
        )
        let truth = trueMachine.processText(ciphertext)
        let baseKey = EnigmaM4Key(
            greek: EnigmaM4Warehouse.gamma,
            rotors: (
                EnigmaWarehouse.rotorIV,
                EnigmaWarehouse.rotorIII,
                EnigmaWarehouse.rotorVIII
            ),
            rings: EnigmaM4Key.rings(fromLetters: "AACU"),
            positions: positions,
            plugboard: Array(0..<26),
            reflector: EnigmaM4Warehouse.thinB
        )
        return (ciphertext, truth, baseKey)
    }

    func testTrigramAndObjectiveCalibrationMatchIndependentReceipts() throws {
        XCTAssertTrue(GermanTrigrams.isLoaded)
        XCTAssertEqual(
            GermanTrigrams.modelID,
            "helut-german-trigram-add-k-0.5-e08a5659-v1"
        )
        XCTAssertEqual(GermanTrigrams.Calibration.germanMean, -2.967122)
        XCTAssertEqual(GermanTrigrams.Calibration.randomMean, -5.100027)
        XCTAssertEqual(GermanTrigrams.Calibration.randomDeviation, 0.248256)

        let controls = (0..<400).map(deterministicRandomSample)
        let trigramScores = controls.compactMap(GermanTrigrams.scoreIfLoaded)
        XCTAssertEqual(trigramScores.count, controls.count)
        let trigramStats = populationStats(trigramScores)
        XCTAssertEqual(trigramStats.mean.bitPattern, 0xc014_666d_81c4_f1fc)
        XCTAssertEqual(trigramStats.deviation.bitPattern, 0x3fcf_c6d9_9a2e_a2da)

        let attackScores = controls.map {
            HostM4Bombe.attackScore(plaintext: $0, scorer: .germanMilitary())
        }
        let attackStats = populationStats(attackScores)
        XCTAssertEqual(attackStats.mean.bitPattern, 0xc013_ca64_ce71_e32b)
        XCTAssertEqual(attackStats.deviation.bitPattern, 0x3fcd_e045_5070_675d)

        let covariance = populationCovariance(
            attackScores,
            lhsMean: attackStats.mean,
            trigramScores,
            rhsMean: trigramStats.mean
        )
        let correlation = covariance / (attackStats.deviation * trigramStats.deviation)
        XCTAssertEqual(covariance.bitPattern, 0x3f9d_b4ca_a1cf_ae49)
        XCTAssertEqual(correlation.bitPattern, 0x3fe0_0553_b8b4_46b6)

        let objectiveStats = populationStats(controls.map(EnigmaSearchObjective.score))
        XCTAssertEqual(EnigmaSearchObjective.attackRandomMean, -4.947650)
        XCTAssertEqual(EnigmaSearchObjective.attackRandomDeviation, 0.233407)
        XCTAssertEqual(EnigmaSearchObjective.attackTrigramCorrelation, 0.500650)
        XCTAssertEqual(EnigmaSearchObjective.trigramWeight, 0.499350)
        XCTAssertEqual(
            EnigmaSearchObjective.modelID,
            "helut-enigma-search-n72-correlation-discounted-z-06f8694e-e08a5659-v2"
        )
        XCTAssertEqual(objectiveStats.mean.bitPattern, 0xbea5_6104_8d3b_051f)
        XCTAssertEqual(objectiveStats.deviation.bitPattern, 0x3fec_3a72_6a2a_0d89)
    }

    func testTruthBeatsDenseBigramOverfitUnderSeparateAttestedEvidence() throws {
        let fixture = knownShell()
        let recovered = EnigmaAlphabet.normalize(denseRecoveredNonsense)
        XCTAssertEqual(fixture.truth.count, 72)
        XCTAssertEqual(recovered.count, 72)

        let truthBigram = LanguageScorer.bigramScore(fixture.truth)
        let recoveredBigram = LanguageScorer.bigramScore(recovered)
        XCTAssertGreaterThan(recoveredBigram, truthBigram, "Documents the raw-bigram objective trap")

        let truthTrigram = try XCTUnwrap(GermanTrigrams.scoreIfLoaded(fixture.truth))
        let recoveredTrigram = try XCTUnwrap(GermanTrigrams.scoreIfLoaded(recovered))
        XCTAssertEqual(truthTrigram.bitPattern, 0xc007_bcaa_6c6f_d790)
        XCTAssertEqual(recoveredTrigram.bitPattern, 0xc00d_6ee3_44c5_114d)
        XCTAssertGreaterThan(truthTrigram, recoveredTrigram)

        let truthAttack = HostM4Bombe.attackScore(
            plaintext: fixture.truth,
            scorer: .germanMilitary()
        )
        let recoveredAttack = HostM4Bombe.attackScore(
            plaintext: recovered,
            scorer: .germanMilitary()
        )
        XCTAssertGreaterThan(truthAttack, recoveredAttack)

        let truthObjective = try XCTUnwrap(EnigmaSearchObjective.scoreRequiringTrigram(fixture.truth))
        let recoveredObjective = try XCTUnwrap(EnigmaSearchObjective.scoreRequiringTrigram(recovered))
        XCTAssertEqual(truthObjective.bitPattern, 0x401e_d818_0b0a_6dd9)
        XCTAssertEqual(recoveredObjective.bitPattern, 0x4018_84df_b596_c4a1)
        XCTAssertGreaterThan(truthObjective, recoveredObjective)

        let truthAssessment = EnigmaFinalAssessment.evaluate(plaintext: fixture.truth)
        let recoveredAssessment = EnigmaFinalAssessment.evaluate(plaintext: recovered)
        XCTAssertTrue(truthAssessment.isPossibleBreak, truthAssessment.reason)
        XCTAssertFalse(recoveredAssessment.isPossibleBreak, recoveredAssessment.reason)

        let unavailable = EnigmaFinalAssessment.evaluate(
            plaintext: fixture.truth,
            verifiedTrigramScore: nil
        )
        XCTAssertEqual(unavailable.status, .modelUnavailable)
        XCTAssertFalse(unavailable.isPossibleBreak)
    }

    func testCalibratedObjectiveImprovesKnownShellRecoveryWithoutForcingTenPlugs() {
        let fixture = knownShell()
        let baseline = ExhaustiveCracker.hillClimb(
            key: fixture.baseKey,
            ciphertext: fixture.ciphertext,
            maxPlugs: 10,
            scorePlaintext: LanguageScorer.bigramScore
        )
        XCTAssertEqual(EnigmaAlphabet.string(from: baseline.plain), denseRecoveredNonsense)

        let improved = ExhaustiveCracker.hillClimb(
            key: fixture.baseKey,
            ciphertext: fixture.ciphertext,
            maxPlugs: 10
        )
        let truePairs: Set<Set<Int>> = Set(
            [("C", "H"), ("E", "J"), ("N", "V"), ("O", "U"), ("T", "Y"),
             ("L", "G"), ("S", "Z"), ("P", "K"), ("D", "I"), ("Q", "B")]
                .map {
                    Set([
                        EnigmaAlphabet.index(Character($0.0)),
                        EnigmaAlphabet.index(Character($0.1)),
                    ])
                }
        )
        func recovery(_ result: (pairs: [(Int, Int)], score: Double, plain: [Int]))
            -> (letters: Int, pairs: Int) {
            let letters = zip(result.plain, fixture.truth).filter { $0 == $1 }.count
            let proposed = Set(result.pairs.map { Set([$0.0, $0.1]) })
            return (letters, proposed.intersection(truePairs).count)
        }

        let baselineRecovery = recovery(baseline)
        let improvedRecovery = recovery(improved)
        XCTAssertEqual(baselineRecovery.letters, 21)
        XCTAssertEqual(baselineRecovery.pairs, 4)
        XCTAssertEqual(
            EnigmaAlphabet.string(from: improved.plain),
            "NNNWOLNARSUNSTTOSOITSXDMIROOONISSIKETTONZWBGNIKSIBATRONDORIVZAUDLEGSEKKS"
        )
        XCTAssertEqual(improvedRecovery.letters, 25)
        XCTAssertEqual(improvedRecovery.pairs, 5)
        XCTAssertEqual(improved.pairs.count, 7)

        let assessment = EnigmaFinalAssessment.evaluate(plaintext: improved.plain)
        XCTAssertFalse(assessment.isPossibleBreak, "Ranking improvement is not publication confidence")

        let zeroPlug = ExhaustiveCracker.hillClimb(
            key: fixture.baseKey,
            ciphertext: fixture.ciphertext,
            maxPlugs: 0
        )
        XCTAssertTrue(zeroPlug.pairs.isEmpty)
    }
}
