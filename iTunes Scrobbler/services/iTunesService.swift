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
     Creates an instance of SongMetadata from an iTunes Track.
     - Parameter track: iTunes track that will be used to fill the new instance
     */
    init(_ info: [String: Any]) {
        trackTitle = info["name"] as! String?
        artistName = info["artist"] as! String?
        albumArtistName = info["albumArtist"] as! String?
        albumName = info["album"] as! String?
        duration = info["duration"] as! Double
    }
}


/**
 Service implementation for iTunes player.
 */
class iTunesService: Service {

    private let getCurrentTrackScript = AppleScript("""
on getOrNull(value)
    if value is "" or value is 0 then
        return "null"
    else if class of value is text then
        return quote & value & quote
    else
        return value
    end if
end getOrNull

tell application "iTunes"
    set t to current track
    "name: " & my getOrNull(name of t) & "
artist: " & my getOrNull(artist of t) & "
album: " & my getOrNull(album of t) & "
duration: " & (duration of t as text) & "
albumArtist: " & my getOrNull(album artist of t)
end tell
""")
    private let getPlayerPositionScript = AppleScript("""
tell application "iTunes"
    "position: " & (player position as text)
end tell
""")
    private let getPlayerStateScript = AppleScript("""
tell application "iTunes"
    "state: " & player state
end tell
""")
    private let log = Logger(category: "iTunesService")

    var delegate: ServiceDelegate?

    private var state = ServiceState.inactive {
        didSet {
            log.debug("Player State is now: \(state)")
            delegate?.serviceStateChanged(state, state == .inactive ? nil : self.metadata, scrobbled)
        }
    }
    private var metadata: SongMetadata = SongMetadata() {
        didSet {
            timeStartPlayingSong = Date()
            log.debug("Player metadata is now: \(metadata) [\(timeStartPlayingSong!)]")
            delegate?.serviceSongChanged(metadata)
        }
    }
    private var timeStartPlayingSong: Date? = nil
    private var scrobbled = false

    var name: String {
        get { return "iTunes" }
    }

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
        log.debug("iTunes status changed received: \(playerState)")
        if playerState == "Stopped" {
            state = .inactive
        } else if playerState == "Paused" {
            state = .paused
        } else if playerState == "Playing" {
            checkSongChanges()
            state = .playing
        }
    }

    private func checkAppleScriptPermission() {
        if #available(macOS 10.14, *) {
            if !isRunning { return }
            //See https://www.felix-schwarz.org/blog/2018/08/new-apple-event-apis-in-macos-mojave
            let desc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.iTunes").aeDesc!
            let status = AEDeterminePermissionToAutomateTarget(desc, 0x61657674, typeWildCard, true)

            if status == -1743 {
                //User has declined the permission
                delegate?.permissionCheckFailed(self, .Denied)
            } else if status == -1744 {
                //User has to be requested for permission
                delegate?.permissionCheckFailed(self, .UserRequested)
            } else if status == -600 {
                //App is not running
                delegate?.permissionCheckFailed(self, .AppNotRunning)
            }
        }
    }

    private func checkSongChanges() {
        checkAppleScriptPermission()
        let currentSong = SongMetadata(getCurrentTrackScript.run())

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

    private var playerState: String {
        get {
            return getPlayerStateScript.run()["state"] as! String
        }
    }

    private func checkForScrobbling(inside: Bool = false) {
        if !self.isRunning {
            state = .inactive
        } else {
            if !scrobbled {
                let position = getPlayerPositionScript.run()["position"] as! Double
                let scrobbleTime = min(metadata.duration / 2, 4 * 60)
                if position < scrobbleTime {
                    let timeToHalf = Int((scrobbleTime - position) * 1000)
                    log.debug("Next scrobbling checc \(timeToHalf)ms")
                    DispatchQueue.main.asyncAfter(deadline: DispatchTimeInterval.milliseconds(timeToHalf).fromNow) {
                        self.checkForScrobbling(inside: true)
                    }
                } else {
                    inside ? log.debug("Scrobbling from inside!") : log.debug("Scrobbling!")
                    scrobbled = true
                    delegate?.serviceScrobbleTime(metadata, timeStartPlayingSong!)
                }
            }
        }
    }

    private func checkForStatus() {
        checkAppleScriptPermission()
        if self.state != .inactive && (!self.isRunning || playerState == "stopped") {
            self.state = .inactive
        } else if self.state != .paused && self.isRunning && playerState != "stopped" && playerState != "playing" {
            self.checkSongChanges()
            self.state = .paused
        } else if self.state != .playing && self.isRunning && playerState == "playing" {
            self.checkSongChanges()
            self.state = .playing
        }
        DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(10)) {
            self.checkForStatus()
        }
    }

}
