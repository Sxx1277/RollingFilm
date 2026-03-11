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
        Self.backfillRollUUIDsIfNeeded(in: sharedModelContainer)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .modelContainer(sharedModelContainer)
    }

    /// 启动时回填历史数据：旧版本没有 rollUUID 时，自动补齐并保存。
    private static func backfillRollUUIDsIfNeeded(in container: ModelContainer) {
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<FilmRoll>()
        guard let rolls = try? context.fetch(descriptor), !rolls.isEmpty else { return }

        var didUpdate = false
        let activeRolls = rolls.filter { $0.isActive }
        let keepActiveUUID = activeRolls
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .rollUUID

        for roll in rolls {
            if roll.rollUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                roll.rollUUID = UUID().uuidString
                didUpdate = true
            }
            if roll.filmType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                roll.filmType = roll.name
                didUpdate = true
            }
            if roll.createdAt.timeIntervalSince1970 <= 0 {
                roll.createdAt = roll.loadDate
                didUpdate = true
            }
            let shouldBeActive = (roll.rollUUID == keepActiveUUID)
            if roll.isActive != shouldBeActive {
                roll.isActive = shouldBeActive
                didUpdate = true
            }
        }

        if didUpdate {
            try? context.save()
        }
    }
}
