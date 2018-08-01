//
//  SongMetadata.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 1/8/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

internal func emptyIsNil(_ a: String?) -> String? {
    if a != nil && a!.isEmpty {
        return nil
    } else {
        return a
    }
}

internal func intOr0(_ a: Int?) -> Int {
    if let a = a { return a } else { return 0 }
}

struct SongMetadata {
    var trackTitle: String?
    var artistName: String?
    var albumArtistName: String?
    var albumName: String?
    var duration = 0.0

    init() {}

    init(managedObject: NSManagedObject) {
        trackTitle = emptyIsNil(managedObject.value(forKey: "track") as? String)
        artistName = emptyIsNil(managedObject.value(forKey: "artist") as? String)
        albumArtistName = emptyIsNil(managedObject.value(forKey: "albumArtist") as? String)
        albumName = emptyIsNil(managedObject.value(forKey: "album") as? String)
        duration = (managedObject.value(forKey: "duration") as! NSNumber).doubleValue
    }

    static internal func non(_ a: Int?) -> Int {
        if let a = a { return a } else { return 0 }
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
