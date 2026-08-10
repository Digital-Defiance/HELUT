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
            <h1>The Universal Imitation Game</h1>
            <p className="lede">
              In 1950, Alan Turing formalized the "Imitation Game" based on a profound mathematical truth: a discrete-state digital computer can perfectly imitate the behavior of any other machine. Homomorphic Edge Look-Up Tensors takes that theorem to its absolute limit. I take raw hardware circuits, translate them into pure tensor mathematics, and force modern silicon to perfectly imitate their physical execution—while the data stays entirely encrypted.
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
            Software flowgraphs are beautiful, but they hit a wall when you need absolute real-time, deterministic execution. FPGAs became my language of choice because they are the physical embodiment of universal computation. Pure software waits its turn for a CPU cycle. An FPGA is a blank die playing a hardware imitation game—rewiring its own logic gates on the fly to become the exact circuit you need to catch a signal on the wire.
            </p>
            <p className="origin-slot origin-punch" data-slot="mining">
            The value of edge compute crystallized in a pitch-black mine when all our gear failed. Sitting in the dark, I reconfigured an FPGA in the literal Field, cobbled together a custom flowgraph, and successfully pushed a signal 3,000 meters using the mine’s raw powerline infrastructure as our transmission medium. That is when dynamic, field-programmable hardware stopped being theoretical.
            </p>
            <p>
              That is why I created HELUT. I wanted to take the raw, reconfigurable power of an FPGA and emulate it in software on modern tensor silicon, allowing the kind of work I used to do in the clear to run seamlessly on ciphertext. 
            </p>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">The Trajectory</div>
            <h2>Imitating Logic in the Dark</h2>
            <p>
              HELUT is a systems prototype designed to evaluate real hardware netlists blindly, under homomorphic tensor arithmetic. It is the deepest layer of the Imitation Game: it forces the processor to emulate physical logic on data it cannot see, calculating absolute truth while remaining completely in the dark.
            </p>
            <p style={{ marginTop: '1rem' }}>
              The secret to its execution speed lies in the "LUT" (Look-Up Table). FPGAs don't compute complex equations; they map inputs to outputs using physical LUTs. An Enigma rotor operates the exact same way—it is not an algebraic function, but a scrambled ball of wires acting as a hardwired 26-element look-up table. 
            </p>
            <p style={{ marginTop: '1rem' }}>
              Here is where the architecture becomes a masterpiece. You cannot efficiently evaluate physical circuits on a GPU by writing software that simulates sequential spinning gears. Graphics cards actively choke on branching <code>if/then</code> loops. They are built for one thing: evaluating massive matrices in parallel.
            </p>
            <p style={{ marginTop: '1rem' }}>
              Instead, HELUT hooks directly into Yosys, the industry-standard open-source synthesis suite. You write standard Verilog. Yosys synthesizes it into a flattened hardware netlist. HELUT ingests that netlist, transforms every Look-Up Table into a multidimensional tensor array, and maps the hardware’s boolean constraints directly into Apple’s Metal shaders as branchless, pure matrix mathematics. When the engine tests a cryptographic key, it doesn't step through a program; it executes millions of parallel tensor operations where an impossible physical state instantly and mathematically collapses to zero.
            </p>
            <p style={{ marginTop: '1rem' }}>
              I am using this "mock" PBS and pure LUT execution to prove that the datapath, batching mechanics, and logic gates can scale to universal computation without collapsing. Once the plumbing is perfected, I introduce true cryptographic noise budgets and actual Torus PBS.
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
                <strong>The Blind Decision Tree</strong> — An exact non-linear classification circuit, proving I don't have to take floating-point shortcuts to make complex logical choices on encrypted states.
              </span>
            </li>
            <li>
              <span className="mono">04</span>
              <span>
                <strong>The Welchman Bombe</strong> — The ultimate datapath stress test: translating the 1945 electromechanical Bombe into pure tensor mathematics to deterministically dismantle an unbroken Kriegsmarine ghost.
              </span>
            </li>
          </ul>
        </div>
      </section>
    </main>
  )
}