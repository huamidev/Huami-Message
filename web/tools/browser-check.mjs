import { chromium } from 'playwright'

const BASE = 'http://127.0.0.1:5181'
const EMAIL = 'huamidev@gmail.com'
const PASSWORD = '88888888'
const OUT = '/tmp/shots'
const { mkdirSync } = await import('node:fs')
mkdirSync(OUT, { recursive: true })

const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })

const problems = []
page.on('console', (m) => { if (m.type() === 'error') problems.push('console: ' + m.text().slice(0, 200)) })
page.on('pageerror', (e) => problems.push('pageerror: ' + String(e).slice(0, 200)))

async function shot(name) { await page.screenshot({ path: `${OUT}/${name}.png` }) }

// ① 打开
await page.goto(BASE, { waitUntil: 'networkidle' })
await page.waitForTimeout(800)
await shot('1-打开')
console.log('① 页面标题:', await page.title())
console.log('   看到登录页:', await page.locator('text=Huami Message').count() > 0 ? '是' : '否')

// ② 登录
await page.fill('input[type=email]', EMAIL)
await page.fill('input[type=password]', PASSWORD)
await shot('2-填好登录')
await page.click('button[type=submit]')
await page.waitForTimeout(6000)
await shot('3-登录后')

const hasList = await page.locator('.conv').count()
console.log('② 登录后会话条数:', hasList)
if (hasList > 0) {
  const names = await page.locator('.conv-name').allInnerTexts()
  const previews = await page.locator('.conv-preview').allInnerTexts()
  console.log('   会话:', names.map((n, i) => `${n}(${previews[i] ?? ''})`).join(' / '))
}

// ③ 进第一个会话
if (hasList > 0) {
  await page.locator('.conv').first().click()
  await page.waitForTimeout(2500)
  await shot('4-聊天页')
  const bubbles = await page.locator('.bubble').count()
  const mine = await page.locator('.bubble.mine').count()
  const theirs = await page.locator('.bubble.theirs').count()
  const avatars = await page.locator('.row.theirs .avatar').count()
  console.log('③ 聊天页气泡:', bubbles, `（我的 ${mine} / 对方 ${theirs}）`)
  console.log('   对方每条的左侧头像数:', avatars, avatars === theirs ? '✓ 每条都有' : '✗ 数量对不上')

  // ④ 发一条
  const text = '浏览器自检 ' + new Date().toLocaleTimeString('zh-CN')
  await page.fill('.composer input[type=text], .composer input:not([type])', text)
  await page.waitForTimeout(300)
  await page.click('.composer button[type=submit]')
  await page.waitForTimeout(3500)
  await shot('5-发送后')
  const sent = await page.locator(`text=${text}`).count()
  console.log('④ 发出去的消息出现在页面上:', sent > 0 ? '✓' : '✗')
}

// ⑤ 联系人页
await page.click('.tab:has-text("联系人")')
await page.waitForTimeout(2000)
await shot('6-联系人')
console.log('⑤ 联系人页有「加好友」:', await page.locator('text=加好友').count() > 0 ? '✓' : '✗')

// ⑥ 我的页
await page.click('.tab:has-text("我")')
await page.waitForTimeout(1200)
await shot('7-我')
console.log('⑥ 「我」页显示邮箱:', (await page.locator(`text=${EMAIL}`).count()) > 0 ? '✓' : '✗')

// ⑦ Service Worker 注册了吗
const sw = await page.evaluate(() => navigator.serviceWorker.getRegistrations().then((r) => r.length))
console.log('⑦ Service Worker 注册数:', sw, sw > 0 ? '✓' : '✗（PWA 离线能力没有生效）')

console.log('\n控制台错误:', problems.length ? problems.slice(0, 6) : '无 ✓')
await browser.close()
