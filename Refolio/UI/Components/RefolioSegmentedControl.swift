import SwiftUI

struct RefolioSegmentedControl<Item: Identifiable & Equatable>: View {
    let items: [Item]
    @Binding var selection: Item
    let title: (Item) -> String
    var icon: ((Item) -> String)? = nil
    var helpText: ((Item) -> String)? = nil

    @Namespace private var animation
    @State private var hoveredItem: Item? = nil

    init(
        items: [Item],
        selection: Binding<Item>,
        title: @escaping (Item) -> String,
        icon: ((Item) -> String)? = nil,
        helpText: ((Item) -> String)? = nil
    ) {
        self.items = items
        self._selection = selection
        self.title = title
        self.icon = icon
        self.helpText = helpText
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                let isSelected = selection == item
                let isHovered = hoveredItem == item && !isSelected

                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selection = item
                    }
                } label: {
                    HStack(spacing: 5) {
                        if let iconName = icon?(item) {
                            Image(systemName: iconName)
                                .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                        }
                        Text(title(item))
                            .font(.system(size: 12.5, weight: isSelected ? .semibold : .medium))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(
                        isSelected
                            ? Color.primary
                            : (isHovered ? Color.primary.opacity(0.85) : Color.secondary)
                    )
                    .frame(maxWidth: .infinity)
                    .frame(height: 30)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background {
                    if isSelected {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.08), radius: 2.5, x: 0, y: 1.5)
                            .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 0.5)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 0.5)
                            )
                            .matchedGeometryEffect(id: "active_indicator", in: animation)
                    } else if isHovered {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    }
                }
                .onHover { hovering in
                    hoveredItem = hovering ? item : nil
                }
                .help(helpText?(item) ?? title(item))

                if index < items.count - 1 {
                    if selection != item && selection != items[index + 1] && hoveredItem != item && hoveredItem != items[index + 1] {
                        Rectangle()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 1, height: 14)
                    } else {
                        Spacer().frame(width: 1)
                    }
                }
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(Color.primary.opacity(0.04), lineWidth: 0.5)
                )
        )
    }
}
