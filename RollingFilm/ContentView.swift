//
//  ContentView.swift
//  RollingFilm
//
//  Created by 啊傻傻傻 on 2026/3/10.
//

import SwiftUI
import SwiftData
#if os(iOS)
import Photos
import UIKit
#endif

private enum RFTheme {
    static var pageBackground: Color {
#if os(iOS)
        Color(UIColor.secondarySystemBackground)
#else
        Color.black
#endif
    }
    static let cardBackground = Color.black.opacity(0.92)
    static let primaryText = Color.white
    static let secondaryText = Color.gray
    static let accent = Color.orange
    static let accentAlt = Color.cyan
}

struct ContentView: View {
    @StateObject private var session = SessionDelegator.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FilmRoll.loadDate, order: .reverse) private var rolls: [FilmRoll]
    @State private var showingNewRoll = false

    private var recentRolls: [FilmRoll] {
        Array(rolls.prefix(5))
    }

    private var archiveGroups: [(filmType: String, rolls: [FilmRoll])] {
        let activeUUID = session.lastSyncedRollUUID
        let nonActive = rolls.filter { $0.rollUUID != activeUUID }
        let grouped = Dictionary(grouping: nonActive, by: { $0.name })
        return grouped
            .map { (filmType: $0.key, rolls: $0.value.sorted { $0.loadDate > $1.loadDate }) }
            .sorted { lhs, rhs in
                if lhs.rolls.count == rhs.rolls.count {
                    return lhs.filmType < rhs.filmType
                }
                return lhs.rolls.count > rhs.rolls.count
            }
    }

    var body: some View {
        NavigationStack {
            List {
                if rolls.isEmpty {
                    Section {
                        VStack(spacing: 10) {
                            Image(systemName: "camera.macro")
                                .font(.system(size: 30, weight: .light))
                                .foregroundStyle(RFTheme.accent)
                            Text("装入你的第一卷胶片")
                                .font(.headline)
                                .foregroundStyle(RFTheme.primaryText)
                            Text("点击右上角 + 创建一卷，开始记录每一张底片。")
                                .font(.subheadline)
                                .foregroundStyle(RFTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section("最近装卷") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(recentRolls) { roll in
                                    NavigationLink {
                                        RollDetailView(roll: roll)
                                    } label: {
                                        RecentRollCard(
                                            roll: roll,
                                            isActive: session.lastSyncedRollUUID == roll.rollUUID
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .simultaneousGesture(TapGesture().onEnded {
                                        session.sendCurrentRoll(roll: roll)
                                    })
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .listRowBackground(Color.clear)
                    }

                    Section("胶卷文件夹") {
                        ForEach(archiveGroups, id: \.filmType) { group in
                            NavigationLink {
                                FilmTypeArchiveView(filmType: group.filmType)
                            } label: {
                                ArchiveFolderRow(filmType: group.filmType, count: group.rolls.count)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(rolls: group.rolls)
                                } label: {
                                    Label("删除", systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    archive(rolls: group.rolls)
                                } label: {
                                    Label("归档", systemImage: "archivebox")
                                }
                                .tint(.indigo)
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                }
            }
            .listStyle(.grouped)
#if os(iOS)
            .scrollContentBackground(.hidden)
            .background(RFTheme.pageBackground.ignoresSafeArea())
#endif
            .navigationTitle("Film")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewRoll = true
                    } label: {
                        Image(systemName: "plus")
                            .foregroundStyle(RFTheme.primaryText)
                    }
                }
            }
            .sheet(isPresented: $showingNewRoll) {
                NewRollSheet()
            }
            .onAppear {
                if let mostRecent = rolls.first {
                    session.sendCurrentRoll(roll: mostRecent)
                }
            }
        }
    }

    private func delete(rolls: [FilmRoll]) {
        withAnimation {
            for roll in rolls {
                modelContext.delete(roll)
            }
        }
    }

    private func archive(rolls: [FilmRoll]) {
        withAnimation {
            for roll in rolls {
                roll.isFinished = true
            }
        }
    }
}

struct RecentRollCard: View {
    let roll: FilmRoll
    let isActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Circle()
                    .fill(isActive ? Color.green : Color.gray.opacity(0.45))
                    .frame(width: 8, height: 8)
                Spacer()
                Text(roll.loadDate, format: .dateTime.year().month().day())
                    .font(.caption2)
                    .foregroundStyle(RFTheme.secondaryText)
            }
            Text(roll.name)
                .font(.headline)
                .foregroundStyle(RFTheme.primaryText)
                .lineLimit(1)
            HStack(spacing: 10) {
                Text("ISO \(roll.iso)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(RFTheme.accent)
                Text("\(roll.frames.count)/\(roll.totalFrames)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(RFTheme.accentAlt)
            }
            if roll.isFinished {
                Text("已拍完")
                    .font(.caption)
                    .foregroundStyle(RFTheme.accent)
            }
        }
        .padding(12)
        .frame(width: 210, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(RFTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
    }
}

struct ArchiveFolderRow: View {
    let filmType: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
                .foregroundStyle(RFTheme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(filmType)
                    .font(.headline)
                    .foregroundStyle(RFTheme.primaryText)
                    .lineLimit(1)
                Text("\(count) 卷")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(RFTheme.secondaryText)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct FilmTypeArchiveView: View {
    let filmType: String
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FilmRoll.loadDate, order: .reverse) private var allRolls: [FilmRoll]

    private var rolls: [FilmRoll] {
        allRolls.filter { $0.name == filmType }
    }

    var body: some View {
        List {
            ForEach(rolls) { roll in
                NavigationLink {
                    RollDetailView(roll: roll)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("装卷 \(roll.loadDate, format: .dateTime.year().month().day())")
                                .font(.subheadline)
                                .foregroundStyle(RFTheme.primaryText)
                            HStack(spacing: 10) {
                                Text("ISO \(roll.iso)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(RFTheme.accent)
                                Text("\(roll.frames.count)/\(roll.totalFrames)")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(RFTheme.accentAlt)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        modelContext.delete(roll)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .leading) {
                    Button {
                        roll.isFinished = true
                    } label: {
                        Label("归档", systemImage: "archivebox")
                    }
                    .tint(.indigo)
                }
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.grouped)
#if os(iOS)
        .scrollContentBackground(.hidden)
        .background(RFTheme.pageBackground.ignoresSafeArea())
#endif
        .navigationTitle(filmType)
    }
}

// MARK: - 胶卷详情
struct RollDetailView: View {
    @StateObject private var session = SessionDelegator.shared
    @Bindable var roll: FilmRoll
    @Environment(\.modelContext) private var modelContext
    @State private var showingLogFrame = false
#if os(iOS)
    @State private var showingPhotoPicker = false
    @State private var showingSaveModeDialog = false
    @State private var photoPickerLimit = 1
    @State private var pendingBatchInject = false
    @State private var selectedSaveMode: PhotoExifInjector.SaveMode = .saveAsCopy
    @State private var selectedFrameForInject: FilmFrame?
    @State private var matchedThumbnails: [PersistentIdentifier: UIImage] = [:]
    @State private var feedbackMessage = ""
    @State private var showingFeedbackAlert = false
#endif

    private var sortedFrames: [FilmFrame] {
        roll.frames.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        detailList
            .safeAreaInset(edge: .bottom) { bottomBar }
            .sheet(isPresented: $showingLogFrame) {
                LogFrameSheet(roll: roll)
            }
#if os(iOS)
            .sheet(isPresented: $showingPhotoPicker) {
                PhotoAssetPickerView(selectionLimit: photoPickerLimit) { assets in
                    if photoPickerLimit == 1 {
                        handleManualInject(assets: assets)
                    } else {
                        handleBatchInject(assets: assets)
                    }
                }
            }
            .confirmationDialog("保存方式", isPresented: $showingSaveModeDialog, titleVisibility: .visible) {
                Button("保存为新副本（推荐）") {
                    selectedSaveMode = .saveAsCopy
                    showingPhotoPicker = true
                }
                Button("替换原图") {
                    selectedSaveMode = .replaceOriginal
                    showingPhotoPicker = true
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("请选择 EXIF 写入后的保存方式。")
            }
            .alert("EXIF注入结果", isPresented: $showingFeedbackAlert) {
                Button("确定", role: .cancel) {}
            } message: {
                Text(feedbackMessage)
            }
            .onChange(of: session.syncSuccessToken) {
                let generator = UINotificationFeedbackGenerator()
                generator.prepare()
                generator.notificationOccurred(.success)
            }
#endif
            .onAppear {
                session.sendCurrentRoll(roll: roll)
            }
    }

    private var detailList: some View {
        List {
            Section {
                dashboardCard
                    .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
                    .listRowBackground(Color.clear)
            }

            Section("底片记录") {
                ForEach(sortedFrames) { frame in
                    frameRow(for: frame)
                        .listRowInsets(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
                        .listRowBackground(Color.clear)
                }
                .onDelete(perform: deleteFrames)
            }
        }
        .listStyle(.grouped)
        .navigationTitle(roll.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollContentBackground(.hidden)
        .background(RFTheme.pageBackground.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                syncToolbarButton
            }
        }
#endif
    }

    @ViewBuilder
    private func frameRow(for frame: FilmFrame) -> some View {
#if os(iOS)
        FrameRowView(
            frame: frame,
            matchedThumbnail: matchedThumbnails[frame.persistentModelID],
            onInjectPhoto: { startSingleInject(for: frame) }
        )
#else
        FrameRowView(frame: frame, onInjectPhoto: nil)
#endif
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            Button {
                showingLogFrame = true
            } label: {
                Text("记录当前 (Log Frame)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(MechanicalActionButtonStyle(fill: RFTheme.cardBackground, foreground: RFTheme.primaryText))

#if os(iOS)
            Button {
                startBatchInject()
            } label: {
                Image(systemName: "square.stack.3d.up.fill")
                    .font(.title3.weight(.semibold))
                    .frame(width: 52, height: 52)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color.orange.opacity(0.92))
                    )
                    .foregroundStyle(.black)
            }
                .buttonStyle(MechanicalFABStyle())
#endif
        }
        .padding(.horizontal)
        .padding(.bottom, 8)
    }

#if os(iOS)
    private var syncToolbarButton: some View {
        Button {
            session.sendCurrentRoll(roll: roll)
        } label: {
            Image(systemName: syncSymbolName)
                .foregroundStyle(syncSymbolColor)
                .contentTransition(.symbolEffect(.replace))
        }
    }
#endif

    private var syncSymbolName: String {
        if session.isSyncing { return "arrow.triangle.2.circlepath.circle.fill" }
        return session.lastSyncedRollUUID == roll.rollUUID ? "checkmark.circle.fill" : "applewatch"
    }

    private var syncSymbolColor: Color {
        if session.isSyncing { return .orange }
        return session.lastSyncedRollUUID == roll.rollUUID ? .green : .white
    }

    private var dashboardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(roll.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(RFTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                Text("ISO \(roll.iso)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(RFTheme.accent)
            }

            HStack(spacing: 10) {
                Label(roll.cameraModel.isEmpty ? "未设置机身" : roll.cameraModel, systemImage: "camera.aperture")
                    .font(.footnote)
                    .lineLimit(1)
                Label(roll.lensModel.isEmpty ? "未设置镜头" : roll.lensModel, systemImage: "opticalswitch.vertical")
                    .font(.footnote)
                    .lineLimit(1)
            }
            .foregroundStyle(RFTheme.secondaryText)

            HStack {
                Text(roll.loadDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(RFTheme.secondaryText)
                Spacer()
                Text("\(roll.frames.count)/\(roll.totalFrames)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(RFTheme.accent)
                Toggle("", isOn: $roll.isFinished)
                    .labelsHidden()
                    .tint(RFTheme.accent)
                    .scaleEffect(0.9)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(RFTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func deleteFrames(offsets: IndexSet) {
        withAnimation {
            let toDelete = offsets.map { sortedFrames[$0] }
            for frame in toDelete {
                modelContext.delete(frame)
            }
        }
    }

#if os(iOS)
    private func startSingleInject(for frame: FilmFrame) {
        selectedFrameForInject = frame
        pendingBatchInject = false
        photoPickerLimit = 1
        showingSaveModeDialog = true
    }

    private func startBatchInject() {
        selectedFrameForInject = nil
        pendingBatchInject = true
        photoPickerLimit = 0
        showingSaveModeDialog = true
    }

    private func handleManualInject(assets: [PHAsset]) {
        guard let frame = selectedFrameForInject else { return }
        guard let asset = assets.first else { return }
        PhotoExifInjector.inject(frame: frame, roll: roll, into: asset, saveMode: selectedSaveMode) { success in
            if success {
                cacheThumbnail(for: frame, from: asset)
            }
            feedbackMessage = success ? "注入成功" : "注入失败，请检查相册权限或图片格式"
            showingFeedbackAlert = true
        }
    }

    private func handleBatchInject(assets: [PHAsset]) {
        guard !assets.isEmpty else { return }
        guard pendingBatchInject else { return }
        let framesAsc = roll.frames.sorted { $0.timestamp < $1.timestamp }
        PhotoExifInjector.injectBatch(
            assets: assets,
            frames: framesAsc,
            roll: roll,
            saveMode: selectedSaveMode,
            orderMode: .byCaptureTime
        ) { summary in
            if summary.successCount > 0 {
                let pairs = PhotoExifInjector.pairAssetsAndFramesSequentially(
                    assets: assets,
                    frames: framesAsc,
                    orderMode: .byCaptureTime
                )
                for (asset, frame) in pairs {
                    cacheThumbnail(for: frame, from: asset)
                }
            }
            feedbackMessage =
                "共选中\(summary.totalAssets)张，匹配\(summary.matchedPairs)张，成功\(summary.successCount)张，失败\(summary.failureCount)张。"
            showingFeedbackAlert = true
        }
    }

    private func cacheThumbnail(for frame: FilmFrame, from asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        options.isSynchronous = false
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 64, height: 64),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            guard let image else { return }
            matchedThumbnails[frame.persistentModelID] = image
        }
    }
#endif
}

// MARK: - 底片行
struct FrameRowView: View {
    let frame: FilmFrame
#if os(iOS)
    var matchedThumbnail: UIImage? = nil
#endif
    var onInjectPhoto: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(frame.timestamp, format: .dateTime.day().month().year().hour().minute())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(RFTheme.secondaryText)
                Spacer()
#if os(iOS)
                if let matchedThumbnail {
                    Image(uiImage: matchedThumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if let onInjectPhoto {
                    Button {
                        onInjectPhoto()
                    } label: {
                        Image(systemName: "photo.badge.plus")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(RFTheme.accent)
                    }
                }
#endif
            }

            HStack(spacing: 16) {
                Text("f/\(frame.aperture.isEmpty ? "-" : frame.aperture)")
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(RFTheme.accent)
                Text(frame.shutter.isEmpty ? "-" : frame.shutter)
                    .font(.system(size: 22, weight: .bold, design: .monospaced))
                    .foregroundStyle(RFTheme.accent)
                Spacer()
                if let lat = frame.latitude, let lon = frame.longitude {
                    Text(String(format: "%.4f, %.4f", lat, lon))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(RFTheme.secondaryText)
                }
            }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(RFTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .overlay(alignment: .leading) {
            Capsule()
                .fill(RFTheme.accent.opacity(0.85))
                .frame(width: 3)
                .padding(.vertical, 7)
        }
    }
}

// MARK: - 新建胶卷
struct NewRollSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilm = "Kodak Portra 400"
    @State private var selectedISO = 400
    @State private var selectedCamera = "Leica M6"
    @State private var customCamera = ""
    @State private var selectedLens = "35mm f/2"

    private let filmOptions = [
        "Kodak Portra 400",
        "Kodak Gold 200",
        "Fujifilm C200",
        "Ilford HP5",
        "CineStill 800T"
    ]
    private let isoOptions = [50, 100, 160, 200, 400, 800, 1600, 3200]
    private let cameraOptions = ["Leica M6", "Nikon FM2", "Hasselblad 503CW", "Contax G2", "自定义"]
    private let lensOptions = ["28mm f/2.8", "35mm f/2", "50mm f/1.4", "85mm f/1.8"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("胶卷类型", selection: $selectedFilm) {
                    ForEach(filmOptions, id: \.self) { film in
                        Text(film).tag(film)
                    }
                }
                Picker("ISO", selection: $selectedISO) {
                    ForEach(isoOptions, id: \.self) { iso in
                        Text("\(iso)").tag(iso)
                    }
                }
                Picker("相机机身", selection: $selectedCamera) {
                    ForEach(cameraOptions, id: \.self) { camera in
                        Text(camera).tag(camera)
                    }
                }
                if selectedCamera == "自定义" {
                    TextField("输入机身型号", text: $customCamera, prompt: Text("如 Canon AE-1"))
                }
                Picker("镜头型号", selection: $selectedLens) {
                    ForEach(lensOptions, id: \.self) { lens in
                        Text(lens).tag(lens)
                    }
                }
            }
            .navigationTitle("新建胶卷")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(RFTheme.pageBackground.ignoresSafeArea())
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addRoll()
                    }
                    .disabled(selectedCamera == "自定义" && customCamera.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func addRoll() {
        let camera = selectedCamera == "自定义"
            ? customCamera.trimmingCharacters(in: .whitespacesAndNewlines)
            : selectedCamera
        let newRoll = FilmRoll(
            name: selectedFilm,
            iso: selectedISO,
            cameraModel: camera,
            lensModel: selectedLens
        )
        modelContext.insert(newRoll)
        dismiss()
    }
}

// MARK: - 记录底片
struct LogFrameSheet: View {
    let roll: FilmRoll
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var aperture = ""
    @State private var shutter = ""
    @State private var latitudeText = ""
    @State private var longitudeText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("光圈", text: $aperture, prompt: Text("如 2.8"))
                    TextField("快门", text: $shutter, prompt: Text("如 1/125"))
                }
                Section("位置（可选）") {
                    TextField("纬度", text: $latitudeText, prompt: Text("如 39.9042"))
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                    TextField("经度", text: $longitudeText, prompt: Text("如 116.4074"))
#if os(iOS)
                        .keyboardType(.decimalPad)
#endif
                }
            }
            .navigationTitle("记录当前底片")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            .scrollContentBackground(.hidden)
            .background(RFTheme.pageBackground.ignoresSafeArea())
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saveFrame()
                    }
                }
            }
        }
    }

    private func saveFrame() {
        let lat = Double(latitudeText.replacingOccurrences(of: ",", with: "."))
        let lon = Double(longitudeText.replacingOccurrences(of: ",", with: "."))
        let frame = FilmFrame(
            aperture: aperture.trimmingCharacters(in: .whitespaces),
            shutter: shutter.trimmingCharacters(in: .whitespaces),
            latitude: lat,
            longitude: lon
        )
        frame.roll = roll
        roll.frames.append(frame)
        modelContext.insert(frame)
        dismiss()
    }
}

struct MechanicalActionButtonStyle: ButtonStyle {
    var fill: Color
    var foreground: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(foreground)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(configuration.isPressed ? fill.opacity(0.78) : fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(configuration.isPressed ? 0.24 : 0.12), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
    }
}

struct MechanicalFABStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .brightness(configuration.isPressed ? 0.12 : 0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .shadow(color: .black.opacity(0.35), radius: configuration.isPressed ? 2 : 6, y: 3)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [FilmRoll.self, FilmFrame.self], inMemory: true)
}
