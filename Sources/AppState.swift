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
  // 完整模式表格的列排序（空 = 默认端口序）
  @Published var tableSort: [KeyPathComparator<PortRow>] = []
  // 已忽略服务（serviceId，无 serviceId 的进程按 "proc:进程名"），从列表隐藏、侧栏「已忽略」可找回
  @Published var ignoredKeys: Set<String> = Set(UserDefaults.standard.stringArray(forKey: ignoredDefaultsKey) ?? [])

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
  private var pendingRefresh = false   // 采集中又来了刷新请求（如 kill 后），排队补跑而非静默丢弃

  // 滚动期间冻结 UI 发布：快照刷新撞进滚动会整页重建、必卡一帧。
  // 非 @Published——滚动开始/结束本身不该触发重绘；攒下的快照在滚动结束时应用。
  private(set) var liveScrolling = false {
    didSet {
      guard oldValue != liveScrolling, !liveScrolling, let held = heldSnapshot else { return }
      heldSnapshot = nil
      apply(held)
    }
  }
  private var heldSnapshot: Snapshot?
  private var scrollQuietTask: Task<Void, Never>?
  private var scrollMonitor: Any?

  /// 每收到一个交互事件调用一次；静默 1.2 秒才算交互结束，应用攒下的快照。
  /// 1.2 秒是给「小步轻滚」留的：两次轻滚间隙 <1.2s 时快照永远不落地，
  /// 落地停顿吞滚轮事件的「撞墙感」（2026-07-16 实测 50~386ms）就不会出现
  func noteScrollActivity() {
    liveScrolling = true
    scrollQuietTask?.cancel()
    scrollQuietTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: 1_200_000_000)
      guard !Task.isCancelled else { return }
      self?.liveScrolling = false
    }
  }
  private var timer: Timer?
  private var toastTask: Task<Void, Never>?

  // 星标乐观更新：点击立即生效，等快照追上（包含该收藏状态）后自动清除。
  // 不加这个的话星标要等下一轮完整采集（lsof+探测，可达 1 秒+）才变化。
  @Published var favoriteOverrides: [String: Bool] = [:]

  // 采集周期：原为 2 秒，放宽到 3 秒，采集 CPU 尖峰频率下降约 1/3
  private let interval: TimeInterval = 3
  // 主窗口和菜单面板都不可见时的采集周期（采集是能耗大头，没人看就不用 3s 一轮）
  private let idleInterval: TimeInterval = 30
  private var lastCollect = Date.distantPast

  /// 有任何自家 UI 在屏上可见（occlusionState 按遮挡判断，不看焦点——
  /// scenePhase / didResignActive 两条路都实测失败过，见 memory bashlook-performance）。
  /// 排除菜单栏图标本身（NSStatusBarWindow 永远可见）。
  private var anyUIVisible: Bool {
    NSApp.windows.contains { w in
      w.isVisible && w.occlusionState.contains(.visible)
        && !w.className.contains("StatusBar")
    }
  }

  /* 启动不能依赖主窗口出现：open -g（不激活）拉起时 Window 场景不会创建、
     .task 永不触发，实测（2026-07-17）监控引擎完全不跑、菜单栏面板永远空数据。
     Window 的 .task 里仍保留 start() 调用（幂等），只负责 unhide 自愈。 */
  init() {
    start()
  }

  func start() {
    guard timer == nil else { return }  // 窗口关闭重开时 .task 会再次触发
    Task { await refresh() }
    timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
      Task { await self?.tick() }
    }
    timer?.tolerance = 0.5  // 允许系统合并定时器唤醒，省电

    // app 级交互监听：滚轮（含惯性）、按下、拖拽、捏合都算交互，期间冻结快照发布。
    // 挂在视图上的检测（NSScrollView 通知、GeometryReader 偏移量）都实测漏报过。
    // leftMouseDown 也要冻结：快照应用若落在按住瞬间会重建行视图，正在酝酿的拖拽会话直接死掉
    scrollMonitor = NSEvent.addLocalMonitorForEvents(
      matching: [.scrollWheel, .leftMouseDown, .leftMouseDragged, .magnify]
    ) { [weak self] event in
      self?.noteScrollActivity()
      return event
    }
  }

  private func tick() async {
    if liveScrolling { return }   // 滚动中不开新采集，降低采完撞回滚动的概率
    if !anyUIVisible, Date().timeIntervalSince(lastCollect) < idleInterval { return }
    await refresh()
  }

  func refresh(manual: Bool = false) async {
    if refreshing {
      pendingRefresh = true   // 让在跑的这轮结束后再补一轮，保证操作后的状态尽快反映
      return
    }
    refreshing = true
    if manual { isRefreshing = true }
    repeat {
      pendingRefresh = false
      lastCollect = Date()
      let next = await Monitor.collectSnapshot()
      if liveScrolling {
        heldSnapshot = next   // 滚动中不发布，偏移量静止后由 didSet 应用
      } else {
        apply(next)
      }
    } while pendingRefresh
    refreshing = false
    if manual { isRefreshing = false }
  }

  private func apply(_ next: Snapshot) {
    var next = next
    // 拖拽排序后、磁盘顺序被快照追上前，强制按拖拽结果排；追上即撤防
    if let order = pendingFavoriteOrder {
      if next.favorites.map(\.id) == order {
        pendingFavoriteOrder = nil
      } else {
        let position = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        next.favorites.sort { (position[$0.id] ?? Int.max) < (position[$1.id] ?? Int.max) }
      }
    }
    // 不用 withAnimation：每 2 秒刷新若给整个 snapshot 变化套动画，
    // 会让全列表带过渡重绘，是卡顿来源之一。数据监控直接换值即可。
    snapshot = next
    startingIds = startingIds.filter { id in
      !next.favorites.contains { $0.id == id && $0.running }
    }
    // 快照已和乐观值一致的清掉；仍不一致（快照采集早于写盘）的保留，下一轮自愈
    favoriteOverrides = favoriteOverrides.filter { id, fav in
      next.favorites.contains { $0.id == id } != fav
    }
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
    hasher.combine(ignoredKeys)
    hasher.combine(tableSort)
    let key = hasher.finalize()
    if key == treeCacheKey { return treeCache }

    var rows = snapshot.ports
    switch selection {
    case .all:
      rows += snapshot.agentProcesses
    case .category(let category):
      rows = rows.filter { $0.category == category }
      if category == .agent { rows += snapshot.agentProcesses }
    case .ignored:
      rows += snapshot.agentProcesses
    case .home, .stopped:
      rows = []
    }
    // 忽略过滤：常规视图剔掉已忽略的；「已忽略」视图只看它们（找回入口）
    rows = selection == .ignored ? rows.filter(isIgnored) : rows.filter { !isIgnored($0) }

    var tree = groupByDependency(
      rows, home: FileManager.default.homeDirectoryForCurrentUser.path,
      edges: snapshot.connections)

    // 简单模式 / 搜索：组内任一行命中即保留整组（关联的前后端一起显示）
    func groupMatches(_ head: PortRow, _ predicate: (PortRow) -> Bool) -> Bool {
      predicate(head) || (head.children ?? []).contains(where: predicate)
    }
    // 「已忽略」视图不做简单模式过滤：没标题的服务也得能被找回
    if simpleMode, selection != .ignored {
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
    if !tableSort.isEmpty {
      tree.sort(using: tableSort)   // 列排序只排顶层，组内子行保持端口序
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
    return favoriteOverrides[id] ?? snapshot.favorites.contains { $0.id == id }
  }

  // MARK: - 忽略

  func ignoreKey(_ row: PortRow) -> String { row.serviceId ?? "proc:\(row.name)" }
  func isIgnored(_ row: PortRow) -> Bool { ignoredKeys.contains(ignoreKey(row)) }

  func toggleIgnore(_ row: PortRow) {
    let key = ignoreKey(row)
    if ignoredKeys.contains(key) {
      ignoredKeys.remove(key)
      toast(t("已恢复显示", "Unhidden"))
    } else {
      ignoredKeys.insert(key)
      toast(t("已忽略，可在侧栏「已忽略」中找回", "Hidden; recover from “Ignored” in the sidebar"))
    }
    UserDefaults.standard.set(Array(ignoredKeys).sorted(), forKey: ignoredDefaultsKey)
  }

  /// 当前活着的进程里被忽略的数量（侧栏计数）
  var ignoredLiveCount: Int {
    (snapshot.ports + snapshot.agentProcesses).filter(isIgnored).count
  }

  // MARK: - 操作

  func toggleFavorite(_ row: PortRow) {
    guard let id = row.serviceId else { return }
    let isFav = isFavorite(row)
    favoriteOverrides[id] = !isFav
    Monitor.setFavorite(id: id, favorite: !isFav, from: row)
    toast(isFav ? t("已取消收藏", "Unfavorited") : t("已收藏到侧栏", "Added to sidebar"))
    Task { await refresh() }
  }

  func unfavorite(id: String) {
    favoriteOverrides[id] = false
    Monitor.setFavorite(id: id, favorite: false)
    toast(t("已取消收藏", "Unfavorited"))
    Task { await refresh() }
  }

  // 拖拽后的乐观顺序：采集中途开始的旧快照应用时按它重排（否则 UI 闪回旧顺序），
  // 等快照自然追上（磁盘 sortOrder 已生效）就清除
  private var pendingFavoriteOrder: [String]?

  /// 拖拽经过目标行时的实时重排（只动内存，落盘等 commit）。菜单栏面板与侧栏共用
  func reorderFavorite(dragged: String, over target: String) {
    guard dragged != target,
          let from = snapshot.favorites.firstIndex(where: { $0.id == dragged }),
          let to = snapshot.favorites.firstIndex(where: { $0.id == target }) else { return }
    snapshot.favorites.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
    pendingFavoriteOrder = snapshot.favorites.map(\.id)   // 拖拽途中刷新落地也保持这个顺序
  }

  /// 把当前快照里的收藏顺序定为正式顺序：落盘 + 防旧快照回冲
  func commitFavoriteOrder() {
    let ids = snapshot.favorites.map(\.id)
    pendingFavoriteOrder = ids
    Monitor.setFavoriteOrder(ids)
    Task { await refresh() }
  }

  /// 从收藏面板跳到某个端口对应活进程的详情页
  func showDetails(favoritePort port: Int?) {
    guard let row = liveRow(port: port) else { return }
    detailTarget = row
  }

  var runningServiceIds: Set<String> { Set(snapshot.ports.compactMap(\.serviceId)) }
  var runningPorts: Set<Int> { Set(snapshot.ports.compactMap(\.port)) }

  // MARK: - 收藏操作面板（启动/重启/关闭 × 全部/单个）

  private func liveRow(port: Int?) -> PortRow? {
    guard let port else { return nil }
    return snapshot.ports.first { $0.port == port }
  }

  /* 关整条链：本体 + 全部活着的依赖（docker 走 docker stop）。返回失败信息，空数组=全部成功 */
  private func stopEverything(_ favorite: FavoriteItem) async -> [String] {
    var failures: [String] = []
    if let row = liveRow(port: favorite.livePort) {
      let result = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
      if !result.ok { failures.append(result.message) }
    }
    for dep in favorite.deps where dep.running {
      if dep.isDocker {
        if let port = dep.port { _ = Monitor.dockerAction("stop", publishPort: port) }
      } else if let row = liveRow(port: dep.port) {
        let result = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
        if !result.ok { failures.append(result.message) }
      }
    }
    return failures
  }

  /* 重启整组：本体从服务树根 kill+respawn（编排器 pnpm dev 管的子服务由根命令整家拉回），
     树外依赖（docker、独立进程）各自原地重启。旧路径「杀叶子 + 按收藏记录起」对
     编排器派生的子服务只回本体——dependsOn 里根本没有它们的记录 */
  private func restartAll(_ favorite: FavoriteItem, row: PortRow) async {
    let processes = Monitor.parsePs(
      await Monitor.run("/bin/ps", ["-axo", "pid,ppid,user,pcpu,pmem,lstart,comm,args"]))
    let root = await Monitor.serviceTreeRoot(pid: row.pid, command: row.command, cwd: row.cwd, in: processes)
    let treePids = Set([root.pid] + Monitor.descendants(of: root.pid, in: processes))
    var failures: [String] = []
    let result = await Monitor.restart(row: row)
    if !result.ok { failures.append(result.message) }
    for dep in favorite.deps where dep.running {
      if dep.isDocker {
        if let port = dep.port { _ = Monitor.dockerAction("restart", publishPort: port) }
      } else if let depRow = liveRow(port: dep.port), !treePids.contains(depRow.pid) {
        let depResult = await Monitor.restart(row: depRow)
        if !depResult.ok { failures.append(depResult.message) }
      }
    }
    toast(failures.isEmpty
      ? "\(ServiceAction.restart.done) \(favorite.title)"
      : failures.joined(separator: t("；", "; ")))
  }

  func performAll(_ action: ServiceAction, _ favorite: FavoriteItem) {
    toast("\(action.doing) \(favorite.title)")
    Task {
      if action == .restart, let row = liveRow(port: favorite.livePort) {
        startingIds.insert(favorite.id)
        await restartAll(favorite, row: row)
        await refresh()
        try? await Task.sleep(nanoseconds: 8_000_000_000)
        startingIds.remove(favorite.id)
        return
      }
      let watchPorts = ([favorite.livePort]
        + favorite.deps.filter { $0.running && !$0.isDocker }.map(\.port)).compactMap { $0 }
      var failures: [String] = []
      if action != .start {
        failures = await stopEverything(favorite)
        await refresh()
      }
      guard failures.isEmpty else {
        toast(failures.joined(separator: t("；", "; ")))
        return
      }
      if action == .stop {
        // 杀完核对端口真的空了才报成功，防止被别的守护进程秒级拉起还谎报已关闭
        let stillUp = watchPorts.filter(runningPorts.contains)
        toast(stillUp.isEmpty
          ? t("已关闭 \(favorite.title) 及其依赖", "Stopped \(favorite.title) and its dependencies")
          : t("端口 \(stillUp.map(String.init).joined(separator: "、")) 被守护进程自动拉起，未能关闭",
              "Port \(stillUp.map(String.init).joined(separator: ", ")) was respawned by a supervisor; not stopped"))
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
    toast(action.doing)
    Task {
      let label: String
      var failure: String?
      if let dep {
        label = dep.label + (dep.port.map { " \($0)" } ?? "")
        if dep.isDocker {
          if let port = dep.port {
            let verb = action == .stop ? "stop" : action == .restart ? "restart" : "start"
            _ = Monitor.dockerAction(verb, publishPort: port)
          }
        } else if action == .restart, let row = liveRow(port: dep.port) {
          // 树根重启：编排器派生的子服务单独「杀叶子+按记录起」会双开或被联动关掉
          let result = await Monitor.restart(row: row)
          if !result.ok { failure = result.message }
        } else {
          if action != .start, let row = liveRow(port: dep.port) {
            let result = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
            if !result.ok { failure = result.message }
          }
          if failure == nil, action != .stop, let record = Monitor.loadServices()[dep.id] {
            if action == .restart { try? await Task.sleep(nanoseconds: 400_000_000) }
            _ = Monitor.startService(record)
          }
        }
      } else {
        label = favorite.title
        if action == .restart, let row = liveRow(port: favorite.livePort) {
          let result = await Monitor.restart(row: row)
          if !result.ok { failure = result.message }
        } else {
          if action != .start, let row = liveRow(port: favorite.livePort) {
            let result = await Monitor.killTree(pid: row.pid, includeChildren: true, force: false)
            if !result.ok { failure = result.message }
          }
          if failure == nil, action != .stop {
            if action == .restart { try? await Task.sleep(nanoseconds: 400_000_000) }
            startingIds.insert(favorite.id)
            _ = Monitor.startService(favorite.record)
            Task {
              try? await Task.sleep(nanoseconds: 8_000_000_000)
              startingIds.remove(favorite.id)
            }
          }
        }
      }
      toast(failure ?? "\(action.done) \(label)")
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
    toast(t("正在结束 \(row.name)…", "Killing \(row.name)…"))
    Task {
      let result = await Monitor.killTree(pid: row.pid, includeChildren: includeChildren, force: force)
      toast(result.message)
      await refresh()
    }
  }

  func restart(_ row: PortRow) {
    toast(t("正在重启 \(row.name)…", "Restarting \(row.name)…"))
    Task {
      let result = await Monitor.restart(row: row)
      toast(result.message)
      await refresh()
    }
  }
}
