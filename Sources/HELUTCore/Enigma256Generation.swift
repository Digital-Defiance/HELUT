import CryptoKit
import Foundation

// MARK: - E256-v2 native NLFF profile
//
// The active profile is immutable generation data selected before a context is
// built. Its eight balanced component truth tables are semantics; the matching
// reversible XOR/Toffoli gate networks and search evidence remain in the
// generation receipt. This is a bounded research profile, not a security proof.

package enum Enigma256NLFFFormula: String, Sendable, Equatable, Codable {
    case nativeReversible16 = "native_reversible_16"
}

/// One balanced seven-input component produced by a reversible gate network.
package struct Enigma256NLFFComponent: Sendable, Equatable, Codable, Hashable {
    package let truthLow: UInt64
    package let truthHigh: UInt64

    package init(truthHex: String) {
        precondition(truthHex.count == 32, "NLFF component truth table must contain 128 bits")
        let split = truthHex.index(truthHex.startIndex, offsetBy: 16)
        guard let high = UInt64(truthHex[..<split], radix: 16),
              let low = UInt64(truthHex[split...], radix: 16) else {
            preconditionFailure("invalid NLFF truth table hex")
        }
        self.truthLow = low
        self.truthHigh = high
        precondition(ones == 64, "native NLFF components must be exactly balanced")
    }

    package init(truthLow: UInt64, truthHigh: UInt64) {
        self.truthLow = truthLow
        self.truthHigh = truthHigh
    }

    package var ones: Int { truthLow.nonzeroBitCount + truthHigh.nonzeroBitCount }

    package var truthHex: String {
        String(format: "%016llx%016llx", truthHigh, truthLow)
    }

    package func evaluate(_ input: UInt8) -> Bool {
        precondition(input < 128)
        if input < 64 {
            return ((truthLow >> UInt64(input)) & 1) != 0
        }
        return ((truthHigh >> UInt64(input - 64)) & 1) != 0
    }

    private enum CodingKeys: String, CodingKey { case truthHex = "truth_hex" }

    package init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let text = try container.decode(String.self, forKey: .truthHex)
        guard text.count == 32 else {
            throw DecodingError.dataCorruptedError(
                forKey: .truthHex,
                in: container,
                debugDescription: "NLFF truth table must be exactly 32 hex characters"
            )
        }
        let split = text.index(text.startIndex, offsetBy: 16)
        guard let high = UInt64(text[..<split], radix: 16),
              let low = UInt64(text[split...], radix: 16) else {
            throw DecodingError.dataCorruptedError(
                forKey: .truthHex,
                in: container,
                debugDescription: "NLFF truth table contains non-hex data"
            )
        }
        truthLow = low
        truthHigh = high
        guard ones == 64 else {
            throw DecodingError.dataCorruptedError(
                forKey: .truthHex,
                in: container,
                debugDescription: "NLFF component is not exactly balanced"
            )
        }
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(truthHex, forKey: .truthHex)
    }
}

/// One rotor-enable filter over sixteen distinct state taps.
///
/// `taps[0] XOR component[left](taps[1...7]) XOR
///  taps[8] XOR component[right](taps[9...15])`
package struct Enigma256NLFFFold: Sendable, Equatable, Codable, Hashable {
    package let taps: [Int]
    package let leftComponent: Int
    package let rightComponent: Int

    package init(taps: [Int], leftComponent: Int, rightComponent: Int) {
        precondition(taps.count == 16)
        precondition(Set(taps).count == 16)
        precondition(taps.allSatisfy { (0 ..< 64).contains($0) })
        precondition((0 ..< 8).contains(leftComponent))
        precondition((0 ..< 8).contains(rightComponent))
        self.taps = taps
        self.leftComponent = leftComponent
        self.rightComponent = rightComponent
    }

    package func evaluate(_ state: UInt64, components: [Enigma256NLFFComponent]) -> Bool {
        var leftInput: UInt8 = 0
        var rightInput: UInt8 = 0
        for bit in 0 ..< 7 {
            leftInput |= UInt8((state >> UInt64(taps[bit + 1])) & 1) << UInt8(bit)
            rightInput |= UInt8((state >> UInt64(taps[bit + 9])) & 1) << UInt8(bit)
        }
        let leftPivot = ((state >> UInt64(taps[0])) & 1) != 0
        let rightPivot = ((state >> UInt64(taps[8])) & 1) != 0
        let left = leftPivot != components[leftComponent].evaluate(leftInput)
        let right = rightPivot != components[rightComponent].evaluate(rightInput)
        return left != right
    }

    private enum CodingKeys: String, CodingKey {
        case taps
        case leftComponent = "left_component"
        case rightComponent = "right_component"
    }
}

