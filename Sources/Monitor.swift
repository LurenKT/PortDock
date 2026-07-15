import Foundation

/* 核心引擎：lsof/ps 采集、分类、HTTP 探测、进程控制、服务记录。
   逻辑迁移自旧版 src/monitor.js，服务记录文件格式保持兼容。 */

enum Monitor {
  static let servicesFile = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent(".portdock/services.json")

  // 复用的格式器（DateFormatter 创建较贵，避免每轮新建）；ISO8601DateFormatter 线程安全
  static let isoFormatter = ISO8601DateFormatter()
  // services.json 写盘节流：records 每轮因 lastSeenAt 都在变，按时间降频落盘
  private static var lastServicesSave: Date?

  // MARK: - 模式表（与旧版一致）

  static let agentPatterns: [(String, String)] = [
    ("codex", "Codex"), ("claude", "Claude"), ("cursor", "Cursor"), ("opencode", "OpenCode")
  ]

  static let webPatterns: [(String, String)] = [
    ("vite", "Vite"), ("next", "Next.js"), ("nuxt", "Nuxt"), ("astro", "Astro"),
    ("webpack", "Webpack"), ("node", "Node"), ("npm ", "npm"), ("pnpm", "pnpm"),
    ("bun", "Bun"), ("deno", "Deno"), ("python", "Python"), ("http.server", "HTTP server"),
    ("uvicorn", "Uvicorn"), ("gunicorn", "Gunicorn"), ("flask", "Flask"),
    ("django", "Django"), ("rails", "Rails"), ("ruby", "Ruby"), ("php", "PHP")
  ]

  static let infraPatterns: [(String, String)] = [
    ("docker", "Docker"), ("postgres", "Postgres"), ("redis", "Redis"), ("mysql", "MySQL"),
    ("mariadb", "MariaDB"), ("mongod", "MongoDB"), ("mongo", "MongoDB"), ("ollama", "Ollama"),
    ("qdrant", "Qdrant"), ("chroma", "Chroma"), ("milvus", "Milvus"),
    ("elastic", "Elastic"), ("kafka", "Kafka")
  ]

  static let highRiskSubstrings = ["docker", "postgres", "redis", "mysql", "mariadb", "mongod", "ollama", "launchd"]

  static let httpHints = [
    "vite", "next", "nuxt", "astro", "webpack", "node", "bun", "deno", "python",
    "http.server", "uvicorn", "gunicorn", "flask", "django", "rails", "ruby", "php",
    "ollama", "codex", "claude"
  ]

  // MARK: - 命令执行

