//
//  AppDelegate.swift
//  iTunes Scrobbler Launcher
//
//  Created by Melchor Garau Madrigal on 11/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

extension Notification.Name {
    static let killLauncher = Notification.Name("me.melchor9000.iTunes-Scrobbler.killLauncher")
}

//https://theswiftdev.com/2017/10/27/how-to-launch-a-macos-app-at-login/
@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let mainAppIdentifier = "me.melchor9000.iTunes-Scrobbler"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == mainAppIdentifier }.isEmpty
        NSLog("iTunes Scrobbler is \(isRunning ? "" : "not") running")

        if !isRunning {
            DistributedNotificationCenter.default().addObserver(self,
                                                                selector: #selector(self.terminate),
                                                                name: .killLauncher,
                                                                object: mainAppIdentifier)
            let path = Bundle.main.bundlePath as NSString
            var components = path.pathComponents
            components.removeLast()
            components.removeLast()
            components.removeLast()
            components.append("MacOS")
            components.append("iTunes Scrobbler")
            let newPath = NSString.path(withComponents: components)
            NSWorkspace.shared.launchApplication(newPath)
        } else {
            terminate()
        }
    }

    @objc func terminate() {
        NSApp.terminate(nil)
    }

}

