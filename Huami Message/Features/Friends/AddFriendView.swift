import SwiftUI
import CoreImage.CIFilterBuiltins

/// 加好友。
///
/// 【为什么用用户名，而不是读通讯录】
///
/// 读通讯录要弹权限，用户看到「这个 App 想访问你的通讯录」很容易直接卸载；
/// 而且那等于把用户的关系网整个上传 —— 是个很重的隐私承诺。
///
/// 用户名反过来：**由用户决定给谁**。谁都可以加你，所以想不被找到就别把名字说出去。
///
/// 这一页同时管两件事：把我的码给别人、把别人的码输进来。
/// 放在一页是因为它们本来就是同一个动作的两面。
struct AddFriendView: View {

    @Environment(AuthStore.self) private var auth
    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var inputCode = ""
    @State private var isAdding = false
    @State private var errorMessage: String?
    @State private var addedName: String?
    @State private var copied = false

    @FocusState private var inputFocused: Bool

    private var myUsername: String { auth.account?.username ?? "" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    myUsernameCard
                    addCard
                }
                .padding(16)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    // MARK: - 我的用户名

    private var myUsernameCard: some View {
        VStack(spacing: 14) {
            HStack {
                Text("我的用户名")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            QRCodeView(text: myUsername)
                .padding(.top, 2)
                .onTapGesture {
                    copyCode()
                }

            // 等宽字体：用户名是要一个字符一个字符核对的，
            // 用比例字体的话 8 和 B、0 和 O 看起来太像
            Text("@" + myUsername)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.textPrimary)
                .onTapGesture { copyCode() }

            if copied {
                Text("已复制")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.mint)
                    .transition(.opacity)
            } else {
                Text("让对方扫这个码，或者把这 8 位输进他的 App")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
            }

            HStack(spacing: 10) {
                Button {
                    copyCode()
                } label: {
                    Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)

                ShareLink(item: shareText) {
                    Label("分享", systemImage: "square.and.arrow.up")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .card()
    }

    private var shareText: String {
        "我在用 Huami Message 聊天，加我：@\(myUsername)"
    }

    private func copyCode() {
        UIPasteboard.general.string = myUsername
        Haptics.success()
        withAnimation(.snappy(duration: 0.2)) { copied = true }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.snappy(duration: 0.2)) { copied = false }
        }
    }

    // MARK: - 加别人

    private var addCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("加好友")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("输入对方的用户名")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 8) {
                TextField("对方的用户名", text: $inputCode)
                    .font(.system(size: 17, weight: .medium, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($inputFocused)
                    .submitLabel(.go)
                    .onSubmit { add() }
                    .onChange(of: inputCode) { _, newValue in
                        // ⚠️ 这里原来写死成「强制大写 + 最多 8 位」——
                        // 那是**邀请码**的规矩（8 位大写字母数字）。
                        // 改成用户名之后没跟着改，结果是：
                        // **5 位的用户名连输都输不进去**（一输就被截断/被按钮挡住）。
                        // 现在统一走 Username 那一套：小写、字母数字、5-15 位。
                        let cleaned = Username.normalize(newValue)
                        if cleaned != newValue { inputCode = cleaned }
                    }

                Button(action: add) {
                    if isAdding {
                        ProgressView().tint(.white).controlSize(.small)
                    } else {
                        Text("添加")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .frame(width: 66, height: 38)
                .background(
                    canAdd ? AnyShapeStyle(Theme.myBubbleGradient) : AnyShapeStyle(Theme.separator),
                    in: Capsule()
                )
                .buttonStyle(.plain)
                .disabled(!canAdd)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.surfaceAlt,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))

            if let addedName {
                feedbackRow("已添加 \(addedName)", icon: "checkmark.circle.fill", color: Theme.mint)
            } else if let errorMessage {
                feedbackRow(errorMessage, icon: "exclamationmark.circle.fill", color: Theme.danger)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private var canAdd: Bool { Username.isValid(inputCode) && !isAdding }

    private func feedbackRow(_ text: String, icon: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
            Text(text)
                .font(.system(size: 12.5))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .transition(.opacity)
    }

    private func add() {
        guard canAdd else { return }
        inputFocused = false
        Haptics.tap()

        withAnimation(.snappy(duration: 0.2)) {
            isAdding = true
            errorMessage = nil
            addedName = nil
        }

        Task {
            do {
                try await store.addFriend(username: inputCode)
                // 加成功之后立刻能看出加的是谁 —— 只显示"成功"两个字的提示是没有用的
                let name = store.conversations.first { $0.friend.id == friendIDForInput }?.friend.name
                withAnimation(.snappy(duration: 0.25)) {
                    isAdding = false
                    addedName = name ?? "好友"
                    inputCode = ""
                }
                Haptics.success()
            } catch {
                withAnimation(.snappy(duration: 0.25)) {
                    isAdding = false
                    errorMessage = (error as? ChatError)?.errorDescription
                        ?? "加好友失败，等一下再试。"
                }
                Haptics.warning()
            }
        }
    }

    /// 加完之后从会话列表里找出刚加的那个人（用来显示名字）
    private var friendIDForInput: Friend.ID {
        // 用和假实现同一套派生规则把码翻回 id。
        // 接上真服务器之后，`addFriend` 会直接返回 Friend，这里就不用猜了。
        var bytes = Array(inputCode.utf8)
        while bytes.count < 16 { bytes.append(0x30) }
        let b = Array(bytes.prefix(16))
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                           b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}

// MARK: - 二维码

/// 把一段文字画成二维码。
///
/// 几个容易踩的点：
///   · **必须 `interpolation(.none)`** —— 平滑缩放会让格子糊掉，扫不出来
///   · **必须留白边**（quiet zone）。二维码规范要求四周有空白，
///     贴着别的元素会扫不出。这里的 `.padding(10)` 就是干这个的
struct QRCodeView: View {

    let text: String
    var size: CGFloat = 128

    var body: some View {
        Group {
            if let image = Self.makeImage(text) {
                Image(uiImage: image)
                    .interpolation(.none)
                    .resizable()
                    .scaledToFit()
                    .frame(width: size, height: size)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surfaceAlt)
                    .frame(width: size, height: size)
            }
        }
    }

    private static func makeImage(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        // 中等纠错：够应付屏幕反光和轻微遮挡，又不会让格子密到扫不动
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        // 原始输出只有几十像素，放大 12 倍再交给系统做无插值渲染
        let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))

        let context = CIContext()
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}
