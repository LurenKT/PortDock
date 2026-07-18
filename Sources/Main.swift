import SwiftUI

@main
struct PortDockApp: App {
  @StateObject private var state = AppState()
  @AppStorage(langKey) private var lang = "system"

  var body: some Scene {
    // Window 而非 WindowGroup：openWindow 复用已有窗口，不会开出第二个主窗口
    Window("PortDock", id: "main") {
      ContentView()
        .environmentObject(state)
        .frame(minWidth: 860, minHeight: 520)
        .task {
          // 以隐藏态启动（open -j）时 MenuBarExtra 窗口式面板绑定不上、点图标不弹出，
          // 启动即无激活解除隐藏（不抢焦点）
          if NSApp.isHidden { NSApp.unhideWithoutActivation() }
          state.start()
        }
    }
    .defaultSize(width: 1200, height: 780)

    Settings {
      SettingsView()
    }

    MenuBarExtra {
      MenuBarView(state: state)
        .id(lang)
    } label: {
      Image(systemName: "ferry")
    }
    .menuBarExtraStyle(.window)
  }
}

// MARK: - 设置（⌘, 打开）

struct SettingsView: View {
  @AppStorage(langKey) private var lang = "system"

  var body: some View {
    Form {
      Picker(t("语言", "Language"), selection: $lang) {
        Text(t("跟随系统", "System")).tag("system")
        Text("中文").tag("zh")
        Text("English").tag("en")
      }
      .pickerStyle(.inline)
    }
    .padding(20)
    .frame(width: 300)
  }
}

// MARK: - 菜单栏快捷操作（.window 样式自定义面板）

/// .window 样式的面板不会因点击按钮自动收起，跳走型动作后手动关掉
func closeMenuBarPanel() {
  for window in NSApp.windows where window.className.contains("MenuBarExtraWindow") {
    window.close()
  }
}

struct MenuBarView: View {
  // 显式传 state：MenuBarExtra 是独立场景，不吃 WindowGroup 的 environmentObject
  @ObservedObject var state: AppState
  @Environment(\.openWindow) private var openWindow
  @State private var draggingFavorite: String?   // 正在被拖拽重排的收藏 id
  @State private var expandedIds: Set<String> = []   // 展开显示依赖的收藏

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(t("\(state.snapshot.ports.count) 个端口在监听", "\(state.snapshot.ports.count) ports listening"))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        Spacer()
        if state.isRefreshing {
          ProgressView()
            .controlSize(.mini)
        } else {
          Button {
            Task { await state.refresh(manual: true) }
          } label: {
            Image(systemName: "arrow.clockwise")
              .font(.system(size: 10, weight: .semibold))
              .foregroundStyle(.secondary)
          }
          .buttonStyle(.borderless)
          .help(t("刷新", "Refresh"))
          .accessibilityLabel(t("刷新", "Refresh"))
        }
      }
      .padding(.horizontal, 14)
      .padding(.top, 12)
      .padding(.bottom, 8)

      if state.snapshot.favorites.isEmpty {
        Text(t("在主窗口收藏服务后会出现在这里", "Starred services show up here"))
          .font(.system(size: 11))
          .foregroundStyle(.tertiary)
          .padding(.horizontal, 14)
          .padding(.bottom, 8)
      } else {
        VStack(spacing: 1) {
          ForEach(state.snapshot.favorites) { favorite in
            MenuFavoriteRow(state: state, favorite: favorite,
                            dragging: $draggingFavorite, expandedIds: $expandedIds)
          }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
      }

      Divider()
        .padding(.horizontal, 8)

      HStack {
        Button {
          openWindow(id: "main")
          NSApp.activate(ignoringOtherApps: true)
          closeMenuBarPanel()
        } label: {
          Label(t("打开 PortDock", "Open PortDock"), systemImage: "macwindow")
            .font(.system(size: 12, weight: .medium))
        }
        .modifier(HoverPill())
        Spacer()
        Button {
          NSApp.terminate(nil)
        } label: {
          Image(systemName: "power")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .modifier(HoverPill())
        .help(t("退出 PortDock", "Quit PortDock"))
        .accessibilityLabel(t("退出 PortDock", "Quit PortDock"))
        .keyboardShortcut("q")
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 8)
      .padding(.vertical, 6)

      // 面板内的操作反馈：toast 原本只显示在主窗口，从这里启停服务毫无反馈
      if let message = state.toastMessage {
        Divider().padding(.horizontal, 8)
        Text(message)
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(2)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
      }
    }
    .frame(width: 300)
  }
}

