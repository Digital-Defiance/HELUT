import Foundation
import HELUTCore

// MARK: - C ABI (`include/helut.h`)

private final class EngineBox {
    let engine: RadioEngine
    init(_ engine: RadioEngine) { self.engine = engine }
}

private func box(_ raw: OpaquePointer?) -> EngineBox? {
    guard let raw else { return nil }
    return Unmanaged<EngineBox>.fromOpaque(UnsafeRawPointer(raw)).takeUnretainedValue()
}

private func writeError(_ message: String, errbuf: UnsafeMutablePointer<CChar>?, errbufLen: Int) {
    guard let errbuf, errbufLen > 0 else { return }
    let bytes = Array(message.utf8.prefix(errbufLen - 1))
    for (i, b) in bytes.enumerated() {
        errbuf[i] = CChar(bitPattern: b)
    }
    errbuf[bytes.count] = 0
}

@_cdecl("helut_version")
public func helut_version() -> UnsafePointer<CChar>? {
    // Static lifetime — do not free.
    return UnsafePointer(strdup("HELUTRadio 0.1.0"))
}

@_cdecl("helut_open")
public func helut_open(
    _ netlistPath: UnsafePointer<CChar>?,
    _ mode: UnsafePointer<CChar>?,
    _ errbuf: UnsafeMutablePointer<CChar>?,
    _ errbufLen: Int
) -> OpaquePointer? {
    guard let netlistPath else {
        writeError("netlist_path is NULL", errbuf: errbuf, errbufLen: errbufLen)
        return nil
    }
    let path = String(cString: netlistPath)
    let modeRaw = mode.map { String(cString: $0) } ?? "clear"
    guard let modeKind = RadioEngine.Mode(rawValue: modeRaw) else {
        writeError("unknown mode '\(modeRaw)' (use clear|encrypted-demo)", errbuf: errbuf, errbufLen: errbufLen)
        return nil
    }
    do {
        let engine = try RadioEngine(netlistPath: path, mode: modeKind)
        let boxed = EngineBox(engine)
        return OpaquePointer(Unmanaged.passRetained(boxed).toOpaque())
    } catch {
        writeError(String(describing: error), errbuf: errbuf, errbufLen: errbufLen)
        return nil
    }
}

@_cdecl("helut_close")
public func helut_close(_ raw: OpaquePointer?) {
    guard let raw else { return }
    Unmanaged<EngineBox>.fromOpaque(UnsafeRawPointer(raw)).release()
}

@_cdecl("helut_mode")
public func helut_mode(_ raw: OpaquePointer?) -> UnsafePointer<CChar>? {
    guard let box = box(raw) else { return nil }
    return box.engine.mode.rawValue.withCString { strdup($0) }
        .map { UnsafePointer($0) }
}

@_cdecl("helut_module_name")
public func helut_module_name(_ raw: OpaquePointer?) -> UnsafePointer<CChar>? {
    guard let box = box(raw) else { return nil }
    return box.engine.moduleName.withCString { strdup($0) }
        .map { UnsafePointer($0) }
}

@_cdecl("helut_input_port_count")
public func helut_input_port_count(_ raw: OpaquePointer?) -> Int32 {
    Int32(box(raw)?.engine.inputPorts.count ?? -1)
}

@_cdecl("helut_output_port_count")
public func helut_output_port_count(_ raw: OpaquePointer?) -> Int32 {
    Int32(box(raw)?.engine.outputPorts.count ?? -1)
}

@_cdecl("helut_input_port_name")
public func helut_input_port_name(
    _ raw: OpaquePointer?,
    _ index: Int32,
    _ buf: UnsafeMutablePointer<CChar>?,
    _ buflen: Int
) -> Int32 {
    guard let engine = box(raw)?.engine, let buf, buflen > 0 else { return Int32(HELUT_ERR_ARGS) }
    guard index >= 0, index < engine.inputPorts.count else { return Int32(HELUT_ERR_ARGS) }
    writeError(engine.inputPorts[Int(index)].name, errbuf: buf, errbufLen: buflen)
    return Int32(HELUT_OK)
}

