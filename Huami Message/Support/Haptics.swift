import UIKit

/// 触觉反馈（震动）。
///
/// 【为什么这点小东西值得单独一个文件】
///
/// 好的触觉反馈用户**注意不到**，但它会让操作显得"扎实"。
/// 少了它，界面会显得"飘"——说不上哪里不对，就是不如原生 App 舒服。
///
/// 三条使用原则（我在下面各处都照这个来）：
///   1. **只给"用户做了某件事"的时刻反馈**，不给"正在发生"的时刻。
///      每来一条消息就震一下，用户会想卸载。
///   2. **强度要克制**。`.light` 是日常；`.medium` 只在真正重要的动作上用。
///   3. **失败和成功要给不同的手感**。成功的"咔"和失败的"梆"必须能分辨。
///
/// 模拟器上没有震动马达，这些调用是空操作 ——
/// 所以**必须装到真机上才能感觉到**。
enum Haptics {

    /// 轻点一下：发送消息、选中一个选项
    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// 选中变化：在选项之间切换（比如润色的三个风格）
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// 成功：消息发送成功、AI 分析完成
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// 警告：删除、清空、拉黑这类不可撤销的动作
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
