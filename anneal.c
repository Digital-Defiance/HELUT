/* gcc -O2 -o anneal anneal.c -lm ; ./anneal RESTARTS STEPS MAXDECOYS file.bin
   Per control: score of the TRUE board at the true setting, cold-start annealing at the true setting
   (plugs recovered), and the best annealed board at each decoy setting (same budget). */
#include <stdio.h>
#include <stdlib.h>
#include <math.h>
#include <string.h>
typedef unsigned char u8;
static float tab[17576]; static u8 ct[72];
static double score(const u8 *perm, const u8 *S) {
  u8 p[72]; for (int i = 0; i < 72; i++) p[i] = S[perm[i*26 + S[ct[i]]]];
  double s = 0; for (int i = 2; i < 72; i++) s += tab[p[i-2]*676 + p[i-1]*26 + p[i]]; return s; }
static unsigned long long rng = 88172645463325252ULL;
static unsigned long long xr(void) { rng ^= rng << 13; rng ^= rng >> 7; rng ^= rng << 17; return rng; }
static double ur(void) { return (xr() >> 11) * (1.0 / 9007199254740992.0); }
static int npairs(const u8 *S) { int n = 0; for (int i = 0; i < 26; i++) if (S[i] > i) n++; return n; }
static double anneal(const u8 *perm, int R, int steps, u8 *best) {
  double g = -1e18; u8 S[26], T[26];
  for (int r = 0; r < R; r++) {
    for (int i = 0; i < 26; i++) S[i] = i;
    double cur = score(perm, S);
    for (int k = 0; k < steps; k++) {
      double t = 3.0 * pow(0.05 / 3.0, (double)k / steps);
      int x = xr() % 26, y = xr() % 26; if (x == y) continue; memcpy(T, S, 26);
      if (T[x] == y) { T[x] = x; T[y] = y; }
      else { int xp = T[x], yp = T[y]; T[xp] = xp; T[yp] = yp; T[x] = y; T[y] = x; if (npairs(T) > 10) continue; }
      double sc = score(perm, T);
      if (sc >= cur || ur() < exp((sc - cur) / t)) { memcpy(S, T, 26); cur = sc; if (cur > g) { g = cur; memcpy(best, S, 26); } }
    }
  }
  return g;
}
int main(int argc, char **argv) {
  int R = atoi(argv[1]), STEPS = atoi(argv[2]), MAXD = atoi(argv[3]); FILE *f = fopen(argv[4], "rb"); int n, c = 0;
  while (fread(&n, 4, 1, f) == 1) {
    u8 plug[26]; if (!fread(ct, 1, 72, f) || !fread(plug, 1, 26, f) || !fread(tab, 4, 17576, f)) break;
    u8 *P = malloc((size_t)n * 72 * 26); if (!fread(P, 1, (size_t)n * 72 * 26, f)) break;
    double truth = score(P, plug); u8 b[26]; double sat = anneal(P, R, STEPS, b); int ok = 0;
    for (int i = 0; i < 26; i++) if (plug[i] > i && b[i] == plug[i]) ok++;
    int m = n - 1 < MAXD ? n - 1 : MAXD; double mx = -1e18, s1 = 0, s2 = 0;
    for (int s = 1; s <= m; s++) { u8 bb[26]; double v = anneal(P + (size_t)s * 72 * 26, R, STEPS, bb); if (v > mx) mx = v; s1 += v; s2 += v * v; }
    double mean = s1 / m, sd = sqrt(s2 / m - mean * mean);
    printf("ctrl %2d true-board %7.1f | cold-start@true %7.1f (%2d/10 plugs) | decoys n=%d mean %7.1f sd %4.1f max %7.1f | z(true)=%5.1f\n",
           c++, truth, sat, ok, m, mean, sd, mx, (truth - mean) / sd);
    fflush(stdout); free(P);
  }
  return 0;
}
