import Foundation

enum Category: String, Codable, CaseIterable {
  case agent, web, infra, other
}

// MARK: - 打开链接的主机名

/* 本机局域网 IPv4：en0（Wi-Fi/主网卡）优先，否则第一个非回环、非链路本地的地址 */
func lanIPv4() -> String? {
  var ifaddr: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&ifaddr) == 0 else { return nil }
  defer { freeifaddrs(ifaddr) }
  var fallback: String?
  var pointer = ifaddr
  while let current = pointer {
    defer { pointer = current.pointee.ifa_next }
    let ifa = current.pointee
    guard let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET),
          ifa.ifa_flags & UInt32(IFF_LOOPBACK) == 0,
          ifa.ifa_flags & UInt32(IFF_UP) != 0 else { continue }
    var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    guard getnameinfo(sa, socklen_t(sa.pointee.sa_len), &host, socklen_t(host.count),
                      nil, 0, NI_NUMERICHOST) == 0 else { continue }
    let ip = String(cString: host)
    guard !ip.hasPrefix("169.254.") else { continue }
    if String(cString: ifa.ifa_name) == "en0" { return ip }
    if fallback == nil { fallback = ip }
  }
  return fallback
}

let lanShareKey = "portdock-lan-share"
let ignoredDefaultsKey = "portdock-ignored"

/* 打开服务的 URL：默认 localhost；开了局域网共享用本机局域网 IP——
   但绑定在 127.0.0.1 的服务（scope == loopback）局域网 IP 连不上，仍走 localhost。
   path：API 服务探测到的管理台路径（如 management.html），有则深链过去 */
func serviceURL(port: Int, scope: String, path: String = "") -> URL? {
  let host: String
  if UserDefaults.standard.bool(forKey: lanShareKey),
     scope != "loopback", let ip = lanIPv4() {
    host = ip
  } else {
    host = "localhost"
  }
  return URL(string: "http://\(host):\(port)" + (path.isEmpty ? "" : "/\(path)"))
}

struct ProbeResult: Hashable {
  var status: String        // ok / error / skipped
  var statusCode: Int?
  var latencyMs: Int?
  var title: String = ""
  var uiPath: String = ""   // 根路径是 JSON 的 API 服务，探测到的管理台路径（不带前导斜杠）
}

/* 进程树成员（CPU 排行明细、详情页进程树/折线图用） */
struct TreeProc: Hashable, Identifiable {
  var pid: Int
  var name: String
  var cpu: Double
  var memory: Double = 0
  var parentPid: Int = 0
  var command: String = ""

  var id: Int { pid }
}

/* 单次采样点：详情页 CPU/内存历史折线图的数据单位 */
struct UsageSample: Hashable {
  var t: Date
  var cpu: Double
  var memory: Double
}

struct PortRow: Identifiable, Hashable {
  var children: [PortRow]?   // 同组（同项目/同进程树）的关联服务
  var port: Int?             // nil = 无监听端口的相关进程（agent）
  var address: String = ""
  var proto: String = "TCP"
  var scope: String = ""     // all / loopback / host
  var pid: Int
  var parentPid: Int?
  var parentName: String = ""
  var name: String = ""
  var command: String = ""
  var user: String = ""
  var cpu: Double = 0
  var memory: Double = 0
  var started: String = ""
  var startedAt: Date?
  var cwd: String = ""
  var projectRoot: String = ""   // 最近的含 .git 的祖先目录，空 = 不在项目里
  var descendantPids: [Int] = []
  var treeProcs: [TreeProc] = []   // 所有子孙进程的明细（不含自身）
  var category: Category = .other
  var tags: [String] = []
  var highRisk: Bool = false
  var http: ProbeResult?

  var id: String { "\(pid):\(address):\(port ?? 0)" }

  var title: String { http?.title ?? "" }

  /// 整棵进程树（自身 + 所有子孙）的 CPU 总和
  var treeCpu: Double { treeProcs.reduce(cpu) { $0 + $1.cpu } }

  var localUrl: URL? {
    guard let port else { return nil }
    return serviceURL(port: port, scope: scope, path: http?.uiPath ?? "")
  }

