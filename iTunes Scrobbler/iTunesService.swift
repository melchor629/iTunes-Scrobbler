//
//  iTunesService.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 7/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa
import ScriptingBridge

extension DispatchTimeInterval {
    public var fromNow: DispatchTime {
        return DispatchTime.now() + self
    }
}

enum iTunesState {
    case inactive
    case playing
}

struct SongMetadata {
    var trackTitle: String?
    var artistName: String?
    var albumArtistName: String?
    var albumName: String?
    var duration = 0.0

    init() {}
    init(track: iTunesTrack) {
        trackTitle = non(track.name)
        artistName = non(track.artist)
        albumArtistName = non(track.albumArtist)
        albumName = non(track.album)
        duration = track.duration!
    }

    init(managedObject: NSManagedObject) {
        trackTitle = non(managedObject.value(forKey: "track") as? String)
        artistName = non(managedObject.value(forKey: "artist") as? String)
        albumArtistName = non(managedObject.value(forKey: "albumArtist") as? String)
        albumName = non(managedObject.value(forKey: "album") as? String)
        duration = (managedObject.value(forKey: "duration") as! NSNumber).doubleValue
    }

    private func non(_ a: String?) -> String? {
        if a != nil && a!.isEmpty {
            return nil
        } else {
            return a
        }
    }

    private func non(_ a: Int?) -> Int {
        if let a = a { return a } else { return 0 }
    }

    var hash: Int {
        get {
            return non(trackTitle?.hashValue) ^
                (non(artistName?.hashValue) << 2) ^
                (non(albumArtistName?.hashValue) << 4) ^
                (non(albumName?.hashValue) << 6)
        }
    }

}

func ==(a: SongMetadata, b: SongMetadata) -> Bool {
    return a.trackTitle == b.trackTitle && a.artistName == b.artistName && a.albumArtistName == b.albumArtistName && a.albumName == b.albumName
}

func !=(a: SongMetadata, b: SongMetadata) -> Bool {
    return !(a == b)
}

protocol iTunesServiceDelegate {
    func iTunesStateChanged(_ state: iTunesState)
    func iTunesSongChanged(_ metadata: SongMetadata)
    func iTunesScrobbleTime(_ metadata: SongMetadata, _ timestamp: Date)
}

class iTunesService: NSObject {

    private let iTunes = SBApplication(bundleIdentifier: "com.apple.iTunes")! as iTunesApplication

    var delegate: iTunesServiceDelegate?

    private var state = iTunesState.inactive {
        didSet {
            delegate?.iTunesStateChanged(state)
        }
    }
    private var metadata: SongMetadata = SongMetadata() {
        didSet {
            timeStartPlayingSong = Date()
            delegate?.iTunesSongChanged(metadata)
        }
    }
    private var timeStartPlayingSong: Date? = nil
    private var scrobbled = false

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(iTunesService.playerStateChanged),
            name: NSNotification.Name(rawValue: "com.apple.iTunes.playerInfo"),
            object: nil
        )

        if isRunning {
            if iTunes.playerState != .stopped {
                state = .playing
                checkSongChanges()
            } else {
                state = .inactive
            }
        } else {
            state = .inactive
        }

        checkForStatus()
    }

    @objc func playerStateChanged(_ notification: Notification) {
        let playerState = notification.userInfo!["Player State"] as! String
        if playerState == "Stopped" || playerState == "Paused" {
            if playerState == "Stopped" {
                state = .inactive
            } else {
                state = .playing
            }
        } else if playerState == "Playing" {
            checkSongChanges()
            state = .playing
        }
    }

    private func checkSongChanges() {
        let currentSong = SongMetadata(track: iTunes.currentTrack!)
        if currentSong != self.metadata {
            self.metadata = currentSong
            self.scrobbled = false
        }
        checkForScrobbling()
    }

    private var isRunning: Bool {
        get {
            return NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == "com.apple.iTunes" }
                .count > 0
        }
    }

    private func checkForScrobbling(inside: Bool = false) {
        if !self.isRunning {
            state = .inactive
        } else {
            if !scrobbled {
                let position = iTunes.playerPosition!
                let scrobbleTime = min(metadata.duration / 2, 4 * 60)
                if position < scrobbleTime {
                    let timeToHalf = Int((scrobbleTime - position) * 1000)
                    log("Next scrobbling checc \(timeToHalf)ms")
                    DispatchQueue.main.asyncAfter(deadline: DispatchTimeInterval.milliseconds(timeToHalf).fromNow) {
                        self.checkForScrobbling(inside: true)
                    }
                } else {
                    inside ? log("Scrobbling from inside!") : log("Scrobbling!")
                    scrobbled = true
                    delegate?.iTunesScrobbleTime(metadata, timeStartPlayingSong!)
                }
            }
        }
    }

    private func checkForStatus() {
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(10)) {
            if self.state != .inactive && !self.isRunning {
                self.state = .inactive
            } else if self.state != .playing && self.isRunning && self.iTunes.playerState == .playing {
                self.state = .playing
            }
            self.checkForStatus()
        }
    }

}