/// 面板里的收藏行：状态灯 + 徽标 + 名称 + 端口，hover 浮现操作按钮。
/// 点击展开依赖子进程；按住拖动重排（纯 DragGesture 驱动——
/// 系统拖放会话 onDrag 在菜单栏非激活面板里根本不启动，2026-07-17 用户实测）
private struct MenuFavoriteRow: View {
  @ObservedObject var state: AppState
  let favorite: FavoriteItem
  @Binding var dragging: String?
  @Binding var expandedIds: Set<String>
  @State private var hovering = false
  @State private var movedBy = 0   // 本次拖拽已挪动的槽位数，与光标位移对齐用

  // ponytail: 行高 30 + VStack 间距 1 = 每槽 31pt；行字体/内边距改了要跟着改
  private static let rowStride: CGFloat = 31

  private var port: Int? { favorite.running ? favorite.livePort : favorite.record.port }
  private var expanded: Bool { expandedIds.contains(favorite.id) }

  var body: some View {
    VStack(spacing: 0) {
      mainRow
      if expanded {
        ForEach(favorite.deps) { dep in
          MenuDepRow(state: state, favorite: favorite, dep: dep)
        }
      }
    }
  }

  private var reorderDrag: some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
      .onChanged { value in
        if dragging != favorite.id {
          dragging = favorite.id
          movedBy = 0
          // 收起全部展开行：行高统一成固定槽高，位移→槽位的换算才成立
          withAnimation(.easeInOut(duration: 0.12)) { expandedIds.removeAll() }
        }
        let desired = Int((value.translation.height / Self.rowStride).rounded())
        var steps = desired - movedBy
        while steps != 0 {
          let dir = steps > 0 ? 1 : -1
          guard let index = state.snapshot.favorites.firstIndex(where: { $0.id == favorite.id }),
                state.snapshot.favorites.indices.contains(index + dir) else { break }
          state.reorderFavorite(dragged: favorite.id, over: state.snapshot.favorites[index + dir].id)
          movedBy += dir
          steps -= dir
        }
      }
      .onEnded { _ in
        dragging = nil
        state.commitFavoriteOrder()
      }
  }

  private var mainRow: some View {
    HStack(spacing: 8) {
      if !favorite.deps.isEmpty {
        Image(systemName: "chevron.right")
          .font(.system(size: 8, weight: .semibold))
          .foregroundStyle(.tertiary)
          .rotationEffect(.degrees(expanded ? 90 : 0))
      }
      StatusDot(running: favorite.running)
      StackBadge(tags: favorite.record.tags ?? [])
      Text(favorite.title.isEmpty ? t("未命名", "Untitled") : favorite.title)
        .font(.system(size: 12.5, weight: .medium))
        .lineLimit(1)
      Spacer(minLength: 8)
      if hovering {
        if let url = favorite.localUrl {
          menuRowIcon("safari", t("在浏览器打开", "Open in browser")) {
            NSWorkspace.shared.open(url)
            closeMenuBarPanel()
          }
        }
        if favorite.running {
          menuRowIcon("arrow.clockwise", t("重启所有", "Restart all")) { state.performAll(.restart, favorite) }
          menuRowIcon("stop.fill", t("关闭所有", "Stop all")) { state.performAll(.stop, favorite) }
        } else {
          menuRowIcon("play.fill", t("启动（含依赖）", "Start (with deps)")) { state.performAll(.start, favorite) }
        }
      } else if let port {
        Text(String(port))
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .frame(height: 30)
    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
      .fill(dragging == favorite.id ? Color.accentColor.opacity(0.15)
            : hovering ? Color.primary.opacity(0.07) : .clear))
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .help(favorite.deps.isEmpty
      ? t("点击：运行中开浏览器，停止则启动 · 按住拖动排序", "Click: open if running, start if stopped · hold and drag to reorder")
      : t("点击展开依赖 · 按住拖动排序", "Click to expand dependencies · hold and drag to reorder"))
    .onTapGesture {
      // 有依赖 → 点击展开/收起；没有 → 保持原快捷行为（开浏览器/启动）
      if !favorite.deps.isEmpty {
        withAnimation(.easeInOut(duration: 0.15)) {
          if expanded { expandedIds.remove(favorite.id) } else { expandedIds.insert(favorite.id) }
        }
      } else if let url = favorite.localUrl {
        NSWorkspace.shared.open(url)
        closeMenuBarPanel()
      } else if !favorite.running {
        state.performAll(.start, favorite)
      }
    }
    .gesture(reorderDrag)
  }
}

