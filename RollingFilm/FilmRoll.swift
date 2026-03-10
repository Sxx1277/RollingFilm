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
    var name: String
    var iso: Int
    var loadDate: Date
    var totalFrames: Int
    var isFinished: Bool

    @Relationship(deleteRule: .cascade, inverse: \FilmFrame.roll)
    var frames: [FilmFrame] = []

    init(
        name: String,
        iso: Int,
        loadDate: Date = Date(),
        totalFrames: Int = 36,
        isFinished: Bool = false
    ) {
        self.name = name
        self.iso = iso
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

    var roll: FilmRoll?

    init(
        timestamp: Date = Date(),
        aperture: String = "",
        shutter: String = "",
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.timestamp = timestamp
        self.aperture = aperture
        self.shutter = shutter
        self.latitude = latitude
        self.longitude = longitude
    }
}
