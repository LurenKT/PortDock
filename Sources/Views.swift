import SwiftUI

// MARK: - 技术栈徽标（品牌色圆角块 + 缩写）

struct StackBadge: View {
  let tags: [String]

  static let brands: [(tag: String, label: String, color: Color)] = [
    ("Vite", "V", Color(red: 0.39, green: 0.42, blue: 1.0)),
    ("Next.js", "N", .black),
    ("Nuxt", "Nx", Color(red: 0.0, green: 0.86, blue: 0.51)),
    ("Astro", "A", Color(red: 1.0, green: 0.36, blue: 0.21)),
    ("Webpack", "W", Color(red: 0.55, green: 0.84, blue: 0.98)),
    ("Node", "N", Color(red: 0.37, green: 0.63, blue: 0.31)),
    ("npm", "n", Color(red: 0.8, green: 0.2, blue: 0.2)),
    ("pnpm", "p", Color(red: 0.96, green: 0.68, blue: 0.09)),
    ("Python", "Py", Color(red: 0.22, green: 0.46, blue: 0.67)),
    ("HTTP server", "Py", Color(red: 0.22, green: 0.46, blue: 0.67)),
    ("Uvicorn", "Uv", Color(red: 0.22, green: 0.46, blue: 0.67)),
    ("Django", "Dj", Color(red: 0.27, green: 0.72, blue: 0.55)),
    ("Flask", "F", .gray),
    ("Rails", "R", Color(red: 0.83, green: 0.0, blue: 0.0)),
    ("Ruby", "R", Color(red: 0.8, green: 0.2, blue: 0.18)),
    ("PHP", "P", Color(red: 0.47, green: 0.48, blue: 0.71)),
    ("Docker", "D", Color(red: 0.14, green: 0.59, blue: 0.93)),
    ("Postgres", "Pg", Color(red: 0.25, green: 0.41, blue: 0.88)),
    ("Redis", "Re", Color(red: 1.0, green: 0.27, blue: 0.22)),
    ("MySQL", "My", Color(red: 0.27, green: 0.47, blue: 0.63)),
    ("MariaDB", "Ma", Color(red: 0.27, green: 0.47, blue: 0.63)),
    ("MongoDB", "M", Color(red: 0.28, green: 0.64, blue: 0.28)),
    ("Bun", "B", Color(red: 0.98, green: 0.91, blue: 0.71)),
    ("Deno", "De", .black),
    ("Ollama", "O", .black),
    ("Claude", "C", Color(red: 0.85, green: 0.47, blue: 0.34)),
    ("Codex", "Cx", .black),
    ("Cursor", "Cu", .black)
  ]

  var body: some View {
    if let brand = Self.brands.first(where: { tags.contains($0.tag) }) {
      Text(brand.label)
        .font(.system(size: 8.5, weight: .bold, design: .rounded))
        .foregroundStyle(.white)
        .frame(width: 16, height: 16)
        .background(brand.color.gradient, in: RoundedRectangle(cornerRadius: 4))
    } else {
      Image(systemName: "shippingbox")
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(width: 16, height: 16)
    }
  }
}

// MARK: - 运行状态点（运行中带呼吸脉冲）

struct StatusDot: View {
  let running: Bool
  @State private var pulsing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Circle()
      .fill(running ? Color.green : Color.secondary.opacity(0.4))
      .frame(width: 7, height: 7)
      .background {
        if running && !reduceMotion {
          Circle()
            .stroke(Color.green.opacity(0.5), lineWidth: 2)
            .scaleEffect(pulsing ? 2.4 : 1)
            .opacity(pulsing ? 0 : 0.8)
            .onAppear {
              withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulsing = true
              }
            }
        }
      }
  }
}

// MARK: - 主结构

struct ContentView: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    NavigationSplitView {
      SidebarView()
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      MainView()
    }
    .searchable(text: $state.searchText, placement: .toolbar, prompt: "端口、PID、命令")
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Picker("显示模式", selection: $state.simpleMode) {
          Text("简单").tag(true)
          Text("完整").tag(false)
        }
        .pickerStyle(.segmented)
      }
      ToolbarItemGroup {
        if let row = state.selectedRow {
          if let url = row.localUrl {
            Button {
              NSWorkspace.shared.open(url)
            } label: {
              Label("打开", systemImage: "safari")
            }
            .help("在浏览器打开")
          }
          Button {
            state.detailTarget = row
          } label: {
            Label("详情", systemImage: "info.circle")
          }
          .help("详细信息")
          if canRestart(row) {
            Button {
              state.requestRestart(row)
            } label: {
              Label("重启", systemImage: "arrow.clockwise.circle")
            }
            .help("重启该服务")
          }
          Button {
            state.requestKill(row)
          } label: {
            Label("结束", systemImage: "stop.circle")
          }
          .help("结束进程")
        }
        Button {
          Task { await state.refresh(manual: true) }
        } label: {
          if state.isRefreshing {
            ProgressView()
              .controlSize(.small)
          } else {
            Label("刷新", systemImage: "arrow.clockwise")
          }
        }
        .help("刷新")
      }
    }
    .overlay(alignment: .bottom) {
      if let message = state.toastMessage {
        Text(message)
          .font(.callout)
          .padding(.horizontal, 14)
          .padding(.vertical, 8)
          .background(.regularMaterial, in: Capsule())
          .shadow(radius: 8, y: 2)
          .padding(.bottom, 16)
          .transition(.move(edge: .bottom).combined(with: .opacity))
      }
    }
    .animation(.easeOut(duration: 0.2), value: state.toastMessage)
    .modifier(ActionDialogs())
  }
}

