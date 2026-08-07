// Prototype harness: three evaluators for the same Yosys LUT/DFF netlist.
//   A) float_ref : mirrors HELUT's Metal kernel (AoS lanes, 64-corner multilinear sum, padded INIT)
//   B) float_dc  : SoA lanes, width-aware de Casteljau (2^w - 1 lerps), same math
//   C) bits      : SoA bit-sliced uint64 (64 lanes/word), Shannon mux tree over live width
// Plus DFF commit modes: two-phase (reference semantics) vs in-place (what soft_dff_update does)
// under two different thread orders, to expose the read-after-write race.
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <math.h>
#include <time.h>

typedef struct { int w; int in[6]; int out; uint64_t tt; float init64[64]; } Lut;
typedef struct { int D,Q,E,epol,R,rpol,rval; } Dff;

static int W, ONE, ZERO, NL, ND, NLV;
static int *lvl;
static Lut *L;
static Dff *F;
static int P_reset, P_ct[8], P_pt[8], P_ls[16];

static double now(void){ struct timespec t; clock_gettime(CLOCK_MONOTONIC,&t); return t.tv_sec+1e-9*t.tv_nsec; }

static void load(const char *path){
  FILE *f=fopen(path,"r"); if(!f){perror(path);exit(1);}
  if(fscanf(f,"%d %d %d %d %d %d",&W,&ONE,&ZERO,&NL,&ND,&NLV)!=6) exit(2);
  lvl=malloc(sizeof(int)*NLV); for(int i=0;i<NLV;i++) if(fscanf(f,"%d",&lvl[i])!=1) exit(2);
  L=calloc(NL,sizeof(Lut)); F=calloc(ND,sizeof(Dff));
  for(int i=0;i<NL;i++){
    unsigned long long tt;
    if(fscanf(f,"%d %d %d %d %d %d %d %d %llu",&L[i].w,&L[i].in[0],&L[i].in[1],&L[i].in[2],&L[i].in[3],&L[i].in[4],&L[i].in[5],&L[i].out,&tt)!=9) exit(3);
    L[i].tt=tt; int raw=1<<L[i].w;
    for(int k=0;k<64;k++) L[i].init64[k]=(float)((tt>>(k%raw))&1ull); // HELUT broadcast padding
  }
  for(int i=0;i<ND;i++) if(fscanf(f,"%d %d %d %d %d %d %d",&F[i].D,&F[i].Q,&F[i].E,&F[i].epol,&F[i].R,&F[i].rpol,&F[i].rval)!=7) exit(4);
  char name[64];
  for(int p=0;p<4;p++){ if(fscanf(f,"%63s",name)!=1) exit(5);
    int n = !strcmp(name,"resetn")?1: !strcmp(name,"linguistic_score")?16:8;
    int *dst = !strcmp(name,"resetn")?&P_reset: !strcmp(name,"ciphertext_char")?P_ct: !strcmp(name,"plaintext_char")?P_pt:P_ls;
    for(int i=0;i<n;i++) if(fscanf(f,"%d",&dst[i])!=1) exit(6);
  }
  fclose(f);
}

// ---------------- A) float_ref: exactly the Metal kernel's arithmetic, AoS ----------------
static inline float eval64(const float *init, const float x[6]){
  float acc=0.f;
  for(int k=0;k<64;k++){
    float p0=(k&1)?x[0]:1.f-x[0], p1=(k&2)?x[1]:1.f-x[1], p2=(k&4)?x[2]:1.f-x[2];
    float p3=(k&8)?x[3]:1.f-x[3], p4=(k&16)?x[4]:1.f-x[4], p5=(k&32)?x[5]:1.f-x[5];
    acc+=init[k]*(p0*p1*p2*p3*p4*p5);
  }
  return acc;
}
// ---------------- B) de Casteljau on the Boolean cube: 2^w-1 lerps --------------------------
static inline float evaldc(const float *init, const float *x, int w){
  float v[64]; int n=1<<w; for(int k=0;k<n;k++) v[k]=init[k];
  for(int m=0;m<w;m++){ n>>=1; float t=x[m]; for(int j=0;j<n;j++){ float a=v[2*j], b=v[2*j+1]; v[j]=a+t*(b-a);} }
  return v[0];
}

enum { TWO_PHASE=0, INPLACE_FWD=1, INPLACE_REV=2 };

