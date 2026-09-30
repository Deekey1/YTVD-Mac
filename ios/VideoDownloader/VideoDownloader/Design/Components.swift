import SwiftUI
import YTVDIcons

// Детали интерфейса — те же, что в окне YTVD на Mac: плашки с зерном, заголовки групп
// прописными в разрядку, цветные квадратики, тонкие разделители.

/// Плашка: заливка цветом, объёмный градиент, тонкая тёмная обводка и зерно.
struct BlockBackground: View {
    let color: Color
    var radius: CGFloat = Theme.Metrics.radius

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(color)
            .overlay(
                LinearGradient(colors: [.white.opacity(0.22), .clear, .black.opacity(0.16)],
                               startPoint: .top, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            )
            .overlay(Grain.overlay(opacity: 0.16).clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous)))
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.black.opacity(0.34), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.28), radius: 1, y: 1)
    }
}

/// Горизонтальная линия-разделитель.
struct Hairline: View {
    var body: some View { Theme.sep.frame(height: 1) }
}

/// Заголовок группы: «ВИДЕО» слева, «8 вариантов» справа.
struct GroupHeader: View {
    let title: String
    var trailing: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title.uppercased())
                    .font(Theme.Font.group)
                    .tracking(1.2)
                    .foregroundStyle(Theme.dim)
                Spacer(minLength: 8)
                if let trailing {
                    Text(trailing).font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .frame(minHeight: 30)
            .background(Theme.bg2)
            Hairline()
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Метка поверх обложки: площадка и длительность.
struct Tag: View {
    let text: String
    let color: Color
    var mono = false

    var body: some View {
        Text(text)
            .font(.system(.caption2, weight: .bold))
            .tracking(mono ? 0.2 : 0.7)
            .monospacedDigit()
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .frame(minHeight: 18)
            .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color))
            .overlay(RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.black.opacity(0.3), lineWidth: 1))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Маленькая плашка с подписью: «HEVC», «ЗВУК».
struct BadgeView: View {
    let text: String
    var outside = true

    var body: some View {
        Text(text.uppercased())
            .font(Theme.Font.badge)
            .tracking(0.7)
            .foregroundStyle(outside ? Theme.muted : .white.opacity(0.92))
            .padding(.horizontal, 5)
            .frame(minHeight: 17)
            .background(RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(outside ? Theme.bg3 : Color.black.opacity(0.26)))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

/// Цветной квадратик — тип варианта, как в списке на Mac.
struct Swatch: View {
    let color: Color
    var size = Theme.Metrics.swatch

    var body: some View {
        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
            .fill(color)
            .frame(width: size, height: size)
            .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                .strokeBorder(.black.opacity(0.4), lineWidth: 1))
    }
}

// MARK: - кнопки

/// Главная кнопка — синяя фактурная плашка, как «Скачать» на Mac. Высота постоянная:
/// крупный шрифт делает надпись больше, но не раздувает саму кнопку.
struct PrimaryButtonStyle: ButtonStyle {
    var color: Color = Theme.blue
    var height: CGFloat = Theme.Metrics.buttonHeight
    /// false — по ширине надписи, для кнопки внутри строки.
    var expand = true

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, color: color, height: height, expand: expand)
    }

    private struct PrimaryButtonBody: View {
        let configuration: Configuration
        let color: Color
        let height: CGFloat
        let expand: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Font.button)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 0.5, y: 1)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 14)
                .frame(maxWidth: expand ? .infinity : nil, minHeight: height, maxHeight: height)
                .background(BlockBackground(color: isEnabled ? color : Theme.bg3, radius: 8))
                .brightness(configuration.isPressed ? -0.08 : 0)
                .opacity(isEnabled ? 1 : 0.55)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .contentShape(Rectangle())
        }
    }
}

/// Второстепенная кнопка — тёмная подложка с тонкой рамкой, как «YTVD ›» на Mac.
struct SecondaryButtonStyle: ButtonStyle {
    var height: CGFloat = Theme.Metrics.buttonHeight
    var expand = true

    func makeBody(configuration: Configuration) -> some View {
        SecondaryButtonBody(configuration: configuration, height: height, expand: expand)
    }

    private struct SecondaryButtonBody: View {
        let configuration: Configuration
        let height: CGFloat
        let expand: Bool
        @Environment(\.isEnabled) private var isEnabled

