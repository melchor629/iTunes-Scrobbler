//
//  Service.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 1/8/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Foundation

protocol ServiceDelegate {
    func serviceStateChanged(_ state: ServiceState)
    func serviceSongChanged(_ metadata: SongMetadata)
    func serviceScrobbleTime(_ metadata: SongMetadata, _ timestamp: Date)
}

enum ServiceState {
    case inactive
    case playing
}

protocol Service {
    func start()
    var delegate: ServiceDelegate? { get set }
}
