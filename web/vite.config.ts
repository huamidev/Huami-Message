import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // 相对路径：Cloudflare Pages 上放在子目录也能正常加载资源
  base: './',
  build: { outDir: 'dist', sourcemap: true },
})
