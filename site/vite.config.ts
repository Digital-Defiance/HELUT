import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Custom domain: https://helut.digitaldefiance.org
export default defineConfig({
  plugins: [react()],
  base: '/',
})
