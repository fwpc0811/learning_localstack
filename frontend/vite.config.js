import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [react()],
  server: {
    watch: {
      usePolling: true, // Docker環境での変更検知を確実にする設定
    },
    host: true, // Dockerからアクセス可能にする
    port: 3000
  }
})