import { Link } from 'react-router-dom'
import { ProjectJournalShell } from './ProjectJournalShell'
import { NaziBlaster9000Span } from '../NaziBlaster9000Span'

export function NetlistFheJournalPage() {
  return (
    <ProjectJournalShell
      kicker="Pillar I · Field journal"
      title="What the encrypted netlist has graded"
      lede="This is the chronology for netlist-clocked torus FHE — SING receipts, noisy-BK certificates, and honest remainders. It is not the U-534 hunt. P1030680 is still unbroken; that ledger lives on Nazi Blaster 9000."
      hubPath="/projects/netlist-fhe"
    >
      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Proven</div>
            <h2>Closed bars (claim-sheet IDs)</h2>
            <p>
              Numbers follow <code>directives/claim-sheet.md</code>. Trivial Metal is not FHE.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">C20/C21</span>
              <span>
                Encrypted <code>full_adder</code> Metal SING at production-shaped <em>N</em>=1024:
                boolean wavefront and crypto ℓ=2. Equivalence to clear is C6.
              </span>
            </li>
            <li>
              <span className="mono">C23</span>
              <span>
                Sage fill-in on the hardness table. Quote HELUT vs Sage on the named row (175.7 vs
                180.2 on prod-n1024-s16). Do not quote “176-bit secure” (H1).
              </span>
            </li>
            <li>
              <span className="mono">C52–C54</span>
              <span>
                Covering Track A at <em>N</em>=1024, σ=128, stride-<em>k</em>=7: adder ε + SING
                (C52), counter (C53), toy ISA (C54). Public-MS is native-δ refresh on {'{0,k}'}{' '}
                wires, not the historical /kδ path (C43).
              </span>
            </li>
            <li>
              <span className="mono">C57</span>
              <span>
                Covering-b2 (<em>ℓ</em>=16) σ=128 at <em>N</em>=1024: Metal public-ms adder
                10.33 s/1 and regex 23 LUT 26.69 s/1 PASS at <em>k</em>=7. The
                εlog2≈−110.7 recorded here was a 4-trial low-σ̂ draw — settled it is
                −60.5 at <em>k</em>=7, short of −64. Stride <em>k</em>=14 clears it
                (−319.3, 95% bound −200.5) with SING still PASS. Corrected 2026-08-16. Covering-b4
                public-ms and the historical C39 E256 58-LUT cone covering-b2 SING FAIL
                (not the live fixture-v4 conjugated-XOR center).
              </span>
            </li>
            <li>
              <span className="mono">C58</span>
              <span>
                PicoRV32 <code>abc -lut 6</code>: 2006 LUTs (−58% vs 4785). Encrypted CPU
                public-ms boolean SING PASS at <em>N</em>=64 (1.35 s pre-wavefront).
              </span>
            </li>
            <li>
              <span className="mono">C59</span>
              <span>
                Sequential combinational wavefront: PicoRV lut6 <em>N</em>=64 CPU boolean 0.165 s
                (~8.2× vs C58).
              </span>
            </li>
            <li>
              <span className="mono">C62</span>
              <span>
                Metal PicoRV lut6 at production <em>N</em>=1024, noiseless BK: Q SING PASS in
                373.89 s (C62). Covering noisy BK PASSes Q at <em>N</em>=64 (C63) and still FAILs at
                production <em>N</em> (C60/C61).
              </span>
            </li>
            <li>
              <span className="mono">C63</span>
              <span>
                PicoRV lut6 covering-b2 σ=128 at <em>N</em>=64: Q SING PASS in 1.72 s. Native{' '}
                <em>k</em>. Stride-<em>k</em>=7 at this <em>N</em> SIGTRAPs.
              </span>
            </li>
            <li>
              <span className="mono">C64</span>
              <span>
                Extract→KS (<em>n</em>=64≪kN): native-<em>k</em> covering-b2 adder 4.22 s and counter
                6.35 s at poly <em>N</em>=1024. Not LWE-176. C37 still at <em>n</em>=<em>N</em>.
              </span>
            </li>
            <li>
              <span className="mono">C65</span>
              <span>
                PicoRV lut6 covering Metal at poly <em>N</em>=1024, extract→KS <em>n</em>=64: Q SING
                PASS covering-b2 114 s, covering-b1 212 s. C60/C61 remain <em>n</em>=<em>N</em>{' '}
                <em>k</em>=7 FAIL.
              </span>
            </li>
            <li>
              <span className="mono">C66</span>
              <span>
                Same KS covering-b2, 10-tick resetn boot: Metal Q SING PASS in 1136 s (114 s/row).
                Idle mem. Not NOP-fetch.
              </span>
            </li>
            <li>
              <span className="mono">C67</span>
              <span>
                Covering KS adder ladder: <em>n</em>=128 PASS 8.6 s; <em>n</em>=256 and 512 SIGTRAP
                after extract→KS. Both were later explained: C69 traced <em>n</em>=256 to four
                identity BRs (PASS once fixed), and the <em>n</em>=512 trap to nondeterministic
                input encryption, fixed 2026-08-15 (now PASS).
              </span>
            </li>
            <li>
              <span className="mono">C68</span>
              <span>
                PicoRV lut6 covering NOP-fetch, 8 ticks, extract→KS <em>n</em>=64: Metal PASS 911 s,
                fetches 0x0 then 0x4. Not 10-fetch. Not Linux.
              </span>
            </li>
            <li>
              <span className="mono">C69</span>
              <span>
                Covering KS adder PASS at <em>n</em>=256 (17 s) and <em>n</em>=512. C67 SIGTRAP was four
                identity BRs, not key-switch. The <em>n</em>=512 sum mismatch recorded here
                until 2026-08-15 is <strong>withdrawn</strong>: it was nondeterministic input
                encryption (Dictionary-order RNG), not a noise limit.
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell">
          <div className="section-head">
            <div className="kicker">Remainders</div>
            <h2>Open science — not site bugs</h2>
            <p>
              If a public page does not claim these as done, that is correct. Do not “fix” the
              gallery by inventing production SING.
            </p>
          </div>
          <ul className="stack-list">
            <li>
              <span className="mono">I.2</span>
              <span>
                Encrypted tree SING exists at <strong>demo N</strong> (C6). Regex covering at
                production <em>N</em> is C57. Tree Metal covering is still a remainder.
              </span>
            </li>
            <li>
              <span className="mono">C37</span>
              <span>
                Native <em>k</em>=1 torus-scale at <em>N</em>=1024 covering-b1 σ=128 is still
                undecodable at <em>n</em>=1024 (C37, 8 trials). Cutting LWE <em>n</em> (C55) makes
                identity decodable but ε stays above −64.
              </span>
            </li>
            <li>
              <span className="mono">C26</span>
              <span>
                <code>cryptoPublicMS</code> inject at production <em>N</em> is still a graded
                failure (C26). Stride-<em>k</em>=7 makes tiny <em>B</em>=1 identity-decodable but
                Metal SING fails (C56).
              </span>
            </li>
            <li>
              <span className="mono">PicoRV</span>
              <span>
                Encrypted PicoRV32 covering at <em>n</em>=<em>N</em> <em>k</em>=7 is C60/C61 Q SING
                FAIL. Extract→KS <em>n</em>=64 is C65–C66 and C68 (NOP 2 fetches). Covering Q PASSes at
                poly <em>N</em>=64 (C63). Noiseless Metal PicoRV at production <em>N</em> is C62
                (374 s).
              </span>
            </li>
          </ul>
        </div>
      </section>

      <section className="band">
        <div className="shell prose">
          <p>
            Reproduce: <code>REPRODUCE.md</code> · gallery:{' '}
            <Link to="/apps">Applications</Link> · campaign (still open):{' '}
            <Link to="/projects/p1030680/journal"><NaziBlaster9000Span /></Link>.
          </p>
        </div>
      </section>
    </ProjectJournalShell>
  )
}
