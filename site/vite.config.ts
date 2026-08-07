import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Custom domain: https://helut.org
export default defineConfig({
  plugins: [react()],
  base: '/',
})
