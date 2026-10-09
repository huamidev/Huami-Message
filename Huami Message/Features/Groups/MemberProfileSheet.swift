import SwiftUI

/// 群里某个人的资料。
///
/// 【为什么只需要这些】
///
/// 从群聊里点开一个人的头像，想知道的其实就三件事：
/// **他是谁、长什么样、我能不能加他。**
///
/// 前两个这里有了。第三个（加好友）要按用户名去查 —— 而群成员的资料里
/// 暂时没带 username（那是另一个查询）。所以先老实地不放按钮，
/// 而不是放一个点了会失败的按钮。
struct MemberProfileSheet: View {

    let member: GroupMember

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Avatar(initial: member.initial,
                       seed: member.avatarSeed,
                       size: 84,
                       url: member.avatarURL)

                Text(member.name)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                Text("在这个群里")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.textTertiary)

                Spacer()
            }
            .padding(.top, 36)
            .frame(maxWidth: .infinity)
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }
}
