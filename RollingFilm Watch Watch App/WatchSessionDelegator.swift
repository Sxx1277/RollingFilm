//
//  WatchSessionDelegator.swift
//  RollingFilm Watch Watch App
//

import Foundation
import Combine
import WatchConnectivity
import CoreLocation
import WatchKit

/// Watch 端 WCSession 代理：接收 iPhone 下发的当前胶卷，发送「记录底片」请求。
final class WatchSessionDelegator: NSObject, ObservableObject {
    static let shared = WatchSessionDelegator()

    @Published var currentRollId: String = ""
    @Published var currentRollName: String = ""
    @Published var rollUpdateToken: Int = 0
    @Published var isPhoneReachable: Bool = false
    @Published private(set) var latestLatitude: Double?
    @Published private(set) var latestLongitude: Double?

    private let locationManager = CLLocationManager()

    private override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func activateSession() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        isPhoneReachable = session.isReachable
        requestLocationPermissionIfNeeded()
        refreshLocation()
    }

    func requestLocationPermissionIfNeeded() {
        let status = locationManager.authorizationStatus
        switch status {
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            break
        default:
            break
        }
    }

    func refreshLocation() {
        let status = locationManager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            locationManager.requestLocation()
        }
    }

    /// 用户点击「记录」时调用：仅使用 transferUserInfo 进入系统后台传输队列
    func sendLogFrame(aperture: String, shutter: String) {
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        refreshLocation()
        let messageId = UUID().uuidString
        let payload: [String: Any] = [
            MessageKey.action: MessageAction.logFrame.rawValue,
            MessageKey.messageId: messageId,
            MessageKey.rollId: currentRollId,
            MessageKey.rollName: currentRollName,
            MessageKey.aperture: aperture,
            MessageKey.shutter: shutter,
            MessageKey.timestamp: Date().timeIntervalSince1970,
            MessageKey.latitude: latestLatitude as Any,
            MessageKey.longitude: latestLongitude as Any,
        ]
        // 1) 永远入系统后台队列，保证息屏/后台可送达
        _ = session.transferUserInfo(payload)
        // 2) 前台可达时补发即时消息，提升“点击记录后立刻看到结果”的体验
        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        }
        // 入队后立即给一个轻触感反馈，提示“已加入后台传输队列”
        WKInterfaceDevice.current().play(.click)
    }
}

// MARK: - WCSessionDelegate
extension WatchSessionDelegator: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
            if activationState == .activated, !session.receivedApplicationContext.isEmpty {
                self.applyApplicationContext(session.receivedApplicationContext)
            }
        }
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        DispatchQueue.main.async {
            self.applyApplicationContext(applicationContext)
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPhoneReachable = session.isReachable
        }
    }

    /// iPhone 通过 sendMessage 即时推送当前胶卷时也会走到这里，便于 Watch 立刻更新界面
    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        DispatchQueue.main.async {
            if message[MessageKey.action] as? String == MessageAction.setCurrentRoll.rawValue {
                self.applyApplicationContext(message)
            }
        }
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
        DispatchQueue.main.async {
            if message[MessageKey.action] as? String == MessageAction.setCurrentRoll.rawValue {
                self.applyApplicationContext(message)
            }
            replyHandler([:])
        }
    }

    /// 若 iPhone 通过 transferUserInfo 下发当前胶卷，也统一更新 currentRollId / currentRollName
    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
        DispatchQueue.main.async {
            if userInfo[MessageKey.rollId] != nil || userInfo[MessageKey.rollName] != nil {
                self.applyApplicationContext(userInfo)
            }
        }
    }

    private func applyApplicationContext(_ context: [String: Any]) {
        var didChangeRoll = false
        if let id = context[MessageKey.rollId] as? String {
            if id != currentRollId { didChangeRoll = true }
            currentRollId = id
        }
        if let name = context[MessageKey.rollName] as? String {
            if name != currentRollName { didChangeRoll = true }
            currentRollName = name
        }
        if didChangeRoll {
            rollUpdateToken += 1
        }
    }
}

// MARK: - CLLocationManagerDelegate
extension WatchSessionDelegator: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        DispatchQueue.main.async {
            self.latestLatitude = location.coordinate.latitude
            self.latestLongitude = location.coordinate.longitude
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // 定位失败时保持上一次有效坐标，不中断记录流程
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            manager.requestLocation()
        }
    }
}

// MARK: - 与 iPhone 约定的键
enum MessageKey {
    static let action = "action"
    static let messageId = "messageId"
    static let rollId = "rollId"
    static let rollName = "rollName"
    static let aperture = "aperture"
    static let shutter = "shutter"
    static let timestamp = "timestamp"
    static let latitude = "latitude"
    static let longitude = "longitude"
}

enum MessageAction: String {
    case logFrame = "logFrame"
    /// iPhone 下发当前选中的胶卷
    case setCurrentRoll = "setCurrentRoll"
}
