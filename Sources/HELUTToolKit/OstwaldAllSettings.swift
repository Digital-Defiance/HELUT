import Foundation
import HELUTCore
import HELUTCLI

// MARK: - `--ostwald-all-settings` : climb every message key on a locked shell
//
// ExhaustiveCracker's Phase 1 is an IC sieve over 26⁴ starts, then a stecker climb of the
// survivors. The true P1030684 key ranks 223,118 / 456,976 on that sieve — noise. This
// runner drops the sieve: every position on one locked shell gets an Ostwald climb.
//
// One locked setting × 164M 4-plug starts is ~38 min on this machine and *greets*
// on true P1030684 (Phase 67). The wrong-setting ghost is crib BAD. A handful of
// locked P1030680 settings is eligible; 26⁴ is not. Empty cribs cannot clear the
// break bar (OstwaldBreakBar.minAttestedCrib).
//
// Requires an explicit shell (`--ostwald-shell` / `--ostwald-control p1030684` / first
// unique shell in `--ostwald-escalate`). Does not mint a crib.

package enum OstwaldAllSettings {
    package static let messageKeys = 26 * 26 * 26 * 26

    package static func positions(index: Int) -> (Int, Int, Int, Int) {
        let i = ((index % messageKeys) + messageKeys) % messageKeys
        return (i / 17_576, (i / 676) % 26, (i / 26) % 26, i % 26)
    }

    package static func index(_ positions: (Int, Int, Int, Int)) -> Int {
        positions.0 * 17_576 + positions.1 * 676 + positions.2 * 26 + positions.3
    }

    package static func letters(_ positions: (Int, Int, Int, Int)) -> String {
        String([positions.0, positions.1, positions.2, positions.3].map {
            EnigmaAlphabet.character($0)
        })
    }

    package struct Shell: Equatable {
        package let ukw: String
        package let greek: String
        package let wheelOrder: String
        package let rings: String
    }

    /// Operational-prior shell from the bounded Mulein stripe. A working search
    /// assignment, not a Thetis daily-key proof.
    package static let workingPriorShell = Shell(
        ukw: "B", greek: "beta", wheelOrder: "IV-III-VIII", rings: "AAAA"
    )

    package static func parseShell(_ text: String) -> Shell? {
        let parts = text.split(separator: "/").map(String.init)
        guard parts.count == 4 else { return nil }
        return Shell(ukw: parts[0], greek: parts[1], wheelOrder: parts[2], rings: parts[3])
    }

    package static func p1030684Control() -> (
        shell: Shell, ciphertext: String, crib: String, positions: String
    ) {
        let pt = EnigmaAlphabet.string(
            from: Array(EnigmaAlphabet.normalize(ControlMessageP1030684.plaintext).prefix(16))
        )
        let ct = EnigmaAlphabet.string(
            from: Array(EnigmaAlphabet.normalize(ControlMessageP1030684.ciphertext).prefix(72))
        )
        return (
            Shell(ukw: "B", greek: "gamma", wheelOrder: "IV-III-VIII", rings: "AACU"),
            ct, pt, ControlMessageP1030684.positions
        )
    }
}

