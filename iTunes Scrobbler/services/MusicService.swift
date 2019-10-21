//
//  MusicService.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 09/10/2019.
//  Copyright © 2019 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

/**
 Service implementation for iTunes player.
 */
class MusicService: Service {

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

tell application "Music"
    "name: " & my getOrNull(name of current track) & "
artist: " & my getOrNull(artist of current track) & "
album: " & my getOrNull(album of current track) & "
duration: " & (duration of current track as text) & "
albumArtist: " & my getOrNull(album artist of current track)
end tell
""")
    private let getPlayerPositionScript = AppleScript("""
tell application "Music"
    "position: " & (player position as text)
end tell
""")
    private let getPlayerStateScript = AppleScript("""
tell application "Music"
    "state: " & player state
end tell
""")
    private let log = Logger(category: "MusicService")

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
        get { return "Music" }
    }

    func start() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(MusicService.playerStateChanged),
            name: NSNotification.Name(rawValue: "com.apple.Music.playerInfo"),
            object: nil
        )

        checkForStatus()
    }

    @objc func playerStateChanged(_ notification: Notification) {
        let playerState = notification.userInfo?["Player State"] as? String ?? "Stopped"
        log.debug("Music status changed received: \(playerState)")
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
            let desc = NSAppleEventDescriptor(bundleIdentifier: "com.apple.Music").aeDesc!
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
        do {
            let scriptResult = try getCurrentTrackScript.run()
            let currentSong = SongMetadata(scriptResult)

            if currentSong != self.metadata {
                self.metadata = currentSong
                self.scrobbled = false
            }

            checkForScrobbling()
        } catch let e as AppleScriptError {
            log.error("Script for getting current track metadata failed: \(e.message)")
        } catch let e {
            log.error("Getting current track metadata has failed: \(e)")
        }
    }

    private var isRunning: Bool {
        get {
            return NSWorkspace.shared.runningApplications
                .filter { $0.bundleIdentifier == "com.apple.Music" }
                .count > 0
        }
    }

    private var playerState: String {
        get {
            return (try? getPlayerStateScript.run())?["state"] as? String ?? "Stopped"
        }
    }

    private func checkForScrobbling(inside: Bool = false) {
        if !self.isRunning {
            state = .inactive
        } else {
            if !scrobbled {
                guard metadata.canBeScrobbled else { return }
                var position: Double = 0.0
                do {
                    let scriptResult = try getPlayerPositionScript.run()
                    log.debug("script result for position: \(scriptResult["position"] ?? "nil")")
                    position = scriptResult["position"] as? Double ?? 0.0
                } catch let e as AppleScriptError {
                    log.error("Could not get player position: \(e.message)")
                } catch let e {
                    log.error("Could not get player position: \(e)")
                }

                let scrobbleTime = min(metadata.duration! / 2, 4 * 60)
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
