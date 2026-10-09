import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './styles.css'

// 注册 Service Worker：让"添加到主屏幕"之后能像 App 一样打开。
//
// 只在正式构建里注册 —— 开发时注册会把 Vite 的热更新搞乱
//（缓存了旧的模块，改了代码看不到变化，很难查）。
if ('serviceWorker' in navigator && import.meta.env.PROD) {
  window.addEventListener('load', () => {
    navigator.serviceWorker.register('./sw.js').catch(() => {
      // 注册失败不影响使用 —— 只是少了离线能力，不该弹错误吓用户
    })
  })
}

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
