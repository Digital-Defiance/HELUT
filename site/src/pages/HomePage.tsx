import { Link } from 'react-router-dom'

export function HomePage() {
  return (
    <main>
      <section className="hero hero--home">
        <div className="hero-plane" aria-hidden="true" />
        <div className="shell hero-copy">
          <div className="brand-mark">
            HE<em>LUT</em>
          </div>
          <div className="hero-readable">
            <p className="brand-expand">Homomorphic Edge Look-Up Tensors</p>
            <h1>Turning Silicon into Mathematics</h1>
            <p className="lede">
              Take a chip’s wiring, rewrite it as equations, and run those equations at Apple Silicon speed—while the data stays encrypted. That is Homomorphic Edge Look-Up Tensors. To prove the engine can carry real cryptographic weight, I aimed it at an 80-year-old unbroken WWII ghost.
            </p>
            <div className="cta-row">
              <Link className="btn" to="/stack">
                How the engine works
              </Link>
              <Link className="btn ghost" to="/enigma">
                The hunt for U-534
              </Link>
            </div>
          </div>
        </div>
      </section>

      <section className="band">
        <div className="shell origin">
          <div className="section-head">
            <div className="kicker">Origin</div>
            <h2>I built this because I already lived at the edge.</h2>
            <p>
              Homomorphic Edge Look-Up Tensors did not start as a product pitch. I’ve always been fascinated by the seamless interchange between bits and radio waves. With tools like GNURadio, you could manipulate a flowgraph to make the physical air between transmitter and receiver effectively disappear.
            </p>
          </div>
          <div className="prose origin-body">
            <p className="origin-slot" data-slot="sigint">
            In SIGINT, those signals can't wait for a cloud round-trip. More commonly, they are operating on an air-gapped machine or a standalone device in the field—the math has to execute exactly where the data lives.
            </p>
            <p className="origin-slot" data-slot="fpga">
            Software flowgraphs are beautiful, but they hit a wall when you need absolute real-time, deterministic execution. FPGAs became my language of choice because they erased the boundary between code and silicon. Pure software waits its turn for a CPU cycle. An FPGA lets you rewire a physical circuit on the fly to catch a signal the exact microsecond it arrives on the wire.
            </p>
            <p className="origin-slot origin-punch" data-slot="mining">
            The value of edge compute crystallized in a pitch-black mine when all our 'Plan A' gear didn't make it. Sitting in the dark, I reconfigured an FPGA in the literal Field (as in Field Programmable Gate Array), cobbled together a custom flowgraph, and successfully pushed a signal 3,000 meters using the mine’s raw powerline infrastructure as our transmission medium. That is when dynamic, field-programmable hardware stopped being theoretical.
            </p>
            <p>
              That is why I created HELUT: Homomorphic Edge Look-Up Tensors—so the kind of work I used to do in the clear could eventually run on ciphertext, on hardware that already knows how to think in tables and edges. I wanted to bring the power of reconfigurable computing to Apple Silicon.
            </p>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The Trajectory</div>
            <h2>From Mock-PBS to True Homomorphic Encryption</h2>
            <p>
              HELUT was not built to be an Enigma cracking tool. It is a systems prototype designed to evaluate real hardware netlists under homomorphic tensor arithmetic. I am currently using "mock" Programmable Bootstrapping (PBS) to prove that my datapath, batching mechanics, and logic gates can run at CPU-scale without collapsing.
            </p>
            <p style={{ marginTop: '1rem' }}>
              Once the plumbing is perfected, I introduce true cryptographic noise budgets, actual Torus PBS, and key-switching. The Enigma campaign is just my ultimate stress test.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">01</span>
              <span>
                <strong>The Virtual Brain (Encrypted RISC-V)</strong> — I successfully booted a full RISC-V processor under mock encryption to prove my logic gates scale to the size of a real computer.
              </span>
            </li>
            <li>
              <span className="mono">02</span>
              <span>
                <strong>The Parallel Searcher</strong> — A batched pattern matcher across thousands of streams simultaneously, proving my engine can handle overwhelming amounts of data in a single pass.
              </span>
            </li>
            <li>
              <span className="mono">03</span>
              <span>
                <strong>The Blind Decision Tree</strong> — An exact non-linear classification circuit, proving I don't have to take floating-point shortcuts to make complex logical choices.
              </span>
            </li>
            <li>
              <span className="mono">04</span>
              <span>
                <strong>The Welchman Bombe</strong> — The ultimate datapath test: weaponizing the engine to deterministically dismantle an unbroken 1945 message from a German U-boat.
              </span>
            </li>
          </ul>
        </div>
      </section>
    </main>
  )
}
