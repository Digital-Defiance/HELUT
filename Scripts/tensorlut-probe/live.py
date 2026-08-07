import json,sys,collections
def analyze(path):
    d=json.load(open(path))
    for mname,m in d['modules'].items():
        cells=m.get('cells',{})
        luts=[c for c in cells.values() if c['type']=='$lut']
        if not luts: continue
        dffs=[c for c in cells.values() if 'DFF' in c['type']]
        maxnet=0
        for c in cells.values():
            for bs in c['connections'].values():
                for b in bs:
                    if isinstance(b,int): maxnet=max(maxnet,b)
        for p in m['ports'].values():
            for b in p['bits']:
                if isinstance(b,int): maxnet=max(maxnet,b)
        prod={c['connections']['Y'][0]:i for i,c in enumerate(luts)}
        # Kahn ASAP order
        indeg=[0]*len(luts); deps=collections.defaultdict(list)
        for i,c in enumerate(luts):
            s=set()
            for b in c['connections']['A']:
                if isinstance(b,int) and b in prod and prod[b] not in s:
                    s.add(prod[b]); deps[prod[b]].append(i); indeg[i]+=1
        cur=[i for i in range(len(luts)) if indeg[i]==0]; order=[]
        while cur:
            order+=cur; nxt=[]
            for i in cur:
                for j in deps[i]:
                    indeg[j]-=1
                    if indeg[j]==0: nxt.append(j)
            cur=nxt
        # sinks: DFF D/E/R, outputs
        sinks=set()
        for c in dffs:
            for p in ('D','E','R'):
                for b in c['connections'].get(p,[]):
                    if isinstance(b,int): sinks.add(b)
        for p in m['ports'].values():
            if p['direction']=='output':
                for b in p['bits']:
                    if isinstance(b,int): sinks.add(b)
        # last use position of each net
        last={}
        for pos,i in enumerate(order):
            for b in luts[i]['connections']['A']:
                if isinstance(b,int): last[b]=pos
        # sources: inputs+Q live from start
        srcs=set()
        for p in m['ports'].values():
            if p['direction']=='input':
                for b in p['bits']:
                    if isinstance(b,int): srcs.add(b)
        for c in dffs:
            for b in c['connections']['Q']:
                if isinstance(b,int): srcs.add(b)
        END=len(order)
        live=set(s for s in srcs if s in last or s in sinks)
        peak=len(live); 
        # process
        died=collections.defaultdict(list)
        for n,p in last.items():
            if n not in sinks: died[p].append(n)
        for pos,i in enumerate(order):
            y=luts[i]['connections']['Y'][0]
            for n in died[pos]: live.discard(n)
            if y in last or y in sinks: live.add(y)
            peak=max(peak,len(live))
        nets_used=set()
        for c in luts:
            for b in c['connections']['A']+c['connections']['Y']:
                if isinstance(b,int): nets_used.add(b)
        print(f"{path}: totalWires(maxnet+1)={maxnet+1} distinct nets used by LUTs={len(nets_used)} sinks(state/outputs)={len(sinks)} peak-live(ASAP order)={peak}")
for p in sys.argv[1:]: analyze(p)
