import SwiftUI

/// 小工具庫：上方搜尋列、左側 App 列表、右側預覽與「加入小工具」。
struct WidgetGallery: View {
    let onAdd: (WidgetKind) -> Void
    let onClose: () -> Void

    @State private var query = ""
    @State private var selected: WidgetApp?
    @State private var page = 0
    @GestureState private var dragY: CGFloat = 0

    private var results: [WidgetKind] {
        guard !query.isEmpty else { return WidgetKind.allCases }
        return WidgetKind.allCases.filter {
            $0.title.localizedCaseInsensitiveContains(query) || $0.app.name.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let W = geo.size.width, H = geo.size.height
            ZStack {
                Color.black.opacity(0.55)
                    .onTapGesture(perform: onClose)
                    .accessibilityLabel("關閉小工具庫")
                    .accessibilityAddTraits(.isButton)
                VStack(spacing: 0) {
                    searchBar
                        .padding(.top, 20)
                        .padding(.bottom, 16)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .gesture(DragGesture().updating($dragY) { v, s, _ in s = max(0, v.translation.height) }
                            .onEnded { v in if v.translation.height > 120 { onClose() } })
                    Rectangle().fill(Color.white.opacity(0.08)).frame(height: 1)
                    HStack(spacing: 0) {
                        sidebar.frame(width: W * 0.28)
                        Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1)
                        detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(width: W * 0.9, height: H * 0.88)
                .background(RoundedRectangle(cornerRadius: 40, style: .continuous).fill(Color(hex: 0x1C1C1E)))
                .clipShape(RoundedRectangle(cornerRadius: 40, style: .continuous))
                .shadow(color: .black.opacity(0.5), radius: 40, y: 10)
                .offset(y: dragY)
            }
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundColor(.sbGray)
            TextField("搜尋小工具", text: $query)
                .submitLabel(.search)
                .foregroundColor(.white)
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.sbGray)
                }
                .accessibilityLabel("清除搜尋")
            }
        }
        .font(.system(size: 20))
        .padding(.horizontal, 16)
        .frame(width: 500, height: 50)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.12)))
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 4) {
                sidebarRow(nil)
                ForEach(WidgetApp.allCases) { sidebarRow($0) }
            }
            .padding(16)
        }
    }

    private func sidebarRow(_ app: WidgetApp?) -> some View {
        let isSelected = query.isEmpty && selected == app
        return Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                selected = app
                page = 0
                query = ""
            }
        } label: {
            HStack(spacing: 14) {
                if let app {
                    AppIconView(app: app, size: 40)
                } else {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 22))
                        .frame(width: 40, height: 40)
                }
                Text(app?.name ?? "建議").font(.system(size: 21))
                Spacer()
            }
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.white.opacity(0.13) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private var detail: some View {
        if let app = selected, query.isEmpty {
            appDetail(app)
        } else {
            grid(results)
        }
    }

    private func grid(_ kinds: [WidgetKind]) -> some View {
        ScrollView {
            if kinds.isEmpty {
                Text("找不到「\(query)」")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.sbGray)
                    .padding(.top, 80)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210, maximum: 260), spacing: 28)], spacing: 30) {
                ForEach(kinds) { k in
                    Button { onAdd(k) } label: {
                        VStack(spacing: 10) {
                            WidgetView(kind: k, side: 210)
                                .background(RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color.black))
                                .allowsHitTesting(false)
                            VStack(spacing: 2) {
                                Text(k.app.name).font(.system(size: 17, weight: .semibold)).foregroundColor(.white)
                                Text(k.title).font(.system(size: 15)).foregroundColor(.sbGray)
                            }
                        }
                    }
                    .buttonStyle(PressScaleStyle())
                    .accessibilityLabel("加入\(k.app.name)\(k.title)")
                }
            }
            .padding(28)
        }
    }

    @ViewBuilder private func appDetail(_ app: WidgetApp) -> some View {
        let kinds = app.kinds
        let k = kinds[min(page, kinds.count - 1)]
        VStack(spacing: 10) {
            Text(k.title)
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
            Text(k.subtitle)
                .font(.system(size: 18))
                .foregroundColor(.sbGray)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            TabView(selection: $page) {
                ForEach(Array(kinds.enumerated()), id: \.offset) { i, kind in
                    WidgetView(kind: kind, side: 230)
                        .background(RoundedRectangle(cornerRadius: 34, style: .continuous).fill(Color.black))
                        .allowsHitTesting(false)
                        .tag(i)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: kinds.count > 1 ? .always : .never))
            .frame(height: 300)
            .animation(.easeInOut(duration: 0.25), value: page)

            Button { onAdd(k) } label: {
                Label("加入小工具", systemImage: "plus.circle.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(app.buttonText)
                    .frame(maxWidth: 440, minHeight: 56)
                    .background(Capsule().fill(app.buttonColor))
            }
            .buttonStyle(PressScaleStyle())
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .id(app)
    }
}
