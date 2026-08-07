// Reference for the proposed Metal blind-rotation arithmetic, written in the 32-bit ops MSL has
// (mul, mulhi), so each function transliterates to MSL line for line.
//   1. Montgomery and Shoup modular multiply vs the current `(ulong)a*b % p`.
//   2. Negacyclic NTT with the psi twist merged into the butterflies and NO bit reversal:
//      forward = Cooley-Tukey (natural in -> bit-reversed out), inverse = Gentleman-Sande
//      (bit-reversed in -> natural out); pointwise products happen in bit-reversed order.
//   3. Two-prime CRT, sufficient whenever the exact negacyclic coefficients fit in (-P/2, P/2).
// End-to-end check: sum over 2*ell of digit_poly * key_poly (negacyclic, mod 2^32) must equal
// schoolbook exactly, for the covering-b2 shape (B = 4, ell = 16, N = 1024).
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <time.h>

typedef uint32_t u32; typedef uint64_t u64; typedef int64_t i64;
static const u32 PR[3] = {2013265921u, 1811939329u, 469762049u};  // NegacyclicNTT.primes

static inline u32 mulhi(u32 a, u32 b){ return (u32)(((u64)a*b)>>32); }   // MSL: mulhi(a,b)
static inline u32 mod_mul_ref(u32 a,u32 b,u32 p){ return (u32)((u64)a*b%p); } // current kernel

// ---- Montgomery, R = 2^32, pinv = -p^{-1} mod 2^32; inputs < p, output < p -------------------
static u32 neg_inv32(u32 p){ u32 x=1; for(int i=0;i<5;i++) x*=2u-p*x; return (u32)(0u-x); }
static inline u32 mont_mul(u32 a,u32 b,u32 p,u32 pinv){
  u32 lo=a*b, hi=mulhi(a,b);
  u32 m=lo*pinv;
  u32 t=hi+mulhi(m,p)+(lo!=0u);          // (a*b + m*p) / 2^32, < 2p < 2^32 since p < 2^31
  return t>=p? t-p : t;
}
static inline u32 to_mont(u32 a,u32 p){ return (u32)(((u64)a<<32)%p); }  // host-side only

// ---- Shoup for a constant w: wq = floor(w * 2^32 / p); a may be any u32 --------------------
static inline u32 shoup_q(u32 w,u32 p){ return (u32)(((u64)w<<32)/p); }   // host-side only
static inline u32 shoup_mul(u32 a,u32 w,u32 wq,u32 p){
  u32 q=mulhi(a,wq); u32 r=a*w-q*p;       // exact in [0, 2p)
  return r>=p? r-p : r;
}

static u32 powmod(u32 b,u64 e,u32 p){ u64 r=1,x=b; while(e){ if(e&1) r=r*x%p; x=x*x%p; e>>=1;} return (u32)r; }
static u32 find_psi(u32 p,int n){ // primitive 2n-th root of unity
  for(u32 g=2;;g++){ u32 psi=powmod(g,(p-1)/(2*(u64)n),p); if(powmod(psi,n,p)==p-1) return psi; } }
static int bitrev(int x,int logn){ int r=0; for(int i=0;i<logn;i++){ r=(r<<1)|(x&1); x>>=1;} return r; }

typedef struct { u32 p,pinv; int n,logn; u32 *psi_br,*psi_br_q,*ipsi_br,*ipsi_br_q,ninv,ninv_q; } Ntt;
static void ntt_init(Ntt*T,u32 p,int n){
  T->p=p; T->pinv=neg_inv32(p); T->n=n; T->logn=__builtin_ctz(n);
  u32 psi=find_psi(p,n), ipsi=powmod(psi,2*(u64)n-1,p);
  T->psi_br=malloc(4*n); T->psi_br_q=malloc(4*n); T->ipsi_br=malloc(4*n); T->ipsi_br_q=malloc(4*n);
  for(int i=0;i<n;i++){ int j=bitrev(i,T->logn);
    T->psi_br[i]=powmod(psi,j,p);  T->psi_br_q[i]=shoup_q(T->psi_br[i],p);
    T->ipsi_br[i]=powmod(ipsi,j,p); T->ipsi_br_q[i]=shoup_q(T->ipsi_br[i],p); }
  T->ninv=powmod(n,p-2,p); T->ninv_q=shoup_q(T->ninv,p);
}
// Forward: natural order in, bit-reversed out, twist merged (Longa-Naehrig / Seiler form).
static void ntt_fwd(const Ntt*T,u32*a){
  u32 p=T->p; int n=T->n, t=n;
  for(int m=1;m<n;m<<=1){ t>>=1;
    for(int i=0;i<m;i++){ u32 w=T->psi_br[m+i], wq=T->psi_br_q[m+i]; int j1=2*i*t;
      for(int j=j1;j<j1+t;j++){ u32 u=a[j], v=shoup_mul(a[j+t],w,wq,p);
        u32 s=u+v; a[j]= s>=p? s-p:s; a[j+t]= u>=v? u-v : u+p-v; } } }
}
// Inverse: bit-reversed in, natural out, untwist and 1/n merged at the end.
static void ntt_inv(const Ntt*T,u32*a){
  u32 p=T->p; int n=T->n, t=1;
  for(int m=n;m>1;m>>=1){ int j1=0, h=m>>1;
    for(int i=0;i<h;i++){ u32 w=T->ipsi_br[h+i], wq=T->ipsi_br_q[h+i];
      for(int j=j1;j<j1+t;j++){ u32 u=a[j], v=a[j+t]; u32 s=u+v; a[j]= s>=p? s-p:s;
        a[j+t]=shoup_mul(u>=v? u-v : u+p-v, w, wq, p); }
      j1+=2*t; }
    t<<=1; }
  for(int j=0;j<n;j++) a[j]=shoup_mul(a[j],T->ninv,T->ninv_q,p);
}