@_cdecl("helut_output_port_name")
public func helut_output_port_name(
    _ raw: OpaquePointer?,
    _ index: Int32,
    _ buf: UnsafeMutablePointer<CChar>?,
    _ buflen: Int
) -> Int32 {
    guard let engine = box(raw)?.engine, let buf, buflen > 0 else { return Int32(HELUT_ERR_ARGS) }
    guard index >= 0, index < engine.outputPorts.count else { return Int32(HELUT_ERR_ARGS) }
    writeError(engine.outputPorts[Int(index)].name, errbuf: buf, errbufLen: buflen)
    return Int32(HELUT_OK)
}

@_cdecl("helut_input_port_width")
public func helut_input_port_width(_ raw: OpaquePointer?, _ index: Int32) -> Int32 {
    guard let engine = box(raw)?.engine,
          index >= 0, index < engine.inputPorts.count else { return -1 }
    return Int32(engine.inputPorts[Int(index)].width)
}

@_cdecl("helut_output_port_width")
public func helut_output_port_width(_ raw: OpaquePointer?, _ index: Int32) -> Int32 {
    guard let engine = box(raw)?.engine,
          index >= 0, index < engine.outputPorts.count else { return -1 }
    return Int32(engine.outputPorts[Int(index)].width)
}

@_cdecl("helut_input_bit_count")
public func helut_input_bit_count(_ raw: OpaquePointer?) -> Int32 {
    Int32(box(raw)?.engine.inputBitCount ?? -1)
}

@_cdecl("helut_output_bit_count")
public func helut_output_bit_count(_ raw: OpaquePointer?) -> Int32 {
    Int32(box(raw)?.engine.outputBitCount ?? -1)
}

@_cdecl("helut_tick")
public func helut_tick(
    _ raw: OpaquePointer?,
    _ inBits: UnsafePointer<UInt8>?,
    _ inLen: Int,
    _ outBits: UnsafeMutablePointer<UInt8>?,
    _ outCap: Int,
    _ outLen: UnsafeMutablePointer<Int>?
) -> Int32 {
    guard let engine = box(raw)?.engine else { return Int32(HELUT_ERR_ARGS) }
    guard let inBits, let outBits, let outLen else { return Int32(HELUT_ERR_ARGS) }
    guard inLen == engine.inputBitCount else { return Int32(HELUT_ERR_BUFFER) }
    guard outCap >= engine.outputBitCount else { return Int32(HELUT_ERR_BUFFER) }
    let input = Array(UnsafeBufferPointer(start: inBits, count: inLen))
    do {
        let output = try engine.tick(inBits: input)
        for (i, bit) in output.enumerated() {
            outBits[i] = bit
        }
        outLen.pointee = output.count
        return Int32(HELUT_OK)
    } catch {
        return Int32(HELUT_ERR_TICK)
    }
}

@_cdecl("helut_regex_feed")
public func helut_regex_feed(
    _ raw: OpaquePointer?,
    _ byte: UInt8,
    _ match: UnsafeMutablePointer<UInt8>?
) -> Int32 {
    guard let engine = box(raw)?.engine, let match else { return Int32(HELUT_ERR_ARGS) }
    do {
        match.pointee = try engine.regexFeed(byte)
        return Int32(HELUT_OK)
    } catch {
        return Int32(HELUT_ERR_TICK)
    }
}

@_cdecl("helut_reset")
public func helut_reset(_ raw: OpaquePointer?) -> Int32 {
    guard let engine = box(raw)?.engine else { return Int32(HELUT_ERR_ARGS) }
    engine.reset()
    return Int32(HELUT_OK)
}

// Mirror helut.h constants for Swift call sites.
private let HELUT_OK: Int32 = 0
private let HELUT_ERR_ARGS: Int32 = -1
private let HELUT_ERR_BUFFER: Int32 = -6
private let HELUT_ERR_TICK: Int32 = -5
