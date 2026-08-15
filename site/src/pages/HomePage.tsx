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
              Honest limits: calibrated hardness is not lattice-estimator Cost on every row (H1 /
              C23: prod-n1024-s16 HELUT 175.7 vs Sage 180.2). Covering Track A noisy BK at{' '}
              <em>N</em>=1024 is C52–C54 (<em>k</em>=7) and cheaper covering-b2 C57; native <em>k</em>=1 (C37/C55) and{' '}
              <code>cryptoPublicMS</code> (C26/C56) remain graded negatives. Campaign fitness is
              Welchman/cleartext—not FHE tick rate. P1030680 is not decrypted.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">I</span>
              <span>
                <strong>Netlist-clocked torus FHE</strong> — LWE/GLWE + GGSW BK on Metal/CPU;
                encrypted full_adder SING at production <em>N</em> (C20/C21); covering noisy BK at
                the same <em>N</em> with stride-<em>k</em> (C52–C54); Metal PicoRV lut6 1-tick at
                that <em>N</em> with <em>e</em>=0 BK (C62). Covering Q on that core PASSes at{' '}
                <em>N</em>=64 (C63) and still FAILs at production <em>N</em> (C60/C61). Extract→KS
                LWE <em>n</em>=64 native-<em>k</em> covering is C64; PicoRV lut6 covering Q via that
                KS is C65–C66/C68 (C60/C61 stay <em>n</em>=<em>N</em> <em>k</em>=7 FAIL). C69: covering
                KS <em>n</em>=256 PASS, <em>n</em>=512 SING FAIL. Chronology:{' '}
                <Link to="/projects/netlist-fhe/journal">FHE journal</Link>.
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
