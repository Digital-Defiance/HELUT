// Transliteration check of two pieces of helut_proposed_kernels.metal:
// (a) bit-sliced fold with constant-leaf first level vs plain mux tree, all widths 1..6
// (b) DFF next-state formulas (float multilinear and bitwise) vs Yosys semantics, exhaustive
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
typedef uint32_t u32; typedef uint64_t u64;
static u32 mux(u32 a,u32 b,u32 s){ return a^((a^b)&s); }
static u32 plain(u64 tt,int w,const u32*x){ u32 v[64]; int n=1<<w; for(int k=0;k<n;k++) v[k]=((tt>>k)&1)?~0u:0u;
  for(int m=0;m<w;m++){ n>>=1; for(int k=0;k<n;k++) v[k]=mux(v[2*k],v[2*k+1],x[m]); } return v[0]; }
static u32 kernel_fold(u64 tt,u32 w,const u32*x){ u32 v[32]; u32 x0=x[0]; u32 half=(1u<<w)>>1;
  for(u32 k=0;k<(half>1?half:1);k++){ u32 bits=(u32)((tt>>(2*k))&3); v[k]= bits==0?0u: bits==1?~x0: bits==2?x0:0xFFFFFFFFu; }
  u32 n=half; for(u32 m=1;m<w;m++){ u32 s=x[m]; n>>=1; for(u32 k=0;k<n;k++) v[k]=mux(v[2*k],v[2*k+1],s);} return v[0]; }
int main(void){ srand(5); long bad=0;
  for(int it=0;it<200000;it++){ int w=1+rand()%6; u64 tt=((u64)rand()<<33)^((u64)rand()<<11)^rand(); if(w<6) tt&=(1ull<<(1<<w))-1;
    u32 x[6]; for(int m=0;m<6;m++) x[m]=((u32)rand()<<1)^rand(); bad+= plain(tt,w,x)!=kernel_fold(tt,w,x); }
  printf("bit-sliced constant-leaf fold vs plain mux tree: %ld mismatches / 200000\n",bad);
  long bd=0;
  for(int gate=0;gate<2;gate++) for(int e=0;e<2;e++) for(int r=0;r<2;r++) for(int d=0;d<2;d++) for(int q=0;q<2;q++) for(int rv=0;rv<2;rv++){
    int yosys = gate ? (e ? (r ? rv : d) : q) : (r ? rv : (e ? d : q));
    float E=e,R=r,D=d,Q=q,RV=rv; float f = gate ? E*(R*RV+(1-R)*D)+(1-E)*Q : R*RV+(1-R)*(E*D+(1-E)*Q);
    u32 EN=e?~0u:0,RS=r?~0u:0,DD=d?~0u:0,QQ=q?~0u:0,RR=rv?~0u:0;
    u32 b = gate ? mux(QQ,mux(DD,RR,RS),EN) : mux(mux(QQ,DD,EN),RR,RS);
    bd += (f!=(float)yosys) + ((b&1)!=(u32)yosys); }
  printf("DFF next-state (float multilinear + bitwise) vs Yosys SDFF/SDFFE/SDFFCE semantics: %ld mismatches / 128\n",bd);
  return 0; }