  var serviceId: String? {
    guard !cwd.isEmpty, cwd != "/", !command.isEmpty else { return nil }
    return "\(cwd)::\(command)"
  }

  var uptime: String {
    guard let startedAt else { return "" }
    let minutes = Int(Date().timeIntervalSince(startedAt) / 60)
    if minutes < 0 { return "" }
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    if hours < 48 { return "\(hours)h \(minutes % 60)m" }
    return "\(hours / 24)d \(hours % 24)h"
  }

  // 表格列排序键（KeyPathComparator 要求非 Optional 的 Comparable）
  var sortPort: Int { port ?? Int.max }
  var sortUptime: TimeInterval { startedAt.map { -$0.timeIntervalSinceNow } ?? 0 }
}

/* 本机服务间的 TCP 依赖边：src 进程连着 dst 进程监听的端口 */
struct ConnEdge: Hashable {
  var srcPid: Int
  var dstPid: Int
  var dstPort: Int
}

/* services.json 记录 — 与旧版（node）格式字段兼容 */
struct ServiceRecord: Codable, Identifiable, Hashable {
  var id: String
  var name: String = ""
  var command: String
  var cwd: String
  var port: Int?
  var categories: [String]? = []
  var title: String? = ""
  var tags: [String]? = []
  var lastSeenAt: String? = ""
  var favorite: Bool? = false
  // 观察到的依赖：其他记录的 id，或 "docker-port:<端口>"（docker 发布端口 → 容器）
  var dependsOn: [String]? = nil
  // 收藏的手动排序位（侧栏拖拽写入）；nil 排最后、按标题字母序兜底
  var sortOrder: Int? = nil

  var isFavorite: Bool { favorite ?? false }
}

/* 收藏卡片上显示的依赖状态行 */
struct DepStatus: Hashable, Identifiable {
  var id: String        // dependsOn 里的 key
  var label: String
  var port: Int?
  var scope: String = ""
  var running: Bool
  var uiPath: String = ""

  var isDocker: Bool { id.hasPrefix("docker-port:") }
}

/* 收藏操作面板的动作 */
enum ServiceAction {
  case start, restart, stop

  var label: String {
    switch self {
    case .start: return t("启动", "Start")
    case .restart: return t("重启", "Restart")
    case .stop: return t("关闭", "Stop")
    }
  }

  /* 完成时态，用于 toast 文案 */
  var done: String {
    switch self {
    case .start: return t("已启动", "Started")
    case .restart: return t("已重启", "Restarted")
    case .stop: return t("已关闭", "Stopped")
    }
  }

  /* 进行时态：操作要 1~2 秒（杀树+核对），先给即时反馈 */
  var doing: String {
    switch self {
    case .start: return t("正在启动…", "Starting…")
    case .restart: return t("正在重启…", "Restarting…")
    case .stop: return t("正在关闭…", "Stopping…")
    }
  }
}

struct FavoriteItem: Identifiable, Hashable {
  var record: ServiceRecord
  var running: Bool
  var livePort: Int?
  var liveScope: String = ""
  var liveUptime: String = ""
  var liveCpu: Double = 0
  var liveUiPath: String = ""
  var deps: [DepStatus] = []

  var id: String { record.id }
  var title: String {
    let t = record.title ?? ""
    return t.isEmpty ? record.name : t
  }
  var localUrl: URL? {
    guard running, let livePort else { return nil }
    return serviceURL(port: livePort, scope: liveScope, path: liveUiPath)
  }
}

struct SystemStats: Hashable {
  var cpuUsage: Double?      // 0~1，首次采样前为 nil
  var memUsedBytes: UInt64 = 0
  var memTotalBytes: UInt64 = 0

  var memUsage: Double? {
    memTotalBytes > 0 ? Double(memUsedBytes) / Double(memTotalBytes) : nil
  }
}

struct Snapshot {
  var generatedAt = Date()
  var ports: [PortRow] = []
  var agentProcesses: [PortRow] = []
  var stopped: [ServiceRecord] = []
  var favorites: [FavoriteItem] = []
  var connections: [ConnEdge] = []
  var system = SystemStats()