  static func run(_ path: String, _ args: [String]) async -> String {
    await withCheckedContinuation { continuation in
      DispatchQueue.global().async {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
          try process.run()
          let data = pipe.fileHandleForReading.readDataToEndOfFile()
          process.waitUntilExit()
          continuation.resume(returning: String(data: data, encoding: .utf8) ?? "")
        } catch {
          continuation.resume(returning: "")
        }
      }
    }
  }

  // MARK: - 分类

  static func classify(name: String, command: String) -> (Category, [String], Bool) {
    let text = "\(name) \(command)".lowercased()
    let processName = name.lowercased()
    var tags: [String] = []
    var category = Category.other

    for (pattern, label) in agentPatterns where processName == pattern || hasToken(text, pattern) {
      category = .agent
      tags.append(label)
    }
    if category == .other {
      for (pattern, label) in webPatterns where text.contains(pattern) {
        category = .web
        tags.append(label)
      }
    }
    if category == .other {
      for (pattern, label) in infraPatterns where text.contains(pattern) {
        category = .infra
        tags.append(label)
      }
    }

    var highRisk = highRiskSubstrings.contains { text.contains($0) }
    if !highRisk {
      highRisk = agentPatterns.contains { processName == $0.0 || hasToken(text, $0.0) }
    }
    var seen = Set<String>()
    let uniqueTags = tags.filter { seen.insert($0).inserted }
    return (category, uniqueTags.isEmpty ? [category.rawValue] : uniqueTags, highRisk)
  }

  static func hasToken(_ text: String, _ token: String) -> Bool {
    let escaped = NSRegularExpression.escapedPattern(for: token)
    guard let regex = try? NSRegularExpression(pattern: "(^|[\\s/\"'])\(escaped)([\\s/\"']|$)", options: [.caseInsensitive]) else { return false }
    return regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
  }

  // MARK: - ps 解析

  struct ProcInfo {
    var pid = 0, parentPid = 0
    var user = "", cpu = 0.0, memory = 0.0
    var started = "", startedAt: Date?
    var name = "", command = ""
    var children: [Int] = []
  }

  static let startedFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "EEE MMM d HH:mm:ss yyyy"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  static func parsePs(_ output: String) -> [Int: ProcInfo] {
    var processes: [Int: ProcInfo] = [:]
    for line in output.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard let first = trimmed.first, first.isNumber else { continue }
      let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
      guard parts.count >= 11, let pid = Int(parts[0]), let ppid = Int(parts[1]) else { continue }

      var info = ProcInfo()
      info.pid = pid
      info.parentPid = ppid
      info.user = parts[2]
      info.cpu = Double(parts[3]) ?? 0
      info.memory = Double(parts[4]) ?? 0
      info.started = parts[5...9].joined(separator: " ")
      info.startedAt = startedFormatter.date(from: info.started)
      let comm = parts[10]
      info.command = parts.count > 11 ? parts[11...].joined(separator: " ") : comm
      let firstArg = info.command.split(separator: " ").first.map(String.init) ?? comm
      info.name = URL(fileURLWithPath: firstArg == "-" ? comm : firstArg).lastPathComponent
      processes[pid] = info
    }
    for (pid, info) in processes {
      if var parent = processes[info.parentPid] {
        parent.children.append(pid)
        processes[info.parentPid] = parent
      }
    }
    return processes
  }

  static func descendants(of pid: Int, in processes: [Int: ProcInfo]) -> [Int] {
    var result: [Int] = []
    var queue = processes[pid]?.children ?? []
    while !queue.isEmpty {
      let child = queue.removeFirst()
      result.append(child)
      queue.append(contentsOf: processes[child]?.children ?? [])
    }
    return result
  }

  // MARK: - lsof 解析

  struct LsofRow {
    var pid = 0
    var processName = ""
    var proto = "TCP"
    var address = ""
    var port = 0
    var scope = ""
  }

  static func parseLsof(_ output: String) -> [LsofRow] {
    var rows: [LsofRow] = []
    var pid = 0
    var processName = ""
    var proto = "TCP"
    var seen = Set<String>()

    for line in output.split(separator: "\n") {
      guard let field = line.first else { continue }
      let value = String(line.dropFirst())
      switch field {
      case "p": pid = Int(value) ?? 0
      case "c": processName = value
      case "P": proto = value
      case "n":
        guard let endpoint = parseEndpoint(value) else { continue }
        let key = "\(pid):\(endpoint.0):\(endpoint.1)"
        guard seen.insert(key).inserted else { continue }
        var row = LsofRow()
        row.pid = pid
        row.processName = processName
        row.proto = proto
        row.address = endpoint.0
        row.port = endpoint.1
        row.scope = endpoint.0 == "*" ? "all"
          : (endpoint.0 == "localhost" || endpoint.0 == "::1" || endpoint.0.hasPrefix("127.")) ? "loopback" : "host"
        rows.append(row)
      default: break
      }
    }
    return rows
  }

  static func parseEndpoint(_ value: String) -> (String, Int)? {
    var clean = value
    if let range = clean.range(of: #"\s+\(LISTEN\)$"#, options: [.regularExpression, .caseInsensitive]) {
      clean.removeSubrange(range)
    }
    if clean.hasPrefix("["), let close = clean.firstIndex(of: "]") {
      let address = String(clean[clean.index(after: clean.startIndex)..<close])
      let rest = clean[clean.index(after: close)...]
      guard rest.hasPrefix(":"), let port = Int(rest.dropFirst()) else { return nil }
      return (address, port)
    }
    guard let colon = clean.lastIndex(of: ":"), let port = Int(clean[clean.index(after: colon)...]) else { return nil }
    let address = String(clean[..<colon])
    return (address.isEmpty ? "*" : address, port)
  }

  // MARK: - cwd（按 pid+启动时间缓存，避免每轮 fork lsof）

  private static var cwdCache: [Int: (started: String, cwd: String)] = [:]
  private static let cwdLock = NSLock()

  private static func cachedCwd(_ pid: Int) -> (started: String, cwd: String)? {
    cwdLock.lock()
    defer { cwdLock.unlock() }
    return cwdCache[pid]
  }

  private static func storeCwd(_ pid: Int, started: String, cwd: String) {
    cwdLock.lock()
    defer { cwdLock.unlock() }
    cwdCache[pid] = (started, cwd)
  }

  static func cwd(of pid: Int, started: String) async -> String {
    if let cached = cachedCwd(pid), cached.started == started {
      return cached.cwd
    }
    let output = await run("/usr/sbin/lsof", ["-a", "-p", String(pid), "-d", "cwd", "-Fn"])
    let cwd = output.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) } ?? ""
    storeCwd(pid, started: started, cwd: cwd)
    return cwd
  }

  /// 批量补全 cwd：cache 未命中的 pid 用**一条** lsof 查询，取代每进程 fork 一个子进程。
  static func fillCwd(_ rows: inout [PortRow]) async {
    let missing = Set(rows.filter { cachedCwd($0.pid)?.started != $0.started }.map(\.pid))
    var fetched: [Int: String] = [:]
    if !missing.isEmpty {
      let arg = missing.map(String.init).joined(separator: ",")
      let output = await run("/usr/sbin/lsof", ["-a", "-p", arg, "-d", "cwd", "-Fpn"])
      var pid: Int?
      for line in output.split(separator: "\n") {
        if line.hasPrefix("p") {
          pid = Int(line.dropFirst())
        } else if line.hasPrefix("n"), let p = pid {
          fetched[p] = String(line.dropFirst())
        }
      }
    }
    for i in rows.indices {
      if let c = cachedCwd(rows[i].pid), c.started == rows[i].started {
        rows[i].cwd = c.cwd
      } else {
        let cwd = fetched[rows[i].pid] ?? ""
        rows[i].cwd = cwd
        storeCwd(rows[i].pid, started: rows[i].started, cwd: cwd)
      }
    }
  }

  // MARK: - 项目根（最近的含 .git 的祖先目录）

  // ponytail: 缓存永不失效——.git 目录基本不会移动，移动了重启 app 即可
  private static var projectRootCache: [String: String] = [:]

  static func projectRoot(of cwd: String) -> String {
    guard !cwd.isEmpty, cwd != "/" else { return "" }
    if let cached = projectRootCache[cwd] { return cached }
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    var dir = URL(fileURLWithPath: cwd)
    var root = ""
    while dir.path != "/" && dir.path != home {
      if FileManager.default.fileExists(atPath: dir.appendingPathComponent(".git").path) {
        root = dir.path
        break
      }
      dir.deleteLastPathComponent()
    }
    // 只认 home 下的项目仓库；/opt/homebrew 这类系统 git 仓库会把所有
    // brew 服务误判成同一项目（2026-07-15 真机实测）
    if !root.hasPrefix(home + "/") { root = "" }
    projectRootCache[cwd] = root
    return root
  }

  // MARK: - 服务间 TCP 依赖边

  /* ESTABLISHED 连接 → 依赖边。只认「web/infra 服务进程 → 本机监听端口」，
     排除 PortDock 自己的探测连接和浏览器等杂音。
     ponytail: 不监听端口的进程（如 worker）连出去的边收不到，需要时再放宽 src 条件 */
  static func parseConnections(_ output: String, ports: [PortRow]) -> [ConnEdge] {
    var pidByListenPort: [Int: Int] = [:]
    var categoryByPid: [Int: Category] = [:]
    for row in ports {
      if let port = row.port, pidByListenPort[port] == nil { pidByListenPort[port] = row.pid }
      categoryByPid[row.pid] = row.category
    }
    let selfPid = Int(ProcessInfo.processInfo.processIdentifier)
    var edges = Set<ConnEdge>()
    var pid = 0
    for line in output.split(separator: "\n") {
      guard let field = line.first else { continue }
      let value = String(line.dropFirst())
      if field == "p" { pid = Int(value) ?? 0; continue }
      guard field == "n", pid != selfPid,
            let category = categoryByPid[pid], category == .web || category == .infra else { continue }
      let endpoint = value.split(separator: " ").first.map(String.init) ?? value
      let sides = endpoint.components(separatedBy: "->")
      guard sides.count == 2,
            let local = parseEndpoint(sides[0]), let remote = parseEndpoint(sides[1]) else { continue }
      let loopback = remote.0 == "localhost" || remote.0 == "::1" || remote.0.hasPrefix("127.")
      guard loopback,
            let dstPid = pidByListenPort[remote.1], dstPid != pid,
            pidByListenPort[local.1] == nil else { continue }   // local 端是监听端口 = 服务端 fd，跳过
      edges.insert(ConnEdge(srcPid: pid, dstPid: dstPid, dstPort: remote.1))
    }
    return Array(edges)
  }

  /* 把监听进程解析成“可重放”的启动命令：沿进程树向上走，cwd 相同且不是
     shell/agent 的最高祖先（uvicorn reload 的 spawn 子进程 → uvicorn 本体，
     vite → npm run dev）。重放它才能真正把服务再拉起来。 */
  static func replayableService(
    for row: PortRow, processes: [Int: ProcInfo], listenPortsByPid: [Int: Set<Int>]
  ) async -> (id: String, command: String, cwd: String)? {
    guard !row.cwd.isEmpty, row.cwd != "/" else { return nil }
    let shells: Set<String> = ["zsh", "bash", "sh", "fish", "dash", "login", "tmux", "screen", "sshd", "launchd"]
    var best = processes[row.pid]
    var current = best
    while let parent = (current?.parentPid).flatMap({ processes[$0] }), parent.pid > 1 {
      // login shell 的进程名带前导连字符（-bash/-zsh），去掉再比对
      let name = parent.name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "-"))
      if shells.contains(name) || classify(name: parent.name, command: parent.command).0 == .agent { break }
      // 祖先自己监听着别的端口 = 它是另一个服务（监督者，如 test-console 拉起后端），
      // 不能把它当作本服务的启动命令。同端口的除外（uvicorn reload 主进程）。
      if let parentPorts = listenPortsByPid[parent.pid],
         !parentPorts.subtracting([row.port ?? -1]).isEmpty { break }
      guard await cwd(of: parent.pid, started: parent.started) == row.cwd else { break }
      best = parent
      current = parent
    }
    let command = best?.command ?? row.command
    guard !command.isEmpty else { return nil }
    return ("\(row.cwd)::\(command)", command, row.cwd)
  }

  // MARK: - HTTP 探测

  static let probeSession: URLSession = {
    let config = URLSessionConfiguration.ephemeral
    config.timeoutIntervalForRequest = 0.8
    config.timeoutIntervalForResource = 1.5
    config.httpAdditionalHeaders = ["User-Agent": "portdock-native-monitor"]
    return URLSession(configuration: config)
  }()

  static func probe(port: Int) async -> ProbeResult {
    let started = Date()
    guard let url = URL(string: "http://127.0.0.1:\(port)/") else {
      return ProbeResult(status: "error")
    }
    do {
      let (data, response) = try await probeSession.data(from: url)
      let latency = Int(Date().timeIntervalSince(started) * 1000)
      guard let http = response as? HTTPURLResponse else {
        return ProbeResult(status: "error", latencyMs: latency)
      }
      let body = String(data: data.prefix(64 * 1024), encoding: .utf8) ?? ""
      return ProbeResult(status: "ok", statusCode: http.statusCode, latencyMs: latency, title: extractTitle(body))
    } catch {
      return ProbeResult(status: "error", latencyMs: Int(Date().timeIntervalSince(started) * 1000))
    }
  }

  static func extractTitle(_ body: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: "<title[^>]*>([^<]*)</title>", options: [.caseInsensitive]),
          let match = regex.firstMatch(in: body, range: NSRange(body.startIndex..., in: body)),
          let range = Range(match.range(at: 1), in: body) else { return "" }
    return String(body[range])
      .replacingOccurrences(of: "&amp;", with: "&")
      .replacingOccurrences(of: "&lt;", with: "<")
      .replacingOccurrences(of: "&gt;", with: ">")
      .replacingOccurrences(of: "&quot;", with: "\"")
      .replacingOccurrences(of: "&#39;", with: "'")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  // MARK: - 快照

  static func collectSnapshot() async -> Snapshot {
    async let lsofOutput = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcnP"])
    async let establishedOutput = run("/usr/sbin/lsof", ["-nP", "-iTCP", "-sTCP:ESTABLISHED", "-F", "pcnP"])
    async let psOutput = run("/bin/ps", ["-axo", "pid,ppid,user,pcpu,pmem,lstart,comm,args"])

    let processes = parsePs(await psOutput)
    let lsofRows = parseLsof(await lsofOutput)

    var ports: [PortRow] = []
    for lsofRow in lsofRows {
      var row = PortRow(pid: lsofRow.pid)
      row.port = lsofRow.port
      row.address = lsofRow.address
      row.proto = lsofRow.proto
      row.scope = lsofRow.scope
      if let info = processes[lsofRow.pid] {
        row.name = info.name
        row.command = info.command
        row.user = info.user
        row.parentPid = info.parentPid
        row.cpu = info.cpu
        row.memory = info.memory
        row.started = info.started
        row.startedAt = info.startedAt
        row.descendantPids = descendants(of: lsofRow.pid, in: processes)
      } else {
        row.name = lsofRow.processName
        row.command = lsofRow.processName
      }
      (row.category, row.tags, row.highRisk) = classify(name: row.name, command: row.command)
      ports.append(row)
    }

    // 无端口的 agent 进程
    let portPids = Set(ports.map(\.pid))
    var agents: [PortRow] = []
    for (pid, info) in processes where !portPids.contains(pid) {
      let (category, tags, highRisk) = classify(name: info.name, command: info.command)
      guard category == .agent else { continue }
      var row = PortRow(pid: pid)
      row.name = info.name
      row.command = info.command
      row.user = info.user
      row.parentPid = info.parentPid
      row.cpu = info.cpu
      row.memory = info.memory
      row.started = info.started
      row.startedAt = info.startedAt
      row.descendantPids = descendants(of: pid, in: processes)
      row.category = category
      row.tags = tags
      row.highRisk = highRisk
      agents.append(row)
    }
    agents.sort { $0.name.localizedCompare($1.name) == .orderedAscending || ($0.name == $1.name && $0.pid < $1.pid) }

    // cwd 补全：一条 lsof 批量查所有未缓存 pid（消除每进程 fork 一个子进程的风暴）
    await fillCwd(&ports)
    await fillCwd(&agents)
    for i in ports.indices { ports[i].projectRoot = projectRoot(of: ports[i].cwd) }
    for i in agents.indices { agents[i].projectRoot = projectRoot(of: agents[i].cwd) }

    let liveEdges = parseConnections(await establishedOutput, ports: ports)

    await withTaskGroup(of: (Int, ProbeResult).self) { group in
      for (index, row) in ports.enumerated() {
        guard let port = row.port else { continue }
        let text = "\(row.name) \(row.command)".lowercased()
        guard httpHints.contains(where: { text.contains($0) }) else { continue }
        group.addTask { (index, await probe(port: port)) }
      }
      for await (index, result) in group {
        ports[index].http = result
      }
    }

    ports.sort { ($0.port ?? 0, $0.pid) < ($1.port ?? 0, $1.pid) }

    // 服务记录同步
    var records = loadServices()
    let now = Date()
    let nowIso = isoFormatter.string(from: now)
    for row in ports {
      guard let id = row.serviceId, let port = row.port, port != 0 else { continue }
      let existing = records[id]
      if existing == nil && row.category != .web { continue }
      var record = existing ?? ServiceRecord(id: id, command: row.command, cwd: row.cwd)
      record.name = row.name
      record.command = row.command
      record.cwd = row.cwd
      record.port = port
      record.categories = [row.category.rawValue]
      record.tags = row.tags
      if !row.title.isEmpty { record.title = row.title }
      record.lastSeenAt = nowIso
      records[id] = record
    }
    // 依赖边落盘：给启动级联用。目标解析成可重放的祖先命令再记 id。
    var listenPortsByPid: [Int: Set<Int>] = [:]
    for row in ports {
      if let port = row.port { listenPortsByPid[row.pid, default: []].insert(port) }
    }
    var depsChanged = false
    for edge in liveEdges {
      guard let srcRow = ports.first(where: { $0.pid == edge.srcPid && $0.serviceId != nil }),
            let srcId = srcRow.serviceId, records[srcId] != nil,
            let dstRow = ports.first(where: { $0.pid == edge.dstPid && $0.port == edge.dstPort }) else { continue }
      var dep: String
      if dstRow.command.lowercased().contains("docker") {
        dep = "docker-port:\(edge.dstPort)"
      } else if let target = await replayableService(
                  for: dstRow, processes: processes, listenPortsByPid: listenPortsByPid) {
        dep = target.id
        if records[dep] == nil {
          var record = ServiceRecord(id: dep, command: target.command, cwd: target.cwd)
          record.name = dstRow.name
          record.port = dstRow.port
          record.categories = [dstRow.category.rawValue]
          record.tags = dstRow.tags
          record.lastSeenAt = nowIso
          records[dep] = record
          depsChanged = true
        }
      } else { continue }
      guard dep != srcId else { continue }
      var deps = Set(records[srcId]?.dependsOn ?? [])
      if deps.insert(dep).inserted {
        records[srcId]?.dependsOn = deps.sorted()
        depsChanged = true
      }
    }

    // 已记录的依赖回放成边：连接是瞬时的（vite 只在代理请求时连后端），
    // 学到过的父子关系在两端都活着时保持稳定显示，不随流量闪烁。
    var edges = Set(liveEdges)
    let liveRowById = Dictionary(ports.compactMap { row in row.serviceId.map { ($0, row) } },
                                 uniquingKeysWith: { first, _ in first })
    for record in records.values {
      guard let srcRow = liveRowById[record.id] else { continue }
      for dep in record.dependsOn ?? [] {
        var dstRow: PortRow?
        if dep.hasPrefix("docker-port:") {
          let port = Int(dep.dropFirst("docker-port:".count))
          dstRow = ports.first { $0.port == port && $0.command.lowercased().contains("docker") }
        } else {
          dstRow = liveRowById[dep]
          // 依赖记的是可重放根命令，监听进程可能是它的子进程（命令串不同），
          // 兜底用 端口+工作目录 匹配活进程
          if dstRow == nil, let depRecord = records[dep], let depPort = depRecord.port {
            dstRow = ports.first { $0.port == depPort && $0.cwd == depRecord.cwd }
          }
        }
        if let dstRow, let dstPort = dstRow.port, dstRow.pid != srcRow.pid {
          edges.insert(ConnEdge(srcPid: srcRow.pid, dstPid: dstRow.pid, dstPort: dstPort))
        }
      }
    }

    // 写盘节流：records 大多只是 lastSeenAt 在变，30 秒才落一次盘；
    // 用户操作（收藏/移除）走 setFavorite/forgetService 立即写，不受此影响。
    // 新学到依赖边时立即写，不等节流窗口。
    if depsChanged || lastServicesSave == nil || now.timeIntervalSince(lastServicesSave!) >= 30 {
      saveServices(records)
      lastServicesSave = now
    }

    let runningIds = Set(ports.compactMap(\.serviceId))
    let stopped = records.values
      .filter { !runningIds.contains($0.id) && !$0.isFavorite }
      .sorted { ($0.lastSeenAt ?? "") > ($1.lastSeenAt ?? "") }

    // 同一进程可能监听多个端口（如 Docker backend），serviceId 会重复，保留第一个
    let liveById = Dictionary(ports.compactMap { row in
      row.serviceId.map { ($0, row) }
    }, uniquingKeysWith: { first, _ in first })
    // 收藏卡片的依赖状态行（标签取依赖 cwd 的目录名，与列表里 cleanSubtitle 的兜底一致）。
    // 递归展开整条链（前端→后端→docker）；同 port+cwd 的记录视为同一服务的不同
    // 命令形态（监听子进程 vs 可重放根命令），合并它们的 dependsOn 防止断链。
    let livePortSet = Set(ports.compactMap(\.port))
    func depStatuses(_ record: ServiceRecord) -> [DepStatus] {
      func depsOf(_ rec: ServiceRecord) -> [String] {
        var ids = Set(rec.dependsOn ?? [])
        for other in records.values
        where other.id != rec.id && other.port == rec.port && other.cwd == rec.cwd {
          ids.formUnion(other.dependsOn ?? [])
        }
        return ids.sorted()
      }
      var seen: Set<String> = [record.id]
      var result: [DepStatus] = []
      func walk(_ rec: ServiceRecord) {
        for dep in depsOf(rec) where seen.insert(dep).inserted {
          if dep.hasPrefix("docker-port:") {
            let port = Int(dep.dropFirst("docker-port:".count))
            result.append(DepStatus(
              id: dep, label: "Docker 容器", port: port,
              scope: port.flatMap { p in ports.first { $0.port == p }?.scope } ?? "",
              running: port.map(livePortSet.contains) ?? false))
            continue
          }
          let depRecord = records[dep]
          let live = liveById[dep]
            ?? depRecord.flatMap { rec in
              rec.port.flatMap { port in ports.first { $0.port == port && $0.cwd == rec.cwd } }
            }
          let cwdName = depRecord.map { URL(fileURLWithPath: $0.cwd).lastPathComponent } ?? ""
          result.append(DepStatus(
            id: dep,
            label: cwdName.isEmpty ? (depRecord?.name ?? "未知服务") : cwdName,
            port: live?.port ?? depRecord?.port,
            scope: live?.scope ?? "",
            running: live != nil))
          if let depRecord { walk(depRecord) }
        }
      }
      walk(record)
      return result
    }
    let favorites = records.values
      .filter(\.isFavorite)
      .map { record -> FavoriteItem in
        let live = liveById[record.id]
        return FavoriteItem(
          record: record,
          running: live != nil,
          livePort: live?.port,
          liveScope: live?.scope ?? "",
          liveUptime: live?.uptime ?? "",
          liveCpu: live?.cpu ?? 0,
          deps: depStatuses(record)
        )
      }
      .sorted { $0.title.localizedCompare($1.title) == .orderedAscending }

    var snapshot = Snapshot()
    snapshot.ports = ports
    snapshot.agentProcesses = agents
    snapshot.stopped = stopped
    snapshot.favorites = favorites
    snapshot.connections = Array(edges)
    snapshot.system = systemStats()
    return snapshot
  }

  // MARK: - 系统状态（mach API，CPU 需两次采样求差值）

  private static var prevCpuTicks: (user: Double, system: Double, idle: Double, nice: Double)?

  static func systemStats() -> SystemStats {
    var stats = SystemStats()

    var loadInfo = host_cpu_load_info()
    var count = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info>.stride / MemoryLayout<integer_t>.stride)
    let cpuResult = withUnsafeMutablePointer(to: &loadInfo) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
        host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
      }
    }
    if cpuResult == KERN_SUCCESS {
      let ticks = (
        user: Double(loadInfo.cpu_ticks.0),
        system: Double(loadInfo.cpu_ticks.1),
        idle: Double(loadInfo.cpu_ticks.2),
        nice: Double(loadInfo.cpu_ticks.3)
      )
      if let prev = prevCpuTicks {
        let total = (ticks.user - prev.user) + (ticks.system - prev.system)
          + (ticks.idle - prev.idle) + (ticks.nice - prev.nice)
        if total > 0 {
          stats.cpuUsage = max(0, min(1, 1 - (ticks.idle - prev.idle) / total))
        }
      }
      prevCpuTicks = ticks
    }

    stats.memTotalBytes = ProcessInfo.processInfo.physicalMemory
    var vmStats = vm_statistics64()
    var vmCount = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
    let vmResult = withUnsafeMutablePointer(to: &vmStats) {
      $0.withMemoryRebound(to: integer_t.self, capacity: Int(vmCount)) {
        host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &vmCount)
      }
    }
    if vmResult == KERN_SUCCESS {
      let pageSize = UInt64(vm_kernel_page_size)
      stats.memUsedBytes = (UInt64(vmStats.active_count) + UInt64(vmStats.wire_count)
        + UInt64(vmStats.compressor_page_count)) * pageSize
    }
    return stats
  }

  // MARK: - 服务记录

  static func loadServices() -> [String: ServiceRecord] {
    guard let data = try? Data(contentsOf: servicesFile),
          let records = try? JSONDecoder().decode([String: ServiceRecord].self, from: data) else { return [:] }
    return records
  }

  static func saveServices(_ records: [String: ServiceRecord]) {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let data = try? encoder.encode(records) else { return }
    try? FileManager.default.createDirectory(
      at: servicesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try? data.write(to: servicesFile)
  }

  static func setFavorite(id: String, favorite: Bool, from row: PortRow? = nil) {
    var records = loadServices()
    if records[id] == nil {
      guard let row, let serviceId = row.serviceId else { return }
      var record = ServiceRecord(id: serviceId, command: row.command, cwd: row.cwd)
      record.name = row.name
      record.port = row.port
      record.categories = [row.category.rawValue]
      record.tags = row.tags
      record.title = row.title
      record.lastSeenAt = isoFormatter.string(from: Date())
      records[serviceId] = record
    }
    records[id]?.favorite = favorite
    saveServices(records)
  }

  static func forgetService(id: String) {
    var records = loadServices()
    records.removeValue(forKey: id)
    saveServices(records)
  }

  // MARK: - 进程控制

  struct ActionResult {
    var ok: Bool
    var message: String
  }

  static func killTree(pid: Int, includeChildren: Bool, force: Bool) async -> ActionResult {
    if pid == Int(ProcessInfo.processInfo.processIdentifier) || pid <= 1 {
      return ActionResult(ok: false, message: "该进程受保护")
    }
    let processes = parsePs(await run("/bin/ps", ["-axo", "pid,ppid,user,pcpu,pmem,lstart,comm,args"]))
    guard let target = processes[pid] else {
      return ActionResult(ok: false, message: "PID \(pid) 不存在")
    }
    if target.user != NSUserName() {
      return ActionResult(ok: false, message: "不能结束其他用户的进程")
    }

    var targets = includeChildren ? descendants(of: pid, in: processes).reversed() + [pid] : [pid]
    targets = targets.filter { $0 > 1 && $0 != Int(ProcessInfo.processInfo.processIdentifier) }
    let signal: Int32 = force ? SIGKILL : SIGTERM
    var failed: [Int] = []
    for targetPid in targets where kill(Int32(targetPid), signal) != 0 && errno != ESRCH {
      failed.append(targetPid)
    }
    try? await Task.sleep(nanoseconds: force ? 250_000_000 : 600_000_000)

    let after = parsePs(await run("/bin/ps", ["-axo", "pid,ppid,user,pcpu,pmem,lstart,comm,args"]))
    let stillAlive = targets.filter { after[$0] != nil }
    if !failed.isEmpty {
      return ActionResult(ok: false, message: "部分进程无法结束: \(failed.map(String.init).joined(separator: ", "))")
    }
    if !stillAlive.isEmpty {
      return ActionResult(ok: false, message: "仍在运行: \(stillAlive.map(String.init).joined(separator: ", "))")
    }
    return ActionResult(ok: true, message: "已结束进程")
  }

  /* 脱离 app 生命周期启动：sh 派生后台孙进程后立即退出，服务挂到 launchd */
  static func spawnDetached(command: String, cwd: String) -> ActionResult {
    guard FileManager.default.fileExists(atPath: cwd) else {
      return ActionResult(ok: false, message: "工作目录不存在: \(cwd)")
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sh")
    process.arguments = ["-c", "cd \(shellQuote(cwd)) && nohup \(command) >/dev/null 2>&1 &"]
    do {
      try process.run()
      return ActionResult(ok: true, message: "已发起启动")
    } catch {
      return ActionResult(ok: false, message: "启动失败: \(error.localizedDescription)")
    }
  }

  static func shellQuote(_ value: String) -> String {
    "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
  }

  static func restart(row: PortRow, force: Bool = false) async -> ActionResult {
    guard !row.command.isEmpty, !row.cwd.isEmpty else {
      return ActionResult(ok: false, message: "拿不到启动命令或工作目录，无法重启")
    }
    let killResult = await killTree(pid: row.pid, includeChildren: true, force: force)
    guard killResult.ok else { return killResult }
    try? await Task.sleep(nanoseconds: 400_000_000)
    let started = spawnDetached(command: row.command, cwd: row.cwd)
    return started.ok ? ActionResult(ok: true, message: "已重启") : started
  }

  static func startService(_ record: ServiceRecord) -> ActionResult {
    spawnDetached(command: record.command, cwd: record.cwd)
  }

  /* docker 容器操作（按发布端口定位容器）。start 会先唤起 Docker Desktop 并等 daemon */
  static func dockerAction(_ verb: String, publishPort: Int) -> ActionResult {
    var script = "export PATH=\"/usr/local/bin:/opt/homebrew/bin:$PATH\"; "
    if verb == "start" {
      // ponytail: 等 docker daemon 最多 30s，daemon 起不来就静默放弃
      script += "open -ga Docker >/dev/null 2>&1; "
        + "for i in $(seq 30); do docker info >/dev/null 2>&1 && break; sleep 1; done; "
    }
    script += "docker \(verb) $(docker ps -aq --filter publish=\(publishPort))"
    return spawnDetached(command: "sh -c \(shellQuote(script))", cwd: NSHomeDirectory())
  }

  /* 级联启动：先递归拉起没在跑的依赖（后端、数据库、docker 容器），再启动自己。
     返回实际发起启动的依赖名，供 toast 展示。 */
  static func startWithDependencies(
    _ record: ServiceRecord, runningIds: Set<String>, runningPorts: Set<Int>
  ) -> (result: ActionResult, startedDeps: [String]) {
    let records = loadServices()
    var startedDeps: [String] = []
    var visited: Set<String> = [record.id]

    func startDeps(of rec: ServiceRecord) {
      for dep in rec.dependsOn ?? [] where visited.insert(dep).inserted {
        if dep.hasPrefix("docker-port:") {
          guard let port = Int(dep.dropFirst("docker-port:".count)), !runningPorts.contains(port) else { continue }
          if dockerAction("start", publishPort: port).ok {
            startedDeps.append("docker:\(port)")
          }
        } else if let depRecord = records[dep], !runningIds.contains(dep) {
          startDeps(of: depRecord)   // 先起更深层的依赖（db 先于后端）
          if spawnDetached(command: depRecord.command, cwd: depRecord.cwd).ok {
            startedDeps.append(depRecord.name.isEmpty ? "端口 \(depRecord.port ?? 0)" : depRecord.name)
          }
        }
      }
    }

    startDeps(of: record)
    return (spawnDetached(command: record.command, cwd: record.cwd), startedDeps)
  }
}
