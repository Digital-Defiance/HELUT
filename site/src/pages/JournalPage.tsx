import { Link } from 'react-router-dom'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'
import { Fahrenheit261Span } from '../Fahrenheit261Span'
import { TuringLiveStat } from '../TuringLiveStat'
import { enigmaPaths } from '../enigma/paths'
import { horenbergHome } from '../enigma/corpus'
import { JournalAttachments, JournalParaphrase, JournalQuote } from '../journal/JournalCite'
import {
  SELM_CREDIT,
  SELM_QUOTES,
  selmAllPublicFiles,
  selmNidInterrogation,
  selmQuelle2499,
  selmSchluesselMBauer,
  selmU3521Dossier,
  selmU534LastDays,
} from '../journal/selmSources'

export function JournalPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">
              <Link to={enigmaPaths.message} style={{ color: 'inherit', textDecoration: 'none' }}>
                Enigma · P1030680
              </Link>
              {' · '}Campaign journal
            </div>
            <h2>The ledger of an 80-year-old ghost</h2>
            <p className="byline">Jessica Mulein · mechanical arm · HELUT</p>
            <p className="lede">
              On 1 May 1945 a Kriegsmarine Enigma M4 on the training net M-Thetis enciphered a 72-letter signal. Bletchley Park did not attack this net. Daily key sheets were printed on water-soluble paper and do not survive. The ciphertext is preserved among the Hörenberg / U-534 radio and cipher papers; preservation is not proof of intended recipient.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              P1030680 remains unbroken. This page is Jessica Mulein’s operational log: a chronology of every hypothesis that failed, every control that passed, and every arm still open. Tracking what was eliminated is the public record until a key and plaintext clear the BREAK gate.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              The unified search machine is named <NaziBlaster9000Span />. <Fahrenheit261Span /> is its bounded 261-entry canonical-menu campaign. The name is blunt on purpose. The hunt is a graded Boolean search: crib exact, IC, tail, and a physically possible ≤10-plug board. Defeating Nazi Germany is the historical purpose of the work, not a caption.
            </p>
          </div>

          <div className="status-strip status-strip-4">
            <div className="stat">
              <div className="label">Indicators</div>
              <div className="value">VROL NMKA</div>
            </div>
            <div className="stat">
              <div className="label">Key-Net</div>
              <div className="value">M-Thetis (working assignment)</div>
            </div>
            <div className="stat">
              <div className="label">Ciphertext</div>
              <div className="value">72 letters (JCRSA…HVGF)</div>
            </div>
            <TuringLiveStat />
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Hard facts</div>
            <h2>What we know for sure against history</h2>
            <p>
              Not hunches. Exhaustion, archival negatives, and graded controls.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">NET</span>
              <span>
                <strong>M-Thetis, not Potsdam.</strong> Kenngruppe <code>ACH</code> names Thetis. The three recovered 1 May daily keys from other nets decrypt other U-534 traffic; against this ciphertext every message key is noise. No depth partner, no kiss, no Thetis key sheet—the Grund table is gone, so indicators buy less than one bit.
              </span>
            </li>
            <li>
              <span className="mono">ENGINE</span>
              <span>
                <strong>The campaign path works.</strong> Blind Welchman control breaks known P1030684 in six minutes with all ten plugs. Stochastic KPA recovers the same control when the template is known (oracle and near-miss). Every clean negative below is a real negative, not a broken tool. Parallel track: TensorLUT locks the unmutated M4 netlist at <em>F<sub>crypto</sub> = 0</em>; full INIT melt and stecker-cone melt shattered under λ; the live arm freezes that core and evolves a reciprocal stecker by construction.
              </span>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>Where tested, these wedges are gone:</strong> exact ≥16 catalog × rings AAAA; fuzzed top-40 × right rings; ≥16 UEBUNG heads, and their body anchors under right-ring coverage — that last one re-run on a corrected kernel and re-confirmed (40/40 dead, 0 stops). The curated exact top-30 was contaminated on 20 of its 30 placements by the table-cap bug in Phase 12 and has been re-run and re-confirmed (73 raw stops, identical to the archive, no break). Thetis-register × AAAA; training, collapse, and weather/keyboard stochastic priors under an 80% rigor bar (ceiling ~60–69% is coincidence). Shell-RIGA with free rings did not lift a wrong prior over that bar. Soft-tail UEBUNG quarantine escalate: 0 survivors. The legacy Phase 23 Regenbogen/Hannibal slices (anchor, scuttle, Hela, own-orders, filler) are not those tested exact letter-strings as a BREAK—anchor clean dead; scuttle/Hela soft-band physicals escalate to 0 survivors on the coincidence wall; own-orders AAAA all ghosts; filler AAAA below soft. That bounded history does not close the operational prior under correction-aware Future geometry. Separately, <Fahrenheit261Span />—the historical 261-entry canonical-menu/Future campaign—remains a clean local negative only for shell 0 / identity Future 0 / settings <code>0..&lt;256</code>: 6,656 checked receipts, zero positives, zero BREAK gates.
              </span>
            </li>
            <li>
              <span className="mono">OPEN</span>
              <span>
                <strong>Still open or incomplete — and still unbroken.</strong> No key, no plaintext. Resume flags below are where the hunt sits, not coverage of the whole space. The legacy target arms retain bounded, partial receipts rather than global verdicts. Tolerance 1 × right rings is suspended at <strong>3/24</strong>, with all three completed placements dead at the board; resume <code>--bombe-menus 0 --bombe-ring-sweep --bombe-garble-tolerance 1 --bombe-from 4</code>. The exact-board post-gap δ=4 arm is suspended at <strong>144/237</strong>: entries 1–110 and 112–144 are dead, and entry 111's eight raw stops yielded zero valid ≤10-plug completions; resume <code>--bombe-menus 0 --bombe-from 145</code>. Full middle × right ring coverage under the VIII-fast prior is now <strong>complete: 24/24 dead at the board</strong> — placement 1 over 4.152×10<sup>11</sup> settings at all 336 wheel orders, placements 2–24 with <strong>0 raw stops over 1.194×10<sup>12</sup> settings</strong> at 72.1M/s, nothing in quarantine. That is coverage of 42 of 336 wheel orders, not wheel-order elimination; the other 294 stay open. The four-placement P1030668 BLEIBTBESETZT context fixture is <strong>complete: 4/4 dead at the board, 0 raw stops over 2.076×10<sup>11</sup> settings</strong> at 52.3M/s (Phase 60) — still 42 of 336 wheel orders. Complete-receipt benchmarking selected <code>BANK_LANES=4</code> for <NaziBlaster9000Span />, the unified P1030680 Mulein search machine, at 276.035 receipts/s. Its Phase 51.15 preflight then completed shell 0 <code>B/beta/IV-III-VIII/AAAA</code>, setting 0, and all <strong>628 operational-prior Futures</strong>: 628/628 chunks and 16,328 receipts produced 15 host-replayed one-edge physical candidates (5 identity-family, 10 post-gap), but every candidate was non-exact, so there were <strong>0 exact hits and 0 BREAK gates</strong>. Phase 51.16 then completed settings <code>1..&lt;256</code> across all 628 Futures: <strong>10,048/10,048 new chunks, 4,163,640 checked receipts, 4,184 host-verified physical candidates, and 0 BREAK gates</strong>. Those candidates comprise 40 exact identity hits killed by ≤10-plug completion, 2,056 repaired identity hits, 41 exact post-gap hits, and 2,047 repaired post-gap hits; none produced scored plaintext, a key, or a decrypt. Candidate replay is now <strong>done for every exact candidate, and it corrected our own diagnosis</strong>. Counting the ledger gave 41 exact/no-drop post-gap candidates, 40 exact identity candidates already killed by plug completion, and 4,103 repaired. A read-only geometry-aware adjudicator then graded the 41 with no GPU at all: host replay verified 41/41, and <strong>all 41 return no-consistent-board</strong> — no ≤10-plug board satisfies the whole menu, so they never reach the language test. The missing geometry-aware decrypt was therefore never the blocker. Their six source Futures carry <strong>two to five disconnected components</strong> on 16–21 edges, one of them a zero-loop tree, which makes them split-menu ghosts of the kind documented since Phase 4 — and the campaign had already killed all 40 identity siblings the same way. <strong>All 81 exact candidates in that stripe are ghosts.</strong> Identity-family repairs with at least four forced plugs were consumed by <code>--mulein-ostwald-adapt</code> / <code>--ostwald-escalate</code> (Phases 62–64): <strong>38 then 824 then 4,101 climbed, NO BREAK</strong>. Phase 64's best −3.0390 (IC 0.0544) crib BAD beats a 12-sample floor after 3.33 million climbs; that is not a near-miss. Settings <code>256..&lt;456976</code> and other shells remain open. Also open: catalog right rings from originalIndex 418, tolerance 1 from placement 4, post-gap δ=4 from 145, and the deprioritised 300-placement long-menu remainder. Phase 65’s ranker/beam path did not greet at 72 letters. Phase 67 greets on locked P1030684; the wrong-setting ghost is crib BAD (IC 0.0509, NO BREAK). Phase 68 resumes Thetis-register × right rings from menu 14/73 — both the archival arm and this Welchman remainder stay live; 26<sup>4</sup> is not a campaign. P1030680 remains unbroken; these cleartext Float TensorLUT/Metal receipts are not FHE and supply no key or decrypt.
              </span>
            </li>
            <li>
              <span className="mono">HAPAX</span>
              <span>
                <strong>A known but dormant corpus surface was tested with historian-supplied leads, and came back clean.</strong> HELUT's August 2026 relay audit had already measured that the recurrence catalogue omits 152,938 of 154,469 distinct 16–40 letter windows and expands them to 2,691,455 legal placements; its naive 24-placement fixture was never run and the gap never reached this chronology. In September, <strong>Selm Merel Wenselaers</strong> (historian and curator, Amsterdam / Antwerp), who leads the archival arm, independently flagged the filter and supplied three historically motivated phrases. Her 15/44 legal-placement list reproduces exactly, and her highlighted starts 3 and 12 are the only single-component menus among the four tied at nine loops. The 28-placement right-ring arm is now <strong>complete: 28/28 dead at the board, zero raw stops over 4.471×10<sup>11</sup> settings</strong>, nothing reaching the plug sieve and no soft-band hit. That is a verdict on those 28 placements of the <em>recorded</em> ciphertext under right-ring coverage with the middle ring pinned — not on the phrases in general, and not on the wider hapax surface. The strings are second-net/Potsdam rather than Thetis register. The post-gap arm then came back the same way: <strong>28/28 dead, zero raw stops over another 4.471×10<sup>11</sup> settings</strong>, testing the hypothesis that a four-letter group went missing from the recording before the crib — the error Girard documented in the sister message. Both readings of the transcript are therefore closed for these placements, and neither produced so much as a stop. Tolerance 1, which tests a single mis-read letter, is measured affordable at a 7.7× cost factor with zero projected spurious stops and is the only edit hypothesis left untested for these phrases. With thanks: Wenselaers' historical selection, independent diagnosis, placement arithmetic, and menu insight made the experiment possible; HELUT's graded path turned that work into a bounded measurement. The two clean negatives are joint campaign findings, not separate contributions competing for credit.
              </span>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>The joint BLEIBTBESETZT × NEUSTADT constellation ran, and it is a clean negative.</strong> All 24 menus dead at the board: <strong>0 raw stops across 3.83×10<sup>11</sup> settings</strong> at 42.5M/s, 0 physically buildable boards, and 0 soft near-misses — nothing even reached the quarantine band. Under right-ring coverage with the middle wheel pinned, no key places both anchors at any of those alignments. This does <em>not</em> touch the underlying history: what was falsified is the narrow claim that both strings sit verbatim in this ciphertext at those offsets, not the archival finding that Neustadt transfer and scuttling were stages of one process. Residual scope, printed rather than buried: the pinned middle wheel leaves roughly 12–23% of keys untested across these 40–67 letter spans, so this is a negative over a large majority of the space, not a proof of absence.
              </span>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>The VIII-fast middle-ring arm ran to completion, and it is a clean negative.</strong> All 24 strongest-plus-diverse placements dead at the board. Placement 1 had already died over 4.152×10<sup>11</sup> settings at the full 336 wheel orders; placements 2–24 under the rotor-VIII-fast prior added <strong>0 raw stops across 1.194×10<sup>12</sup> settings</strong> at 72.1M/s, 0 physically buildable boards, and 0 soft near-misses. The engine still reported no residual ring gap, so middle and right coverage is intact for those 42 orders. <strong>It still eliminates nothing about the other 294 wheel orders</strong> — this reordered the search, and a negative here is not wheel-order coverage. Three nets is a thin sample; they may have drawn from a shared key table rather than choosing freely. That remains a historical question, and the archival ask is unchanged: if central assignment is documented, 42 orders become the space rather than the head of a queue.
              </span>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>The four-placement P1030668 BLEIBTBESETZT context fixture ran, and it is a clean negative.</strong> All 4 menus dead at the board: <strong>0 raw stops across 2.076×10<sup>11</sup> settings</strong> at 52.3M/s (3,972 s), 0 physically buildable boards, and 0 soft near-misses — nothing even reached the quarantine band. Each menu was the exact 40-letter radio window <code>UHRJKIELWEINGELAUFENYFFFTTTBLEIBTBESETZT</code> at offsets 30, 27, 17, and 7: 40 edges, 18 loops, one component, middle and right rings unpinned under the VIII-fast prior. This does <em>not</em> touch the P1030668 radio finding; what was falsified is those four alignments sitting verbatim in this ciphertext under that coverage. Residual scope, printed rather than buried: 42 of 336 wheel orders. The short 19-letter core was never swept solo, and the joint constellation with <code>NEUSTADT</code> remains the Phase 56.1 pinned-A negative.
              </span>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>Identity-family one-edge repairs from the bounded stripe were climbed, including split-menu trees, and they are a clean negative.</strong> Phase 62: 38 single-component repairs, <strong>NO BREAK</strong>, best −3.6976 versus a random-setting floor of −3.4564. Phase 63: <code>--mulein-ostwald-split-menu</code> emitted 824 identity-family repairs with at least four forced plugs; Metal Ostwald (exhaust 6 / depth 2 / top-up 4, 8 GB unified) climbed them in one second at 4.6M decrypts/s. <strong>NO BREAK</strong>: 824/824 crib BAD, best −3.4797 versus −3.4564 (Δ −0.0233), IC 0.0395 — still below the floor. Scope is shell 0, settings <code>1..&lt;256</code> only. Log <code>logs/campaign-mulein-ostwald-metal.log</code>. This is not a decrypt. P1030680 remains unbroken.
              </span>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>CPU Ostwald climbed every remaining repair on the bounded stripe, including empty boards and gapped post-gap walks, and it is a clean negative.</strong> <code>--mulein-ostwald-family both --mulein-ostwald-split-menu --mulein-ostwald-min-pairs 0</code> emitted 4,101 identity and gapped post-gap repairs. 3,329,721 climbs finished in 1,779 s at 1.3M decrypts/s. <strong>NO BREAK</strong>, 4101/4101 crib BAD. Best −3.0390 (IC 0.0544, tail −3.0390) at <code>B/beta/IV-III-VIII/AAAA</code> AAIP/AAIT — twin garbage decrypts. That score beats a 12-sample random-setting floor (−3.4564), which is what taking a maximum over 3.33 million climbs does; it is not a near-miss. IC misses 0.055. Log <code>logs/campaign-mulein-ostwald-cpu-everything.log</code>. Not a decrypt.
              </span>
            </li>
            <li>
              <span className="mono">OPEN</span>
              <span>
                <strong>The 2026 Ostwald path is built. A 72-letter curve did not greet, so it is not pointed at P1030680.</strong> A leave-one-out linear ranker, a beam climb, unlocking all forced plugs with <code>--ostwald-keep 0</code>, and <code>--ostwald-all-settings</code> (every message key on one locked shell, no IC sieve) replace searching a broken scorer faster. Full curve on 30 round-tripping controls: greedy <strong>5/30 (17%), median −1.2000</strong>; decoy-climb fit <strong>1/30, −1.7306</strong> (worse); beam 4 <strong>6/30, −1.0925</strong>. Median plugs 1/10. The 6-control smoke (2/6) overstated the win rate. That is not a zero crossing.                 Logs <code>logs/ostwald-curve-ranker-72.log</code>, <code>logs/ostwald-curve-ranker-decoy.log</code>, <code>logs/ostwald-curve-ranker-beam4.log</code>.
              </span>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>Four-plug hot-letter brute cannot seed Ostwald from ciphertext frequency.</strong> Four correct plugs still flip the 72-letter sign (Phase 50.6), but those four are not among the eight hottest ciphertext letters on any of 32 round-tripping controls. <code>--ostwald-brute-plugs 4 --ostwald-exhaust 8</code> enumerates 105 perfect matchings and scores <strong>1/30 wins, median −0.1633</strong>, 0/10 plugs. An unclimbed true 4-plug is a moderate trigram outlier against 2048 random 4-plug boards (8/12 beat the random max) and is still buried in the 164-million-board tail. Metal can hold that enumeration; it cannot invent the plugs. Logs <code>logs/ostwald-curve-brute4-e8.log</code>, <code>logs/ostwald-brute-probe.log</code>.
              </span>
            </li>
            <li>
              <span className="mono">OPEN</span>
              <div>
                <span>
                  <strong>Quelle Tafel A pairs are photographed. The May plan is a different Prüfnummer.</strong> Crypto Museum Doppelbuchstabentauschtafeln Prüfnr. 2499, pp. 3–4, shows <code>VR→ES OL→AE NM→CD KA→HM</code> and the control maps <code>FN→KY HC→DM GV→UU ET→ZZ</code>. So <code>VROL NMKA → EACH/SEDM</code> is no longer only a recovered mapping. 1 May table <em>selection</em> remains Tauschtafelplan Bruno Prüfnr. 1772a. The 2499 cover assigns that set's plan the same Prüfnr. Edition compatibility is not demonstrated; <code>discovery_eligible</code> stays false.
                </span>
                <JournalAttachments
                  kicker={`Attachment · ${SELM_CREDIT}`}
                  files={[selmQuelle2499]}
                />
              </div>
            </li>
            <li>
              <span className="mono">OPEN</span>
              <span>
                <strong>The 164-million 4-plug alphabet climb greets on the true P1030684 setting. The wrong-setting ghost is crib BAD.</strong> True VYAA / index 385320: 164,038,875 streamed starts, 313 Metal waves, <strong>~37.8 min at 36.3M/s</strong>, <strong>1 candidate clears the break bar</strong> — crib ok, IC 0.0657, tail −2.9671, 10 pairs, the known 72-letter window. Log <code>logs/ostwald-fourplug-p1030684-true-385320.log</code>. Ghost AAAA / index 0: 2026-09-24T17:30:26Z → 18:08:27Z, <strong>~38.0 min at 36.2M/s</strong>, crib BAD, IC 0.0509, tail −3.0462, <strong>NO BREAK</strong>. Log <code>logs/ostwald-fourplug-p1030684-wrong-0.log</code>. Known-key pair, not P1030680. A handful of locked P1030680 settings is eligible as a 38-minute confirmation; never 26<sup>4</sup>. Phase 68 spends the GPU on Thetis-register rings instead of one random AAAA ticket.
              </span>
            </li>
            <li>
              <span className="mono">OPEN</span>
              <div>
                <span>
                  <strong>Bauer’s May 1945 Hydra sheet and Quelle Tafel D are in the scan. Neither is loaded onto P1030680.</strong> Selm Merel Wenselaers recovered the Hellschreiber PDF of <em>Ultra versus Enigma</em>. She reports Appendix F (p. 314) as Schlüssel M Hydra for May 1945, and Appendix G (p. 315) as Tafel D, Kennwort Quelle, Prüf-Nr. 2409. Hydra plugs are not Thetis plugs. Tafel D is not applied to <code>VROL NMKA</code>. The archival ask is now M.Dv.Nr. 98 / the K-Buch, not another pass over this ciphertext. <code>FORT</code> is a four-letter procedure word; it cannot clear the 16-letter crib bar, and it is not queued.
                </span>
                <JournalAttachments
                  kicker={`Attachment · ${SELM_CREDIT}`}
                  files={[selmSchluesselMBauer]}
                />
              </div>
            </li>
            <li>
              <span className="mono">ELIMINATED</span>
              <span>
                <strong>Three classical human methods tested against our own data, and all three are dead.</strong> <em>Cillies</em> — Bletchley's most productive lever was operators choosing lazy message keys. Measured across the 47 recovered keys: 11 of 47 carry a repeated letter against a uniform expectation of 10.2, and per-position letter frequencies are flat. These operators randomised properly; there is no habit to exploit, and that is now a measurement rather than an assumption. <em>The indicator system</em> — the message key is a function of the daily key and the Grundstellung, and that mapping is a bijection, so trading an unknown message key for an unknown Grund reduces the space by exactly nothing. <em>Banburismus</em> — needs two messages in depth, and the target has no partner, which is the founding problem of this whole campaign.
                {' '}
                We also mined the expanded corpus for new cribs and found 480 mechanically strong hypotheses, some reaching 20 loops — as strong as the best menus we have. They will not be run. Their provenance is wrong: Graf Spee is 1939, one is a Swedish-intercepted lightship position report, another is U-boat provisioning from November. None is Baltic training register from May 1945. Running them would repeat this campaign's most-tested mistake, the imported-register wedge, which has been negative in every arm to date. A 20-loop menu aimed at the wrong hypothesis is only efficiently wrong.
              </span>
            </li>
            <li>
              <span className="mono">REFRAME</span>
              <span>
                <strong>72 letters is enough — the barrier is our search, not the message.</strong> The full M4 key (wheels, rings, position, ten-plug board) is about <strong>2<sup>86</sup></strong>. Seventy-two letters of German carries roughly <strong>230 bits</strong> of redundancy, putting unicity distance near <strong>27 letters</strong>. We sit at about 2.7× that. So exactly one key yields German, by a wide margin, and every negative on this page is an <em>estimation</em> failure rather than a shortage of information. An independent check confirms the estimator is what binds: a from-scratch Enigma simulator plus leave-one-out n-grams, grading the truth against genuine wrong-key decrypts with the plugboard climbed symmetrically, reproduces the standing negative (median margin −0.053 at 72 letters) from a completely separate implementation.
                {' '}
                <strong>One trap worth publishing.</strong> The first version of that measurement reported a positive margin and a 100% win rate — an apparent breakthrough. The bug was handing the true plugboard to the truth <em>and</em> to every decoy, which is grading with the answer key. Forcing the board to be earned at every candidate moved the result from +1.14 to −0.044. That correction is the entire difficulty of the problem.
                {' '}
                It also sets the priority: the plugboard was a <em>daily</em> setting, so a second Thetis signal would constrain the same board with 144 letters instead of 72, and four correct plugs already flip the margin positive. Archival discovery outranks more sweeping.
              </span>
            </li>
            <li>
              <span className="mono">METHOD</span>
              <span>
                <strong>Constellation menus: two attested anchors, one menu, no invented sentence.</strong> The doctrine was already on the record: Neustadt transfer and scuttling are linked stages, so their strings must compete independently and must never be concatenated into a sentence nobody sent. The machinery now matches it. A <em>constellation</em> is one joint hypothesis that unions only the absolute <code>(step, plaintext, ciphertext)</code> board constraints of separate anchors and <strong>asserts no plaintext in the gap between them</strong>. That is what finally lets the 8-letter <code>NEUSTADT</code> contribute at all, since it is far too short to sweep on its own. <code>FFFTTTBLEIBTBESETZT</code> × <code>NEUSTADT</code> gives <strong>24 single-component rows, 27 edges and 7–9 loops each</strong>, with the topology cross-checked between an independent union-find and the board, and a test that fails loudly if either string ever stops being verbatim in the corpus. Priced at 3.83×10<sup>11</sup> settings, about 2.8 h.
                {' '}
                <strong>Loops are not free, which is why the coverage caveat above exists.</strong> A 27-edge contiguous crib spans 27 positions. These constellations span 40–67, because the anchors sit far apart — and span, not edge count, is what a middle ring pinned at A fails to cover. The engine's own banner reports <strong>~12% of keys uncovered for one middle-wheel notch and ~23% for two</strong> on a 67-letter span, against a few percent for a compact crib. The extra deduction power the joint menu buys is partly paid for in a wider blind spot.
              </span>
            </li>
            <li>
              <span className="mono">NEXT</span>
              <span>
                <strong>For the first time, we can name a single document that would change the mechanics — not another crib.</strong> Five mechanical routes closed in one day (the constellation pairing, the basin estimator, corpus volume, operator key habits, and the indicator system), against one ordering prior and one reframe. The pattern is the finding: every closed route was mechanical, and the arithmetic now ranks archives above compute. The plugboard was a <em>daily</em> setting, four correct plugs flip the statistics from hopeless to solvable, and a second same-day message would constrain the same board with 144 letters instead of 72. No sweep we own competes with that.
                {' '}
                So the ask has a specific target: <strong>the 1 May 1945 Kriegsmarine key table — did it assign wheel orders centrally across nets, or did each net draw independently?</strong> All three nets broken that day used the same fast rotor, which we are currently forced to treat as a mere ordering hint. If central assignment is documented, that hint becomes a hard constraint and the search space genuinely shrinks eightfold; if nets chose freely, it stays a weak hint and we keep paying full price. Either answer is worth having, and only an archive can give it. That is a question a single document settles, which is what makes it worth a journey. Bauer's Appendix F is now in the linked scan: a Hydra May 1945 plugboard sheet, not the wheel-order table, and not loaded onto P1030680. Identity-family Ostwald against the bounded stripe is now another closed mechanical route (Phases 62–64, including Metal on split-menu seeds and CPU on every remaining repair); it does not change that ranking. Live mechanical plan (Phase 67): the true P1030684 4-plug greeting is <strong>done</strong> (crib-exact, known plaintext); the wrong-setting ghost control is running. Archives still outrank more sweeping of this ciphertext. Tafel A pairs are now photographed in Prüfnr. 2499; the May plan is still 1772a.
              </span>
            </li>
            <li>
              <span className="mono">ARCHIVE</span>
              <div>
                <span>
                  <strong>A photographed U-3521 war diary gives us the Baltic training environment — and its custodian was careful to say what it is not.</strong> Wenselaers recovered the complete U-3521 material including photographs of surviving KTB pages rather than forum transcriptions. The boat begins Agru-Front training on 2 April, and a 9 April entry records <code>Auf Sehrohrtiefe (FT-Programmzeit)</code> — scheduled radio reception at periscope depth, which is the concrete form of the broadcast layer we had only inferred. The final pages document preparations for scuttling on 30 April and 1 May, the crew leaving on 2 May except for the demolition party and travelling to Neustadt, and the boat scuttled on 3 May.
                  {' '}
                  <strong>She also reported the absence first.</strong> There is no second Thetis transmission in the dossier, and she declined to oversell it. Two sources, two claims, kept apart. So this is procedural context, not evidence that U-3521 itself used Thetis.
                  {' '}
                  One trap worth flagging before anyone walks into it: a DEFE signal places U-3014, U-2538 and U-3024 together at Travemünde on 1 May, which looks like corroboration for the boat-number cribs we withdrew. It is not. That withdrawal rested on the raw sister copies not carrying those number strings cleanly — a transcription fact the DEFE material does not touch. Boats sharing a harbour is not a letter string in this ciphertext. The withdrawal stands.
                </span>
                <JournalQuote speaker={SELM_CREDIT} source="U-3521 source dossier, 24 September 2026">
                  {SELM_QUOTES.thetisRefusal}
                </JournalQuote>
                <JournalQuote speaker={SELM_CREDIT} source="U-3521 source dossier, 24 September 2026">
                  {SELM_QUOTES.neustadtSeparation}
                </JournalQuote>
                <JournalQuote speaker={SELM_CREDIT} source="U-3521 source dossier, 24 September 2026">
                  {SELM_QUOTES.dossierHierarchy}
                </JournalQuote>
                <JournalAttachments
                  kicker={`Attachment · ${SELM_CREDIT}`}
                  files={[selmU3521Dossier]}
                />
              </div>
            </li>
            <li>
              <span className="mono">ARCHIVE</span>
              <div>
                <span>
                  <strong>The historical arm is now active team work, and it changes the model without pretending to prove it.</strong> Wenselaers reports a concrete Volksliste III process from DEFE and the original U-3521 KTB: demolition parties remained aboard while crews transferred to the 3. U-Lehrdivision at Neustadt. That makes Neustadt and scuttling linked stages rather than competing scenarios. The repository independently confirms <code>FFFTTTBLEIBTBESETZT</code> exactly in P1030668 and the corrupted <code>FFFTTTBLEIBTBESEOZTX</code> sister reading in P1030707; the proposed clean U-3024/U-2538 strings are withdrawn after raw-copy recheck. The reported <code>KLAR ZUM VERSENKEN GEM. BEFEHL.</code>, U-3521 <code>FT-Programmzeit</code>, DEFE references, and changing Aegir/Thetis allocation lists remain source-reported pending scans, exact message IDs, and chronology. P1030680's working net stays M-Thetis, but the later allocation-list provenance and the intended recipient are now printed as open. An exact 40-letter P1030668 radio context gives four single-component 18-loop menus and is <strong>complete: 4/4 dead, 0 raw stops over 2.076×10<sup>11</sup> settings</strong> under the VIII-fast middle-ring coverage that came back empty on the strongest catalog menus (Phase 60). Phase 61 holds VIII-fast as an ordering prior: NARA key-log requests, R.I.P. 401 non-random sheets, and a 3 May Kenngruppen test are live archival lines with no receipts yet. Not another invented sentence, and not a Girard-named-class weighted Mulein board.
                </span>
                <JournalQuote speaker={SELM_CREDIT} source="The last days of U-534, 23 September 2026">
                  {SELM_QUOTES.notForU534}
                </JournalQuote>
                <JournalAttachments
                  kicker={`Attachment · ${SELM_CREDIT}`}
                  files={[selmU534LastDays]}
                />
              </div>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Chronology</div>
            <h2>Hunting the true key, step by step</h2>
            <p>
              The first instinct against a cipher this old is to let a computer guess. That is what Enigma was designed to defeat. What follows is the chronological record of the attack on P1030680 — not a claim that the signal was addressed to U-534.
            </p>
          </div>
          <div className="timeline">
            <article className="tl-item">
              <div className="when">Phase 0: The False Start</div>
              <h3>Statistics cannot search; they only rank.</h3>
              <div className="prose">
                <p>
                  Before I built my current Boolean engine, I treated this like a modern computing problem. I threw statistical models, genetic algorithms, and massive computing power at the ciphertext, running Gillogly-style outer shell searches. I hoped the computer would simply "evolve" the right answer by scoring how closely the output resembled German syntax.
                </p>
                <p>
                  It failed completely. When a message is only 72 letters long, and the Enigma plugboard (the <em>Steckerbrett</em>) offers roughly 47 bits of freedom, statistical gradients hallucinate. The algorithm would proudly present a high-scoring string of letters that looked like German, but was actually pure mathematical noise. I proved this by running a control test on a known, solved message (P1030684): the statistics favored false positives over the true key. I learned my first major lesson: statistics cannot search an Enigma space; they can only rank a tiny list of survivors. I retired the AI and went back to the history books.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 1: The Archives</div>
              <h3>History is cheaper than compute.</h3>
              <div className="prose">
                <p>
                  Before spinning up the graphics cards again, I scraped the historical archives. I pulled a corpus of 50 message pages intercepted from U-534 on that exact same day: 48 broken M4 messages, one hand-cipher, and exactly one unbroken Enigma message—mine. The pages are hosted by{' '}
                  <a href={horenbergHome} target="_blank" rel="noreferrer">
                    Michael Hörenberg
                  </a>
                  . That scrape is now public on the{' '}
                  <Link to={enigmaPaths.corpus}>U-534 corpus</Link> page, with the JSON available to download.
                </p>
                <p>
                  I was hunting for a lucky break. Did the operator accidentally re-send a message that was already broken (a "kiss")? I tested all 72 possible alignments, but the survival rate matched pure random chance. Did they reuse a daily key from another network like Potsdam or Plaice? I exhausted all 456,976 possible message keys against the three recovered daily keys from those networks, and found nothing but the noise floor (a bigram score of ≈ −212).
                </p>
                <p>
                  I even tried to use the historical indicators (<code>VROL NMKA</code>) to narrow the search. However, because the starting position table (the <em>Grundstellung</em>) was lost to history, those indicators only collapsed the search space by a factor of 1.92×—less than a single bit of information.
                </p>
                <p>
                  The target message stood entirely alone. However, this archival dig gave me my ammunition. By studying the 48 broken messages, I extracted highly probable, formulaic German naval phrases (cribs). Words like <code>UUUFLOTTX</code> (U-Flotilla), <code>KOMXADMXU</code> (Commanding Admiral), and <code>TRAVEMUE</code> (Travemünde). I generated a catalog of 100 cribs mapped to 2,513 potential legal placements to use as my attack wedges.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 2: The Boolean Engine</div>
              <h3>A Metal Welchman board.</h3>
              <div className="prose">
                <p>
                  Statistics were retired. In their place: a Metal-accelerated Gordon Welchman diagonal board. It tests for Boolean contradiction and rejects physically impossible rotor states at roughly 45 million settings per second — close to double that once the middle-ring coverage skip lets most lanes exit early.
                </p>
                <p>
                  The software is pinned to 1945 hardware. The Greek wheel does not step on a 72-letter message, and the left rotor’s notch drives nothing, so both are held. That Turing-shaped reduction collapses the search by 676.
                </p>
                <p>
                  A rehearsal run on a known message (P1030684) proved the <em>board</em> is perfect: if I hand it the true shell and a 16-letter phrase, the true key is the absolute only survivor out of 456,976 possible settings. What that rehearsal did <em>not</em> grade was the full campaign path—336 rotor orders, Greek wheels, reflectors, ring phases. That gap is Phase 11.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 3 & 4: The Ghost Problem</div>
              <h3>Reality beats mathematics.</h3>
              <div className="prose">
                <p>
                  During my first major sweep, I thought I had cracked it. I tested the common naval phrase <code>UUUVIRSIBENNULEINS</code> at the very beginning of the message (offset 0). The GPU returned 12 surviving rotor states where the logical math worked perfectly.
                </p>
                <p>
                  But a physical 1945 Enigma operator only had exactly 10 cables to plug into their machine. When my script took those 12 mathematical survivors and tried to map the remaining letters to see if they fit within that strict 10-cable limit, every single one of them failed. My digital forensics showed that the menu was mathematically "split," meaning one cluster of letters admitted zero valid starting seeds. They were "ghosts"—mathematical flukes that failed basic physics. I immediately built an automated, inline kill chain into my engine to permanently catch these false positives as they drain off the GPU.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 6: The False Alarm</div>
              <h3>Tightening the net.</h3>
              <div className="prose">
                <p>
                  Later in the campaign, the system halted, bells ringing, claiming a break at menu 627. It was testing a 14-letter phrase: <code>KOMXADMXUUUBOO</code> at offset 29.
                </p>
                <p>
                  Because the phrase was too short, it didn't provide enough logical constraints. The GPU generated a staggering 193 million raw false positives, and 2,118 of those actually physically fit the 10-cable limit. One of those random garbage strings just happened to chain enough letters together to barely trick my linguistic scanner, generating a tail score of −4.070 (just 0.044 points above my threshold).
                </p>
                <p>
                  It was a complete hallucination. I tightened my defenses instantly. I dropped all 1,627 cribs shorter than 16 letters from the queue, raised my scoring threshold to a strict −3.600, and added an Index of Coincidence (IC) gate requiring a baseline of 0.055 to automatically filter out random noise. I resumed the sweep of the remaining 259 menus and finished with a clean negative.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 8: The Turnover Sweep</div>
              <h3>Exact cribs, clean negative.</h3>
              <div className="prose">
                <p>
                  My baseline sweeps proved the target isn't hiding in the easy, stable sections of the machine. The true key — if these cribs are present — lives where the middle rotor clicks forward mid-message (the turnover).
                </p>
                <p>
                  A full <code>--bombe-ring-sweep</code> across every placement long enough to test would take roughly 4 days, so I curated a surgical strike: the 30 highest-probability menus, openings first, then maximum loop connectivity. The GPU finished the hunt. Result: 73 raw stops, zero boards that fit 10 physical plugs, across nearly 5×10¹¹ settings. The exact historical phrases at those offsets are not in this message.
                </p>
                <p>
                  <strong>Two caveats added later.</strong> Because I curated this set for long, strong menus, 20 of these 30 placements turned out to be exactly the ones the kernel table cap was quietly mis-reporting (Phase 12). And when I went to re-run it, I found the archived log for this arm is <em>truncated at menu 6 of 30</em> and contains no summary at all — the 73 stops and 4.79×10<sup>11</sup> settings I quoted above had never actually been written to disk. Same buffered-<code>tee</code> truncation that cost me the fuzzed arm.
                </p>
                <p>
                  The re-run settles both. Identical coverage-sensitive figures — 73 raw stops over 4.79×10<sup>11</sup> settings — so the lanes the old cap had been discarding produced <em>zero</em> additional survivors. Best board scores IC 0.041 and a tail of −4.819, far under the 0.055 and −3.600 bars. No break. The negative stands, and this arm finally has a receipt.
                </p>
                <p>
                  One number did move, and it is worth being precise about why: scored completions went from 0 to 35. That is not new coverage, it is a different scoring surface. Phase 8 predates both the head-reading gate I added after Phase 11 and the quarantine soft IC floor from Phase 22. Under those two later additions, 35 boards get far enough to be scored at all; under Phase 8's strict whole-message gate, none did. The raw stop count is the number that tracks coverage, and it did not budge.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 9: Fuzzy Cribs</div>
              <h3>Hunting operator error.</h3>
              <div className="prose">
                <p>
                  A clean negative on exact register language points at human error—the kind of typo, non-standard abbreviation, or header padding that shatters rigid Welchman logic without changing the underlying key. I built a fuzzed crib generator upstream of the engine: header offsets ±1/2/3, Kriegsmarine signal contractions, phonetic slips, and single-letter Hamming probes, all still gated at 16+ letters and the self-encipherment law.
                </p>
                <p>
                  Rings-AAAA on 400 fuzzed menus came back clean: a quarter-million raw stops, zero physical boards. Almost all of that stop mass was a weak <code>XX</code>+<code>KOM</code> Hamming swarm—split menus, same ghost pathology as before. I curated the useful remainder for a turnover sweep. The Boolean board stays untouched; only the wedge changes.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 10: The Fuzzed Turnover Sweep</div>
              <h3>Operator-error cribs, clean negative.</h3>
              <div className="prose">
                <p>
                  I launched a ring sweep on the curated top-40 fuzzed menus and wrongly treated the log as finished. An audit showed the process had died at menu 18 of 40—half an arm, not a result. Menus 19 through 40 went back on the GPU under the head-reading gate.
                </p>
                <p>
                  They finished clean: every remaining menu dead at the board, zero raw stops across 3.5×10¹¹ settings. Combined with the first eighteen, that is a real negative on all forty curated fuzzed placements. Orthographic noise on Potsdam register language is not hiding the key under right-ring coverage.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 11: The Blind Control</div>
              <h3>I stopped trusting my own machine.</h3>
              <div className="prose">
                <p>
                  A day of GPU time had produced nothing but clean negatives, and I asked myself the only question that mattered: have I ever actually fed a <em>valid</em> key into this system and watched it come back out? I went looking, and the answer was no—not really.
                </p>
                <p>
                  My rehearsal test was rigged in my favor. It handed the Bombe the correct rotor order, the correct reflector, and the correct ring settings, then asked it to find only the four-letter starting position. But my real campaigns search 336 rotor orders × 2 Greek wheels × 2 reflectors × 26 ring phases on top of that. All of that outer machinery—the part that had produced every single negative result—had never once been graded against an answer it wasn't told.
                </p>
                <p>
                  So I built a blind control. I took P1030684, a message from the same day whose key is published, lifted a 27-letter crib from its known plaintext, and fed it to the full campaign as if it were the unbroken target. No shell, no rings, no plugs—nothing but ciphertext and a guess at one phrase.
                </p>
                <p>
                  It broke it in 361 seconds—the archived log reads 427 s, because 361 s was the first run and the log was overwritten by a re-run after head scoring was added; the 427 s figure is the reproducible one. Out of 16 billion settings the engine surfaced exactly two, and one of them was the truth: reflector B, Greek gamma, rotor order IV-III-VIII, and all ten historical plugboard cables—<code>BQ CH DI EJ GL KP NV OU SZ TY</code>—followed by 119 letters of clean naval German. It even reported the rings as <code>AAAH</code> instead of the historical <code>AACU</code>, which is not an error but a proof: those two settings are mathematically the same machine, and watching my engine land on the equivalent form confirmed that the 676× shortcut I built on Turing's reduction is sound.
                </p>
                <p>
                  That is the answer to the question. The engine works as advertised. Every negative in this ledger is a real negative. Pointed at a key that is actually there, it finds it in six minutes.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 12: The Audit</div>
              <h3>The good news cost me my headline.</h3>
              <div className="prose">
                <p>
                  Validating the engine was the easy half. The hard half was auditing what I had actually eliminated—and there my own log messages had been lying to me.
                </p>
                <p>
                  My sweep printed <em>"turnover phase fully covered, elimination is complete"</em> whenever I swept the ring settings. That was too strong. Sweeping the fast rotor's ring covers every phase of <em>its</em> turnover, but I kept the middle ring pinned at A, and that shortcut only holds while the middle rotor doesn't click over inside the crib itself. At this point in the chronology, no target run had tested another middle ring; roughly 8% to 15% of the key space had never been on the board. Phase 51.12 below records the first partial target run into that gap.
                </p>
                <p>
                  A third overclaim surfaced later, and it is worse than the other two because it wore the language of a result. The Metal kernel builds one rotor-path table per distinct slow-wheel state a menu span reaches, and it capped that at four. When a lane needed a fifth, the kernel wrote a zero survivor mask — which my driver reads as <em>eliminated</em> — for a lane it had never actually tested. A cap on a lookup table was printing clean negatives.
                </p>
                <p>
                  I bounded it with stepping arithmetic rather than guesses: every span in every fixture I have ever run, all 56 naval middle/right rotor pairs, all 676 windows, no GPU required. It never fires at or below 25 letters. At 28 letters it silently eliminates 0.29% of lanes, at 30 letters 1.14%, and at 40 letters <strong>5.56%</strong>.
                </p>
                <p>
                  The damage is not spread thinly — it sits on exactly the arms I curated for long, strong menus. My Übung body-anchor arm is forty menus of forty letters each, and its result was "0 raw stops, every menu dead at the board," which is what let me close the Übung-push hypothesis. <strong>All forty were contaminated.</strong> That negative was unearned as I recorded it. The cap is now eight and overflow reports <em>undecided</em>, which the host re-tests in full on an engine that has no such limit.
                </p>
                <p>
                  So I re-ran it. Forty of forty still dead at the board, zero raw stops across 6.39×10<sup>11</sup> settings, five and a quarter hours. The lanes the old cap had been quietly discarding got tested and died too — the bug was not hiding a key here, and the Übung-push hypothesis stays closed, this time on evidence. The curated top-30 was also re-run later: 73 raw stops over 4.79×10<sup>11</sup> settings, identical to the archived count, zero extra survivors, no break. The main catalog's 300 contaminated placements are retained but deprioritised. The Regenbogen queue is clean. Everything at 16 to 25 letters — the large majority of the catalog, and all of the Thetis-register work — was never affected and stands.
                </p>
                <p>
                  Worse, I went back through the terminal history and found my fuzzed turnover sweep had been killed at menu 18 of 40—I had been treating half an arm as a finished negative. I finished that arm properly (Phase 10: clean). And of my 2,513 catalog placements, only 886 were ever long enough to test—and of those 886, about <strong>182</strong> have had genuine ring coverage, plus the 54 curated ones. My "clean negative on the full catalog" was a negative across roughly a fifth of the ring space.
                </p>
                <p>
                  I fixed the log line so the machine reports its own gap honestly. I would rather have an uncomfortable ledger than a flattering one.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 13: The Suspicion</div>
              <h3>My cribs may be from the wrong navy desk.</h3>
              <div className="prose">
                <p>
                  Then I noticed something in my own archival table that reframes the entire hunt. My corpus holds 48 broken messages: 31 from the Potsdam net, 16 from a second net, 1 from a third. Not one of them is M-Thetis.
                </p>
                <p>
                  P1030680 is the only Thetis message in the scrape—that is precisely why it is still unbroken eighty years later. Which means every crib I have driven into it, all 100 of them, is register language borrowed from <em>other networks' traffic</em>. Thetis was a training net that Bletchley Park never bothered to work. If Thetis operators didn't open their messages the way Potsdam operators did, then no amount of ring coverage or fuzzed spelling will ever help, because the wedge itself is the wrong shape.
                </p>
                <p>
                  That is not a reason to stop. It is a reason to reorder: finish the cheap arms, then stop asking the message to speak Potsdam.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 14: The Head-Gate Re-read</div>
              <h3>The answer was not already in the logs.</h3>
              <div className="prose">
                <p>
                  I re-swept every exact crib of 16 letters or longer under rings AAAA with the new head-reading gate—868 menus, half a trillion settings. Result: three physically valid ten-plug boards, zero breaks. The best candidate scored IC 0.051 and a trigram tail of −4.837, under both bars. The head reading did not resurrect a true key from the turnover-free slice.
                </p>
                <p>
                  That closes the cheap hope that I had already thrown the answer away. Exact historical cribs are eliminated under rings AAAA for real. What remained was the expensive half—or opening a Thetis-shaped wedge instead of more Potsdam.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 15: The Park</div>
              <h3>I stopped the four-day sweep on purpose.</h3>
              <div className="prose">
                <p>
                  I started the exact ≥16 catalog ring sweep, then parked it at menu 57 of 868—all dead at the board so far—in <code>logs/campaign-catalog-rings.log</code> to chase Übung. That arm later cleared through menu 202 (still all dead), paused for Regenbogen/Hannibal (Phase 23), resumed from 203/257/265, and is now parked at originalIndex <strong>417</strong>/2513—last line <code>VVVUUUDREINULEINSVI@25</code>, still all dead, resume <code>--bombe-from 418</code>. I was not going to spend those days forcing Potsdam register onto a training net while a Thetis-shaped opening was still untested.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 16: UEBUNG</div>
              <h3>Stop speaking Potsdam. Try a training header.</h3>
              <div className="prose">
                <p>
                  Arm 1: forty-six ≥16 <code>UEBUNG</code>/<code>FUNKUEBUNG</code> pads at offsets 0–2 under rings AAAA—zero physical boards. Those exact training openings are not at the absolute head in the turnover-free slice.
                </p>
                <p>
                  Arm 2: short headers paired with mid-message body cribs under confirm-2. All forty ≥16 body anchors died at the board under AAAA, so agreement was already impossible. The short menus then stalled the host on tens of millions of ghost completions; several printed “clears the bar” on prefix flukes while their whole-message IC and tail still failed. I aborted and taught confirm mode to only re-test shells a ≥16 anchor already locked. Ring-sweep of those bodies: 40/40 dead at the board, zero raw stops. The “header pushes the body back” claim is exhausted under right-ring coverage.
                </p>
                <p>
                  Every one of those forty anchors is a forty-letter menu, which later turned out to be precisely the length the kernel table cap was mis-handling (Phase 12) — so this whole arm was contaminated, and I had closed the Übung-push hypothesis on a result I had not earned. I re-ran it on the corrected kernel: <strong>40/40 still dead at the board, zero raw stops across 6.39×10<sup>11</sup> settings</strong>, five and a quarter hours. The conclusion holds. It just holds on evidence now.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Phase 17: Thetis Register</div>
              <h3>Not Potsdam. Not more UEBUNG. Try the training desk.</h3>
              <div className="prose">
                <p>
                  With Übung-push exhausted, I probed Kenngruppe drill from this message’s own keying material—<code>ACH</code>, <code>SEDM</code>, <code>OEDM</code>—and school/training openings like <code>AUSBILDUNG</code>, <code>LEHRGANG</code>, <code>ANALLEFUNKSTELLEN</code>, at the head, length ≥16. AAAA: three physical boards, zero breaks. Best candidate IC 0.041 / tail −4.903. Right-ring sweep of that set was parked at menu 13 of 73—all dead or unscorable so far. Resume is <code>--bombe-from 14</code>.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Phase 18: Stochastic Bombe</div>
              <h3>Match the template. Do not score German-ness.</h3>
              <div className="prose">
                <p>
                  Turing’s Bombe eliminated impossible keys with a known crib: boolean death by contradiction. Eighty-five years later I can do the reverse—because the GPU can score millions of keys that are merely <em>better</em>, not only keys that are impossible. The Stochastic Bombe keeps a hypothesized plaintext fixed (or a small template bank) and evolves the daily key until the decrypt matches letter-for-letter. That is not brute-forcing 26<sup>72</sup> plaintext; it is searching the key space under an exact-match objective. German n-grams are irrelevant—Thetis need not look like Potsdam.
                </p>
                <p>
                  The Metal cleartext batch already runs this on the GPU: 26 Greek windows × 17,576 L/M/R lanes per stecker. Control on the first 72 letters of known P1030684 proves the datapath: oracle stecker recovers plaintext and message key <code>VYAA</code> in ~0.2s; drop one true plug and hill-climb climbs 65→72. Cold blind stecker search only reached 22/72 in forty generations—more gens will not melt a false peak in a 10<sup>14</sup>-sized plugboard. Near the truth the landscape is sharp; far away it is full of traps.
                </p>
                <p>
                  What will break P1030680 is not “evolve harder” on an empty template. It is a small bank of Thetis-shaped hypothesized plaintexts (training pads, Kenngruppe drill, structural grids) plus shell constraints, then key search under letter-match—Welchman still runs wherever a ≥16 crib lives. Reversing Turing only works when you bring a hypothesis the 1945 machine never needed to invent on its own.
                </p>
                <p>
                  First live shots on the GPU: Metal KPA against a Thetis template bank under the Potsdam-wheel prior. Max-over-bank peaked at 14/39 on a mid-message FLOTTX guess. Per-template GA on sixteen head masks topped out around half—noise. Then I ran it with rigor: ratio fitness, an empirical noise floor per cell, a survivor bar of 80% and at least ten points above that floor, twenty-one structural Thetis masks, and both the Potsdam-wheel and two-notch priors. Forty-two cells. Zero survivors. Best score 11/16 (68.8%) on <code>THETIS@1</code> under Potsdam—above noise, below the bar.
                </p>
                <p>
                  Then I dropped the training-net assumption. If Thetis was a shadow tactical fallback in the last days, the lexicon is collapse language: <code>VERSENKEN</code>, <code>REGENBOGEN</code>, <code>SOFORT</code>, <code>FLENSBURG</code>, <code>DOENITZ</code>, <code>ANTWORTEN</code>. Same engine, new targets. Another rigor pass—twenty-four collapse heads × two priors—again zero survivors. Best: 11/16 (68.8%) on <code>DOENITZFLENSBURG@0</code>, the same ceiling as the training bank.
                </p>
                <p>
                  Meta-evolve mutated those banks; weather, keyboard slides, and Kurzsignal-shaped masks followed; then shell-RIGA with continuous random immigration and free rings. Every arm: zero survivors under the rigor bar. Best weather-RIGA score was 60%—still coincidence. The architecture is holding the line exactly where it should. Wrong plaintext plus all the Metal in the world does not invent the true letters. Exact cribs go back to the Welchman ring sweep; stochastic stays parked until a qualitatively new hypothesis appears.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Phase 21: TensorLUT</div>
              <h3>Melt the silicon. Learn what cannot melt. Adapt.</h3>
              <div className="prose">
                <p>
                  While the catalog ring sweep burns Boolean coverage, I closed a different loop: a continuous–discrete compiler. Yosys LUT6 cells become 64-wide floating-point INIT tensors. Metal evaluates them with a multilinear kernel and ticks the DFFs in a streaming inject→forward→clock→sample contract—exactly what a stateful Enigma needs. Fitness is soft ciphertext×plaintext MSE; a rising λ penalty squeezes fractions toward binary. When the elite snaps clean, <code>TensorLUTEmitter</code> writes gate-level <code>{`LUT6 #(.INIT(64'h…))`}</code> Verilog.
                </p>
                <p>
                  Before wiping anything I locked the unmutated M4 core: 925 LUT6 + 49 DFFs, ~158 KB of baseline Verilog, and <em>F<sub>crypto</sub> = 0</em> on a four-letter crib with known Grundstellung. That proves the continuous weights still execute physical Enigma. Then the full melt: all 59,200 INIT floats to 0.5. Explore climbed from about −4.59 to −1.22. Squeeze toward λ=10 forced discreteness and <em>regressed</em> crypto to −8.04 with tens of thousands of fractional weights left. Continuous soft paths that ignore rotor wiring look brilliant until the hardware law arrives. That is dependency-chain shatter—not rediscovery.
                </p>
                <p>
                  Adaptation one: freeze known-good LUTs and melt only a cone. On an abc-flattened netlist there are no hierarchical plugboard names; a naive reverse BFS floods hundreds of cells through the state cloud. A cone tagger that refuses state-Q wires and unwraps registered plaintext recovered sixteen edge LUTs. Melting just those still shattered under λ. Early resignation correctly aborted doomed lineages—including an identity-stecker control that resigned three times with hundreds of fractional melt weights. The structural lesson: Verilog <code>plugboard()</code> is identity. Those sixteen cells are I/O codecs, not a reciprocal letter map. Independent INIT floats never invent A↔X.
                </p>
                <p>
                  Adaptation two: stop melting the stecker into INIT tables. Freeze the entire known-good TensorLUT core. Evolve a <code>SteckerInvolution</code>—at most ten disjoint pairs—and sandwich it around the frozen silicon: inject <em>S</em>(ciphertext), score soft plaintext against the bits of <em>S</em>(plaintext). Reciprocity is structural; the GA cannot invent a non-involution. Identity seed on the same four-letter crib hits <em>F<sub>crypto</sub> = 0</em>. Blind search needed longer cribs, parsimony, plateau pair-growth, and soft freeze with thaw—hard freeze once locked a wrong second plug. With those adaptations, a three-pair board on a fourteen-letter crib rediscovers the exact involution with no oracle seed. This is still not a P1030680 break claim. It is the generative compiler learning which genotype belongs on which side of the wire.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Phase 22: Quarantine</div>
              <h3>Exact bars drop garbled truths. Soft-band them into Stochastic.</h3>
              <div className="prose">
                <p>
                  Dan Girard’s degarbling of the Dönitz sister message P1030681 shows what U-534 paper actually looks like: two disagreeing copies, U confused with N, Q with G, a whole four-letter group missing from one transcript. Our message may be the same kind of mess. An exact Welchman BREAK bar can therefore throw away the true shell because two or three ciphertext letters are wrong.
                </p>
                <p>
                  So I added a quarantine tier. Physical stops that still decrypt their crib exactly, clear a soft IC/trigram band, but fail the strict break gate are written to <code>logs/quarantine_candidates.json</code>. The Stochastic Bombe can ingest that file as elite shell seeds—wheels and rings locked, stecker free to drift—and hunt local garbles without abandoning the Boolean sieve. Synthetic control: wipe twenty letters of known P1030684 after the crib; clean CT still BREAKs, garbled CT soft-bands, Hybrid escalate recovers 100/120 (≥80%). Historical control on Girard’s P1030681: the Schlüsselzettel re-check is only twelve letter diffs and still BREAKs; the first draft—uncertain dots filled, missing group <code>HMHY</code> re-inserted—is thirty-eight diffs, lands in the soft band, and escalate recovers the edit ceiling (334/372). Prior exact-menu clean negatives still stand for those letter strings; they do not stand for a nearby transcription of the same German.
                </p>
                <p>
                  An audit of older campaign logs found no soft-band hits on P1030680 at the default soft tail (−4.0)—closest is <code>UEBUNGXUEBUNG@0</code> at IC 0.049 / tail −4.270. A temporary soft-tail floor of −4.3 on a slim UEBUNG near-miss fixture pulled 55 candidates into quarantine (one whole-band shell). Hybrid locked-shell escalate from that net returned a clean negative under the 80% survivor bar—German-looking IC, coincidence-wall ratio. Soft boundary catches the stop; it does not invent the plaintext.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Phase 23: Regenbogen / Hannibal</div>
              <h3>Not the fleet scuttle order. Not the Hela evacuation phrase.</h3>
              <div className="prose">
                <p>
                  With the catalog ring sweep parked at menu 202, I burned Metal on the operational prior: if U-534 lacked current Thetis keys, would this 72-letter scrap be a Regenbogen scuttle or Hannibal/Hela evacuation broadcast? Long, self-stecker-legal phrases—<code>BEFEHLERHALTENREGENBOGEN</code>, <code>STICHWORTREGENBOGEN</code>, <code>VERSENKUNGBEFOHLEN</code>, <code>RAEUMUNGOSTPREUSSEN</code>, <code>EINSCHIFFUNGHELA</code>, and kin—went through AAAA then full right rings with quarantine armed.
                </p>
                <p>
                  The anchor is a clean negative: nineteen offsets, rings AAAA and right, zero raw stops. Scuttle and Hela produced physical boards and soft-band prefixes (183 / 22 quarantine; 75 / 7), but Hybrid locked-shell escalate returned zero survivors under the 80% bar—ceilings around 54–58%, the coincidence wall again. Own-orders AAAA: all ghosts. Filler AAAA: two physicals, best IC 0.043 — below soft, so no ring sweep. Under right-ring coverage with the middle ring still pinned at A, this ciphertext is <em>not</em> those exact letter-strings at the legal offsets tried. Soft-band German-looking decrypts are not plaintext. Metal returned to the catalog ring sweep; that fragment reached menu 256 before parking.
                </p>
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Phases 24–48: Elsewhere in HELUT</div>
              <h3>Why this chronology skips twenty-five phases.</h3>
              <div className="prose">
                <p>
                  If you are counting, the numbers jump here, and the jump is not missing work — it is work on a different subject. HELUT is three pillars sharing one GPU, and only one of them is this message. My campaign ledger numbered every phase sequentially as I worked, regardless of which pillar it belonged to, so this chronology inherits a gap wherever a phase was not about Enigma.
                </p>
                <p>
                  <strong>Phases 24–48 are the encrypted-computation pillar</strong>: the ladder from "our Metal graphs are FHE-<em>shaped</em>" to "our Metal graphs are actually encrypted." Closing the mock-PBS boolean loop (my <code>$lut</code> lowering had been XOR-packing wires against a random Toeplitz, so tensors I called "plaintext" were nothing of the kind), then real TFHE machinery — GLWE and LWE sample types, GGSW external products, a non-zero secret, a crypto gadget, real key-switching — then an encrypted Yosys netlist, LWE blind rotation under a bootstrap key, public modulus-switch refresh, a machine-checked bounded-noise proof, a Gaussian failure-probability certificate, and a Decision-LWE hardness certificate with a calibration table.
                </p>
                <p>
                  <strong>One caveat about chasing them.</strong> That phase numbering is local to this ledger and exists nowhere else in the project. The <Link to="/projects/netlist-fhe/journal">encrypted-netlist journal</Link> grades the same work by <em>claim-sheet ID</em> — C52–C54 for noisy BK at N=1024, C57 for the cheaper covering SING, C62 for noiseless PicoRV, C65–C69 for covering PicoRV via extract→key-switch — so there is no "Phase 24" to find over there. Two numbering schemes for one body of work is a wart I am recording rather than papering over.
                </p>
                <p>
                  Two campaign-relevant exceptions sit inside that range. Phases 19 and 20 — collapse lexicon, meta-evolve, weather and keyboard priors, shell-RIGA, all zero survivors under the rigor bar — I folded into the Phase 18 narrative above instead of giving them entries. And Phase 49 is squarely this campaign, so it gets its own entry below: it cost me two published results. Separately, Phase 21's TensorLUT work appears above because it shared this GPU, but its real home is <Link to="/projects/differentiable-hardware/journal">Differentiable Hardware Cryptanalysis</Link>, where the continuous-to-discrete loop is the subject rather than a side effect.
                </p>
                <p>
                  Very briefly, so the gap is not mysterious: closing the mock-PBS boolean loop (my <code>$lut</code> lowering had been XOR-packing wires against a random Toeplitz, so tensors I was calling "plaintext" were nothing of the kind); then real TFHE machinery — GLWE and LWE sample types, GGSW external products, a non-zero secret, a crypto gadget, real key-switching; then an encrypted Yosys netlist, LWE blind rotation with a bootstrap key, public modulus-switch refresh, a machine-checked bounded-noise proof, a Gaussian failure-probability certificate, and a Decision-LWE hardness certificate with a calibration table. It ends with a whole-netlist single-graph Metal path and N=1024 microbenchmarks.
                </p>
                <p>
                  None of it touches the Enigma hunt. It shares the silicon, competes for it, and occasionally parks the ring sweep — which is why it appears in the campaign ledger's phase numbering at all. Two campaign-relevant exceptions sit in that range: Phases 19 and 20 (collapse lexicon, meta-evolve, weather and keyboard priors, shell-RIGA — all zero survivors under the rigor bar), which I folded into the Phase 18 narrative above rather than giving separate entries; and Phase 49, which is very much this campaign and gets its own entry below because it cost me two published results.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 49: The Cap That Printed Negatives</div>
              <h3>A lookup-table size limit had been reporting clean negatives.</h3>
              <div className="prose">
                <p>
                  Phase 12 above tells the discovery story. This is what it cost and what I did about it, because the fix changed the engine and re-opened two arms I had already published as closed.
                </p>
                <p>
                  The Metal kernel tabulates one rotor-path involution per distinct slow-wheel state a menu span reaches, and it capped that at four. When a lane needed a fifth, the kernel wrote a zero survivor mask — which my driver reads as <em>eliminated</em> — for a lane it had never actually tested. A cap on the size of a lookup table was emitting clean negatives, in the same language as a real result.
                </p>
                <p>
                  I bounded the damage with stepping arithmetic rather than by re-running anything: every menu span in every fixture I have ever swept, all 56 naval middle/right rotor pairs, all 676 windows, no GPU required. It never fires at or below 25 letters. At 28 it silently eliminates 0.29% of lanes, at 30 letters 1.14%, and at 40 letters <strong>5.56%</strong>. Whole-catalog exposure is 0.33% — but it is not spread thinly, and that is the problem.
                </p>
                <p>
                  It concentrates on exactly the arms I curated for long, strong menus. My Übung body-anchor arm is forty menus of forty letters each, so <strong>all forty were contaminated</strong> — and that arm's "zero raw stops" is what let me close the Übung-push hypothesis. The curated top-30 was contaminated on 20 of 30. The main catalog on 300 of 2,513. The Regenbogen queue is clean, and everything from 16 to 25 letters, which is the large majority of the catalog and all of the Thetis-register work, was never affected.
                </p>
                <p>
                  The fix: the cap is now eight, and overflow writes <em>undecided</em> — all 26 seeds live — so the host re-tests that lane in full on an engine that has no such limit. A lane can no longer be discarded by a table size. Then I re-ran both contaminated arms. Übung body: 40/40 still dead, zero raw stops across 6.39×10<sup>11</sup> settings. Top-30: 73 raw stops over 4.79×10<sup>11</sup> settings — <em>byte-identical</em> to the archived figures. In both arms the previously-untested lanes produced <strong>zero</strong> extra survivors. The bug was not hiding a key. Both negatives stand, and now they are earned.
                </p>
                <p>
                  The same phase made the middle ring affordable. It had been pinned at A by a literal zero in one host tuple, and unpinning it looked like 26× the work. It is not, because notch tests depend on window position rather than on the ring: a lane whose middle wheel never reaches its notch — and whose ring-A partner at window <em>m</em>−ρ never does either — is the <em>same machine</em> as that partner. So ring A runs in full and rings B–Z run only their notch-hitting lanes, and the union is complete coverage rather than a sample. Measured cost: <strong>6.5× for a one-notch middle wheel, 11.4× for two</strong>. I graded the equivalence before trusting it — 2.4 million claimed-covered pairs, zero verdict mismatches — because a coverage shortcut that quietly drops keys is the same class of bug as the cap.
                </p>
                <p>
                  Throughput came along for free. The kernel had been applying no plug budget at all, so every over-budget stop was shipped to the host and re-derived before being thrown away; and the driver was reading only "did any seed survive," discarding the 26-bit seed mask the GPU had already computed, then re-running all 26 host closures. Both fixed, with the kernel applying the host rule verbatim so verdicts cannot change: <strong>399 s → 352 s, 45.4M settings/s</strong>, same shell, same ten plugs, same IC and tail, and the GPU-versus-host cross-check still at zero lane mismatches.
                </p>
                <p>
                  Two ideas failed and are recorded as failures. A Kriegsmarine board carried <em>exactly</em> ten leads, so plugs the menu has not yet forced must still fit — sound, and the control still breaks, but <strong>useless</strong>: it took 847,434 raw stops down to 847,414, which is 0.002%, while costing 4% throughput. Its selectivity is anti-correlated with where ghosts actually live. And three quarantine flags documented in my own ledger had <strong>never been parsed</strong> for the Welchman path, which means Phase 22's "temporary soft tail of −4.3" actually ran at −4.0 the whole time. All three are wired now.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 50: The Crib-Free Path</div>
              <h3>I stopped needing a probable word — and measured how far that gets me.</h3>
              <div className="prose">
                <p>
                  Every arm above needs a crib, and every crib I have is borrowed from another network. So I built the other kind of attack. Ostwald and Weierud's ciphertext-only method needs no probable word at all: for each candidate rotor setting it hill-climbs the plugboard and ranks the setting by how good a score the climb reaches. Their published reach is messages down to about 100 letters, and the shortest they have ever broken is 78 — on three-rotor Army traffic. Mine is 72 letters on four-rotor naval M4. Shorter than the record, on a harder machine.
                </p>
                <p>
                  The first thing to understand is that this wall is not made of compute, and that changes where hardware helps. Seventy-two letters of naval German carries about 223 bits of redundancy. A ten-plug board is about 47 bits of nuisance parameter, and the attack <em>fits it fresh at every candidate</em>. With roughly 10<sup>11</sup> candidates, you are taking the maximum of an overfitted score over an enormous population — and adding candidates makes that <em>worse</em>, because it raises the maximum of the noise. Enigma@Home has vastly more aggregate compute than my one Mac, and it stops at 78 too.
                </p>
                <p>
                  So the number that decides everything is not a rate. It is the <strong>margin</strong>: the climbed score at the true setting minus the best climbed score over wrong settings. Positive, and a sweep can find the key. Negative, and the search ranks noise above signal no matter what you throw at it. I built a harness that measures exactly that, at a ladder of message lengths, against the 48 published 1 May 1945 keys — same net, same signals office, same German dialect as my target. Two of those controls are 60 and 68 letters, shorter than P1030680 itself.
                </p>
                <p>
                  I made the harness refuse to print a curve unless its controls can decrypt their own published plaintext under their own published key. That preflight caught something immediately: <strong>only 32 of the 48 round-trip exactly.</strong> My first reaction was that I had found transcription garble in the archive itself — the same disease I had been arguing afflicts P1030680, measured in sixteen of its neighbours.
                </p>
                <p>
                  <strong>That was wrong, and I caught it the same day.</strong> When I classified the seventeen failures by the <em>shape</em> of their errors, most turned out to be messages whose errors begin at some position and run to the end — and several of those exceed the ~320-letter Kriegsmarine limit, meaning they were transmitted in parts with a fresh rotor start for each part. Decrypting one of those end-to-end under a single message key is <em>supposed</em> to give a clean head and a garbage tail. That is my harness's assumption breaking, not the archive's transcription. A few others are genuine shifts or divergent transcripts. Only four controls show scattered single-letter errors — eight events in total, which is nowhere near enough to fit a confusion model on.
                </p>
                <p>
                  So the garble hypothesis for my target still rests where it always did: on Girard's documented degarbling of the sister message, not on this. I would rather record the retraction than keep a flattering number.
                </p>
                <p>
                  Validation is unambiguous: at 372 letters the attack recovers <strong>all ten plugs and 100% of the plaintext</strong>, with the true setting sitting 35 standard deviations above the noise. The implementation works, which is what earns the right to believe its failures.
                </p>
                <p>
                  Then a lesson in reading the manual. The reference implementation scores in stages — index of coincidence first, then bigrams, then trigrams — because the measures fail at different moments: with an empty board the text is letter-substituted so n-gram structure is destroyed, while IC survives; once a few plugs are right the n-grams become far sharper. <em>My climb had been bigram-only the whole time.</em> Switching to staged scoring took 252-letter recovery from 0 plugs to 8.
                </p>
                <p>
                  The August curve, measured under the sparse bigram model, crossed zero at about <strong>200 letters</strong>. That was the honest baseline at the time: 2.8× worse than the published record, with a 72-letter target that requires being slightly better. The current dependent rerun did not sample 200 or 220, so I am not relabelling that historical crossing as a newly measured threshold.
                </p>
                <p>
                  In the same August sparse-model A/B, Ostwald's partial exhaustion moved the 72-letter median margin from −0.2389 to <strong>−0.0754</strong> and doubled the win rate. That removed 68 percent of <em>that historical deficit</em>. The partial-exhaustion arm has not been rerun under the current dense staged scorer, so 68 percent is no longer a current headline.
                </p>
                <p>
                  Then I audited the scorer itself. The trigram stage already used 28.5 million letters, while the bigram stage was compiled from a 10,359-letter sample. The sparse table left 235 of 676 cells on the same finite add-half floor; a dense bigram fixture built from the existing corpus left only two. Python, Ruby, and Swift independently agreed on the dense scores before I accepted the replacement.
                </p>
                <p>
                  The data-path repair moved the same 72-letter known-shell rehearsal from <strong>4/72 letters and 0/10 plugs</strong> under the August sparse model to <strong>21/72 and 4/10</strong> with the dense table. Objective v1 then reached <strong>25/72 and 5/10</strong>, but its calibration audit found that it normalized the full bigram/IC/crib attack score with raw-bigram moments and used raw-bigram/trigram correlation. Objective v2 calibrates that exact attack score and its paired trigram relationship. It recovers the same 25/72, 5/10 candidate as v1, now on corrected objective coordinates. The IC-only rank stays exactly 223,118 of 456,976 across all four checkpoints, and every row still says <strong>NO BREAK</strong>.
                </p>
                <p>
                  That last boundary matters. The search objective ranks candidates; it does not publish confidence. The old <code>likeness</code> number is gone, replaced by an explicitly unbounded <code>bigram-position</code> diagnostic. Final assessment is a separate fail-closed policy gate—not a claim of statistical independence—and requires Core bigram-position, IC, and structure evidence plus the exact hash-bound trigram model above its threshold. Better ranking is real progress, not permission to call fluent-looking nonsense German.
                </p>
                <p>
                  There is still one lever I have that the people who set the record do not. Their tool documents a flag for "known plugboard connections, e.g. from running a bombe" — and then makes you type them in, because the bombe is somebody else's program. Here both engines live in the same binary, and my quarantine files already hold soft-band Welchman stops <em>together with the stecker each menu forced</em>: fifteen to twenty-four of the twenty-six letters, which is seven to twelve plugs.
                </p>
                <p>
                  I reran that oracle-seeded ladder with the objective-v2 binary. The command uses the legacy staged scorer rather than <code>EnigmaSearchObjective</code>, so all five stdout receipts are byte-identical to the preceding v1-binary bundle. At zero seeds the median margin is −0.1226. Four correct seed plugs flip it to <strong>+0.3308</strong>, with 6 of 10 plugs and 47% of the letters recovered. Six gets 8 of 10 and 85%; <strong>eight recovers all ten plugs and 100% of the plaintext on every control.</strong> The six- and eight-plug numbers also happen to match their August values, but objective-v2 did not cause the ladder to move—or hold still.
                </p>
                <p>
                  I have to be precise about what that is, because it is easy to over-read and I would rather state it narrowly than be wrong loudly. Those correct plugs come from the known key — it is <em>oracle-seeded</em>, and it assumes the stop you are seeding from is the true one. It does not make the attack crib-free at 72 letters. What it establishes is smaller and still worth having: <strong>a true bombe stop is finishable.</strong> A stop the strict bar threw out for garble or short-message noise can now be recovered, plugs and plaintext and all.
                </p>
                <p>
                  So I pointed it at every soft-band stop the campaign has ever quarantined. Fifty-five UEBUNG near-misses, twenty-two Regenbogen scuttle boards, seven Hela, two from this week's re-run — eighty-six candidates, each seeded with its own forced plugs and climbed. No break. And in every single arm the best stop scored <em>below</em> the best of twelve random settings. Not "no survivor above the bar" — <strong>worse than noise</strong>, under a scorer that would have finished a true stop. My soft band was never a near miss. Phase 22's genetic escalation told me zero survivors and could not tell me why; this tells me why. That path is closed, properly.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 51: The Mulein Board</div>
              <h3>A board that counts contradictions instead of shorting out on the first one.</h3>
              <div className="prose">
                <p>
                  Here is something the 1945 machine could not do — not slowly, but <em>at all</em>. On a physical bombe a contradiction <em>is</em> electricity finding a second path through the diagonal board. The hypothesis short-circuits, the drum spins on. Copper cannot answer "how many contradictions?" because the relay either lights or it does not, and every faithful reimplementation of the board inherits that limitation, including mine.
                </p>
                <p>
                  That is fatal if the ciphertext is dirty. One mis-transcribed letter contradicts a <em>true</em> menu, and the board throws the real key away without comment. Which means every "clean negative" in this entire ledger is a negative about the ciphertext as it was <em>written down</em>, not necessarily as it was transmitted. Girard needed two disagreeing transcripts to degarble the sister message.
                </p>
                <p>
                  In silicon I can count instead of short-circuit, and ask the question a relay cannot phrase: <strong>how few menu edges must I delete before this setting closes consistently?</strong> Delete up to <em>t</em> of them and accept the setting. That is a deletion-tolerant diagonal board. It sits in exactly the slot Welchman's diagonal board did — not a new bombe, a new board on one — so I am calling it the Mulein board. At tolerance zero it is the historical board, bit for bit.
                </p>
                <p>
                  <strong>My first version of it was a complete no-op, and the reason is worth keeping.</strong> I abandoned contradicting edges mid-flight instead of removing them before propagating. Two things went wrong at once: by the time a conflict surfaces the bad value is already committed and has spread through the rest of the board, so restoring the two rows that just clashed unwinds nothing; and the conflict almost always surfaces at the <em>wrong</em> edge, so a perfectly good edge gets blamed while the real culprit stays in. Enumerating the deleted set instead is order-independent and reuses the closure I had already validated.
                </p>
                <p>
                  Then the test that matters. Known key, 27-letter crib, corrupting letters inside the crib span. At one, two, and three garbled letters the exact board <strong>loses</strong> the true setting and the tolerant board <strong>keeps</strong> it — while still forcing <strong>all 25</strong> plug deductions correctly. That LOST → KEPT flip is the whole mechanism, and it is the check my no-op version had quietly failed. The plug column matters just as much: Phase 50 measured that a true stop needs only <em>four</em> correct plugs to flip the crib-free margin positive at 72 letters. Twenty-five is a long way past four. The two halves compose — a garbled true key survives the board <em>and</em> can be finished off.
                </p>
                <p>
                  So I put it in the GPU kernel, and graded it against the host board rather than trusting it: <strong>zero lane mismatches out of 192, at every tolerance, across 45 different crib and offset combinations.</strong> One shell is 26<sup>4</sup> lanes, about ten milliseconds, so tolerance is cheap per shell and expensive per sweep — roughly eight minutes per menu on a pinned ring pass, ninety hours per menu at full ring coverage.
                </p>
                <p>
                  <strong>And then I got the important part wrong, and had to retract it the same day.</strong> Tolerance widens what survives, so the price is survivor inflation, and at offset 0 the price looked beautifully crisp: 16 edges exploded to 130,787 survivors at tolerance 1, while 17 and above stayed at exactly one, and 22 and above stayed at one even at tolerance 2. I wrote up a rule — tolerance 1 needs 17 edges, tolerance 2 needs 22.
                </p>
                <p>
                  Varying the <em>placement</em> destroyed it. At offset 15, sixteen edges costs nothing at all. At offsets 40 and 65, eighteen edges admits 4,301 and 16,019 survivors. Crib length does not predict inflation. What does is the menu's loop structure — tolerance <em>spends</em> redundancy, and only a loop-rich menu has enough to spend. Look at which placements detonate and it is obvious in hindsight: the ones where the exact board was already weak. <strong>Tolerance amplifies an under-determined menu rather than rescuing it.</strong>
                </p>
                <p>
                  The corrected rule is better than the one I lost. Tolerance is not a global switch, it is a per-menu decision pre-qualified by measurement. I cannot simply run the campaign's 16-letter minimum at tolerance 1 — one offset-0 menu there produces 130,787 survivors per shell against an escalator that has so far handled eighty-six. So the order is measure, then run.
                </p>
                <p>
                  That mechanism grade was not a decrypt or evidence that P1030680 is garbled. The target arm has now run, but only to a durable partial boundary: <strong>3 of 24</strong> strongest placements completed under tolerance 1 × right-ring coverage, all three dead at the board. It is suspended, not running; resume <code>--bombe-menus 0 --bombe-ring-sweep --bombe-garble-tolerance 1 --bombe-from 4</code>. The remaining 21 placements are open, so this is three local negatives rather than a target-wide verdict.
                </p>
                <p>
                  Tolerance still does not model <strong>indels</strong>, and that gap turned out to matter more than the board itself — so I built and partially ran the other half. Full design notes for both live on the <Link to={enigmaPaths.mulein}>Mulein board page</Link>.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 51.7: The Indel Board</div>
              <h3>What Girard actually found was not a wrong letter. It was a missing group.</h3>
              <div className="prose">
                <p>
                  The tolerant board fixes substitutions — a letter read wrong at a position I know. But the error Girard actually documented in the sister message was different in kind: an entire four-letter group, <code>HMHY</code>, present on the Schlüsselzettel copy and simply blank on the plain-paper one. Nothing was mis-read. Letters went <em>missing</em>, and everything after them slid.
                </p>
                <p>
                  That is a completely different failure, and it needs completely different machinery. If four letters fell out, then every remaining letter is <em>correct</em> — it just sits at the wrong index, which means the rotor had advanced four more times than the recorded position suggests. So each menu edge after the splice needs a <strong>different scrambler</strong>. Nothing about the deduction is relaxed. It is a different, and much more specific, hypothesis about what happened to the paper.
                </p>
                <p>
                  <strong>So the Mulein board has two mechanisms, not one.</strong> Together they cover the two halves of edit distance: substitution is a deleted edge, an indel is a re-alignment. They act at genuinely different layers, and I keep that documented because the difference is operationally load-bearing — but it is one board. And the second half turns out to be the better-behaved one, for three reasons I did not expect going in.
                </p>
                <p>
                  First, <strong>it needed no new board at all.</strong> The step number and the ciphertext index were already separate arrays in my menu structure, and the GPU kernel already picks a scrambler per edge from that step array. So a spliced menu runs on Welchman's <em>exact</em> board with zero kernel changes. Second, and following from that, <strong>zero survivor inflation</strong> — the entire pre-qualification problem that dominates tolerance simply does not arise. Third, it is the hypothesis with actual evidence behind it: Girard <em>found</em> a missing group, whereas isolated substitution garble across my 48 controls amounts to only four controls and eight events.
                </p>
                <p>
                  The grade. I deleted a real four-letter group — <code>HBSX</code> — from the known P1030684 ciphertext at position 12, manufacturing the transcript a copyist would have left behind, then attacked the damaged text with a 27-letter crib straddling the gap. The ordinary menu did not merely lose the key: it came out <strong>illegal</strong>, because the misalignment forced a letter to encipher to itself, which Enigma forbids. The true shell was never even testable. The spliced menu with the right splice and gap size <strong>kept it, with all 25 plug deductions correct</strong>, on the 23 edges that survived the gap.
                </p>
                <p>
                  <strong>The specificity result is more interesting than a pass would have been.</strong> I checked whether a <em>wrong</em> splice could rescue the setting, and found that at the 16-letter floor, all 28 wrong splices were eliminated before the bombe was ever asked — by self-encipherment. Enigma never encodes a letter to itself, so re-pairing a crib against shifted ciphertext almost always produces an illegal placement.
                </p>
                <p>
                  That asymmetry is structurally in my favour. A menu built from the true crib at the true offset with the true splice is <em>always</em> legal, because it is reconstructing real plain/cipher pairs — so this filter can never reject the truth, while it killed 28 of 28 wrong candidates for free with no GPU at all. But I have to be careful about what it does <em>not</em> show: the discrimination is coming from the cipher's own constraint, not from the board, and legality prunes by coincidence rather than by correctness. I have no measurement of what the board does with a legal-but-wrong splice, so a spliced hit would still need independent confirmation.
                </p>
                <p>
                  Two of my own test bugs are worth recording, because both produced confident wrong answers. My first probe shortened the crib while keeping its start fixed, which quietly walked it off the gap entirely — and since the damaged and undamaged transcripts are <em>identical before the gap</em>, every splice produced the same correct menu and the tool cheerfully reported "28 of 28 wrong splices surviving." My second auto-shortened to 12 letters, below my own ghost threshold, where nothing discriminates anything. The probe now forces the crib to straddle the gap and refuses to go below 16.
                </p>
                <p>
                  The target arm then ran on the exact Welchman/Metal path with post-gap δ=4 geometry and right-ring coverage. It is <strong>suspended at 144/237</strong>: entries 1–110 and 112–144 are dead at the board; entry 111 produced eight raw stops and <strong>zero valid ≤10-plug completions</strong>. No physical candidate, no break. Resume <code>--bombe-menus 0 --bombe-from 145</code>; 93 splices remain, and this arm still pins the middle ring at A.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 51.13: The Unified Verilog Future Bank</div>
              <h3>The hardware path landed before the target campaign.</h3>
              <div className="prose">
                <p>
                  I replaced the collection of independent host loops with a production Verilog path. One outer TensorLUT lane owns one rotor setting and one shared 80×26 trail; parameterized bank slots own explicit Future-Lattice geometry and independent seeds. Each slot performs exact-first one-edge repair and holds a complete tagged receipt until the host accepts it.
                </p>
                <p>
                  The known-key grade is deliberately P1030684 only. Clean hit, exact negative, combined post-gap plus one-edge repair, and transmitted step 79 produce identical held receipts through source RTL, post-Yosys RTL, clear Yosys-JSON simulation, and cleartext Float TensorLUT at <code>BANK_LANES=1</code>, including backpressure. This is a cleartext Boolean-oracle grade, <strong>not FHE</strong>.
                </p>
                <p>
                  The deterministic target inventory later named <Fahrenheit261Span /> contains <strong>261 entries</strong>: 24 identity plus 237 post-gap δ=4, fingerprint <code>fnv1a64-32fd2543824a62a3</code>. Building that manifest compiles hypotheses; it evaluates no rotor setting. Width-qualified JSON, Verilog, and statistics artifacts now exist for <code>BANK_LANES=1/2/4/8/16</code>, from 45,463 to 758,323 LUTs. That proved all candidate graphs synthesize; it did not identify the fastest runtime architecture. At the end of this phase the bank had processed zero target settings; Phase 51.14 records the measured selection and bounded launch.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 51.14: <Fahrenheit261Span /></div>
              <h3>The bounded canonical-manifest launch returned zero positives.</h3>
              <div className="prose">
                <p>
                  <Fahrenheit261Span /> is the formal name of this historical 261-entry canonical-menu/Future campaign. The name denotes the inventory and campaign, not executed breadth: only identity Future 0 ran in the bounded target slice below; the other 260 Futures did not. I benchmarked widths 1, 2, 4, 8, and 16 on the same P1030684 workload—16 settings × 16 jobs × five repetitions, each width in a fresh process, every receipt checked. All five produced the same digest. Their median rates were 233.777, 264.719, <strong>276.035</strong>, 273.890, and 230.780 complete receipts per second, so <code>BANK_LANES=4</code> won. The selected graph has 189,032 LUT6, 2,772 DFF, 205,177 wires, and 28 levels. Graph size did not choose it; measured runtime did.
                </p>
                <p>
                  Protocol v3 binds one immutable manifest snapshot, the netlist, width, graph, protocol, and exact shell/Future/setting plan into the run identity. The ledger admits only an exact ordered plan prefix and stores every canonical per-job receipt projection, so resume recomputes each digest and derives hits and BREAK gates rather than trusting row summaries. Every persisted hit is replayed through the host and discriminator; a prior gate halts before evaluator submission. Malformed, sparse, reordered, post-gate, or candidate-deleted rows fail closed. One atomic non-truncating descriptor stays exclusively locked from pre-read through final synchronized append. Repaired and post-gap positives remain non-BREAK-eligible until their correction geometry can be verified over the full message, and the runner never announces a break automatically.
                </p>
                <p>
                  The bounded target run was deliberately small: shell 0 <code>B/beta/IV-III-VIII/AAAA</code>, identity Future 0, settings <code>0..&lt;256</code>. Protocol-v3 run <code>sha256-e6dc10d45b2e2e9fb4fbc69936fd0909a89dbecc4d53063cb415c58232fc1360</code> completed <strong>16/16 synchronized chunks and 6,656/6,656 canonical receipt projections, with zero hardware positives and zero BREAK gates</strong>. Re-running the identical plan revalidated all 16 rows and appended nothing. The durable receipt is <code>logs/p1030680-mulein-unified-smoke-v3.jsonl</code>, SHA-256 <code>687d08383111b90b284ca08496d5ba02c9d0b560c17613c2e56283362b1f7e7d</code>.
                </p>
                <p>
                  That is a clean local negative, not a global elimination. The other 260 manifest Futures, settings <code>256..&lt;456976</code>, other shells, and the existing catalog, middle-ring, tolerance, and legacy indel remainders were not covered. This was cleartext Float TensorLUT/Metal, <strong>not FHE</strong>. P1030680 remains unbroken: no key, no plaintext, no implied decrypt.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 51.15: <NaziBlaster9000Span /></div>
              <h3>The operational preflight was graded; the bounded production stripe launched.</h3>
              <div className="prose">
                <p>
                  <NaziBlaster9000Span /> is the formal name of the unified P1030680 Mulein search machine and overall campaign. I built a separate operational/scuttle inventory rather than overwrite the <Fahrenheit261Span /> canonical artifact. <code>p1030680_mulein_regenbogen_hannibal_identity_postgap_delta4.json</code> contains <strong>628 Futures</strong>—314 identity and 314 post-gap δ=4—with fingerprint <code>fnv1a64-616326e94036a97d</code> and SHA-256 <code>1086b697d70ef9f05855292dd2e041b94a8551d18b1c51ec12c161a0c974c510</code>.
                </p>
                <p>
                  Protocol-v3 run <code>sha256-2b6bde1ead5ffd33b3e598038a7af597d9c1c189c9b607147c98451a527c727a</code> evaluated shell 0 <code>B/beta/IV-III-VIII/AAAA</code>, setting 0, and Futures <code>0..&lt;628</code>. It completed <strong>628/628 chunks and 16,328 checked receipts</strong>. Fifteen physical candidates survived host replay: five identity-family one-edge repairs and ten post-gap one-edge repairs. Every one was <code>exact=false</code>, leaving <strong>0 exact hits and 0 BREAK gates</strong>. These are non-BREAK-eligible ghosts unless an explicit correction or geometry-aware full-message replay changes their grade; they are not evidence that the ciphertext is garbled.
                </p>
                <p>
                  The durable preflight receipt is <code>logs/p1030680-mulein-operational-preflight-v3.jsonl</code>, SHA-256 <code>55a68266f79ca0b17b6de18a80644883c7c8a2585ab2508d42d5d73c9a17f993</code>. At launch, the bounded production stripe covered settings <code>1..&lt;256</code> across all 628 Futures under run identity <code>sha256-efb770bcaddd2bc0581edbb19b66077160a806c30650a60d0b9d6a733c592cc0</code>, with a fixed plan of 10,048 chunks and 4,163,640 receipts. Phase 51.16 records its completed grade. Operational/scuttle hypotheses ran first; that ordering was a working search prior, not historical proof. P1030680 remained unbroken at launch, and the cleartext Float TensorLUT/Metal run was not FHE.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 51.16: bounded production receipt</div>
              <h3>The printed stripe is complete: 4,184 physical candidates, zero BREAK gates.</h3>
              <div className="prose">
                <p>
                  From <code>2026-08-20T20:44:18Z</code> through <code>2026-08-21T01:54:45Z</code>, the production run completed <strong>10,048/10,048 new synchronized chunks, 0 skipped, and 4,163,640/4,163,640 canonical receipt projections</strong>. The durable ledger is <code>logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl</code>, SHA-256 <code>c516238d5420bde46fb7bdc76078ac086b5946de2374f8d7a4b4d56b1e7e52f2</code>. A read-only audit found every one of the 628 Futures in 16 chunks, no duplicate chunks, one run identity, and exact attempted/stored receipt counts.
                </p>
                <p>
                  Host replay retained <strong>4,184 physical candidates</strong>, all <code>hostReplayVerified=true</code>: 40 exact/no-drop identity hits killed by ≤10-plug completion, 2,056 one-edge identity repairs, 41 exact/no-drop post-gap δ=4 hits, and 2,047 one-edge post-gap repairs. There were <strong>0 row BREAK gates, 0 candidate BREAK gates, no scored plaintext, no key, and no decrypt</strong>. This is neither a zero-positive result nor a global negative.
                </p>
                <p>
                  A translation audit paired 1,724 identity/post-gap candidates at <code>post-gap lane = identity lane - 4</code>, so widening the same leading-gap shape would mostly resample closure states. The read-only adjudicator has now resolved every exact candidate: all 40 identity hits and all 41 post-gap hits die at joint ≤10-plug completion. The six source Futures have two to five disconnected components on only 16–21 edges—one is a zero-loop tree—so <strong>all 81 exact candidates are split-menu ghosts</strong>. They never reach the language score, and the earlier claim that geometry-aware decryption was their blocker is withdrawn. Identity-family repairs with at least four forced plugs were later climbed (Phases 62–63): 38 then 824 crib BAD, <strong>NO BREAK</strong>, best −3.4797 versus a random-setting floor of −3.4564. Split-menu identity trees with enough plugs are in that 824; 1,232 identity repairs remain below the pair floor. Post-gap repairs must not enter the dense 72-letter walker; a leading-gap walk exists and was not consumed. Settings <code>256..&lt;456976</code>, other shells, and the legacy remainders remain open. These are cleartext Float TensorLUT/Metal receipts, not FHE or encrypted tick rate. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phases 52–55: historian-led archival pivot</div>
              <h3>Selm joins the team; two clean negatives sharpen a better historical model.</h3>
              <div className="prose">
                <p>
                  Selm Merel Wenselaers is now a deeply valued campaign contributor leading the historical and archival arm alongside HELUT's mechanical cryptanalysis. Her first three leads were independently regenerated and tested twice: exact and post-gap δ=4 each returned <strong>28/28 dead at the board and zero raw stops over 4.471×10<sup>11</sup> settings</strong>. Her menu-selection instinct also exposed the same disconnected-component flaw in all 81 exact candidates from the bounded Future stripe.
                </p>
                <p>
                  The next tranche changes the target model rather than inventing another sentence. Wenselaers reports primary-source evidence that crews transferred to Neustadt while demolition parties remained aboard, so Neustadt and scuttling are stages of one process. She also reports scheduled <code>FT-Programmzeit</code> reception during AGRU-Front training, changing Aegir/Thetis allocation lists, and active archive enquiries. These reports carry named sources but remain source-reported until scans or exact transcriptions enter the evidence room. Preservation among U-534's papers does not prove intended recipient; intercepted training-network traffic is now an open hypothesis.
                </p>
                <JournalQuote speaker={SELM_CREDIT} source="The last days of U-534, 23 September 2026">
                  {SELM_QUOTES.notForU534}
                </JournalQuote>
                <JournalQuote speaker={SELM_CREDIT} source="The last days of U-534, 23 September 2026">
                  {SELM_QUOTES.unreadMessage}
                </JournalQuote>
                <JournalAttachments
                  kicker={`Attachments · ${SELM_CREDIT}`}
                  files={[selmU534LastDays, selmU3521Dossier]}
                />
                <p>
                  The corpus independently confirms one new exact radio phrase: <code>FFFTTTBLEIBTBESETZT</code> in P1030668. Its short core is mechanically weak, but the exact 40-letter source context yields four single-component, 18-loop alignment hypotheses. Phase 60 then ran those four placements under the same VIII-fast middle-ring coverage that came back empty on the strongest catalog menus: <strong>4/4 dead, 0 raw stops over 2.076×10<sup>11</sup> settings</strong>.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 59: identity-repair Ostwald adapter</div>
              <h3>The Future-aware escalate adapter is built. Phase 62 later pointed it at the stripe.</h3>
              <div className="prose">
                <p>
                  <code>--mulein-ostwald-adapt</code> streams the durable campaign JSONL, rebounds the 628-Future inventory by SHA-256 and fingerprint, and compiles <strong>only the identity-repair ordinals</strong> that appear on candidate rows. That is the fast path: not a TensorLUT rematerialize of all 628 Futures. Forced plugs are rebuilt from the host <code>live</code> bitmask. Split menus and post-gap repairs are counted with an explicit skip reason. Dense Ostwald is legal only on the identity family's 72-letter timeline; after a gap the same walker would encipher every later symbol at a rotor position four steps too low.
                </p>
                <p>
                  This phase did not consume the stripe. Phase 62 later did: 38 identity repairs climbed, NO BREAK. Phase 63 then Metal-climbed the split-menu identity boards with at least four plugs: 824, NO BREAK. XCTest covers both flags on synthetic fixtures and the P1030684 known-key control; it does not load the 628-Future operational JSON. Crib-exact on a dropped letter remains undefined. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 60: BLEIBTBESETZT context fixture</div>
              <h3>The four 18-loop P1030668 alignments are dead at the board.</h3>
              <div className="prose">
                <p>
                  <code>--welchman --bombe-fixture Fixtures/p1030680_wenselaers_bleibt_besetzt_context_menus.json --bombe-menus 0 --subspace viii-fast-wheel --bombe-middle-ring --bombe-ring-sweep</code> selected <strong>4/4 menus</strong>, each 40 edges / 23 letters / 18 loops / one component, spans 47–70. Banner: 113,568 shells per menu (42 wheel orders × 2 Greek × 2 UKW × 26 middle × 26 right), covered-lane skip, <strong>no residual ring gap</strong>. Log <code>logs/campaign-wenselaers-bleibt-besetzt-viii-fast-middlering.log</code>.
                </p>
                <p>
                  Result (2026-09-24T03:37:46Z, exit 0): <strong>4/4 dead at the board, 0 raw stops over 2.076×10<sup>11</sup> settings</strong> at 52.3M/s (3,972 s), 0 physically buildable boards, 0 soft near-misses — nothing reached quarantine. This is VIII-fast subspace coverage (42 of 336 orders), not wheel-order elimination, and not a decrypt. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 61: archival map</div>
              <h3>The search-changing documents are now named. The interrogation is attached; the NARA boxes have not been read.</h3>
              <div className="prose">
                <p>
                  Wenselaers has a NARA RG 457 request acknowledged for German key logs, allocation lists, and indicator books, including Box 620 NR 1665 key logs through May 1945. R.I.P. 401 is reported to document non-random naval wheel-order sheets; that is structure <em>inside</em> a net’s key generation, not yet a proof that one net’s fast wheel constrains another. The April 1945 NID interrogation (U 413 / U 1209 / U 877 / U 1199) reconstructs Baltic working-up as temporary flotilla attachments and describes radio-watch practice — listen to routines even when remaining silent — but <strong>never names Thetis</strong>. A 3 May FdU Ausbildung / FdU Front split is a designed natural experiment once original 8-letter Kenngruppen exist; Cloots and Beckers are the trail, and no indicators are in hand.
                </p>
                <JournalParaphrase speaker={SELM_CREDIT} source="24 September 2026 replies">
                  <p>
                    Do not promote VIII-fast from the three recovered nets until it is known whether General Key Sheets used a common wheel-order schedule across Schlüsselnetze, or were generated independently inside each net. Keep the 42-of-336 ordering prior until that document exists.
                  </p>
                </JournalParaphrase>
                <JournalParaphrase speaker={SELM_CREDIT} source="24 September 2026, ranked payoffs">
                  <p>What would change the search, in the order she ranked it:</p>
                  <ol>
                    <li>a second same-period Thetis transmission</li>
                    <li>the 1 May Schlüsseltafel / key-log answer to wheel order</li>
                    <li>original 3 May Kenngruppen</li>
                    <li>a duplicate or better P1030680 witness</li>
                    <li>late Thetis holder / distribution</li>
                    <li>a high-fidelity working-up register</li>
                  </ol>
                </JournalParaphrase>
                <JournalAttachments
                  kicker={`Attachment · ${SELM_CREDIT}`}
                  files={[selmNidInterrogation]}
                />
                <p>
                  VIII-fast stays an ordering prior. No new GPU tranche. Do not mint cribs from the training vocabulary. If a key table, a second Thetis witness, or one indicator from each side of the split lands, that outranks sweeping.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 61.1: Tauschtafelplan Bruno</div>
              <h3>1 May 1945 uses Kennwort Quelle, Tafel A. That is table selection, not a Thetis proof.</h3>
              <div className="prose">
                <p>
                  Wenselaers recovered Tauschtafelplan Bruno, Prüfnr. 1772a, Kennwort Quelle. Column six is annotated Mai 45; day 1 is a clean printed A. The P1030680 path <code>VROL NMKA → Quelle/A → EACH/SEDM → ACH → 645/14</code> no longer depends on assuming Tafel A for May. Pair contents of Tafel A are now photographed in a different edition (Phase 61.3). The 621–653 = M-Thetis crop is still undated, so the detector keeps <code>discovery_eligible</code> false. P1030680 is never a discovery.
                </p>
                <p>
                  3 May is a different cell in the same column and carries a handwritten mark. It is not encoded, and a 3 May classify must not inherit Tafel A. Original 3 May indicators, when they exist, use that day's letter — not A.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 61.2: Bauer Appendix F</div>
              <h3>A surviving May 1945 Hydra plugboard table is cited. The page is not in hand, and it is not this ciphertext's board.</h3>
              <div className="prose">
                <p>
                  Wenselaers recovered Bauer's <em>Ultra versus Enigma</em> chapter on the daily-key changeover and the Tagesschlüssel destruction rule. Inner setting (wheels and rings) at midnight, outer setting (plugs) at noon, until 1 July 1942 when the change is described as simultaneous at noon. Almost no daily-key papers survive. Footnote 15 points to Appendix F for the Steckerverbindungen for May 1945, Schlüssel M Hydra, with struck-through positions in use through 7 May. The attached extract is the chapter, not the appendix.
                </p>
                <p>
                  Hydra is the home-waters comparison net. A Hydra plugboard column does not answer whether wheel orders were assigned centrally — that is a Walzenlage question — and it will not be loaded onto P1030680. A planned 1 May plurality of Grundstellungen is source-reported from the same chapter and is not confirmed. <em>Enigmafunk</em> confirms Kenngruppen procedure and contains no Thetis key. Funkschaltung Bruno in that chapter is a radio circuit, not Tauschtafelplan Bruno.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 61.3: Quelle Tafel A photograph</div>
              <h3>The pair map is on a table. The May plan is a different Prüfnummer.</h3>
              <div className="prose">
                <p>
                  Wenselaers found a photographic scan of Quelle, Tafel A in the Crypto Museum Doppelbuchstabentauschtafeln, Prüfnr. 2499, pp. 3–4. The cover is Kennwort Quelle. The table confirms <code>VR→ES OL→AE NM→CD KA→HM</code> and, independently, <code>FN→KY HC→DM GV→UU ET→ZZ</code>. So <code>VROL NMKA → EACH/SEDM</code> is backed by a Tafel A photograph, not only a recovered mapping.
                </p>
                <p>
                  The 2499 cover states that that Ausgabe's Tauschtafelplan carries the same Prüfnummer. The May plan in hand is Prüfnr. 1772a. Edition compatibility is not demonstrated. The detector records both documents and keeps <code>discovery_eligible</code> false. 3 May still fail-closed. P1030680 remains unbroken.
                </p>
                <JournalAttachments
                  kicker={`Attachment · ${SELM_CREDIT}`}
                  files={[selmQuelle2499]}
                />
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 62: identity-repair Ostwald consume</div>
              <h3>Thirty-eight identity repairs climbed. None cleared the random-setting floor.</h3>
              <div className="prose">
                <p>
                  <code>--mulein-ostwald-adapt</code> streamed <code>logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl</code> (SHA-256 <code>c516238d5420bde46fb7bdc76078ac086b5946de2374f8d7a4b4d56b1e7e52f2</code>), rebounded the 628-Future inventory by content, and compiled <strong>59 identity-repair ordinals</strong> — not a rematerialize of all 628. Of 4,184 candidates: 2,056 identity repairs queued; 40+41 exact already scored; <strong>2,047 post-gap skipped as dense-climb-illegal</strong>. Host replay emitted <strong>38</strong> after <strong>1,993 split-menu</strong> skips and 25 pair-floor skips.
                </p>
                <p>
                  <code>--ostwald-escalate</code> on that quarantine (2026-09-24T14:12:20Z, exit 0): <strong>NO BREAK</strong>, 38/38 crib BAD. Best climbed <strong>−3.6976</strong> (IC 0.0493) versus noise best of 12 random settings <strong>−3.4564</strong> (Δ <strong>−0.2412</strong>). These stops do not clear the random-setting floor. Log <code>logs/campaign-mulein-ostwald-adapt.log</code>. Post-gap repairs were not climbed. Settings <code>256..&lt;456976</code> and other shells remain open. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 63: Metal Ostwald on split-menu seeds</div>
              <h3>Eight hundred twenty-four identity repairs, including split-menu trees, climbed on Metal. None cleared the floor.</h3>
              <div className="prose">
                <p>
                  The Phase 62 climber skipped 1,993 split-menu identity repairs before host replay. <code>--mulein-ostwald-split-menu</code> now emits them. Of 2,056 queued identity repairs, host replay kept <strong>824</strong> with at least four forced plugs (38 single-component plus 786 split-menu) and dropped 1,232 below the pair floor. Post-gap stays dense-climb-illegal; a leading-gap walk exists in the climber and was not pointed at those 2,047 hits.
                </p>
                <p>
                  Metal Ostwald batches every live climb's unused-pair trials into one dispatch, with an 8 GB unified-memory cap (~2.68×10<sup>8</sup> 32-byte trials) and Welchman-shaped progress: <code>ETA floor (~10M decrypts/s): 0.0 min</code>, then live <code>4.6M/s ETA 0.0 min</code>. Defaults are board seeds, top-up target 4, exhaust 6, depth 2, climb to 10. All 824 already had four plugs, so this was climb-only. 4-plug hot-letter brute remains refused at exhaust 6 (four pairs need eight letters). Known-key control: eight correct plugs still crib-exact on Metal.
                </p>
                <p>
                  Escalate (2026-09-24T14:57:20Z, exit 0): <strong>NO BREAK</strong>, 824/824 crib BAD. Best climbed <strong>−3.4797</strong> (IC 0.0395) versus noise best <strong>−3.4564</strong> (Δ <strong>−0.0233</strong>). Still below the random-setting floor. Log <code>logs/campaign-mulein-ostwald-metal.log</code>. This is not a decrypt. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 64: CPU Ostwald on every remaining repair</div>
              <h3>Four thousand one hundred one repairs climbed, including empty boards and gapped post-gap. None cleared the break bar.</h3>
              <div className="prose">
                <p>
                  <code>--mulein-ostwald-family both --mulein-ostwald-split-menu --mulein-ostwald-min-pairs 0</code> emitted 4,101 identity and gapped post-gap repairs (2 duplicate-shell skips). CPU Ostwald scored 3,329,721 climbs in 1,779 s at 1.3M decrypts/s.
                </p>
                <p>
                  Escalate (2026-09-24T15:37:38Z, exit 0): <strong>NO BREAK</strong>, 4101/4101 crib BAD. Best <strong>−3.0390</strong> (IC 0.0544, tail −3.0390) at <code>B/beta/IV-III-VIII/AAAA</code> AAIP/AAIT — identical decrypts, not German. That score beats a 12-sample random-setting floor of −3.4564 because 3.33 million climbs will; it is not a near-miss. IC misses 0.055. Log <code>logs/campaign-mulein-ostwald-cpu-everything.log</code>. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 65: 2026 Ostwald path</div>
              <h3>A leave-one-out ranker, a beam climb, and all-settings without the IC sieve. The curve is the gate.</h3>
              <div className="prose">
                <p>
                  Searching the 2014 Ostwald scorer faster cannot flip a negative margin. Phase 65 keeps the climb and changes the objective: a leave-one-out linear ranker fitted on 72-letter known-key windows against wrong-setting decrypts, not uniform random text; a beam of partial boards; <code>--ostwald-keep 0</code> actually unlocking forced plugs; and <code>--ostwald-all-settings</code> climbing every message key on one locked shell so the IC sieve that ranked the true P1030684 key 223,118 / 456,976 is no longer in the way.
                </p>
                <p>
                  Smoke <code>--ostwald-curve --ostwald-scorer ranker --ostwald-lengths 72 --ostwald-controls 8 --ostwald-wrong 8</code> (2026-09-24, exit 0): 6 eligible controls, <strong>2/6 wins, median margin −1.0269</strong> in ranker units. Thin sample.
                </p>
                <p>
                  Full curve <code>--ostwald-curve --ostwald-scorer ranker --ostwald-lengths 72</code> (2026-09-24, exit 0, 5.7 s): 32/48 round-trip, 30 eligible, 16 wrong samples, <strong>5/30 wins (17%), median margin −1.2000</strong>, z 0.59, 1/10 plugs. Decoy-climb fit: <strong>1/30, −1.7306</strong> (worse). Beam 4: <strong>6/30, −1.0925</strong> (still negative). Not a zero crossing, not a crib, not pointed at P1030680. Logs <code>logs/ostwald-curve-ranker-72.log</code>, <code>logs/ostwald-curve-ranker-decoy.log</code>, <code>logs/ostwald-curve-ranker-beam4.log</code>. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 66: 4-plug hot-letter brute</div>
              <h3>Ostwald needs four correct plugs. Ciphertext frequency does not contain them.</h3>
              <div className="prose">
                <p>
                  <code>--ostwald-brute-plugs 4</code> was already built and refused at exhaust 6, because four pairs need eight letters. It is now wired into <code>--ostwald-curve</code> and graded at exhaust 8: 105 perfect matchings, staged scorer, 16 wrong samples.
                </p>
                <p>
                  Result (2026-09-24, exit 0, 26.9 s): <strong>0/32</strong> round-tripping controls have four true plugs among the eight hottest ciphertext letters. Curve <strong>1/30 wins, median −0.1633</strong>, 0/10 plugs. Unclimbed true 4-subsets beat 2048 random 4-plug boards on 8/12 controls, with a still-populated tail (up to 24/2048). A Metal score of all 164 million 4-plug boards does not uniquely surface Phase 50.6. Logs <code>logs/ostwald-curve-brute4-e8.log</code>, <code>logs/ostwald-brute-probe.log</code>. P1030680 remains unbroken.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 67: streamed 4-plug alphabet climb</div>
              <h3>Known-key greeting recovered P1030684. The ghost is crib BAD. Not this ciphertext.</h3>
              <div className="prose">
                <p>
                  C(26,8)×105 = 164,038,875 four-plug boards. Metal greedy insertion from a 4-plug seed is 503 decrypts each, 8.25×10<sup>10</sup> decrypts per locked setting. The 164 million starts stream in waves of 524,288; replacement polish runs only on the top 256 scores in each wave. On the true rotor setting, 210 of those boards are true 4-subsets of a 10-plug board — about 1 in 781,000. Frequency cannot find them (Phase 66, 0/32). The greeting visits all 210; it does not roll a die. Phase 50.6 froze four <em>oracle</em> plugs on a ten-message panel (50% win, median +0.33). That is not a promise that greedy insertion from an enumerated 4-subset prints crib-exact on this 72-letter text. On a wrong setting the same budget raises ghost maxima; 72-letter IC cannot pick them.
                </p>
                <p>
                  <strong>DONE</strong> on true VYAA / 385320 (restart 2026-09-24T16:51:24Z, exit 0 at 17:29:14Z): 313/313 waves, <strong>~37.8 min at 36.3M/s</strong>. <strong>1 candidate clears the break bar</strong> — <code>B/gamma/IV-III-VIII</code> AACU / VYAA, crib ok, IC 0.0657, tail −2.9671, 10 pairs, the known 72-letter window <code>VVVUUUVIRSOBENNULEINS…SECHS</code>. Log <code>logs/ostwald-fourplug-p1030684-true-385320.log</code>. That is a known-key greeting, not a P1030680 decrypt.
                </p>
                <p>
                  <strong>DONE</strong> on wrong AAAA / 0 (launch 2026-09-24T17:30:26Z, exit 0 at 18:08:27Z): 313/313 waves, <strong>~38.0 min at 36.2M/s</strong>. Best candidate crib BAD, IC 0.0509, tail −3.0462, climbed −3.0462, decrypt <code>QWGRINEMUSEMANGN…</code>. <strong>NO BREAK</strong>. Log <code>logs/ostwald-fourplug-p1030684-wrong-0.log</code>. A handful of locked P1030680 settings is eligible as a confirmation test; never 26<sup>4</sup>.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 68: dual path</div>
              <h3>The archival arm stays first. The GPU goes back on Turing's remaining menus.</h3>
              <div className="prose">
                <p>
                  Unicity says 72 letters determine German. That is not a 26<sup>4</sup> lottery. Phase 67 showed the 4-plug alphabet climb can finish a <em>true</em> setting in ~38 minutes and will not hallucinate a BREAK on a ghost — and an empty crib can no longer clear the bar. The missing input is still a historically locked setting, a second Thetis message, or a crib that actually stops. Both arms stay live so neither avenue is abandoned: Selm's archival work, and HELUT's remaining Welchman remainder.
                </p>
                <p>
                  <strong>DONE, no break</strong>, 73/73, exited 2026-09-25T04:59:39Z. Menus 66–73: 5,284,950 raw stops, 40 physical, best IC 0.038, tail −4.629. Menu 62's head still misses the whole-message bar (IC 0.049, tail −4.387). Not a plaintext. Middle ring stayed A. Three <code>FUNKSPRUCHUEBUNG</code> quarantine rows are prefix hits (tails −5.256, −4.534, −4.733 on the whole message) and are not an escalate. The catalog VIII-fast continuation is <strong>running</strong> from menu 418 (451 menus after the 16-letter filter). Log <code>logs/campaign-thetis-register-rings.log</code>.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 69: plugboard marginal</div>
              <h3>The integral compresses the scores. It does not separate the key.</h3>
              <div className="prose">
                <p>
                  Metropolis–Hastings on legal ≤10-plug boards, tempered from β=1 down to 0, graded on 8 known keys against 6 wrong message keys, 3 seeds. The margin got less negative on every seed and the scale-free separation got worse. Win rate stayed at the peak's 12% after the first seed. That is compression, the same failure as the Phase 56.3 proxies. Log <code>logs/plugboard-marginal-probe-20260924.log</code>. Not pointed at P1030680.
                </p>
                <p>
                  Menus 15 and 16 of the live ring sweep each printed one physical stop (IC 0.049, tails −5.028 and −5.804). Both miss the soft tail floor of −4, and the shell was not recorded, so Ostwald has nothing to climb.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">Phase 70: Schlüssel M procedure</div>
              <h3>The Kenngruppen chain is in the manual. FORT is not a crib we can run.</h3>
              <div className="prose">
                <p>
                  Selm Merel Wenselaers recovered the Hellschreiber scan of Bauer’s <em>Ultra versus Enigma</em>. She reports that it reproduces M.Dv.Nr. 32/1 as Appendix E, a May 1945 Hydra key sheet as Appendix F, and Tafel D under Kennwort Quelle as Appendix G. The scan is linked below. Hydra stecker is not this board. Tafel D is not applied to <code>VROL NMKA</code>. A Marinenachrichtenauffangstelle named Thetis is not treated as Schlüsselbereich M-Thetis.
                </p>
                <p>
                  Her reading of the manual separates Schlüsselkenngruppe, Verfahrenkenngruppe, and Spruchschlüssel, and names the missing book: M.Dv.Nr. 98, the K-Buch. That is the archival ask. <code>FORT</code> is the procedure word for a split message. It is four letters. The break bar requires a crib of at least 16, so it is not queued, and it does not appear as its own crib in the catalog. Seventy-two letters is 18 groups, under the manual’s roughly 80-group maximum, so the length does not show that P1030680 is a fragment.
                </p>
                <JournalAttachments
                  kicker={`Attachment · ${SELM_CREDIT}`}
                  files={[selmSchluesselMBauer]}
                />
              </div>
            </article>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Honest Scope</div>
            <h2>The Evidence Room</h2>
            <p>
              The target's working assignment is M-Thetis under the later allocation list used by Hörenberg; reported earlier and later Zuteilungslisten map column 645 differently, so the later list's date and provenance remain open. Preservation among U-534 papers likewise does not establish intended recipient. Online archival levers were exhausted, but the archival arm led by Selm Merel Wenselaers now has active primary-source and collection enquiries. Jessica Mulein’s engine is graded rather than trusted: the blind Welchman control breaks a known key in 352 seconds on the current binary with all ten plugs, and the full middle × right-ring control breaks in 4,307 seconds with no residual ring gap. Current P1030680 evidence remains bounded: catalog right rings through originalIndex 417/2513 are the full-order receipt; the VIII-fast continuation is <strong>running from menu 418</strong> (451 menus, 42 of 336 orders); Thetis-register rings are <strong>done, 73/73, no break</strong> (Phase 71). Menu 62's head meets the head gate, and the whole message misses the bar. Middle ring stayed A. Three prefix quarantine rows are not an escalate. Next morning the catalog resumes at 418 of 2513 under the VIII-fast wheel prior. That one menu was re-run with the middle ring unpinned (`logs/campaign-thetis-register-m62-middlering.log`): 343 raw stops, 4 physical, and the best stop is the same head. Holding its nine plugs and trying every tenth pair, every message key, and every middle ring missed the bar (best IC 0.044, tail −3.710); tolerance 1 × right rings at 3/24; post-gap δ=4 × right rings at 144/237; and full middle × right rings under the VIII-fast prior are <strong>24/24 dead at the board</strong> (42 of 336 wheel orders; the other 294 remain open). The two highest-risk table-cap re-runs are complete and re-confirmed with zero extra survivors; the remaining 300 contaminated catalog placements are retained but deprioritised. The production Verilog Future Bank inside <NaziBlaster9000Span /> agrees across source RTL, post-Yosys RTL, clear JSON, and cleartext Float TensorLUT on P1030684 controls, and complete-receipt benchmarking selected <code>BANK_LANES=4</code> at 276.035 receipts/s. Its operational-prior preflight covered shell 0, setting 0, and all 628 Futures: 628/628 chunks and 16,328 receipts yielded 15 host-replayed one-edge physical candidates, all non-exact, with 0 exact hits and 0 BREAK gates. The Phase 51.16 production stripe then completed settings <code>1..&lt;256</code> across those 628 Futures: <strong>10,048/10,048 chunks, 4,163,640 checked receipts, 4,184 host-verified physical candidates, and 0 BREAK gates</strong>. All 40 exact identity hits and all 41 exact post-gap hits now die at joint ≤10-plug completion: <strong>all 81 exact candidates are split-menu ghosts</strong>. Identity-family repairs with enough forced plugs were consumed by <code>--mulein-ostwald-adapt</code> / <code>--ostwald-escalate</code> (Phases 62–64): <strong>38 then 824 then 4,101 climbed, NO BREAK</strong>, best −3.0390 versus a 12-sample floor of −3.4564 after 3.33 million climbs — not a near-miss. Split-menu identity trees with at least four plugs are in the 824; Phase 64 included empty boards and gapped post-gap. The 2026 Ostwald ranker/beam/all-settings path is built (Phase 65). The 164-million 4-plug alphabet climb <strong>greets on locked P1030684 VYAA</strong> (Phase 67: crib-exact, known 72-letter plaintext); the wrong-setting ghost is <strong>crib BAD</strong> (IC 0.0509, NO BREAK). None of that is a P1030680 key or decrypt. The four-placement P1030668 BLEIBTBESETZT context fixture is <strong>complete: 4/4 dead, 0 raw stops over 2.076×10<sup>11</sup> settings</strong> under the same VIII-fast middle-ring coverage (Phase 60; log <code>campaign-wenselaers-bleibt-besetzt-viii-fast-middlering.log</code>), 0 quarantine. Live archival lines (Phase 61) include a NARA RG 457 key-log request with no box read, a reported R.I.P. 401 non-random wheel-order section that does not yet answer cross-net assignment, a 3 May Ausbildung/Front Kenngruppen test that is not executable until original indicators exist, and Bauer Appendix F is the linked Hydra May 1945 stecker scan (not this ciphertext's board). Tafel D is not applied to the indicators. FORT is four letters and is not queued. Tauschtafelplan Bruno Prüfnr. 1772a now dates P1030680's Kenngruppen table as Quelle / Tafel A on 1 May (selection). Tafel A pairs are photographed in Prüfnr. 2499 (Phase 61.3); 1772a vs 2499 edition compatibility is open, and the 621–653 Thetis crop remains undated. NID 1/PW/REP/17 reconstructs Baltic working-up and radio-watch practice but does not identify Thetis. A Girard-named-class weighted Mulein deletion board is not next: it is a subset of uniform tolerance 1, already dead on the strongest menus. Settings <code>256..&lt;456976</code>, other shells, and the printed legacy remainders remain open. TensorLUT remains a cleartext parallel compiler path, not a Thetis crib, not encrypted tick rate, and not an FHE result. P1030680 remains unbroken.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">SELM</span>
              <div>
                <span>
                  <strong>Named sources, attached as she recovered them.</strong> Selm Merel Wenselaers (Historian / Curator, Amsterdam / Antwerp) leads the archival arm. The files below are her reconstructions and recovered scans, published with her credit. Direct quotations are taken from those files; email rankings that are not on file are labelled paraphrase. They do not mint cribs, do not identify Thetis, and do not imply a decrypt.
                </span>
                <JournalAttachments
                  kicker={`Attachments · ${SELM_CREDIT}`}
                  files={selmAllPublicFiles}
                  previewImages={false}
                />
              </div>
            </li>
            <li>
              <span className="mono">FIXTURES</span>
              <span>
                <strong>The Input Data:</strong> Contains the scraped 1 May corpus (
                <Link to={enigmaPaths.corpus}><code>u534_corpus.json</code></Link>
                ), my 100 mined cribs mapped to 2,513 placements (<code>p1030680_menus.json</code>), the Top-30 turnover set, fuzzed and Thetis-specific fixtures, the known-key control, and the naval trigram model. The <Fahrenheit261Span /> canonical historical unified-bank inventory remains <code>p1030680_mulein_identity_postgap_delta4.json</code> (24 identity + 237 post-gap δ=4 = 261 entries). The separate <NaziBlaster9000Span /> operational-prior inventory is <code>p1030680_mulein_regenbogen_hannibal_identity_postgap_delta4.json</code> (314 identity + 314 post-gap δ=4 = 628 Futures), fingerprint <code>fnv1a64-616326e94036a97d</code>, SHA-256 <code>1086b697d70ef9f05855292dd2e041b94a8551d18b1c51ec12c161a0c974c510</code>. Inventories are input, not execution receipts.
              </span>
            </li>
            <li>
              <span className="mono">LOGS</span>
              <span>
                <strong>The Ledger:</strong> Every campaign, including the embarrassing ones—Welchman controls, catalog and Thetis arms, table-cap audit and corrected re-runs, middle-ring coverage grades, Stochastic controls, TensorLUT shatter/involution grades, and quarantine receipts. The legacy target boundaries are on disk in <code>campaign-tolerance1-strongest-2026-08-17.log</code> (3/24), <code>campaign-indel-postgap-target-2026-08-17.log</code> (144/237), <code>campaign-middlering-strongest-2026-08-16.log</code> (placement 1/24), and <code>campaign-middlering-viii-fast-resume2.log</code> (placements 2–24, 0 stops). The BLEIBTBESETZT 40-letter context arm is <strong>complete</strong> in <code>campaign-wenselaers-bleibt-besetzt-viii-fast-middlering.log</code> (4/4 dead, 0 stops over 2.076×10<sup>11</sup> settings). Identity-repair Ostwald consume is <strong>complete</strong> in <code>campaign-mulein-ostwald-adapt.log</code> (38 climbed, NO BREAK), <code>campaign-mulein-ostwald-metal.log</code> (824 split-menu-inclusive climbed, NO BREAK, best −3.4797 vs noise −3.4564), and <code>campaign-mulein-ostwald-cpu-everything.log</code> (4,101 identity + gapped post-gap, 3,329,721 climbs, NO BREAK, best −3.0390 crib BAD). <code>MuleinFutureTensorLUTTests.swift</code> is the P1030684 four-surface parity receipt. Runtime selection is recorded in <code>logs/mulein-future-tensorlut-selection.json</code> and the five <code>mulein_future_bank*_bench.txt</code> logs. The <Fahrenheit261Span /> bounded target receipt is <code>logs/p1030680-mulein-unified-smoke-v3.jsonl</code>. The <NaziBlaster9000Span /> operational-prior preflight receipt is <code>logs/p1030680-mulein-operational-preflight-v3.jsonl</code>, SHA-256 <code>55a68266f79ca0b17b6de18a80644883c7c8a2585ab2508d42d5d73c9a17f993</code>, run <code>sha256-2b6bde1ead5ffd33b3e598038a7af597d9c1c189c9b607147c98451a527c727a</code>: 16,328 checked receipts, 15 repaired/non-exact physical candidates, 0 exact hits, and 0 BREAK gates. Its completed production ledger is <code>logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl</code>, SHA-256 <code>c516238d5420bde46fb7bdc76078ac086b5946de2374f8d7a4b4d56b1e7e52f2</code>, run <code>sha256-efb770bcaddd2bc0581edbb19b66077160a806c30650a60d0b9d6a733c592cc0</code>: 10,048 synchronized chunks, 4,163,640 checked receipts, 4,184 host-verified physical candidates, and 0 BREAK gates; no candidate supplied scored plaintext, a key, or a decrypt.
              </span>
            </li>
            <li>
              <span className="mono">VICTORY CONDITIONS</span>
              <span>
                <strong>The Rules of Engagement:</strong> I claim a break only when five things align: a naval German plaintext, an exact crib match, an IC ≥ 0.055, a trigram tail &gt; −3.600, and a physically possible ≤ 10-plug board — judged over the whole message, or over a readable head of at least 16 letters outside the crib. Cribs under 16 cannot solo-claim a break; under confirm-2 they only re-test shells a ≥16 anchor already locked. Stochastic Bombe halt is exact template match under a ≤10-plug board—never a high bigram score alone. Anything less is a ghost.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Plan</div>
            <h2>What is left, in order of cheapness</h2>
            <p>
              The head-gate re-read, the fuzzed turnover arm, UEBUNG arms, and the current stochastic priors are closed. Everything below is priced in real GPU time on one Apple Silicon machine. One crib placement, swept across all 26 ring phases, is 16 billion machine settings and takes about six and a half minutes—roughly 190 placements a day.
            </p>
          </div>

          <div className="timeline">
            <article className="tl-item">
              <div className="when">1 — Done, clean negative</div>
              <h3>Re-read the catalog under the head gate.</h3>
              <div className="prose">
                <p>
                  868 menus, half a trillion settings, three physical boards, zero breaks. The mid-message divergence hypothesis does not hide a key in the turnover-free slice. That cheap hope is closed.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">2 — Done, clean negative</div>
              <h3>Finish the fuzzed sweep I abandoned.</h3>
              <div className="prose">
                <p>
                  Full top-40 fuzzed ring sweep closed with zero raw stops. Orthographic fuzzing of Potsdam register language is exhausted under right-ring coverage.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">3 — Parked: catalog resume from originalIndex 418</div>
              <h3>Sweep every ring phase on every exact crib.</h3>
              <div className="prose">
                <p>
                  OriginalIndex 1–417/2513 are done—all dead at the board—in <code>logs/campaign-catalog-rings.log</code> (last <code>VVVUUUDREINULEINSVI@25</code>). Resume with <code>--bombe-from 418</code> (quarantine → <code>logs/quarantine_candidates.json</code>). The legacy Phase-23 Regenbogen/Hannibal slices are closed only for the exact strings and AAAA/right-ring scopes actually tested; correction-aware operational Futures remain an active, separate arm.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">4 — Done, clean negative</div>
              <h3>Stop speaking Potsdam. Try UEBUNG.</h3>
              <div className="prose">
                <p>
                  Forty-six ≥16 training-header pads at offsets 0–2 under rings AAAA: every stop was a ghost—zero physical boards. Those exact Thetis openings are not sitting at the absolute head in the turnover-free slice.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">5 — Done, clean negative</div>
              <h3>Pair a Thetis head with a mid-message body crib.</h3>
              <div className="prose">
                <p>
                  All forty ≥16 mid-message body anchors died at the board under rings AAAA, so confirm-2 could not fire. Short <code>UEBUNG</code> headers then flooded the host with tens of millions of ghost completions; the “clears the bar” lines were prefix flukes—whole-message IC and tail still failed. I aborted, taught confirm mode to only re-test shells a ≥16 anchor already locked.
                </p>
                <p>
                  Ring-sweep of those same forty bodies: every menu dead at the board, zero raw stops across 6.4×10¹¹ settings. Turnover does not save the “header pushes the body back” claim for these cribs. The Übung-push hypothesis is exhausted under right-ring coverage — and since all forty were later found to be contaminated by the table-cap bug, that sweep has been re-run on the corrected kernel with the same verdict.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">6 — done, 73 of 73, no break</div>
              <h3>Probe Thetis register: Kenngruppe and training openings.</h3>
              <div className="prose">
                <p>
                  Seventy-three ≥16 Kenngruppe/training placements at the head under rings AAAA: three physical boards, zero breaks. The right-ring arm finished 73 of 73 on 2026-09-25 with no break. Menu 62 on <code>SCHULFUNKSPRUCHX@1</code> misses the whole-message bar (IC 0.049, tail −4.387). The head through letter 32 meets the head gate (IC 0.058, tail −3.416). That head is not a plaintext. Three <code>FUNKSPRUCHUEBUNG</code> rows were quarantined on a prefix score; the whole message on each is past the soft tail. Middle ring stayed A. The catalog continuation from 418 is running with VIII on the fast wheel.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">7 — Done, clean negatives under rigor bar</div>
              <h3>Stochastic Bombe: training, collapse, weather, RIGA.</h3>
              <div className="prose">
                <p>
                  Training structural, collapse/tactical, weather/keyboard/Kurzsignal, meta-evolve, and shell-RIGA with free rings: all zero survivors. Coincidence ceiling ~60–69%. More immigration does not invent plaintext. Stochastic stays parked; menus stay on Welchman.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">8 — Complete under VIII-fast; 294 wheel orders remain open</div>
              <h3>Unpin the middle ring on the best menus.</h3>
              <div className="prose">
                <p>
                  This arm opens the 8–15% middle-ring gap the earlier audit identified. It is no longer twenty-six times the cost. Notch tests depend on window position, not on the ring, so a lane whose middle wheel never reaches its notch — and whose ring-A partner at window <em>m</em>−ρ never does either — is the <em>same machine</em> as that partner. Ring A runs in full, rings B–Z run only their notch-hitting lanes, and the union is complete coverage rather than a sample.
                </p>
                <p>
                  I graded that equivalence before trusting it, because a coverage shortcut that quietly drops keys is the same bug as the one below. On the validated host board, 2.4 million claimed-covered pairs, zero verdict mismatches. Through the Metal kernel, with roughly 5,600–6,900 survivors per ring actually discarded, every discarded verdict is carried identically by its ring-A partner.
                </p>
                <p>
                  Then I ran the blind control at <em>full</em> middle × right ring coverage — 908,544 shells, 4.15×10<sup>11</sup> settings, the first run in this campaign with no residual ring gap anywhere. It breaks: same key, all ten plugs, IC 0.064, tail −2.848, in 4,307 seconds at 96.4M settings/s. Twenty-six times the search space for 12.2× the time, because about 70% of lanes exit after the trail test. Raw stops went from 2 to 4, which is the mechanism working rather than a fault — unpin the middle ring and the true machine has several ring-equivalent representations for the sweep to find.
                </p>
                <p>
                  The target arm then completed. Placement 1 died at the board over 4.152×10<sup>11</sup> settings at all 336 wheel orders. Placements 2–24 resumed under the VIII-fast prior: <strong>23/23 dead, 0 raw stops over 1.194×10<sup>12</sup> settings</strong> at 72.1M/s, 0 physical, 0 quarantine. That is a clean negative on 42 of 336 wheel orders with no residual ring gap, not a verdict on the other 294, and not a decrypt.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">8b — Highest-risk re-runs done; remainder deprioritised</div>
              <h3>Re-run the arms a table cap mis-reported.</h3>
              <div className="prose">
                <p>
                  Cheapest outstanding work in the campaign, because the damage is concentrated rather than spread. Ordered by contaminated share per GPU-hour:
                </p>
                <p>
                  <strong>Done —</strong> the Übung body arm, contaminated on all 40 of 40 placements: 40/40 dead, zero raw stops, negative re-established. <strong>Done —</strong> the curated top-30, contaminated on 20 of 30: 73 raw stops over 4.79×10<sup>11</sup> settings, identical to the archived figures, best board IC 0.041 / tail −4.819, no break. In both arms the previously-untested lanes produced <em>zero</em> extra survivors — the bug was not hiding a key. <strong>Deprioritised —</strong> the remaining 300 catalog placements (~32 h); the two fuzzed arms remain retained at still lower priority. Strong representatives are already present in the partial full-middle-ring arm.
                </p>
                <p>
                  One thing I got wrong on the first pass: rings AAAA is the wrong re-run for these. My own sweep banner reports AAAA as covering 0 of 26 ring phases once a menu passes 26 letters, so the AAAA pass never carried a meaningful negative for a 28-to-40-letter menu in the first place. Right-ring coverage is the claim that actually needs re-establishing.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">10a — Tolerance suspended at 3/24</div>
              <h3>Resume the one-edge Mulein arm from placement 4.</h3>
              <div className="prose">
                <p>
                  The 24 strongest loop-rich menus passed pre-qualification. Under tolerance 1 × right rings, the first three are dead at the board. Resume <code>--bombe-menus 0 --bombe-ring-sweep --bombe-garble-tolerance 1 --bombe-from 4</code>; 21 placements remain. A completed negative allows any one crib-span edge to be removed, but the partial prefix does not eliminate garble generally.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">10b — Post-gap δ=4 suspended at 144/237</div>
              <h3>Resume the exact-board indel arm from splice 145.</h3>
              <div className="prose">
                <p>
                  Entries 1–110 and 112–144 are dead at the board. Entry 111's eight raw stops all fail valid ≤10-plug completion. Resume <code>--bombe-menus 0 --bombe-from 145</code>; 93 hypotheses remain, with the middle ring still pinned at A. No physical candidate and no break.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">10c — <NaziBlaster9000Span /> bounded stripe DONE; identity Ostwald DONE</div>
              <h3>Replay of identity-family repairs, including split-menu trees, is a clean negative.</h3>
              <div className="prose">
                <p>
                  The separate 628-Future operational inventory completed setting 0 across shell 0, then completed settings <code>1..&lt;256</code> across every Future. The production receipt contains <strong>10,048/10,048 new chunks, 4,163,640 checked receipts, 4,184 host-verified physical candidates, and 0 BREAK gates</strong> in <code>logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl</code>, run identity <code>sha256-efb770bcaddd2bc0581edbb19b66077160a806c30650a60d0b9d6a733c592cc0</code>. It produced no scored plaintext, key, or decrypt; broader settings and shells remain open.
                </p>
                <p>
                  Exact-family replay is done: all 81 exact candidates are split-menu ghosts. Identity-family and gapped post-gap repairs were climbed (Phases 62–64): <strong>38 then 824 then 4,101 crib BAD, NO BREAK</strong>. Phase 64's best −3.0390 (IC 0.0544) vs a 12-sample floor after 3.33 million climbs is not a near-miss. The 2026 Ostwald ranker/beam path (Phase 65) and the 4-plug hot-letter brute (Phase 66) are graded negatives; the 164-million 4-plug alphabet climb <strong>greets on locked P1030684 VYAA</strong> (Phase 67, crib-exact, known plaintext) and the AAAA ghost is crib BAD (IC 0.0509, NO BREAK), log <code>logs/ostwald-fourplug-p1030684-wrong-0.log</code>. Not a P1030680 consume. Four correct plugs still finish a true stop. A translation audit found 1,724 identity/post-gap pairs at a four-lane setting shift, so another broad TensorLUT stripe or same-shape leading δ6/δ8 stripe is low-information. Ordinary legacy resumes stay at their printed durable boundaries. This is a working search order, not evidence of a historical plaintext or a claim that P1030680 is garbled.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">9 — Parallel: TensorLUT involution</div>
              <h3>Freeze the core; evolve reciprocal plugs.</h3>
              <div className="prose">
                <p>
                  Full INIT melt and stecker-cone melt are diagnosed dead ends. The live arm freezes the known-good TensorLUT silicon and searches a ≤10-pair involution sandwich. Blind three-pair rediscovery on a fourteen-letter crib already PASSed. Still parallel research—not a substitute for catalog right-ring coverage from originalIndex 418.
                </p>
              </div>
            </article>
          </div>
        </div>
      </section>
      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The Legacy</div>
            <h2>Walking in Turing's Footsteps</h2>
            <p>
              Alan Turing designed the original Bombe to break the unbreakable. He gave the world the foundation of modern computer science, saved countless lives, and was ultimately driven to his death by a government that criminalized his existence.
            </p>
          </div>
          <div className="prose">
            <p>
              Eighty years later, history is rhyming with a chilling resonance.
            </p>
            <p>
              I am writing this in 2026 as a trans woman in America. With Trump at the helm, transgender rights are eroding daily, and state-sanctioned persecution is at a high not seen in recent history. The hostile political machinery Turing faced is not a relic of the past; it is the reality I am navigating right now.
            </p>
            <p>
              I have been at the console engineering systems for nearly four decades, but building this specific engine means something more. Weaponizing Turing’s exact logical reductions—pinning the rotors, collapsing the search space, and relying on absolute Boolean truth to hunt down this final Kriegsmarine ghost—is an act of survival and defiance.
            </p>
            <p>
              It is about finishing the mission he started. It is about honoring the community I share with him, and proving that the brilliant, persecuted minds the state tries to crush will always be the ones who build the future—regardless of the personal cost.
            </p>
          </div>
        </div>
      </section>
    </main>
  )
}
