import SwiftUI

/// 「新的朋友」—— 收到的好友申请。
///
/// 【为什么单独一页，而不是混在联系人列表里】
///
/// 因为它是**待办**，不是联系人。混在一起会让"联系人"这个列表
/// 一会儿长一会儿短，而且用户根本不知道该不该处理。
/// 单独一页 + 一个数字红点，"有几件事等我做"一眼就清楚。
struct FriendRequestsView: View {

    @Environment(ChatStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var working: FriendRequest.ID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            AppPage {
                ScrollView {
                    VStack(spacing: 10) {
                        if store.incomingRequests.isEmpty {
                            emptyHint
                        } else {
                            ForEach(store.incomingRequests) { request in
                                card(request)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.refreshRequests() }
            }
            .navigationTitle("新的朋友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                        .font(.system(size: 16, weight: .medium))
                }
            }
            .task { await store.refreshRequests() }
            .alert("操作没成功", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("好") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
    }

    private func card(_ request: FriendRequest) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 11) {
                Avatar(initial: String(request.fromName.prefix(1)).uppercased(),
                       seed: 0,
                       size: 42,
                       url: request.fromAvatarURL)

                VStack(alignment: .leading, spacing: 2) {
                    Text(request.fromName)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    if !request.fromUsername.isEmpty {
                        Text("@" + request.fromUsername)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.textTertiary)
                    }
                }

                Spacer(minLength: 0)

                Text(request.createdAt, format: .dateTime.month().day())
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textTertiary)
            }

            // 附言。没写就不占地方（空着一行反而让人以为没加载出来）
            if let note = request.note, !note.isEmpty {
                Text(note)
                    .font(.system(size: 13.5))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.surfaceAlt,
                                in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            }

            HStack(spacing: 9) {
                Button {
                    respond(request, accept: false)
                } label: {
                    Text("拒绝")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.surfaceAlt,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    respond(request, accept: true)
                } label: {
                    Text(working == request.id ? "处理中…" : "同意")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent,
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            .disabled(working != nil)
            .opacity(working == nil ? 1 : 0.6)
        }
        .padding(14)
        .card()
    }

    private var emptyHint: some View {
        VStack(spacing: 9) {
            Image(systemName: "person.badge.clock")
                .font(.system(size: 30))
                .foregroundStyle(Theme.textTertiary)
            Text("没有待处理的申请")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.textSecondary)
            Text("别人用你的用户名加你时，会出现在这里。\n下拉可以刷新。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 30)
        .padding(.top, 60)
    }

    private func respond(_ request: FriendRequest, accept: Bool) {
        working = request.id
        Task {
            do {
                try await store.respond(to: request, accept: accept)
            } catch {
                // 失败要说出来，而且**别把它从列表里移走** ——
                // 否则用户以为处理过了，其实服务器上还是待处理。
                errorMessage = (error as? LocalizedError)?.errorDescription
                    ?? "没处理成功，等一下再试。"
            }
            working = nil
        }
    }
}