static void dff_float_aos(float *wires,int B,int mode,float *scratch){
  for(int b=0;b<B;b++){
    float *lw=wires+(size_t)b*W;
    int start = mode==INPLACE_REV? ND-1:0, step = mode==INPLACE_REV? -1:1;
    for(int c=0;c<ND;c++){
      int i=start+c*step; Dff *d=&F[i];
      float dv=lw[d->D], q=lw[d->Q], nx=dv;
      if(d->R>=0){ float r=lw[d->R]; int as = d->rpol? (r>=.5f):(r<.5f);
        if(as){ nx=(float)d->rval; goto done; } }
      if(d->E>=0){ float e=lw[d->E]; int en=d->epol?(e>=.5f):(e<.5f); if(!en) nx=q; }
      done:
      if(mode==TWO_PHASE) scratch[(size_t)b*ND+i]=nx; else lw[d->Q]=nx;
    }
    if(mode==TWO_PHASE) for(int i=0;i<ND;i++) lw[F[i].Q]=scratch[(size_t)b*ND+i];
  }
}

static void run_float_ref(int B,int T,const uint8_t *ct,uint32_t *pt_out,uint32_t *ls_out,int mode,double *secs,uint64_t *visited){
  float *wires=calloc((size_t)B*W,sizeof(float)), *scr=malloc(sizeof(float)*(size_t)B*ND);
  for(int b=0;b<B;b++) wires[(size_t)b*W+ONE]=1.f;
  double t0=now();
  for(int t=0;t<=T;t++){
    for(int b=0;b<B;b++){ float *lw=wires+(size_t)b*W;
      lw[P_reset]= t==0?0.f:1.f;
      uint8_t c= t==0?0:ct[(size_t)b*T+t-1]; for(int i=0;i<8;i++) lw[P_ct[i]]=(float)((c>>i)&1); }
    for(int i=0;i<NL;i++){ Lut *l=&L[i];
      for(int b=0;b<B;b++){ float *lw=wires+(size_t)b*W; float x[6];
        for(int m=0;m<6;m++) x[m]=lw[l->in[m]];
        if(visited && t>0){ int idx=0; for(int m=0;m<l->w;m++) idx|=(x[m]>=.5f)<<m; visited[i]|=1ull<<idx; }
        lw[l->out]=eval64(l->init64,x); } }
    dff_float_aos(wires,B,mode,scr);
    if(t>0) for(int b=0;b<B;b++){ float *lw=wires+(size_t)b*W; uint32_t p=0,s=0;
      for(int i=0;i<8;i++) p|=(uint32_t)(lw[P_pt[i]]>=.5f)<<i; for(int i=0;i<16;i++) s|=(uint32_t)(lw[P_ls[i]]>=.5f)<<i;
      pt_out[(size_t)b*T+t-1]=p; ls_out[(size_t)b*T+t-1]=s; }
  }
  *secs=now()-t0; free(wires); free(scr);
}

static void run_float_dc(int B,int T,const uint8_t *ct,uint32_t *pt_out,double *secs){
  float *wires=calloc((size_t)B*W,sizeof(float)), *nx=malloc(sizeof(float)*(size_t)B*ND);
  for(int b=0;b<B;b++) wires[(size_t)ONE*B+b]=1.f;
  double t0=now();
  for(int t=0;t<=T;t++){
    for(int b=0;b<B;b++){ wires[(size_t)P_reset*B+b]= t==0?0.f:1.f;
      uint8_t c= t==0?0:ct[(size_t)b*T+t-1]; for(int i=0;i<8;i++) wires[(size_t)P_ct[i]*B+b]=(float)((c>>i)&1); }
    for(int i=0;i<NL;i++){ Lut *l=&L[i]; float *o=wires+(size_t)l->out*B; const float *xi[6];
      for(int m=0;m<l->w;m++) xi[m]=wires+(size_t)l->in[m]*B;
      for(int b=0;b<B;b++){ float x[6]; for(int m=0;m<l->w;m++) x[m]=xi[m][b]; o[b]=evaldc(l->init64,x,l->w);} }
    for(int i=0;i<ND;i++){ Dff *d=&F[i];
      for(int b=0;b<B;b++){ float v=wires[(size_t)d->D*B+b], q=wires[(size_t)d->Q*B+b], n=v;
        if(d->R>=0){ float r=wires[(size_t)d->R*B+b]; if(d->rpol?(r>=.5f):(r<.5f)){ n=(float)d->rval; goto dn; } }
        if(d->E>=0){ float e=wires[(size_t)d->E*B+b]; if(!(d->epol?(e>=.5f):(e<.5f))) n=q; }
        dn: nx[(size_t)i*B+b]=n; } }
    for(int i=0;i<ND;i++) memcpy(wires+(size_t)F[i].Q*B, nx+(size_t)i*B, sizeof(float)*B);
    if(t>0) for(int b=0;b<B;b++){ uint32_t p=0; for(int i=0;i<8;i++) p|=(uint32_t)(wires[(size_t)P_pt[i]*B+b]>=.5f)<<i; pt_out[(size_t)b*T+t-1]=p; }
  }
  *secs=now()-t0; free(wires); free(nx);
}

