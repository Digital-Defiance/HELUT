export function JournalPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Turing Complete</div>
            <h2>The ledger of an 80-year-old ghost</h2>
            <p className="lede">
              On May 1, 1945, in the dying days of World War II, a German U-boat transmitted a 72-letter encrypted message across the Baltic Sea. It was encoded using a four-rotor Enigma M4 machine on a training network known as M-Thetis. The Allied forces at Bletchley Park never bothered to break this specific network, assigning it no operational value, and the German operators printed their daily key sheets on water-soluble paper that dissolved decades ago.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              For eighty years, message P1030680 has remained unbroken. In cryptography, tracking what failed is just as vital as recording what worked. This is my operational log—a chronological record of every ghost I chased off the board on my way to the true key.
            </p>
          </div>

          <div className="status-strip">
            <div className="stat">
              <div className="label">Indicators</div>
              <div className="value">VROL NMKA</div>
            </div>
            <div className="stat">
              <div className="label">Key-Net</div>
              <div className="value">M-Thetis (Confirmed)</div>
            </div>
            <div className="stat">
              <div className="label">Ciphertext</div>
              <div className="value">72 letters (JCRSA…HVGF)</div>
            </div>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Chronology</div>
            <h2>Hunting the true key, step by step</h2>
            <p>
              When you are trying to break a cipher this old, your first instinct is to let a computer guess the answer. I learned very quickly that guessing is exactly what the Enigma machine was designed to defeat. Here is the true chronological history of my attack on U-534.
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
                  Before spinning up the graphics cards again, I scraped the historical archives. I pulled a corpus of 50 message pages intercepted from U-534 on that exact same day: 48 broken M4 messages, one hand-cipher, and exactly one unbroken Enigma message—mine.
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
              <h3>Building a flawless digital Bombe.</h3>
              <div className="prose">
                <p>
                  I abandoned statistics and engineered a massive, Metal-accelerated digital version of Gordon Welchman’s WWII diagonal board. Instead of guessing, it uses pure Boolean logic to test for contradictions, rejecting impossible physical states at a blistering 40 million settings per second.
                </p>
                <p>
                  To make it faster, I optimized my software to perfectly match the physical reality of the 1945 hardware. Because the far-left Enigma rotor (the Greek wheel) never steps during a short message, and the left rotor's notch drives nothing, I digitally pinned them in place. This Turing-shaped architectural decision collapsed the search space by a massive factor of 676.
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
                  During my first major sweep, I thought I had cracked it. I tested the common naval phrase <code>UUUVIRSIBENNULEINS</code> at the very beginning of the message (offset 0). The GPU engine spit out 12 surviving rotor states where the logical math worked perfectly.
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
                  It broke it in 361 seconds. Out of 16 billion settings the engine surfaced exactly two, and one of them was the truth: reflector B, Greek gamma, rotor order IV-III-VIII, and all ten historical plugboard cables—<code>BQ CH DI EJ GL KP NV OU SZ TY</code>—followed by 119 letters of clean naval German. It even reported the rings as <code>AAAH</code> instead of the historical <code>AACU</code>, which is not an error but a proof: those two settings are mathematically the same machine, and watching my engine land on the equivalent form confirmed that the 676× shortcut I built on Turing's reduction is sound.
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
                  My sweep printed <em>"turnover phase fully covered, elimination is complete"</em> whenever I swept the ring settings. That was too strong. Sweeping the fast rotor's ring covers every phase of <em>its</em> turnover, but I keep the middle ring pinned at A, and that shortcut only holds while the middle rotor doesn't click over inside the crib itself. No run I have ever launched has tested any other middle ring. Somewhere between 8% and 15% of all possible keys have never been on the board at all.
                </p>
                <p>
                  Worse, I went back through the terminal history and found my fuzzed turnover sweep had been killed at menu 18 of 40—I had been treating half an arm as a finished negative. I finished that arm properly (Phase 10: clean). And of my 2,513 catalog placements, only 886 were ever long enough to test—and of those 886, exactly <strong>54</strong> have had genuine ring coverage. My "clean negative on the full catalog" was a negative across less than a fifth of the ring space.
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
                  I started the exact ≥16 catalog ring sweep, then parked it at menu 57 of 868—all dead at the board so far—in <code>logs/campaign-catalog-rings.log</code>. Resume is <code>--bombe-from 58</code> with append. I was not going to spend the remaining days forcing Potsdam register onto a training net while a Thetis-shaped opening was still untested.
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
              </div>
            </article>
            <article className="tl-item">
              <div className="when">Phase 17: Thetis Register</div>
              <h3>Not Potsdam. Not more UEBUNG. Try the training desk.</h3>
              <div className="prose">
                <p>
                  With Übung-push exhausted, I am probing Kenngruppe drill from this message’s own keying material—<code>ACH</code>, <code>SEDM</code>, <code>OEDM</code>—and school/training openings like <code>AUSBILDUNG</code>, <code>LEHRGANG</code>, <code>ANALLEFUNKSTELLEN</code>, at the head, length ≥16. The scraped “plaintext” field is Girard’s Buchgruppen worksheet, not a decrypt; I am not cribbing that.
                </p>
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
              I know the Potsdam 1 May keys decrypt other U-534 traffic, but not this message. The archival levers are spent. My engine is graded rather than trusted—a blind control breaks a known key through the full campaign in 361 seconds. Exact catalog and fuzzed arms under rings AAAA are clean negatives; so is the ≥16 UEBUNG head. The mid-message “Übung push” claim is dead under AAAA and under full right-ring sweep (40/40 body anchors, zero stops). What remains: parked catalog rings at menu 57/868, no middle ring but A, and Thetis-register probes now running.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">FIXTURES</span>
              <span>
                <strong>The Input Data:</strong> Contains the scraped 1 May corpus (<code>u534_corpus.json</code>), my 100 mined cribs mapped to 2,513 placements (<code>p1030680_menus.json</code>), the Top-30 turnover set, the fuzzed operator-error menus, the Thetis UEBUNG fixtures, the Thetis-register fixture (<code>p1030680_thetis_register_menus.json</code>), the known-key control fixture, and my naval trigram model.
              </span>
            </li>
            <li>
              <span className="mono">LOGS</span>
              <span>
                <strong>The Ledger:</strong> A record of every campaign, including the ones that embarrass me. The false-alarm catalog run, the top-30 and fuzzed top-40 ring sweeps, the blind control (<code>control-p1030684-rings.log</code>), the head-gate catalog re-read, the UEBUNG arm 1 clean negative, the arm 2 pair run aborted in a ghost flood (<code>campaign-uebung-pair-aaaa.log</code>), and the parked catalog rings log.
              </span>
            </li>
            <li>
              <span className="mono">VICTORY CONDITIONS</span>
              <span>
                <strong>The Rules of Engagement:</strong> I claim a break only when four things align: a naval German plaintext, an exact crib match, an IC ≥ 0.055, and a physically possible ≤ 10-plug board — judged over the whole message, or over a readable head of at least 16 letters outside the crib. Cribs under 16 cannot solo-claim a break; under confirm-2 they only re-test shells a ≥16 anchor already locked. Anything less is a ghost.
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
              The head-gate re-read, the fuzzed turnover arm, and both UEBUNG AAAA arms are closed. Everything below is priced in real GPU time on one Apple Silicon machine. One crib placement, swept across all 26 ring phases, is 16 billion machine settings and takes about six and a half minutes—roughly 190 placements a day.
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
              <div className="when">3 — Parked at menu 57 of 868</div>
              <h3>Sweep every ring phase on every exact crib.</h3>
              <div className="prose">
                <p>
                  I started the four-day ring sweep and parked it to chase another theory. Menus 1–57 are done—all dead at the board—in <code>logs/campaign-catalog-rings.log</code>. Resume later with <code>--bombe-from 58</code> and append to that log; do not restart from menu 1.
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
                  Ring-sweep of those same forty bodies: every menu dead at the board, zero raw stops across 6.4×10¹¹ settings. Turnover does not save the “header pushes the body back” claim for these cribs. The Übung-push hypothesis is exhausted under right-ring coverage.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">6 — Running — hours</div>
              <h3>Probe Thetis register: Kenngruppe and training openings.</h3>
              <div className="prose">
                <p>
                  Not Potsdam. Not more <code>UEBUNG</code> pads. Head offsets, length ≥16, rings AAAA first. Catalog ring sweep stays parked until this cools.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">7 — About 2.5 days</div>
              <h3>Unpin the middle ring on the best menus.</h3>
              <div className="prose">
                <p>
                  The 8–15% of keys my audit says have never been on the board. Twenty-six times the cost, so it only earns its slot on menus that ever live.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">8 — Parked, last resort</div>
              <h3>Catalog ring sweep can wait.</h3>
              <div className="prose">
                <p>
                  Menus 1–57 of the exact ≥16 ring sweep are already dead in <code>logs/campaign-catalog-rings.log</code>. Resume with <code>--bombe-from 58</code> only if Thetis-register probes cool. I still do not believe in spending the remaining days forcing Potsdam register onto a training net.
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
