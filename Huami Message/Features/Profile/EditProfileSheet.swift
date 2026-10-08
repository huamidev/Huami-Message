import SwiftUI

/// 编辑资料。
///
/// 只有三样能改：头像底色、昵称、简介。
///
/// 【为什么头像只让改底色，不让上传图片】
///
/// 上传头像意味着要开存储、要处理裁剪和压缩、要防不良图片——
/// 那是一个独立的功能，不该塞进"改个名字"这件事里。
/// 底色 + 名字首字，在好友列表里已经足够区分了。
struct EditProfileSheet: View {

    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var bio: String
    @State private var avatarSeed: Int
    @State private var isSaving = false

    /// 用户名。边打字边过滤，不合法的字符**根本打不进去** ——
    /// 比"输完了再报错"友好得多。
    @State private var username: String

    /// 改用户名的结果（成功 / 被占用 / 格式问题）
    @State private var usernameNote: String?
    @State private var usernameOK = false

    private static let bioLimit = 70

    init(account: Account) {
        _name = State(initialValue: account.displayName)
        _bio = State(initialValue: account.bio)
        _avatarSeed = State(initialValue: account.avatarSeed)
        _username = State(initialValue: account.username)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    avatarPicker
                    fields
                    usernameField
                    if let message = auth.errorMessage { errorBanner(message) }
                }
                .padding(18)
                .padding(.bottom, 30)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
            .background(AppBackground())
            .navigationTitle("编辑资料")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }.foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("保存") { save() }
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(canSave ? Theme.accent : Theme.textTertiary)
                        .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - 头像底色

    private var avatarPicker: some View {
        VStack(spacing: 12) {
            Avatar(initial: String(name.prefix(1)).uppercased(),
                   seed: avatarSeed, size: 84)

            Text("选一个底色")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)

            HStack(spacing: 10) {
                ForEach(0..<6, id: \.self) { seed in
                    Button {
                        Haptics.selection()
                        withAnimation(.snappy(duration: 0.2)) { avatarSeed = seed }
                    } label: {
                        Circle()
                            .fill(LinearGradient(colors: Avatar.palette(seed),
                                                 startPoint: .topLeading,
                                                 endPoint: .bottomTrailing))
                            .frame(width: 30, height: 30)
                            .overlay(
                                Circle()
                                    .strokeBorder(Theme.textPrimary,
                                                  lineWidth: seed == avatarSeed ? 2 : 0)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
        .card()
    }

    // MARK: - 昵称和简介

    private var fields: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("昵称")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 40, alignment: .leading)
                TextField("你的名字", text: $name)
                    .font(.system(size: 16))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)

            HairLine()

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("简介")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Text("\(bio.count)/\(Self.bioLimit)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(bio.count > Self.bioLimit ? Theme.danger : Theme.textTertiary)
                }

                TextField("一句话介绍自己（好友能看到）", text: $bio, axis: .vertical)
                    .font(.system(size: 15))
                    .lineLimit(2...4)
                    .onChange(of: bio) { _, newValue in
                        // 在输入的时候就截断，比保存之后报错友好
                        if newValue.count > Self.bioLimit {
                            bio = String(newValue.prefix(Self.bioLimit))
                        }
                    }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .card(radius: 16)
    }

    /// 用户名。
    ///
    /// 【为什么它单独一张卡片，不并进"昵称/简介"那一块】
    ///
    /// 因为它是**别人的入口** —— 别人靠这个名字找到你。
    /// 昵称和简介只是"看上去像谁"，用户名是"怎么找到你"。
    /// 混在一起，用户会以为它和昵称一样随便改改没关系。
    private var usernameField: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 2) {
                Text("@")
                    .font(.system(size: 16, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.textTertiary)

                TextField("用户名", text: $username)
                    .font(.system(size: 16, design: .monospaced))
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: username) { _, newValue in
                        // 不合法的一律打不进去，顺手转小写
                        let cleaned = Username.normalize(newValue)
                        if cleaned != newValue { username = cleaned }
                        usernameNote = nil
                    }
            }

            Text("别人用这个名字加你。只能用**英文字母和数字**，字母开头，\(Username.minLength)–\(Username.maxLength) 位。")
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)

            if let note = usernameNote {
                Text(note)
                    .font(.system(size: 12))
                    .foregroundStyle(usernameOK ? Theme.mint : Theme.danger)
            }

            if username != (auth.account?.username ?? "") {
                Button {
                    saveUsername()
                } label: {
                    Text(isSaving ? "保存中…" : "保存用户名")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(
                            Username.isValid(username) ? Theme.accent : Theme.textTertiary,
                            in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!Username.isValid(username) || isSaving)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .card()
    }

    private func saveUsername() {
        guard Username.isValid(username) else { return }
        isSaving = true
        Task {
            let ok = await auth.updateUsername(username)
            isSaving = false
            usernameOK = ok
            if ok {
                usernameNote = "改好了。旧名字已经释放，别人可以拿去用。"
            } else {
                // 失败原因原样显示 —— 后端已经把这些话说成人话了
                usernameNote = auth.errorMessage
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 13))
            Text(message)
                .font(.system(size: 13))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(Theme.danger)
        .padding(12)
        .background(Theme.danger.opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 保存

    private func save() {
        guard canSave else { return }
        isSaving = true
        Task {
            let ok = await auth.updateProfile(
                displayName: name.trimmingCharacters(in: .whitespaces),
                bio: bio.trimmingCharacters(in: .whitespacesAndNewlines),
                avatarSeed: avatarSeed
            )
            isSaving = false
            if ok { dismiss() }
        }
    }
}
