import type { Project } from './types'

/**
 * Canonical project registry for the site.
 * Each project owns a hub, optional journal, and related essays/labs.
 * Add a new entry here first — then wire any custom page component in App.tsx.
 */
export const projects: Project[] = [
  {
    slug: 'p1030680',
    title: 'Nazi Blaster 9000 · P1030680',
    subtitle: 'Unified Mulein campaign against the unbroken M-Thetis ciphertext',
    pillar: 'campaign',
    phase: 'campaign',
    status: 'active',
    kicker: 'Campaign journal',
    summary:
      'Nazi Blaster 9000 unifies the Mulein Future Bank, Welchman diagonal board, Stochastic Bombe, and quarantine escalation against one still-unbroken 72-letter Kriegsmarine ciphertext; Fahrenheit 261 names the historical 261-entry canonical campaign.',
    stakes: [
      'Boolean coverage under right rings (catalog live / resume tracked in the journal)',
      'Nazi Blaster 9000 settings 1..<256 stripe is operator-reported RUNNING; outcomes unknown',
      'Exact clean negatives do not rule out a mis-transcribed ciphertext',
      'Middle ring ≠ A is partial/suspended at 1/24 against P1030680',
    ],
    pages: [
      {
        path: '/projects/p1030680',
        label: 'Project hub',
        kind: 'hub',
        blurb: 'Status, scope, and entry points',
      },
      {
        path: '/projects/p1030680/journal',
        label: 'Campaign journal',
        kind: 'journal',
        blurb: 'Chronology of wedges, ghosts, and graded controls',
      },
      {
        path: '/enigma',
        label: 'The hunt for U-534',
        kind: 'essay',
        blurb: 'Narrative of the archival pivot and Boolean engine',
      },
      {
        path: '/projects/e256',
        label: 'Enigma256 (sibling)',
        kind: 'lab',
        blurb: 'Blue-team rewrite born from this campaign’s leaks',
      },
    ],
    relatedDocs: ['BREAK_P1030680.md', 'stochastic-bombe.md', 'discriminator.md'],
  },
  {
    slug: 'e256',
    title: 'Enigma256 · E256',
    subtitle: 'Base-256 polymorphic stream cipher — SoftBus on Apple Silicon',
    pillar: 'schneier',
    phase: 'III',
    status: 'active',
    kicker: 'Blue Team · E256/v2/gen0 · fixture-v4',
    summary:
      'The experimental fixture-v4 profile uses the conjugated-XOR center A_i^-1(A_i(x) XOR k_i). The host derives and transports payload, centerMask, and absoluteByteCounter; RTL validates the counter and has no HMAC. A day key supplies a plugboard plus 16 forward/reverse rotor pools, with no reflector. The active slot has 9 unique tables, a 2,304-byte burst, and 10 accesses because the plugboard is used twice. This is bounded functional evidence, not a production-security claim.',
    stakes: [
      'Live tuple: E256/v2/gen0/fa246e9cba9009a4799e5a81722a9b14e9a67293d9621b45985c5f3e620865d4/fixture-v4',
      'KAT: 1,024 bytes / 9 tables / 10 traces / 25 artifacts; equality 260/65536 (z=0.250); formal 1/1; suite 49/49; receipt logs/e256-v2-gen0-fixture-v4-validation.json',
      'TensorLUT: 366-LUT6 scramble cone with independent center_mask; blue_hold (final_crypto -291592.781250, final_nonbinary 1217) is bounded optimizer failure only—not HMAC or the full core',
      'Experimental and not for real data; E256-003 OPEN pending human acceptance. No IND-CPA, HMAC-security, external-cryptanalysis, security-level, or work-factor claim',
      'Historical gen5 and C39 cones remain quarantined evidence, not the live fixture-v4 datapath',
    ],
    pages: [
      {
        path: '/projects/e256',
        label: 'Project hub',
        kind: 'hub',
        blurb: 'Status and entry points',
      },
      {
        path: '/projects/e256/design',
        label: 'Architecture & field',
        kind: 'lab',
        blurb: 'Planes, host schedule, fixture receipt, Red/Blue pressure',
      },
      {
        path: '/projects/e256/journal',
        label: 'Field journal',
        kind: 'journal',
        blurb: 'Generation grades and reciprocity controls',
      },
      {
        path: '/projects/polymorphic-ciphers',
        label: 'Polymorphic Ciphers pillar',
        kind: 'docs',
        blurb: 'The standard this lab feeds',
      },
      {
        path: '/projects/p1030680/journal',
        label: 'Nazi Blaster 9000',
        kind: 'journal',
        blurb: 'The Red ledger that specified what E256 must never do',
      },
    ],
    relatedDocs: ['Enigma256.md', 'Fixtures/enigma256_generation.json'],
  },
  {
    slug: 'netlist-fhe',
    title: 'Netlist-Clocked Torus FHE',
    subtitle: 'Pillar I — Yosys $lut ticks under LWE/GLWE + GGSW',
    pillar: 'turing',
    phase: 'I',
    status: 'active',
    kicker: 'Graduated FHE',
    summary:
      'Covering Track A noisy BK at N=1024 k=7 is C52–C54; covering-b2 cheaper SING + regex is C57. C62 is noiseless PicoRV at that N; C65/C66/C68 are covering PicoRV via extract→KS n=64 (1-tick, boot, NOP-fetch). C69: KS n=256 and n=512 covering SING PASS; the old n=512 FAIL is withdrawn as a determinism artifact (C67 SIGTRAP at n=256 was identity×4). C60/C61 still FAIL at n=N k=7. Sage filled C23; H1 still applies.',
    stakes: [
      'Encrypted ≡ clear on full_adder (C20/C21) and covering noisy sequential ticks (C53/C54)',
      'Calibrated bits ≠ estimator Cost on every row (H1 / C23: 175.7 vs 180.2 on prod-n1024-s16)',
      'Metal persist ~0.52 s/BR at N=1024 (C17); wavefront boolean SING 10.6 s/8 (C20)',
      'Covering public-MS at N=1024 uses stride-k wires, not “g₀=δ exact covering” (C27 still {8,128}); C65/C66/C68 PicoRV covering via extract→KS n=64; C69 n=256 and n=512 PASS, with the old n=512 FAIL withdrawn as a determinism artifact; C60/C61 still FAIL at n=N k=7',
    ],
    pages: [
      {
        path: '/projects/netlist-fhe',
        label: 'Project hub',
        kind: 'hub',
        blurb: 'Status and non-claims',
      },
      {
        path: '/projects/netlist-fhe/journal',
        label: 'FHE journal',
        kind: 'journal',
        blurb: 'SING receipts, covering Track A, honest remainders',
      },
      {
        path: '/stack',
        label: 'The stack',
        kind: 'docs',
        blurb: 'Path B — graduated FHE',
      },
      {
        path: '/apps',
        label: 'Applications',
        kind: 'lab',
        blurb: 'Encrypted SING nets + cleartext scale',
      },
    ],
    relatedDocs: [
      'directives/fhe-graduation.md',
      'directives/parameter-cookbook.md',
      'directives/research-release.md',
      'paper/helut.tex',
    ],
  },
  {
    slug: 'differentiable-hardware',
    title: 'Differentiable Hardware Cryptanalysis',
    subtitle: 'The Turing Pillar — continuous→discrete logic synthesis',
    pillar: 'turing',
    phase: 'III',
    status: 'research',
    kicker: 'Formalize the paradigm',
    summary:
      'Publish the mathematical loop that melts LUT INIT tables into continuous tensors, squeezes them under crypto fitness, and emits reciprocal silicon. TensorLUT on Enigma M4 is the existence proof; the pillar is the general method.',
    stakes: [
      'Baseline stream fitness F_crypto = 0 on unmutated M4',
      'Full INIT melt and stecker-cone melt shatter under λ — involution sandwich is the live arm',
      'Same engine aimed at stream ciphers, FHE gates, and proving circuits',
      'Parked: bgpucap-style GPU power analysis on live TensorLUT/HELUT Metal cores (see roadmap-overall.md)',
    ],
    pages: [
      {
        path: '/projects/differentiable-hardware',
        label: 'Project hub',
        kind: 'hub',
      },
      {
        path: '/projects/differentiable-hardware/journal',
        label: 'Research journal',
        kind: 'journal',
        blurb: 'Grades, shatter modes, and involution controls',
      },
      {
        path: '/projects/differentiable-hardware/paradigm',
        label: 'The paradigm',
        kind: 'essay',
        blurb: 'Continuous-to-discrete synthesis as cryptanalytic method',
      },
      {
        path: '/stack',
        label: 'The stack',
        kind: 'docs',
        blurb: 'Yosys → tensor → Metal / TensorLUT pipeline',
      },
    ],
    relatedDocs: ['adversarial-synthesis.md', 'tensorlut.md', 'roadmap-overall.md'],
  },
  {
    slug: 'polymorphic-ciphers',
    title: 'Polymorphic Ciphers',
    subtitle: 'The Schneier Pillar — fail-closed Red/Blue evolution',
    pillar: 'schneier',
    phase: 'III',
    status: 'research',
    kicker: 'Standardize the loop',
    summary:
      'Open the architectural philosophy of ciphers that mutate under adversarial pressure: a Red team melts structure; a Blue team hardens non-linear feedback until the attack fails closed. The Enigma256 project is the working laboratory for that standard.',
    stakes: [
      'Red: differentiable melt and combinatorial sieves as attack surfaces',
      'Blue: involution constraints, fail-closed mutation of NLFSRs / S-boxes',
      'Public framework, not a single cipher product',
    ],
    pages: [
      {
        path: '/projects/polymorphic-ciphers',
        label: 'Project hub',
        kind: 'hub',
      },
      {
        path: '/projects/polymorphic-ciphers/journal',
        label: 'Research journal',
        kind: 'journal',
        blurb: 'Red/Blue campaign notes as the loop hardens',
      },
      {
        path: '/projects/polymorphic-ciphers/red-blue',
        label: 'Red / Blue loop',
        kind: 'essay',
        blurb: 'How adversarial evolution becomes a design baseline',
      },
      {
        path: '/projects/e256',
        label: 'Enigma256',
        kind: 'lab',
        blurb: 'Experimental fixture-v4 E256 profile · E256-003 OPEN pending human acceptance',
      },
    ],
    relatedDocs: ['Enigma256.md'],
  },
  {
    slug: 'fhe-gates',
    title: 'FHE Gate Optimization',
    subtitle: 'Shallower homomorphic netlists for edge Metal',
    pillar: 'turing',
    phase: 'II',
    status: 'queued',
    kicker: 'Phase II',
    summary:
      'Separate from Pillar I graduation: use TensorLUT to mutate and squeeze FHE-shaped logic toward shallower Metal-native topologies. The encrypted runtime already ticks small netlists; this project is about depth/LUT count under continuous search.',
    stakes: [
      'Target: multiplicative depth and LUT count on TFHE-shaped gates',
      'Depends on TensorLUT squeeze reliability beyond Enigma stecker',
      'Does not replace lattice-estimator or noisy-BK production work on netlist-fhe',
    ],
    pages: [
      {
        path: '/projects/fhe-gates',
        label: 'Project hub',
        kind: 'hub',
      },
    ],
  },
  {
    slug: 'zk-circuits',
    title: 'Zero-Knowledge Circuit Minimization',
    subtitle: 'Evolve proving circuits with lower multiplicative depth',
    pillar: 'turing',
    phase: 'II',
    status: 'queued',
    kicker: 'Phase II',
    summary:
      'Attack the arithmetic circuits behind zk-SNARKs and kin. Search mathematically equivalent topologies with fewer gates and shallower multiplication — the primary friction in decentralized privacy infrastructure.',
    stakes: [
      'Equivalence-preserving rewrites under continuous squeeze',
      'Benchmarks against known proving-system bottlenecks',
    ],
    pages: [
      {
        path: '/projects/zk-circuits',
        label: 'Project hub',
        kind: 'hub',
      },
    ],
  },
  {
    slug: 'stream-melt',
    title: 'Melting Legacy Stream Ciphers',
    subtitle: 'A5/1, RC4, and late-20th-century telecom crypto',
    pillar: 'turing',
    phase: 'II',
    status: 'queued',
    kicker: 'Phase II',
    summary:
      'Compile legacy stream ciphers into Yosys netlists and melt internal state logic under differentiable fitness — the same paradigm that dismantles 1940s machines, aimed at 1990s silicon.',
    stakes: [
      'Netlist ingest for A5/1 / RC4-class designs',
      'Keystream fitness as the continuous objective',
    ],
    pages: [
      {
        path: '/projects/stream-melt',
        label: 'Project hub',
        kind: 'hub',
      },
    ],
  },
  {
    slug: 'grand-challenge',
    title: 'ZKP & PQC Bottleneck',
    subtitle: 'The Grand Challenge — lattice and proving-scale melts',
    pillar: 'grand-challenge',
    phase: 'III',
    status: 'queued',
    kicker: 'Phase III',
    summary:
      'Focus the engine on post-quantum lattice algorithms and massive proving circuits. Dynamically melt those structures into ultra-low-gate-count topologies — the scaling problem that decides whether privacy infrastructure stays theoretical.',
    stakes: [
      'Requires Turing Pillar formalization and Phase II gate/circuit wins',
      'Success metric: gate count and depth under cryptographic equivalence',
    ],
    pages: [
      {
        path: '/projects/grand-challenge',
        label: 'Project hub',
        kind: 'hub',
      },
    ],
  },
]

export function getProject(slug: string): Project | undefined {
  return projects.find((p) => p.slug === slug)
}

export function projectsByStatus(status: Project['status']): Project[] {
  return projects.filter((p) => p.status === status)
}
