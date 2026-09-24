import Foundation
import HELUTCore
import HELUTCLI

// MARK: - `--ostwald-escalate` : finish what the bombe started
//
// The measured result that motivates this (Phase 50.6): at 72 letters — P1030680's exact
// length, below the published 78-letter record for crib-free attacks — the staged climb
// recovers the full key and 100% of the plaintext once something hands it 8 correct plugs,
// and its margin over wrong settings goes positive at 4. A Welchman stop arrives with the
// stecker its menu forced, which is 7–12 plugs.
//
// So this is not a crib-free break of P1030680, and it must not be described as one. What
// it is: a far better *escalator* than the GA the quarantine tier currently feeds. Phase 22
// pushed soft-band stops into a stochastic hill-climb and got 0 survivors at a ~60%
// coincidence ceiling. The climber's job here is narrower and much better posed — the shell
// is fixed by the stop, several plugs are already forced, and only the remainder is
// searched.
//
// Logic of the test: if a quarantined stop is the *true* key, its forced plugs are correct,
// the climb finishes, and the plaintext appears. If it is a ghost, its forced plugs are
// wrong, and no amount of climbing rescues it. That is a clean decision on each candidate.

package struct OstwaldEscalateManifest: Decodable {
    package struct Candidate: Decodable {
        package let ukw: String
        package let greek: String
        package let wheelOrder: String
        package let rings: String
        package let positions: String
        package let steckerPairs: [String]
        package let menuCrib: String
        package let menuOffset: Int
        package let menuAnchors: [BombeMenuAnchor]?
        package let ic: Double
        package let tailScore: Double
        package let source: String
        package let leadingHoles: Int?

        package init(
            ukw: String,
            greek: String,
            wheelOrder: String,
            rings: String,
            positions: String,
            steckerPairs: [String],
            menuCrib: String,
            menuOffset: Int,
            menuAnchors: [BombeMenuAnchor]? = nil,
            ic: Double = 0,
            tailScore: Double = 0,
            source: String,
            leadingHoles: Int? = nil
        ) {
            self.ukw = ukw
            self.greek = greek
            self.wheelOrder = wheelOrder
            self.rings = rings
            self.positions = positions
            self.steckerPairs = steckerPairs
            self.menuCrib = menuCrib
            self.menuOffset = menuOffset
            self.menuAnchors = menuAnchors
            self.ic = ic
            self.tailScore = tailScore
            self.source = source
            self.leadingHoles = leadingHoles
        }
    }
    package let target: String
    package let ciphertext: String
    package let candidates: [Candidate]

    package init(target: String, ciphertext: String, candidates: [Candidate]) {
        self.target = target
        self.ciphertext = ciphertext
        self.candidates = candidates
    }
}

package enum OstwaldEscalateError: Error, CustomStringConvertible {
    case trigramsUnavailable
    case unreadableManifest(String)
    case emptyManifest
    case invalidExhaust(String)

    package var description: String {
        switch self {
        case .trigramsUnavailable:
            return "ABORT — attested trigram model unavailable; escalation break bar not evaluated."
        case let .unreadableManifest(path):
            return "could not read quarantine manifest at \(path)"
        case .emptyManifest:
            return "quarantine manifest has no candidates"
        case let .invalidExhaust(message):
            return message
        }
    }
}

package struct OstwaldEscalateCandidateResult: Sendable {
    package let index: Int
    package let ukw: String
    package let greek: String
    package let wheelOrder: String
    package let rings: String
    package let positions: String
    package let score: Double
    package let ic: Double
    package let tail: Double
    package let plaintext: String
    package let pairCount: Int
    package let cribExact: Bool
    package let clearsBreakBar: Bool
}

package struct OstwaldEscalateResult: Sendable {
    package let target: String
    package let ciphertextLength: Int
    package let candidateCount: Int
    package let noiseSampleCount: Int
    package let floorMean: Double
    package let floorBest: Double
    package let ranked: [OstwaldEscalateCandidateResult]
    package let breakCount: Int
}

