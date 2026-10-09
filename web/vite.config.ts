import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  // 相对路径：Cloudflare Pages 上放在子目录也能正常加载资源
  base: './',
  build: {
    outDir: 'dist',
    // ⚠️ **生产不要 sourcemap。**
    //
    // 它只在打开开发者工具时才下载，所以不影响用户打开速度 ——
    // 但它是 1.8 MB，而 JS 本身才 430 KB。白白占着部署体积，
    // 而且会把整份源码（含注释）一起发到服务器上。
    //
    // 真要在线上调试时，临时改成 true 重新构建一次就行。
    sourcemap: false,
  },
})
