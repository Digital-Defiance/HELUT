import json,sys,collections
def analyze(path):
    d=json.load(open(path))
    for mname,m in d['modules'].items():
        cells=m.get('cells',{})
        if not cells: continue
        types=collections.Counter(c['type'] for c in cells.values())
        luts=[c for c in cells.values() if c['type']=='$lut']
        dffs=[c for c in cells.values() if 'DFF' in c['type'] or 'LATCH' in c['type'] or 'dff' in c['type']]
        if not luts and not dffs: continue
        print(f"== {path} :: {mname}")
        print("  types:",dict(types.most_common(12)))
        # widths
        wc=collections.Counter(len(c['connections']['A']) for c in luts)
        print("  LUT width hist:",dict(sorted(wc.items())))
        q=set()
        for c in dffs:
            for b in c['connections'].get('Q',[]):
                if isinstance(b,int): q.add(b)
        # DFF->DFF direct
        dd=0; de=0
        for c in dffs:
            for port in ('D',):
                for b in c['connections'].get(port,[]):
                    if isinstance(b,int) and b in q: dd+=1
            for port in ('E','R','S'):
                for b in c['connections'].get(port,[]):
                    if isinstance(b,int) and b in q: de+=1
        print(f"  DFFs={len(dffs)} D-from-Q={dd} ctrl-from-Q={de}")
        # levels
        prod={}
        for i,c in enumerate(luts): prod[c['connections']['Y'][0]]=i
        lvl=[None]*len(luts)
        import sys
        sys.setrecursionlimit(100000)
        order=[]
        indeg=[0]*len(luts); deps=collections.defaultdict(list)
        for i,c in enumerate(luts):
            s=set()
            for b in c['connections']['A']:
                if isinstance(b,int) and b in prod and prod[b]!=i and prod[b] not in s:
                    s.add(prod[b]); deps[prod[b]].append(i); indeg[i]+=1
        cur=[i for i in range(len(luts)) if indeg[i]==0]; L=[]
        while cur:
            L.append(len(cur)); nxt=[]
            for i in cur:
                for j in deps[i]:
                    indeg[j]-=1
                    if indeg[j]==0: nxt.append(j)
            cur=nxt
        print(f"  LUTs={len(luts)} levels={len(L)} widths(first/last)={L[:8]}...{L[-5:]} max={max(L) if L else 0} min={min(L) if L else 0}")
        # truth-table zero-dependence: how many LUTs have a declared input the function doesn't depend on
        nodep=0; fn_const=0
        for c in luts:
            t=c['parameters']['LUT']; w=len(c['connections']['A'])
            t=t if isinstance(t,str) else format(t,'b')
            t=t.zfill(1<<w)
            bits=[t[len(t)-1-k]=='1' for k in range(1<<w)]
            for m in range(w):
                if all(bits[k]==bits[k^(1<<m)] for k in range(1<<w)): nodep+=1
        print(f"  vacuous LUT inputs={nodep}")
for p in sys.argv[1:]: analyze(p)