package enum OstwaldEscalate {
    /// Campaign JSON stores `"beta"` / `"gamma"`. Historical climber lookup is
    /// `beta → B`, everything else → `C` (so `"gamma"` lands on gamma, which is correct).
    /// A stored `"B"` would be sent to gamma — adapters must emit `"beta"`, not `"B"`.
    package static func greekLookupName(_ stored: String) -> String {
        stored == "beta" ? "B" : "C"
    }

    package static func parseSteckerPairs(_ tokens: [String]) -> [(Int, Int)] {
        tokens.compactMap { token -> (Int, Int)? in
            let letters = Array(token)
            guard letters.count == 2 else { return nil }
            let a = EnigmaAlphabet.index(letters[0])
            let b = EnigmaAlphabet.index(letters[1])
            guard a >= 0, a < 26, b >= 0, b < 26, a != b else { return nil }
            return (min(a, b), max(a, b))
        }
    }

    package static func rotorTriple(
        _ wheelOrder: String
    ) -> (EnigmaRotorSpec, EnigmaRotorSpec, EnigmaRotorSpec) {
        let names = wheelOrder.split(separator: "-").map(String.init)
        guard names.count == 3 else {
            return (EnigmaWarehouse.rotorI, EnigmaWarehouse.rotorII, EnigmaWarehouse.rotorIII)
        }
        func rotor(_ name: String) -> EnigmaRotorSpec {
            M4ThetisAttack.navalRotors.first { $0.name == name } ?? EnigmaWarehouse.rotorI
        }
        return (rotor(names[0]), rotor(names[1]), rotor(names[2]))
    }

    /// One greedy wave (Metal lockstep or CPU concurrent) over a job batch.
    /// Accumulates `decryptsDone` so streamed 4-plug chunks share one ETA.
    private static func executeClimbs(
        jobs: inout [OstwaldClimbJob],
        ciphertext: [Int],
        scorer: ClimbScorer,
        beamWidth: Int,
        ranker: OstwaldRanker.Model?,
        anyMetal: Bool,
        engineFor: (OstwaldClimbJob) -> OstwaldMetalEngine?,
        printProgress: Bool,
        started: Date,
        plannedDecrypts: Int,
        decryptsDone: inout Int,
        note: (String) -> Void
    ) {
        guard !jobs.isEmpty else { return }
        if anyMetal {
            var round = 0
            while jobs.contains(where: { !$0.stuck && $0.pairs.count < $0.maxPlugs }) {
                round += 1
                OstwaldWave.greedyRound(
                    jobs: &jobs,
                    ciphertext: ciphertext,
                    scorer: scorer,
                    engineFor: engineFor,
                    decryptsDone: &decryptsDone,
                    ranker: ranker
                )
                let elapsed = Date().timeIntervalSince(started)
                let live = OstwaldProgress.liveLine(
                    elapsed: elapsed, decryptsDone: decryptsDone, decryptsTotal: plannedDecrypts
                )
                let active = jobs.filter { !$0.stuck && $0.pairs.count < $0.maxPlugs }.count
                note(String(format: "  [round %d · %d climbs live · %d decrypts] %@",
                            round, active, decryptsDone, live))
                if round > 12 { break }
            }
            OstwaldWave.scoreFinal(
                jobs: &jobs,
                ciphertext: ciphertext,
                scorer: scorer,
                engineFor: engineFor,
                ranker: ranker
            )
            OstwaldWave.polishTop(
                jobs: &jobs, ciphertext: ciphertext, scorer: scorer,
                beamWidth: beamWidth, ranker: ranker
            )
            return
        }
        final class Slot: @unchecked Sendable {
            var result: (pairs: [(Int, Int)], score: Double, plain: [Int])?
        }
        let jobCount = jobs.count
        let planned = plannedDecrypts
        let already = decryptsDone
        let snapshot = jobs
        let slots = snapshot.map { _ in Slot() }
        final class Progress: @unchecked Sendable {
            let lock = NSLock()
            var completed = 0
            var scored = 0
        }
        let progress = Progress()
        let stride = jobCount <= 2_000 ? 25 : max(100, jobCount / 200)
        DispatchQueue.concurrentPerform(iterations: jobCount) { index in
            let job = snapshot[index]
            let climbed = OstwaldCurve.climb(
                key: job.key, ciphertext: ciphertext, scorer: scorer,
                maxPlugs: job.maxPlugs, seeded: job.pairs, walk: job.walk,
                beamWidth: beamWidth, ranker: ranker
            )
            slots[index].result = climbed
            progress.lock.lock()
            progress.scored += OstwaldProgress.greedyDecrypts(
                seeded: job.seededCount, beamWidth: beamWidth
            )
            progress.completed += 1
            let done = progress.completed
            let decrypts = already + progress.scored
            progress.lock.unlock()
            if printProgress, done == 1 || done % stride == 0 || done == jobCount {
                let elapsed = Date().timeIntervalSince(started)
                let live = OstwaldProgress.liveLine(
                    elapsed: elapsed, decryptsDone: decrypts, decryptsTotal: planned
                )
                print(String(format: "  [%d/%d] %@", done, jobCount, live))
                fflush(stdout)
            }
        }
        decryptsDone += progress.scored
        for index in jobs.indices {
            if let climbed = slots[index].result {
                jobs[index].pairs = climbed.pairs
                jobs[index].score = climbed.score
                jobs[index].plain = climbed.plain
            }
        }
    }

    /// Callable core. Does not read argv or `exit`. Default `noiseSamples` is the campaign
    /// floor (12); tests pass 0 to skip random climbs. `exhaustLetters` defaults to 0 so
    /// existing tests stay a single climb; the CLI wrapper applies the measured cell
    /// (exhaust 6 / depth 2 / top-up 4) and Metal.
    /// `keepSeeded` nil = hold every forced plug; 0 = unlock all (empty extra board).
    package static func run(
        manifestPath: String,
        scorer: ClimbScorer = .staged,
        exhaustLetters: Int = 0,
        keepSeeded: Int? = nil,
        noiseSamples: Int = 12,
        printProgress: Bool = false,
        exhaustDepth: Int = 1,
        topUpTo: Int = 0,
        brutePlugs: Int = 0,
        bruteAll: Bool = false,
        bruteSettingsOk: Bool = false,
        useMetal: Bool = false,
        budgetBytes: Int = OstwaldMemory.defaultBudgetBytes,
        beamWidth: Int = 1,
        ranker: OstwaldRanker.Model? = nil
    ) throws -> OstwaldEscalateResult {
        guard let data = FileManager.default.contents(atPath: manifestPath),
              let manifest = try? JSONDecoder().decode(OstwaldEscalateManifest.self, from: data)
        else {
            throw OstwaldEscalateError.unreadableManifest(manifestPath)
        }
        return try run(
            manifest: manifest,
            label: manifestPath,
            scorer: scorer,
            exhaustLetters: exhaustLetters,
            keepSeeded: keepSeeded,
            noiseSamples: noiseSamples,
            printProgress: printProgress,
            exhaustDepth: exhaustDepth,
            topUpTo: topUpTo,
            brutePlugs: brutePlugs,
            bruteAll: bruteAll,
            bruteSettingsOk: bruteSettingsOk,
            useMetal: useMetal,
            budgetBytes: budgetBytes,
            beamWidth: beamWidth,
            ranker: ranker
        )
    }

    package static func run(
        manifest: OstwaldEscalateManifest,
        label: String,
        scorer: ClimbScorer = .staged,
        exhaustLetters: Int = 0,
        keepSeeded: Int? = nil,
        noiseSamples: Int = 12,
        printProgress: Bool = false,
        exhaustDepth: Int = 1,
        topUpTo: Int = 0,
        brutePlugs: Int = 0,
        bruteAll: Bool = false,
        bruteSettingsOk: Bool = false,
        useMetal: Bool = false,
        budgetBytes: Int = OstwaldMemory.defaultBudgetBytes,
        beamWidth: Int = 1,
        ranker: OstwaldRanker.Model? = nil
    ) throws -> OstwaldEscalateResult {
        guard GermanTrigrams.isLoaded else { throw OstwaldEscalateError.trigramsUnavailable }
        guard !manifest.candidates.isEmpty else { throw OstwaldEscalateError.emptyManifest }

        let ciphertext = EnigmaAlphabet.normalize(manifest.ciphertext)
        do {
            _ = try OstwaldExhaust.startSets(
                ciphertext: ciphertext,
                exhaustLetters: exhaustLetters,
                exhaustDepth: exhaustDepth,
                alsoSeeded: [],
                topUpTo: topUpTo,
                brutePlugs: brutePlugs,
                bruteAll: bruteAll
            )
        } catch OstwaldExhaust.Error.fourPlugWouldMaterialize {
            // Full-alphabet 4-plug brute streams in chunks. Preflight still ran the
            // exhaust-6 / saturation-trap refusals inside startSets before this throw.
        } catch let error as OstwaldExhaust.Error {
            throw OstwaldEscalateError.invalidExhaust(error.description)
        }

        func note(_ line: String) {
            if printProgress {
                print(line)
                fflush(stdout)
            }
        }

        note("=== Ostwald escalation of bombe stops ===")
        note("manifest      : \(label)")
        note("target        : \(manifest.target) (\(ciphertext.count) letters)")
        note("candidates    : \(manifest.candidates.count)")
        note("scorer        : \(scorer.rawValue)   trigram model: \(GermanTrigrams.sourceDescription)")
        if let ranker {
            note("ranker        : \(ranker.sourceDescription)")
        }
        if beamWidth > 1 {
            note("beam          : \(beamWidth) partial boards per insertion round")
        }
        note("seeding       : " + {
            if let keepSeeded {
                if keepSeeded == 0 {
                    return "all forced plugs UNLOCKED (--ostwald-keep 0); climb from empty extra board"
                }
                return "first \(keepSeeded) forced plug(s) held fixed, remainder re-climbed"
            }
            return "all forced plugs held fixed (--ostwald-keep 0 to unlock all)"
        }())
        if brutePlugs >= 4 {
            note("exhaustion    : 4-plug brute on \(exhaustLetters) hot letters")
        } else if topUpTo > 0 {
            note("exhaustion    : top-up to \(topUpTo) via exhaust \(exhaustLetters) depth \(exhaustDepth), then climb to 10")
        } else if exhaustLetters > 0 {
            note("exhaustion    : \(exhaustLetters) high-frequency letters, depth \(exhaustDepth)")
        }
        note("break bar     : crib exact ∧ IC ≥ \(PostBombeDiscriminator.icFloor) ∧ "
            + "tail > \(PostBombeDiscriminator.breakThreshold)")
        note("")

        var generator = SplitMix64(seed: 0xC0FFEE)
        var floorScores: [Double] = []
        if noiseSamples > 0, let first = manifest.candidates.first {
            let triple = rotorTriple(first.wheelOrder)
            for _ in 0..<noiseSamples {
                let key = EnigmaM4Key(
                    greek: EnigmaM4Warehouse.greek(named: greekLookupName(first.greek)),
                    rotors: triple,
                    rings: EnigmaM4Key.rings(fromLetters: first.rings),
                    positions: (Int(generator.next() % 26), Int(generator.next() % 26),
                                Int(generator.next() % 26), Int(generator.next() % 26)),
                    plugboard: Array(0..<26),
                    reflector: EnigmaM4Warehouse.thinReflector(named: first.ukw)
                )
                floorScores.append(
                    OstwaldCurve.climb(
                        key: key, ciphertext: ciphertext, scorer: scorer,
                        beamWidth: beamWidth, ranker: ranker
                    ).score
                )
            }
        }
        let floorMean = floorScores.isEmpty
            ? 0
            : floorScores.reduce(0, +) / Double(floorScores.count)
        let floorBest = floorScores.max() ?? -.infinity
        if !floorScores.isEmpty {
            note(String(format: "noise floor   : mean %.4f, best of %d random settings %.4f",
                        floorMean, floorScores.count, floorBest))
            note("")
        }

        var jobs: [OstwaldClimbJob] = []
        var plannedDecrypts = 0
        var streamPlans: [(
            index: Int,
            key: EnigmaM4Key,
            walk: OstwaldWalk,
            pool: [Int],
            startCount: Int
        )] = []
        for (index, candidate) in manifest.candidates.enumerated() {
            let forced = parseSteckerPairs(candidate.steckerPairs)
            let seeded: [(Int, Int)]
            if let keepSeeded {
                seeded = Array(forced.prefix(keepSeeded))
            } else {
                seeded = forced
            }
            let holes = candidate.leadingHoles ?? 0
            let walk = holes > 0 ? OstwaldWalk.leadingGap(holes) : .dense
            let key = EnigmaM4Key(
                greek: EnigmaM4Warehouse.greek(named: greekLookupName(candidate.greek)),
                rotors: rotorTriple(candidate.wheelOrder),
                rings: EnigmaM4Key.rings(fromLetters: candidate.rings),
                positions: EnigmaM4Key.positions(fromLetters: candidate.positions),
                plugboard: Array(0..<26),
                reflector: EnigmaM4Warehouse.thinReflector(named: candidate.ukw)
            )
            let locked = Set(seeded.flatMap { [$0.0, $0.1] })
            let pool = OstwaldExhaust.fourPlugPool(
                ciphertext: ciphertext, exhaustLetters: exhaustLetters, locked: locked
            )
            let streamCount = (brutePlugs >= 4 && bruteAll && seeded.isEmpty)
                ? OstwaldExhaust.fourPlugStartCount(letterCount: pool.count)
                : 0
            if streamCount > OstwaldExhaust.fourPlugMaterializeCap {
                streamPlans.append(
                    (index: index, key: key, walk: walk, pool: pool, startCount: streamCount)
                )
                plannedDecrypts += streamCount * OstwaldProgress.greedyInsertDecrypts(
                    seeded: 4
                ) * max(1, beamWidth)
                continue
            }
            let starts: [[(Int, Int)]]
            do {
                starts = try OstwaldExhaust.startSets(
                    ciphertext: ciphertext,
                    exhaustLetters: exhaustLetters,
                    exhaustDepth: exhaustDepth,
                    alsoSeeded: seeded,
                    topUpTo: topUpTo,
                    brutePlugs: brutePlugs,
                    bruteAll: bruteAll
                )
            } catch let error as OstwaldExhaust.Error {
                throw OstwaldEscalateError.invalidExhaust(error.description)
            }
            for start in starts {
                let pairs = seeded + start
                jobs.append(
                    OstwaldClimbJob(
                        candidateIndex: index,
                        key: key,
                        pairs: pairs,
                        seededCount: pairs.count,
                        walk: walk
                    )
                )
                plannedDecrypts += OstwaldProgress.greedyDecrypts(
                    seeded: pairs.count, beamWidth: beamWidth
                )
            }
        }

        if plannedDecrypts > OstwaldExhaust.fourPlugDecryptCapWithoutOverride,
           !bruteSettingsOk {
            throw OstwaldEscalateError.invalidExhaust(
                "ABORT — \(plannedDecrypts) decrypts is more than one locked-setting "
                    + "4-plug alphabet climb. Known-key greeting is one setting "
                    + "(--ostwald-setting-count 1). Pass --ostwald-brute-settings-ok "
                    + "only if that wall-clock was the intent."
            )
        }

        let metalEligible = useMetal && beamWidth <= 1 && scorer.usesMetalKernel && ranker == nil
        var metalEngines: [String: OstwaldMetalEngine] = [:]
        func engineKey(_ key: EnigmaM4Key) -> String {
            "\(key.greek.name)|\(key.rotors.0.name)-\(key.rotors.1.name)-\(key.rotors.2.name)|"
                + "\(key.rings.0)-\(key.rings.1)-\(key.rings.2)-\(key.rings.3)|"
                + "\(key.reflector.hashValue)"
        }
        func engineFor(_ job: OstwaldClimbJob) -> OstwaldMetalEngine? {
            guard metalEligible else { return nil }
            let id = engineKey(job.key)
            if let existing = metalEngines[id] { return existing }
            let made = OstwaldMetalEngine.make(
                key: job.key, ciphertext: ciphertext, budgetBytes: budgetBytes
            )
            if let made { metalEngines[id] = made }
            return made
        }
        let probeJob = jobs.first ?? streamPlans.first.map {
            OstwaldClimbJob(
                candidateIndex: $0.index, key: $0.key, pairs: [(0, 1)],
                seededCount: 4, walk: $0.walk
            )
        }
        let anyMetal = probeJob.map { engineFor($0) != nil } ?? false
        let backend = anyMetal ? "Metal-ostwald-score" : "CPU"
        let floorRate = anyMetal
            ? OstwaldProgress.metalDecryptFloorPerSecond
            : OstwaldProgress.cpuDecryptFloorPerSecond
        let trialCap = OstwaldMemory.maxTrials(budgetBytes: budgetBytes)
        let waveJobs = OstwaldExhaust.fourPlugWaveJobs(trialCap: trialCap)
        let streamedStarts = streamPlans.reduce(0) { $0 + $1.startCount }
        if streamedStarts > 0 {
            note("exhaustion    : streaming \(streamedStarts) 4-plug starts "
                + "in waves of \(waveJobs) "
                + "(not materialised; polish-top \(OstwaldWave.polishTopCount))")
        }
        note(String(format: "climbs        : %d materialised + %d streamed (%d candidates)",
                    jobs.count, streamedStarts, manifest.candidates.count))
        note(String(
            format: "unified budget: %.1f GB → %.3g trials/dispatch (32-byte records)",
            Double(budgetBytes) / 1_073_741_824.0, Double(trialCap)
        ))
        note("backend       : \(backend)   cores \(ProcessInfo.processInfo.activeProcessorCount)")
        note("decrypts      : \(plannedDecrypts)")
        note(OstwaldProgress.floorLine(decrypts: plannedDecrypts, perSecond: floorRate))
        note("")

        let started = Date()
        var decryptsDone = 0
        var bestByCandidate: [Int: OstwaldClimbJob] = [:]
        func merge(_ finished: [OstwaldClimbJob]) {
            for job in finished {
                if let existing = bestByCandidate[job.candidateIndex] {
                    if job.score > existing.score { bestByCandidate[job.candidateIndex] = job }
                } else {
                    bestByCandidate[job.candidateIndex] = job
                }
            }
        }
        if !jobs.isEmpty {
            executeClimbs(
                jobs: &jobs,
                ciphertext: ciphertext,
                scorer: scorer,
                beamWidth: beamWidth,
                ranker: ranker,
                anyMetal: anyMetal,
                engineFor: engineFor,
                printProgress: printProgress,
                started: started,
                plannedDecrypts: plannedDecrypts,
                decryptsDone: &decryptsDone,
                note: note
            )
            merge(jobs)
            jobs = []
        }
        if !streamPlans.isEmpty {
            let chunk = waveJobs
            var chunkIndex = 0
            let chunkTotal = (streamedStarts + chunk - 1) / chunk
            for plan in streamPlans {
                var batch: [OstwaldClimbJob] = []
                batch.reserveCapacity(chunk)
                OstwaldExhaust.visitFourPlugStarts(pool: plan.pool) { pairs in
                    batch.append(
                        OstwaldClimbJob(
                            candidateIndex: plan.index,
                            key: plan.key,
                            pairs: pairs,
                            seededCount: pairs.count,
                            walk: plan.walk
                        )
                    )
                    if batch.count >= chunk {
                        chunkIndex += 1
                        note("  [wave \(chunkIndex)/\(chunkTotal) · \(batch.count) 4-plug climbs]")
                        var toRun = batch
                        batch = []
                        executeClimbs(
                            jobs: &toRun,
                            ciphertext: ciphertext,
                            scorer: scorer,
                            beamWidth: beamWidth,
                            ranker: ranker,
                            anyMetal: anyMetal,
                            engineFor: engineFor,
                            printProgress: printProgress,
                            started: started,
                            plannedDecrypts: plannedDecrypts,
                            decryptsDone: &decryptsDone,
                            note: note
                        )
                        merge(toRun)
                    }
                }
                if !batch.isEmpty {
                    chunkIndex += 1
                    note("  [wave \(chunkIndex)/\(chunkTotal) · \(batch.count) 4-plug climbs]")
                    executeClimbs(
                        jobs: &batch,
                        ciphertext: ciphertext,
                        scorer: scorer,
                        beamWidth: beamWidth,
                        ranker: ranker,
                        anyMetal: anyMetal,
                        engineFor: engineFor,
                        printProgress: printProgress,
                        started: started,
                        plannedDecrypts: plannedDecrypts,
                        decryptsDone: &decryptsDone,
                        note: note
                    )
                    merge(batch)
                }
            }
        }

        // bestByCandidate already filled.

        var results: [OstwaldEscalateCandidateResult] = []
        for (index, candidate) in manifest.candidates.enumerated() {
            let job = bestByCandidate[index]
            let plain = job?.plain ?? []
            let score = job?.score ?? -.infinity
            let pairCount = job?.pairs.count ?? 0
            let anchors = candidate.menuAnchors
                ?? [BombeMenuAnchor(text: candidate.menuCrib, offset: candidate.menuOffset)]
            let exact = anchors.allSatisfy { anchor in
                anchor.offset >= 0 && anchor.range.upperBound <= plain.count
                    && Array(plain[anchor.range]) == anchor.letters
            }
            let ic = LanguageScorer.indexOfCoincidence(plain)
            let tail = GermanTrigrams.scoreIfLoaded(plain) ?? -.infinity
            let clears = exact
                && ic >= PostBombeDiscriminator.icFloor
                && tail > PostBombeDiscriminator.breakThreshold
                && pairCount <= 10
            results.append(
                OstwaldEscalateCandidateResult(
                    index: index,
                    ukw: candidate.ukw,
                    greek: candidate.greek,
                    wheelOrder: candidate.wheelOrder,
                    rings: candidate.rings,
                    positions: candidate.positions,
                    score: score,
                    ic: ic,
                    tail: tail,
                    plaintext: EnigmaAlphabet.string(from: plain),
                    pairCount: pairCount,
                    cribExact: exact,
                    clearsBreakBar: clears
                )
            )
        }

        let ranked = results.sorted { $0.score > $1.score }
        note("top escalated candidates by climbed score:")
        note("   #  climbed      IC     tail  crib  shell / position")
        for result in ranked.prefix(12) {
            note(String(format: "  %2d  %7.4f  %.4f  %7.4f  %@   %@/%@/%@ %@ %@",
                        result.index,
                        result.score, result.ic, result.tail,
                        result.cribExact ? "ok " : "BAD",
                        result.ukw as NSString,
                        result.greek as NSString,
                        result.wheelOrder as NSString,
                        result.rings as NSString,
                        result.positions as NSString))
            note("      \(String(result.plaintext.prefix(72)))")
        }
        note("")

        let breaks = ranked.filter(\.clearsBreakBar)
        if breaks.isEmpty {
            let best = ranked.first
            note("NO BREAK — no escalated candidate clears crib-exact ∧ IC ≥ "
                + "\(PostBombeDiscriminator.icFloor) ∧ tail > \(PostBombeDiscriminator.breakThreshold).")
            if let best {
                note(String(format: "  best climbed %.4f (noise best %.4f, Δ %+.4f) "
                            + "IC %.4f tail %.4f",
                            best.score, floorBest, best.score - floorBest, best.ic, best.tail))
                if !floorScores.isEmpty, best.score <= floorBest {
                    note("  and it does not even clear the random-setting floor, so these stops")
                    note("  are ghosts as far as this scorer can tell.")
                }
            }
            note("")
            note("Read this narrowly. It says the quarantined stops in this file are not the")
            note("key. It does not bound the escalator, which is graded separately on known")
            note("keys (Phase 50.6): given 4+ correct plugs it clears the bar at 72 letters.")
        } else {
            note("*** \(breaks.count) CANDIDATE(S) CLEAR THE BREAK BAR ***")
            for result in breaks {
                note(String(format: "  IC %.4f tail %.4f pairs %d",
                            result.ic, result.tail, result.pairCount))
                note("  \(result.ukw)/\(result.greek)/"
                    + "\(result.wheelOrder) rings \(result.rings) "
                    + "pos \(result.positions)")
                note("  \(result.plaintext)")
                note("  VERIFY BY HAND before this is recorded as a break.")
            }
        }

        return OstwaldEscalateResult(
            target: manifest.target,
            ciphertextLength: ciphertext.count,
            candidateCount: manifest.candidates.count,
            noiseSampleCount: floorScores.count,
            floorMean: floorMean,
            floorBest: floorBest,
            ranked: ranked,
            breakCount: breaks.count
        )
    }
}