int main(void){
  srand(2026);
  // 1. modular multiply equivalence
  for(int k=0;k<3;k++){ u32 p=PR[k], pinv=neg_inv32(p); long bad=0;
    for(int i=0;i<10000000;i++){ u32 a=((u32)rand()<<1^rand())%p, b=((u32)rand()<<1^rand())%p;
      u32 ref=mod_mul_ref(a,b,p);
      u32 mm=mont_mul(to_mont(a,p),to_mont(b,p),p,pinv); mm=mont_mul(mm,1,p,pinv); // out of Montgomery form
      u32 sh=shoup_mul(a,b,shoup_q(b,p),p);
      bad+=(mm!=ref)+(sh!=ref); }
    printf("prime %u: Montgomery and Shoup vs 64-bit %% over 10M random pairs: %ld mismatches\n",p,bad); }

  // 2 + 3. external-product shape: sum_{j<2*ell} digit_j (*) key_j, negacyclic, mod 2^32
  const int n=1024, ell=16, B=4; const int P=2*ell;
  u32 *dig=malloc(4*(size_t)P*n), *key=malloc(4*(size_t)P*n);
  for(size_t i=0;i<(size_t)P*n;i++){ dig[i]=rand()%B; key[i]=((u32)rand()<<16)^(u32)rand(); }
  // schoolbook, exact mod 2^32 via u32 wraparound
  u32 *ref=calloc(n,4);
  for(int j=0;j<P;j++) for(int a=0;a<n;a++){ u32 d=dig[(size_t)j*n+a]; if(!d) continue;
    for(int b=0;b<n;b++){ u32 v=d*key[(size_t)j*n+b]; int k=a+b; if(k<n) ref[k]+=v; else ref[k-n]-=v; } }
  // exact integer range bound for the negacyclic sum: |c| < 2*ell*n*(B-1)*2^32
  double bound_bits = __builtin_log2((double)P*n*(B-1)) + 32 + 1;  // +1: two-sided range
  printf("covering-b2 shape (B=%d, ell=%d, N=%d): needs CRT modulus > 2^%.1f; primes[0]*primes[1] = 2^%.2f\n",
         B,ell,n,bound_bits,__builtin_log2((double)PR[0]*PR[1]));
  // NTT path with two primes, Garner CRT, centered, reduced mod 2^32
  Ntt T[2]; ntt_init(&T[0],PR[0],n); ntt_init(&T[1],PR[1],n);
  u32 *acc[2], *tmp=malloc(4*n), *kh=malloc(4*n);
  for(int k=0;k<2;k++){ acc[k]=calloc(n,4); u32 p=PR[k];
    for(int j=0;j<P;j++){
      memcpy(tmp,dig+(size_t)j*n,4*n); ntt_fwd(&T[k],tmp);
      for(int i=0;i<n;i++) kh[i]=key[(size_t)j*n+i]%p;
      ntt_fwd(&T[k],kh);                   // on the GPU the key is stored pre-transformed
      for(int i=0;i<n;i++){ u32 s=acc[k][i]+(u32)((u64)tmp[i]*kh[i]%p); acc[k][i]= s>=p? s-p:s; } }
    ntt_inv(&T[k],acc[k]); }
  u32 p0=PR[0], p1=PR[1]; u32 inv01=powmod(p0%p1,p1-2,p1); u64 P01=(u64)p0*p1; long bad=0;
  for(int i=0;i<n;i++){
    u32 a0=acc[0][i], a1=acc[1][i];
    u32 v1=(u32)((u64)((a1+p1-a0%p1)%p1)*inv01%p1);
    u64 x=(u64)a0+(u64)p0*v1;               // in [0, p0*p1)
    i64 c = x> P01/2 ? (i64)(x-P01) : (i64)x; // centered
    bad += ((u32)c != ref[i]);
  }
  printf("2-prime NTT (merged twist, no bit reversal) + Garner CRT vs schoolbook mod 2^32: %ld / %d coefficient mismatches\n",bad,n);

  // rough CPU cost ratio of the reductions (not a GPU number)
  volatile u32 sink=0; u32 p=PR[0], pinv=neg_inv32(p), w=123456789u%p, wq=shoup_q(w,p); clock_t c0;
  u32 x=1; c0=clock(); for(int i=0;i<200000000;i++){ x=mod_mul_ref(x+i,w,p); } double t_ref=(double)(clock()-c0)/CLOCKS_PER_SEC; sink^=x;
  x=1; c0=clock(); for(int i=0;i<200000000;i++){ x=mont_mul(x+i<p?x+i:x,w,p,pinv); } double t_m=(double)(clock()-c0)/CLOCKS_PER_SEC; sink^=x;
  x=1; c0=clock(); for(int i=0;i<200000000;i++){ x=shoup_mul(x+i,w,wq,p); } double t_s=(double)(clock()-c0)/CLOCKS_PER_SEC; sink^=x;
  printf("CPU x86 (has a hardware 64-bit divider, unlike Apple GPUs), 200M dependent mulmods: %% %.2fs | Montgomery %.2fs | Shoup %.2fs\n",t_ref,t_m,t_s);
  return (int)(sink&0);
}
