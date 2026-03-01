import SwiftUI

struct TagPopoverView: View {
    let tags: [Tag]
    let onSelect: (Int64?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(tags, id: \.id) { tag in
                Button {
                    onSelect(tag.id)
                } label: {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(tagColor(tag))
                            .frame(width: 10, height: 10)
                        Text(tag.name)
                            .font(.system(size: 13))
                            .foregroundStyle(.primary)
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .cornerRadius(4)
            }

            Divider()

            Button {
                onSelect(nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "xmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                    Text("Remove tag")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .frame(width: 180)
    }

    private func tagColor(_ tag: Tag) -> Color {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hex = isDark ? tag.colorDark : tag.colorLight
        return Color(nsColor: NSColor(hex: hex))
    }
}