// MARK: - 侧栏

struct SidebarView: View {
  @EnvironmentObject var state: AppState
  @AppStorage(lanShareKey) private var lanShare = false

  var body: some View {
    List(selection: $state.selection) {
      Section {
        Label("Home", systemImage: "house")
          .tag(SidebarSelection.home)
      }

      Section("收藏") {
        if state.snapshot.favorites.isEmpty {
          Text("在列表中右键收藏项目，\n停止后可从这里一键启动。")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        ForEach(state.snapshot.favorites) { favorite in
          Button {
            state.openFavorite(favorite)
          } label: {
            HStack(spacing: 7) {
              StackBadge(tags: favorite.record.tags ?? [])
              Text(favorite.title.isEmpty ? "未命名" : favorite.title)
                .lineLimit(1)
              Spacer()
              if let port = favorite.running ? favorite.livePort : favorite.record.port {
                Text(String(port))
                  .font(.system(size: 10, design: .monospaced))
                  .foregroundStyle(.secondary)
              }
              if state.startingIds.contains(favorite.id) {
                ProgressView()
                  .controlSize(.mini)
              } else {
                StatusDot(running: favorite.running)
              }
            }
          }
          .buttonStyle(.plain)
          .help(favorite.running ? "运行中 · 点击在浏览器打开" : "已停止 · 点击启动\n\(favorite.record.command)")
          .contextMenu {
            Button("取消收藏") { state.unfavorite(id: favorite.id) }
          }
        }
      }

      Section("分类") {
        sidebarRow(.all, label: "全部", icon: "square.grid.2x2",
                   count: state.snapshot.ports.count + state.snapshot.agentProcesses.count)
        sidebarRow(.category(.web), label: "Web", icon: "globe", count: state.snapshot.count(of: .web))
        sidebarRow(.category(.agent), label: "Agent", icon: "sparkles", count: state.snapshot.count(of: .agent))
        sidebarRow(.category(.infra), label: "基础设施", icon: "cylinder.split.1x2", count: state.snapshot.count(of: .infra))
        sidebarRow(.category(.other), label: "其它", icon: "shippingbox", count: state.snapshot.count(of: .other))
        sidebarRow(.stopped, label: "已停止", icon: "moon.zzz", count: state.snapshot.stopped.count)
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      VStack(alignment: .leading, spacing: 3) {
        Toggle(isOn: $lanShare) {
          Label("局域网共享", systemImage: "wifi")
            .font(.system(size: 11.5))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        if lanShare {
          Text(lanIPv4().map { "打开链接用 \($0)" } ?? "未找到局域网地址")
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
      .help("开启后，打开网页用本机局域网 IP，同一网络的手机/电脑也能访问；仅监听 127.0.0.1 的服务仍用 localhost")
    }
  }

  func sidebarRow(_ value: SidebarSelection, label: String, icon: String, count: Int) -> some View {
    Label {
      HStack {
        Text(label)
        Spacer()
        Text(String(count))
          .font(.system(size: 10.5, design: .monospaced))
          .foregroundStyle(.secondary)
          .contentTransition(.numericText())
      }
    } icon: {
      Image(systemName: icon)
    }
    .tag(value)
  }
}

// MARK: - 主区

struct MainView: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    ZStack {
      switch state.selection {
      case .home:
        HomeView()
          .transition(.opacity)
      case .stopped:
        StoppedTable()
          .transition(.opacity)
      default:
        PortsTable()
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.18), value: state.selection)
  }
}

// MARK: - Home

/// 统一卡片表面：抬起的控件底色 + 极细描边 + 轻阴影，hover 时加强。
extension View {
  func cardSurface(cornerRadius: CGFloat = 12, elevated: Bool = false) -> some View {
    self
      .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(Color.primary.opacity(elevated ? 0.12 : 0.06), lineWidth: 1))
      .shadow(color: .black.opacity(elevated ? 0.10 : 0.045),
              radius: elevated ? 8 : 2.5, y: elevated ? 3 : 1)
  }
}

/// CPU 列表副标题：优先干净的网页标题，退回项目目录名，再退回命令首词。
/// 目的是消掉 "Page not found at /" 这类抓取噪音。
func cleanSubtitle(_ row: PortRow) -> String {
  let title = row.title.trimmingCharacters(in: .whitespaces)
  let lower = title.lowercased()
  let noise = title.isEmpty
    || lower.contains("not found")
    || lower.contains("error")
    || lower.hasPrefix("page ")
  if !noise { return title }
  if row.cwd != "/", !row.cwd.isEmpty {
    let dir = URL(fileURLWithPath: row.cwd).lastPathComponent
    if !dir.isEmpty, dir != "/" { return dir }
  }
  if let head = row.command.split(separator: " ").first {
    return URL(fileURLWithPath: String(head)).lastPathComponent
  }
  return row.name
}

struct HomeView: View {
  @EnvironmentObject var state: AppState

  var topCpuRows: [PortRow] {
    var pool = state.snapshot.ports + state.snapshot.agentProcesses
    // 跟随简单/完整模式：简单模式只看有标题的项目服务
    if state.simpleMode {
      pool = pool.filter { !$0.title.isEmpty }
    }
    return Array(pool.sorted { $0.cpu > $1.cpu }.prefix(5)).filter { $0.cpu > 0.05 }
  }

  /// 列表里最高的 CPU 值，用作强度条的满格基准
  var maxCpu: Double { max(topCpuRows.first?.cpu ?? 0, 0.1) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        if !state.snapshot.favorites.isEmpty {
          section("收藏项目", count: state.snapshot.favorites.count) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 12)], spacing: 12) {
              ForEach(state.snapshot.favorites) { favorite in
                FavoriteCard(favorite: favorite)
              }
            }
          }
        }

        section("系统") {
          // 自适应网格：等宽等高、铺满整行，不再让卡片挤在左边留白
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 148), spacing: 12)],
            alignment: .leading, spacing: 12
          ) {
            gaugeTile(
              "CPU",
              fraction: state.snapshot.system.cpuUsage,
              value: state.snapshot.system.cpuUsage.map { String(format: "%.0f", $0 * 100) } ?? "--",
              unit: "%"
            )
            gaugeTile(
              "内存",
              fraction: state.snapshot.system.memUsage,
              value: String(format: "%.1f", Double(state.snapshot.system.memUsedBytes) / 1_073_741_824),
              unit: String(format: "/ %.0f GB", Double(state.snapshot.system.memTotalBytes) / 1_073_741_824)
            )
            countTile("监听端口", value: state.snapshot.ports.count,
                      systemImage: "antenna.radiowaves.left.and.right", tint: .green)
            countTile("HTTP 可访问", value: state.snapshot.httpOkCount,
                      systemImage: "checkmark.seal", tint: .blue)
            countTile("已停止", value: state.snapshot.stopped.count,
                      systemImage: "moon.zzz", tint: .orange)
          }
        }

        if !topCpuRows.isEmpty {
          section("CPU 占用最高的服务") {
            VStack(spacing: 0) {
              ForEach(Array(topCpuRows.enumerated()), id: \.element.id) { index, row in
                TopCpuRowView(row: row, fraction: row.cpu / maxCpu)
                if index != topCpuRows.count - 1 {
                  Divider().padding(.leading, 40)
                }
              }
            }
            .cardSurface()
          }
        }
      }
      .padding(22)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  // MARK: 区块容器（统一小标题 + 可选计数）

  @ViewBuilder
  func section<Content: View>(
    _ title: String, count: Int? = nil, @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 11) {
      HStack(spacing: 7) {
        Text(title)
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(.secondary)
        if let count {
          Text(String(count))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
        }
        Spacer()
      }
      content()
    }
  }

  // MARK: 系统指标卡（统一等高：标题在上、右上角环/图标、大数字在下）

  func gaugeTile(_ label: String, fraction: Double?, value: String, unit: String) -> some View {
    let f = fraction ?? 0
    let tint: Color = f > 0.85 ? .red : f > 0.6 ? .orange : .green
    return VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(label)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        Spacer()
        ZStack {
          Circle().stroke(.quaternary, lineWidth: 3)
          Circle()
            .trim(from: 0, to: f)
            .stroke(tint.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
            .animation(.easeOut(duration: 0.4), value: f)
        }
        .frame(width: 18, height: 18)
      }
      Spacer(minLength: 8)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value)
          .font(.system(size: 23, weight: .semibold, design: .rounded))
          .contentTransition(.numericText())
        Text(unit)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .frame(height: 82, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  func countTile(_ label: String, value: Int, systemImage: String, tint: Color) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        Text(label)
          .font(.system(size: 11, weight: .medium))
          .foregroundStyle(.secondary)
        Spacer()
        Image(systemName: systemImage)
          .font(.system(size: 12, weight: .medium))
          .foregroundStyle(tint)
      }
      Spacer(minLength: 8)
      Text(String(value))
        .font(.system(size: 23, weight: .semibold, design: .rounded))
        .contentTransition(.numericText())
        .foregroundStyle(value == 0 ? Color.secondary : Color.primary)
    }
    .padding(12)
    .frame(height: 82, alignment: .topLeading)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }
}

