import Foundation
import Metal
import HELUTCore
import HELUTCLI

// MARK: - `--bombe-tolerance-prequal <fixture>`
//
// Phase 51.4 forbids switching the tolerant board on globally: survivor inflation is a
// property of the individual menu's loop structure, not of its crib length, and the menus
// that detonate are the ones already weak at tolerance 0. So each placement has to earn
// tolerance by measurement before any GPU-hours are committed to it.
//
// This measures, per menu, how many of 26^4 lanes survive at each tolerance on a sample of
// wrong shells — which is the right population, because a real arm spends almost all of its
// time on wrong shells and that is where the stop budget is actually consumed. It then
// projects the arm's total stop count and compares it against what the escalator has ever
// digested (86 candidates, Phase 50.7).
//
// This is a *cost* measurement on the target, not a search: no verdict, no key, no decrypt.

private struct PrequalRow {
    let menu: BombeMenu
    let survivorsPerTolerance: [Int]
    let seconds: [Double]
}

func runTolerancePrequal() {
    let fixture = stringFlag("--bombe-tolerance-prequal")
        ?? "Fixtures/p1030680_maxupper_strongest_menus.json"
    let maxTolerance = min(intFlag("--bombe-garble-tolerance") ?? 2, welchmanMaxTolerance)
    let menuLimit = intFlag("--bombe-menus").flatMap { $0 > 0 ? $0 : nil } ?? 24
    let shellSamples = intFlag("--prequal-shells") ?? 3
    let minCrib = intFlag("--bombe-min-crib") ?? 16
    // Shells per placement for the arm being priced. Default is the rings-AAAA / pinned pass
    // (336 WO x 2 Greek x 2 UKW), which is the only pass tolerance is affordable on at all.
    let armShells = intFlag("--prequal-arm-shells") ?? (336 * 4)

    guard let set = loadCribMenus(path: fixture) else {
        print("could not load fixture \(fixture)")
        return
    }
    guard let engine = WelchmanMetalEngine(depth: 1) else {
        print("no Metal device available")
        return
    }

    let chosen = set.menus.filter { $0.edgeCount >= minCrib }.prefix(menuLimit)
    print("=== Tolerance pre-qualification — \(fixture) ===")
    print("menus            : \(chosen.count) of \(set.menus.count) (crib ≥ \(minCrib))")
    print("tolerance ladder : 0…\(maxTolerance)")
    print("shell samples    : \(shellSamples) wrong shells per menu, rings AAAA")
    print("arm priced       : \(armShells) shells/placement")
    print()
    print("Inflation is placement dependent (Phase 51.4). A menu qualifies only if its")
    print("projected stop count stays inside what the escalator has actually digested —")
    print("86 candidates across four arms (Phase 50.7). This measures cost on the target;")
    print("it is not a search and produces no verdict.")
    print()

    // Wrong shells, spread through the wheel-order space. Tolerance inflation is a property
    // of the menu graph against a scrambler set, so any shell samples it; using wrong shells
    // is deliberate, since that is where an arm spends essentially all of its time.
    let allOrders = M4ThetisAttack.allWheelOrders()
    let stride = max(1, allOrders.count / max(1, shellSamples))
    let sampleOrders = (0..<shellSamples).compactMap { index -> (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec)? in
        let at = index * stride
        return at < allOrders.count ? allOrders[at] : nil
    }

    var rows: [PrequalRow] = []
    print("  # menu                                          "
        + "t=0        t=1        t=2   verdict")

    for (index, menu) in chosen.enumerated() {
        var survivors = [Int](repeating: 0, count: maxTolerance + 1)
        var seconds = [Double](repeating: 0, count: maxTolerance + 1)

        for tolerance in 0...maxTolerance {
            engine.sieve = WelchmanSieve(
                maxPlugs: 10, exactPlugs: 0,
                skipMiddleRingCovered: false, garbleTolerance: tolerance
            )
            var total = 0
            let began = Date()
            for order in sampleOrders {
                guard let buffer = engine.sweep(
                    menu: menu, greek: EnigmaM4Warehouse.gamma,
                    left: order.0, middle: order.1, right: order.2,
                    reflector: EnigmaM4Warehouse.thinB, rings: (0, 0, 0, 0)
                ) else { continue }
                for lane in 0..<buffer.count where buffer[lane] != 0 {
                    // An undecided lane is a lane the host must re-test, so for costing
                    // purposes it is a stop: it will be shipped back either way.
                    total += 1
                }
            }
            survivors[tolerance] = total / max(1, sampleOrders.count)
            seconds[tolerance] = Date().timeIntervalSince(began)
                / Double(max(1, sampleOrders.count))
        }

        // Qualify against the escalator's demonstrated capacity.
        let projected = Double(survivors[min(1, maxTolerance)]) * Double(armShells)
        let verdict: String
        if survivors.count > 1 && survivors[1] <= max(4 * survivors[0], survivors[0] + 2) {
            verdict = String(format: "QUALIFIES t=1 (proj %.3g stops)", projected)
        } else {
            verdict = String(format: "REJECT t=1 (proj %.3g stops)", projected)
        }

        let label = String(menu.description.prefix(46))
        var line = String(format: "%3d %-46@", index + 1, label as NSString)
        for tolerance in 0...maxTolerance {
            line += String(format: " %10d", survivors[tolerance])
        }
        print(line + "   " + verdict)
        fflush(stdout)

        rows.append(PrequalRow(menu: menu, survivorsPerTolerance: survivors, seconds: seconds))
    }

    print()
    let qualifying = rows.filter { row in
        row.survivorsPerTolerance.count > 1
            && row.survivorsPerTolerance[1]
                <= max(4 * row.survivorsPerTolerance[0], row.survivorsPerTolerance[0] + 2)
    }
    print("qualifying at tolerance 1: \(qualifying.count) of \(rows.count) menus")
    if !qualifying.isEmpty {
        let t0 = qualifying.map { $0.seconds[0] }.reduce(0, +)
        let t1 = qualifying.map { $0.seconds[1] }.reduce(0, +)
        let factor = t0 > 0 ? t1 / t0 : 0
        let armHours = t1 * Double(armShells) / 3600.0
        print(String(format: "measured tolerance-1 cost factor: %.1fx", factor))
        print(String(format: "projected arm: %.2f h for those %d menus at %d shells each",
                     armHours, qualifying.count, armShells))
        let stops = qualifying.map { $0.survivorsPerTolerance[1] }.reduce(0, +) * armShells
        print("projected raw stops for the arm: \(stops)")
        if stops > 100_000 {
            print("→ that is far beyond the 86 candidates the escalator has digested."
                + " Host drain, not the GPU, is the binding constraint.")
        }
    }
    if qualifying.count < rows.count {
        print("rejected menus are not a bug: 51.4 predicts that tolerance amplifies an"
            + " under-determined menu instead of rescuing it.")
    }
}
