import Foundation
import HELUTCore

// MARK: - Shared CLI helpers (HELUTCLI)

/// P1030680 / M-Thetis tensor path: M4 netlist, B = 26³, in-graph linguistic score.
public let p1030680Bombe = CommandLine.arguments.contains("--p1030680-bombe")

/// Parse `--name N` from argv; nil if absent or not an int.
/// By default requires a positive value. Pass `allowZero: true` when 0 is meaningful
/// (e.g. `--bombe-menus 0` means "all placements").
public func intFlag(_ name: String, allowZero: Bool = false) -> Int? {
    guard let idx = CommandLine.arguments.firstIndex(of: name),
          idx + 1 < CommandLine.arguments.count,
          let value = Int(CommandLine.arguments[idx + 1]) else {
        return nil
    }
    if allowZero {
        return value >= 0 ? value : nil
    }
    return value > 0 ? value : nil
}

/// Parse `--name VALUE` from argv.
public func stringFlag(_ name: String) -> String? {
    guard let idx = CommandLine.arguments.firstIndex(of: name),
          idx + 1 < CommandLine.arguments.count else {
        return nil
    }
    let value = CommandLine.arguments[idx + 1]
    return value.hasPrefix("--") ? nil : value
}

/// Parse `--name X.Y` from argv (finite, non-negative).
public func doubleFlag(_ name: String) -> Double? {
    guard let raw = stringFlag(name), let value = Double(raw), value.isFinite, value >= 0 else {
        return nil
    }
    return value
}

/// Batch dimension. Override with `--batch N`.
/// Defaults: P1030680 → 17,576 (26³); demo bombe → 10,000.
/// On 64 GB unified memory, M4 @ N=1024 is comfortable near B≈30–35k; ≥40k is tight.
public let bombeBatch: Int = {
    if let batch = intFlag("--batch") {
        return batch
    }
    return p1030680Bombe ? 17_576 : 10_000
}()

public let positionalArgs: [String] = {
    let args = Array(CommandLine.arguments.dropFirst())
    var out: [String] = []
    var index = 0
    let valueFlags: Set<String> = [
        "--ticks", "--batch", "--rings", "--subspace", "--msg-keys", "--skip", "--from",
        "--degree", "--warmup", "--reset-hold", "--encoding", "--lut-backend",
        "--vectors", "--paths", "--trials", "--bk-noise",
        "--bk-noise-sigma", "--covering-base-log", "--boolean-scale-mul",
        "--encrypted-mem", "--metal-br-tile",
        "--hybrid-pop", "--hybrid-gens", "--hybrid-greek-samples",
        "--exhaust-top", "--exhaust-plugs", "--selftest-len",
        "--bombe-menus", "--bombe-plugs", "--bombe-report", "--bombe-pipeline",
        "--bombe-from", "--bombe-min-crib", "--bombe-fixture",
        "--bombe-confirm", "--bombe-partners", "--bombe-opening-len",
        "--enigma256-out", "--enigma256-plain",
        "--enigma256-in", "--enigma256-ikm", "--enigma256-salt", "--enigma256-nonce",
        "--enigma256-mode", "--enigma256-plain-file",
        "--enigma256-host", "--enigma256-port",
        "--enigma256-passphrase", "--enigma256-pbkdf2-iters",
        "--enigma256-netlist", "--enigma256-emit-out", "--enigma256-tensorlut-log",
        "--enigma256-tensorlut-gens", "--enigma256-tensorlut-pop", "--enigma256-tensorlut-polish",
        "--enigma256-tensorlut-lambda", "--enigma256-tensorlut-seed",
        "--enigma256-identity", "--enigma256-identity-out",
        "--enigma256-trust", "--enigma256-trust-file",
        "--enigma256-genes", "--enigma256-campaign-log", "--enigma256-campaign-trials",
        "--enigma256-nlff-stats-steps", "--enigma256-nlff-breed-trials",
        "--enigma256-ent-bytes", "--enigma256-ent-out", "--enigma256-ent-log",
        "--enigma256-ent-plain",
        "--enigma256-kpa-rounds",
        "--enigma256-bijection-states", "--enigma256-bijection-stream",
        "--enigma256-bijection-seed"
    ]
    while index < args.count {
        let arg = args[index]
        if valueFlags.contains(arg) {
            index += 2 // skip flag + value
            continue
        }
        if arg.hasPrefix("--") {
            index += 1
            continue
        }
        out.append(arg)
        index += 1
    }
    return out
}()


