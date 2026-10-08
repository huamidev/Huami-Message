import SwiftUI

/// 法律文档的阅读页（隐私政策 / 服务条款）。
///
/// 设计上只有一个原则：**让"想读的人"读得下去。**
/// 小字号的密排法律文本没人看得完，所以这里：
///   · 用小标题分段，每段之间留白
///   · 关键句子加粗（文本里的 ** ** 会渲染成粗体）
///   · 行距放大 —— 中文长段落挤在一起非常难读
struct LegalDocumentView: View {

    let document: LegalDocument

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text(document.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(document.sections) { section in
                        sectionView(section)
                    }

                    // 时间戳和联系方式放在最后
                    VStack(alignment: .leading, spacing: 6) {
                        HairLine()
                        Text("生效日期：TODO（待填写）")
                        Text("联系邮箱：TODO（待填写）")
                    }
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.top, 8)
                }
                .padding(20)
                .padding(.bottom, 40)
            }
            .scrollIndicators(.hidden)
            .background(AppBackground())
            .navigationTitle(document.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }

    private func sectionView(_ section: LegalDocument.Section) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(section.heading)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, text in
                    paragraph(text)
                }
            }
        }
    }

    /// 一段正文。以 "- " 开头的渲染成小圆点条目，其余当普通段落。
    @ViewBuilder
    private func paragraph(_ text: String) -> some View {
        if text.hasPrefix("- ") {
            HStack(alignment: .top, spacing: 9) {
                Circle()
                    .fill(Theme.accent.opacity(0.55))
                    .frame(width: 4.5, height: 4.5)
                    .padding(.top, 8)
                // LocalizedStringKey 让文本里的 **粗体** 生效
                Text(LocalizedStringKey(String(text.dropFirst(2))))
                    .font(.system(size: 14))
                    .lineSpacing(4)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        } else {
            Text(LocalizedStringKey(text))
                .font(.system(size: 14))
                .lineSpacing(4)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
