//
//  SongMetadata.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 1/8/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

/// Returns nil if the string is empty too.
/// - Parameter a: The string to check.
/// - Returns: nil if the string is nil or empty.
internal func emptyIsNil(_ a: String?) -> String? {
    if a != nil && a!.isEmpty {
        return nil
    } else {
        return a
    }
}

/// Holds metadata from a song.
struct SongMetadata {
    var trackTitle: String?
    var artistName: String?
    var albumArtistName: String?
    var albumName: String?
    var duration: Double? = 0.0
    var playedCount: UInt?

    init() {}

    /// Creates an instance from a NSManagedObject from a cached scrobble.
    /// - Parameter managedObject: Cached scrobble.
    init(managedObject: NSManagedObject) {
        trackTitle = emptyIsNil(managedObject.value(forKey: "track") as? String)
        artistName = emptyIsNil(managedObject.value(forKey: "artist") as? String)
        albumArtistName = emptyIsNil(managedObject.value(forKey: "albumArtist") as? String)
        albumName = emptyIsNil(managedObject.value(forKey: "album") as? String)
        duration = (managedObject.value(forKey: "duration") as! NSNumber).doubleValue
        playedCount = (managedObject.value(forKey: "playedCount") as? NSNumber)?.uintValue
    }

    var hash: Int {
        get {
            let trackTitleHash = trackTitle?.hashValue ?? 0
            let artistNameHash = artistName?.hashValue ?? 0
            let albumArtistNameHash = albumArtistName?.hashValue ?? 0
            let albumNameHash = albumName?.hashValue ?? 0
            let playedCountHash = playedCount?.hashValue ?? 0
            return trackTitleHash ^
                (artistNameHash << 2) ^
                (albumArtistNameHash << 4) ^
                (albumNameHash << 6) ^
                (playedCountHash << 8)
        }
    }

    var canBeScrobbled: Bool {
        return trackTitle != nil && artistName != nil && duration != nil && duration! >= 30
    }

}

func ==(a: SongMetadata, b: SongMetadata) -> Bool {
    return a.trackTitle == b.trackTitle && a.artistName == b.artistName && a.albumArtistName == b.albumArtistName && a.albumName == b.albumName && a.playedCount == b.playedCount
}

func !=(a: SongMetadata, b: SongMetadata) -> Bool {
    return !(a == b)
}
