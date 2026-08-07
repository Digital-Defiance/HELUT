# Flatten a Yosys JSON (LUT + SDFF/SDFFE/DFF) into a plain-text netlist for the C harness.
import json,sys,collections
src,modname,out=sys.argv[1],sys.argv[2],sys.argv[3]
m=json.load(open(src))['modules'][modname]
cells=m['cells']
maxnet=1
def nets(bs):
    for b in bs:
        if isinstance(b,int): yield b
for c in cells.values():
    for bs in c['connections'].values():
        for b in nets(bs): maxnet=max(maxnet,b)
for p in m['ports'].values():
    for b in nets(p['bits']): maxnet=max(maxnet,b)
ONE=maxnet+1; ZERO=maxnet+2; W=maxnet+3
def mb(b):
    if isinstance(b,int): return b
    return ONE if b=='1' else ZERO
luts=[];dffs=[]
for k in sorted(cells):
    c=cells[k]
    if c['type']=='$lut':
        A=[mb(b) for b in c['connections']['A']]; w=len(A)
        t=c['parameters']['LUT']; t=t if isinstance(t,str) else format(t,'b'); t=t.zfill(1<<w)
        tt=0
        for i in range(1<<w):
            if t[len(t)-1-i]=='1': tt|=1<<i
        luts.append((A,mb(c['connections']['Y'][0]),tt))
    elif 'DFF' in c['type']:
        ty=c['type']; code=ty[2:-1].split('_')[1]
        D=mb(c['connections']['D'][0]); Q=mb(c['connections']['Q'][0])
        R=mb(c['connections']['R'][0]) if 'R' in c['connections'] else -1
        E=mb(c['connections']['E'][0]) if 'E' in c['connections'] else -1
        rpol= 1 if (R>=0 and code[1]=='P') else 0
        rval= int(code[2]) if R>=0 else 0
        epol= 1 if (E>=0 and code[-1]=='P') else 0
        dffs.append((D,Q,E,epol,R,rpol,rval))
# Kahn levels
prod={y:i for i,(A,y,t) in enumerate(luts)}
indeg=[0]*len(luts); deps=collections.defaultdict(list)
for i,(A,y,t) in enumerate(luts):
    s=set()
    for b in A:
        if b in prod and prod[b] not in s: s.add(prod[b]); deps[prod[b]].append(i); indeg[i]+=1
cur=[i for i in range(len(luts)) if indeg[i]==0]; order=[]; levels=[]
while cur:
    levels.append(len(cur)); order+=cur; nxt=[]
    for i in cur:
        for j in deps[i]:
            indeg[j]-=1
            if indeg[j]==0: nxt.append(j)
    cur=nxt
ports={n:[mb(b) for b in p['bits']] for n,p in m['ports'].items()}
with open(out,'w') as f:
    f.write(f"{W} {ONE} {ZERO} {len(luts)} {len(dffs)} {len(levels)}\n")
    f.write(" ".join(map(str,levels))+"\n")
    for i in order:
        A,y,t=luts[i]; A6=A+[ZERO]*(6-len(A))
        f.write(f"{len(A)} {' '.join(map(str,A6))} {y} {t}\n")
    for d in dffs: f.write(" ".join(map(str,d))+"\n")
    for n in ('resetn','ciphertext_char','plaintext_char','linguistic_score'):
        f.write(n+" "+" ".join(map(str,ports[n]))+"\n")
print("wires",W,"luts",len(luts),"dffs",len(dffs),"levels",len(levels))
