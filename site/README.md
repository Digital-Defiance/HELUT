# HELUT site

React + Vite site for [helut.digitaldefiance.org](https://helut.digitaldefiance.org).

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
2. **Settings → Pages → Custom domain:** `helut.digitaldefiance.org` (Enforce HTTPS once DNS propagates)

DNS at your registrar (Digital Defiance):

| Type | Name | Value |
|------|------|--------|
| `CNAME` | `helut` | `digital-defiance.github.io` |

`public/CNAME` is copied into the build so Pages keeps the domain on each deploy.
