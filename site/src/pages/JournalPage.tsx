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
              <div className="when">Phase 10: The Interrupted Arm</div>
              <h3>45% of a sweep is not a negative.</h3>
              <div className="prose">
                <p>
                  I launched a ring sweep on the curated top-40 fuzzed menus and treated the log as finished. An audit of the terminal history showed the process had died at menu 18 of 40—no completion summary, eighteen placements dead at the board, zero raw stops. That is not a clean negative; it is half an arm.
                </p>
                <p>
                  Menus 19 through 40 are back on the GPU now, on the rebuilt engine so whatever they produce is judged by the head-reading gate rather than the old whole-message score. Closing an arm properly is cheaper than opening a new one.
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
                  Worse, I went back through the terminal history and found my fuzzed turnover sweep had been killed at menu 18 of 40. I had been treating it as a finished clean negative. It was 45% of one arm. And of my 2,513 catalog placements, only 886 were ever long enough to test—and of those 886, exactly <strong>54</strong> have had genuine ring coverage. My "clean negative on the full catalog" was a negative across less than a fifth of the ring space.
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
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Honest Scope</div>
            <h2>The Evidence Room</h2>
            <p>
              I know the Potsdam 1 May keys decrypt other U-534 traffic, but not this message. The archival levers are spent. My engine is graded rather than trusted—a blind control breaks a known key through the full campaign in 361 seconds. But my audit is blunt about the rest: 54 of 886 placements have real ring coverage, no middle ring but A has ever been tested, and 1,627 short placements were never tried at all. Here is the strict index of my artifacts and victory conditions.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">FIXTURES</span>
              <span>
                <strong>The Input Data:</strong> Contains the scraped 1 May corpus (<code>u534_corpus.json</code>), my 100 mined cribs mapped to 2,513 placements (<code>p1030680_menus.json</code>), the Top-30 turnover set, the fuzzed operator-error menus (<code>p1030680_fuzzed_menus.json</code>), the known-key control fixture (<code>p1030684_control_menus.json</code>), and my naval trigram model.
              </span>
            </li>
            <li>
              <span className="mono">LOGS</span>
              <span>
                <strong>The Ledger:</strong> A record of every campaign, including the ones that embarrass me. The early openings sweeps that yielded zero stops (<code>welchman-openings.log</code>), the false-alarm catalog run (<code>campaign-all-menus.log</code>), the completed top-30 turnover sweep (<code>campaign-top30-rings.log</code>) — clean negative — the fuzzed sweep I wrongly called finished at 18 of 40 menus, its resume still in flight (<code>campaign-fuzzed-top40-rings-resume.log</code>), and the blind control that broke a real key in six minutes (<code>control-p1030684-rings.log</code>).
              </span>
            </li>
            <li>
              <span className="mono">VICTORY CONDITIONS</span>
              <span>
                <strong>The Rules of Engagement:</strong> I claim a break only when four things align: a naval German plaintext, an exact crib match, an IC ≥ 0.055, and a physically possible ≤ 10-plug board — judged over the whole message, or over a readable head of at least 16 letters outside the crib. Anything less is a ghost.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The Plan</div>
            <h2>Six moves left, in order of cheapness</h2>
            <p>
              Everything below is priced in real GPU time on one Apple Silicon machine. One crib placement, swept across all 26 ring phases, is 16 billion machine settings and takes about six and a half minutes—roughly 190 placements a day. That number is what makes this a campaign and not a coin flip.
            </p>
          </div>

          <div className="timeline">
            <article className="tl-item">
              <div className="when">1 — Code shipped, 8 hours of GPU left</div>
              <h3>Re-read the survivors I already threw away.</h3>
              <div className="prose">
                <p>
                  This is the move I would bet on. My linguistic scanner scores the whole 72-letter decrypt. But if the true key clicks the middle rotor over <em>after</em> my crib and before the end of the message, the plaintext comes out perfect across the crib and turns to garbage after it—so the whole-message score lands halfway between German and noise, below my threshold, and I discard the answer.
                </p>
                <p>
                  My catalog runs already produced <strong>2,219 physically valid ten-plug boards</strong> that I rejected on that score alone. There is a real chance the key is already sitting in a log file I wrote weeks ago.
                </p>
                <p>
                  The code for this is now written. My engine scores the readable head of a decrypt as well as the whole message, and it will accept a break on either. I proved it two ways before trusting it: my known-key control still breaks identically, and the infamous menu-627 ghost still dies—its best head scores <em>worse</em> than its whole message, which is exactly right, because you cannot manufacture a correct beginning out of noise. What remains is the eight hours of GPU time to re-read the survivors.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">2 — Running now, about 2.5 hours</div>
              <h3>Finish the fuzzed sweep I abandoned.</h3>
              <div className="prose">
                <p>
                  Twenty-two placements remain from the run that died at menu 18. Closing an arm properly is cheaper than opening a new one, and I no longer get to call it a negative until it finishes. It is on the GPU as I write this, on the rebuilt engine, so whatever it finds gets judged by the new scoring rather than the old.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">3 — About 4 days</div>
              <h3>Sweep every ring phase on every exact crib.</h3>
              <div className="prose">
                <p>
                  886 placements × 26 ring phases. This is the run that converts my comfortable-sounding negative into a real one: right now I have eliminated the exact historical cribs across less than a fifth of the ring space. Until this finishes, everything I believe about exact cribs is a guess.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">4 — About 8 hours to triage</div>
              <h3>Bring back the 1,627 short cribs—in pairs.</h3>
              <div className="prose">
                <p>
                  I banned cribs under 16 letters because a 14-letter phrase produced my worst false alarm. That ban was right for a crib judged <em>alone</em>. But two <em>independent</em> short cribs landing on the same rotor state is a completely different claim, and my engine already supports that kind of cross-confirmation.
                </p>
                <p>
                  This is the only move that adds genuinely new attack surface instead of grinding harder on the same wedges—it recovers the 65% of my catalog that I have never tested.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">5 — About 2.5 days</div>
              <h3>Unpin the middle ring on the best menus.</h3>
              <div className="prose">
                <p>
                  The 8–15% of keys my audit says have never been on the board. Twenty-six times the cost, so it only earns its slot on the strongest twenty placements, and only after move 3 comes back empty.
                </p>
              </div>
            </article>

            <article className="tl-item">
              <div className="when">6 — Back to the archives</div>
              <h3>Stop asking a training net to speak Potsdam.</h3>
              <div className="prose">
                <p>
                  If the first five moves are clean, the wedge is wrong and not the offsets. A 72-letter Thetis message plausibly opens with a callsign or key group before the body ever starts—which would put the real crib short, and somewhere around letter 5 to 15. That makes move 4, not move 3, the one that lands. And it means the next real breakthrough may come from a records office rather than a GPU.
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
