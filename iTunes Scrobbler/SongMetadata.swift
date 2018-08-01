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

/// Returns the number or 0 if nil.
internal func intOr0(_ a: Int?) -> Int {
    if let a = a { return a } else { return 0 }
}

/// Holds metadata from a song.
struct SongMetadata {
    var trackTitle: String?
    var artistName: String?
    var albumArtistName: String?
    var albumName: String?
    var duration = 0.0

    init() {}

    /// Creates an instance from a NSManagedObject from a cached scrobble.
    /// - Parameter managedObject: Cached scrobble.
    init(managedObject: NSManagedObject) {
        trackTitle = emptyIsNil(managedObject.value(forKey: "track") as? String)
        artistName = emptyIsNil(managedObject.value(forKey: "artist") as? String)
        albumArtistName = emptyIsNil(managedObject.value(forKey: "albumArtist") as? String)
        albumName = emptyIsNil(managedObject.value(forKey: "album") as? String)
        duration = (managedObject.value(forKey: "duration") as! NSNumber).doubleValue
    }

    var hash: Int {
        get {
            return intOr0(trackTitle?.hashValue) ^
                (intOr0(artistName?.hashValue) << 2) ^
                (intOr0(albumArtistName?.hashValue) << 4) ^
                (intOr0(albumName?.hashValue) << 6)
        }
    }

}

func ==(a: SongMetadata, b: SongMetadata) -> Bool {
    return a.trackTitle == b.trackTitle && a.artistName == b.artistName && a.albumArtistName == b.albumArtistName && a.albumName == b.albumName
}

func !=(a: SongMetadata, b: SongMetadata) -> Bool {
    return !(a == b)
}
