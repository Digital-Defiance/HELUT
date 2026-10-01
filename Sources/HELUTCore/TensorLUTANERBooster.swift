import Darwin
import Foundation
import Metal

private enum ANERDylib {
    nonisolated(unsafe) static let handle: UnsafeMutableRawPointer? = {
        if let override = getenv("ANER_LIBRARY"), let opened = dlopen(override, RTLD_NOW) {
            return opened
        }
        let candidates = [
            "/Volumes/Code/ANER/lib/build/libaner.dylib",
            "/Volumes/Code/ANER/lib/build/libaner.0.dylib",
            "/usr/local/lib/libaner.dylib",
            "/usr/local/lib/libaner.0.dylib"
        ]
        for path in candidates {
            if let opened = dlopen(path, RTLD_NOW) {
                return opened
            }
        }
        return dlopen("libaner.dylib", RTLD_NOW)
    }()

    static func symbol<T>(_ name: String, as type: T.Type) -> T? {
        guard let handle, let raw = dlsym(handle, name) else { return nil }
        return unsafeBitCast(raw, to: type)
    }
}

private typealias ANERLUT6Compile = @convention(c) (
    Int32,
    UnsafePointer<Int32>?,
    UnsafePointer<Int32>?,
    UnsafePointer<Float>?,
    Int32,
    UnsafePointer<Int32>?,
    UnsafePointer<Int32>?,
    Int32
) -> UnsafeMutableRawPointer?

private typealias ANERLUT6Free = @convention(c) (UnsafeMutableRawPointer?) -> Void
private typealias ANERLUT6Uses = @convention(c) (UnsafeMutableRawPointer?) -> Int32
private typealias ANERLUT6Forward = @convention(c) (
    UnsafeMutableRawPointer?,
    UnsafeMutablePointer<Float>?,
    Int32,
    UnsafeMutablePointer<Double>?
) -> Int32

/// Combinational TensorLUT pass compiled onto the Neural Engine.
///
/// The netlist is frozen into one ANER graph. A later INIT edit, a wire count
/// above 512, more than `maxBoostLUTs` lookups, or a batch wider than
/// `maxBoostBatch` leaves the caller on the Metal pipeline. Flip-flops are
/// not part of the graph.
package final class TensorLUTANERBooster {
    /// One compiled spatial tile. On an M4 Max this was the steady-state band
    /// where the Neural Engine matched or beat one Metal dispatch. A wider
    /// batch is another launch per 64 columns, and Metal kept that dispatch.
    package static let maxBoostBatch = 64
    /// Above the largest measured netlist that won inside one tile (the regex
    /// circuit, 23 lookups). A 256-lookup chain was slower at batch 1.
    package static let maxBoostLUTs = 64

    package let wires: Int
    package let usesNeuralEngine: Bool
    private let program: UnsafeMutableRawPointer
    private let entries: [Float]
    private let forwardFn: ANERLUT6Forward
    private let freeFn: ANERLUT6Free

    package init?(netlist: TensorLUTNetlist) {
        let channels = (netlist.totalWires + 63) & ~63
        guard netlist.totalWires > 0, channels <= 512 else { return nil }
        guard netlist.luts.count <= Self.maxBoostLUTs else { return nil }
        guard let compile: ANERLUT6Compile = ANERDylib.symbol("aner_lut6_compile", as: ANERLUT6Compile.self),
              let freeFn: ANERLUT6Free = ANERDylib.symbol("aner_lut6_free", as: ANERLUT6Free.self),
              let uses: ANERLUT6Uses = ANERDylib.symbol("aner_lut6_uses_neural_engine", as: ANERLUT6Uses.self),
              let forwardFn: ANERLUT6Forward = ANERDylib.symbol("aner_lut6_forward", as: ANERLUT6Forward.self)
        else {
            return nil
        }

        var inputs = [Int32]()
        var outputs = [Int32]()
        var entries = [Float]()
        inputs.reserveCapacity(netlist.luts.count * 6)
        outputs.reserveCapacity(netlist.luts.count)
        entries.reserveCapacity(netlist.luts.count * 64)
        for lut in netlist.luts {
            inputs.append(contentsOf: [lut.in0, lut.in1, lut.in2, lut.in3, lut.in4, lut.in5])
            outputs.append(lut.outWire)
            entries.append(contentsOf: lut.entries)
        }

        var levelLuts = [Int32]()
        var levelCounts = [Int32]()
        levelCounts.reserveCapacity(netlist.executionLevels.count)
        for level in netlist.executionLevels {
            levelCounts.append(Int32(level.count))
            levelLuts.append(contentsOf: level)
        }

        let program = inputs.withUnsafeBufferPointer { inputPtr in
            outputs.withUnsafeBufferPointer { outputPtr in
                entries.withUnsafeBufferPointer { entryPtr in
                    levelLuts.withUnsafeBufferPointer { levelPtr in
                        levelCounts.withUnsafeBufferPointer { countPtr in
                            compile(
                                Int32(netlist.totalWires),
                                inputPtr.baseAddress,
                                outputPtr.baseAddress,
                                entryPtr.baseAddress,
                                Int32(netlist.luts.count),
                                levelPtr.baseAddress,
                                countPtr.baseAddress,
                                Int32(netlist.executionLevels.count)
                            )
                        }
                    }
                }
            }
        }
        guard let program, uses(program) != 0 else {
            if let program {
                freeFn(program)
            }
            return nil
        }

        self.program = program
        self.entries = entries
        self.wires = netlist.totalWires
        self.usesNeuralEngine = true
        self.forwardFn = forwardFn
        self.freeFn = freeFn
    }

    deinit {
        freeFn(program)
    }

    package func matches(_ inits: MTLBuffer) -> Bool {
        let bytes = entries.count * MemoryLayout<Float>.stride
        guard inits.length >= bytes else { return false }
        return entries.withUnsafeBytes { raw in
            memcmp(raw.baseAddress, inits.contents(), bytes) == 0
        }
    }

    @discardableResult
    package func forward(wires: UnsafeMutablePointer<Float>, batch: Int) -> Bool {
        guard batch > 0 else { return false }
        return forwardFn(program, wires, Int32(batch), nil) == 0
    }
}
