//
//  SessionDelegator.swift
//  RollingFilm
//
//  iPhone 与 Watch 双向同步：接收 Watch 记录写入 SwiftData，向 Watch 同步当前选中胶卷。
//

import Foundation
import Combine
import WatchConnectivity
import SwiftData

final class SessionDelegator: NSObject, ObservableObject {
    static let shared = SessionDelegator()

    /// 由 App 启动时注入，用于创建 ModelContext 写入 SwiftData
    var modelContainer: ModelContainer?

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - 同步选中胶卷到 Watch（更新 Watch 顶部标题）

    /// 将当前选中的胶卷名（及 rollId）发送给 Watch，Watch 用于更新顶部标题与记录归属
    func sendCurrentRoll(roll: FilmRoll) {
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired else { return }
        let rollId: String
        if let data = try? JSONEncoder().encode(roll.persistentModelID) {
            rollId = data.base64EncodedString()
        } else { return }
        let payload: [String: Any] = [
            IOSMessageKey.action: IOSMessageAction.setCurrentRoll.rawValue,
            IOSMessageKey.rollId: rollId,
            IOSMessageKey.rollName: roll.name,
        ]
        try? session.updateApplicationContext(payload)
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
    }

    // MARK: - 接收 Watch 发来的记录并写入 SwiftData

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handleReceivedLogFrame(userInfo)
        }
    }

    /// 收到 Watch 的 logFrame 数据（transferUserInfo / sendMessage）后：按 rollName 查找 FilmRoll，创建 FilmFrame 并保存
    private func handleReceivedLogFrame(_ payload: [String: Any]) {
        guard let container = modelContainer else { return }
        guard let aperture = payload[IOSMessageKey.aperture] as? String,
              let shutter = payload[IOSMessageKey.shutter] as? String else { return }

        let timestamp: Date
        if let t = payload[IOSMessageKey.timestamp] as? TimeInterval {
            timestamp = Date(timeIntervalSince1970: t)
        } else {
            timestamp = Date()
        }

        let context = ModelContext(container)
        context.autosaveEnabled = true

        // 优先根据 rollName 查找胶卷；若无则尝试 rollId（兼容旧版 Watch）
        var roll: FilmRoll?
        if let rollName = payload[IOSMessageKey.rollName] as? String, !rollName.isEmpty {
            let descriptor = FetchDescriptor<FilmRoll>(
                predicate: #Predicate<FilmRoll> { $0.name == rollName },
                sortBy: [SortDescriptor(\.loadDate, order: .reverse)]
            )
            roll = try? context.fetch(descriptor).first
        }
        if roll == nil, let rollId = payload[IOSMessageKey.rollId] as? String,
           let data = Data(base64Encoded: rollId),
           let pid = try? JSONDecoder().decode(PersistentIdentifier.self, from: data) {
            roll = context.model(for: pid) as? FilmRoll
        }

        guard let targetRoll = roll else { return }

        let frame = FilmFrame(timestamp: timestamp, aperture: aperture, shutter: shutter, latitude: nil, longitude: nil)
        frame.roll = targetRoll
        targetRoll.frames.append(frame)
        context.insert(frame)
        try? context.save()
    }
}

// MARK: - WCSessionDelegate

extension SessionDelegator: WCSessionDelegate {
    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func sessionReachabilityDidChange(_ session: WCSession) {}

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        Task { @MainActor in
            handleReceivedLogFrame(message)
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        Task { @MainActor in
            handleReceivedLogFrame(message)
            replyHandler([:])
        }
    }
}

// MARK: - 与 Watch 约定的键

enum IOSMessageKey {
    static let action = "action"
    static let rollId = "rollId"
    static let rollName = "rollName"
    static let aperture = "aperture"
    static let shutter = "shutter"
    static let timestamp = "timestamp"
}

enum IOSMessageAction: String {
    case logFrame = "logFrame"
    case setCurrentRoll = "setCurrentRoll"
}