func runOstwaldEscalate() {
    guard let path = stringFlag("--ostwald-escalate") else {
        print("usage: --ostwald-escalate <quarantine.json> "
            + "[--ostwald-exhaust 6] [--ostwald-exhaust-depth 2] [--ostwald-top-up 4] "
            + "[--ostwald-brute-plugs 4] [--ostwald-brute-all] [--ostwald-cpu] "
            + "[--ostwald-brute-settings-ok] "
            + "[--ostwald-memory-gb \(OstwaldMemory.defaultBudgetGigabytes)] "
            + "[--ostwald-keep 0] [--ostwald-beam N] [--ostwald-scorer staged|ranker]")
        return
    }
    let scorer = ClimbScorer(rawValue: stringFlag("--ostwald-scorer") ?? "staged") ?? .staged
    let brutePlugs = intFlag("--ostwald-brute-plugs", allowZero: true) ?? 0
    let bruteAll = CommandLine.arguments.contains("--ostwald-brute-all")
    let bruteSettingsOk = CommandLine.arguments.contains("--ostwald-brute-settings-ok")
    var exhaustLetters = intFlag("--ostwald-exhaust", allowZero: true)
        ?? OstwaldExhaust.measuredLetters
    if brutePlugs >= 4, bruteAll, intFlag("--ostwald-exhaust", allowZero: true) == nil {
        exhaustLetters = OstwaldExhaust.fourPlugAlphabetLetters
    }
    let exhaustDepth = intFlag("--ostwald-exhaust-depth") ?? OstwaldExhaust.measuredDepth
    let topUpTo = intFlag("--ostwald-top-up", allowZero: true) ?? OstwaldExhaust.measuredTopUpTo
    let useMetal = !CommandLine.arguments.contains("--ostwald-cpu")
    let budgetGB = intFlag("--ostwald-memory-gb") ?? OstwaldMemory.defaultBudgetGigabytes
    let keepSeeded = intFlag("--ostwald-keep", allowZero: true)
    let beamWidth = intFlag("--ostwald-beam") ?? 1
    let ranker: OstwaldRanker.Model?
    if scorer == .ranker {
        let corpusPath = resolveCorpusPath()
        let controls = OstwaldCurve.loadControls(path: corpusPath)
        let naval = NavalGrams.load(corpusPath: corpusPath)
        ranker = OstwaldRanker.fit(
            controls: controls, excluding: nil,
            decoyClimbs: intFlag("--ostwald-ranker-decoy-climbs", allowZero: true) ?? 0,
            navalCorpus: naval
        )
        if ranker == nil {
            print("ABORT — --ostwald-scorer ranker needs a fitted leave-one-out model "
                + "from \(corpusPath); none built.")
            return
        }
    } else {
        ranker = nil
    }
    do {
        _ = try OstwaldEscalate.run(
            manifestPath: path,
            scorer: scorer,
            exhaustLetters: exhaustLetters,
            keepSeeded: keepSeeded,
            noiseSamples: 12,
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
