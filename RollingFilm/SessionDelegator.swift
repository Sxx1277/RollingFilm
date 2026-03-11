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
    private var pendingRollPayload: [String: Any]?
    @Published var isSyncing: Bool = false
    @Published var lastSyncedRollUUID: String?
    @Published var syncSuccessToken: Int = 0

    private override init() {
        super.init()
        if WCSession.isSupported() {
            let session = WCSession.default
            session.delegate = self
            session.activate()
        }
    }

    // MARK: - 同步选中胶卷到 Watch（更新 Watch 顶部标题）

    /// 将当前选中的胶卷名和 UUID 发送给 Watch，Watch 用于更新顶部标题与记录归属
    func sendCurrentRoll(roll: FilmRoll) {
        let session = WCSession.default
        guard session.isPaired else { return }
        if roll.rollUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            roll.rollUUID = UUID().uuidString
        }
        markSyncStarted()
        let payload: [String: Any] = [
            IOSMessageKey.action: IOSMessageAction.setCurrentRoll.rawValue,
            IOSMessageKey.rollId: roll.rollUUID,
            IOSMessageKey.rollName: roll.name,
        ]
        if session.activationState != .activated {
            pendingRollPayload = payload
            session.activate()
            return
        }
        dispatchRollPayload(payload, with: session)
    }

    private func dispatchRollPayload(_ payload: [String: Any], with session: WCSession) {
        do {
            try session.updateApplicationContext(payload)
        } catch {
            markSyncFinished(success: false, rollUUID: payload[IOSMessageKey.rollId] as? String)
            return
        }
        if session.isReachable {
            session.sendMessage(payload, replyHandler: { [weak self, payload] _ in
                self?.markSyncFinished(success: true, rollUUID: payload[IOSMessageKey.rollId] as? String)
            }, errorHandler: { [weak self, payload] _ in
                self?.pendingRollPayload = payload
                self?.markSyncFinished(success: false, rollUUID: payload[IOSMessageKey.rollId] as? String)
            })
        } else {
            // ApplicationContext 已写入，视为已进入同步队列。
            markSyncFinished(success: true, rollUUID: payload[IOSMessageKey.rollId] as? String)
        }
    }

    private func flushPendingRollPayloadIfNeeded(with session: WCSession) {
        guard session.activationState == .activated else { return }
        guard let payload = pendingRollPayload else { return }
        dispatchRollPayload(payload, with: session)
        pendingRollPayload = nil
    }

    private func markSyncStarted() {
        DispatchQueue.main.async {
            self.isSyncing = true
        }
    }

    private func markSyncFinished(success: Bool, rollUUID: String?) {
        DispatchQueue.main.async {
            self.isSyncing = false
            guard success else { return }
            if let rollUUID {
                self.persistActiveRoll(rollUUID: rollUUID)
            }
            self.lastSyncedRollUUID = rollUUID
            self.syncSuccessToken += 1
        }
    }

    /// 配对状态持久化：全量置 false，再将当前卷置 true。
    private func persistActiveRoll(rollUUID: String) {
        guard let container = modelContainer else { return }
        let context = ModelContext(container)
        let descriptor = FetchDescriptor<FilmRoll>()
        guard let allRolls = try? context.fetch(descriptor) else { return }

        var didChange = false
        for item in allRolls {
            let shouldActive = (item.rollUUID == rollUUID)
            if item.isActive != shouldActive {
                item.isActive = shouldActive
                didChange = true
            }
        }
        if didChange {
            try? context.save()
        }
    }

    // MARK: - 接收 Watch 发来的记录并写入 SwiftData

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        Task { @MainActor in
            handleReceivedLogFrame(userInfo)
        }
    }

    /// 收到 Watch 的 logFrame 数据后：优先按 UUID 精确匹配 FilmRoll，创建 FilmFrame 并保存
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
        let latitude = payload[IOSMessageKey.latitude] as? Double
        let longitude = payload[IOSMessageKey.longitude] as? Double

        let context = ModelContext(container)
        context.autosaveEnabled = true

        // 1) 优先使用 rollUUID 精确匹配，避免同名胶卷冲突
        var roll: FilmRoll?
        if let rollUUID = payload[IOSMessageKey.rollId] as? String, !rollUUID.isEmpty {
            let descriptor = FetchDescriptor<FilmRoll>(
                predicate: #Predicate<FilmRoll> { $0.rollUUID == rollUUID }
            )
            roll = try? context.fetch(descriptor).first
        }

        // 2) 兼容兜底：若 UUID 不可用，再按名称取最近的一卷
        if roll == nil, let rollName = payload[IOSMessageKey.rollName] as? String, !rollName.isEmpty {
            let descriptor = FetchDescriptor<FilmRoll>(
                predicate: #Predicate<FilmRoll> { $0.name == rollName },
                sortBy: [SortDescriptor(\.loadDate, order: .reverse)]
            )
            roll = try? context.fetch(descriptor).first
        }

        guard let targetRoll = roll else { return }

        let frame = FilmFrame(
            timestamp: timestamp,
            aperture: aperture,
            shutter: shutter,
            latitude: latitude,
            longitude: longitude
        )
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
    ) {
        flushPendingRollPayloadIfNeeded(with: session)
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        flushPendingRollPayloadIfNeeded(with: session)
    }

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
    static let latitude = "latitude"
    static let longitude = "longitude"
}

enum IOSMessageAction: String {
    case logFrame = "logFrame"
    case setCurrentRoll = "setCurrentRoll"
}
