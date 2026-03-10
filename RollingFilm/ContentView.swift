//
//  ContentView.swift
//  RollingFilm
//
//  Created by 啊傻傻傻 on 2026/3/10.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \FilmRoll.loadDate, order: .reverse) private var rolls: [FilmRoll]
    @State private var showingNewRoll = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(rolls) { roll in
                    NavigationLink {
                        RollDetailView(roll: roll)
                    } label: {
                        RollRowView(roll: roll)
                    }
                }
                .onDelete(perform: deleteRolls)
            }
            .navigationTitle("胶卷")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingNewRoll = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingNewRoll) {
                NewRollSheet()
            }
            .onAppear {
                // 主列表出现时把「最近一条胶卷」推给 Watch，这样 Watch 无需先点进详情也能显示胶卷
                if let mostRecent = rolls.first {
                    SessionDelegator.shared.sendCurrentRoll(roll: mostRecent)
                }
            }
        }
    }

    private func deleteRolls(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(rolls[index])
            }
        }
    }
}

// MARK: - 胶卷行
struct RollRowView: View {
    let roll: FilmRoll

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(roll.name)
                .font(.headline)
            HStack(spacing: 12) {
                Text("ISO \(roll.iso)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(roll.frames.count)/\(roll.totalFrames)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if roll.isFinished {
                    Text("已拍完")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 胶卷详情
struct RollDetailView: View {
    @Bindable var roll: FilmRoll
    @Environment(\.modelContext) private var modelContext
    @State private var showingLogFrame = false

    private var sortedFrames: [FilmFrame] {
        roll.frames.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("ISO")
                    Spacer()
                    Text("\(roll.iso)")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("装卷日期")
                    Spacer()
                    Text(roll.loadDate, format: .dateTime.day().month().year())
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("张数")
                    Spacer()
                    Text("\(roll.frames.count) / \(roll.totalFrames)")
                        .foregroundStyle(.secondary)
                }
                Toggle("已拍完", isOn: $roll.isFinished)
            }

            Section("底片记录") {
                ForEach(sortedFrames) { frame in
                    FrameRowView(frame: frame)
                }
                .onDelete(perform: deleteFrames)
            }
        }
        .navigationTitle(roll.name)
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    SessionDelegator.shared.sendCurrentRoll(roll: roll)
                } label: {
                    Label("同步到手表", systemImage: "applewatch")
                }
            }
        }
#endif
        .safeAreaInset(edge: .bottom) {
            Button {
                showingLogFrame = true
            } label: {
                Text("记录当前 (Log Frame)")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showingLogFrame) {
            LogFrameSheet(roll: roll)
        }
        .onAppear {
            SessionDelegator.shared.sendCurrentRoll(roll: roll)
        }
    }

    private func deleteFrames(offsets: IndexSet) {
        withAnimation {
            let toDelete = offsets.map { sortedFrames[$0] }
            for frame in toDelete {
                modelContext.delete(frame)
            }
        }
    }
}

// MARK: - 底片行
struct FrameRowView: View {
    let frame: FilmFrame

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(frame.timestamp, format: .dateTime.day().month().year().hour().minute())
                .font(.subheadline.weight(.medium))
            HStack(spacing: 16) {
                if !frame.aperture.isEmpty {
                    Text("f/\(frame.aperture)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !frame.shutter.isEmpty {
                    Text(frame.shutter)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let lat = frame.latitude, let lon = frame.longitude {
                    Text(String(format: "%.4f, %.4f", lat, lon))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - 新建胶卷
struct NewRollSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isoText = "400"

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name, prompt: Text("如 Kodak 5207"))
                TextField("ISO", text: $isoText, prompt: Text("如 400"))
#if os(iOS)
                    .keyboardType(.numberPad)
#endif
            }
            .navigationTitle("新建胶卷")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        addRoll()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || Int(isoText) == nil)
                }
            }
        }
    }

    private func addRoll() {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        guard let iso = Int(isoText), iso > 0 else { return }
        let newRoll = FilmRoll(name: trimmedName, iso: iso)
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

#Preview {
    ContentView()
        .modelContainer(for: [FilmRoll.self, FilmFrame.self], inMemory: true)
}
