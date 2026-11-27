import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(0)
            PreferencesView()
                .tabItem { Label("Preferences", systemImage: "gearshape") }
                .tag(1)
            AboutView()
                .tabItem { Label("Tentang", systemImage: "info.circle") }
                .tag(2)
        }
        .frame(minWidth: 780, minHeight: 560)
    }
}