        var body: some View {
            configuration.label
                .font(Theme.Font.button)
                .foregroundStyle(Theme.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .padding(.horizontal, 14)
                .frame(maxWidth: expand ? .infinity : nil, minHeight: height, maxHeight: height)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(configuration.isPressed ? Theme.bg3 : Theme.bg2))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.hair, lineWidth: 1))
                .opacity(isEnabled ? 1 : 0.5)
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .contentShape(Rectangle())
        }
    }
}

/// Небольшая кнопка в строке — как «Показать код» или «Очистить» на Mac.
struct MiniButtonStyle: ButtonStyle {
    var tint: Color? = nil

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.subheadline, weight: .semibold))
            .foregroundStyle(tint ?? Theme.text)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 34)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(configuration.isPressed ? Theme.bg3 : Theme.bg2))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(Theme.hair, lineWidth: 1))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .contentShape(Rectangle())
    }
}

/// Кнопка-иконка, как в шапке окна YTVD: активная — на синей подложке.
struct IconToolButton: View {
    let icon: Icon
    var active = false
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            IconView(icon, size: 20, lineWidth: 1.9)
                .foregroundStyle(active ? Color.white : Theme.dim)
                .frame(width: 38, height: 38)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(active ? Theme.blue : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - переключатели

/// Тумблер в «блочном» стиле, как на Mac.
struct BlockToggle: View {
    @Binding var isOn: Bool
    var label: String

    var body: some View {
        Button { isOn.toggle() } label: {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(isOn ? Theme.blue : Theme.bg3)
                .frame(width: 46, height: 27)
                .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(.black.opacity(0.35), lineWidth: 1))
                .overlay(alignment: isOn ? .trailing : .leading) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(isOn ? Color.white : Color(hex: 0xC8C8C9))
                        .frame(width: 21, height: 21)
                        .padding(.horizontal, 3)
                        .shadow(color: .black.opacity(0.4), radius: 1, y: 1)
                }
                .animation(.easeOut(duration: 0.16), value: isOn)
                .frame(minWidth: 46, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "Включено" : "Выключено")
        .accessibilityAddTraits(.isButton)
    }
}

/// Сегментированный переключатель, как «Сеть / Только Mac» на Mac.
struct Segmented<Value: Hashable>: View {
    @Binding var value: Value
    let options: [(label: String, value: Value)]
    var expand = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                let selected = value == option.value
                Button { value = option.value } label: {
                    Text(option.label)
                        .font(.system(.subheadline, weight: selected ? .semibold : .regular))
                        .foregroundStyle(selected ? Color.white : Theme.dim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .padding(.horizontal, 12)
                        .frame(maxWidth: expand ? .infinity : nil, minHeight: 34)
                        .background(selected ? Theme.blue : Theme.bg2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
                if index < options.count - 1 { Theme.sep.frame(width: 1, height: 34) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hair, lineWidth: 1))
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }
}

// MARK: - строки и поля

/// Строка настройки: слева описание, справа управляющий элемент.
struct SettingRow<Control: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var control: () -> Control

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body).foregroundStyle(Theme.text)
                    if let note {
                        Text(note).font(.footnote).foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 8)
                control()
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 10)
            .frame(minHeight: 50)
            Hairline()
        }
        .background(Theme.bg)
    }
}

/// Поле ввода: тёмная подложка и тонкая рамка.
struct PanelFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body)
            .foregroundStyle(Theme.text)
            .tint(Theme.blue)
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Theme.lane))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.hair, lineWidth: 1))
    }
}

extension View {
    func panelField() -> some View { modifier(PanelFieldStyle()) }
}

/// Полоса хода загрузки: дорожка и синяя фактурная заливка с процентами.
struct ProgressTrack: View {
    let fraction: Double?
    let label: String
    var color: Color = Theme.blue

    @State private var shimmer = false

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                    .fill(Theme.lane)
                    .overlay(RoundedRectangle(cornerRadius: Theme.Metrics.radius, style: .continuous)
                        .strokeBorder(.black.opacity(0.4), lineWidth: 1))
                if let fraction {
                    BlockBackground(color: color)
                        .frame(width: max(8, geometry.size.width * min(1, max(0, fraction))))
                        .animation(.linear(duration: 0.3), value: fraction)
                } else {
                    // Этап без понятного прогресса: плашка ходит туда-сюда, а не стоит на «100 %».
                    BlockBackground(color: color)
                        .frame(width: 34)
                        .offset(x: shimmer ? geometry.size.width - 34 : 0)
                        .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: shimmer)
                        .onAppear { shimmer = true }
                }
                HStack {
                    Spacer()
                    Text(label)
                        .font(Theme.Font.block)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.55), radius: 1, y: 1)
                        .padding(.trailing, 8)
                }
            }
        }
        .frame(height: Theme.Metrics.blockHeight)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement()
        .accessibilityLabel(label)
    }
}

