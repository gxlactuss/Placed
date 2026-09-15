import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

enum PPAppearance {

    static func configure() {
        #if canImport(UIKit)
        configureTabBar()
        configureNavigationBar()
        #endif
    }

    #if canImport(UIKit)
    private static func configureTabBar() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.ppSurface)
        appearance.shadowColor = UIColor(Color.ppBorder)

        for layout in [
            appearance.stackedLayoutAppearance,
            appearance.inlineLayoutAppearance,
            appearance.compactInlineLayoutAppearance,
        ] {
            layout.normal.iconColor = UIColor(Color.ppMuted)
            layout.normal.titleTextAttributes = [
                .foregroundColor: UIColor(Color.ppMuted)
            ]
            layout.selected.iconColor = UIColor(Color.ppAccent400)
            layout.selected.titleTextAttributes = [
                .foregroundColor: UIColor(Color.ppAccent400)
            ]
        }

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    private static func configureNavigationBar() {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(Color.ppGround)
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor(Color.ppText)]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor(Color.ppText)]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
        UINavigationBar.appearance().compactAppearance = appearance
    }
    #endif
}
