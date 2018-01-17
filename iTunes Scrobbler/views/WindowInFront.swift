//
//  WindowInFront.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 11/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

class WindowInFront: NSWindow {

    override init(contentRect: NSRect, styleMask style: NSWindow.StyleMask, backing backingStoreType: NSWindow.BackingStoreType, defer flag: Bool) {
        super.init(contentRect: contentRect, styleMask: style, backing: backingStoreType, defer: flag)
        self.orderFrontRegardless()
        self.setIsVisible(true)
        NSApp.activate(ignoringOtherApps: true)
    }

}