struct TopCpuRowView: View {
  @EnvironmentObject var state: AppState
  let row: PortRow
  let fraction: Double   // 相对列表最高 CPU 的比例，决定强度条长度

  var tint: Color {
    row.cpu > 50 ? .red : row.cpu > 15 ? .orange : .accentColor
  }

  var body: some View {
    HStack(spacing: 10) {
      StackBadge(tags: row.tags)
      VStack(alignment: .leading, spacing: 1) {
        Text(row.name)
          .font(.system(size: 12.5, weight: .medium))
          .lineLimit(1)
        Text(cleanSubtitle(row))
          .font(.system(size: 10.5))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 12)
      if let port = row.port {
        Text(String(port))
          .font(.system(size: 10.5, design: .monospaced))
          .foregroundStyle(.tertiary)
      }
      // 强度条：条长按相对最高占用，颜色按绝对占用（低占用保持平静）
      ZStack(alignment: .leading) {
        Capsule().fill(.quaternary)
        GeometryReader { geo in
          Capsule()
            .fill(tint.gradient)
            .frame(width: max(3, geo.size.width * min(1, fraction)))
        }
      }
      .frame(width: 60, height: 5)
      Text(String(format: "%.1f%%", row.cpu))
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .frame(width: 46, alignment: .trailing)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .onTapGesture { state.detailTarget = row }
    .contextMenu {
      RowMenuItems(state: state, row: row)
    }
  }
}

struct FavoriteCard: View {
  @EnvironmentObject var state: AppState
  let favorite: FavoriteItem
  @State private var hovering = false
  @State private var showActions = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var starting: Bool { state.startingIds.contains(favorite.id) }

