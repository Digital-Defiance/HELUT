import XCTest
@testable import HELUTCore

final class PicoRVHostMemTests: XCTestCase {
    func testTinyProgramCleartextIssuesStore() throws {
        guard let path = resolvePicoRVNetlist() else {
            throw XCTSkip("picorv32_netlist.json not found")
        }
        let netlist = loadYosysNetlist(from: path)
        guard let (moduleName, module) = netlist.modules.first else {
            return XCTFail("empty netlist")
        }
        let clear = CleartextNetlistSimulator(moduleName: moduleName, module: module)
        var host = PicoRVHostMem()
        var last: [String: [UInt8]]?
        let hold = 3
        let ticks = 48
        for tick in 1...ticks {
            let inputs = makePicoRVHostMemInputs(
                clear: clear,
                tick: tick,
                resetHold: hold,
                lastOutputs: last,
                kind: "prog",
                host: &host
            )
            let out = clear.tick(inputs: inputs)
            let valid = (out["mem_valid"] ?? [0]).first ?? 0
            let ready = (inputs["mem_ready"] ?? [0]).first ?? 0
            let addr = unpackHostLE(out["mem_addr"] ?? [])
            let instr = (out["mem_instr"] ?? [0]).first ?? 0
            let wstrb = unpackHostLE(out["mem_wstrb"] ?? [])
            let wdata = unpackHostLE(out["mem_wdata"] ?? [])
            if valid == 1 && ready == 1 {
                if instr == 1 { host.noteFetch(tick: tick, addr: addr) }
                else if wstrb == 0 {
                    host.noteLoad(tick: tick, addr: addr, rdata: unpackHostLE(inputs["mem_rdata"] ?? []))
                }
                if wstrb != 0 {
                    host.noteStore(tick: tick, addr: addr, wstrb: UInt8(wstrb & 0xf), wdata: wdata)
                }
            }
            host.afterTick(valid: valid, ready: ready, instr: instr, addr: addr)
            last = out
        }
        XCTAssertGreaterThanOrEqual(host.fetches.count, 2)
        XCTAssertGreaterThanOrEqual(Set(host.fetches.map(\.addr)).count, 2)
        XCTAssertFalse(host.stores.isEmpty, "expected a store bus cycle")
        XCTAssertEqual(host.stores.first?.wstrb, 15)
        XCTAssertTrue(
            host.stores.contains { $0.wdata == 1 },
            "addi x1,x0,1 must be visible on sw x1; stores=\(host.stores)"
        )
        XCTAssertTrue(
            host.loadXfers.contains { $0.rdata == 1 },
            "lw must see stored 1; xfers=\(host.loadXfers) loads=\(host.loads)"
        )
    }

    func testSDFFCEEnableGatesReset() {
        let ce = parseYosysDFFPolarity("$_SDFFCE_PN0P_")
        XCTAssertEqual(ce.enableActiveHigh, true)
        XCTAssertEqual(ce.syncReset?.activeHigh, false)
        XCTAssertEqual(ce.syncReset?.value, 0)
        XCTAssertTrue(ce.clockEnableGatesReset)
        let e = parseYosysDFFPolarity("$_SDFFE_PN0P_")
        XCTAssertFalse(e.clockEnableGatesReset)
        let p = parseYosysDFFPolarity("$_DFF_P_")
        XCTAssertFalse(p.clockEnableGatesReset)
        XCTAssertNil(p.enableActiveHigh)
    }
}

private func resolvePicoRVNetlist() -> String? {
    let name = "picorv32_netlist.json"
    let fm = FileManager.default
    let cwd = fm.currentDirectoryPath
    for relative in [name, "../\(name)", "../../\(name)"] {
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
