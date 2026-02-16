import SwiftUI

@main
struct BlackHoleApp: App {
    var body: some Scene {
        WindowGroup {
            MetalView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 800, height: 600)
    }
}
