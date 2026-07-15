import Foundation

// 语言设置："system" 跟随系统 / "zh" / "en"。切换即时生效：
// ContentView 与 MenuBarView 以 .id(lang) 整树重建，无需重启。
let langKey = "portdock-lang"

private var isZh: Bool {
  switch UserDefaults.standard.string(forKey: langKey) ?? "system" {
  case "zh": return true
  case "en": return false
  default: return Locale.preferredLanguages.first?.hasPrefix("zh") ?? false
  }
}

/// 本地化取词：t("中文", "English")。翻译贴在调用点，免键名间接层。
/// ponytail: 两语内联够用；真要加第三语言再换字典方案
func t(_ zh: String, _ en: String) -> String { isZh ? zh : en }
