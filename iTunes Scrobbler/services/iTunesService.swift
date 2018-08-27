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

extension SongMetadata {
    /**
     Creates an instance of SongMetadata from an iTunesTrack.
     - Parameter track: iTunes track that will be used to fill the new instance
     */
    init(track: iTunesTrack) {
        trackTitle = emptyIsNil(track.name)
        artistName = emptyIsNil(track.artist)
        albumArtistName = emptyIsNil(track.albumArtist)
        albumName = emptyIsNil(track.album)
        duration = track.duration!
    }
}


/**
 Service implementation for iTunes player.
 */
class iTunesService: Service {

    private let iTunes = SBApplication(bundleIdentifier: "com.apple.iTunes")! as iTunesApplication

    var delegate: ServiceDelegate?

    private var state = ServiceState.inactive {
        didSet {
            log("Player State is now: \(state)")
            delegate?.serviceStateChanged(state, state == .inactive ? nil : self.metadata, scrobbled)
        }
    }
    private var metadata: SongMetadata = SongMetadata() {
        didSet {
            timeStartPlayingSong = Date()
            log("Player metadata is now: \(metadata) [\(timeStartPlayingSong)]")
            delegate?.serviceSongChanged(metadata)
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

        checkForStatus()
    }

    @objc func playerStateChanged(_ notification: Notification) {
        let playerState = notification.userInfo!["Player State"] as! String
        log("iTunes status changed received: \(playerState)")
        if playerState == "Stopped" {
            state = .inactive
        } else if playerState == "Paused" {
            state = .paused
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
                    delegate?.serviceScrobbleTime(metadata, timeStartPlayingSong!)
                }
            }
        }
    }

    private func checkForStatus() {
        if self.state != .inactive && (!self.isRunning || self.iTunes.playerState == .stopped) {
            self.state = .inactive
        } else if self.state != .paused && self.isRunning && self.iTunes.playerState != .stopped && self.iTunes.playerState != .playing {
            self.state = .paused
        } else if self.state != .playing && self.isRunning && self.iTunes.playerState == .playing {
            self.checkSongChanges()
            self.state = .playing
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(10)) {
            self.checkForStatus()
        }
    }

}
