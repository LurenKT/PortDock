import SwiftUI

@main
struct PortDockApp: App {
  @StateObject private var state = AppState()
  @AppStorage(langKey) private var lang = "system"

  var body: some Scene {
    WindowGroup(id: "main") {
      ContentView()
        .environmentObject(state)
        .frame(minWidth: 860, minHeight: 520)
        .task { state.start() }
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

// MARK: - 菜单栏快捷操作

struct MenuBarView: View {
  // 显式传 state：MenuBarExtra 是独立场景，不吃 WindowGroup 的 environmentObject
  @ObservedObject var state: AppState
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text(t("\(state.snapshot.ports.count) 个端口在监听", "\(state.snapshot.ports.count) ports listening"))
    Divider()
    ForEach(state.snapshot.favorites) { favorite in
      Menu {
        if let url = favorite.localUrl {
          Button(t("在浏览器打开", "Open in browser")) { NSWorkspace.shared.open(url) }
        }
        Button(t("启动（含依赖）", "Start (with deps)")) { state.performAll(.start, favorite) }
          .disabled(favorite.running)
        Button(t("重启所有", "Restart all")) { state.performAll(.restart, favorite) }
          .disabled(!favorite.running)
        Button(t("关闭所有", "Stop all")) { state.performAll(.stop, favorite) }
          .disabled(!favorite.running)
      } label: {
        let port = (favorite.running ? favorite.livePort : favorite.record.port).map { "  \($0)" } ?? ""
        Text("\(favorite.running ? "●" : "○") \(favorite.title.isEmpty ? t("未命名", "Untitled") : favorite.title)\(port)")
      }
    }
    if !state.snapshot.favorites.isEmpty { Divider() }
    Button(t("打开 PortDock", "Open PortDock")) {
      openWindow(id: "main")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button(t("刷新", "Refresh")) { Task { await state.refresh(manual: true) } }
    Divider()
    Button(t("退出 PortDock", "Quit PortDock")) { NSApp.terminate(nil) }
      .keyboardShortcut("q")
  }
}
