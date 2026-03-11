//
//  PhotoExifInjector.swift
//  RollingFilm
//

import Foundation
#if os(iOS)
import SwiftUI
import SwiftData
import Photos
import PhotosUI
import ImageIO
import UniformTypeIdentifiers

struct BatchInjectSummary {
    let totalAssets: Int
    let matchedPairs: Int
    let successCount: Int
    let failureCount: Int
}

enum PhotoExifInjector {
    enum SaveMode {
        case saveAsCopy
        case replaceOriginal
    }

    enum BatchOrderMode {
        case byCaptureTime
        case bySequence
    }

    static func requestLibraryPermission(completion: @escaping (Bool) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
            DispatchQueue.main.async {
                completion(status == .authorized || status == .limited)
            }
        }
    }

    /// 单张注入：将 FilmRoll + FilmFrame 信息写入 EXIF/TIFF/GPS。
    static func inject(
        frame: FilmFrame,
        roll: FilmRoll,
        into asset: PHAsset,
        saveMode: SaveMode = .saveAsCopy,
        completion: @escaping (Bool) -> Void
    ) {
        requestLibraryPermission { granted in
            guard granted else {
                completion(false)
                return
            }
            loadPhotoData(from: asset) { data, uti in
                guard let data, let uti else {
                    completion(false)
                    return
                }
                guard let injectedData = buildInjectedImageData(from: data, uti: uti, frame: frame, roll: roll) else {
                    completion(false)
                    return
                }
                saveToLibrary(
                    imageData: injectedData,
                    sourceAsset: asset,
                    frame: frame,
                    roll: roll,
                    saveMode: saveMode,
                    completion: completion
                )
            }
        }
    }

    /// 兼容旧调用（保留 rollISO 参数），默认按副本保存。
    static func inject(
        frame: FilmFrame,
        rollISO: Int,
        into asset: PHAsset,
        completion: @escaping (Bool) -> Void
    ) {
        let tempRoll = FilmRoll(name: "", iso: rollISO, cameraModel: "", lensModel: "")
        inject(frame: frame, roll: tempRoll, into: asset, saveMode: .saveAsCopy, completion: completion)
    }

    static func injectBatch(
        assets: [PHAsset],
        frames: [FilmFrame],
        roll: FilmRoll,
        saveMode: SaveMode = .saveAsCopy,
        orderMode: BatchOrderMode = .byCaptureTime,
        onEachResult: ((PHAsset, FilmFrame, Bool) -> Void)? = nil,
        completion: @escaping (BatchInjectSummary) -> Void
    ) {
        let pairs = pairAssetsAndFramesSequentially(assets: assets, frames: frames, orderMode: orderMode)
        guard !pairs.isEmpty else {
            completion(BatchInjectSummary(totalAssets: assets.count, matchedPairs: 0, successCount: 0, failureCount: 0))
            return
        }

        var success = 0
        var fail = 0
        let group = DispatchGroup()

        for (asset, frame) in pairs {
            group.enter()
            inject(frame: frame, roll: roll, into: asset, saveMode: saveMode) { ok in
                onEachResult?(asset, frame, ok)
                if ok { success += 1 } else { fail += 1 }
                group.leave()
            }
        }

        group.notify(queue: .main) {
            completion(
                BatchInjectSummary(
                    totalAssets: assets.count,
                    matchedPairs: pairs.count,
                    successCount: success,
                    failureCount: fail
                )
            )
        }
    }

    /// 兼容旧调用（保留 rollISO 参数）
    static func injectBatch(
        assets: [PHAsset],
        frames: [FilmFrame],
        rollISO: Int,
        toleranceSeconds: TimeInterval = 10 * 60,
        completion: @escaping (BatchInjectSummary) -> Void
    ) {
        let tempRoll = FilmRoll(name: "", iso: rollISO, cameraModel: "", lensModel: "")
        injectBatch(assets: assets, frames: frames, roll: tempRoll, saveMode: .saveAsCopy, orderMode: .byCaptureTime, onEachResult: nil, completion: completion)
    }

    /// 批量顺序注入：按时间排序后一一对应（或按传入顺序一一对应）
    static func pairAssetsAndFramesSequentially(
        assets: [PHAsset],
        frames: [FilmFrame],
        orderMode: BatchOrderMode
    ) -> [(PHAsset, FilmFrame)] {
        let orderedAssets: [PHAsset]
        let orderedFrames: [FilmFrame]

        switch orderMode {
        case .byCaptureTime:
            orderedAssets = assets.sorted {
                ($0.creationDate ?? .distantPast) < ($1.creationDate ?? .distantPast)
            }
            orderedFrames = frames.sorted { $0.timestamp < $1.timestamp }
        case .bySequence:
            orderedAssets = assets
            orderedFrames = frames
        }

        let count = min(orderedAssets.count, orderedFrames.count)
        guard count > 0 else { return [] }

        var pairs: [(PHAsset, FilmFrame)] = []
        pairs.reserveCapacity(count)
        for idx in 0..<count {
            pairs.append((orderedAssets[idx], orderedFrames[idx]))
        }
        return pairs
    }

    private static func loadPhotoData(from asset: PHAsset, completion: @escaping (Data?, CFString?) -> Void) {
        guard let resource = PHAssetResource.assetResources(for: asset)
            .first(where: { $0.type == .photo || $0.type == .fullSizePhoto }) else {
            completion(nil, nil)
            return
        }

        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true

        let buffer = NSMutableData()
        PHAssetResourceManager.default().requestData(for: resource, options: options, dataReceivedHandler: { chunk in
            buffer.append(chunk)
        }, completionHandler: { error in
            guard error == nil else {
                completion(nil, nil)
                return
            }
            completion(buffer as Data, resource.uniformTypeIdentifier as CFString)
        })
    }

    private static func buildInjectedImageData(from data: Data, uti: CFString, frame: FilmFrame, roll: FilmRoll) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let destinationData = CFDataCreateMutable(nil, 0),
              let destination = CGImageDestinationCreateWithData(destinationData, uti, 1, nil) else {
            return nil
        }

        let newMetadata = rebuiltMetadata(from: source, frame: frame, roll: roll)

        // 关键：将完整 newMetadata 传给 AddImageFromSource。
        CGImageDestinationAddImageFromSource(destination, source, 0, newMetadata as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return destinationData as Data
    }

    private static func saveToLibrary(
        imageData: Data,
        sourceAsset: PHAsset,
        frame: FilmFrame,
        roll: FilmRoll,
        saveMode: SaveMode,
        completion: @escaping (Bool) -> Void
    ) {
        switch saveMode {
        case .saveAsCopy:
            PHPhotoLibrary.shared().performChanges({
                let creation = PHAssetCreationRequest.forAsset()
                creation.addResource(with: .photo, data: imageData, options: nil)
            }, completionHandler: { success, _ in
                DispatchQueue.main.async { completion(success) }
            })
        case .replaceOriginal:
            replaceOriginalAssetData(asset: sourceAsset, frame: frame, roll: roll, fallbackImageData: imageData, completion: completion)
        }
    }

    /// 原片覆盖：requestContentEditingInput + 临时 jpg + CGImageDestination 重写 metadata
    private static func replaceOriginalAssetData(
        asset: PHAsset,
        frame: FilmFrame,
        roll: FilmRoll,
        fallbackImageData: Data,
        completion: @escaping (Bool) -> Void
    ) {
        let inputOptions = PHContentEditingInputRequestOptions()
        inputOptions.isNetworkAccessAllowed = true

        asset.requestContentEditingInput(with: inputOptions) { input, _ in
            guard let input else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let originalData: Data
            if let sourceURL = input.fullSizeImageURL, let data = try? Data(contentsOf: sourceURL) {
                originalData = data
            } else {
                originalData = fallbackImageData
            }

            let tempURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("rf-edit-\(UUID().uuidString).jpg")

            guard writeInjectedJPEGFile(from: originalData, to: tempURL, frame: frame, roll: roll) else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let output = PHContentEditingOutput(contentEditingInput: input)
            do {
                if FileManager.default.fileExists(atPath: output.renderedContentURL.path) {
                    try FileManager.default.removeItem(at: output.renderedContentURL)
                }
                try FileManager.default.copyItem(at: tempURL, to: output.renderedContentURL)
            } catch {
                DispatchQueue.main.async { completion(false) }
                return
            }

            let formatIdentifier = Bundle.main.bundleIdentifier ?? "RollingFilm"
            output.adjustmentData = PHAdjustmentData(
                formatIdentifier: formatIdentifier,
                formatVersion: "1.0",
                data: Data("RollingFilm EXIF update".utf8)
            )

            PHPhotoLibrary.shared().performChanges({
                let request = PHAssetChangeRequest(for: asset)
                request.contentEditingOutput = output
            }, completionHandler: { success, _ in
                try? FileManager.default.removeItem(at: tempURL)
                DispatchQueue.main.async { completion(success) }
            })
        }
    }

    private static func writeInjectedJPEGFile(from sourceData: Data, to destinationURL: URL, frame: FilmFrame, roll: FilmRoll) -> Bool {
        guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
              let destination = CGImageDestinationCreateWithURL(
                destinationURL as CFURL,
                UTType.jpeg.identifier as CFString,
                1,
                nil
              ) else {
            return false
        }
        let newMetadata = rebuiltMetadata(from: source, frame: frame, roll: roll)
        CGImageDestinationAddImageFromSource(destination, source, 0, newMetadata as CFDictionary)
        return CGImageDestinationFinalize(destination)
    }

    /// 强制重建并覆盖 TIFF / EXIF / GPS 三个核心子字典，防止旧机身信息残留。
    private static func rebuiltMetadata(from source: CGImageSource, frame: FilmFrame, roll: FilmRoll) -> [CFString: Any] {
        let originalMetadata = (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
        let originalExif = (originalMetadata[kCGImagePropertyExifDictionary] as? [CFString: Any]) ?? [:]
        let originalTIFF = (originalMetadata[kCGImagePropertyTIFFDictionary] as? [CFString: Any]) ?? [:]

        var newExif = originalExif
        if let fNumber = parseAperture(frame.aperture) {
            newExif[kCGImagePropertyExifFNumber] = fNumber
        } else {
            newExif.removeValue(forKey: kCGImagePropertyExifFNumber)
        }
        if let exposure = parseShutter(frame.shutter) {
            newExif[kCGImagePropertyExifExposureTime] = exposure
        } else {
            newExif.removeValue(forKey: kCGImagePropertyExifExposureTime)
        }
        newExif[kCGImagePropertyExifISOSpeedRatings] = [roll.iso]
        if !roll.lensModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newExif[kCGImagePropertyExifLensModel] = roll.lensModel
        } else {
            newExif.removeValue(forKey: kCGImagePropertyExifLensModel)
        }
        newExif[kCGImagePropertyExifDateTimeOriginal] = formatEXIFDate(frame.timestamp)

        var newTIFF = originalTIFF
        let make = extractCameraMake(from: roll.cameraModel)
        if !make.isEmpty {
            newTIFF[kCGImagePropertyTIFFMake] = make
        } else {
            newTIFF.removeValue(forKey: kCGImagePropertyTIFFMake)
        }
        if !roll.cameraModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            newTIFF[kCGImagePropertyTIFFModel] = roll.cameraModel
        } else {
            newTIFF.removeValue(forKey: kCGImagePropertyTIFFModel)
        }

        var newGPS: [CFString: Any] = [:]
        if let lat = frame.latitude, let lon = frame.longitude {
            newGPS[kCGImagePropertyGPSLatitude] = Double(abs(lat))
            newGPS[kCGImagePropertyGPSLatitudeRef] = lat >= 0 ? "N" : "S"
            newGPS[kCGImagePropertyGPSLongitude] = Double(abs(lon))
            newGPS[kCGImagePropertyGPSLongitudeRef] = lon >= 0 ? "E" : "W"
        }

        var newMetadata = originalMetadata
        newMetadata[kCGImagePropertyTIFFDictionary] = newTIFF
        newMetadata[kCGImagePropertyExifDictionary] = newExif
        if newGPS.isEmpty {
            newMetadata.removeValue(forKey: kCGImagePropertyGPSDictionary)
        } else {
            newMetadata[kCGImagePropertyGPSDictionary] = newGPS
        }
        return newMetadata
    }

    private static func parseAperture(_ value: String) -> Double? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "f/", with: "")
            .replacingOccurrences(of: "f", with: "")
            .replacingOccurrences(of: ",", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return Double(normalized)
    }

    private static func parseShutter(_ value: String) -> Double? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "s", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if normalized.contains("/") {
            let parts = normalized.split(separator: "/")
            guard parts.count == 2,
                  let numerator = Double(parts[0]),
                  let denominator = Double(parts[1]),
                  denominator != 0 else { return nil }
            return numerator / denominator
        }
        return Double(normalized.replacingOccurrences(of: ",", with: "."))
    }

    private static func extractCameraMake(from cameraModel: String) -> String {
        let normalized = cameraModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return "" }
        let knownMakes = ["Leica", "Nikon", "Canon", "Contax", "Hasselblad", "Fujifilm", "Pentax", "Olympus", "Sony", "Minolta"]
        if let matched = knownMakes.first(where: { normalized.lowercased().hasPrefix($0.lowercased()) }) {
            return matched
        }
        return normalized.split(separator: " ").first.map(String.init) ?? normalized
    }

    private static func formatEXIFDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

/// 语义别名：等价于 PhotoExifInjector，可作为 EXIFService 使用。
typealias EXIFService = PhotoExifInjector

struct PhotoAssetPickerView: UIViewControllerRepresentable {
    var selectionLimit: Int
    var onPicked: ([PHAsset]) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.selectionLimit = selectionLimit
        config.filter = .images
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onPicked: onPicked)
    }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        private let onPicked: ([PHAsset]) -> Void

        init(onPicked: @escaping ([PHAsset]) -> Void) {
            self.onPicked = onPicked
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            let ids = results.compactMap(\.assetIdentifier)
            guard !ids.isEmpty else {
                onPicked([])
                return
            }
            let fetched = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
            var assets: [PHAsset] = []
            fetched.enumerateObjects { asset, _, _ in assets.append(asset) }
            onPicked(assets)
        }
    }
}
#endif
