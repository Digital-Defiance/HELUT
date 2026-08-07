import numpy as np
rng=np.random.default_rng(1)
x=rng.integers(0,2**32,size=200000,dtype=np.uint64)
def unsigned(x,bl):
    ell=32//bl; B=1<<bl; ds=[]
    for lv in range(ell):
        sh=32-(lv+1)*bl; ds.append(((x>>np.uint64(sh))&np.uint64(B-1)).astype(np.int64))
    return ds
def balanced(x,bl):
    # standard signed digits in [-B/2, B/2): process from least significant level with carry
    ell=32//bl; B=1<<bl; ds=[None]*ell; carry=np.zeros_like(x,dtype=np.int64)
    for lv in reversed(range(ell)):
        sh=32-(lv+1)*bl
        d=((x>>np.uint64(sh))&np.uint64(B-1)).astype(np.int64)+carry
        carry=(d>=B//2).astype(np.int64); d=d-carry*B; ds[lv]=d
    return ds  # final carry wraps mod 2^32 (torus)
def recon(ds,bl):
    ell=len(ds); acc=np.zeros(len(ds[0]),dtype=np.int64)
    for lv,d in enumerate(ds): acc+=d*(1<<(32-(lv+1)*bl))
    return (acc%(2**32)).astype(np.uint64)
print(" B  ell | E[d^2] unsigned | E[d^2] balanced | variance ratio | exact mod 2^32")
for bl in (1,2,4):
    u=unsigned(x,bl); b=balanced(x,bl)
    eu=np.mean(np.concatenate(u)**2); eb=np.mean(np.concatenate(b)**2)
    ok=np.all(recon(u,bl)==x) and np.all(recon(b,bl)==x)
    print(f"{1<<bl:2d} {32//bl:4d} | {eu:15.3f} | {eb:15.3f} | {eu/eb:14.2f} | {ok}")
# NAF for base 2
