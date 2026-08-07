import Foundation
import HELUTCore
import HELUTCLI

// MARK: - Locked-plug remainder
//
// The menu-62 head printed nine plug pairs. Eight letters are still free, so a
// tenth pair is 28 boards, plus the nine-pair board itself. Those boards stay
// fixed. The search is the rotor remainder on that one shell: every message key
// and every middle ring. Left, Greek, and right rings stay as given.
//
// No crib is applied. A score that clears the numeric bar is not a campaign break.

func runOstwaldLockedPlugs() {
    guard let shellText = stringFlag("--ostwald-shell"),
          let shell = OstwaldAllSettings.parseShell(shellText) else {
        print("--ostwald-locked-plugs needs --ostwald-shell UKW/greek/L-M-R/rings")
        exit(2)
    }
    guard let plugText = stringFlag("--ostwald-plugs") else {
        print("--ostwald-locked-plugs needs --ostwald-plugs \"AP BG ...\"")
        exit(2)
    }
    let given = plugText.split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
    guard let locked = PlugCompletion.pairs(given) else {
        print("each plug must be two distinct letters")
        exit(2)
    }
    let rings = EnigmaAlphabet.normalize(shell.rings)
    guard rings.count == 4 else {
        print("rings need four letters")
        exit(2)
    }
    let wheels = shell.wheelOrder.split(separator: "-").map(String.init)
    guard wheels.count == 3 else {
        print("wheel order needs L-M-R")
        exit(2)
    }
    let boards = PlugCompletion.boards(locked: locked)
    let ciphertext = EnigmaAlphabet.normalize(U534MessageP1030680.ciphertext)
    let greek = EnigmaM4Warehouse.greek(named: shell.greek)
    let rotors = (
        EnigmaWarehouse.rotor(named: wheels[0]),
        EnigmaWarehouse.rotor(named: wheels[1]),
        EnigmaWarehouse.rotor(named: wheels[2])
    )
    let reflector = EnigmaM4Warehouse.thinReflector(named: shell.ukw)
    let rightRing = rings[3]
    let leftRing = rings[1]
    let greekRing = rings[0]

    print("locked plugs \(given.joined(separator: " ")) — \(locked.count) pairs, "
        + "\(boards.count) boards (the given board plus each tenth pair)")
    print("shell \(shell.ukw)/\(shell.greek)/\(shell.wheelOrder) "
        + "rings \(shell.rings) — middle ring swept, right ring held")
    print("message keys \(OstwaldAllSettings.messageKeys) × \(boards.count) boards "
        + "× 26 middle rings")
    print("ciphertext \(U534MessageP1030680.id), \(ciphertext.count) letters. No crib.")
    fflush(stdout)

    var bestTail = -Double.infinity
    var bestLine = ""
    var scored = 0
    let started = Date()
    for middle in 0..<26 {
        for board in boards {
            let plugboard = PlugCompletion.table(board)
            for index in 0..<OstwaldAllSettings.messageKeys {
                let position = OstwaldAllSettings.positions(index: index)
                let key = EnigmaM4Key(
                    greek: greek,
                    rotors: rotors,
                    rings: (greekRing, leftRing, middle, rightRing),
                    positions: position,
                    plugboard: plugboard,
                    reflector: reflector
                )
                var machine = EnigmaM4Machine(key: key)
                var plain = [Int](repeating: 0, count: ciphertext.count)
                for letter in ciphertext.indices {
                    plain[letter] = machine.process(ciphertext[letter])
                }
                let tail = GermanTrigrams.score(plain)
                scored += 1
                if tail > bestTail {
                    bestTail = tail
                    let ic = LanguageScorer.indexOfCoincidence(plain)
                    let text = EnigmaAlphabet.string(from: plain)
                    bestLine = String(
                        format: "middle %@ pos %@ plugs %@ IC %.3f tail %.3f %@",
                        String(EnigmaAlphabet.character(middle)),
                        OstwaldAllSettings.letters(position),
                        PlugCompletion.label(board),
                        ic, tail, text
                    )
                }
            }
        }
        let elapsed = Date().timeIntervalSince(started)
        let rate = elapsed > 0 ? Double(scored) / elapsed : 0
        print(String(
            format: "middle %@ done  best %@  %.0f decrypts/s",
            String(EnigmaAlphabet.character(middle)), bestLine, rate
        ))
        fflush(stdout)
    }
    print("best \(bestLine)")
    print(String(
        format: "bar is IC ≥ %.3f and tail > %.3f. This search has no crib, so a score is not a break.",
        PostBombeDiscriminator.icFloor, PostBombeDiscriminator.breakThreshold
    ))
}

private enum PlugCompletion {
    static func pairs(_ tokens: [String]) -> [(Int, Int)]? {
        var out: [(Int, Int)] = []
        var used = Set<Int>()
        for token in tokens {
            let letters = EnigmaAlphabet.normalize(token)
            guard letters.count == 2, letters[0] != letters[1],
                  !used.contains(letters[0]), !used.contains(letters[1]) else {
                return nil
            }
            used.insert(letters[0])
            used.insert(letters[1])
            out.append((letters[0], letters[1]))
        }
        return out
    }

    static func boards(locked: [(Int, Int)]) -> [[(Int, Int)]] {
        var used = Set<Int>()
        for pair in locked {
            used.insert(pair.0)
            used.insert(pair.1)
        }
        let free = (0..<26).filter { !used.contains($0) }
        var boards = [locked]
        if locked.count < 10 {
            for left in 0..<free.count {
                for right in (left + 1)..<free.count {
                    boards.append(locked + [(free[left], free[right])])
                }
            }
        }
        return boards
    }

    static func table(_ pairs: [(Int, Int)]) -> [Int] {
        var table = Array(0..<26)
        for pair in pairs {
            table[pair.0] = pair.1
            table[pair.1] = pair.0
        }
        return table
    }

    static func label(_ pairs: [(Int, Int)]) -> String {
        pairs.map {
            "\(EnigmaAlphabet.character($0.0))\(EnigmaAlphabet.character($0.1))"
        }.joined(separator: " ")
    }
}
