#!/usr/bin/env python3
"""Register-matched scorer vs dense scorer on known-key U-534 controls (run from HELUT repo root).

  python3 register_margin.py xent                  # cross-entropy table (b/letter, first 72 letters)
  python3 register_margin.py bin MODEL N out.bin   # MODEL in {dense, lco, xnet}; N decoy settings per control
  ./anneal R STEPS MAXDECOYS out.bin               # true board vs annealed decoys + cold-start recovery

lco  = leave-cluster-out: train on other U-534 decrypts sharing no 16-letter window with the test message
xnet = train only on decrypts from OTHER nets (register-transfer test); both mixed 0.3 dense + 0.7 corpus
"""
import json, math, random, collections, statistics as st, struct, sys, importlib.util
A = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
spec = importlib.util.spec_from_file_location('ic', 'Scripts/indicator_constraints.py')
ic = importlib.util.module_from_spec(spec); spec.loader.exec_module(ic)

def load_dense(path='Fixtures/german_trigrams.txt'):
    t = collections.Counter()
    for line in open(path):
        if line.strip() and not line.startswith('#'):
            g, c = line.split(); t[g] = int(c)
    return t

def counts(texts):
    t = collections.Counter()
    for s in texts:
        for i in range(len(s) - 2): t[s[i:i+3]] += 1
    return t

def model(tri, l=(0.6, 0.3, 0.1)):
    bi, uni, c2, c1 = (collections.Counter() for _ in range(4))
    for g, c in tri.items(): bi[g[1:]] += c; uni[g[2]] += c; c2[g[:2]] += c
    for g, c in bi.items(): c1[g[0]] += c
    N = sum(uni.values())
    def p(a, b, c):
        p3 = tri[a+b+c] / c2[a+b] if c2[a+b] else 0
        p2 = bi[b+c] / c1[b] if c1[b] else 0
        return l[0]*p3 + l[1]*p2 + l[2]*(uni[c] + 1) / (N + 26)
    return p

def H(p, s, n=72):
    s = s[:n]; return -sum(math.log2(p(s[i-2], s[i-1], s[i])) for i in range(2, len(s))) / (len(s) - 2)

corpus = json.load(open('Fixtures/u534_corpus.json'))['messages']
msgs, seen = [], set()
for r in corpus:
    if r.get('broken') and r.get('plaintext') and r['plaintext'] not in seen:
        seen.add(r['plaintext']); msgs.append(r)
win = lambda s, k=16: {s[i:i+k] for i in range(len(s) - k + 1)}
dense = model(load_dense())

def train_for(r, kind):
    if kind == 'lco':  return [m['plaintext'] for m in msgs if not (win(m['plaintext']) & win(r['plaintext']))]
    if kind == 'xnet': return [m['plaintext'] for m in msgs if m['wheels'] != r['wheels']]
    return []

def scorer(r, kind):
    if kind == 'dense': return dense
    pl = model(counts(train_for(r, kind)))
    return lambda a, b, c: 0.3*dense(a, b, c) + 0.7*pl(a, b, c)

def perms(greek, wheels, refl, rings, pos, n=72):
    m = ic.M4(greek, wheels, refl, rings, '')
    streams = [m.process(ch*n, pos) for ch in A]
    return [[ord(streams[a][i]) - 65 for a in range(26)] for i in range(n)]

if __name__ == '__main__':
    if sys.argv[1] == 'xent':
        K = 85.7
        for kind in ('dense', 'lco', 'xnet'):
            hs = [H(scorer(r, kind), r['plaintext']) for r in msgs]
            print(f'{kind:6s} median {st.median(hs):.2f} b/l   log2 E[false keys @72] = {K - 72*(4.70 - st.median(hs)):+.0f}')
    elif sys.argv[1] == 'bin':
        kind, ndec, out = sys.argv[2], int(sys.argv[3]), sys.argv[4]
        random.seed(7)
        wos = [a+b+c for a in '12345678' for b in '12345678' for c in '12345678' if len({a, b, c}) == 3]
        ctrls = [r for r in msgs if r['length'] >= 72 and ic.M4(r['greek'], r['wheels'], r['reflector'], r['rings'], r['plugs']).process(r['ciphertext'], r['wheel_positions']) == r['plaintext']]
        with open(out, 'wb') as f:
            for r in ctrls[:12]:
                p = scorer(r, kind)
                tab = [math.log2(p(a, b, c)) for a in A for b in A for c in A]
                plug = list(range(26))
                for pr in r['plugs'].split():
                    x, y = ord(pr[0]) - 65, ord(pr[1]) - 65; plug[x] = y; plug[y] = x
                sets = [perms(r['greek'], r['wheels'], r['reflector'], r['rings'], r['wheel_positions'])]
                for _ in range(ndec):
                    sets.append(perms(random.choice('BC'), random.choice(wos), random.choice('BC'),
                                      ''.join(random.choices(A, k=4)), ''.join(random.choices(A, k=4))))
                f.write(struct.pack('<i', len(sets))); f.write(bytes(ord(c) - 65 for c in r['ciphertext'][:72]))
                f.write(bytes(plug)); f.write(struct.pack('<%df' % len(tab), *tab))
                for s in sets:
                    for row in s: f.write(bytes(row))
                print(r['id'], file=sys.stderr)