  var body: some View {
    Button {
      showActions = true
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          StackBadge(tags: favorite.record.tags ?? [])
          Text(favorite.title.isEmpty ? "未命名" : favorite.title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
          Spacer()
          if starting {
            ProgressView()
              .controlSize(.mini)
          } else {
            StatusDot(running: favorite.running)
          }
        }
        HStack(spacing: 8) {
          if let port = favorite.running ? favorite.livePort : favorite.record.port {
            Text("端口 \(String(port))")
          }
          if starting {
            Text("启动中…")
          } else if favorite.running {
            if !favorite.liveUptime.isEmpty {
              Text("已运行 \(favorite.liveUptime)")
            }
          } else {
            Text(favorite.deps.isEmpty ? "已停止 · 点击启动" : "已停止 · 点击连带依赖一起启动")
          }
          Spacer()
        }
        .font(.system(size: 10.5))
        .foregroundStyle(.secondary)
        // 依赖服务（学到过的父子关系）：名字 + 端口 + 各自的运行状态
        if !favorite.deps.isEmpty {
          VStack(alignment: .leading, spacing: 3) {
            ForEach(favorite.deps) { dep in
              HStack(spacing: 5) {
                Image(systemName: "arrow.turn.down.right")
                  .font(.system(size: 8.5, weight: .semibold))
                  .foregroundStyle(.tertiary)
                Text(dep.label)
                  .font(.system(size: 10.5))
                  .lineLimit(1)
                if let port = dep.port {
                  Text(String(port))
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                }
                Spacer()
                Circle()
                  .fill(dep.running ? Color.green : Color.secondary.opacity(0.35))
                  .frame(width: 5, height: 5)
              }
            }
          }
          .foregroundStyle(.secondary)
          .padding(.top, 1)
        }
      }
      .padding(12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .cardSurface(elevated: hovering)
      .scaleEffect(hovering && !reduceMotion ? 1.02 : 1)
    }
    .buttonStyle(.plain)
    .disabled(starting)
    .onHover { value in
      withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
        hovering = value
      }
    }
    .help("点击管理：启动 / 重启 / 关闭")
    .popover(isPresented: $showActions, arrowEdge: .bottom) {
      // ponytail: 显式传 state —— popover 是断裂 hosting 上下文，
      // 独立 View 用 @EnvironmentObject 会崩（同 PortCardRow）
      FavoriteActionPanel(state: state, favorite: favorite)
    }
    .contextMenu {
      if let url = favorite.localUrl {
        Button("在浏览器打开") { NSWorkspace.shared.open(url) }
      }
      Button("取消收藏") { state.unfavorite(id: favorite.id) }
    }
  }
}

// MARK: - 收藏操作面板（点击卡片弹出）

struct FavoriteActionPanel: View {
  @ObservedObject var state: AppState
  let favorite: FavoriteItem
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      // 第一行：整行的浏览器打开（最高频动作）
      Button {
        if let url = favorite.localUrl { NSWorkspace.shared.open(url) }
        dismiss()
      } label: {
        Label(favorite.localUrl.map { "打开 \($0.absoluteString)" } ?? "未运行，无法打开",
              systemImage: "safari")
          .font(.system(size: 11.5, weight: .medium))
          .lineLimit(1)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(favorite.localUrl == nil)
      HStack(spacing: 8) {
        bulkButton("启动所有", icon: "play.fill", tint: .green, action: .start)
        bulkButton("重启所有", icon: "arrow.clockwise", tint: .orange, action: .restart)
        bulkButton("关闭所有", icon: "stop.fill", tint: .red, action: .stop)
      }
      Divider()
      VStack(alignment: .leading, spacing: 2) {
        serviceRow(label: favorite.title.isEmpty ? "未命名" : favorite.title,
                   port: favorite.running ? favorite.livePort : favorite.record.port,
                   running: favorite.running, url: favorite.localUrl, dep: nil)
        ForEach(favorite.deps) { dep in
          serviceRow(label: dep.label, port: dep.port, running: dep.running,
                     url: depUrl(dep), dep: dep)
        }
      }
    }
    .padding(12)
    .frame(minWidth: 270)
  }

  func depUrl(_ dep: DepStatus) -> URL? {
    guard dep.running, let port = dep.port, !dep.isDocker else { return nil }
    return serviceURL(port: port, scope: dep.scope)
  }

  func bulkButton(_ title: String, icon: String, tint: Color, action: ServiceAction) -> some View {
    Button {
      state.performAll(action, favorite)
      dismiss()
    } label: {
      Label(title, systemImage: icon)
        .font(.system(size: 11, weight: .medium))
        .frame(maxWidth: .infinity)
    }
    .buttonStyle(.bordered)
    .tint(tint)
    .controlSize(.small)
  }

  func serviceRow(label: String, port: Int?, running: Bool, url: URL?, dep: DepStatus?) -> some View {
    HStack(spacing: 6) {
      if dep != nil {
        Image(systemName: "arrow.turn.down.right")
          .font(.system(size: 8.5, weight: .semibold))
          .foregroundStyle(.tertiary)
      }
      Circle()
        .fill(running ? Color.green : Color.secondary.opacity(0.35))
        .frame(width: 6, height: 6)
      Text(label)
        .font(.system(size: 11.5))
        .lineLimit(1)
      if let port {
        Text(String(port))
          .font(.system(size: 10, weight: .medium, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
      Spacer(minLength: 14)
      if let url {
        rowIcon("safari", "在浏览器打开") { NSWorkspace.shared.open(url) }
      }
      rowIcon("play.fill", "启动", disabled: running) {
        state.perform(.start, favorite, dep: dep)
        dismiss()
      }
      rowIcon("arrow.clockwise", "重启", disabled: !running) {
        state.perform(.restart, favorite, dep: dep)
        dismiss()
      }
      rowIcon("stop.fill", "关闭", disabled: !running) {
        state.perform(.stop, favorite, dep: dep)
        dismiss()
      }
    }
    .padding(.vertical, 3)
  }

  func rowIcon(_ symbol: String, _ help: String, disabled: Bool = false,
               action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 10))
        .frame(width: 20, height: 18)
        .contentShape(Rectangle())
    }
    .buttonStyle(.borderless)
    .disabled(disabled)
    .help(help)
  }
}

