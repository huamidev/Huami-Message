import SwiftUI
import UIKit

/// 输入框上方展开的工具栏。
///
/// 【为什么做成「一排药丸」】
///
/// 对比过两种：一个九宫格大面板（微信那种），和一排小药丸（参考图那种）。
/// 选药丸的理由是**数量少**：我们只有四五个动作，
/// 用不着一个占掉半屏的九宫格 —— 那会把人从对话里推出去。
///
/// 一排药丸既够点，又不会让消息列表被挤走。
struct ChatToolbar: View {

    /// 输入框里现在有没有字 —— 决定「复制」「AI 改写」能不能点
    var hasText: Bool

    var onCopy: () -> Void
    var onPaste: () -> Void
    var onPhoto: () -> Void
    var onPolish: () -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 9) {
                pill("复制", "doc.on.doc", enabled: hasText, action: onCopy)
                pill("粘贴", "doc.on.clipboard", enabled: Clipboard.hasText, action: onPaste)
                pill("照片", "photo", enabled: true, action: onPhoto)
                pill("AI 改写", "sparkles", enabled: hasText, action: onPolish)
            }
            .padding(.horizontal, 12)
        }
        .scrollIndicators(.hidden)
        .padding(.bottom, 8)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func pill(_ title: String,
                      _ icon: String,
                      enabled: Bool,
                      action: @escaping () -> Void) -> some View {
        Button {
            Haptics.tap()
            action()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                Text(title)
                    .font(.system(size: 14))
            }
            .foregroundStyle(enabled ? Theme.textPrimary : Theme.textTertiary)
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(Theme.surface, in: Capsule())
            .overlay { Capsule().strokeBorder(Theme.separator, lineWidth: 0.6) }
            .shadow(color: .black.opacity(0.05), radius: 4, y: 1)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }
}

/// 剪贴板。
///
/// 单独包一层是为了把 UIKit 的细节关在一个地方 ——
/// 而且读剪贴板在 iOS 上会弹一个「xxx 粘贴自…」的系统提示，
/// 所以**只在用户真的点「粘贴」时才读**，不要在别处偷偷读。
enum Clipboard {

    static var hasText: Bool {
        UIPasteboard.general.hasStrings
    }

    static func read() -> String? {
        UIPasteboard.general.string
    }

    static func write(_ text: String) {
        UIPasteboard.general.string = text
    }
}
