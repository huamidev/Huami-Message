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
  //
  // ⚠️ **默认不跑。**
  //
  // 这个自检用的是真实账号、真实会话 —— 发出去的消息会**留在用户的
  // 聊天记录里**，而且删不掉（消息表没有删除权限，那是当初为了
  // 不让任何一方单方面抹掉记录而定的）。
  //
  // 我第一次跑的时候往用户的真实对话里塞了六条"浏览器自检 13:29:37"，
  // 清不掉。所以现在要显式加 --send 才跑这一步。
  //
  // 要跑就：node tools/browser-check.mjs --send
  const allowSend = process.argv.includes('--send')
  const text = '浏览器自检 ' + new Date().toLocaleTimeString('zh-CN')
  if (!allowSend) {
    console.log('④ 发送测试：跳过（要跑加 --send，注意消息会留在聊天记录里）')
  } else {
  await page.fill('.composer input[type=text], .composer input:not([type])', text)
  await page.waitForTimeout(300)
  await page.click('.composer button[type=submit]')
  await page.waitForTimeout(3500)
  await shot('5-发送后')
  const sent = await page.locator(`text=${text}`).count()
    console.log('④ 发出去的消息出现在页面上:', sent > 0 ? '✓' : '✗')
  }
}

// ④a 撤回刚发的那条（长按 = contextmenu）
const lastMine = page.locator('.bubble.mine').last()
if (await lastMine.count()) {
  await lastMine.click({ button: 'right' })
  await page.waitForTimeout(1000)
  await shot('4b-长按菜单')
  const recallBtn = page.locator('.sheet button:has-text("撤回")')
  if (await recallBtn.count()) {
    await recallBtn.click()
    await page.waitForTimeout(2500)
    await shot('4c-撤回后')
    const recalled = await page.locator('.recalled').count()
    console.log('④a 撤回：菜单有「撤回」✓，撤回后页面出现', recalled, '条撤回提示',
                recalled > 0 ? '✓' : '✗（撤回没生效）')
  } else {
    console.log('④a 撤回：✗ 菜单里没有「撤回」按钮')
  }
}

// ④b 群资料页（群里左上角那个 ⋯）
// ⚠️ **先回列表再找群** —— 上面第④步之后还停在聊天页里，
//    那时候页面上根本没有 .conv 元素，找不到群不是"没有群"，
//    是"看错地方了"。第一次写这段就栽在这儿。
await page.locator('.chat-topbar .icon-btn').first().click()
await page.waitForTimeout(1200)

const groupRow = page.locator('.conv').filter({ hasText: /群|、/ }).first()
if (await groupRow.count()) {
  await groupRow.click()
  await page.waitForTimeout(2000)
  const dots = page.locator('.chat-topbar .icon-btn').last()
  if (await dots.count()) {
    await dots.click()
    await page.waitForTimeout(2000)
    await shot('5b-群资料')
    const members = await page.locator('.req .conv-name').count()
    const ownerTag = await page.locator('.owner-tag').count()
    const canLeave = await page.locator('text=退出群聊').count()
    const isOwnerHint = await page.locator('text=你是群主').count()
    console.log('④b 群资料页：成员', members, '| 群主标记', ownerTag,
                '| 退群按钮', canLeave ? '有' : '无',
                '| 群主提示', isOwnerHint ? '有' : '无')
    await page.locator('.topbar .icon-btn').first().click()
    await page.waitForTimeout(600)
  } else {
    console.log('④b 群资料入口 ✗ 没找到 ⋯ 按钮')
  }
  await page.locator('.topbar .icon-btn').first().click()
  await page.waitForTimeout(600)
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
