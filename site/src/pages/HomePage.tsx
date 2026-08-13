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
            <h1>Netlists that tick on ciphertext</h1>
            <p className="lede">
              HELUT compiles Yosys gate-level netlists into tensor graphs on Apple Silicon. The
              graduated path evaluates real LWE/GLWE samples with GGSW blind-rotate and
              machine-checkable certificates—not a new lattice assumption. A cleartext Metal path
              still runs the Enigma campaign at tens of millions of settings per second. TensorLUT
              melts INIT tables when the genotype itself is the question.
            </p>
            <div className="cta-row">
              <Link className="btn" to="/stack">
                The stack
              </Link>
              <Link className="btn ghost" to="/apps">
                Applications
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
              HELUT did not start as a product pitch. I have always been fascinated by the
              interchange between bits and radio waves. With GNU Radio, you could reshape a
              flowgraph until the air between transmitter and receiver effectively disappeared.
            </p>
          </div>
          <div className="prose origin-body">
            <p className="origin-slot" data-slot="sigint">
              In SIGINT, those signals cannot wait for a cloud round-trip. More often the math has
              to run on an air-gapped machine or a standalone device in the field—exactly where the
              data lives.
            </p>
            <p className="origin-slot" data-slot="fpga">
              Software flowgraphs hit a wall when you need deterministic, real-time execution.
              FPGAs became my language of choice: a blank die that rewires its own logic to become
              the circuit you need on the wire.
            </p>
            <p className="origin-slot origin-punch" data-slot="mining">
              That lesson crystallized in a pitch-black mine when our gear failed. I reconfigured
              an FPGA in the field, cobbled together a flowgraph, and pushed a signal 3,000 meters
              over the mine’s raw powerline infrastructure. Dynamic hardware stopped being
              theoretical.
            </p>
            <p>
              HELUT takes that reconfigurable discipline onto tensor silicon: Verilog in, Yosys
              netlist, Metal (or CPU) evaluation—in the clear for campaign-scale search, or under
              torus FHE samples when the datapath must stay dark.
            </p>
          </div>
        </div>
      </section>

      <section className="band-ink">
        <div className="shell split">
          <div className="section-head" style={{ marginBottom: 0 }}>
            <div className="kicker">Three pillars</div>
            <h2>What ships today</h2>
            <p>
              Mock-PBS torus shapes were the scaffolding. They still exist for CPU-scale cleartext
              netlists (PicoRV32, campaign batch). The encrypted path has graduated: per-
              <code>$lut</code> blind-rotate, public-MS or secret wire refresh, noise / hardness /
              noisy-BK certificates, and <code>--sing</code> equivalence benches against clear
              ticks.
            </p>
            <p style={{ marginTop: '1rem' }}>
              Honest limits: classical hardness is a calibrated estimate until Sage fills the
              lattice-estimator table; large-<em>N</em> Metal encrypted wall-clock is still being
              measured; campaign fitness is Welchman/cleartext—not FHE tick rate.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">I</span>
              <span>
                <strong>Netlist-clocked torus FHE</strong> — LWE/GLWE + GGSW BK on Metal/CPU;
                encrypted full_adder, tree, and regex netlists pass cleartext equivalence under{' '}
                <code>--bench-encrypted --sing</code>.
              </span>
            </li>
            <li>
              <span className="mono">II</span>
              <span>
                <strong>Differentiable hardware</strong> — TensorLUT melts INIT tables, grades
                shatter vs hold under λ, recovers reciprocal stecker involutions on frozen cores.
              </span>
            </li>
            <li>
              <span className="mono">III</span>
              <span>
                <strong>Polymorphic ciphers</strong> — Enigma256 SoftBus co-evolves under Red
                pressure (TensorLUT cones, KPA, <code>ent</code>) and fails closed.
              </span>
            </li>
            <li>
              <span className="mono">LAB</span>
              <span>
                <strong>P1030680 campaign</strong> — Welchman + Stochastic Bombe on cleartext Metal
                batch; still the unbroken M-Thetis ghost from U-534.
              </span>
            </li>
          </ul>
        </div>
      </section>
    </main>
  )
}
