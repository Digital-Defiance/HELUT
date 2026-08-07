import json,sys,collections
def anf(bits,w):
    a=list(bits)
    for m in range(w):
        for k in range(1<<w):
            if k>>m&1: a[k]^=a[k^(1<<m)]
    return a
for path in sys.argv[1:]:
    d=json.load(open(path))
    for mn,m in d['modules'].items():
        luts=[c for c in m['cells'].values() if c['type']=='$lut']
        if not luts: continue
        aff=0; deg=collections.Counter(); anfterms=0; muxcost=0
        for c in luts:
            w=len(c['connections']['A']); t=c['parameters']['LUT']; t=t if isinstance(t,str) else format(t,'b'); t=t.zfill(1<<w)
            bits=[int(t[len(t)-1-k]) for k in range(1<<w)]
            a=anf(bits,w)
            dg=max([bin(k).count('1') for k in range(1<<w) if a[k]] or [0])
            deg[dg]+=1
            if dg<=1: aff+=1
            anfterms+=sum(a)
        print(f"{path.split('/')[-1]}: {len(luts)} LUTs; affine (XOR/NOT/wire) LUTs: {aff} ({100*aff/len(luts):.1f}%); ANF degree histogram {dict(sorted(deg.items()))}")
