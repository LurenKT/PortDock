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
        .trackWindowVisibility()
        .task { state.start() }
    }
    .defaultSize(width: 1200, height: 780)

    Settings {
      SettingsView()
    }

    MenuBarExtra {
      MenuBarView(state: state)
        .id(lang)
        .trackWindowVisibility()
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

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(t("\(state.snapshot.ports.count) 个端口在监听", "\(state.snapshot.ports.count) ports listening"))
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        Spacer()
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
            MenuFavoriteRow(state: state, favorite: favorite)
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
        Spacer()
        Button {
          NSApp.terminate(nil)
        } label: {
          Image(systemName: "power")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
        }
        .help(t("退出 PortDock", "Quit PortDock"))
        .accessibilityLabel(t("退出 PortDock", "Quit PortDock"))
        .keyboardShortcut("q")
      }
      .buttonStyle(.borderless)
      .padding(.horizontal, 14)
      .padding(.vertical, 10)
    }
    .frame(width: 300)
  }
}

/// 面板里的收藏行：状态呼吸灯 + 技术栈徽标 + 名称 + 端口，hover 浮现操作按钮
private struct MenuFavoriteRow: View {
  @ObservedObject var state: AppState
  let favorite: FavoriteItem
  @State private var hovering = false

  private var port: Int? { favorite.running ? favorite.livePort : favorite.record.port }

  var body: some View {
    HStack(spacing: 8) {
      StatusDot(running: favorite.running)
      StackBadge(tags: favorite.record.tags ?? [])
      Text(favorite.title.isEmpty ? t("未命名", "Untitled") : favorite.title)
        .font(.system(size: 12.5, weight: .medium))
        .lineLimit(1)
      Spacer(minLength: 8)
      if hovering {
        if let url = favorite.localUrl {
          rowIcon("safari", t("在浏览器打开", "Open in browser")) {
            NSWorkspace.shared.open(url)
            closeMenuBarPanel()
          }
        }
        if favorite.running {
          rowIcon("arrow.clockwise", t("重启所有", "Restart all")) { state.performAll(.restart, favorite) }
          rowIcon("stop.fill", t("关闭所有", "Stop all")) { state.performAll(.stop, favorite) }
        } else {
          rowIcon("play.fill", t("启动（含依赖）", "Start (with deps)")) { state.performAll(.start, favorite) }
        }
      } else if let port {
        Text(String(port))
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
      }
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
      .fill(hovering ? Color.primary.opacity(0.07) : .clear))
    .contentShape(Rectangle())
    .onHover { hovering = $0 }
    .onTapGesture {
      // 整行点击：运行中开浏览器，停着就启动
      if let url = favorite.localUrl {
        NSWorkspace.shared.open(url)
        closeMenuBarPanel()
      } else if !favorite.running {
        state.performAll(.start, favorite)
      }
    }
  }

  private func rowIcon(_ name: String, _ help: String, action: @escaping () -> Void) -> some View {
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
}
