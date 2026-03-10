//
//  RollingFilmApp.swift
//  RollingFilm
//
//  Created by 啊傻傻傻 on 2026/3/10.
//

import SwiftUI
import SwiftData

@main
struct RollingFilmApp: App {
    // 1. 在这里直接持有单例引用，确保 App 一启动就激活 WCSession
    let sessionDelegator = SessionDelegator.shared

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            FilmRoll.self,
            FilmFrame.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    init() {
        // 2. 在初始化时就注入 Container，比 .onAppear 更早、更稳
        SessionDelegator.shared.modelContainer = sharedModelContainer
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
