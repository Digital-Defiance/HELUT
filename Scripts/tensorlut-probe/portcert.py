#!/usr/bin/env python3
"""Port-weighted noise certificate for public-MS LUT packing (HELUT Path B).

Usage: portcert.py SIGMA NETLIST.json:K [NETLIST.json:K ...]
  SIGMA  per-BR output noise std on the 2^32 torus (e.g. the gate's sigma95)
  K      public-MS stride (--boolean-scale-mul); centers k*addr must satisfy k*(2^w-1) < N

Why: the current gate bounds P(|e| > k*delta/2), the logical decode margin. But a consumer
LUT packs *refreshed* natives with weights 2^i, so a native jitter eps on a weight-w port
moves the packed address by w*eps. With k=7, any |eps|=1 on a weight>=4 port lands in the
wrong Voronoi band. That is the C71 trace: producer y=653 refreshed to native 1, consumer
y=654 saw it on its weight-32 port, offset 32, address 24 instead of 19.

A consumer LUT packs refreshed inputs as sum_i 2^i * n_i with n_i = k*b_i + eps_i, eps_i = round(e_i/delta),
and decodes the nearest center k*addr. It is wrong when |sum_i 2^i eps_i| >= k/2.
Joint-safe per-wire budget: every noisy input must satisfy |eps| <= m with m*sum(noisy port weights) < k/2,
i.e. per-wire threshold (m + 1/2)*delta. Union over every noisy LUT input port."""
import json, sys, math
def log2_tail(z):  # two-sided Gaussian tail, log2
    if z < 8: return math.log2(max(math.erfc(z / math.sqrt(2)), 1e-300))
    return math.log2(2) + (-z*z/2 - math.log(z) - 0.5*math.log(2*math.pi)) / math.log(2)
def cert(path, sigma, k, delta=2**21):
    m = json.load(open(path))['modules']; mod = next(v for v in m.values() if any(c['type']=='$lut' for c in v['cells'].values()))
    luts = [c for c in mod['cells'].values() if c['type'] == '$lut']
    noisy = set(c['connections']['Y'][0] for c in luts) | set(b for c in mod['cells'].values() if 'DFF' in c['type'] for b in c['connections']['Q'])
    total = -1e9; ports = 0; worst = None
    for c in luts:
        A = c['connections']['A']
        wsum = sum(1 << i for i, b in enumerate(A) if isinstance(b, int) and b in noisy)
        n = sum(1 for b in A if isinstance(b, int) and b in noisy)
        if n == 0: continue
        mbud = math.floor((k/2 - 1e-9) / wsum)   # |eps| <= mbud on every noisy port keeps the sum inside k/2
        thr = (mbud + 0.5) * delta
        ports += n
        lt = log2_tail(thr / sigma) + math.log2(n)
        hi, lo = max(total, lt), min(total, lt)
        total = hi + math.log2(1 + 2**(lo - hi)) if total > -1e8 else lt
    return len(luts), ports, total
if __name__ == '__main__':
    sigma = float(sys.argv[1])
    for spec in sys.argv[2:]:
        path, k = spec.rsplit(':', 1)
        n, p, lg = cert(path, sigma, int(k))
        print(f"{path.split('/')[-1]:32s} k={int(k):4d}  LUTs={n:5d}  noisy ports={p:6d}  union log2 eps = {lg:8.1f}  {'clears -64' if lg <= -64 else 'does NOT clear'}")
