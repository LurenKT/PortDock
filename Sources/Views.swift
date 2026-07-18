import Charts
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

/* 窗口可见性注入（windowVisible environment + trackWindowVisibility）已随
   呼吸动画一起移除：常驻动画不复存在，没有消费者。若将来重新加常驻动画，
   必须一并恢复按可见性摘除动画视图的机制（不可见时动画持续烧 CPU，实测 30%/14% 底噪）。

   滚动检测统一走 AppState 里的 NSEvent 滚轮监听（app 级，全窗口覆盖）。
   视图级方案都被否掉了：NSViewRepresentable 会弄丢工具栏安全区内边距
   （内容顶端永远滚不出来），GeometryReader 偏移量 preference 实测漏报。 */

// MARK: - 运行状态点（运行中带呼吸脉冲）

struct StatusDot: View {
  let running: Bool

  // 静态光环，不再用 TimelineView 呼吸动画：30fps 的常驻动画会把 ProMotion
  // 窗口的刷新率投票压到 30~40Hz，整个窗口滚动跟着只有 30 帧
  var body: some View {
    Circle()
      .fill(running ? Color.green : Color.secondary.opacity(0.4))
      .frame(width: 7, height: 7)
      .background {
        if running {
          Circle()
            .stroke(Color.green.opacity(0.35), lineWidth: 1.5)
            .scaleEffect(1.7)
        }
      }
  }
}

// MARK: - 主结构

struct ContentView: View {
  @EnvironmentObject var state: AppState
  @AppStorage(langKey) private var lang = "system"

  var body: some View {
    NavigationSplitView {
      SidebarView()
        .navigationSplitViewColumnWidth(min: 190, ideal: 220)
    } detail: {
      MainView()
    }
    .searchable(text: $state.searchText, placement: .toolbar, prompt: t("端口、PID、命令", "Port, PID, command"))
    .toolbar {
      ToolbarItem(placement: .navigation) {
        Picker(t("显示模式", "Display mode"), selection: $state.simpleMode) {
          Text(t("简单", "Simple")).tag(true)
          Text(t("完整", "Full")).tag(false)
        }
        .pickerStyle(.segmented)
      }
      ToolbarItemGroup {
        if let row = state.selectedRow {
          if let url = row.localUrl {
            Button {
              NSWorkspace.shared.open(url)
            } label: {
              Label(t("打开", "Open"), systemImage: "safari")
            }
            .help(t("在浏览器打开", "Open in browser"))
          }
          Button {
            state.detailTarget = row
          } label: {
            Label(t("详情", "Details"), systemImage: "info.circle")
          }
          .help(t("详细信息", "Details"))
          if canRestart(row) {
            Button {
              state.requestRestart(row)
            } label: {
              Label(t("重启", "Restart"), systemImage: "arrow.clockwise.circle")
            }
            .help(t("重启该服务", "Restart this service"))
          }
          Button {
            state.requestKill(row)
          } label: {
            Label(t("结束", "Kill"), systemImage: "stop.circle")
          }
          .help(t("结束进程", "Kill process"))
        }
        Button {
          Task { await state.refresh(manual: true) }
        } label: {
          if state.isRefreshing {
            ProgressView()
              .controlSize(.small)
          } else {
            Label(t("刷新", "Refresh"), systemImage: "arrow.clockwise")
          }
        }
        .keyboardShortcut("r", modifiers: .command)
        .help(t("刷新 (⌘R)", "Refresh (⌘R)"))
      }
    }
    .overlay(alignment: .bottom) {
      // 动画只作用于 toast 自身。原来 .animation(value:) 挂在整棵树上，
      // 每次 toast 出现/消失都对全界面做动画遍历，撞上快照刷新时全表乱动、操作掉帧
      ZStack {
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
    }
    .modifier(ActionDialogs())
    .id(lang)   // 语言切换时整树重建，t() 全部重取词
  }
}

// MARK: - 侧栏

/// 收藏行的实时位置上报：自绘拖拽排序靠指针落在哪行的 frame 判定目标槽位
private struct FavRowFramesKey: PreferenceKey {
  static var defaultValue: [String: CGRect] = [:]
  static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
    value.merge(nextValue()) { $1 }
  }
}

struct SidebarView: View {
  @EnvironmentObject var state: AppState
  @AppStorage(lanShareKey) private var lanShare = false
  @State private var rowFrames: [String: CGRect] = [:]
  @State private var draggingFavorite: String?

