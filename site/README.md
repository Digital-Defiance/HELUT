# HELUT site

React + Vite site for [helut.org](https://helut.org).

```bash
cd site
npm install
npm run dev
npm run build
npm run preview
```

## Deploy

Push to `main` (paths under `site/`) or run **Deploy GitHub Pages**. Then in the repo:

1. **Settings → Pages → Source:** GitHub Actions  
2. **Settings → Pages → Custom domain:** `helut.org` (Enforce HTTPS once DNS propagates)

DNS at your registrar (Digital Defiance):

| Type | Name | Value |
|------|------|--------|
| `CNAME` | `helut` | `digital-defiance.github.io` |

`public/CNAME` is copied into the build so Pages keeps the domain on each deploy.

Campaign-journal source files recovered or authored by Selm Merel Wenselaers live in
`public/selm/` and are attached, with her credit, on the P1030680 journal. The U-534
Hörenberg scrape is published from `Fixtures/u534_corpus.json` to `public/horenberg/`
at build time and shown at `/enigma/corpus`.

## Enigma wing

HELUT (Home / Stack / Apps / Projects) is the FHE and cipher-lab site. The Enigma
historian section is a separate wing under `/enigma`:

| Path | What it is |
|------|------------|
| `/enigma` | Overview |
| `/enigma/p1030680` | The message (status, facts; victory page if BREAK FOUND) |
| `/enigma/corpus` | U-534 Hörenberg scrape (table + JSON download) |
| `/enigma/journal` | Campaign chronology |
| `/enigma/nazi-blaster-9000` | The search machine |
| `/enigma/mulein-board` | Tolerant/indel board |

Old `/projects/p1030680/journal` and `/journal` redirect into this wing.