/// Полоса предупреждения — как «Не найден Deno» на Mac.
struct WarningBanner<Action: View>: View {
    let title: String
    let detail: String
    var icon: Icon = .warningTriangle
    @ViewBuilder var action: () -> Action

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                // Значок — на уровне заголовка, а не посередине многострочного текста.
                IconView(icon, size: 20, lineWidth: 1.9).foregroundStyle(Theme.orange)
                    .alignmentGuide(.firstTextBaseline) { $0.height * 0.78 }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(.subheadline, weight: .semibold)).foregroundStyle(Theme.text)
                    Text(detail).font(.footnote).foregroundStyle(Theme.dim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 6)
                action()
            }
            .padding(.horizontal, Theme.Metrics.gutter)
            .padding(.vertical, 10)
            .background(Theme.warning)
            Hairline()
        }
        // Плашка служебная: при самом крупном шрифте она не должна занимать пол-экрана.
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
    }
}

extension WarningBanner where Action == EmptyView {
    init(title: String, detail: String, icon: Icon = .warningTriangle) {
        self.init(title: title, detail: detail, icon: icon) { EmptyView() }
    }
}

/// Пусто — иконка и пара строк посередине.
struct EmptyState: View {
    let icon: Icon
    let title: String
    let detail: String

    var body: some View {
        VStack(spacing: 8) {
            IconView(icon, size: 34, lineWidth: 1.6).foregroundStyle(Theme.muted)
            Text(title).font(.system(.headline)).foregroundStyle(Theme.dim)
            Text(detail).font(.footnote).foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 44)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - шапка и вкладки

/// Шапка экрана: красный квадрат и «YTVD», справа — действия этого экрана.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                    .fill(Theme.red)
                    .frame(width: 13, height: 13)
                    .overlay(RoundedRectangle(cornerRadius: 2.5).strokeBorder(.black.opacity(0.35), lineWidth: 1))
                Text("YTVD").font(Theme.Font.logo).tracking(2.4).foregroundStyle(Theme.text)
                Text(title.uppercased())
                    .font(Theme.Font.group).tracking(1.2).foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                trailing()
            }
            .padding(.leading, 16)
            .padding(.trailing, 8)
            .frame(minHeight: 52)
            .background(Theme.chrome)
            Hairline()
        }
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .contain)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String) { self.init(title: title) { EmptyView() } }
}

/// Нижние вкладки — как иконки в шапке YTVD: выбранная на синей подложке.
struct BottomTabBar<Tab: Hashable>: View {
    @Binding var selection: Tab
    let items: [(tab: Tab, icon: Icon, title: String)]

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    let active = selection == item.tab
                    Button { selection = item.tab } label: {
                        VStack(spacing: 4) {
                            IconView(item.icon, size: 21, lineWidth: 1.9)
                                .foregroundStyle(active ? Color.white : Theme.muted)
                                .frame(width: 44, height: 30)
                                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(active ? Theme.blue : .clear))
                            Text(item.title)
                                .font(.system(.caption2, weight: active ? .semibold : .regular))
                                .foregroundStyle(active ? Theme.text : Theme.muted)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 7)
                        .padding(.bottom, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                    .accessibilityAddTraits(active ? [.isSelected, .isButton] : .isButton)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
        }
        .background(Theme.chrome.ignoresSafeArea(edges: .bottom))
    }
}

/// Прокручен ли список дальше `distance` от верха — например, чтобы показать название
/// в панели, когда шапка с ним уехала. На iOS 17 считаем, что прокручен: название просто
/// стоит в панели всегда.
struct ScrolledPast: ViewModifier {
    let distance: CGFloat
    @Binding var isPast: Bool

    func body(content: Content) -> some View {
        if #available(iOS 18, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.contentInsets.top > distance
            } action: { _, past in
                isPast = past
            }
        } else {
            content.onAppear { isPast = true }
        }
    }
}
