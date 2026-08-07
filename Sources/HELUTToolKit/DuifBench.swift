import Foundation
import Metal
import HELUTCore
import HELUTCLI

/// Same quoted grid as one of Duif's units: 456,976 window positions at one
/// ring setting. His published units/s also walk the 26 middle rings inside
/// that unit. This bench pins the middle ring at A, which is the catalog run.
func runDuifComparisonBench() {
    let ciphertext = EnigmaAlphabet.normalize(
        "JCRSAJTGSJEYEXYKKZZSHVUOCTRFRCRPFVYPLKPPLGRHVVBBTBRSXSWXGGTYTVKQNGSCHVGF"
    )
    let measured = max(1, intFlag("--bombe-bench-shells") ?? 1_500)
    let warmup = 48
    let full = CommandLine.arguments.contains("--bombe-bench-full")
    guard let engine = WelchmanMetalEngine(depth: WelchmanMetalEngine.defaultDepth) else {
        print("no Metal device")
        return
    }
    let device = MTLCreateSystemDefaultDevice()?.name ?? "Metal"
    print("=== Duif comparison bench ===")
    print("device: \(device)")
    print("one shell = 456,976 window positions, one ring setting, middle ring A")
    print("Duif V5 on an RTX 5070, same quoted shell, middle ring walked inside it:")
    print("  26-letter crib 588 units/s    18-letter crib 3,124 units/s")
    print("sample: \(measured) shells after \(warmup) warmup")
    print()

    let menus = duifBenchMenus(ciphertext: ciphertext)
    guard !menus.isEmpty else {
        print("no bench menu could be built")
        return
    }

    let variants: [(String, Bool, Bool, Bool)] = [
        ("board only", false, false, false),
        ("loop test", true, false, false),
        ("loop + 4-wide", true, false, true),
        ("loop + step table", true, true, false),
        ("loop + step table + 4-wide", true, true, true)
    ]

    for menu in menus {
        print(menu.description)
        let sample = duifShells(menu: menu, limit: measured)
        let batch = Array(sample.prefix(warmup)) + sample
        for (name, loop, step, wide) in variants {
            engine.loopTest = loop
            engine.adoptStepTable = step
            engine.wideLoopTest = wide
            let result = duifTime(engine: engine, shells: batch, warmup: warmup)
            let shellsPerSecond = result.seconds > 0
                ? Double(result.shells) / result.seconds : 0
            let settings = shellsPerSecond * Double(WelchmanMetalEngine.laneCount) / 1e6
            print(String(
                format: "  %-28@ %5d shells %7.2fs %7.1f shells/s %6.1f M/s  first-shell lanes %d",
                name as NSString, result.shells, result.seconds,
                shellsPerSecond, settings, result.nonzero as Int
            ))
            fflush(stdout)
        }
        print()
    }

    guard full else { return }
    let cribShells = 336 * 4 * 26
    engine.loopTest = true
    engine.adoptStepTable = false
    engine.wideLoopTest = true
    for menu in menus {
        print("full right-ring crib, loop test with four seeds at once")
        print(menu.description)
        print("shells: \(cribShells) (336 orders × 2 Greek × 2 reflectors × 26 right rings)")
        let all = duifShells(menu: menu, limit: cribShells)
        let batch = Array(all.prefix(warmup)) + all
        let result = duifTime(engine: engine, shells: batch, warmup: warmup)
        let shellsPerSecond = result.seconds > 0
            ? Double(result.shells) / result.seconds : 0
        print(String(
            format: "  %.1fs   %.1f shells/s   %.1f M/s",
            result.seconds, shellsPerSecond,
            shellsPerSecond * Double(WelchmanMetalEngine.laneCount) / 1e6
        ))
        print()
        fflush(stdout)
    }
}

private func duifBenchMenus(ciphertext: [Int]) -> [BombeMenu] {
    var menus: [BombeMenu] = []
    // His 26-letter bench crib, with the '?' dropped. That letter is not an edge.
    if let split = try? BombeMenuBuilder.constellation(
        anchors: [("KOMX", 0), ("DMXUUUBOOTEYFDUUUAUSB", 5)],
        ciphertext: ciphertext
    ) {
        menus.append(split)
    }
    // His 18-letter bench crib at offset 49. The last letter is a crash (S→S)
    // on both ciphertexts, and his menu builder keeps the edge. So does this one.
    let crib = "VVVUUUZWODREISECHS"
    let letters = EnigmaAlphabet.normalize(crib)
    let offset = 49
    var steps: [Int] = []
    var ends: [(Int, Int)] = []
    for index in letters.indices {
        steps.append(offset + index)
        ends.append((letters[index], ciphertext[offset + index]))
    }
    if let crash = BombeMenuBuilder.assemble(
        crib: crib, offset: offset, steps: steps, ends: ends
    ) {
        menus.append(crash)
    }
    return menus
}

private func duifShells(menu: BombeMenu, limit: Int) -> [WelchmanShell] {
    let orders = M4ThetisAttack.allWheelOrders()
    let greeks: [(String, EnigmaRotorSpec)] = [
        ("beta", EnigmaM4Warehouse.beta), ("gamma", EnigmaM4Warehouse.gamma)
    ]
    let reflectors: [(String, [Int])] = [
        ("B", EnigmaM4Warehouse.thinB), ("C", EnigmaM4Warehouse.thinC)
    ]
    var shells: [WelchmanShell] = []
    shells.reserveCapacity(limit)
    for (ukwName, reflector) in reflectors {
        for (greekName, greek) in greeks {
            for right in 0..<26 {
                for order in orders {
                    if shells.count >= limit { return shells }
                    shells.append(WelchmanShell(
                        menu: menu,
                        greek: greek, left: order.0, middle: order.1, right: order.2,
                        reflector: reflector, rings: (0, 0, 0, right),
                        ukwName: ukwName, greekName: greekName,
                        wheelOrder: "\(order.0.name)-\(order.1.name)-\(order.2.name)"
                    ))
                }
            }
        }
    }
    return shells
}

private func duifTime(
    engine: WelchmanMetalEngine,
    shells: [WelchmanShell],
    warmup: Int
) -> (shells: Int, seconds: Double, nonzero: Int) {
    var inFlight: [WelchmanInFlight] = []
    var nonzero = 0
    var counted = 0

    func drain(tally: Bool) {
        guard !inFlight.isEmpty else { return }
        let flight = inFlight.removeFirst()
        let survivors = engine.wait(flight)
        if tally {
            // One shell is enough to show the menu is not vacuous. Scanning every
            // lane of every shell would time the readback, not the GPU.
            if counted == 0 {
                for lane in 0..<WelchmanMetalEngine.laneCount where survivors[lane] != 0 {
                    nonzero += 1
                }
            }
            counted += 1
        }
        engine.release(flight)
    }

    let warm = min(warmup, shells.count)
    for shell in shells.prefix(warm) {
        while inFlight.count >= engine.depth { drain(tally: false) }
        if let flight = engine.enqueue(shell: shell) { inFlight.append(flight) }
    }
    while !inFlight.isEmpty { drain(tally: false) }

    let started = Date()
    for shell in shells.dropFirst(warm) {
        while inFlight.count >= engine.depth { drain(tally: true) }
        if let flight = engine.enqueue(shell: shell) { inFlight.append(flight) }
    }
    while !inFlight.isEmpty { drain(tally: true) }
    return (counted, Date().timeIntervalSince(started), nonzero)
}
