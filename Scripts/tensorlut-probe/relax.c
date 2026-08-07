// Relaxation gap: mean-field TensorLUT (what the melt optimizes) vs the true expectation over
// binary circuits drawn from the same INIT probabilities (mixed-strategy reading).
#include "harness_core.h"
int main(int argc,char**argv){
  load(argv[1]); int M=atoi(argv[2]); float pmode=atof(argv[3]); int B=256,T=72;
  srand(99);
  uint8_t *ct=malloc(B*T); for(int i=0;i<B*T;i++) ct[i]=rand()%26;
  // reference plaintext (binary core)
  uint32_t *ref=malloc(4*B*T); double s; run_bits(B,T,ct,ref,NULL,&s);
  // choose M distinct LUTs to melt, set live entries to p (pmode<0 => uniform random p)
  int *mel=calloc(NL,sizeof(int)); int c=0; while(c<M){ int i=rand()%NL; if(!mel[i]){mel[i]=1;c++;} }
  static float P[4096][64];
  for(int i=0;i<NL;i++) if(mel[i]) for(int k=0;k<(1<<L[i].w);k++) P[i][k]= pmode<0? rand()/(float)RAND_MAX : pmode;
  // (1) mean-field float run, SoA, de Casteljau (identical math to the Metal kernel)
  float *w=calloc((size_t)B*W,4),*nx=malloc(4*(size_t)B*ND); for(int b=0;b<B;b++) w[(size_t)ONE*B+b]=1;
  double mse=0,l1=0; long cnt=0;
  for(int t=0;t<=T;t++){
    for(int b=0;b<B;b++){ w[(size_t)P_reset*B+b]=t?1:0; uint8_t cc=t?ct[b*T+t-1]:0; for(int i=0;i<8;i++) w[(size_t)P_ct[i]*B+b]=(cc>>i)&1; }
    for(int i=0;i<NL;i++){ Lut*l=&L[i]; float init[64]; for(int k=0;k<64;k++) init[k]= mel[i]?P[i][k&((1<<l->w)-1)]:l->init64[k];
      for(int b=0;b<B;b++){ float x[6]; for(int m=0;m<l->w;m++) x[m]=w[(size_t)l->in[m]*B+b]; w[(size_t)l->out*B+b]=evaldc(init,x,l->w);} }
    for(int i=0;i<ND;i++){ Dff*d=&F[i]; for(int b=0;b<B;b++){ float v=w[(size_t)d->D*B+b],q=w[(size_t)d->Q*B+b],n=v;
      if(d->R>=0){ float r=w[(size_t)d->R*B+b]; if(d->rpol?(r>=.5f):(r<.5f)){n=d->rval; goto dn;} }
      if(d->E>=0){ float e=w[(size_t)d->E*B+b]; if(!(d->epol?(e>=.5f):(e<.5f))) n=q; } dn: nx[(size_t)i*B+b]=n; } }
    for(int i=0;i<ND;i++) memcpy(w+(size_t)F[i].Q*B,nx+(size_t)i*B,4*B);
    if(t) for(int b=0;b<B;b++) for(int i=0;i<5;i++){ float y=w[(size_t)P_pt[i]*B+b], tg=(ref[b*T+t-1]>>i)&1; mse+=(y-tg)*(y-tg); l1+=fabsf(y-tg); cnt++; }
  }
  // (2) sampled binary circuits: word = stream, bit = sampled circuit (fixed across streams & ticks)
  static uint64_t leaf[4096][64];
  for(int i=0;i<NL;i++) if(mel[i]) for(int k=0;k<(1<<L[i].w);k++){ uint64_t x=0; for(int j=0;j<64;j++) if(rand()/(float)RAND_MAX < P[i][k]) x|=1ull<<j; leaf[i][k]=x; }
  uint64_t *wb=calloc((size_t)W*B,8),*nb=malloc(8*(size_t)ND*B); for(int b=0;b<B;b++) wb[(size_t)ONE*B+b]=~0ull;
  double ham=0; long hc=0;
  for(int t=0;t<=T;t++){
    for(int b=0;b<B;b++){ wb[(size_t)P_reset*B+b]=t?~0ull:0; uint8_t cc=t?ct[b*T+t-1]:0; for(int i=0;i<8;i++) wb[(size_t)P_ct[i]*B+b]=((cc>>i)&1)?~0ull:0; }
    for(int i=0;i<NL;i++){ Lut*l=&L[i]; for(int b=0;b<B;b++){ uint64_t v[64]; int n=1<<l->w;
      for(int k=0;k<n;k++) v[k]= mel[i]?leaf[i][k]:(((l->tt>>k)&1)?~0ull:0);
      for(int m=0;m<l->w;m++){ n>>=1; uint64_t sx=wb[(size_t)l->in[m]*B+b]; for(int j=0;j<n;j++){ uint64_t a=v[2*j],bb=v[2*j+1]; v[j]=a^((a^bb)&sx);} }
      wb[(size_t)l->out*B+b]=v[0]; } }
    for(int i=0;i<ND;i++){ Dff*d=&F[i]; for(int b=0;b<B;b++){ uint64_t dv=wb[(size_t)d->D*B+b],q=wb[(size_t)d->Q*B+b],n=dv;
      if(d->E>=0){ uint64_t e=wb[(size_t)d->E*B+b],en=d->epol?e:~e; n=(dv&en)|(q&~en);} if(d->R>=0){ uint64_t r=wb[(size_t)d->R*B+b],as=d->rpol?r:~r,rv=d->rval?~0ull:0; n=(rv&as)|(n&~as);} nb[(size_t)i*B+b]=n; } }
    for(int i=0;i<ND;i++) memcpy(wb+(size_t)F[i].Q*B,nb+(size_t)i*B,8*B);
    if(t) for(int b=0;b<B;b++) for(int i=0;i<5;i++){ uint64_t y=wb[(size_t)P_pt[i]*B+b], tg=((ref[b*T+t-1]>>i)&1)?~0ull:0; ham+=__builtin_popcountll(y^tg); hc+=64; }
  }
  printf("melt %3d LUTs, p=%s: mean-field MSE/bit %.4f | mean-field L1/bit %.4f | TRUE E[bit error] over 64 binary circuits %.4f\n",
    M, pmode<0?"U(0,1)":argv[3], mse/cnt, l1/cnt, ham/hc);
  return 0;
}
