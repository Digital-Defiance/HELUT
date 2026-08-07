import json, numpy as np, collections, itertools
A=ord('A')
T=json.load(open('tafel_a_quelle_2499.json'))
W={"1":"EKMFLGDQVZNTOWYHXUSPAIBRCJ","2":"AJDKSIRUXBLHWTMCQGZNPYFVOE","3":"BDFHJLCPRTXVZNYEIWGAKMUSQO",
"4":"ESOVPZJAYQUIRHXLNFTGKDCMWB","5":"VZBRGITYUPSDNHLXAWMJQOFECK","6":"JPGVOUMFYQBENHZRDKASXLICTW",
"7":"NZJHGRCXMYSWBOUFAIVLPEKQDT","8":"FKQHTLXOCBJSPDZRAMEWNIUYGV"}
GREEK={"B":"LEYJVCNIXWPBQMDRTAKZGFUHOS","C":"FSOKANUERHMBTIYCWLQPZXVGJD"}
UKW={"B":"ENKQAUYWJICOPBLMDXZVFTHRGS","C":"RDOBJNTKVEHMLFCWZAXGYIPSUQ"}
n=lambda s:[ord(c)-A for c in s]
def inv(p):
    o=[0]*26
    for i,v in enumerate(p): o[v]=i
    return o
def decode(g1,g2,orient,row):
    pairs=[g1[0:2],g1[2:4],g2[0:2],g2[2:4]] if orient=='h' else [g1[i]+g2[i] for i in range(4)]
    ps=[T[p] for p in pairs]
    return ''.join(p[row] for p in ps)
def maxrun(Ds):
    Ds=np.sort(np.stack(Ds),axis=0); eq=(Ds[1:]==Ds[:-1])
    best=np.ones(Ds.shape[1],dtype=np.int16); run=np.ones(Ds.shape[1],dtype=np.int16)
    for k in range(eq.shape[0]):
        run=np.where(eq[k],run+1,1); best=np.maximum(best,run)
    return best
corpus=json.load(open('Fixtures/u534_corpus.json'))['messages']
key=('B','C','438','AACU','CH EJ NV OU TY LG SZ PK DI QB')
rs=[r for r in corpus if r.get('broken') and r.get('indicators') and r['wheels']=='438']
seen=set();uniq=[]
for r in rs:
    s=(tuple(r['indicators']),r['wheel_positions'])
    if s not in seen: seen.add(s);uniq.append(r)
refl,greek,wheels,rings,plugs=key
fw=[np.array(n(GREEK[greek]))]+[np.array(n(W[w])) for w in wheels]
rv=[np.array(inv(list(f))) for f in fw]
ukw=np.array(n(UKW[refl])); plug=np.arange(26)
for p in plugs.split(): x,y=n(p); plug[x]=y; plug[y]=x
R=np.array(n(rings))
G=np.array(list(itertools.product(range(26),repeat=4)))
def enc(ch,kp,turn):
    off=G.copy(); off[:,3]=(off[:,3]+kp)%26
    if turn and kp>=turn: off[:,2]=(off[:,2]+1)%26
    c=np.full(len(G),plug[ord(ch)-A])
    for r in (3,2,1,0): c=(fw[r][(c+off[:,r])%26]-off[:,r])%26
    c=ukw[c]
    for r in (0,1,2,3): c=(rv[r][(c+off[:,r])%26]-off[:,r])%26
    return plug[c]
overall=[]
for orient in ('h','v'):
  for row in (1,0):
    for start in (0,1):   # which 3 letters: V[0:3] or V[1:4]; also 4-letter
      for turn in (0,):
        outs=[]; offs=[]
        for r in uniq:
            V=decode(*r['indicators'],orient,row)
            letters=V[start:start+3] if start is not None else V
            outs.append([enc(ch,j+1,turn) for j,ch in enumerate(letters)])
            offs.append((np.array(n(r['wheel_positions']))-R)%26)
        best_cfg=(0,)
        for tgt in itertools.permutations(range(4),3):
            Ds=[]
            for o,e in zip(offs,outs):
                D=np.zeros(len(G),dtype=np.int32)
                for letter,t in zip(e,tgt): D=D*26+((letter-o[t])%26)
                Ds.append(D)
            b=maxrun(Ds); i=int(b.argmax())
            if b[i]>best_cfg[0]: best_cfg=(int(b[i]),tgt,G[i].tolist())
        print(orient,row,start,turn,'best',best_cfg,flush=True)
