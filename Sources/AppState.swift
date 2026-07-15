import SwiftUI

@MainActor
final class AppState: ObservableObject {
  @Published var snapshot = Snapshot()
  @Published var selection: SidebarSelection = .home
  @Published var searchText = ""
  @Published var toastMessage: String?
  @AppStorage("portdock-mode") var simpleMode = true

  // 全局操作目标（表格、Home 共用同一套确认弹窗）
  @Published var killTarget: PortRow?
  @Published var restartTarget: PortRow?
  @Published var detailTarget: PortRow?
  @Published var confirmationInput = ""
  @Published var tableSelection: Set<PortRow.ID> = []
  // 简单模式卡片列表的展开状态（自绘展开钮管理，替代 Table(children:) 的系统 disclosure）
  @Published var expandedIds: Set<String> = []

  /* 表格当前选中的行（工具栏操作按钮的目标） */
  var selectedRow: PortRow? {
    guard selection != .home, selection != .stopped,
          let id = tableSelection.first else { return nil }
    return flatVisibleRows.first { $0.id == id }
  }

  func needsStrongConfirmation(_ row: PortRow) -> Bool {
    row.highRisk || !row.descendantPids.isEmpty
  }

  func requestKill(_ row: PortRow) {
    confirmationInput = ""
    killTarget = row
  }

  func requestRestart(_ row: PortRow) {
    confirmationInput = ""
    restartTarget = row
  }

  @Published var isRefreshing = false          // 手动刷新的按钮反馈
  @Published var startingIds: Set<String> = [] // 正在启动中的收藏项

  private var refreshing = false
  private var timer: Timer?
  private var toastTask: Task<Void, Never>?

  // 采集周期：原为 2 秒，放宽到 3 秒，采集 CPU 尖峰频率下降约 1/3
  private let interval: TimeInterval = 3

