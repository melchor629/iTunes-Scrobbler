//
//  VibrantDarkView.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 11/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

class VibrantDarkView: NSVisualEffectView {

    open override var allowsVibrancy: Bool { get { return true } }

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        self.material = .appearanceBased
        self.blendingMode = .behindWindow
        self.state = .active
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        self.material = .dark
        self.blendingMode = .behindWindow
        self.state = .active
    }

}
