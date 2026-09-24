import { mkdirSync, copyFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { defineConfig, type Plugin } from 'vite'
import react from '@vitejs/plugin-react'

const siteRoot = dirname(fileURLToPath(import.meta.url))

function syncHorenbergCorpus(): Plugin {
  const toDir = resolve(siteRoot, 'public/horenberg')
  const files = ['u534_corpus.json', 'bgnc_wider_corpus.json', 'bgnc_register_clean.json']
  return {
    name: 'sync-horenberg-corpus',
    buildStart() {
      mkdirSync(toDir, { recursive: true })
      for (const name of files) {
        copyFileSync(resolve(siteRoot, '../Fixtures', name), resolve(toDir, name))
      }
    },
  }
}

// Custom domain: https://helut.org
export default defineConfig({
  plugins: [react(), syncHorenbergCorpus()],
  base: '/',
})
