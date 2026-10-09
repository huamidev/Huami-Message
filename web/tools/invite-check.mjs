// 邀请链接的验证：https://你的网址/?add=huami
//
// 朋友点这个链接进来，登录之后应该**自动跳到「联系人」、
// 用户名已经填好、而且直接查到对方**。
//
// 【为什么单独写一个脚本】
//
// 主自检是从根地址进的（没有 ?add=），走不到这条路径。
// 而这条路径恰恰是"朋友第一次用"的那条 —— 它坏了的话，
// 我们自己完全感觉不到（我们都是从根地址进的）。

import { chromium } from 'playwright'

const BASE = process.env.BASE ?? 'http://127.0.0.1:5181'
const EMAIL = 'huamidev@gmail.com'
const PASSWORD = '88888888'
const OUT = '/tmp/shots'
const { mkdirSync } = await import('node:fs')
mkdirSync(OUT, { recursive: true })

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })

const problems = []
page.on('console', (m) => { if (m.type() === 'error') problems.push('console: ' + m.text().slice(0, 160)) })
page.on('pageerror', (e) => problems.push('pageerror: ' + String(e).slice(0, 160)))

// ① 从邀请链接进来
await page.goto(`${BASE}/?add=test002`, { waitUntil: 'networkidle' })
await page.waitForTimeout(1000)
await page.screenshot({ path: `${OUT}/invite-1-打开.png` })
console.log('① 打开邀请链接，看到登录页:',
            (await page.locator('text=用邮箱注册').count()) > 0 ? '✓' : '✗')

// ② 登录
await page.fill('input[type=email]', EMAIL)
await page.fill('input[type=password]', PASSWORD)
await page.click('button[type=submit]')
await page.waitForTimeout(7000)
await page.screenshot({ path: `${OUT}/invite-2-登录后.png` })

// ③ 应该自动在「联系人」页，而且已经查到对方
const onContacts = (await page.locator('text=加好友').count()) > 0
const inputValue = await page.locator('.card input').first().inputValue().catch(() => '')
const cardName = (await page.locator('.req .conv-name').first().innerText().catch(() => '')).trim()
const cardUser = (await page.locator('.req .muted.small').first().innerText().catch(() => '')).trim()

console.log('② 登录后自动跳到联系人:', onContacts ? '✓' : '✗')
console.log('③ 输入框自动填好:', inputValue, inputValue === 'test002' ? '✓' : '✗')
console.log('④ 自动查到了对方:', cardName, cardUser,
            (cardName && cardUser.includes('test002')) ? '✓' : '✗')

// ⑤ 地址栏里的 ?add= 应该被抹掉
const url = page.url()
console.log('⑤ 地址栏已清理:', url, url.includes('add=') ? '✗ 还留着' : '✓')

console.log('\n控制台错误:', problems.length ? problems.slice(0, 5) : '无 ✓')
await browser.close()