  func start() {
    guard timer == nil else { return }  // 窗口关闭重开时 .task 会再次触发
    Task { await refresh() }
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { await self?.refresh() }
    }
  }

  func refresh(manual: Bool = false) async {
    guard !refreshing else { return }
    refreshing = true
    if manual { isRefreshing = true }
    let next = await Monitor.collectSnapshot()
    // 不用 withAnimation：每 2 秒刷新若给整个 snapshot 变化套动画，
    // 会让全列表带过渡重绘，是卡顿来源之一。数据监控直接换值即可。
    snapshot = next
    startingIds = startingIds.filter { id in
      !next.favorites.contains { $0.id == id && $0.running }
    }
    refreshing = false
    if manual { isRefreshing = false }
  }

  func toast(_ message: String) {
    toastMessage = message
    toastTask?.cancel()
    toastTask = Task {
      try? await Task.sleep(nanoseconds: 4_000_000_000)
      if !Task.isCancelled { toastMessage = nil }
    }
  }

  // MARK: - 行数据（当前筛选下，按依赖分组成树）

  // visibleTree 缓存：并查集分组是 O(n²)，同一份数据/筛选下只算一次。
  // 渲染热路径（Table、overlay、flatVisibleRows）会多次读取它。
  private var treeCache: [PortRow] = []
  private var treeCacheKey: Int = -1

  var visibleTree: [PortRow] {
    var hasher = Hasher()
    hasher.combine(snapshot.generatedAt)
    hasher.combine(selection)
    hasher.combine(searchText)
    hasher.combine(simpleMode)
    let key = hasher.finalize()
    if key == treeCacheKey { return treeCache }

    var rows = snapshot.ports
    switch selection {
    case .all:
      rows += snapshot.agentProcesses
    case .category(let category):
      rows = rows.filter { $0.category == category }
      if category == .agent { rows += snapshot.agentProcesses }
    case .home, .stopped:
      rows = []
    }

    var tree = groupByDependency(
      rows, home: FileManager.default.homeDirectoryForCurrentUser.path,
      edges: snapshot.connections)

    // 简单模式 / 搜索：组内任一行命中即保留整组（关联的前后端一起显示）
    func groupMatches(_ head: PortRow, _ predicate: (PortRow) -> Bool) -> Bool {
      predicate(head) || (head.children ?? []).contains(where: predicate)
    }
    if simpleMode {
      tree = tree.filter { groupMatches($0) { !$0.title.isEmpty } }
    }
    if !searchText.isEmpty {
      let needle = searchText.lowercased()
      tree = tree.filter {
        groupMatches($0) { row in
          "\(row.port ?? 0) \(row.pid) \(row.name) \(row.title) \(row.command) \(row.cwd) \(row.tags.joined(separator: " "))"
            .lowercased().contains(needle)
        }
      }
    }
    treeCache = tree
    treeCacheKey = key
    return tree
  }

  /* 树展平，供选中行查找 */
  var flatVisibleRows: [PortRow] {
    visibleTree.flatMap { [$0] + ($0.children ?? []) }
  }

  // 简单模式卡片列表：父行 +（若展开）其子行，扁平化。不走 Table(children:) 的系统
  // disclosure —— 那个三角热区太小且改不了，改由 PortCardRow 自绘大热区展开钮。
  var cardRows: [PortRow] {
    visibleTree.flatMap { parent in
      guard parent.children != nil, expandedIds.contains(parent.id) else { return [parent] }
      return [parent] + (parent.children ?? [])
    }
  }

  // cardRows 里作为子行显示的 id，供行视图判断缩进
  // ponytail: 每行渲染重算，可见行数很小；破百再像 treeCache 那样缓存
  var childRowIds: Set<String> {
    Set(visibleTree
      .filter { expandedIds.contains($0.id) }
      .flatMap { ($0.children ?? []).map(\.id) })
  }

  func toggleExpand(_ row: PortRow) {
    if expandedIds.contains(row.id) { expandedIds.remove(row.id) } else { expandedIds.insert(row.id) }
  }

  var visibleStopped: [ServiceRecord] {
    var rows = snapshot.stopped
    if simpleMode {
      rows = rows.filter { !($0.title ?? "").isEmpty }
    }
    if !searchText.isEmpty {
      let needle = searchText.lowercased()
      rows = rows.filter {
        "\($0.port ?? 0) \($0.name) \($0.title ?? "") \($0.command) \($0.cwd)".lowercased().contains(needle)
      }
    }
    return rows
  }

  func isFavorite(_ row: PortRow) -> Bool {
    guard let id = row.serviceId else { return false }
    return snapshot.favorites.contains { $0.id == id }
  }

  // MARK: - 操作

  func toggleFavorite(_ row: PortRow) {
    guard let id = row.serviceId else { return }
    let isFav = isFavorite(row)
    Monitor.setFavorite(id: id, favorite: !isFav, from: row)
    toast(isFav ? t("已取消收藏", "Unfavorited") : t("已收藏到侧栏", "Added to sidebar"))
    Task { await refresh() }
  }

  func unfavorite(id: String) {
    Monitor.setFavorite(id: id, favorite: false)
    toast(t("已取消收藏", "Unfavorited"))
    Task { await refresh() }
  }

  func openFavorite(_ favorite: FavoriteItem) {
    if let url = favorite.localUrl {
      NSWorkspace.shared.open(url)
    } else {
      startingIds.insert(favorite.id)
      let (result, deps) = Monitor.startWithDependencies(
        favorite.record, runningIds: runningServiceIds, runningPorts: runningPorts)
      if !result.ok {
        startingIds.remove(favorite.id)
        toast(result.message)
      } else {
        if !deps.isEmpty { toast(t("已连带启动依赖: ", "Also started: ") + deps.joined(separator: t("、", ", "))) }
        // 兜底：启动失败没起来时不让 spinner 永远转
        Task {
          try? await Task.sleep(nanoseconds: 8_000_000_000)
          startingIds.remove(favorite.id)
        }
      }
      Task { await refresh() }
    }
  }

  var runningServiceIds: Set<String> { Set(snapshot.ports.compactMap(\.serviceId)) }
  var runningPorts: Set<Int> { Set(snapshot.ports.compactMap(\.port)) }

  // MARK: - 收藏操作面板（启动/重启/关闭 × 全部/单个）

  private func liveRow(port: Int?) -> PortRow? {
    guard let port else { return nil }
    return snapshot.ports.first { $0.port == port }
  }

  /* 关整条链：本体 + 全部活着的依赖（docker 走 docker stop） */
  private func stopEverything(_ favorite: FavoriteItem) async {
    if let row = liveRow(port: favorite.livePort) {
      _ = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
    }
    for dep in favorite.deps where dep.running {
      if dep.isDocker {
        if let port = dep.port { _ = Monitor.dockerAction("stop", publishPort: port) }
      } else if let row = liveRow(port: dep.port) {
        _ = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
      }
    }
  }

  func performAll(_ action: ServiceAction, _ favorite: FavoriteItem) {
    Task {
      if action != .start {
        await stopEverything(favorite)
        await refresh()
      }
      if action == .stop {
        toast(t("已关闭 \(favorite.title) 及其依赖", "Stopped \(favorite.title) and its dependencies"))
      } else {
        if action == .restart { try? await Task.sleep(nanoseconds: 500_000_000) }
        startingIds.insert(favorite.id)
        let (result, deps) = Monitor.startWithDependencies(
          favorite.record, runningIds: runningServiceIds, runningPorts: runningPorts)
        if result.ok {
          toast(deps.isEmpty
            ? "\(action.done) \(favorite.title)"
            : "\(action.done) \(favorite.title) + \(deps.joined(separator: t("、", ", ")))")
        } else {
          startingIds.remove(favorite.id)
          toast(result.message)
        }
        Task {
          try? await Task.sleep(nanoseconds: 8_000_000_000)
          startingIds.remove(favorite.id)
        }
      }
      await refresh()
    }
  }

  /* 单个服务的操作。dep == nil 表示收藏本体（不连带依赖） */
  func perform(_ action: ServiceAction, _ favorite: FavoriteItem, dep: DepStatus?) {
    Task {
      let label: String
      if let dep {
        label = dep.label + (dep.port.map { " \($0)" } ?? "")
        if dep.isDocker {
          if let port = dep.port {
            let verb = action == .stop ? "stop" : action == .restart ? "restart" : "start"
            _ = Monitor.dockerAction(verb, publishPort: port)
          }
        } else {
          if action != .start, let row = liveRow(port: dep.port) {
            _ = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
          }
          if action != .stop, let record = Monitor.loadServices()[dep.id] {
            if action == .restart { try? await Task.sleep(nanoseconds: 400_000_000) }
            _ = Monitor.startService(record)
          }
        }
      } else {
        label = favorite.title
        if action != .start, let row = liveRow(port: favorite.livePort) {
          _ = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
        }
        if action != .stop {
          if action == .restart { try? await Task.sleep(nanoseconds: 400_000_000) }
          startingIds.insert(favorite.id)
          _ = Monitor.startService(favorite.record)
          Task {
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            startingIds.remove(favorite.id)
          }
        }
      }
      toast("\(action.done) \(label)")
      await refresh()
    }
  }

  func startStopped(_ record: ServiceRecord) {
    let (result, deps) = Monitor.startWithDependencies(
      record, runningIds: runningServiceIds, runningPorts: runningPorts)
    let suffix = deps.isEmpty ? "" : t("（依赖: \(deps.joined(separator: "、"))）", " (deps: \(deps.joined(separator: ", ")))")
    toast(result.ok ? t("已启动", "Started") + " \(record.name)\(suffix)" : result.message)
    Task { await refresh() }
  }

  func forget(_ record: ServiceRecord) {
    Monitor.forgetService(id: record.id)
    Task { await refresh() }
  }

  func kill(_ row: PortRow, includeChildren: Bool, force: Bool) {
    Task {
      let result = await Monitor.killTree(pid: row.pid, includeChildren: includeChildren, force: force)
      toast(result.message)
      await refresh()
    }
  }

  func restart(_ row: PortRow) {
    Task {
      let result = await Monitor.restart(row: row)
      toast(result.message)
      await refresh()
    }
  }
}
