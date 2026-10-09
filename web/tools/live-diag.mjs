import { chromium } from 'playwright'
const BASE = 'https://huami-message.huamidev.workers.dev'
const browser = await chromium.launch()
const page = await browser.newPage({ viewport: { width: 390, height: 844 } })

const logs = [], failed = [], bad = []
page.on('console', (m) => logs.push(`[${m.type()}] ${m.text().slice(0, 300)}`))
page.on('pageerror', (e) => logs.push(`[pageerror] ${String(e).slice(0, 300)}`))
page.on('requestfailed', (r) => failed.push(`${r.method()} ${r.url().slice(0, 120)} → ${r.failure()?.errorText}`))
page.on('response', (r) => { if (r.status() >= 400) bad.push(`${r.status()} ${r.url().slice(0, 120)}`) })

await page.goto(BASE, { waitUntil: 'networkidle' })
await page.waitForTimeout(1200)
await page.fill('input[type=email]', 'huamidev@gmail.com')
await page.fill('input[type=password]', '88888888')
await page.click('button[type=submit]')
console.log('  等 15 秒看它到底发生了什么…')
await page.waitForTimeout(15000)

const convCount = await page.locator('.conv').count()
const bodyText = (await page.locator('body').innerText()).slice(0, 400)
await page.screenshot({ path: '/tmp/shots/live-diag.png' })

console.log('\n  ── 会话条数:', convCount)
console.log('\n  ── 页面上的字（前 400）：')
console.log('    ' + bodyText.replace(/\n/g, ' | '))
console.log('\n  ── 失败的请求:')
console.log(failed.length ? failed.slice(0, 10).map((x) => '    ' + x).join('\n') : '    没有')
console.log('\n  ── 4xx/5xx 的响应:')
console.log(bad.length ? bad.slice(0, 10).map((x) => '    ' + x).join('\n') : '    没有')
console.log('\n  ── 控制台:')
console.log(logs.length ? logs.slice(0, 10).map((x) => '    ' + x).join('\n') : '    没有')

await browser.close()