// MARK: - 端口表

// HTTP 状态徽章（全局，表格与卡片行共用）：状态点 + 码 + 同色描边 capsule
func statusPill(_ text: String, color: Color) -> some View {
  HStack(spacing: 4) {
    Circle().fill(color).frame(width: 5, height: 5)
    Text(text)
      .font(.system(size: 10.5, weight: .semibold, design: .rounded))
      .monospacedDigit()
  }
  .foregroundStyle(color)
  .padding(.horizontal, 7)
  .padding(.vertical, 2)
  .background(color.opacity(0.12), in: Capsule())
  .overlay(Capsule().strokeBorder(color.opacity(0.22), lineWidth: 0.5))
}

@ViewBuilder
func httpPill(_ row: PortRow) -> some View {
  if let http = row.http {
    if http.status == "ok" {
      let code = http.statusCode ?? 0
      statusPill(String(code), color: code < 400 ? .green : .orange)
    } else {
      statusPill("无响应", color: .red)
    }
  } else {
    Text("--").font(.system(size: 10.5)).foregroundStyle(.tertiary)
  }
}

struct PortsTable: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    Group {
      if state.simpleMode {
        cardTable
      } else {
        fullTable
      }
    }
    .tableStyle(.inset(alternatesRowBackgrounds: true))
    .overlay {
      if state.visibleTree.isEmpty {
        emptyState.allowsHitTesting(false)
      }
    }
    .contextMenu(forSelectionType: PortRow.ID.self) { ids in
      if let row = rowFor(ids) {
        RowMenuItems(state: state, row: row)
      }
    } primaryAction: { ids in
      if let row = rowFor(ids), let url = row.localUrl {
        NSWorkspace.shared.open(url)
      } else if let row = rowFor(ids) {
        state.detailTarget = row
      }
    }
  }

  var emptyState: some View {
    VStack(spacing: 8) {
      Image(systemName: "antenna.radiowaves.left.and.right.slash")
        .font(.system(size: 30))
        .foregroundStyle(.tertiary)
      Text(state.simpleMode ? "没有带标题的网页服务" : "当前筛选下没有服务")
        .foregroundStyle(.secondary)
      if state.simpleMode {
        Text("切换到「完整」查看全部端口")
          .font(.caption)
          .foregroundStyle(.tertiary)
      }
    }
  }

  // 简单模式：单列 Table，行是卡片式布局。用 Table（NSTableView 后端）而非
  // ScrollView+LazyVStack —— 行复用 + 增量更新，每 2 秒刷新不再整列表重建，是流畅度关键。
  // 展开（children disclosure）、选中、双击（primaryAction）、右键全走 Table 内置。
  var cardTable: some View {
    Table(state.cardRows, selection: $state.tableSelection) {
      TableColumn("服务") { (row: PortRow) in
        PortCardRow(state: state, row: row)
      }
    }
  }

  var fullTable: some View {
    Table(state.visibleTree, children: \.children, selection: $state.tableSelection) {
      Group {
        TableColumn("") { (row: PortRow) in
          favStar(row)
        }
        .width(24)
        TableColumn("端口") { (row: PortRow) in
          portLabel(row)
        }
        .width(min: 56, ideal: 64)
        TableColumn("进程") { (row: PortRow) in
          procLabel(row)
        }
        .width(min: 100, ideal: 140)
        TableColumn("标题") { (row: PortRow) in
          titleWithGroupBadge(row)
        }
        .width(min: 100, ideal: 180)
        TableColumn("标签") { (row: PortRow) in
          Text(row.tags.joined(separator: " · "))
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .width(min: 70, ideal: 110)
        TableColumn("HTTP") { (row: PortRow) in
          httpLabel(row)
        }
        .width(min: 70, ideal: 84)
      }
      Group {
        TableColumn("PID") { (row: PortRow) in
          Text(String(row.pid)).font(.system(size: 11, design: .monospaced))
        }
        .width(min: 46, ideal: 56)
        TableColumn("CPU%") { (row: PortRow) in
          Text(String(format: "%.1f", row.cpu)).font(.system(size: 11, design: .monospaced))
        }
        .width(min: 44, ideal: 50)
        TableColumn("MEM%") { (row: PortRow) in
          Text(String(format: "%.1f", row.memory)).font(.system(size: 11, design: .monospaced))
        }
        .width(min: 44, ideal: 52)
        TableColumn("运行") { (row: PortRow) in
          Text(row.uptime).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .width(min: 60, ideal: 74)
        TableColumn("工作目录") { (row: PortRow) in
          Text(row.cwd)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.head)
            .help(row.cwd)
        }
        .width(min: 120, ideal: 220)
        TableColumn("命令") { (row: PortRow) in
          Text(row.command)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(row.command)
        }
        .width(min: 120, ideal: 260)
      }
    }
  }

  // MARK: 单元格

  func titleWithGroupBadge(_ row: PortRow) -> some View {
    HStack(spacing: 6) {
      if row.title.isEmpty {
        Text("—").font(.system(size: 12.5)).foregroundStyle(.tertiary)
      } else {
        Text(row.title).font(.system(size: 12.5)).lineLimit(1).help(row.title)
      }
      if let children = row.children, !children.isEmpty {
        Text("+\(children.count) 关联")
          .font(.system(size: 9.5, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: Capsule())
      }
    }
  }

  func favStar(_ row: PortRow) -> some View {
    Group {
      if row.serviceId != nil {
        Button {
          state.toggleFavorite(row)
        } label: {
          Image(systemName: state.isFavorite(row) ? "star.fill" : "star")
            .foregroundStyle(state.isFavorite(row) ? .yellow : .secondary)
            .font(.system(size: 11))
            .modifier(StarBounce(trigger: state.isFavorite(row)))
        }
        .buttonStyle(.plain)
        .help(state.isFavorite(row) ? "取消收藏" : "收藏到侧栏")
      }
    }
  }

  func portLabel(_ row: PortRow) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(row.port != nil ? Color.green : Color.secondary.opacity(0.4))
        .frame(width: 6, height: 6)
      Text(row.port.map(String.init) ?? "--")
        .font(.system(size: 11.5, weight: .semibold, design: .rounded))
        .monospacedDigit()
        .foregroundStyle(row.port != nil ? Color.primary : Color.secondary)
    }
    .help(row.port != nil ? "\(row.address):\(row.port!) · \(row.proto)" : "无监听端口")
  }

  func procLabel(_ row: PortRow) -> some View {
    HStack(spacing: 7) {
      StackBadge(tags: row.tags)
      Text(row.name).font(.system(size: 12.5)).lineLimit(1)
    }
  }

  func httpLabel(_ row: PortRow) -> some View {
    httpPill(row)
  }

  func rowFor(_ ids: Set<PortRow.ID>) -> PortRow? {
    guard let id = ids.first else { return nil }
    return state.flatVisibleRows.first { $0.id == id }
  }
}