func runOstwaldAllSettings() {
    let sliceFrom = intFlag("--ostwald-setting-from", allowZero: true) ?? 0
    let sliceCount = intFlag("--ostwald-setting-count") ?? OstwaldAllSettings.messageKeys
    let beamWidth = intFlag("--ostwald-beam") ?? 1
    let scorer = ClimbScorer(rawValue: stringFlag("--ostwald-scorer") ?? "staged") ?? .staged
    let brutePlugs = intFlag("--ostwald-brute-plugs", allowZero: true) ?? 0
    let bruteAll = CommandLine.arguments.contains("--ostwald-brute-all")
    let bruteSettingsOk = CommandLine.arguments.contains("--ostwald-brute-settings-ok")
    let useMetal = !CommandLine.arguments.contains("--ostwald-cpu")
    let budgetGB = intFlag("--ostwald-memory-gb") ?? OstwaldMemory.defaultBudgetGigabytes
    var exhaustLetters = intFlag("--ostwald-exhaust", allowZero: true) ?? 0
    if brutePlugs >= 4, bruteAll, intFlag("--ostwald-exhaust", allowZero: true) == nil {
        exhaustLetters = OstwaldExhaust.fourPlugAlphabetLetters
    }
    let exhaustDepth = intFlag("--ostwald-exhaust-depth") ?? 1
    let topUpTo = intFlag("--ostwald-top-up", allowZero: true) ?? 0

    var ciphertext = ""
    var crib = ""
    var target = "ostwald-all-settings"
    var shells: [OstwaldAllSettings.Shell] = []
    var cribOffset = 0

    if stringFlag("--ostwald-control")?.lowercased() == "p1030684" {
        let control = OstwaldAllSettings.p1030684Control()
        ciphertext = control.ciphertext
        crib = control.crib
        target = "P1030684-control"
        shells = [control.shell]
        let truePos = EnigmaM4Key.positions(fromLetters: control.positions)
        print("true P1030684 index: \(OstwaldAllSettings.index(truePos)) "
            + "(\(control.positions)); wrong-setting control is --ostwald-setting-from 0")
    } else if stringFlag("--ostwald-control")?.lowercased() == "p1030680" {
        ciphertext = U534MessageP1030680.ciphertext
        crib = ""
        target = "P1030680"
        shells = [OstwaldAllSettings.workingPriorShell]
        print("P1030680 probe — working-prior shell "
            + "\(OstwaldAllSettings.workingPriorShell.ukw)/"
            + "\(OstwaldAllSettings.workingPriorShell.greek)/"
            + "\(OstwaldAllSettings.workingPriorShell.wheelOrder)/"
            + "\(OstwaldAllSettings.workingPriorShell.rings) "
            + "unless --ostwald-shell overrides. Not a Thetis daily-key proof.")
        print("No crib loaded. Anchors shorter than \(OstwaldBreakBar.minAttestedCrib) "
            + "cannot clear the break bar (N5).")
        if intFlag("--ostwald-setting-count") == nil && !bruteSettingsOk {
            print("ABORT — P1030680 requires --ostwald-setting-count (a handful of locked "
                + "settings). Never default 26⁴.")
            return
        }
    }

    if let path = stringFlag("--ostwald-escalate"),
       let data = FileManager.default.contents(atPath: path),
       let manifest = try? JSONDecoder().decode(OstwaldEscalateManifest.self, from: data) {
        if ciphertext.isEmpty { ciphertext = manifest.ciphertext }
        target = manifest.target
        if crib.isEmpty, target != "P1030680", let first = manifest.candidates.first {
            crib = first.menuCrib
            cribOffset = first.menuOffset
        }
        var seen = Set<String>()
        for candidate in manifest.candidates {
            let key = "\(candidate.ukw)/\(candidate.greek)/\(candidate.wheelOrder)/\(candidate.rings)"
            if seen.insert(key).inserted {
                shells.append(
                    OstwaldAllSettings.Shell(
                        ukw: candidate.ukw, greek: candidate.greek,
                        wheelOrder: candidate.wheelOrder, rings: candidate.rings
                    )
                )
            }
        }
    }

    if let raw = stringFlag("--ostwald-shell"), let parsed = OstwaldAllSettings.parseShell(raw) {
        shells = [parsed]
    }

    let shellIndex = intFlag("--ostwald-shell-index", allowZero: true) ?? 0
    guard !shells.isEmpty, (0..<shells.count).contains(shellIndex) else {
        let trueIndex = OstwaldAllSettings.index(
            EnigmaM4Key.positions(fromLetters: ControlMessageP1030684.positions)
        )
        print("usage: --ostwald-all-settings --ostwald-control p1030684")
        print("   or: --ostwald-all-settings --ostwald-control p1030680 "
            + "--ostwald-setting-from 0 --ostwald-setting-count 1")
        print("   or: --ostwald-all-settings --ostwald-shell B/beta/IV-III-VIII/AAAA "
            + "--ostwald-escalate <quarantine.json>")
        print("drops the IC sieve; climbs locked message keys on one shell. "
            + "Not a crib. P1030680 never defaults to 26⁴.")
        print("4-plug alphabet greeting (one locked setting, ~3.1 h at the 10M floor):")
        print("  --ostwald-all-settings --ostwald-control p1030684 "
            + "--ostwald-setting-from \(trueIndex) --ostwald-setting-count 1 "
            + "--ostwald-brute-plugs 4 --ostwald-brute-all --ostwald-exhaust 26")
        return
    }
    guard !ciphertext.isEmpty else {
        print("ABORT — all-settings needs ciphertext (--ostwald-control p1030684 "
            + "or p1030680 or --ostwald-escalate <quarantine.json>).")
        return
    }

    if shells.count > 1 {
        print("all-settings   : \(shells.count) unique shells in the manifest; "
            + "climbing shell index \(shellIndex) only")
    }
    let shell = shells[shellIndex]
    let from = max(0, sliceFrom)
    let count = min(max(1, sliceCount), OstwaldAllSettings.messageKeys - from)
    var candidates: [OstwaldEscalateManifest.Candidate] = []
    candidates.reserveCapacity(count)
    for offset in 0..<count {
        let pos = OstwaldAllSettings.positions(index: from + offset)
        candidates.append(
            OstwaldEscalateManifest.Candidate(
                ukw: shell.ukw,
                greek: shell.greek,
                wheelOrder: shell.wheelOrder,
                rings: shell.rings,
                positions: OstwaldAllSettings.letters(pos),
                steckerPairs: [],
                menuCrib: crib,
                menuOffset: cribOffset,
                source: "all-settings"
            )
        )
    }
    let manifest = OstwaldEscalateManifest(
        target: target, ciphertext: ciphertext, candidates: candidates
    )

    let ranker: OstwaldRanker.Model?
    if scorer == .ranker {
        let corpusPath = resolveCorpusPath()
        ranker = OstwaldRanker.fit(
            controls: OstwaldCurve.loadControls(path: corpusPath),
            excluding: target == "P1030684-control" ? "P1030684" : nil,
            decoyClimbs: intFlag("--ostwald-ranker-decoy-climbs", allowZero: true) ?? 0,
            navalCorpus: NavalGrams.load(corpusPath: corpusPath)
        )
        if ranker == nil {
            print("ABORT — ranker fit failed on \(corpusPath)")
            return
        }
    } else {
        ranker = nil
    }

    print("=== Ostwald all-settings (no IC sieve) ===")
    print("shell         : \(shell.ukw)/\(shell.greek)/\(shell.wheelOrder)/\(shell.rings)")
    print("positions     : \(from)..<\(from + count) of \(OstwaldAllSettings.messageKeys)")
    print("scorer        : \(scorer.rawValue)   beam \(beamWidth)")
    print("board         : empty (--ostwald-keep 0)")
    print()

    do {
        _ = try OstwaldEscalate.run(
            manifest: manifest,
            label: "all-settings \(shell.ukw)/\(shell.greek)/\(shell.wheelOrder)/\(shell.rings)",
            scorer: scorer,
            exhaustLetters: exhaustLetters,
            keepSeeded: 0,
            noiseSamples: 0,
            printProgress: true,
            exhaustDepth: exhaustDepth,
            topUpTo: topUpTo,
            brutePlugs: brutePlugs,
            bruteAll: bruteAll,
            bruteSettingsOk: bruteSettingsOk,
            useMetal: useMetal,
            budgetBytes: budgetGB * 1_024 * 1_024 * 1_024,
            beamWidth: beamWidth,
            ranker: ranker
        )
    } catch {
        print("\(error)")
    }
}
