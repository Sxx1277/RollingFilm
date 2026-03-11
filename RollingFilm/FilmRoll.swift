//
//  FilmRoll.swift
//  RollingFilm
//
//  Created by 啊傻傻傻 on 2026/3/10.
//

import Foundation
import SwiftData

@Model
final class FilmRoll {
    var rollUUID: String = UUID().uuidString
    var filmType: String = ""
    var createdAt: Date = Date()
    var isActive: Bool = false
    var name: String
    var iso: Int
    var cameraModel: String = ""
    var lensModel: String = ""
    var loadDate: Date
    var totalFrames: Int
    var isFinished: Bool

    @Relationship(deleteRule: .cascade, inverse: \FilmFrame.roll)
    var frames: [FilmFrame] = []

    init(
        rollUUID: String = UUID().uuidString,
        filmType: String = "",
        createdAt: Date = Date(),
        isActive: Bool = false,
        name: String,
        iso: Int,
        cameraModel: String = "",
        lensModel: String = "",
        loadDate: Date = Date(),
        totalFrames: Int = 36,
        isFinished: Bool = false
    ) {
        self.rollUUID = rollUUID
        self.filmType = filmType.isEmpty ? name : filmType
        self.createdAt = createdAt
        self.isActive = isActive
        self.name = name
        self.iso = iso
        self.cameraModel = cameraModel
        self.lensModel = lensModel
        self.loadDate = loadDate
        self.totalFrames = totalFrames
        self.isFinished = isFinished
    }
}

@Model
final class FilmFrame {
    var timestamp: Date
    var aperture: String
    var shutter: String
    var latitude: Double?
    var longitude: Double?
    var photoIdentifier: String?

    var roll: FilmRoll?

    init(
        timestamp: Date = Date(),
        aperture: String = "",
        shutter: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil,
        photoIdentifier: String? = nil
    ) {
        self.timestamp = timestamp
        self.aperture = aperture
        self.shutter = shutter
        self.latitude = latitude
        self.longitude = longitude
        self.photoIdentifier = photoIdentifier
    }
}