// MARK: - 卡片式端口行（简单模式）

struct PortCardRow: View {
  // ponytail: 显式传入 state，不用 @EnvironmentObject —— 本视图渲染在 Table 单元格里，
  // 那里的 hosting 上下文不传播 environmentObject，用 @EnvironmentObject 会在解析时崩溃
  @ObservedObject var state: AppState
  let row: PortRow

  // 主标题：项目名 / 网页标题；噪声或缺失时 cleanSubtitle 兜底为目录名 / 命令 / 进程名
  var primaryLabel: String { cleanSubtitle(row) }
  // 副标题：进程名；当主标题已退回进程名（无有效项目名）时不重复显示
  var secondaryLabel: String { primaryLabel == row.name ? "" : row.name }

  var isChild: Bool { state.childRowIds.contains(row.id) }

  var body: some View {
    HStack(spacing: 9) {
      expandToggle
      favStar
      StackBadge(tags: row.tags)
      VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
          Text(primaryLabel)
            .font(.system(size: 12.5, weight: .medium))
            .lineLimit(1)
          if let port = row.port {
            Text(String(port))
              .font(.system(size: 10.5, weight: .medium, design: .rounded))
              .monospacedDigit()
              .foregroundStyle(.secondary)
          }
          if let children = row.children, !children.isEmpty {
            Text("+\(children.count) 关联")
              .font(.system(size: 9.5, weight: .semibold, design: .rounded))
              .foregroundStyle(.secondary)
              .padding(.horizontal, 5)
              .padding(.vertical, 1)
              .background(.quaternary, in: Capsule())
          }
        }
        if !secondaryLabel.isEmpty {
          Text(secondaryLabel)
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 10)
      httpPill(row)
      Text(row.uptime)
        .font(.system(size: 10.5, design: .monospaced))
        .foregroundStyle(.tertiary)
        .frame(minWidth: 54, alignment: .trailing)
    }
    .padding(.vertical, 5)
    .padding(.leading, isChild ? 22 : 0)   // 子行缩进
  }

  // 展开钮：有关联子服务时显示；热区 22×30，比 Table 系统三角大得多。
  // 子行显示 ⤷ 转角符号标出层级；其余留同宽占位，让收藏星标纵向对齐。
  @ViewBuilder
  var expandToggle: some View {
    if row.children != nil {
      Button {
        withAnimation(.easeInOut(duration: 0.16)) { state.toggleExpand(row) }
      } label: {
        Image(systemName: "chevron.right")
          .font(.system(size: 10, weight: .semibold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(state.expandedIds.contains(row.id) ? 90 : 0))
          .frame(width: 22, height: 30)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .help(state.expandedIds.contains(row.id) ? "收起关联服务" : "展开关联服务")
    } else if isChild {
      Image(systemName: "arrow.turn.down.right")
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.tertiary)
        .frame(width: 22, height: 30)
    } else {
      Color.clear.frame(width: 22, height: 1)
    }
  }

  @ViewBuilder
  var favStar: some View {
    if row.serviceId != nil {
      Button {
        state.toggleFavorite(row)
      } label: {
        Image(systemName: state.isFavorite(row) ? "star.fill" : "star")
          .font(.system(size: 11))
          .foregroundStyle(state.isFavorite(row) ? .yellow : .secondary)
      }
      .buttonStyle(.plain)
      .help(state.isFavorite(row) ? "取消收藏" : "收藏到侧栏")
    } else {
      Color.clear.frame(width: 11, height: 11)
    }
  }
}

