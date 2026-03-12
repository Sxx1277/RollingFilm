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

private enum I18N {
    private static var isChinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    static func t(_ zh: String, _ en: String) -> String {
        isChinese ? zh : en
    }
}

struct ContentView: View {
    private struct ArchiveGroup: Identifiable {
        var id: String { filmType }
        let filmType: String
        let rolls: [FilmRoll]
    }

    @StateObject private var session = SessionDelegator.shared
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FilmRoll.createdAt, order: .reverse) private var rolls: [FilmRoll]
    @State private var showingNewRoll = false

    private var activeRollUUID: String? {
        rolls
            .filter { $0.isActive && !$0.rollUUID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { $0.createdAt > $1.createdAt }
            .first?
            .rollUUID
    }

    private var activeRolls: [FilmRoll] {
        rolls
            .filter { !$0.isFinished }
            .sorted { $0.loadDate > $1.loadDate }
    }

    private var pendingRolls: [FilmRoll] {
        rolls
            .filter { $0.isFinished && missingPhotoCount(for: $0) > 0 }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var sortedGroupedRolls: [ArchiveGroup] {
        let libraryRolls = rolls.filter { $0.isFinished && missingPhotoCount(for: $0) == 0 }
        let grouped = Dictionary(grouping: libraryRolls, by: { normalizedFilmType(for: $0) })
        let sortedKeys = grouped.keys.sorted()
        return sortedKeys.compactMap { key in
            guard let groupedRolls = grouped[key] else { return nil }
            let sortedRolls = groupedRolls.sorted { $0.loadDate > $1.loadDate }
            return ArchiveGroup(
                filmType: key,
                rolls: sortedRolls
            )
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
                            Text(I18N.t("装入你的第一卷胶片", "Load your first roll"))
                                .font(.headline)
                                .foregroundStyle(RFTheme.primaryText)
                            Text(I18N.t("点击右上角 + 创建一卷，开始记录每一张底片。", "Tap + to create a roll and start logging frames."))
                                .font(.subheadline)
                                .foregroundStyle(RFTheme.secondaryText)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 30)
                        .listRowBackground(Color.clear)
                    }
                } else {
                    Section(I18N.t("相机里", "Active Rolls")) {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 12) {
                                ForEach(activeRolls) { roll in
                                    NavigationLink {
                                        RollDetailView(roll: roll)
                                    } label: {
                                        ActiveRollCard(
                                            roll: roll,
                                            isActive: roll.rollUUID == activeRollUUID,
                                            onSync: { session.sendCurrentRoll(roll: roll) }
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
                        .listRowBackground(Color.clear)
                    }

                    Section(I18N.t("灯箱上", "Ready to Match")) {
                        if pendingRolls.isEmpty {
                            Text(I18N.t("所有已拍完胶卷都已完成匹配。", "All finished rolls are fully matched."))
                                .font(.subheadline)
                                .foregroundStyle(RFTheme.secondaryText)
                                .listRowBackground(Color.clear)
                        } else {
                            ForEach(Array(pendingRolls.prefix(3))) { roll in
                                NavigationLink {
                                    RollDetailView(roll: roll)
                                } label: {
                                    PendingRollRow(
                                        roll: roll,
                                        missingCount: missingPhotoCount(for: roll)
                                    )
                                }
                                .listRowBackground(Color.clear)
                            }
                        }
                    }

                    Section(I18N.t("底片册里", "Film Library")) {
                        ForEach(sortedGroupedRolls) { group in
                            NavigationLink {
                                FilmTypeArchiveView(filmType: group.filmType)
                            } label: {
                                ArchiveFolderRow(
                                    filmType: group.filmType,
                                    count: group.rolls.count
                                )
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    delete(rolls: group.rolls)
                                } label: {
                                    Label(I18N.t("删除", "Delete"), systemImage: "trash")
                                }
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    archive(rolls: group.rolls)
                                } label: {
                                    Label(I18N.t("归档", "Archive"), systemImage: "archivebox")
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
            .background(Color.black.ignoresSafeArea())
#endif
            .navigationTitle(I18N.t("胶卷", "RollingFilm"))
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
        }
    }

    private func normalizedFilmType(for roll: FilmRoll) -> String {
        let t = roll.filmType.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? roll.name : t
    }

    private func missingPhotoCount(for roll: FilmRoll) -> Int {
        roll.frames.filter { frame in
            let id = frame.photoIdentifier?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return id.isEmpty
        }.count
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

struct ActiveRollCard: View {
    let roll: FilmRoll
    let isActive: Bool
    let onSync: () -> Void

    private var progress: Double {
        guard roll.totalFrames > 0 else { return 0 }
        return min(1.0, Double(roll.frames.count) / Double(roll.totalFrames))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Circle()
                    .fill(isActive ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Spacer()
                Text(roll.loadDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
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
            ProgressView(value: progress)
                .tint(RFTheme.accent)
                .progressViewStyle(.linear)
            Button {
                onSync()
            } label: {
                Label(I18N.t("同步到手表", "Sync to Watch"), systemImage: "applewatch")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
            .tint(.green)
            if roll.isFinished {
                Text(I18N.t("已拍完", "Finished"))
                    .font(.caption)
                    .foregroundStyle(RFTheme.accent)
            }
        }
        .padding(12)
        .frame(width: 230, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(RFTheme.cardBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
        )
    }
}

struct PendingRollRow: View {
    let roll: FilmRoll
    let missingCount: Int

    var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(RFTheme.secondaryText.opacity(0.9))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.caption)
                        .foregroundStyle(RFTheme.secondaryText)
                )
            VStack(alignment: .leading, spacing: 4) {
                Text(roll.name)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(RFTheme.primaryText)
                    .lineLimit(1)
                Text(roll.loadDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(RFTheme.secondaryText)
                Text(I18N.t("待匹配 \(missingCount) 张", "Pending \(missingCount)"))
                    .font(.caption)
                    .foregroundStyle(RFTheme.accent)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

struct ArchiveFolderRow: View {
    let filmType: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.full.fill")
                .font(.title3)
                .foregroundStyle(RFTheme.primaryText)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(filmType) (\(count))")
                    .font(.headline)
                    .foregroundStyle(RFTheme.primaryText)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 8)
    }
}

struct FilmTypeArchiveView: View {
    let filmType: String
    @Query(sort: \FilmRoll.createdAt, order: .reverse) private var allRolls: [FilmRoll]
    @State private var selectedRoll: FilmRoll?
    @State private var pressedRollID: PersistentIdentifier?

    private var rolls: [FilmRoll] {
        allRolls
            .filter {
                let type = $0.filmType.trimmingCharacters(in: .whitespacesAndNewlines)
                return (type.isEmpty ? $0.name : type) == filmType
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 14) {
                ForEach(rolls) { roll in
                    Button {
                        withAnimation(.easeOut(duration: 0.12)) {
                            pressedRollID = roll.persistentModelID
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                            selectedRoll = roll
                            withAnimation(.easeIn(duration: 0.18)) {
                                pressedRollID = nil
                            }
                        }
                    } label: {
                        FilmSheetCard(roll: roll)
                            .scaleEffect(pressedRollID == roll.persistentModelID ? 1.03 : 1.0)
                            .animation(.spring(response: 0.25, dampingFraction: 0.82), value: pressedRollID)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
#if os(iOS)
        .background(RFTheme.pageBackground.ignoresSafeArea())
#endif
        .overlay(GrainOverlay().allowsHitTesting(false))
        .navigationDestination(item: $selectedRoll) { roll in
            RollDetailView(roll: roll)
        }
        .navigationTitle(filmType)
    }
}

struct FilmSheetCard: View {
    let roll: FilmRoll

    private var firstPreviewIdentifier: String? {
        roll.frames
            .sorted { $0.timestamp < $1.timestamp }
            .compactMap(\.photoIdentifier)
            .first(where: { !$0.isEmpty })
    }

    var body: some View {
        HStack(spacing: 12) {
            FilmSheetPreview(identifier: firstPreviewIdentifier)
                .frame(width: 92, height: 92)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                Text(roll.loadDate, format: .dateTime.year().month(.twoDigits).day(.twoDigits))
                    .font(.system(.headline, design: .monospaced))
                    .foregroundStyle(RFTheme.secondaryText)
                Text(roll.cameraModel.isEmpty ? "Unknown Camera" : roll.cameraModel)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(RFTheme.secondaryText)
                    .lineLimit(1)
                Text("\(roll.frames.count)/\(roll.totalFrames) EXP")
                    .font(.system(.body, design: .monospaced).weight(.semibold))
                    .foregroundStyle(RFTheme.accent)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(white: 0.12))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            FilmPerforationStrip()
                .padding(.top, 4)
        }
        .overlay(alignment: .bottom) {
            FilmPerforationStrip()
                .padding(.bottom, 4)
        }
    }
}

struct FilmSheetPreview: View {
    let identifier: String?
#if os(iOS)
    @State private var thumbnail: UIImage?
#endif

    var body: some View {
#if os(iOS)
        ZStack {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.white.opacity(0.95))
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.7))
                .padding(2)
            if let thumbnail {
                Image(uiImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .padding(2)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                placeholder
                    .padding(2)
            }
        }
        .onAppear { loadThumbnailIfNeeded() }
        .onChange(of: identifier) { loadThumbnailIfNeeded() }
#else
        placeholder
#endif
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "film")
                .font(.title2)
                .foregroundStyle(RFTheme.secondaryText)
            Text("35mm")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(RFTheme.secondaryText)
        }
    }

#if os(iOS)
    private func loadThumbnailIfNeeded() {
        guard let identifier, !identifier.isEmpty else {
            thumbnail = nil
            return
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else {
            thumbnail = nil
            return
        }
        let options = PHImageRequestOptions()
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 220, height: 220),
            contentMode: .aspectFill,
            options: options
        ) { image, _ in
            thumbnail = image
        }
    }
#endif
}

struct FilmPerforationStrip: View {
    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<12, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(Color.white.opacity(0.18))
                    .frame(width: 6, height: 3)
            }
        }
    }
}

struct GrainOverlay: View {
    var body: some View {
        Canvas { context, size in
            for _ in 0..<420 {
                let x = CGFloat.random(in: 0...size.width)
                let y = CGFloat.random(in: 0...size.height)
                let rect = CGRect(x: x, y: y, width: 1.2, height: 1.2)
                context.fill(Path(rect), with: .color(.white.opacity(0.03)))
            }
        }
        .blendMode(.overlay)
        .opacity(0.45)
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
    @State private var selectedSaveMode: PhotoExifInjector.SaveMode = .saveAsCopy
    @State private var selectedFrameForInject: FilmFrame?
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
                PhotoAssetPickerView(selectionLimit: 1) { assets in
                    handleManualInject(assets: assets)
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
            if !roll.isFinished {
                ToolbarItem(placement: .primaryAction) {
                    syncToolbarButton
                }
            }
        }
#endif
    }

    @ViewBuilder
    private func frameRow(for frame: FilmFrame) -> some View {
#if os(iOS)
        FrameRowView(
            frame: frame,
            onInjectPhoto: { startSingleInject(for: frame) }
        )
#else
        FrameRowView(frame: frame, onInjectPhoto: nil)
#endif
    }

    private var bottomBar: some View {
        HStack(spacing: 12) {
            if !roll.isFinished {
                Button {
                    showingLogFrame = true
                } label: {
                    Text("记录当前 (Log Frame)")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(MechanicalActionButtonStyle(fill: RFTheme.cardBackground, foreground: RFTheme.primaryText))
            }
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
        let isFinished = roll.isFinished
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text(roll.name)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(isFinished ? RFTheme.primaryText.opacity(0.72) : RFTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                Text("ISO \(roll.iso)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(isFinished ? RFTheme.accent.opacity(0.75) : RFTheme.accent)
            }

            HStack(spacing: 10) {
                Label(roll.cameraModel.isEmpty ? "未设置机身" : roll.cameraModel, systemImage: "camera.aperture")
                    .font(.footnote)
                    .lineLimit(1)
                Label(roll.lensModel.isEmpty ? "未设置镜头" : roll.lensModel, systemImage: "opticalswitch.vertical")
                    .font(.footnote)
                    .lineLimit(1)
            }
            .foregroundStyle(isFinished ? RFTheme.secondaryText.opacity(0.8) : RFTheme.secondaryText)

            HStack {
                Text(roll.loadDate, format: .dateTime.day().month().year())
                    .font(.caption)
                    .foregroundStyle(isFinished ? RFTheme.secondaryText.opacity(0.8) : RFTheme.secondaryText)
                Spacer()
                Text("\(roll.frames.count)/\(roll.totalFrames)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(isFinished ? RFTheme.accent.opacity(0.75) : RFTheme.accent)
                Toggle("", isOn: $roll.isFinished)
                    .labelsHidden()
                    .tint(RFTheme.accent)
                    .scaleEffect(0.9)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isFinished ? Color(white: 0.20) : RFTheme.cardBackground)
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
        showingSaveModeDialog = true
    }

    private func handleManualInject(assets: [PHAsset]) {
        guard let frame = selectedFrameForInject else { return }
        guard let asset = assets.first else { return }
        PhotoExifInjector.inject(frame: frame, roll: roll, into: asset, saveMode: selectedSaveMode) { success in
            if success {
                frame.photoIdentifier = asset.localIdentifier
                try? modelContext.save()
            }
            feedbackMessage = success ? "注入成功" : "注入失败，请检查相册权限或图片格式"
            showingFeedbackAlert = true
        }
    }
#endif
}

// MARK: - 底片行
struct FrameRowView: View {
    let frame: FilmFrame
#if os(iOS)
    @State private var loadedThumbnail: UIImage?
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
                if let loadedThumbnail {
                    Image(uiImage: loadedThumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if let id = frame.photoIdentifier, !id.isEmpty {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                        ProgressView()
                            .controlSize(.mini)
                    }
                    .frame(width: 28, height: 28)
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
#if os(iOS)
        .onAppear {
            loadThumbnailIfNeeded()
        }
        .onChange(of: frame.photoIdentifier) {
            loadThumbnailIfNeeded()
        }
#endif
    }

#if os(iOS)
    private func loadThumbnailIfNeeded() {
        guard let identifier = frame.photoIdentifier, !identifier.isEmpty else {
            loadedThumbnail = nil
            return
        }
        let result = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
        guard let asset = result.firstObject else {
            loadedThumbnail = nil
            return
        }
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
            loadedThumbnail = image
        }
    }
#endif
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
            filmType: selectedFilm,
            createdAt: Date(),
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

#Preview {
    ContentView()
        .modelContainer(for: [FilmRoll.self, FilmFrame.self], inMemory: true)
}