/// 展开后的依赖子行：状态点 + 名称 + 端口，hover 浮现该服务自己的操作
private struct MenuDepRow: View {
  @ObservedObject var state: AppState
  let favorite: FavoriteItem
  let dep: DepStatus
  @State private var hovering = false

  private var url: URL? {
    guard dep.running, let port = dep.port, !dep.isDocker else { return nil }
    return serviceURL(port: port, scope: dep.scope, path: dep.uiPath)
  }

  var body: some View {
    HStack(spacing: 6) {
      Image(systemName: "arrow.turn.down.right")
        .font(.system(size: 8.5, weight: .semibold))
        .foregroundStyle(.tertiary)
      Circle()
        .fill(dep.running ? Color.green : Color.secondary.opacity(0.35))
        .frame(width: 5, height: 5)
      Text(dep.label)
        .font(.system(size: 11))
        .lineLimit(1)
      if let port = dep.port {
        Text(String(port))
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(.tertiary)
      }
      Spacer(minLength: 8)
      if hovering {
        if let url {
          menuRowIcon("safari", t("在浏览器打开", "Open in browser")) {
            NSWorkspace.shared.open(url)
            closeMenuBarPanel()
          }
        }
        if dep.running {
          menuRowIcon("arrow.clockwise", t("重启", "Restart")) { state.perform(.restart, favorite, dep: dep) }
          menuRowIcon("stop.fill", t("关闭", "Stop")) { state.perform(.stop, favorite, dep: dep) }
        } else {
          menuRowIcon("play.fill", t("启动", "Start")) { state.perform(.start, favorite, dep: dep) }
        }
      }
    }
    .padding(.leading, 30)
    .padding(.trailing, 8)
    .frame(height: 24)   // 固定行高：hover 浮现的按钮(20pt)不再把行撑高
    .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
      .fill(hovering ? Color.primary.opacity(0.05) : .clear))
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture {
      if let url {
        NSWorkspace.shared.open(url)
        closeMenuBarPanel()
      }
    }
  }
}

/// 底部行按钮的 hover 高亮：与列表行同款圆角变色
private struct HoverPill: ViewModifier {
  @State private var hovering = false
  func body(content: Content) -> some View {
    content
      .padding(.horizontal, 6)
      .padding(.vertical, 4)
      .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(hovering ? Color.primary.opacity(0.07) : .clear))
      .onHover { hovering = $0 }
  }
}

private func menuRowIcon(_ name: String, _ help: String, action: @escaping () -> Void) -> some View {
  Button(action: action) {
    Image(systemName: name)
      .font(.system(size: 10, weight: .semibold))
      .frame(width: 20, height: 20)
      .contentShape(Rectangle())
  }
  .buttonStyle(.borderless)
  .help(help)
  .accessibilityLabel(help)
}

