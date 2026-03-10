//
//  RollingFilm_WatchApp.swift
//  RollingFilm Watch Watch App
//

import SwiftUI

@main
struct RollingFilm_Watch_Watch_AppApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    WatchSessionDelegator.shared.activateSession()
                }
        }
    }
}