// MARK: - 共享行操作（右键菜单 / 行内按钮 / 全局确认弹窗）

struct RowMenuItems: View {
  // ponytail: 显式传入 state —— 本视图渲染在 .contextMenu 里，那里不传播
  // environmentObject，用 @EnvironmentObject 会崩（同 PortCardRow）
  @ObservedObject var state: AppState
  let row: PortRow

  var body: some View {
    if let url = row.localUrl {
      Button("在浏览器打开") { NSWorkspace.shared.open(url) }
      Button("复制地址") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
      }
    }
    Button("详细信息") { state.detailTarget = row }
    Divider()
    if row.serviceId != nil {
      Button(state.isFavorite(row) ? "取消收藏" : "收藏到侧栏") { state.toggleFavorite(row) }
    }
    if canRestart(row) {
      Button("重启") { state.requestRestart(row) }
    }
    Divider()
    Button("结束进程", role: .destructive) { state.requestKill(row) }
  }
}

func canRestart(_ row: PortRow) -> Bool {
  !row.command.isEmpty && !row.cwd.isEmpty
    && row.pid != Int(ProcessInfo.processInfo.processIdentifier)
}

struct StarBounce: ViewModifier {
  let trigger: Bool

  func body(content: Content) -> some View {
    if #available(macOS 14.0, *) {
      content.symbolEffect(.bounce, value: trigger)
    } else {
      content
    }
  }
}

struct ActionDialogs: ViewModifier {
  @EnvironmentObject var state: AppState

  var killNeedsStrong: Bool {
    state.killTarget.map { state.needsStrongConfirmation($0) } ?? false
  }

  var strongKillBinding: Binding<Bool> {
    Binding(
      get: { state.killTarget != nil && killNeedsStrong },
      set: { if !$0 { state.killTarget = nil } }
    )
  }

  var normalKillBinding: Binding<Bool> {
    Binding(
      get: { state.killTarget != nil && !killNeedsStrong },
      set: { if !$0 { state.killTarget = nil } }
    )
  }

  var restartBinding: Binding<Bool> {
    Binding(
      get: { state.restartTarget != nil },
      set: { if !$0 { state.restartTarget = nil } }
    )
  }

  func body(content: Content) -> some View {
    content
      .sheet(item: $state.detailTarget) { row in
        DetailSheet(row: row)
      }
      .alert("结束 PID \(state.killTarget?.pid ?? 0)", isPresented: strongKillBinding) {
        Button("结束进程树", role: .destructive) { confirmStrongKill() }
        Button("取消", role: .cancel) { state.killTarget = nil }
      } message: {
        Text("高风险操作：将结束该进程及其全部 \(state.killTarget?.descendantPids.count ?? 0) 个子进程。")
      }
      .confirmationDialog("结束 \(state.killTarget?.name ?? "") (PID \(state.killTarget?.pid ?? 0))?",
                          isPresented: normalKillBinding, titleVisibility: .visible) {
        Button("温和结束 (SIGTERM)") { performKill(force: false) }
        Button("强制结束 (SIGKILL)", role: .destructive) { performKill(force: true) }
        Button("取消", role: .cancel) { state.killTarget = nil }
      }
      .alert("重启 \(state.restartTarget?.name ?? "") (PID \(state.restartTarget?.pid ?? 0))?",
             isPresented: restartBinding) {
        Button("重启", role: .destructive) { confirmRestart() }
        Button("取消", role: .cancel) { state.restartTarget = nil }
      } message: {
        Text("会先结束该进程及其子进程，再在原目录重新执行原命令。")
      }
  }

  func confirmStrongKill() {
    guard let row = state.killTarget else { return }
    state.kill(row, includeChildren: true, force: false)
    state.killTarget = nil
  }

  func performKill(force: Bool) {
    guard let row = state.killTarget else { return }
    state.kill(row, includeChildren: false, force: force)
    state.killTarget = nil
  }

