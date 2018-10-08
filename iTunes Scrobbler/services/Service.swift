//
//  Service.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 1/8/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Foundation

/**
 Protocol to implement in the target of those methods for listening to a player
 service events.
 */
protocol ServiceDelegate {
    /**
     Notifies when the service detects the state of the player has changed.

     - Parameter state: The new state of the player.
     - Parameter metadata: If state is not inactive, will pass the metadata
     - Parameter scrobbled: If state is not active, will pass if scrobbled
     */
    func serviceStateChanged(_ state: ServiceState, _ metadata: SongMetadata?, _ scrobbled: Bool)

    /**
     Notifies when the service detects a song has changed.

     - Parameter metadata: The metadata of the new song.
     */
    func serviceSongChanged(_ metadata: SongMetadata)

    /**
     Notifies when the song has reached either 4 minutes or half duration
     playing the song.

     - Parameters:
        - metadata: The metadata of the playing song.
        - timestamp: The clock time when the song started to play.
     */
    func serviceScrobbleTime(_ metadata: SongMetadata, _ timestamp: Date)

    /**
     Notifies when the app has no access to the player through AppleScript.

     - Parameters:
        - service: A reference to the service that originated the lack of permissions.
        - status: Status of the permission that has the app to the player
     */
    func permissionCheckFailed(_ service: Service, _ status: ServicePermissionStatus)
}

/**
 Indicates the state of the player.
 */
enum ServiceState {
    case inactive
    case playing
    case paused
}

enum ServicePermissionStatus {
    case AppNotRunning
    case Denied
    case UserRequested
}

/**
 Protocol that defines the common interface for a player service.
 */
protocol Service {
    /**
     Notifies the service that it should start listening for any events from
     the player and notifiy them to the delegate. The constructor should not
     start listening as the app has not been initialized yet.
     */
    func start()

    /**
     Name of the player
     */
    var name: String { get }

    /**
     The target of the notifications.
     */
    var delegate: ServiceDelegate? { get set }
}
