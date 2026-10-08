import SwiftUI

/// 登录 / 注册页。
///
/// 【为什么注册和登录放在同一页，用切换而不是两个页面】
///
/// 因为它们是同一个动作的两种状态，字段几乎一样。
/// 分成两个页面，用户点错了还得返回；切换一下只要一次点击。
/// 而且新用户第一次进来时，"注册"这个选项**就在眼前**，不用去找。
///
/// 【关于用邮箱注册的决定】
/// 手机号登录在国内要企业资质报备（阿里云已不再接受个人申请），
/// "通过 Apple 登录"需要付费开发者账号。
/// 邮箱注册是唯一一条**不需要任何资质、现在就能做完**的路。
struct AuthGateView: View {

    enum Mode: String, CaseIterable {
        case signIn, signUp
        var title: String { self == .signIn ? "登录" : "注册" }
    }

    @Environment(AuthStore.self) private var auth

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var showPassword = false
    @State private var showResetHint = false

    /// 服务器自检发现的问题。空数组表示一切正常 —— 界面什么都不显示。
    @State private var serverIssues: [ServerIssue] = []

    @FocusState private var focus: Field?
    private enum Field { case email, password, confirm }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespaces).isEmpty
        && !password.isEmpty
        && !auth.isWorking
    }

    var body: some View {
        ZStack {
            AppBackground()

            ScrollView {
                VStack(spacing: 20) {
                    header
                    if !serverIssues.isEmpty { setupCard }
                    modePicker
                    fields
                    if let message = auth.errorMessage { errorBanner(message) }
                    submitButton
                    footerLinks
                }
                .padding(22)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        // 进登录页时检查一次服务器配置。
        // 这一步**不阻塞任何操作** —— 用户照样可以试着注册，
        // 只是如果注定失败，旁边会告诉他为什么。
        .task {
            serverIssues = await AppServices.runServerDiagnostics()
        }
        .alert("找回密码", isPresented: $showResetHint) {
            Button("知道了") {}
        } message: {
            Text("第一版还没接邮件服务，暂时发不了重置链接。\n\n如果你忘了密码，可以换一个邮箱重新注册。接上邮件服务之后这里就能用了。")
        }
    }

    // MARK: - 顶部

    private var header: some View {
        VStack(spacing: 12) {
            MascotAvatar(size: 64)

            Text(mode == .signIn ? "欢迎回来" : "创建账号")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            Text("用邮箱注册，不需要手机号")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.top, 10)
    }

    // MARK: - 服务器还没配好

    /// 把"服务器缺什么"直接摆在登录页上。
    ///
    /// 【为什么值得专门做这一块】
    ///
    /// 漏掉配置的后果是**很难懂**的：注册完登不进去、好友列表永远是空的。
    /// 报错通常是 "PGRST205" 或者干脆什么都不说。
    /// 而这个项目里"开发者"和"用户"是同一个人 ——
    /// 与其让他去翻文档，不如让 App 自己说清楚要去点哪里。
    ///
    /// 配置正确的服务器上这个卡片不会出现，所以它**会自己消失**。
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 7) {
                Image(systemName: "wrench.and.screwdriver.fill")
                    .font(.system(size: 12))
                Text("服务器还有 \(serverIssues.count) 项没配置好")
                    .font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 0)
            }
            .foregroundStyle(Theme.warning)

            ForEach(serverIssues) { issue in
                VStack(alignment: .leading, spacing: 7) {
                    Text(issue.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    Text(issue.detail)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(issue.steps.enumerated()), id: \.offset) { index, step in
                            HStack(alignment: .top, spacing: 6) {
                                Text("\(index + 1).")
                                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                                    .foregroundStyle(Theme.accent)
                                Text(step)
                                    .font(.system(size: 12))
                                    .foregroundStyle(Theme.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.surfaceAlt,
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.warning.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.warning.opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - 登录 / 注册 切换

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(Mode.allCases, id: \.self) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: mode) { _, _ in
            // 切模式时把错误清掉 —— 用户已经换动作了，
            // 上一条错误提示留在那里只会让人困惑
            auth.errorMessage = nil
            confirmPassword = ""
        }
    }

    // MARK: - 输入框

    private var fields: some View {
        VStack(spacing: 0) {
            fieldRow(icon: "envelope.fill") {
                TextField("邮箱", text: $email)
                    .keyboardType(.emailAddress)
                    .textContentType(.emailAddress)
                    .textInputAutocapitalization(.never)   // 邮箱不会有大写开头的道理
                    .autocorrectionDisabled()
                    .focused($focus, equals: .email)
                    .submitLabel(.next)
                    .onSubmit { focus = .password }
            }

            HairLine()

            fieldRow(icon: "lock.fill") {
                HStack(spacing: 8) {
                    passwordField
                    // 显示/隐藏密码。
                    // 手机上打密码很容易错，看不见的话只能重打一遍。
                    Button {
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye.slash.fill" : "eye.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    .buttonStyle(.plain)
                }
            }

            if mode == .signUp {
                HairLine()
                fieldRow(icon: "lock.rotation") {
                    SecureField("再输一遍密码", text: $confirmPassword)
                        .textContentType(.newPassword)
                        .focused($focus, equals: .confirm)
                        .submitLabel(.done)
                        .onSubmit(submit)
                }
            }
        }
        .card(radius: 16)
        .overlay(alignment: .topLeading) {
            // 密码规则只在需要时出现，别一上来就压一堆要求给用户
            if mode == .signUp && !password.isEmpty && !AuthRules.isValidPassword(password) {
                Text("密码至少 \(AuthRules.minimumPasswordLength) 位")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
                    .padding(.leading, 46)
                    .offset(y: 92)
            }
        }
    }

    @ViewBuilder
    private var passwordField: some View {
        if showPassword {
            TextField("密码", text: $password)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focus, equals: .password)
                .submitLabel(mode == .signIn ? .go : .next)
                .onSubmit { mode == .signIn ? submit() : (focus = .confirm) }
        } else {
            SecureField("密码", text: $password)
                .textContentType(mode == .signIn ? .password : .newPassword)
                .focused($focus, equals: .password)
                .submitLabel(mode == .signIn ? .go : .next)
                .onSubmit { mode == .signIn ? submit() : (focus = .confirm) }
        }
    }

    private func fieldRow<Content: View>(icon: String,
                                         @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.textTertiary)
                .frame(width: 20)
            content()
                .font(.system(size: 16))
                .foregroundStyle(Theme.textPrimary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 14)
    }

    // MARK: - 错误提示

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.system(size: 13))
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.danger)
        .padding(12)
        .background(Theme.danger.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 主按钮

    private var submitButton: some View {
        Button(action: submit) {
            HStack(spacing: 8) {
                if auth.isWorking {
                    ProgressView().tint(.white).controlSize(.small)
                }
                Text(auth.isWorking ? "请稍等…" : mode.title)
                    .font(.system(size: 16, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                canSubmit ? AnyShapeStyle(Theme.myBubbleGradient)
                          : AnyShapeStyle(Theme.separator),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .animation(.snappy(duration: 0.2), value: canSubmit)
    }

    // MARK: - 底部链接

    private var footerLinks: some View {
        HStack(spacing: 18) {
            Button {
                mode = (mode == .signIn ? .signUp : .signIn)
            } label: {
                Text(mode == .signIn ? "还没有账号？注册" : "已经有账号？登录")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
            }
            .buttonStyle(.plain)

            if mode == .signIn {
                Button {
                    showResetHint = true
                } label: {
                    Text("忘记密码")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 4)
    }

    // MARK: - 动作

    private func submit() {
        focus = nil
        Haptics.tap()
        Task {
            switch mode {
            case .signIn:
                await auth.signIn(email: email, password: password)
            case .signUp:
                await auth.signUp(email: email, password: password, confirmPassword: confirmPassword)
            }
        }
    }
}