  var body: some View {
    List(selection: $state.selection) {
      Section {
        Label("Home", systemImage: "house")
          .tag(SidebarSelection.home)
      }

      Section(t("收藏", "Favorites")) {
        if state.snapshot.favorites.isEmpty {
          Text(t("在列表中右键收藏项目，\n停止后可从这里一键启动。", "Right-click a service to favorite it.\nStart stopped favorites from here in one click."))
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        // 系统 List.onMove 是 AppKit 拖放会话，行上任何 SwiftUI 手势（tap/simultaneous）
        // 都会抢走 mouseDown 让文字区拖不动（2026-07-17/18 三次用户实测）。
        // 改为自绘拖拽：DragGesture 驱动 + 行 frame 上报判定悬停槽位，tap 与其共存已在菜单栏行实证
        ForEach(state.snapshot.favorites) { favorite in
          SidebarFavoriteRow(state: state, favorite: favorite)
            .opacity(draggingFavorite == favorite.id ? 0.55 : 1)
            .background(GeometryReader { geo in
              Color.clear.preference(key: FavRowFramesKey.self, value: [favorite.id: geo.frame(in: .global)])
            })
            .gesture(favoriteDrag(favorite))
        }
      }

      Section(t("分类", "Categories")) {
        sidebarRow(.all, label: t("全部", "All"), icon: "square.grid.2x2",
                   count: state.snapshot.ports.count + state.snapshot.agentProcesses.count)
        sidebarRow(.category(.web), label: "Web", icon: "globe", count: state.snapshot.count(of: .web))
        sidebarRow(.category(.agent), label: "Agent", icon: "sparkles", count: state.snapshot.count(of: .agent))
        sidebarRow(.category(.infra), label: t("基础设施", "Infra"), icon: "cylinder.split.1x2", count: state.snapshot.count(of: .infra))
        sidebarRow(.category(.other), label: t("其它", "Other"), icon: "shippingbox", count: state.snapshot.count(of: .other))
        sidebarRow(.stopped, label: t("已停止", "Stopped"), icon: "moon.zzz", count: state.snapshot.stopped.count)
        if !state.ignoredKeys.isEmpty {
          sidebarRow(.ignored, label: t("已忽略", "Ignored"), icon: "eye.slash", count: state.ignoredLiveCount)
        }
      }
    }
    .listStyle(.sidebar)
    .onPreferenceChange(FavRowFramesKey.self) { rowFrames = $0 }
    .safeAreaInset(edge: .bottom) {
      VStack(alignment: .leading, spacing: 3) {
        Toggle(isOn: $lanShare) {
          Label(t("局域网共享", "LAN Share"), systemImage: "wifi")
            .font(.system(size: 11.5))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        if lanShare {
          Text(lanIPv4().map { t("打开链接用 ", "Links use ") + $0 } ?? t("未找到局域网地址", "No LAN address found"))
            .font(.system(size: 9.5, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.leading, 2)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(.bar)
      .help(t("开启后，打开网页用本机局域网 IP，同一网络的手机/电脑也能访问；仅监听 127.0.0.1 的服务仍用 localhost", "When on, links use the Mac's LAN IP so phones and computers on the same network can open them; services bound to 127.0.0.1 keep using localhost"))
    }
  }

  private func favoriteDrag(_ favorite: FavoriteItem) -> some Gesture {
    DragGesture(minimumDistance: 5, coordinateSpace: .global)
      .onChanged { value in
        draggingFavorite = favorite.id
        guard let target = rowFrames.first(where: {
          $0.key != favorite.id && $0.value.minY <= value.location.y && value.location.y < $0.value.maxY
        })?.key else { return }
        state.reorderFavorite(dragged: favorite.id, over: target)
      }
      .onEnded { _ in
        draggingFavorite = nil
        state.commitFavoriteOrder()
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
      }
    } icon: {
      Image(systemName: icon)
    }
    .tag(value)
  }
}

/// 侧栏收藏行：点击弹出与 Home 卡片同款的操作面板（启动/重启/关闭/详情），
/// 不再是「点了就开浏览器/启动」——那套快捷路径保留在菜单栏行的整行点击上
struct SidebarFavoriteRow: View {
  // ponytail: 显式传 state —— popover 是断裂 hosting 上下文（同 FavoriteCard）
  @ObservedObject var state: AppState
  let favorite: FavoriteItem
  @State private var showActions = false

  var body: some View {
    // 不用 Button 包整行：macOS 上按钮的 mouse tracking 会吞掉拖拽起始事件，
    // List 的 .onMove 拖拽排序收不到；.onTapGesture 独占热区，把可拖区域挤到
    // 只剩行内边距几像素（均 2026-07-17 用户实测失效）。
    // 整行点击出面板用 simultaneousGesture：与 List 拖拽并行识别不抢热区，
    // 指针位移超阈值时 tap 自动失败让位给拖拽
    HStack(spacing: 7) {
      StackBadge(tags: favorite.record.tags ?? [])
      Text(favorite.title.isEmpty ? t("未命名", "Untitled") : favorite.title)
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
      // 面板入口收进这个按钮：行身上不挂任何点按手势。onTapGesture 会独占整行热区、
      // 把 List 拖拽排序挤到只剩行内边距几像素（2026-07-17 用户实测「可拖区域太小」），
      // 行体零手势后整行都是拖拽区（无手势区域可拖已被用户成功拖拽实证）
      Button {
        showActions = true
      } label: {
        Image(systemName: "ellipsis.circle")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.borderless)
      .help(t("管理：启动 / 重启 / 关闭 / 详情", "Manage: start / restart / stop / details"))
    }
    .contentShape(Rectangle())
    .onTapGesture { showActions = true }
    .help(t("点击管理 · 拖拽排序", "Click to manage · drag to reorder") + "\n\(favorite.record.command)")
    .popover(isPresented: $showActions, arrowEdge: .trailing) {
      FavoriteActionPanel(state: state, favorite: favorite)
    }
    .contextMenu {
      if let url = favorite.localUrl {
        Button(t("在浏览器打开", "Open in browser")) { NSWorkspace.shared.open(url) }
      }
      if favorite.running {
        Button(t("详细信息", "Details")) { state.showDetails(favoritePort: favorite.livePort) }
        Divider()
        Button(t("重启所有", "Restart all")) { state.performAll(.restart, favorite) }
        Button(t("关闭所有", "Stop all")) { state.performAll(.stop, favorite) }
      } else {
        Divider()
        Button(t("启动（含依赖）", "Start (with deps)")) { state.performAll(.start, favorite) }
      }
      Divider()
      Button(t("取消收藏", "Unfavorite")) { state.unfavorite(id: favorite.id) }
    }
  }
}

// MARK: - 主区

struct MainView: View {
  @EnvironmentObject var state: AppState

  var body: some View {
    ZStack {
      if let target = state.detailTarget {
        DetailPage(initialRow: target)
          .id(target.pid)   // 换目标时重建，滚动位置/图表选择不残留
          .transition(.opacity)
      } else {
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
    }
    .animation(.easeOut(duration: 0.18), value: state.selection)
    .animation(.easeOut(duration: 0.18), value: state.detailTarget == nil)
    .onChange(of: state.selection) { _, _ in state.detailTarget = nil }   // 点侧栏 = 离开详情页
  }
}

// MARK: - Home

/* 非惰性自适应网格。LazyVGrid 在滚动途中内容更新时会丢渲染——5 张收藏卡
   只画出 1 张、内容高度塌缩、顶部“滚不上去”（2026-07-16 真机截图实锤）。
   首页内容量级很小，直接全量布局：等宽列、列数按最小列宽自适应。 */
struct AdaptiveGrid: Layout {
  var minWidth: CGFloat
  var spacing: CGFloat = 12

  private func columns(for width: CGFloat) -> Int {
    max(1, Int((width + spacing) / (minWidth + spacing)))
  }

  private func rowHeights(_ subviews: Subviews, cols: Int, cellWidth: CGFloat) -> [CGFloat] {
    stride(from: 0, to: subviews.count, by: cols).map { start in
      subviews[start..<min(start + cols, subviews.count)]
        .map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }
        .max() ?? 0
    }
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? minWidth
    let cols = columns(for: width)
    let cellWidth = (width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
    let heights = rowHeights(subviews, cols: cols, cellWidth: cellWidth)
    let total = heights.reduce(0, +) + spacing * CGFloat(max(0, heights.count - 1))
    return CGSize(width: width, height: total)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let cols = columns(for: bounds.width)
    let cellWidth = (bounds.width - spacing * CGFloat(cols - 1)) / CGFloat(cols)
    var y = bounds.minY
    for start in stride(from: 0, to: subviews.count, by: cols) {
      let row = subviews[start..<min(start + cols, subviews.count)]
      let height = row
        .map { $0.sizeThatFits(ProposedViewSize(width: cellWidth, height: nil)).height }
        .max() ?? 0
      for (column, view) in row.enumerated() {
        view.place(
          at: CGPoint(x: bounds.minX + CGFloat(column) * (cellWidth + spacing), y: y),
          proposal: ProposedViewSize(width: cellWidth, height: height))
      }
      y += height + spacing
    }
  }
}

/// 统一卡片表面：抬起的控件底色 + 极细描边 + 轻阴影，hover 时描边加强。
/// hover 只改描边不改阴影——阴影半径变化要整卡重新模糊，单次翻转实测 112~125ms
extension View {
  func cardSurface(cornerRadius: CGFloat = 12, elevated: Bool = false) -> some View {
    self
      .background(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .fill(Color(nsColor: .controlBackgroundColor)))
      .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        .strokeBorder(Color.primary.opacity(elevated ? 0.18 : 0.08), lineWidth: 1))
      // 不加 .shadow：高斯模糊阴影让 Home 图层树走不了并发滚动快速路径，
      // 每帧都要主线程同步绘制，整页滚动只有 30 帧（2026-07-16 A/B 实测定罪）
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
  // 行上的操作面板打开期间冻结排行：选中的行不随刷新消失/跳位，关闭后恢复实时
  @State private var pinnedTopCpu: [PortRow]?

  var topCpuRows: [PortRow] { pinnedTopCpu ?? liveTopCpuRows }

  var liveTopCpuRows: [PortRow] {
    var pool = state.snapshot.ports + state.snapshot.agentProcesses
    pool = pool.filter { !state.isIgnored($0) }
    // 跟随简单/完整模式：简单模式只看有标题的项目服务
    if state.simpleMode {
      pool = pool.filter { !$0.title.isEmpty }
    }
    // 按进程树聚合排行：同 pid 多端口只留一行；
    // 已被别的行进程树包含的（uvicorn reload 子进程也监听同端口）不再单独上榜
    var seenPids = Set<Int>()
    pool = pool.filter { seenPids.insert($0.pid).inserted }
    let covered = Set(pool.flatMap(\.descendantPids))
    pool = pool.filter { !covered.contains($0.pid) }
    return Array(pool.sorted { $0.treeCpu > $1.treeCpu }.prefix(5)).filter { $0.treeCpu > 0.05 }
  }

  /// 列表里最高的进程树 CPU 总和，用作强度条的满格基准
  var maxCpu: Double { max(topCpuRows.first?.treeCpu ?? 0, 0.1) }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        if !state.snapshot.favorites.isEmpty {
          section(t("收藏项目", "Favorites"), count: state.snapshot.favorites.count) {
            AdaptiveGrid(minWidth: 220) {
              ForEach(state.snapshot.favorites) { favorite in
                FavoriteCard(favorite: favorite)
              }
            }
          }
        }

        section(t("系统", "System")) {
          // 自适应网格：等宽等高、铺满整行，不再让卡片挤在左边留白
          AdaptiveGrid(minWidth: 148) {
            gaugeTile(
              "CPU",
              fraction: state.snapshot.system.cpuUsage,
              value: state.snapshot.system.cpuUsage.map { String(format: "%.0f", $0 * 100) } ?? "--",
              unit: "%"
            )
            gaugeTile(
              t("内存", "Memory"),
              fraction: state.snapshot.system.memUsage,
              value: String(format: "%.1f", Double(state.snapshot.system.memUsedBytes) / 1_073_741_824),
              unit: String(format: "/ %.0f GB", Double(state.snapshot.system.memTotalBytes) / 1_073_741_824)
            )
            countTile(t("监听端口", "Listening"), value: state.snapshot.ports.count,
                      systemImage: "antenna.radiowaves.left.and.right", tint: .green)
            countTile(t("HTTP 可访问", "HTTP OK"), value: state.snapshot.httpOkCount,
                      systemImage: "checkmark.seal", tint: .blue)
            countTile(t("已停止", "Stopped"), value: state.snapshot.stopped.count,
                      systemImage: "moon.zzz", tint: .orange)
          }
        }

        if !topCpuRows.isEmpty {
          section(t("CPU 占用最高的服务", "Top CPU services")) {
            VStack(spacing: 0) {
              ForEach(Array(topCpuRows.enumerated()), id: \.element.id) { index, row in
                TopCpuRowView(row: row, fraction: row.treeCpu / maxCpu) { pinning in
                  pinnedTopCpu = pinning ? topCpuRows : nil
                }
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
        // 不给每 3 秒必变的数据挂动画：numericText/圆环动画每轮刷新都拖出
        // 几百 ms 的全窗口布局尾巴，是操作期 50~70ms 卡帧的实测来源
        ZStack {
          Circle().stroke(.quaternary, lineWidth: 3)
          Circle()
            .trim(from: 0, to: f)
            .stroke(tint.gradient, style: StrokeStyle(lineWidth: 3, lineCap: .round))
            .rotationEffect(.degrees(-90))
        }
        .frame(width: 18, height: 18)
      }
      Spacer(minLength: 8)
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value)
          .font(.system(size: 23, weight: .semibold, design: .rounded))
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
  let fraction: Double   // 相对列表最高进程树 CPU 的比例，决定强度条长度
  var onPin: (Bool) -> Void = { _ in }   // 面板开/关时通知父级冻结/恢复排行
  @State private var showActions = false

  var tint: Color {
    row.treeCpu > 50 ? .red : row.treeCpu > 15 ? .orange : .accentColor
  }

  /// 该行所属的收藏项目组：自己是收藏本体，或是收藏学到的依赖成员
  var matchedFavorite: FavoriteItem? {
    state.snapshot.favorites.first { favorite in
      (row.serviceId != nil && favorite.record.id == row.serviceId)
        || (row.port != nil && favorite.running && favorite.livePort == row.port)
        || (row.port != nil && favorite.deps.contains { $0.port == row.port })
    }
  }

  /// 树明细：自身 + 活跃子孙（按 CPU 降序）；空闲的（<0.05%）只报数量
  var activeProcs: [TreeProc] {
    ([TreeProc(pid: row.pid, name: row.name, cpu: row.cpu)] + row.treeProcs)
      .filter { $0.cpu > 0.05 }
      .sorted { $0.cpu > $1.cpu }
  }
  var idleCount: Int { 1 + row.treeProcs.count - activeProcs.count }

  var body: some View {
    VStack(spacing: 0) {
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
        // 强度条：条长按相对最高占用，颜色按绝对占用（低占用保持平静）。
        // 总宽固定 60pt，直接算宽度，不用 GeometryReader（每轮刷新都触发布局）
        ZStack(alignment: .leading) {
          Capsule().fill(.quaternary)
          Capsule()
            .fill(tint.gradient)
            .frame(width: max(3, 60 * min(1, fraction)))
        }
        .frame(width: 60, height: 5)
        Text(String(format: "%.1f%%", row.treeCpu))
          .font(.system(size: 11.5, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .frame(width: 46, alignment: .trailing)
      }
      // 进程树明细：多进程服务列出每个成员的占用，右侧总和与上面的总占用对得上
      if !row.treeProcs.isEmpty {
        VStack(spacing: 2) {
          ForEach(activeProcs) { proc in
            HStack(spacing: 6) {
              Text(proc.name)
                .lineLimit(1)
              Text(String(proc.pid))
                .foregroundStyle(.tertiary)
              Spacer(minLength: 8)
              Text(String(format: "%.1f%%", proc.cpu))
                .monospacedDigit()
                .frame(width: 46, alignment: .trailing)
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
          }
          if idleCount > 0 {
            HStack {
              Text(t("+ \(idleCount) 个空闲进程", "+ \(idleCount) idle processes"))
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
              Spacer()
            }
          }
        }
        .padding(.leading, 40)
        .padding(.top, 5)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .contentShape(Rectangle())
    .onTapGesture {
      // 属于某个收藏项目组的行 → 弹和收藏卡片同款的操作面板；其余走详情
      if matchedFavorite != nil {
        showActions = true
      } else {
        state.detailTarget = row
      }
    }
    .popover(isPresented: $showActions, arrowEdge: .bottom) {
      // ponytail: 显式传 state —— popover 是断裂 hosting 上下文，
      // 独立 View 用 @EnvironmentObject 会崩（同 FavoriteCard）
      if let favorite = matchedFavorite {
        FavoriteActionPanel(state: state, favorite: favorite)
      }
    }
    .onChange(of: showActions) { _, open in onPin(open) }
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

  var starting: Bool { state.startingIds.contains(favorite.id) }

  var body: some View {
    Button {
      showActions = true
    } label: {
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          StackBadge(tags: favorite.record.tags ?? [])
          Text(favorite.title.isEmpty ? t("未命名", "Untitled") : favorite.title)
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
            Text(t("端口", "Port") + " \(String(port))")
          }
          if starting {
            Text(t("启动中…", "Starting…"))
          } else if favorite.running {
            if !favorite.liveUptime.isEmpty {
              Text(t("已运行", "Up") + " \(favorite.liveUptime)")
            }
          } else {
            Text(favorite.deps.isEmpty ? t("已停止 · 点击启动", "Stopped · click to start") : t("已停止 · 点击连带依赖一起启动", "Stopped · click to start with dependencies"))
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
    }
    .buttonStyle(.plain)
    .disabled(starting)
    .onHover { value in
      // 滚动时悬停进/出都不处理：卡片扫过指针的连环悬停翻转实测每次 112~125ms，
      // 是滚动帧率低的直接来源；弹簧缩放+阴影动画也一并移除
      guard !state.liveScrolling else { return }
      hovering = value
    }
    .help(t("点击管理：启动 / 重启 / 关闭", "Click to manage: start / restart / stop"))
    .popover(isPresented: $showActions, arrowEdge: .bottom) {
      // ponytail: 显式传 state —— popover 是断裂 hosting 上下文，
      // 独立 View 用 @EnvironmentObject 会崩（同 PortCardRow）
      FavoriteActionPanel(state: state, favorite: favorite)
    }
    .contextMenu {
      if let url = favorite.localUrl {
        Button(t("在浏览器打开", "Open in browser")) { NSWorkspace.shared.open(url) }
      }
      Button(t("取消收藏", "Unfavorite")) { state.unfavorite(id: favorite.id) }
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
        Label(favorite.localUrl.map { t("打开 ", "Open ") + $0.absoluteString } ?? t("未运行，无法打开", "Not running"),
              systemImage: "safari")
          .font(.system(size: 11.5, weight: .medium))
          .lineLimit(1)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.borderedProminent)
      .controlSize(.small)
      .disabled(favorite.localUrl == nil)
      HStack(spacing: 8) {
        bulkButton(t("启动所有", "Start all"), icon: "play.fill", tint: .green, action: .start)
        bulkButton(t("重启所有", "Restart all"), icon: "arrow.clockwise", tint: .orange, action: .restart)
        bulkButton(t("关闭所有", "Stop all"), icon: "stop.fill", tint: .red, action: .stop)
      }
      Divider()
      VStack(alignment: .leading, spacing: 2) {
        serviceRow(label: favorite.title.isEmpty ? t("未命名", "Untitled") : favorite.title,
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
    return serviceURL(port: port, scope: dep.scope, path: dep.uiPath)
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
        rowIcon("safari", t("在浏览器打开", "Open in browser")) { NSWorkspace.shared.open(url) }
      }
      rowIcon("info.circle", t("详细信息", "Details"), disabled: !running) {
        state.showDetails(favoritePort: port)
        dismiss()
      }
      rowIcon("play.fill", t("启动", "Start"), disabled: running) {
        state.perform(.start, favorite, dep: dep)
        dismiss()
      }
      rowIcon("arrow.clockwise", t("重启", "Restart"), disabled: !running) {
        state.perform(.restart, favorite, dep: dep)
        dismiss()
      }
      rowIcon("stop.fill", t("关闭", "Stop"), disabled: !running) {
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
      statusPill(t("无响应", "down"), color: .red)
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
      Text(state.simpleMode ? t("没有带标题的网页服务", "No titled web services") : t("当前筛选下没有服务", "No services in this filter"))
        .foregroundStyle(.secondary)
      if state.simpleMode {
        Text(t("切换到「完整」查看全部端口", "Switch to \"Full\" to see all ports"))
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
      TableColumn(t("服务", "Service")) { (row: PortRow) in
        PortCardRow(state: state, row: row)
      }
    }
  }

  /* 列排序的型别约束（真机 typecheck 实测，macOS 14 SDK）：
     - builder 单层最多 10 列，12 列必须分组；
     - Group 内可排序列与普通列混放会把 Sort 推断成 Never 而编译失败；
     - 但外层扁平位置可以混放。→ 可排序列进同质 Group，普通列留在外层 */
  var fullTable: some View {
    Table(state.visibleTree, children: \.children,
          selection: $state.tableSelection, sortOrder: $state.tableSort) {
      TableColumn("") { (row: PortRow) in
        favStar(row)
      }
      .width(24)
      Group {
        TableColumn(t("端口", "Port"), value: \.sortPort) { (row: PortRow) in
          portLabel(row)
        }
        .width(min: 56, ideal: 64)
        TableColumn(t("进程", "Process"), value: \.name) { (row: PortRow) in
          procLabel(row)
        }
        .width(min: 100, ideal: 140)
        TableColumn(t("标题", "Title"), value: \.title) { (row: PortRow) in
          titleWithGroupBadge(row)
        }
        .width(min: 100, ideal: 180)
      }
      TableColumn(t("标签", "Tags")) { (row: PortRow) in
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
      Group {
        TableColumn("PID", value: \.pid) { (row: PortRow) in
          Text(String(row.pid)).font(.system(size: 11, design: .monospaced))
        }
        .width(min: 46, ideal: 56)
        TableColumn("CPU%", value: \.cpu) { (row: PortRow) in
          Text(String(format: "%.1f", row.cpu)).font(.system(size: 11, design: .monospaced))
        }
        .width(min: 44, ideal: 50)
        TableColumn("MEM%", value: \.memory) { (row: PortRow) in
          Text(String(format: "%.1f", row.memory)).font(.system(size: 11, design: .monospaced))
        }
        .width(min: 44, ideal: 52)
        TableColumn(t("运行", "Uptime"), value: \.sortUptime) { (row: PortRow) in
          Text(row.uptime).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
        }
        .width(min: 60, ideal: 74)
      }
      TableColumn(t("工作目录", "Directory")) { (row: PortRow) in
        Text(row.cwd)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
          .help(row.cwd)
      }
      .width(min: 120, ideal: 220)
      TableColumn(t("命令", "Command")) { (row: PortRow) in
        Text(row.command)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .help(row.command)
      }
      .width(min: 120, ideal: 260)
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
        Text(t("+\(children.count) 关联", "+\(children.count) linked"))
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
        .help(state.isFavorite(row) ? t("取消收藏", "Unfavorite") : t("收藏到侧栏", "Add to sidebar"))
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
    .help(row.port != nil ? "\(row.address):\(row.port!) · \(row.proto)" : t("无监听端口", "No listening port"))
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
            Text(t("+\(children.count) 关联", "+\(children.count) linked"))
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
      .help(state.expandedIds.contains(row.id) ? t("收起关联服务", "Collapse linked") : t("展开关联服务", "Expand linked"))
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
      .help(state.isFavorite(row) ? t("取消收藏", "Unfavorite") : t("收藏到侧栏", "Add to sidebar"))
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
      Button(t("在浏览器打开", "Open in browser")) { NSWorkspace.shared.open(url) }
      Button(t("复制地址", "Copy URL")) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url.absoluteString, forType: .string)
      }
    }
    Button(t("详细信息", "Details")) { state.detailTarget = row }
    Divider()
    if row.serviceId != nil {
      Button(state.isFavorite(row) ? t("取消收藏", "Unfavorite") : t("收藏到侧栏", "Add to sidebar")) { state.toggleFavorite(row) }
    }
    Button(state.isIgnored(row) ? t("取消忽略", "Unignore") : t("忽略此服务", "Ignore this service")) { state.toggleIgnore(row) }
    if canRestart(row) {
      Button(t("重启", "Restart")) { state.requestRestart(row) }
    }
    Divider()
    Button(t("结束进程", "Kill process"), role: .destructive) { state.requestKill(row) }
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
      .alert(t("结束 PID", "Kill PID") + " \(state.killTarget?.pid ?? 0)", isPresented: strongKillBinding) {
        Button(t("结束进程树", "Kill process tree"), role: .destructive) { confirmStrongKill() }
        Button(t("取消", "Cancel"), role: .cancel) { state.killTarget = nil }
      } message: {
        Text(t("高风险操作：将结束该进程及其全部 \(state.killTarget?.descendantPids.count ?? 0) 个子进程。", "High risk: this kills the process and all \(state.killTarget?.descendantPids.count ?? 0) of its children."))
      }
      .confirmationDialog(t("结束", "Kill") + " \(state.killTarget?.name ?? "") (PID \(state.killTarget?.pid ?? 0))?",
                          isPresented: normalKillBinding, titleVisibility: .visible) {
        Button(t("温和结束 (SIGTERM)", "Terminate (SIGTERM)")) { performKill(force: false) }
        Button(t("强制结束 (SIGKILL)", "Force kill (SIGKILL)"), role: .destructive) { performKill(force: true) }
        Button(t("取消", "Cancel"), role: .cancel) { state.killTarget = nil }
      }
      .alert(t("重启", "Restart") + " \(state.restartTarget?.name ?? "") (PID \(state.restartTarget?.pid ?? 0))?",
             isPresented: restartBinding) {
        Button(t("重启", "Restart"), role: .destructive) { confirmRestart() }
        Button(t("取消", "Cancel"), role: .cancel) { state.restartTarget = nil }
      } message: {
        Text(t("会先结束该进程及其子进程，再在原目录重新执行原命令。", "Kills the process and its children, then re-runs the original command in its directory."))
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
      TableColumn(t("状态", "Status")) { _ in
        HStack(spacing: 5) {
          Circle().fill(Color.orange).frame(width: 6, height: 6)
          Text(t("已停止", "Stopped")).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.orange)
        }
      }
      .width(min: 56, ideal: 66)
      TableColumn(t("端口", "Port")) { record in
        Text(record.port.map(String.init) ?? "--")
          .font(.system(size: 11.5, design: .monospaced))
      }
      .width(min: 50, ideal: 60)
      TableColumn(t("进程", "Process")) { record in
        HStack(spacing: 6) {
          StackBadge(tags: record.tags ?? [])
          Text(record.name).lineLimit(1)
        }
      }
      .width(min: 100, ideal: 140)
      TableColumn(t("标题", "Title")) { record in
        Text(record.title ?? "").lineLimit(1)
      }
      .width(min: 120, ideal: 220)
      TableColumn(t("最后在线", "Last seen")) { record in
        Text(formatIso(record.lastSeenAt))
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
      }
      .width(min: 110, ideal: 140)
      TableColumn(t("工作目录", "Directory")) { record in
        Text(record.cwd)
          .font(.system(size: 11, design: .monospaced))
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.head)
          .help(record.cwd)
      }
      .width(min: 120, ideal: 220)
      TableColumn(t("命令", "Command")) { record in
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
        Button(t("启动", "Start")) { state.startStopped(record) }
        Button(t("收藏到侧栏", "Add to sidebar")) {
          Monitor.setFavorite(id: record.id, favorite: true)
          state.toast(t("已收藏到侧栏", "Added to sidebar"))
          Task { await state.refresh() }
        }
        Divider()
        Button(t("移除记录", "Remove record"), role: .destructive) { state.forget(record) }
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

// MARK: - 详情页（占满主区，替代原 DetailSheet 弹窗）

/// 图表分类色（8 槽，浅/深色各一套，经色盲安全校验，顺序即安全机制，不要重排）
let seriesPalette: [Color] = [
  chartColor(0x2A78D6, 0x3987E5), chartColor(0x1BAF7A, 0x199E70),
  chartColor(0xEDA100, 0xC98500), chartColor(0x008300, 0x008300),
  chartColor(0x4A3AA7, 0x9085E9), chartColor(0xE34948, 0xE66767),
  chartColor(0xE87BA4, 0xD55181), chartColor(0xEB6834, 0xD95926)
]

func chartColor(_ light: UInt32, _ dark: UInt32) -> Color {
  func rgb(_ v: UInt32) -> NSColor {
    NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
  }
  return Color(nsColor: NSColor(name: nil) { appearance in
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? rgb(dark) : rgb(light)
  })
}

/* 进程树条目：详情页的树表行 = 图表的一条线，同下标同颜色 */
struct TreeEntry: Identifiable {
  let proc: TreeProc
  let depth: Int
  var id: Int { proc.pid }
}

/* 一条折线：标签 + 颜色 + 采样序列 */
struct UsageSeries: Identifiable {
  let label: String
  let color: Color
  let samples: [UsageSample]
  var id: String { label }
}

struct DetailPage: View {
  @EnvironmentObject var state: AppState
  let initialRow: PortRow

  /// 每轮快照按 pid 找活行；进程退出后保留最后一份数据并标注「已退出」
  var liveRow: PortRow? {
    (state.snapshot.ports + state.snapshot.agentProcesses).first { $0.pid == initialRow.pid }
  }
  var row: PortRow { liveRow ?? initialRow }
  var exited: Bool { liveRow == nil }

  var body: some View {
    let entries = treeEntries(row)
    let series = buildSeries(entries)
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        header
        section(t("基本信息", "Info")) { factsCard }
        section(t("进程树", "Process tree"),
                subtitle: t("父进程与全部子进程，每行颜色对应下方折线。", "Parent and all descendants; row colors match the chart lines."),
                count: entries.count + (row.parentPid != nil ? 1 : 0)) {
          treeCard(entries)
        }
        section(t("CPU 使用历史", "CPU history"),
                subtitle: t("进程树里每个进程一条线，约 3 秒采样一次，保留最近 10 分钟。悬停查看数值。", "One line per process, sampled ~every 3s, last 10 minutes. Hover for values.")) {
          UsageChart(series: series, metric: \.cpu)
        }
        section(t("内存占用历史", "Memory history"),
                subtitle: t("MEM% 是进程占系统总内存的百分比，与列表里的 MEM% 同口径。", "MEM% is the share of total system memory, same as the list column.")) {
          UsageChart(series: series, metric: \.memory)
        }
      }
      .padding(22)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  var header: some View {
    HStack(spacing: 12) {
      Button {
        state.detailTarget = nil
      } label: {
        Label(t("返回", "Back"), systemImage: "chevron.left")
      }
      .keyboardShortcut(.cancelAction)
      VStack(alignment: .leading, spacing: 1) {
        Text(t("详细信息", "Details")).font(.caption).foregroundStyle(.secondary)
        Text(row.port != nil ? "\(row.name) · " + t("端口", "port") + " \(row.port!)" : "\(row.name) · PID \(row.pid)")
          .font(.system(size: 15, weight: .semibold, design: .monospaced))
      }
      if exited {
        statusPill(t("已退出", "exited"), color: .orange)
      }
      Spacer()
      // 操作直接放详情页里，不用回列表右键或去工具栏找（确认弹窗走全局 ActionDialogs）
      if !exited {
        if let url = row.localUrl {
          Button {
            NSWorkspace.shared.open(url)
          } label: {
            Label(t("打开", "Open"), systemImage: "safari")
          }
          .help(t("在浏览器打开", "Open in browser"))
        }
        if canRestart(row) {
          Button {
            state.requestRestart(row)
          } label: {
            Label(t("重启", "Restart"), systemImage: "arrow.clockwise.circle")
          }
          .help(t("重启该服务", "Restart this service"))
        }
        Button(role: .destructive) {
          state.requestKill(row)
        } label: {
          Label(t("结束", "Kill"), systemImage: "stop.circle")
        }
        .help(t("结束进程", "Kill process"))
      }
    }
  }

  @ViewBuilder
  func section<Content: View>(
    _ title: String, subtitle: String = "", count: Int? = nil, @ViewBuilder content: () -> Content
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
        if !subtitle.isEmpty {
          Text(subtitle)
            .font(.system(size: 10.5))
            .foregroundStyle(.tertiary)
        }
        Spacer()
      }
      content()
    }
  }

  // MARK: 基本信息

  var facts: [(String, String)] {
    var list: [(String, String)] = []
    if let port = row.port {
      list.append((t("端口", "Port"), "\(row.address):\(port) · \(row.proto)"))
      list.append((t("范围", "Scope"), row.scope == "all" ? t("全部地址", "all interfaces") : row.scope == "loopback" ? "localhost" : t("本机地址", "host only")))
    }
    list.append(("PID", String(row.pid)))
    if let parentPid = row.parentPid {
      list.append((t("父进程", "Parent"), row.parentName.isEmpty ? String(parentPid) : "\(row.parentName) (\(parentPid))"))
    }
    list.append((t("进程", "Process"), row.name))
    list.append((t("用户", "User"), row.user))
    list.append(("CPU%", String(format: "%.1f", row.cpu)))
    list.append(("MEM%", String(format: "%.1f", row.memory)))
    if !row.started.isEmpty { list.append((t("启动", "Started"), row.started)) }
    if !row.uptime.isEmpty { list.append((t("运行", "Uptime"), row.uptime)) }
    if !row.descendantPids.isEmpty {
      list.append((t("子进程", "Children"), String(row.descendantPids.count)))
    }
    if let http = row.http {
      list.append(("HTTP", "\(http.status)\(http.statusCode.map { " \($0)" } ?? "")"))
      if let latency = http.latencyMs { list.append((t("延迟", "Latency"), "\(latency) ms")) }
      if !http.title.isEmpty { list.append((t("标题", "Title"), http.title)) }
    }
    if !row.tags.isEmpty { list.append((t("标签", "Tags"), row.tags.joined(separator: ", "))) }
    if !row.cwd.isEmpty { list.append((t("工作目录", "Directory"), row.cwd)) }
    if !row.command.isEmpty { list.append((t("命令", "Command"), row.command)) }
    return list
  }

  var factsCard: some View {
    Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 6) {
      ForEach(facts, id: \.0) { fact in
        GridRow {
          Text(fact.0)
            .foregroundStyle(.secondary)
            .frame(width: 74, alignment: .leading)
          Text(fact.1)
            .font(.system(size: 11.5, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  // MARK: 进程树

  /// 目标 + 全部子孙按父子关系排成先序，深度决定缩进
  func treeEntries(_ row: PortRow) -> [TreeEntry] {
    let root = TreeProc(pid: row.pid, name: row.name, cpu: row.cpu, memory: row.memory,
                        parentPid: row.parentPid ?? 0, command: row.command)
    var childrenOf: [Int: [TreeProc]] = [:]
    for proc in row.treeProcs {
      childrenOf[proc.parentPid, default: []].append(proc)
    }
    var result: [TreeEntry] = []
    func walk(_ proc: TreeProc, _ depth: Int) {
      result.append(TreeEntry(proc: proc, depth: depth))
      for child in (childrenOf[proc.pid] ?? []).sorted(by: { $0.pid < $1.pid }) {
        walk(child, depth + 1)
      }
    }
    walk(root, 0)
    return result
  }

  func treeCard(_ entries: [TreeEntry]) -> some View {
    VStack(spacing: 0) {
      if let parentPid = row.parentPid {
        treeRow(swatch: nil,
                name: row.parentName.isEmpty ? String(parentPid) : row.parentName,
                pid: parentPid, cpu: nil, memory: nil, command: "", depth: 0, isParent: true)
        Divider().padding(.leading, 14)
      }
      ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
        treeRow(swatch: index < seriesPalette.count ? seriesPalette[index] : Color.secondary,
                name: entry.proc.name, pid: entry.proc.pid,
                cpu: entry.proc.cpu, memory: entry.proc.memory,
                command: entry.proc.command,
                depth: entry.depth + (row.parentPid != nil ? 1 : 0),
                isParent: false)
        if index != entries.count - 1 {
          Divider().padding(.leading, 14)
        }
      }
    }
    .cardSurface()
  }

  func treeRow(swatch: Color?, name: String, pid: Int, cpu: Double?, memory: Double?,
               command: String, depth: Int, isParent: Bool) -> some View {
    HStack(spacing: 8) {
      Group {
        if let swatch {
          RoundedRectangle(cornerRadius: 3).fill(swatch)
        } else {
          RoundedRectangle(cornerRadius: 3)
            .strokeBorder(Color.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
        }
      }
      .frame(width: 10, height: 10)
      .padding(.leading, CGFloat(depth) * 18)
      Text(name)
        .font(.system(size: 12, weight: pid == row.pid ? .semibold : .regular))
        .lineLimit(1)
      if isParent {
        Text(t("父进程", "parent"))
          .font(.system(size: 9.5, weight: .semibold, design: .rounded))
          .foregroundStyle(.secondary)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(.quaternary, in: Capsule())
      }
      Text(String(pid))
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.tertiary)
      if !command.isEmpty {
        Text(command)
          .font(.system(size: 10.5, design: .monospaced))
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
          .help(command)
      }
      Spacer(minLength: 12)
      Text(cpu.map { String(format: "%.1f%%", $0) } ?? "--")
        .font(.system(size: 11, design: .monospaced))
        .frame(width: 52, alignment: .trailing)
      Text(memory.map { String(format: "%.1f%%", $0) } ?? "--")
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .frame(width: 52, alignment: .trailing)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
  }

  // MARK: 折线序列

  /// 前 8 个进程各占一条线（颜色跟树表行一致），更多的合并为「其他合计」灰线
  func buildSeries(_ entries: [TreeEntry]) -> [UsageSeries] {
    let history = Monitor.history(for: entries.map(\.proc.pid))
    var series: [UsageSeries] = []
    var folded: [Date: (cpu: Double, memory: Double)] = [:]
    for (index, entry) in entries.enumerated() {
      let samples = history[entry.proc.pid] ?? []
      if index < seriesPalette.count {
        series.append(UsageSeries(label: "\(entry.proc.name) (\(entry.proc.pid))",
                                  color: seriesPalette[index], samples: samples))
      } else {
        for sample in samples {
          var acc = folded[sample.t] ?? (0, 0)
          acc.cpu += sample.cpu
          acc.memory += sample.memory
          folded[sample.t] = acc
        }
      }
    }
    if entries.count > seriesPalette.count {
      let count = entries.count - seriesPalette.count
      series.append(UsageSeries(
        label: t("其他 \(count) 个进程合计", "Other \(count) combined"),
        color: .secondary,
        samples: folded.map { UsageSample(t: $0.key, cpu: $0.value.cpu, memory: $0.value.memory) }
          .sorted { $0.t < $1.t }))
    }
    return series
  }
}

// MARK: - 使用历史折线图（Swift Charts）

struct UsageChart: View {
  let series: [UsageSeries]
  let metric: KeyPath<UsageSample, Double>
  @State private var selectedDate: Date?

  var hasData: Bool {
    series.contains { $0.samples.count >= 2 }
  }

  /// 悬停位置吸附到最近的采样时间点
  var snappedDate: Date? {
    guard let selectedDate else { return nil }
    let all = series.flatMap { $0.samples.map(\.t) }
    return all.min { abs($0.timeIntervalSince(selectedDate)) < abs($1.timeIntervalSince(selectedDate)) }
  }

  /// 选中时间点上每条线的值（3 秒采样，容差 2 秒内算命中），按值降序
  var selectedValues: [(label: String, color: Color, value: Double)] {
    guard let snappedDate else { return [] }
    return series.compactMap { s in
      s.samples
        .min { abs($0.t.timeIntervalSince(snappedDate)) < abs($1.t.timeIntervalSince(snappedDate)) }
        .flatMap { abs($0.t.timeIntervalSince(snappedDate)) <= 2 ? (s.label, s.color, $0[keyPath: metric]) : nil }
    }
    .sorted { $0.value > $1.value }
  }

  var body: some View {
    Group {
      if hasData {
        chart
      } else {
        Text(t("正在采集数据，几秒后出现曲线…", "Collecting data; lines appear in a few seconds…"))
          .font(.system(size: 12))
          .foregroundStyle(.tertiary)
          .frame(maxWidth: .infinity, minHeight: 120)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .cardSurface()
  }

  var chart: some View {
    Chart {
      ForEach(series) { s in
        ForEach(s.samples, id: \.t) { sample in
          LineMark(
            x: .value(t("时间", "Time"), sample.t),
            y: .value("%", sample[keyPath: metric]),
            series: .value(t("进程", "Process"), s.label)
          )
          .foregroundStyle(by: .value(t("进程", "Process"), s.label))
          .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
      }
      if let snappedDate {
        RuleMark(x: .value(t("时间", "Time"), snappedDate))
          .foregroundStyle(.secondary.opacity(0.6))
          .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
      }
    }
    .chartForegroundStyleScale(domain: series.map(\.label), range: series.map(\.color))
    .chartXSelection(value: $selectedDate)
    .chartLegend(position: .bottom, spacing: 10)
    .chartYAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) { _ in
        AxisGridLine()
        AxisValueLabel(format: FloatingPointFormatStyle<Double>().precision(.significantDigits(1...2)))
      }
    }
    .frame(height: 190)
    .overlay(alignment: .topLeading) {
      if let snappedDate, !selectedValues.isEmpty {
        VStack(alignment: .leading, spacing: 3) {
          Text(snappedDate.formatted(date: .omitted, time: .standard))
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
          ForEach(selectedValues, id: \.label) { item in
            HStack(spacing: 5) {
              RoundedRectangle(cornerRadius: 2).fill(item.color).frame(width: 8, height: 8)
              Text(item.label)
                .font(.system(size: 10.5))
                .lineLimit(1)
              Text(String(format: "%.1f%%", item.value))
                .font(.system(size: 10.5, design: .monospaced))
            }
          }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        .allowsHitTesting(false)
      }
    }
  }
}