package enum Enigma256GenerationError: Error, Equatable {
    case wrongFamily(String)
    case unsupportedSuite(Int)
    case invalidGeneration(Int)
    case unsupportedFixtureSchema(Int)
    case unsupportedTransition(String)
    case unsupportedUpdateOrder(String)
    case unsupportedCenterConstruction(String)
    case unsupportedCenterMaskKeyKDF(String)
    case unsupportedCenterMaskPRF(String)
    case unsupportedCenterMaskKeyDomain(String)
    case unsupportedCenterMaskBlockDomain(String)
    case unsupportedCenterMaskCounter(String)
    case unsupportedCenterMaskExtraction(String)
    case unsupportedCenterMapOrder(String)
    case unsupportedFormula
    case invalidComponentCount(Int)
    case unbalancedComponent(Int)
    case invalidFoldCount(Int)
    case invalidFold(Int)
    case stateTapPartition
    case componentAssignment
    case invalidResearchStatus(String)
    case invalidReceipt
    case profileHashMismatch(expected: String, actual: String)
}

package struct Enigma256Generation: Sendable, Equatable, Codable {
    package static let supportedFixtureSchemaVersion = 4
    package static let transitionIdentifier = "right_shift_lsb_galois_d800000000000000"
    package static let updateOrderIdentifier = "derive_prestep_mask_and_counter_mask_scramble_then_step_and_increment"
    package static let centerConstructionIdentifier = "conjugated_xor_counter_prf_v1"
    package static let centerMaskKeyKDFIdentifier = "hkdf_sha512_nonce_salt_32_v1"
    package static let centerMaskPRFIdentifier = "hmac_sha256_32_byte_blocks_v1"
    package static let centerMaskKeyDomainIdentifier = "center-mask-key"
    package static let centerMaskBlockDomainIdentifier = "center-mask-block"
    package static let centerMaskCounterIdentifier = "uint64_be_block_counter_start_0"
    package static let centerMaskExtractionIdentifier = "digest_byte_i_mod_32_allow_zero"
    package static let centerMapOrderIdentifier = "plugboard_forward_rotors_xor_mask_reverse_rotors_plugboard_v1"

    /// Historical task-3 identity. This schema-2 tuple binds the corrected LFSR
    /// and native NLFF only; it predates the revised center and is not loadable.
    package static let historicalSchema2ProfileSHA256 = "6734d50d5e985edea4278a897a42e03ec0cf220cc4014bbeb3c3197e2ab83eac"
    package static let historicalSchema2CompatibilityKey =
        "E256/v2/gen0/\(historicalSchema2ProfileSHA256)/fixture-v2"

    package static let historicalSchema3ProfileSHA256 = "2a9f54c70a1619805a911758158f1e2204b0fd96c35102a9db5f4575aeb40cb0"
    package static let historicalSchema3CompatibilityKey =
        "E256/v2/gen0/\(historicalSchema3ProfileSHA256)/fixture-v3"

    package static let v2Gen0ProfileSHA256 = "fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4"

    package let family: String
    package let suiteVersion: Int
    package let id: Int
    package let fixtureSchemaVersion: Int
    package let lfsrTransition: String
    package let updateOrder: String
    package let centerConstruction: String
    package let centerMaskKeyKDF: String
    package let centerMaskPRF: String
    package let centerMaskKeyDomain: String
    package let centerMaskBlockDomain: String
    package let centerMaskCounter: String
    package let centerMaskExtraction: String
    package let centerMapOrder: String
    package let formula: Enigma256NLFFFormula
    package let components: [Enigma256NLFFComponent]
    package let folds: [Enigma256NLFFFold]
    package let researchStatus: String
    package let receipt: String
    package let receiptSHA256: String
    package let declaredProfileSHA256: String

    /// Temporary selector for CLI/research compatibility. Live contexts will
    /// capture a value explicitly before this global is removed in host hardening.
    nonisolated(unsafe) package static var current = Enigma256Generation.v2Gen0

    package static let v2Gen0 = Enigma256Generation(
        family: "E256",
        suiteVersion: 2,
        id: 0,
        fixtureSchemaVersion: supportedFixtureSchemaVersion,
        lfsrTransition: transitionIdentifier,
        updateOrder: updateOrderIdentifier,
        centerConstruction: centerConstructionIdentifier,
        centerMaskKeyKDF: centerMaskKeyKDFIdentifier,
        centerMaskPRF: centerMaskPRFIdentifier,
        centerMaskKeyDomain: centerMaskKeyDomainIdentifier,
        centerMaskBlockDomain: centerMaskBlockDomainIdentifier,
        centerMaskCounter: centerMaskCounterIdentifier,
        centerMaskExtraction: centerMaskExtractionIdentifier,
        centerMapOrder: centerMapOrderIdentifier,
        formula: .nativeReversible16,
        components: [
            Enigma256NLFFComponent(truthHex: "a39d51afd62adcd05b55a9672ee22418"),
            Enigma256NLFFComponent(truthHex: "28934ec6d3776da07da0c6a47da6136c"),
            Enigma256NLFFComponent(truthHex: "5d6022ec0beb78760ed16430b978fe9a"),
            Enigma256NLFFComponent(truthHex: "61ba65b5723f93c0abde9a6ad30f2300"),
            Enigma256NLFFComponent(truthHex: "6e83562d6ef4ded2878ca9347804de34"),
            Enigma256NLFFComponent(truthHex: "a84c3b648fc11ce9fd4c4cb9dac16b34"),
            Enigma256NLFFComponent(truthHex: "4674f9a094fadda75957f09a2523906a"),
            Enigma256NLFFComponent(truthHex: "355c4728f7ca7c6a284e79e6de408a6a")
        ],
        folds: [
            Enigma256NLFFFold(
                taps: [9, 43, 15, 16, 21, 39, 48, 5, 38, 28, 41, 51, 31, 30, 63, 52],
                leftComponent: 0,
                rightComponent: 1
            ),
            Enigma256NLFFFold(
                taps: [42, 13, 53, 32, 1, 11, 36, 50, 0, 45, 19, 22, 6, 23, 12, 29],
                leftComponent: 2,
                rightComponent: 3
            ),
            Enigma256NLFFFold(
                taps: [61, 40, 47, 20, 18, 44, 34, 59, 27, 8, 25, 55, 33, 2, 17, 4],
                leftComponent: 4,
                rightComponent: 5
            ),
            Enigma256NLFFFold(
                taps: [10, 26, 60, 57, 62, 35, 54, 58, 46, 14, 7, 49, 24, 37, 56, 3],
                leftComponent: 6,
                rightComponent: 7
            )
        ],
        researchStatus: "accepted_bounded_profile",
        receipt: "logs/e256-v2-gen0-nlff-search.json",
        receiptSHA256: "5c5bc931a145048037ec420b2c0c47ff310570e963bd45b8262f18a1640f0027",
        declaredProfileSHA256: v2Gen0ProfileSHA256
    )

    package init(
        family: String,
        suiteVersion: Int,
        id: Int,
        fixtureSchemaVersion: Int,
        lfsrTransition: String,
        updateOrder: String,
        centerConstruction: String,
        centerMaskKeyKDF: String,
        centerMaskPRF: String,
        centerMaskKeyDomain: String,
        centerMaskBlockDomain: String,
        centerMaskCounter: String,
        centerMaskExtraction: String,
        centerMapOrder: String,
        formula: Enigma256NLFFFormula,
        components: [Enigma256NLFFComponent],
        folds: [Enigma256NLFFFold],
        researchStatus: String,
        receipt: String,
        receiptSHA256: String,
        declaredProfileSHA256: String
    ) {
        self.family = family
        self.suiteVersion = suiteVersion
        self.id = id
        self.fixtureSchemaVersion = fixtureSchemaVersion
        self.lfsrTransition = lfsrTransition
        self.updateOrder = updateOrder
        self.centerConstruction = centerConstruction
        self.centerMaskKeyKDF = centerMaskKeyKDF
        self.centerMaskPRF = centerMaskPRF
        self.centerMaskKeyDomain = centerMaskKeyDomain
        self.centerMaskBlockDomain = centerMaskBlockDomain
        self.centerMaskCounter = centerMaskCounter
        self.centerMaskExtraction = centerMaskExtraction
        self.centerMapOrder = centerMapOrder
        self.formula = formula
        self.components = components
        self.folds = folds
        self.researchStatus = researchStatus
        self.receipt = receipt
        self.receiptSHA256 = receiptSHA256
        self.declaredProfileSHA256 = declaredProfileSHA256
        precondition((try? validate()) != nil, "invalid E256 generation profile")
    }

    package func validate() throws {
        guard family == "E256" else { throw Enigma256GenerationError.wrongFamily(family) }
        guard suiteVersion == 2 else { throw Enigma256GenerationError.unsupportedSuite(suiteVersion) }
        guard id == 0 else { throw Enigma256GenerationError.invalidGeneration(id) }
        guard fixtureSchemaVersion == Self.supportedFixtureSchemaVersion else {
            throw Enigma256GenerationError.unsupportedFixtureSchema(fixtureSchemaVersion)
        }
        guard lfsrTransition == Self.transitionIdentifier else {
            throw Enigma256GenerationError.unsupportedTransition(lfsrTransition)
        }
        guard updateOrder == Self.updateOrderIdentifier else {
            throw Enigma256GenerationError.unsupportedUpdateOrder(updateOrder)
        }
        guard centerConstruction == Self.centerConstructionIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterConstruction(centerConstruction)
        }
        guard centerMaskKeyKDF == Self.centerMaskKeyKDFIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterMaskKeyKDF(centerMaskKeyKDF)
        }
        guard centerMaskPRF == Self.centerMaskPRFIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterMaskPRF(centerMaskPRF)
        }
        guard centerMaskKeyDomain == Self.centerMaskKeyDomainIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterMaskKeyDomain(centerMaskKeyDomain)
        }
        guard centerMaskBlockDomain == Self.centerMaskBlockDomainIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterMaskBlockDomain(centerMaskBlockDomain)
        }
        guard centerMaskCounter == Self.centerMaskCounterIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterMaskCounter(centerMaskCounter)
        }
        guard centerMaskExtraction == Self.centerMaskExtractionIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterMaskExtraction(centerMaskExtraction)
        }
        guard centerMapOrder == Self.centerMapOrderIdentifier else {
            throw Enigma256GenerationError.unsupportedCenterMapOrder(centerMapOrder)
        }
        guard formula == .nativeReversible16 else { throw Enigma256GenerationError.unsupportedFormula }
        guard components.count == 8 else {
            throw Enigma256GenerationError.invalidComponentCount(components.count)
        }
        for (index, component) in components.enumerated() where component.ones != 64 {
            throw Enigma256GenerationError.unbalancedComponent(index)
        }
        guard folds.count == 4 else { throw Enigma256GenerationError.invalidFoldCount(folds.count) }
        for (index, fold) in folds.enumerated() {
            guard fold.taps.count == 16,
                  Set(fold.taps).count == 16,
                  fold.taps.allSatisfy({ (0 ..< 64).contains($0) }),
                  (0 ..< components.count).contains(fold.leftComponent),
                  (0 ..< components.count).contains(fold.rightComponent) else {
                throw Enigma256GenerationError.invalidFold(index)
            }
        }
        let allTaps = folds.flatMap(\.taps)
        guard allTaps.sorted() == Array(0 ..< 64) else {
            throw Enigma256GenerationError.stateTapPartition
        }
        let assignments = folds.flatMap { [$0.leftComponent, $0.rightComponent] }
        guard assignments == Array(0 ..< 8) else {
            throw Enigma256GenerationError.componentAssignment
        }
        guard researchStatus == "accepted_bounded_profile" else {
            throw Enigma256GenerationError.invalidResearchStatus(researchStatus)
        }
        guard !receipt.isEmpty,
              receiptSHA256.count == 64,
              receiptSHA256 == receiptSHA256.lowercased(),
              receiptSHA256.allSatisfy(\.isHexDigit) else {
            throw Enigma256GenerationError.invalidReceipt
        }
        let actualHash = profileHashHex
        guard declaredProfileSHA256 == actualHash else {
            throw Enigma256GenerationError.profileHashMismatch(
                expected: declaredProfileSHA256,
                actual: actualHash
            )
        }
    }

    package func stepMask(state: UInt64) -> (Bool, Bool, Bool, Bool) {
        precondition(folds.count == 4)
        return (
            folds[0].evaluate(state, components: components),
            folds[1].evaluate(state, components: components),
            folds[2].evaluate(state, components: components),
            folds[3].evaluate(state, components: components)
        )
    }

    package var canonicalProfile: Data {
        let componentText = components.map(\.truthHex).joined(separator: ",")
        let foldText = folds.map { fold in
            "\(fold.taps.map(String.init).joined(separator: ".")):\(fold.leftComponent):\(fold.rightComponent)"
        }.joined(separator: ",")
        return Data(
            "\(family)|\(suiteVersion)|\(id)|\(fixtureSchemaVersion)|\(lfsrTransition)|\(updateOrder)|\(centerConstruction)|\(centerMaskKeyKDF)|\(centerMaskPRF)|\(centerMaskKeyDomain)|\(centerMaskBlockDomain)|\(centerMaskCounter)|\(centerMaskExtraction)|\(centerMapOrder)|\(formula.rawValue)|\(componentText)|\(foldText)".utf8
        )
    }

    package var profileHashHex: String {
        SHA256.hash(data: canonicalProfile).map { String(format: "%02x", $0) }.joined()
    }

    package var compatibilityKey: String {
        "\(family)/v\(suiteVersion)/gen\(id)/\(profileHashHex)/fixture-v\(fixtureSchemaVersion)"
    }

    package var dayInfo: Data {
        Data("\(family)/v\(suiteVersion)/gen\(id)/day/\(profileHashHex)".utf8)
    }

    package var messageInfo: Data {
        Data("\(family)/v\(suiteVersion)/gen\(id)/message/\(profileHashHex)".utf8)
    }

    package var centerMaskKeyInfo: Data {
        Data("\(family)/v\(suiteVersion)/gen\(id)/\(centerMaskKeyDomain)/\(profileHashHex)".utf8)
    }

    package var centerMaskBlockInfo: Data {
        Data("\(family)/v\(suiteVersion)/gen\(id)/\(centerMaskBlockDomain)/\(profileHashHex)".utf8)
    }

    package static func load(from url: URL) throws -> Enigma256Generation {
        let generation = try JSONDecoder().decode(Enigma256Generation.self, from: Data(contentsOf: url))
        try generation.validate()
        return generation
    }

    package func save(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }

    package func activate() {
        Enigma256Generation.current = self
    }

    @discardableResult
    package static func bootstrapFromFixture(
        path: String = "Fixtures/enigma256_generation.json"
    ) -> Enigma256Generation {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else { return current }
        do {
            let generation = try load(from: url)
            generation.activate()
            return generation
        } catch {
            preconditionFailure("invalid E256 generation fixture at \(path): \(error)")
        }
    }

    package func emitNLFFComboVerilog() -> String {
        precondition(
            family == "E256" && suiteVersion == 2 && id == 0
                && profileHashHex == Self.v2Gen0ProfileSHA256,
            "no generated RTL exists for this E256 profile"
        )
        return """
        `timescale 1ns / 1ps

        // E256-v2/gen\(id) native reversible NLFF research profile.
        // profile_sha256=\(profileHashHex)
        module enigma_256_nlff_combo (
            input  wire [63:0] lfsr,
            output wire        step_r1,
            output wire        step_r2,
            output wire        step_r3,
            output wire        step_r4
        );
        `include "Generated/Profiles/Enigma256/enigma_256_nlff_v2.vh"
        assign step_r1 = e256_nlff_step_r1;
        assign step_r2 = e256_nlff_step_r2;
        assign step_r3 = e256_nlff_step_r3;
        assign step_r4 = e256_nlff_step_r4;
        endmodule

        """
    }

    private enum CodingKeys: String, CodingKey {
        case family
        case suiteVersion = "suite_version"
        case id = "generation"
        case fixtureSchemaVersion = "fixture_schema_version"
        case lfsrTransition = "lfsr_transition"
        case updateOrder = "update_order"
        case centerConstruction = "center_construction"
        case centerMaskKeyKDF = "center_mask_key_kdf"
        case centerMaskPRF = "center_mask_prf"
        case centerMaskKeyDomain = "center_mask_key_domain"
        case centerMaskBlockDomain = "center_mask_block_domain"
        case centerMaskCounter = "center_mask_counter"
        case centerMaskExtraction = "center_mask_extraction"
        case centerMapOrder = "center_map_order"
        case formula
        case components
        case folds
        case researchStatus = "research_status"
        case receipt
        case receiptSHA256 = "receipt_sha256"
        case declaredProfileSHA256 = "profile_sha256"
    }
}

