import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// The UI is served to the shell webview from the host's `wake://` protocol, so
// every asset path is relative.
export default defineConfig({
  base: './',
  plugins: [react()],
  build: { outDir: 'dist', emptyOutDir: true, target: 'es2022', chunkSizeWarningLimit: 2000 },
});