// ---------------- C) bit-sliced: 64 lanes per uint64, mux tree with constant leaves -------
static inline uint64_t evalbits(uint64_t tt,int w,const uint64_t *x){
  uint64_t v[64]; int n=1<<w;
  for(int k=0;k<n;k++) v[k]= ((tt>>k)&1)? ~0ull:0ull;
  for(int m=0;m<w;m++){ n>>=1; uint64_t s=x[m]; for(int j=0;j<n;j++){ uint64_t a=v[2*j],b=v[2*j+1]; v[j]=a^((a^b)&s);} }
  return v[0];
}
static void run_bits(int B,int T,const uint8_t *ct,uint32_t *pt_out,uint32_t *ls_out,double *secs){
  int NW=(B+63)/64; uint64_t *wires=calloc((size_t)W*NW,8), *nx=malloc((size_t)ND*NW*8);
  for(int k=0;k<NW;k++) wires[(size_t)ONE*NW+k]=~0ull;
  double t0=now();
  for(int t=0;t<=T;t++){
    for(int k=0;k<NW;k++) wires[(size_t)P_reset*NW+k]= t==0?0:~0ull;
    for(int i=0;i<8;i++) for(int k=0;k<NW;k++){ uint64_t wd=0; for(int j=0;j<64&&k*64+j<B;j++){ int b=k*64+j; uint8_t c= t==0?0:ct[(size_t)b*T+t-1]; wd|=(uint64_t)((c>>i)&1)<<j;} wires[(size_t)P_ct[i]*NW+k]=wd; }
    for(int i=0;i<NL;i++){ Lut *l=&L[i];
      for(int k=0;k<NW;k++){ uint64_t x[6]; for(int m=0;m<l->w;m++) x[m]=wires[(size_t)l->in[m]*NW+k];
        wires[(size_t)l->out*NW+k]=evalbits(l->tt,l->w,x);} }
    for(int i=0;i<ND;i++){ Dff *d=&F[i];
      for(int k=0;k<NW;k++){ uint64_t dv=wires[(size_t)d->D*NW+k], q=wires[(size_t)d->Q*NW+k], n=dv;
        if(d->E>=0){ uint64_t e=wires[(size_t)d->E*NW+k]; uint64_t en=d->epol?e:~e; n=(dv&en)|(q&~en);}
        if(d->R>=0){ uint64_t r=wires[(size_t)d->R*NW+k]; uint64_t as=d->rpol?r:~r; uint64_t rv=d->rval?~0ull:0; n=(rv&as)|(n&~as);}
        nx[(size_t)i*NW+k]=n; } }
    for(int i=0;i<ND;i++) memcpy(wires+(size_t)F[i].Q*NW, nx+(size_t)i*NW, 8*(size_t)NW);
    if(t>0) for(int b=0;b<B;b++){ int k=b/64,j=b%64; uint32_t p=0,s=0;
      for(int i=0;i<8;i++) p|=(uint32_t)((wires[(size_t)P_pt[i]*NW+k]>>j)&1)<<i;
      for(int i=0;i<16;i++) s|=(uint32_t)((wires[(size_t)P_ls[i]*NW+k]>>j)&1)<<i;
      pt_out[(size_t)b*T+t-1]=p; if(ls_out) ls_out[(size_t)b*T+t-1]=s; }
  }
  *secs=now()-t0; free(wires); free(nx);
}

