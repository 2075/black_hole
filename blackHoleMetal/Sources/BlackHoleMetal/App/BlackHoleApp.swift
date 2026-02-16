import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct BlackHoleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var fpsCounter = FPSCounter()

    var body: some Scene {
        WindowGroup {
            ZStack(alignment: .topTrailing) {
                MetalView(fpsCounter: fpsCounter)
                Text("\(Int(fpsCounter.fps)) FPS")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(8)
            }
            .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
    }
}
