import { Link } from 'react-router-dom'
import { HelutSpan } from '../HELUTSpan'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'
import { Fahrenheit261Span } from '../Fahrenheit261Span'

export function MuleinBoardPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">
              <Link
                to="/projects/p1030680/journal"
                style={{ color: 'inherit', textDecoration: 'none' }}
              >
                Project · P1030680
              </Link>
              {' · '}Mulein Board
            </div>
            <h2>The Mulein board: a diagonal board that counts contradictions</h2>
            <p className="lede">
              On a physical bombe, a contradiction <em>is</em> electricity finding a second path through the diagonal board. The hypothesis short-circuits, the drum advances, and the machine moves on. There is no register to count in, and no way to ask a wire to keep going after it has already conducted. Copper cannot answer the question <em>how many</em> contradictions.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              In silicon it can. The Mulein board asks: <strong>how few menu edges must I delete before this rotor setting closes consistently?</strong> Delete up to <em>t</em> of them and accept the setting. At tolerance zero it is Gordon Welchman's board, bit for bit. Above zero it is a machine the 1940s could not have built — not slowly, but at all.
            </p>
            <p className="lede" style={{ marginTop: '1rem' }}>
              <NaziBlaster9000Span /> is the formal name of the unified P1030680 Mulein search machine and overall campaign. <Fahrenheit261Span /> is its historical 261-entry canonical-menu/Future campaign; only identity Future 0 ran in that bounded slice, so the name never substitutes inventory for coverage.
            </p>
          </div>

          <div className="status-strip">
            <div className="stat">
              <div className="label">Mechanism</div>
              <div className="value">Known-key PASS</div>
            </div>
            <div className="stat">
              <div className="label">Target prefixes</div>
              <div className="value">t1 3/24 · indel 144/237</div>
            </div>
            <div className="stat">
              <div className="label">Middle × right</div>
              <div className="value">Suspended 1/24</div>
            </div>
            <div className="stat">
              <div className="label"><Fahrenheit261Span /></div>
              <div className="value">W4 · 1/261 · 256 settings · 0 hits</div>
            </div>
            <div className="stat">
              <div className="label"><NaziBlaster9000Span /></div>
              <div className="value">RUNNING · 628 Futures · outcomes unknown</div>
            </div>
          </div>

          <div className="prose" style={{ marginTop: '1.5rem' }}>
            <p>
              <strong>Listen while you read.</strong> The <HelutSpan /> theme is presented here as an optional companion to the board story. Playback never starts automatically.
            </p>
            <audio className="theme-song-player" controls preload="metadata">
              <source src="/HELUT.mp3" type="audio/mpeg" />
              Your browser does not support the audio element.
            </audio>
            <div className="cta-row">
              <a className="btn ghost" href="/HELUT.mp3" download>
                Download HELUT.mp3
              </a>
            </div>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Lineage</div>
            <h2>On whose shoulders</h2>
            <p>
              Nothing here breaks with the 1940s design. It is one more board bolted onto a machine other people built, and the credit runs in a straight line.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">1932</span>
              <span>
                <strong>Marian Rejewski</strong>, with Jerzy Różycki and Henryk Zygalski at the Biuro Szyfrów, broke Enigma mathematically — recovering the rotor wiring from permutation theory. Everything downstream rests on the fact that Enigma is a <em>group</em>, and therefore attackable at all.
              </span>
            </li>
            <li>
              <span className="mono">1939</span>
              <span>
                <strong>Alan Turing</strong> built the bombe: take a probable word, test it against every rotor setting, and reject by contradiction. Our sweep is his loop, expressed in Metal. The 676× reduction that pins the Greek and left rings is his shape of argument too.
              </span>
            </li>
            <li>
              <span className="mono">1940</span>
              <span>
                <strong>Gordon Welchman</strong> added the diagonal board, exploiting the fact that the plugboard is an <em>involution</em>: if σ(x)=y then σ(y)=x. That is the half that lets a single hypothesis constrain the whole board. Our closure function <em>is</em> his board, and the tolerant path routes straight to it at tolerance zero so the common case cannot drift from the historical machine.
              </span>
            </li>
            <li>
              <span className="mono">CORPUS</span>
              <span>
                <strong>Dan Girard</strong> and <strong>Frode Weierud</strong>, hosted by Hörenberg, recovered and published the U-534 traffic and degarbled the sister message P1030681 from two disagreeing transcripts. They supply the 48 known-key controls every grade on this page is measured against — and the entire empirical reason to believe garble matters. Girard found an entire four-letter group present on one copy and blank on the other.
              </span>
            </li>
            <li>
              <span className="mono">SCORER</span>
              <span>
                <strong>Olaf Ostwald</strong> and <strong>Frode Weierud</strong> built the crib-free ciphertext-only attack that hill-climbs the plugboard per candidate setting. Their work is what makes a tolerant board <em>usable</em> rather than a ghost factory: it adjudicates the extra stops. Their <code>enigma-cuda</code> even documents an interface for seeding plugs "from running a bombe" — which required typing them in by hand, because the bombe was somebody else's program.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Why bother</div>
            <h2>An exact board throws away a garbled true key</h2>
          </div>
          <div className="prose">
            <p>
              This is the entire motivation, and it is narrow enough to state in one sentence: a single mis-transcribed ciphertext letter contradicts a <strong>true</strong> menu, and an exact board then discards the real key without comment or trace.
            </p>
            <p>
              That is not hypothetical. Girard needed two independent transcripts to degarble P1030681 — the Dönitz message from the same boat, the same day, the same signals office as our target — and found a four-letter group, <code>HMHY</code>, present on the Schlüsselzettel copy and simply blank on the plain-paper one.
            </p>
            <p>
              So every exact-crib clean negative in the campaign ledger, and there are dozens, is a negative about the ciphertext as it was <em>written down</em>, not necessarily as it was <em>transmitted</em>. The Mulein board is how those negatives get re-opened against a transcription error, instead of re-run identically and called a result twice.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Architecture</div>
            <h2>Two failure modes, two mechanisms</h2>
            <p>
              Transcription error is edit distance, and edit distance has two halves. They need different machinery inside one campaign system: substitution relaxes closure, while an indel changes Future geometry. Keeping that distinction visible is what makes a combined hardware receipt interpretable.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">SUBSTITUTION</span>
              <span>
                <strong>A letter read wrong</strong> — <code>U</code> transcribed as <code>N</code>. The letter is wrong at a position we know. Fix: delete that menu edge. This is the Mulein board, and it works by relaxing the <em>deduction</em> while the crib-position → rotor-step alignment stays fixed.
              </span>
            </li>
            <li>
              <span className="mono">INDEL</span>
              <span>
                <strong>A group dropped or duplicated</strong> — Girard's missing <code>HMHY</code>. Here every letter is <em>correct</em>; they simply sit at <em>shifted positions</em>. After the splice, each edge pairs with a different machine state entirely. Nothing is relaxed — it is a different, and more specific, hypothesis. Fix: re-index the edges and shift the step numbers.
              </span>
            </li>
          </ul>
          <div className="prose" style={{ marginTop: '1.5rem' }}>
            <p>
              <strong>Both are the Mulein board</strong> — one board, two mechanisms, and the consequences favour the indel half. An indel needs no new board at all: the GPU kernel already reads a per-edge step array, so a spliced menu runs on the historical <em>exact</em> board with no kernel change. Which means <strong>zero survivor inflation</strong> — the entire cost problem below simply does not arise, and no pre-qualification gate is needed.
            </p>
            <p>
              It is also the better-evidenced hypothesis. Girard <em>found</em> a missing group. By contrast, isolated substitution garble in our own corpus amounts to only four controls and eight events — too thin to fit a confusion model on, which is why an earlier and more confident claim about archive garble had to be retracted.
            </p>
            <p>
              And the search is small if you use the historical structure: Kriegsmarine traffic was sent in four-letter groups, so a <em>group</em> going missing puts the splice on a multiple of four — roughly 17 candidate positions per crib placement, not 72.
            </p>
            <p>
              The two compose, since a spliced menu can also be run at tolerance ≥ 1, but neither contains the other. The deletion-tolerant diagonal board is the substitution mechanism; Future geometry is the indel mechanism. Together they make the campaign machine <em>edit-distance aware</em> without pretending the operations are equivalent.
            </p>
            <p>
              <strong>The production path is unified hardware.</strong> One outer TensorLUT lane owns one rotor setting and one shared 80×26 scrambler trail. Parameterized Verilog bank slots own explicit Future geometry and seeds, perform exact-first one-edge repair, and hold complete tagged receipts until accepted. The host compiles evidence into descriptors; it does not run a separate software closure in place of the RTL.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Evidence</div>
            <h2>What is actually proven</h2>
            <p>
              Mechanism claims below begin with known-key grades against P1030684 — published key, same day, same boat — following the standing rule in this project: grade machinery against a key it was not told before pointing it at the unbroken message. The legacy target prefixes remain incomplete; the unified bank now also has one separately bounded target receipt.
            </p>
          </div>
          <div className="prose">
            <p>
              <strong>Sensitivity.</strong> With a 27-letter crib and letters corrupted inside the crib span, the exact board <strong>loses</strong> the true setting at one, two, and three garbles. A board with tolerance ≥ <em>g</em> <strong>keeps</strong> it — and still forces <strong>all 25</strong> plug deductions correctly. That LOST → KEPT transition is the mechanism working.
            </p>
            <p>
              The plug column matters as much as the verdict. The crib-free climber needs only <strong>four</strong> correct plugs to flip its margin positive at 72 letters. Twenty-five is a long way past four, so the two halves compose: a garbled true key survives the board <em>and</em> can be finished off into a full key and plaintext.
            </p>
            <p>
              <strong>Equivalence in silicon.</strong> The Metal port agrees with the host board at <strong>zero lane mismatches out of 192</strong>, at every tolerance, across 45 crib × offset × tolerance combinations. Two separate no-op traps are cleared: the kernel reproduces the LOST → KEPT flip, and per-shell wall time rises from 0.03 s to about 7 s between tolerance 0 and 2, which proves the extra closures are genuinely performed rather than elided. Moving the board into its own file left the output byte-identical.
            </p>
            <p>
              <strong>The pinned-ring flag, graded two-sided.</strong> A flag that <em>narrows</em> the search space can silently exclude the answer, so it earns the same scrutiny: pinning the control's own ring reproduces the full break with all ten plugs, IC 0.064 and tail −2.848, while pinning a wrong ring dies at the board.
            </p>
            <p>
              <strong>Bounded target evidence on the legacy Metal path.</strong> Tolerance 1 × right rings is suspended at <strong>3/24</strong>, all three completed placements dead. Post-gap δ=4 × right rings is suspended at <strong>144/237</strong>; entry 111's eight raw stops produce zero valid ≤10-plug completions. Full middle × right rings is suspended at <strong>1/24</strong>, with the completed placement dead over 4.152×10<sup>11</sup> settings. These are local negatives, not completed arms and not a decrypt.
            </p>
            <p>
              <strong>Four-surface production parity.</strong> At <code>BANK_LANES=1</code>, clean exact hit, exact negative, combined post-gap plus one-edge repair, and transmitted step 79 emit identical full held receipts through source RTL, post-Yosys RTL, clear Yosys-JSON simulation, and cleartext Float TensorLUT, including backpressure. That is a known-key Boolean mechanism grade, <strong>not FHE</strong>.
            </p>
            <p>
              <strong><Fahrenheit261Span /> bank selection.</strong> The deterministic P1030680 inventory stages <strong>261 entries</strong> — 24 identity plus 237 post-gap δ=4. All widths <code>1/2/4/8/16</code> synthesize, but complete-receipt medians of 233.777 / 264.719 / <strong>276.035</strong> / 273.890 / 230.780 receipts per second selected <code>BANK_LANES=4</code>. The winner was measured at runtime, not inferred from graph size.
            </p>
            <p>
              <strong><Fahrenheit261Span /> bounded target execution.</strong> Protocol-v3 run <code>sha256-e6dc10d4…2fc1360</code> covered only shell 0 <code>B/beta/IV-III-VIII/AAAA</code>, identity Future 0, and settings <code>0..&lt;256</code>. It completed <strong>16/16 synchronized chunks and 6,656/6,656 canonical receipt projections, with zero hardware positives and zero BREAK gates</strong>. Exact-prefix resume revalidated all rows and appended nothing; the runner commits every job, derives hit/gate state, host-replays persisted hits, halts on a prior gate, and enforces one writer. Receipt: <code>logs/p1030680-mulein-unified-smoke-v3.jsonl</code>, SHA-256 <code>687d0838…2b1f7e7d</code>. This is a clean local negative. The other 260 Futures, remaining settings, and other shells were not executed, so 261 staged must never be read as 261 covered.
            </p>
            <p>
              <strong><NaziBlaster9000Span /> operational arm.</strong> Its separate 628-Future inventory preflight completed shell 0 and setting 0: 628/628 chunks and 16,328 checked receipts retained 15 host-replayed one-edge physical candidates, all non-exact, with <strong>0 exact hits and 0 BREAK gates</strong>. The settings <code>1..&lt;256</code> production stripe across all 628 Futures is <strong>RUNNING by operator report</strong> in <code>logs/p1030680-mulein-operational-settings-000001-000256-v3.jsonl</code>; outcomes are unknown and no live receipt grade, hit, gate, key, plaintext, or decrypt is claimed.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">The cost</div>
            <h2>And the rule I got wrong</h2>
            <p>
              Tolerance <em>widens</em> what survives. Its price is survivor inflation, and misreading that price is exactly how a tolerant board becomes a ghost factory.
            </p>
          </div>
          <div className="prose">
            <p>
              Measured at crib offset 0, inflation looked like a beautifully clean function of menu size. Sixteen edges admitted 130,787 of 456,976 lanes at tolerance 1. Seventeen through nineteen admitted exactly one. Twenty-two and above admitted one even at tolerance 2. I wrote a rule from it: tolerance 1 needs 17 edges, tolerance 2 needs 22.
            </p>
            <p>
              <strong>It was wrong, and it is withdrawn.</strong> Varying the <em>placement</em> destroys it. At offset 15, sixteen edges costs nothing at all — one survivor. At offsets 40 and 65, eighteen edges admits 4,301 and 16,019 survivors. At offset 40, even twenty-two edges admits 20,823 where offset 0 admitted one.
            </p>
            <p>
              Crib length does not predict inflation. What governs it is the menu's <strong>loop structure</strong>, because tolerance <em>spends</em> redundancy and only a loop-rich menu has enough to spend. Look at which placements detonate and it is obvious in hindsight: the ones where the exact board was <em>already</em> weak. <strong>Tolerance amplifies an under-determined menu rather than rescuing it.</strong>
            </p>
            <p>
              The replacement rule is more useful than the one I lost. Tolerance is a <strong>per-menu decision, pre-qualified by measurement</strong> — never a global switch. On the target's 24 strongest placements that gate passes with <em>zero</em> inflation at tolerance 1. Conflict-directed one-edge repair measures a <strong>6.2×</strong> cost factor rather than the 41× combinatorial ceiling, because the exact pass runs first, candidate deletions are ordered by observed conflict, and most closures die early. Tolerance 2 fails the gate on three of those menus, and the worst offender is the weakest menu in the set. Exactly as the corrected rule predicts.
            </p>
            <p>
              One more trap, caught by the tool's own banner rather than by me: at crib lengths of 26 letters or more, a rings-AAAA pass covers <strong>zero</strong> of the 26 ring phases. A tolerance run there would have been very nearly vacuous on the long menus. Right-ring coverage is the minimum that carries a real negative.
            </p>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Implementation</div>
            <h2>It was a no-op the first time</h2>
            <p>
              Recorded because it is easy to reintroduce, and because it measured as precisely nothing.
            </p>
          </div>
          <div className="prose">
            <p>
              Tolerance must <strong>remove</strong> edges <em>before</em> propagating, never abandon them mid-flight. My first version did the latter and produced one survivor at every tolerance level — a perfect impostor of a working feature. Two causes compounded.
            </p>
            <p>
              First, <strong>the bad value is already committed.</strong> A garbled edge processed early writes a wrong σ(x) into the live rows, which then propagates through other edges <em>and through the diagonal board</em>. Restoring the two rows that just conflicted unwinds none of that.
            </p>
            <p>
              Second, <strong>the conflict surfaces at the wrong edge.</strong> Whichever edge happens to be visited when the inconsistency becomes visible is the one that gets blamed — and that is usually a perfectly <em>correct</em> edge, so dropping it does not help and the real culprit stays in.
            </p>
            <p>
              Enumerating the deleted set instead is order-independent and reuses the already-validated exact closure. Within the legacy host path, both entry points share one implementation of the board logic. The production RTL is intentionally independent and is cross-graded against the Swift oracle through all four surfaces. A second guard exists for a subtler failure: the seed letter must still touch a surviving edge. Without it, a sufficiently reduced board constrains nothing at all, and then <em>every</em> setting "survives" — a silent way to turn a bombe into a random number generator.
            </p>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Honest scope</div>
            <h2>What this is not</h2>
            <p>
              The board is graded, not trusted. Naming it does not promote it.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">NO BREAK</span>
              <span>
                <strong>This is not a decrypt.</strong> P1030680 remains unbroken. The legacy target arms are incomplete: tolerance 1 is 3/24, post-gap δ=4 is 144/237, and full middle × right coverage is 1/24. The unified bank adds one clean local negative—shell 0, identity Future 0, settings <code>0..&lt;256</code>, zero positives—but the other 260 staged Futures and broader shell/setting space remain open. Nothing here proves the target <em>is</em> garbled or missing a group.
              </span>
            </li>
            <li>
              <span className="mono">SCOPE</span>
              <span>
                Tolerance applies to <strong>menu edges, not to the diagonal board itself</strong>. It is an algebraic relaxation of deduction and nominates no letters. Indels remain a distinct exact-board geometry change. The unified hardware can carry both descriptors in one receipt path without collapsing their meanings.
              </span>
            </li>
            <li>
              <span className="mono">DEPENDENCY</span>
              <span>
                A tolerant board with no discriminator is a <strong>ghost factory</strong>. This one is only usable because the crib-free climber provably finishes a true stop at 72 letters given four plugs, and leaves ghosts <em>below</em> the random-setting noise floor. Without that adjudicator, tolerance would be a way to manufacture false positives at scale.
              </span>
            </li>
            <li>
              <span className="mono">CLEARTEXT</span>
              <span>
                The Verilog→Yosys→Float TensorLUT→Metal path on this page is <strong>cleartext hardware evaluation</strong>. Trivial Float TensorLUT is not <HelutSpan />'s encrypted torus path, and its throughput is not an FHE result.
              </span>
            </li>
            <li>
              <span className="mono">NAMING</span>
              <span>
                "Mulein board" is a local name, chosen because the contribution sits in the same structural slot Welchman's diagonal board did — a new board on an existing bombe, not a new bombe. In writing, the substitution mechanism is the <strong>deletion-tolerant diagonal board</strong>; the indel mechanism is explicit Future geometry. Full design notes and receipt paths live in <code>directives/mulein-board.md</code>; the campaign record is <Link to="/projects/p1030680/journal">the ledger</Link>, Phases 51.12–51.14.
              </span>
            </li>
          </ul>
        </div>
      </section>
    </main>
  )
}
