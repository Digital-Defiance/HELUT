import Foundation

/// Diagnostics are opt-in because retaining one record per LUT is intentionally
/// more expensive than the normal encrypted-netlist path.
package enum EncryptedNetlistDiagnosticsMode: Sendable, Equatable {
    case off
    case firstDivergence
}

/// Whether a noisy bootstrap key may execute when its measured, circuit-scoped
/// Gaussian confidence bound does not clear the requested failure bar.
package enum NoisyBKExecutionPolicy: Sendable, Equatable {
    /// Scientific/default mode: refuse execution unless the 95% circuit union
    /// bound clears. A sampled maximum is never accepted as a hard bound.
    case requireCircuitConfidence
    /// Explicit experiment mode: execute to collect diagnostics, but callers
    /// must not report the result as a certified PASS.
    case diagnosticOnly
}

package struct EncryptedLUTDiagnostic: Equatable {
    package var wavefront: Int
    package var ordinal: Int
    package var name: String
    package var yWire: Int
    package var aBits: [String]
    package var arity: Int
    /// Yosys spelling: highest address first.
    package var initMSBFirst: String
    /// Direct address order: entry zero first.
    package var tableLSBFirst: String
    package var clearAddress: Int?
    /// Address obtained by decoding each encrypted input independently.
    package var encryptedAddress: Int
    /// Nearest truth-table center selected by the switched aggregate consumed by BR.
    package var packedAddress: Int
    package var clearExpectedBit: UInt8?
    /// Truth-table bit at `encryptedAddress`.
    package var localExpectedBit: UInt8
    /// Truth-table bit at `packedAddress`; this is the BR arithmetic oracle.
    package var packedExpectedBit: UInt8
    package var actualBit: UInt8
    package var inputPhaseDomain: String
    package var packedNativePhase: UInt32
    package var expectedPackedPhase: UInt32
    package var packedOffset: Int
    package var rawPhase: UInt32
    package var phaseDomain: String
    package var signedResidual: Int64
    package var residualMagnitude: UInt32
    package var halfGap: UInt32
    package var skippedBlindRotate: Bool

    package var divergesFromClear: Bool {
        guard let clearExpectedBit else { return false }
        return actualBit != clearExpectedBit
    }

    /// Individually decoded inputs and the aggregate-selected LUT cell disagree.
    package var hasAddressAlias: Bool { packedAddress != encryptedAddress }

    /// The PBS result disagrees with the cell actually selected by its aggregate phase.
    package var locallyCorrupt: Bool { actualBit != packedExpectedBit }
}

package struct EncryptedDFFDiagnostic: Equatable {
    package var name: String
    package var type: String
    package var qWire: Int
    package var dBit: String
    package var expectedBit: UInt8
    package var actualBit: UInt8
    package var rawPhase: UInt32
    package var phaseDomain: String
    package var normalizedTorusPhase: UInt32
    package var signedResidual: Int64
    package var residualMagnitude: UInt32
    package var halfGap: UInt32
    package var producerName: String?
    package var producerWavefront: Int?
    package var producerArity: Int?
    package var producerINIT: String?
}

package struct EncryptedTickDiagnostics: Equatable {
    package var backend: String
    package var wireRefresh: String
    package var serialWavefront: Bool
    package var lutRecords: [EncryptedLUTDiagnostic]
    package var wrongDFFs: [EncryptedDFFDiagnostic]

    /// Earliest clear/encrypted disagreement in stable (wavefront, ordinal) order.
    package var firstDivergentLUT: EncryptedLUTDiagnostic? {
        lutRecords.first(where: \.divergesFromClear)
    }

    /// Earliest decoded-input versus aggregate-address disagreement.
    package var firstAddressAlias: EncryptedLUTDiagnostic? {
        lutRecords.first(where: \.hasAddressAlias)
    }

    /// Earliest LUT whose output disagrees with the aggregate-selected truth-table cell.
    package var firstLocallyCorruptLUT: EncryptedLUTDiagnostic? {
        lutRecords.first(where: \.locallyCorrupt)
    }

    package var hasFailure: Bool {
        firstDivergentLUT != nil
            || firstAddressAlias != nil
            || firstLocallyCorruptLUT != nil
            || !wrongDFFs.isEmpty
    }

    package func report(pathLabel: String? = nil, tick: Int? = nil) -> String {
        var lines = ["ENCRYPTED DIVERGENCE TRACE"]
        var scope = "  backend=\(backend) refresh=\(wireRefresh) serial-wavefront=\(serialWavefront)"
        if let pathLabel { scope += " path=\(pathLabel)" }
        if let tick { scope += " tick=\(tick)" }
        lines.append(scope)

        func appendLUT(_ label: String, _ lut: EncryptedLUTDiagnostic) {
            lines.append("  \(label): wavefront=\(lut.wavefront) ordinal=\(lut.ordinal) name=\(lut.name) y=\(lut.yWire)")
            lines.append("    A=[\(lut.aBits.joined(separator: ", "))] arity=\(lut.arity) INIT=\(lut.initMSBFirst) table[0...]=\(lut.tableLSBFirst)")
            let clearAddress = lut.clearAddress.map(String.init) ?? "unavailable"
            let clearExpected = lut.clearExpectedBit.map(String.init) ?? "unavailable"
            lines.append("    address clear=\(clearAddress) logical=\(lut.encryptedAddress) packed=\(lut.packedAddress) expected-clear=\(clearExpected) expected-logical=\(lut.localExpectedBit) expected-packed=\(lut.packedExpectedBit) actual=\(lut.actualBit)")
            lines.append("    packed \(lut.inputPhaseDomain) native=\(lut.packedNativePhase) expected=\(lut.expectedPackedPhase) offset=\(lut.packedOffset)")
            lines.append(String(format: "    phase %@ raw=%u (0x%08x) residual=%lld |e|=%u half-gap=%u BR-skip=%@", lut.phaseDomain, lut.rawPhase, lut.rawPhase, lut.signedResidual, lut.residualMagnitude, lut.halfGap, lut.skippedBlindRotate ? "yes" : "no"))
        }

        if let firstDivergentLUT {
            appendLUT("first clear divergence", firstDivergentLUT)
        } else {
            lines.append("  first clear divergence: none")
        }
        if let firstAddressAlias {
            appendLUT("first packed-address alias", firstAddressAlias)
        } else {
            lines.append("  first packed-address alias: none")
        }
        if let firstLocallyCorruptLUT {
            appendLUT("first locally corrupt LUT", firstLocallyCorruptLUT)
        } else {
            lines.append("  first locally corrupt LUT: none")
        }

        if wrongDFFs.isEmpty {
            lines.append("  wrong DFFs: none")
        } else {
            lines.append("  wrong DFFs: \(wrongDFFs.count)")
            for dff in wrongDFFs {
                var producer = dff.producerName ?? "non-LUT/unknown"
                if let wavefront = dff.producerWavefront { producer += "@wavefront\(wavefront)" }
                if let arity = dff.producerArity { producer += "/LUT\(arity)" }
                if let initBits = dff.producerINIT { producer += "/INIT=\(initBits)" }
                lines.append("    \(dff.name) \(dff.type) Q=\(dff.qWire) D=\(dff.dBit) want=\(dff.expectedBit) got=\(dff.actualBit) producer=\(producer)")
                lines.append(String(format: "      phase %@ raw=%u torus=%u residual=%lld |e|=%u half-gap=%u", dff.phaseDomain, dff.rawPhase, dff.normalizedTorusPhase, dff.signedResidual, dff.residualMagnitude, dff.halfGap))
            }
        }
        return lines.joined(separator: "\n")
    }
}
