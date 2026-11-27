import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "gauge.with.dots.needle.67percent") }
                .tag(0)
            InspectorView()
                .tabItem { Label("EFI & ACPI", systemImage: "doc.text.magnifyingglass") }
                .tag(1)
            PreferencesView()
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(2)
        }
        .frame(minWidth: 780, minHeight: 560)
    }
}
