import SwiftUI

// IconView и кэш контуров живут в YTVDIcons — их же рисует приложение для iPhone.

/// Кнопка-иконка в шапке окна и панелях.
public struct IconButton: View {
    let icon: Icon
    let active: Bool
    let help: String
    let action: () -> Void

    @State private var hovering = false

    public init(_ icon: Icon, active: Bool = false, help: String = "", action: @escaping () -> Void) {
        self.icon = icon; self.active = active; self.help = help; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            IconView(icon, size: 15)
                .foregroundStyle(active ? Color.white : (hovering ? Theme.text : Theme.muted))
                .frame(width: 24, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(active ? Theme.blue : (hovering ? Theme.bg3 : .clear))
                )
                // Прозрачная подложка нажатий не принимает — задаём область явно.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(help)
    }
}
