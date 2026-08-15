import SwiftUI

enum RootTab: Hashable {
    case today, review, history, library
}

struct RootView: View {
    @Environment(AppRouter.self) private var router

    var body: some View {
        @Bindable var router = router

        TabView(selection: $router.selectedTab) {
            TodayView()
                .tabItem { Label("오늘", systemImage: "clock") }
                .tag(RootTab.today)

            ReviewHomeView()
                .tabItem { Label("복습", systemImage: "rectangle.on.rectangle") }
                .tag(RootTab.review)

            HistoryView()
                .tabItem { Label("기록", systemImage: "calendar") }
                .tag(RootTab.history)

            LibraryView()
                .tabItem { Label("라이브러리", systemImage: "archivebox") }
                .tag(RootTab.library)
        }
        .background(Palette.surface)
    }
}

/// 화면 전체에 깔리는 바닥. 카드가 떠 보이도록 탭 배경보다 어둡다.
struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollContentBackground(.hidden)
            .background(Palette.surface.ignoresSafeArea())
    }
}

extension View {
    func screenBackground() -> some View { modifier(ScreenBackground()) }
}