  func confirmRestart() {
    guard let row = state.restartTarget else { return }
    state.restart(row)
    state.restartTarget = nil
  }
}

// MARK: - 已停止服务表

struct StoppedTable: View {
  @EnvironmentObject var state: AppState
  @State private var selection: Set<ServiceRecord.ID> = []

  var body: some View {
    Table(state.visibleStopped, selection: $selection) {
      TableColumn("状态") { _ in
        HStack(spacing: 5) {
          Circle().fill(Color.orange).frame(width: 6, height: 6)
          Text("已停止").font(.system(size: 10.5, weight: .medium)).foregroundStyle(.orange)
        }
      }
      .width(min: 56, ideal: 66)
      TableColumn("端口") { record in
        Text(record.port.map(String.init) ?? "--")
          .font(.system(size: 11.5, design: .monospaced))
      }
      .width(min: 50, ideal: 60)
      TableColumn("进程") { record in
        HStack(spacing: 6) {
          StackBadge(tags: record.tags ?? [])
          Text(record.name).lineLimit(1)
        }
      }
      .width(min: 100, ideal: 140)
      TableColumn("标题") { record in
        Text(record.title ?? "").lineLimit(1)
      }
      .width(min: 120, ideal: 220)
      TableColumn("最后在线") { record in
        Text(formatIso(record.lastSeenAt))
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      .width(min: 110, ideal: 140)
      TableColumn("工作目录") { record in
        Text(record.cwd)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
          .help(record.cwd)
      }
      .width(min: 120, ideal: 220)
      TableColumn("命令") { record in
        Text(record.command)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(record.command)
      }
      .width(min: 120, ideal: 260)
    }
    .contextMenu(forSelectionType: ServiceRecord.ID.self) { ids in
      if let record = recordFor(ids) {
        Button("启动") { state.startStopped(record) }
        Button("收藏到侧栏") {
          Monitor.setFavorite(id: record.id, favorite: true)
          state.toast("已收藏到侧栏")
          Task { await state.refresh() }
        }
        Divider()
        Button("移除记录", role: .destructive) { state.forget(record) }
      }
    } primaryAction: { ids in
      if let record = recordFor(ids) {
        state.startStopped(record)
      }
    }
  }

  func recordFor(_ ids: Set<ServiceRecord.ID>) -> ServiceRecord? {
    guard let id = ids.first else { return nil }
    return state.visibleStopped.first { $0.id == id }
  }

  func formatIso(_ iso: String?) -> String {
    guard let iso else { return "--" }
    // 旧版（JS toISOString）带毫秒，新版不带，两种都解析
    let withMs = ISO8601DateFormatter()
    withMs.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    guard let date = withMs.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else { return "--" }
    let formatter = DateFormatter()
    formatter.dateFormat = "M/d HH:mm"
    return formatter.string(from: date)
  }
}

// MARK: - 详情

struct DetailSheet: View {
  @Environment(\.dismiss) private var dismiss
  let row: PortRow

  var facts: [(String, String)] {
    var list: [(String, String)] = []
    if let port = row.port {
      list.append(("端口", "\(row.address):\(port) · \(row.proto)"))
      list.append(("范围", row.scope == "all" ? "全部地址" : row.scope == "loopback" ? "localhost" : "本机地址"))
    }
    list.append(("PID", String(row.pid)))
    if let parentPid = row.parentPid { list.append(("父 PID", String(parentPid))) }
    list.append(("进程", row.name))
    list.append(("用户", row.user))
    list.append(("CPU%", String(format: "%.1f", row.cpu)))
    list.append(("MEM%", String(format: "%.1f", row.memory)))
    if !row.started.isEmpty { list.append(("启动", row.started)) }
    if !row.uptime.isEmpty { list.append(("运行", row.uptime)) }
    if !row.descendantPids.isEmpty {
      list.append(("子进程", "\(row.descendantPids.count) 个: \(row.descendantPids.map(String.init).joined(separator: ", "))"))
    }
    if let http = row.http {
      list.append(("HTTP", "\(http.status)\(http.statusCode.map { " \($0)" } ?? "")"))
      if let latency = http.latencyMs { list.append(("延迟", "\(latency) ms")) }
      if !http.title.isEmpty { list.append(("标题", http.title)) }
    }
    if !row.tags.isEmpty { list.append(("标签", row.tags.joined(separator: ", "))) }
    if !row.cwd.isEmpty { list.append(("工作目录", row.cwd)) }
    if !row.command.isEmpty { list.append(("命令", row.command)) }
    return list
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        VStack(alignment: .leading, spacing: 2) {
          Text("详细信息").font(.caption).foregroundStyle(.secondary)
          Text(row.port != nil ? "\(row.name) · 端口 \(row.port!)" : "\(row.name) · PID \(row.pid)")
            .font(.system(size: 15, weight: .semibold, design: .monospaced))
        }
        Spacer()
        Button("关闭") { dismiss() }
          .keyboardShortcut(.cancelAction)
      }
      ScrollView {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
          ForEach(facts, id: \.0) { fact in
            GridRow {
              Text(fact.0)
                .foregroundStyle(.secondary)
                .frame(width: 70, alignment: .leading)
              Text(fact.1)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }
      }
      .frame(maxHeight: 320)
    }
    .padding(20)
    .frame(width: 500)
  }
}