// MARK: - NLFF step-enable statistics (bounded diagnostics, not a security grade)

package struct Enigma256NLFFStepStats: Sendable {
    package var steps: Int
    package var rates: [Double]
    package var phi: [[Double]]
    package var meanRate: Double
    package var maxAbsOffDiagPhi: Double
    package var allFourOnRate: Double

    package var meanRateOK: Bool { abs(meanRate - 0.5) < 0.02 }
    package var independenceOK: Bool { maxAbsOffDiagPhi < 0.04 }
    package var rateFloorOK: Bool { rates.allSatisfy { $0 > 0.45 && $0 < 0.55 } }
}

extension Enigma256Generation {
    package func stepEnableStats(
        steps: Int = 200_000,
        seed: UInt64 = 0xC0FF_EE12_3456_789A
    ) -> Enigma256NLFFStepStats {
        precondition(steps > 0)
        var lfsr = Enigma256LFSR(seed: seed == 0 ? 1 : seed)
        var counts = [0, 0, 0, 0]
        var pair = Array(repeating: Array(repeating: 0, count: 4), count: 4)
        var allOn = 0
        for _ in 0 ..< steps {
            let mask = stepMask(state: lfsr.state)
            let bits = [mask.0, mask.1, mask.2, mask.3]
            for i in 0 ..< 4 {
                if bits[i] { counts[i] += 1 }
                for j in 0 ..< 4 where bits[i] && bits[j] { pair[i][j] += 1 }
            }
            if bits.allSatisfy({ $0 }) { allOn += 1 }
            lfsr.clock()
        }
        let count = Double(steps)
        let rates = counts.map { Double($0) / count }
        var phi = Array(repeating: Array(repeating: 0.0, count: 4), count: 4)
        var maximum = 0.0
        for i in 0 ..< 4 {
            for j in 0 ..< 4 {
                let joint = Double(pair[i][j]) / count
                let denominator = (
                    rates[i] * (1 - rates[i]) * rates[j] * (1 - rates[j])
                ).squareRoot()
                let value = denominator > 1e-12 ? (joint - rates[i] * rates[j]) / denominator : 0
                phi[i][j] = value
                if i != j { maximum = max(maximum, abs(value)) }
            }
        }
        return Enigma256NLFFStepStats(
            steps: steps,
            rates: rates,
            phi: phi,
            meanRate: rates.reduce(0, +) / 4,
            maxAbsOffDiagPhi: maximum,
            allFourOnRate: Double(allOn) / count
        )
    }
}
