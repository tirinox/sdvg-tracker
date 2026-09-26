/// <reference types="vitest/config" />
import vue from '@vitejs/plugin-vue'
import { defineConfig } from 'vite'
import { VitePWA } from 'vite-plugin-pwa'

export default defineConfig({
  plugins: [
    vue(),
    // The app shell is precached so the tracker opens without the server; data lives in IndexedDB.
    VitePWA({
      registerType: 'autoUpdate',
      workbox: {
        globPatterns: ['**/*.{js,css,html,svg,png,woff2}'],
        navigateFallback: '/index.html',
        navigateFallbackDenylist: [/^\/api\//],
      },
      manifest: {
        name: 'СДВГ-трекер',
        short_name: 'Трекер',
        lang: 'ru',
        start_url: '/',
        display: 'standalone',
        background_color: '#f6f5fb',
        theme_color: '#6a5ae0',
        icons: [
          { src: '/icon-192.png', sizes: '192x192', type: 'image/png', purpose: 'any' },
          { src: '/icon-512.png', sizes: '512x512', type: 'image/png', purpose: 'any' },
        ],
      },
    }),
  ],
  server: {
    proxy: {
      '/api': process.env.API_PROXY_TARGET ?? 'http://localhost:8421',
    },
  },
  test: {
    environment: 'node',
    setupFiles: ['src/test/setup.ts'],
  },
})