int main(int argc,char**argv){
  load(argv[1]); int B=argc>2?atoi(argv[2]):1024, T=argc>3?atoi(argv[3]):72;
  srand(12345);
  uint8_t *ct=malloc((size_t)B*T); for(size_t i=0;i<(size_t)B*T;i++) ct[i]=rand()%26;
  size_t n=(size_t)B*T;
  uint32_t *ptA=malloc(4*n),*lsA=malloc(4*n),*ptF=malloc(4*n),*lsF=malloc(4*n),*ptR=malloc(4*n),*lsR=malloc(4*n),*ptB=malloc(4*n),*ptC=malloc(4*n),*lsC=malloc(4*n);
  uint64_t *vis=calloc(NL,8);
  double sA,sF,sR,sB,sC;
  run_float_ref(B,T,ct,ptA,lsA,TWO_PHASE,&sA,vis);
  run_float_ref(B,T,ct,ptF,lsF,INPLACE_FWD,&sF,NULL);
  run_float_ref(B,T,ct,ptR,lsR,INPLACE_REV,&sR,NULL);
  run_float_dc(B,T,ct,ptB,&sB);
  run_bits(B,T,ct,ptC,lsC,&sC);
  size_t dPtF=0,dLsF=0,dPtR=0,dLsR=0,dB=0,dC=0,dCl=0;
  for(size_t i=0;i<n;i++){ dPtF+=ptA[i]!=ptF[i]; dLsF+=lsA[i]!=lsF[i]; dPtR+=ptA[i]!=ptR[i]; dLsR+=lsA[i]!=lsR[i]; dB+=ptA[i]!=ptB[i]; dC+=ptA[i]!=ptC[i]; dCl+=lsA[i]!=lsC[i]; }
  printf("netlist: %d LUTs, %d DFFs, %d levels, %d wires; B=%d lanes, T=%d ticks\n",NL,ND,NLV,W,B,T);
  printf("DFF commit, in-place forward order : plaintext mismatches %zu / %zu, linguistic_score mismatches %zu\n",dPtF,n,dLsF);
  printf("DFF commit, in-place reverse order : plaintext mismatches %zu / %zu, linguistic_score mismatches %zu\n",dPtR,n,dLsR);
  printf("de Casteljau SoA vs reference      : plaintext mismatches %zu\n",dB);
  printf("bit-sliced vs reference            : plaintext mismatches %zu, linguistic_score mismatches %zu\n",dC,dCl);
  double lt=(double)B*(T+1)*NL;
  printf("throughput (LUT-lane evals/s): ref64 %.3g | deCasteljau %.3g (x%.1f) | bitsliced %.3g (x%.1f)\n",lt/sA,lt/sB,sA/sB,lt/sC,sA/sC);
  // corner occupancy over live entries
  long live=0,unv=0; int dead=0; for(int i=0;i<NL;i++){ int r=1<<L[i].w; live+=r; dead+=64-r; for(int k=0;k<r;k++) if(!((vis[i]>>k)&1)) unv++; }
  printf("INIT floats: %d total, %ld live (%.1f%%), %d dead padding (%.1f%%); live corners never visited in %zu lane-ticks: %ld (%.1f%% of live)\n",
    NL*64,live,100.0*live/(NL*64),dead,100.0*dead/(NL*64),n,unv,100.0*unv/live);
  // numerical check of de Casteljau vs 64-corner on fractional (melted) values
  double maxd=0; srand(7);
  for(int trial=0;trial<200000;trial++){ float init[64],x[6]; for(int k=0;k<64;k++) init[k]=rand()/(float)RAND_MAX; for(int m=0;m<6;m++) x[m]=rand()/(float)RAND_MAX;
    double d=fabs(eval64(init,x)-evaldc(init,x,6)); if(d>maxd) maxd=d; }
  { uint64_t h=1469598103934665603ull; for(size_t i=0;i<n;i++){ h=(h^ptA[i])*1099511628211ull; h=(h^lsA[i])*1099511628211ull;} printf("output checksum (plaintext+linguistic_score, two-phase ref): %016llx\n",(unsigned long long)h); }
  printf("melted LUT6, 200k random (INIT,x) in [0,1]: max |64-corner - deCasteljau| = %.3g\n",maxd);
  return 0;
}
