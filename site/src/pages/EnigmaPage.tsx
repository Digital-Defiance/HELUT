import { Link } from 'react-router-dom'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'

export function EnigmaPage() {
  return (
    <main>
      <section className="page-intro">
        <div className="page-plane" aria-hidden="true" />
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Enigma · U534 · M-Thetis</div>
            <h2>The Hunt for an 80-Year-Old Ghost</h2>
            <p>
              On May 1, 1945, a German U-boat transmitted a short, 72-letter message using a highly complex Enigma M4 machine. The codebook to decipher it was printed on water-soluble paper and destroyed. For eighty years, the message has remained unbroken. This is the story of how I weaponized modern Apple Silicon to hunt it down.
            </p>
          </div>

          <div className="status-strip">
            <div className="stat">
              <div className="label">Status</div>
              <div className="value">
                Historically <em>unbroken</em>
              </div>
            </div>
            <div className="stat">
              <div className="label">My Weapon</div>
              <div className="value">Absolute logic & physical limitations</div>
            </div>
            <div className="stat">
              <div className="label">Current Focus</div>
              <div className="value">Hunting the final rotor turnovers</div>
            </div>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The Method</div>
            <h2>Why guessing doesn't work.</h2>
            <p>
              Modern codebreakers usually rely on statistics—guessing letters and scoring how closely they resemble a real language. But on a message this short, statistics will hallucinate false answers and lead you to dead ends. So I stopped guessing. I built a digital version of Gordon Welchman’s famous WWII "Bombe" machine. It doesn't look for what is likely; it ruthlessly eliminates what is physically impossible.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">01</span>
              <span>I only test suspected historical phrases that are long enough to lock the machine into a single, undeniable answer.</span>
            </li>
            <li>
              <span className="mono">02</span>
              <span>
                My engine uses pure logic to filter out billions of mathematically impossible rotor settings at a blistering 40 million checks per second.
              </span>
            </li>
            <li>
              <span className="mono">03</span>
              <span>
                <strong>The physical catch:</strong> The 1945 operator only had 10 physical cables to plug in. If my math suggests a setting that requires 11 cables, the engine kills it instantly.
              </span>
            </li>
            <li>
              <span className="mono">04</span>
              <span>
                Only the survivors of this brutal logical gauntlet are checked to see if they produce authentic German syntax.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker"><NaziBlaster9000Span /></div>
            <h2>Closing the net, step by step.</h2>
            <p>
              In cryptography, proving where the answer *isn't* is just as important as finding where it is. This is a brief look at the ghosts I have already chased away on my path to the true answer.
            </p>
          </div>

          <div className="timeline">
            <article className="tl-item">
              <div className="when">Step 1: History</div>
              <h3>No lucky breaks.</h3>
              <p>
                I combed through the archives of other messages intercepted that day, hoping the operator had accidentally re-sent a broken code, or that I could piggyback on a known daily key. No luck. The message stood completely alone. I was going to have to do this the hard way.
              </p>
            </article>
            <article className="tl-item">
              <div className="when">Step 2: Optimization</div>
              <h3>Working smarter, not harder.</h3>
              <p>
                Instead of blindly checking every possible combination, I analyzed how the physical machine actually moved. By pinning down the rotors that were mechanically locked in place, I reduced the search space by a massive factor of 676—tuning my software to match the physical reality of the 1945 hardware.
              </p>
            </article>
            <article className="tl-item">
              <div className="when">Step 3: The 10-Plug Trap</div>
              <h3>Reality beats mathematics.</h3>
              <p>
                I thought I had a hit on a common naval phrase starting at the very beginning of the message. The math checked out perfectly, giving me 12 possible answers. But when my engine tried to "plug in" the cables to make it work, every single one required more cables than the machine possessed. I proved the phrase wasn't there by using the laws of physics.
              </p>
            </article>
            <article className="tl-item">
              <div className="when">Step 4: The Final Hunt</div>
              <h3>A massive sweep.</h3>
              <p>
                I recently had a false alarm where a shorter phrase tricked the statistics into thinking it had found German. I tightened my defenses and just finished sweeping a massive portion of the search space with no true break. The net is tightening, and I am currently running a highly targeted hunt on the remaining high-probability locations.
              </p>
            </article>
          </div>

          <div className="note" style={{ marginTop: '2rem' }}>
            I know the engine is flawless. I tested it against a message that was already solved, and out of billions of possibilities, it isolated the one true answer and perfectly rebuilt the operator's physical plugboard. The machine is ready. Now, it's just a matter of time.
          </div>

          <p style={{ marginTop: '1.75rem', color: 'var(--ink-soft)' }}>
            For those who want to dive into the raw engineering logs and code, my public ledger is available here:{' '}
            <a href="https://github.com/Digital-Defiance/HELUT/blob/main/BREAK_P1030680.md">
              The P1030680 Campaign Journal
            </a>
            . The Blue Team rewrite of every flaw this hunt exposed is{' '}
            <Link to="/projects/e256">E256</Link>.
          </p>
        </div>
      </section>
    </main>
  )
}
