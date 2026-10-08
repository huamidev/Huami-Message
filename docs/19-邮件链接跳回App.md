# 邮件确认链接跳回 App

> 之前用户点完邮件里的「确认邮箱」，浏览器会打开 `huamidev.com` ——
> 而那个网页**不知道刚才发生了什么**，所以什么提示都没有：
> 「验证成功了吗？不知道，而且我还得自己切回 App。」
>
> 现在改成跳回 `huami://confirm`：iOS 直接**打开 Huami Message**，
> App 里告诉用户结果。不用做网页，也不用他自己找回来。

---

## 一、做了什么

```
点邮件里的链接
   ↓
Supabase 验证邮箱
   ↓
跳回 huami://confirm   ← 关键：不是网页，是 App 自己的"网址方案"
   ↓
iOS 打开 Huami Message
   ↓
App 里弹一条提示：「✅ 邮箱验证成功」
```

### 还能顺手帮用户登录

Supabase 会把**登录凭证**放在链接的 `#` 后面（OAuth 的 implicit flow）。
App 把它取出来就能**直接登录**，用户连密码都不用再输一遍。

> **为什么凭证放在 `#` 后面而不是 `?` 后面**：
> URL 的片段（fragment）**不会被浏览器发到服务器**，
> 也就不会进服务器日志和中间代理，减少凭证泄露的机会。
> 代价是 `URLComponents` 不帮我们解析它，得自己按 `&` 和 `=` 拆。

**取不到凭证也没关系** —— 邮箱其实已经在服务端验证成功了，
所以这时提示「现在可以用这个邮箱和密码登录了」，让他手动登一次就行。
**绝不能让他以为失败、又去重新注册一遍。**

---

## 二、要改三个地方，必须一致

`huami://confirm` 这个字符串出现在三处，改一处就要改三处：

| 在哪 | 是什么 |
|---|---|
| `Services/AppLink.swift` | 代码里的常量 |
| `Config/Info.plist` | 注册 `huami` 这个网址方案 |
| Supabase → URL Configuration → Redirect URLs | 白名单。**不加的话会被忽略**，又跳回网页 |

---

## 三、Info.plist 这件事有个坑

项目一直用的是「自动生成 Info.plist」（`GENERATE_INFOPLIST_FILE = YES`），
但 **URL 方案在 Info.plist 里是"数组里套字典"的结构，没法用编译设置表达**。

所以加了一个真实的 `Config/Info.plist`。

**但第一版放在 `Huami Message/` 里，构建直接失败**：

```
error: Multiple commands produce '.../Huami Message.app/Info.plist'
warning: The Copy Bundle Resources build phase contains this target's Info.plist file
```

原因：工程用的是**文件系统同步**（`PBXFileSystemSynchronizedRootGroup`），
放在那个目录里的文件会被自动加进"拷贝资源"，于是**两个任务抢着生成同一个文件**。

**修法：把它挪到同步目录之外**（`Config/Info.plist`）。

> 好消息：`GENERATE_INFOPLIST_FILE` 和 `INFOPLIST_FILE` 同时存在时，
> Xcode 会把自动生成的键**合并**进你提供的文件。
> 我验证过：注册上 `huami://` 之后，版本号、显示名、出口合规声明**一个都没丢**。

---

## 四、踩到的两个坑（都是"代码跑了但界面没反应"）

### 坑 1：同一个视图上挂多个"呈现型"修饰符会互相干扰

第一版用 `.alert` 显示提示。日志证明 `handleLink` **确实被调用了**，
但提示**根本没出现**。

原因：`RootView` 上已经挂了一个 `.fullScreenCover`（登录/条款的闸门）。
SwiftUI 里同一个视图上多个呈现型修饰符会打架。

**改成 `overlay`** —— 它不参与呈现机制，只是"画在上面"。

### 坑 2：`fullScreenCover` 是另一个层级，主界面上的东西画不到它上面

改成 overlay 之后还是看不见。因为 overlay 挂在 **TabView** 上，
而登录页是**盖在 TabView 上面的一个全屏覆盖** —— 层级不同，
主界面画什么都出现在它下面，被完全盖住。

**而用户点完确认链接之后，绝大多数情况正是停在登录页**
（他刚注册完，还没登录）。只画在主界面上等于没画。

**修法：在覆盖层的内容上也画一遍。**

> **教训**：这两次的表象都是"代码明明执行了，界面却什么都没有"。
> 遇到这种情况，**先别怀疑逻辑，先检查"画在哪一层"**。
> `print`／日志证明逻辑没问题的时候，问题几乎一定在视图层级上。

---

## 五、验证记录

| 验证项 | 结果 |
|---|---|
| `huami://` 是否注册成功 | ✅ `simctl openurl` 弹出了「Open in "Huami Message"?」 |
| 系统跳转后的处理逻辑 | ✅ 日志确认 `handleLink` 被调用、scheme 匹配 |
| 提示条是否真的显示 | ✅ 见截图（含"验证成功"文案和关闭按钮） |
| 手机号/凭证缺失时的降级 | ✅ 提示"现在可以用这个邮箱和密码登录了" |

> ⚠️ 真机上用户还会看到一个「Open in Huami Message?」的**系统确认框** ——
> 这是自定义网址方案的固有行为，多一次点击。
> 要免掉它得用 Universal Links，那需要**付费开发者账号**（Associated Domains 能力）。

---

*完成于 2026-10-08。*