  var httpOkCount: Int { ports.filter { $0.http?.status == "ok" }.count }

  func count(of category: Category) -> Int {
    ports.filter { $0.category == category }.count
      + agentProcesses.filter { $0.category == category }.count
  }
}

enum SidebarSelection: Hashable {
  case home
  case all
  case category(Category)
  case stopped
  case ignored
}

/* 依赖分组：进程树（父子进程）+ 同项目目录（cwd 相同/互为子目录/同 .git 根）
   + TCP 依赖边（连着谁就挂到谁的组下）。同组服务折叠到代表行下。 */
func groupByDependency(_ rows: [PortRow], home: String, edges: [ConnEdge] = []) -> [PortRow] {
  guard rows.count > 1 else { return rows }

  var parent = Array(rows.indices)
  func find(_ x: Int) -> Int {
    var x = x
    while parent[x] != x {
      parent[x] = parent[parent[x]]
      x = parent[x]
    }
    return x
  }
  func union(_ a: Int, _ b: Int) { parent[find(a)] = find(b) }

  // agent（Claude/Codex 等）是会话启动器，不是项目成员，不参与分组
  func groupable(_ row: PortRow) -> Bool { row.category != .agent }

  // 1) 同 PID（一个进程多个端口）与进程树祖先关系
  var byPid: [Int: [Int]] = [:]
  for (index, row) in rows.enumerated() {
    byPid[row.pid, default: []].append(index)
  }
  for indices in byPid.values where indices.count > 1 {
    for index in indices.dropFirst() { union(indices[0], index) }
  }
  for (index, row) in rows.enumerated() where groupable(row) {
    for descendant in row.descendantPids {
      for other in byPid[descendant] ?? [] where groupable(rows[other]) {
        union(index, other)
      }
    }
  }

  // 2) 工作目录：相同或互为子目录。只认 home 下的目录——
  //    /opt/homebrew/var 这类系统目录会把 ollama/postgres 等无关服务误并一组
  func eligible(_ cwd: String) -> Bool {
    cwd != home && cwd.hasPrefix(home + "/")
      && cwd.split(separator: "/").count >= 3
  }
  for i in rows.indices where groupable(rows[i]) {
    let a = rows[i].cwd
    guard eligible(a) else { continue }
    for j in rows.indices where j > i && groupable(rows[j]) {
      let b = rows[j].cwd
      guard eligible(b) else { continue }
      let sameProjectRoot = !rows[i].projectRoot.isEmpty && rows[i].projectRoot == rows[j].projectRoot
      if a == b || a.hasPrefix(b + "/") || b.hasPrefix(a + "/") || sameProjectRoot { union(i, j) }
    }
  }

  var groups: [Int: [Int]] = [:]
  for index in rows.indices {
    groups[find(index), default: []].append(index)
  }

  // 门面 = 有标题且 HTTP 正常的页面（前端）。每个门面平级置顶，
  // 后端/辅助进程挂到工作目录最匹配的门面下。
  func isFacade(_ row: PortRow) -> Bool {
    !row.title.isEmpty && (row.http?.statusCode ?? 999) < 400
  }

  // 3) TCP 依赖边：某组真实连着的外部服务行（docker 端口、数据库等）挂过来。
  //    只在“唯一认领”时移动；被多个组共享的服务（如 ollama）保持独立，不误导归属。
  if !edges.isEmpty {
    var indexByPidPort: [String: Int] = [:]
    for (i, row) in rows.enumerated() where row.port != nil {
      indexByPidPort["\(row.pid):\(row.port!)"] = i
    }
    var groupOf: [Int: Int] = [:]
    for (key, members) in groups {
      for member in members { groupOf[member] = key }
    }
    var claims: [Int: Set<Int>] = [:]   // 目标行 -> 认领它的组
    for edge in edges {
      guard let target = indexByPidPort["\(edge.dstPid):\(edge.dstPort)"],
            groupable(rows[target]), !isFacade(rows[target]),
            let srcIndex = rows.firstIndex(where: { $0.pid == edge.srcPid }),
            let srcGroup = groupOf[srcIndex], groupOf[target] != srcGroup else { continue }
      claims[target, default: []].insert(srcGroup)
    }
    for (target, claimants) in claims where claimants.count == 1 {
      guard let from = groupOf[target] else { continue }
      groups[from]?.removeAll { $0 == target }
      if groups[from]?.isEmpty == true { groups[from] = nil }
      groups[claimants.first!, default: []].append(target)
    }
  }

  func matchScore(_ child: PortRow, _ facade: PortRow) -> Int {
    guard !child.cwd.isEmpty, !facade.cwd.isEmpty else { return 0 }
    if child.cwd == facade.cwd { return 1000 }
    var common = 0
    for (a, b) in zip(child.cwd.split(separator: "/"), facade.cwd.split(separator: "/")) {
      if a == b { common += 1 } else { break }
    }
    return common
  }

  var result: [PortRow] = []
  func appendHead(_ headIndex: Int, children childIndices: [Int]) {
    var head = rows[headIndex]
    let kids = childIndices
      .map { rows[$0] }
      .sorted { ($0.port ?? 0, $0.pid) < ($1.port ?? 0, $1.pid) }
    head.children = kids.isEmpty ? nil : kids
    result.append(head)
  }

  for members in groups.values {
    if members.count == 1 {
      appendHead(members[0], children: [])
      continue
    }
    let facades = members
      .filter { isFacade(rows[$0]) }
      .sorted { (rows[$0].port ?? 0, rows[$0].pid) < (rows[$1].port ?? 0, rows[$1].pid) }

    if facades.count > 1 {
      // 多个门面各自平级。成员优先挂到真实连着它的门面（TCP 依赖边，
      // 前端→后端→数据库 链式跟随）；没有边的按 cwd 最匹配（平手取端口小的）
      var facadeOf: [Int: Int] = [:]
      var pidToFacade: [Int: Int] = [:]
      for facade in facades where pidToFacade[rows[facade].pid] == nil {
        pidToFacade[rows[facade].pid] = facade
      }
      func edgeTarget(_ edge: ConnEdge) -> Int? {
        members.first {
          rows[$0].pid == edge.dstPid && rows[$0].port == edge.dstPort && !facades.contains($0)
        }
      }
      // 第一轮只吃门面直连边（确定性优先），之后两轮沿已归属成员链式传递
      for edge in edges {
        guard let target = edgeTarget(edge), facadeOf[target] == nil,
              let facade = pidToFacade[edge.srcPid] else { continue }
        facadeOf[target] = facade
      }
      for _ in 0..<2 {
        for edge in edges {
          guard let target = edgeTarget(edge), facadeOf[target] == nil,
                let srcMember = members.first(where: { rows[$0].pid == edge.srcPid }),
                let facade = facadeOf[srcMember] else { continue }
          facadeOf[target] = facade
        }
      }
      var kidsByFacade: [Int: [Int]] = [:]
      for member in members where !facades.contains(member) {
        var best = facadeOf[member] ?? facades[0]
        if facadeOf[member] == nil {
          var bestScore = matchScore(rows[member], rows[best])
          for facade in facades.dropFirst() {
            let score = matchScore(rows[member], rows[facade])
            if score > bestScore {
              best = facade
              bestScore = score
            }
          }
        }
        kidsByFacade[best, default: []].append(member)
      }
      for facade in facades {
        appendHead(facade, children: kidsByFacade[facade] ?? [])
      }
    } else {
      // 单门面（或没有门面）：门面优先做代表，否则取 cwd 最短者
      let head = facades.first ?? members.min { a, b in
        let lenA = rows[a].cwd.isEmpty ? Int.max : rows[a].cwd.count
        let lenB = rows[b].cwd.isEmpty ? Int.max : rows[b].cwd.count
        if lenA != lenB { return lenA < lenB }
        return (rows[a].port ?? 0, rows[a].pid) < (rows[b].port ?? 0, rows[b].pid)
      }!
      appendHead(head, children: members.filter { $0 != head })
    }
  }
  // 无端口的（agent 进程）排最后
  return result.sorted { ($0.port ?? Int.max, $0.pid) < ($1.port ?? Int.max, $1.pid) }
}
