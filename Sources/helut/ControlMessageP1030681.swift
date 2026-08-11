import Foundation
import HELUTCore

/// P1030681 / P1030714 — Dönitz successor message (second net).
/// Proofed CT/PT from the corpus; Schlüsselzettel re-check from Girard's
/// [degarbling note](https://enigma.hoerenberg.com/index.php?cat=The%20U534%20messages&page=Degarbling%20the%20D%C3%B6nitz%20Message%20P1030681)
/// is a *historical* same-length near-miss (12 letter diffs, crib head intact).
enum ControlMessageP1030681 {
    static let rings = "AAEL"
    static let positions = "YOSZ"
    static let plugPairs = ["AE", "BF", "CM", "DQ", "HU", "JN", "LX", "PR", "SZ", "VW"]

    /// Final proofed ciphertext (corpus / Hörenberg P1030681 page).
    static let ciphertextProofed =
        "LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOYJFGSLPPQIHZFXOEBWIIEKFZLCLOAQJULJOYHSSMBBGWHZANVOIIPYRBRTDJQDJJOQKCXWDNBBTYVXLYTAPGVEATXSONPNYNQFUDBBHHVWEPYEYDOHNLXKZDNWRHDUWUJUMWWVIIWZXIVIUQDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTREQEDGXHLZWIFUSKDQVELNMIMITHBHDBWVHDFYHJOQIHORTDJDBWXEMEAYXGYQXOHFDMYUXXNOJAZRSGHPLWMLRECWWUTLRTTVLBHYOORGLGOWUXNXHMHYFAACQEKTHSJW"

    /// Re-checked Schlüsselzettel transcription (Girard) — 12 mismatches vs proofed.
    static let ciphertextSchluesselzettel =
        "LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOCKZFSLPPQIHZFXOEBWIIEKFZLCLOAQJULJOYFSSMBBGWHZANVOIIPCRBRTDJQDJJOQCHXPDNBBTYVXLYTAPGVEATXSONPNYNQFUDBBHHVWEPYEYDOHNLXKZDNWRHDUWUJUOWWVIIWZXIVIUQDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTREQEDGXHLZWIFUSKDQVELNMIMITHBHDBWVHDFYHJOQIHORTDJDBWVEMEAYXGYQXOHFDMYUXXNOJAZRSGHPLWOLRECWWUTLRTTVLBHYOORGLGOWUXNXHMHYFAACQEKTHSJW"

    /// First draft transcription (Girard), length-aligned for KPA:
    /// uncertain `.` → `X`, missing group `HMHY` re-inserted before `FAACQE`.
    /// 38 mismatches vs proofed; shared head through letter 56 (crib-safe).
    static let ciphertextFirstDraftAligned =
        "LANOTCTOUARBBFPMHPHGCZXTDYGAHGUFXGEWKBLKGJWLQXXTGPJJAVTOCKZFSLPPGIHZFXOBBWIIEKFZLCLOAQJULJOYFSSMBBGWHZAMVOIIPCRBRTDJQDJJOQCHXPDNBBFYVXLYTAPGVERTXSONPNYNQFUDBBHHVWEPYEYDOHNLXKZDNWRHDUWUJUMPWVIIWZBIVIXKDRHYMNCYEFUAPNHOTKHKGDNPSAKNUAGHJZSMJBMHVTREQEDGXHLZWIFUSKDQVELNMIMITHBSBBWVSDFYHJOQIFORTDJDBWXEMEAYXGYQXOHFDMUWXXNOJAZRHGRPLWMLRCLALLRTRTTVLBFYOORZLGOWUNUXHMHYFAACQEKRHSJW"

    static let plaintext =
        "KRKRALLEXXFOLGENDESISTSOFORTBEKANNTZUGEBENXXICHHABEFOLGENDENBEFEHLERHALTENXXJANSTERLEDESBISHERIGXNREICHSMARSCHALLSJGOERINGJSETZTDERFUEHRERSIEYHVRRGRZSSADMIRALYALSSEINENNACHFOLGEREINXSCHRIFTLSCHEVOLLMACHTUNTERWEGSXABSOFORTSOLLENSIESAEMTLICHEMASSNAHMENVERFUEGENYDIESICHAUSDERGEGENWAERTIGENLAGEERGEBENXGEZXREICHSLEITEIKKTULPEKKJBORMANNJXXOBXDXMMMDURNHFKSTXKOMXADMXUUUBOOIEXKP"

    static func bombe(maxPlugs: Int = 10) -> WelchmanBombe {
        WelchmanBombe(
            greek: EnigmaM4Warehouse.beta,
            left: EnigmaWarehouse.rotorV,
            middle: EnigmaWarehouse.rotorVI,
            right: EnigmaWarehouse.rotorVIII,
            reflector: EnigmaM4Warehouse.thinC,
            rings: EnigmaM4Key.rings(fromLetters: rings),
            maxPlugs: maxPlugs
        )
    }

    static var trueStecker: [Int] {
        var table = Array(0..<26)
        for pair in plugPairs {
            let letters = Array(pair)
            let a = EnigmaAlphabet.index(letters[0])
            let b = EnigmaAlphabet.index(letters[1])
            table[a] = b
            table[b] = a
        }
        return table
    }

    /// Letter-level diffs between Schlüsselzettel re-check and proofed CT.
    static func schluesselzettelEdits() -> [String] {
        edits(from: ciphertextSchluesselzettel)
    }

    /// Letter-level diffs between aligned first-draft CT and proofed CT.
    static func firstDraftEdits() -> [String] {
        edits(from: ciphertextFirstDraftAligned)
    }

    private static func edits(from garbled: String) -> [String] {
        let a = EnigmaAlphabet.normalize(ciphertextProofed)
        let b = EnigmaAlphabet.normalize(garbled)
        precondition(a.count == b.count)
        var edits: [String] = []
        for i in 0..<a.count where a[i] != b[i] {
            edits.append(
                "\(i):\(EnigmaAlphabet.character(a[i]))→\(EnigmaAlphabet.character(b[i]))"
            )
        }
        return edits
    }
}
