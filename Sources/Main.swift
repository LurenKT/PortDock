import SwiftUI

@main
struct PortDockApp: App {
  @StateObject private var state = AppState()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environmentObject(state)
        .frame(minWidth: 860, minHeight: 520)
        .task { state.start() }
    }
    .defaultSize(width: 1200, height: 780)
  }
}
