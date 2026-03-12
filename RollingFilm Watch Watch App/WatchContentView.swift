//
//  WatchContentView.swift
//  RollingFilm Watch Watch App
//
//  徕卡风格 · 极致简洁：横向双数值，点击高亮，表冠调节。
//

import SwiftUI
import WatchKit

// MARK: - 胶片参数预设
enum WatchPresets {
    static let apertures: [String] = [
        "1.2", "1.4", "2", "2.8", "4", "5.6", "8", "11", "16", "22"
    ]
    static let shutters: [String] = [
        "1s", "1/2", "1/4", "1/8", "1/15", "1/30", "1/60", "1/125",
        "1/250", "1/500", "1/1000", "1/2000", "1/4000"
    ]
}

struct WatchContentView: View {
    @StateObject private var session = WatchSessionDelegator.shared
    @State private var selectedMode: ParameterMode = .aperture
    @State private var crownApertureValue: Double = 4
    @State private var crownShutterValue: Double = 7
    @State private var titlePulse = false
    @State private var titleGlow = false

    private var apertureIndex: Int {
        max(0, min(WatchPresets.apertures.count - 1, Int(crownApertureValue.rounded())))
    }
    private var shutterIndex: Int {
        max(0, min(WatchPresets.shutters.count - 1, Int(crownShutterValue.rounded())))
    }

    /// 选中时大字号，未选中时小字号
    private let fontSelected = Font.system(size: 44, weight: .medium, design: .rounded)
    private let fontUnselected = Font.system(size: 22, weight: .regular, design: .rounded)

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：胶卷名 + UUID 缩略，收到新卷时做绿色反馈
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.currentRollName.isEmpty ? "未选胶卷" : session.currentRollName)
                        .font(.system(size: 11, weight: .regular))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .foregroundStyle(.secondary)
                    Text(session.currentRollId.isEmpty ? "UUID: -" : "UUID: \(shortRollID)")
                        .font(.system(size: 9, weight: .regular))
                        .lineLimit(1)
                        .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.green.opacity(titleGlow ? 0.25 : 0))
            )
            .scaleEffect(titlePulse ? 1.03 : 1.0)
            .padding(.horizontal, 4)
            .padding(.bottom, 6)

            // 中间：横向双数值，左光圈 f/ 右快门，点击切换高亮，表冠控制当前项
            HStack(spacing: 6) {
                // 左：光圈 f/X
                apertureValueView
                    .frame(maxWidth: selectedMode == .aperture ? .infinity : nil)
                    .frame(minWidth: selectedMode == .aperture ? 0 : 44)

                // 右：快门
                shutterValueView
                    .frame(maxWidth: selectedMode == .shutter ? .infinity : nil)
                    .frame(minWidth: selectedMode == .shutter ? 0 : 44)
            }
            .animation(.easeInOut(duration: 0.25), value: selectedMode)

            Spacer(minLength: 8)

            // 底部：记录 · 半透明 Material，不厚重
            Button { logFrame() } label: {
                Text("记录")
                    .font(.system(size: 15, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
            )
            .disabled(session.currentRollId.isEmpty)
            .opacity(session.currentRollId.isEmpty ? 0.6 : 1)

            if !session.isPhoneReachable {
                Text("未连接")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }
        }
        .padding(.horizontal, 8)
        .navigationTitle("RollingFilm")
        .onChange(of: session.rollUpdateToken) {
            withAnimation(.easeOut(duration: 0.2)) {
                titlePulse = true
                titleGlow = true
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                withAnimation(.easeIn(duration: 0.25)) {
                    titlePulse = false
                    titleGlow = false
                }
            }
        }
    }

    // MARK: - 左：光圈 f/X
    @ViewBuilder
    private var apertureValueView: some View {
        let isSelected = selectedMode == .aperture
        if isSelected {
            Text("f/\(WatchPresets.apertures[apertureIndex])")
                .font(fontSelected)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.orange)
                .contentTransition(.numericText())
                .focusable(true)
                .digitalCrownRotation(
                    $crownApertureValue,
                    from: 0,
                    through: Double(WatchPresets.apertures.count - 1),
                    by: 1,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedMode = .aperture }
                }
        } else {
            Text("f/\(WatchPresets.apertures[apertureIndex])")
                .font(fontUnselected)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Color.primary.opacity(0.5))
                .contentTransition(.numericText())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedMode = .aperture }
                }
        }
    }

    // MARK: - 右：快门
    @ViewBuilder
    private var shutterValueView: some View {
        let isSelected = selectedMode == .shutter
        if isSelected {
            Text(WatchPresets.shutters[shutterIndex])
                .font(fontSelected)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.35)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.orange)
                .contentTransition(.numericText())
                .focusable(true)
                .digitalCrownRotation(
                    $crownShutterValue,
                    from: 0,
                    through: Double(WatchPresets.shutters.count - 1),
                    by: 1,
                    sensitivity: .low,
                    isContinuous: false,
                    isHapticFeedbackEnabled: true
                )
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedMode = .shutter }
                }
        } else {
            Text(WatchPresets.shutters[shutterIndex])
                .font(fontUnselected)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .multilineTextAlignment(.trailing)
                .foregroundStyle(Color.primary.opacity(0.5))
                .contentTransition(.numericText())
                .onTapGesture {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedMode = .shutter }
                }
        }
    }

    private func logFrame() {
        session.sendLogFrame(
            aperture: WatchPresets.apertures[apertureIndex],
            shutter: WatchPresets.shutters[shutterIndex]
        )
    }

    private var shortRollID: String {
        let id = session.currentRollId
        guard !id.isEmpty else { return "-" }
        return String(id.prefix(8))
    }
}

enum ParameterMode: String, CaseIterable {
    case aperture
    case shutter
}

#Preview {
    WatchContentView()
}
