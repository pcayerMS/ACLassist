import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Bundle everything (JS + CSS) into ONE self-contained index.html so the dashboard opens with just a
// browser — no server, no Node, no install. base './' keeps it relative.
export default defineConfig({
  base: './',
  plugins: [react(), viteSingleFile()],
  build: { outDir: 'dist', chunkSizeWarningLimit: 4000 },
});
