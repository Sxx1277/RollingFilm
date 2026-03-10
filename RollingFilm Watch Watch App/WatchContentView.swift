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

    private var apertureIndex: Int {
        max(0, min(WatchPresets.apertures.count - 1, Int(crownApertureValue.rounded())))
    }
    private var shutterIndex: Int {
        max(0, min(WatchPresets.shutters.count - 1, Int(crownShutterValue.rounded())))
    }
    private var activeCrownBinding: Binding<Double> {
        selectedMode == .aperture ? $crownApertureValue : $crownShutterValue
    }
    private var activeCrownMax: Double {
        selectedMode == .aperture
            ? Double(WatchPresets.apertures.count - 1)
            : Double(WatchPresets.shutters.count - 1)
    }

    /// 选中时大字号，未选中时小字号
    private let fontSelected = Font.system(size: 44, weight: .medium, design: .rounded)
    private let fontUnselected = Font.system(size: 22, weight: .regular, design: .rounded)

    var body: some View {
        VStack(spacing: 0) {
            // 顶部：胶卷名，极小，靠左
            HStack {
                Text(session.currentRollName.isEmpty ? "未选胶卷" : session.currentRollName)
                    .font(.system(size: 11, weight: .regular))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
            }
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
            // 使用单一可聚焦容器承载表冠，避免 Crown Sequencer 无 view 的告警
            .focusable(true)
            .digitalCrownRotation(
                activeCrownBinding,
                from: 0,
                through: activeCrownMax,
                by: 1,
                sensitivity: .low,
                isContinuous: false,
                isHapticFeedbackEnabled: true
            )

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
        }
        .padding(.horizontal, 8)
        .navigationTitle("RollingFilm")
    }

    // MARK: - 左：光圈 f/X
    private var apertureValueView: some View {
        let isSelected = selectedMode == .aperture
        return Text("f/\(WatchPresets.apertures[apertureIndex])")
            .font(isSelected ? fontSelected : fontUnselected)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(isSelected ? 0.35 : 0.5)
            .multilineTextAlignment(isSelected ? .center : .leading)
            .foregroundStyle(isSelected ? Color.orange : Color.primary.opacity(0.5))
            .contentTransition(.numericText())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { selectedMode = .aperture }
            }
    }

    // MARK: - 右：快门
    private var shutterValueView: some View {
        let isSelected = selectedMode == .shutter
        return Text(WatchPresets.shutters[shutterIndex])
            .font(isSelected ? fontSelected : fontUnselected)
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(isSelected ? 0.35 : 0.5)
            .multilineTextAlignment(isSelected ? .center : .trailing)
            .foregroundStyle(isSelected ? Color.orange : Color.primary.opacity(0.5))
            .contentTransition(.numericText())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) { selectedMode = .shutter }
            }
    }

    private func logFrame() {
        WKInterfaceDevice.current().play(.success)
        session.sendLogFrame(
            aperture: WatchPresets.apertures[apertureIndex],
            shutter: WatchPresets.shutters[shutterIndex]
        )
    }
}

enum ParameterMode: String, CaseIterable {
    case aperture
    case shutter
}

#Preview {
    WatchContentView()
}
