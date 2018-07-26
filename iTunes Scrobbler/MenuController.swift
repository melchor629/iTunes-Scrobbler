//
//  MenuController.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 7/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa
import ServiceManagement

class MenuController: NSObject {

    private let statusBarInactiveIcon = NSImage.Name(rawValue: "StatusBarInactiveTemplate")
    private let statusBarActiveNotScrobbledIcon = NSImage.Name(rawValue: "StatusBarActiveNotScrobbledTemplate")
    private let statusBarActiveScrobbledIcon = NSImage.Name(rawValue: "StatusBarActiveScrobbledTemplate")

    private var statusItem: NSStatusItem?
    private var cachedScrobblings: Int = 0

    internal var loggedIn = false
    internal var loggingIn = false
    internal var mustScrobble = true
    internal var openAtLogin = false
    internal var autoUpdate: Bool? = nil

    override init() {
        super.init()
        createMenu()
    }

    private func createMenu() {
        let statusMenu = NSMenu(title: "iTunes Scrobbler")
        statusMenu.addItem(
            withTitle: NSLocalizedString("STATE_INACTIVE", comment: "Menu: Status when iTunes is closed or stopped"),
            action: nil,
            keyEquivalent: ""
        ).tag = 1
        statusMenu.addItem(
            withTitle: NSLocalizedString("SCROBBLED", comment: "Menu: When the song is scrobbled, this text is visible"),
            action: nil,
            keyEquivalent: ""
        ).tag = 2
        statusMenu.addItem(NSMenuItem.separator())

        statusMenu.addItem(
            withTitle: NSLocalizedString("LOGGED_IN", comment: "Menu: When logged in"),
            action: nil,
            keyEquivalent: ""
        ).tag = 3
        statusMenu.addItem(
            withTitle: NSLocalizedString("END_LOG_IN", comment: "Menu: To end the authentication process"),
            action: #selector(MenuController.endLogIn),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: NSLocalizedString("CANCEL_LOG_IN", comment: "Menu: To end the authentication process by cancelling"),
            action: #selector(MenuController.cancelLogIn),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: NSLocalizedString("NOT_LOGGED_IN", comment: "Menu: Log in"),
            action: #selector(MenuController.logIn),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: NSLocalizedString("LOG_OUT", comment: "Menu: Log out"),
            action: #selector(MenuController.logOut),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(NSMenuItem.separator())

        statusMenu.addItem(
            withTitle: NSLocalizedString("IN_CACHE", comment: "Menu: Scrobblings to be scrobbled"),
            action: nil,
            keyEquivalent: ""
        ).tag = 5
        statusMenu.addItem(
            withTitle: NSLocalizedString("SCROBBLE_NOW", comment: "Menu: Scrobble now"),
            action: #selector(MenuController.scrobbleNow),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: NSLocalizedString("SEE_SCROBBLINGS", comment: "Menu: Show cached scrobblings"),
            action: #selector(MenuController.showCachedScrobblings),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(NSMenuItem.separator())

        statusMenu.addItem(
            withTitle: NSLocalizedString("SEND_SCROBBLE_STATUS", comment: "Menu: Enables/Disables scrobblings sending"),
            action: #selector(MenuController.changeSendScrobbleStatus),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: NSLocalizedString("RUN_AT_LOGIN", comment: "Menu: Run at login"),
            action: #selector(MenuController.changeRunAtLogin),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: NSLocalizedString("AUTO_UPDATE", comment: "Menu: Auto update"),
            action: #selector(MenuController.changeAutoUpdate),
            keyEquivalent: ""
            ).target = self
        statusMenu.addItem(NSMenuItem.separator())

        statusMenu.addItem(
            withTitle: NSLocalizedString("ABOUT", comment: "Menu: About window opener"),
            action: #selector(MenuController.openAboutWindow),
            keyEquivalent: ""
        ).target = self
        statusMenu.addItem(
            withTitle: NSLocalizedString("QUIT", comment: "Menu: Close the app"),
            action: #selector(MenuController.quit),
            keyEquivalent: ""
        ).target = self

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem!.image = NSImage(named: statusBarInactiveIcon)
        statusItem!.menu = statusMenu
        statusItem!.highlightMode = true

        DispatchQueue.main.async {
            self.mustScrobble = DBFacade.shared.sendScrobbles
            self.openAtLogin = DBFacade.shared.openAtLogin
        }
    }

    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(MenuController.changeRunAtLogin) {
            menuItem.state = openAtLogin ? .on : .off
        } else if menuItem.action == #selector(MenuController.logOut) {
            menuItem.isHidden = !loggedIn || loggingIn
        } else if menuItem.action == #selector(MenuController.logIn) {
            menuItem.isHidden = loggedIn || loggingIn
        } else if menuItem.action == #selector(MenuController.endLogIn) {
            menuItem.isHidden = !loggingIn
        } else if menuItem.action == #selector(MenuController.cancelLogIn) {
            menuItem.isHidden = !loggingIn
        } else if menuItem.action == #selector(MenuController.scrobbleNow) {
            menuItem.isHidden = !loggedIn || loggingIn || cachedScrobblings == 0
        } else if menuItem.action == #selector(MenuController.showCachedScrobblings) {
            menuItem.isHidden = !loggedIn || loggingIn || cachedScrobblings == 0
        } else if menuItem.action == #selector(MenuController.changeSendScrobbleStatus) {
            menuItem.isHidden = !loggedIn || loggingIn
            menuItem.state = mustScrobble ? .on : .off
        } else if menuItem.action == #selector(MenuController.changeAutoUpdate) {
            menuItem.isHidden = autoUpdate == nil
            menuItem.state = autoUpdate != nil && autoUpdate! ? .on : .off
        }
        return true
    }

    @objc func logIn() {
        let app = NSApp.delegate! as! AppDelegate
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("LOG_IN_MESSAGE_TEXT", comment: "Alert: Message text when logging in")
        alert.alertStyle = .informational
        alert.runModal()
        app.lastfm.startAutentication()
        loggingIn = true
    }

    @objc func endLogIn() {
        loggingIn = false
        let app = NSApp.delegate! as! AppDelegate
        app.lastfm.endAuthentication { (token, username) in
            if let token = token {
                do {
                    app.account = try DBFacade.shared.addAccount(username!, token)
                    self.setLoggedInState(username!)
                } catch let error as NSError {
                    self.setLoggedOutState()
                    log("Could not save user in DB \(error), \(error.userInfo)")
                }
            } else {
                self.setLoggedOutState()
                let alert = NSAlert()
                alert.messageText = NSLocalizedString("LOG_IN_ERROR_MESSAGE_TEXT", comment: "Alert: Message text when logging in but occurred an error")
                alert.alertStyle = .critical
                alert.runModal()
            }
        }
    }

    @objc func cancelLogIn() {
        loggingIn = false
    }

    @objc func logOut() {
        loggedIn = false
        let app = NSApp.delegate! as! AppDelegate
        app.lastfm.token = nil
        try! DBFacade.shared.deleteAccount(app.account!)
        app.account = nil
    }

    @objc func scrobbleNow() {
        let app = NSApp.delegate! as! AppDelegate
        app.scrobbleNow(true)
    }

    @objc func showCachedScrobblings() {
        (NSApp.delegate! as! AppDelegate).openScrobblingsCacheWindow()
    }

    @objc func changeSendScrobbleStatus() {
        mustScrobble = !mustScrobble
        DBFacade.shared.sendScrobbles = mustScrobble
    }

    @objc func changeRunAtLogin() {
        openAtLogin = !openAtLogin
        DBFacade.shared.openAtLogin = openAtLogin
        log("Changed open at login to \(openAtLogin) " + (SMLoginItemSetEnabled("me.melchor9000.iTunes-Scrobbler-Launcher" as CFString, openAtLogin) ? "sucessfully" : "unsuccessfully"))
    }

    @objc func openAboutWindow() {
        (NSApp.delegate! as! AppDelegate).openAboutWindow()
    }

    @objc func quit() {
        NSApplication.shared.terminate(self)
    }

    @objc func changeAutoUpdate() {
        autoUpdate! = !autoUpdate!
        DBFacade.shared.autoUpdate = autoUpdate!
        if autoUpdate! {
            (NSApp.delegate! as! AppDelegate).updater!.start()
        } else {
            (NSApp.delegate! as! AppDelegate).updater!.stop()
        }
    }

    internal func setSongState(_ metadata: SongMetadata, scrobbled: Bool) {
        var text = metadata.trackTitle!
        if let artist = metadata.artistName {
            text += " - " + artist
        }
        statusItem?.menu!.item(withTag: 1)!.title = text
        statusItem?.menu!.item(withTag: 2)!.isHidden = !scrobbled
        statusItem?.image = NSImage(named: scrobbled ? statusBarActiveScrobbledIcon : statusBarActiveNotScrobbledIcon)
    }

    internal func setInactiveState() {
        statusItem?.menu!.item(withTag: 1)!.title = NSLocalizedString("STATE_INACTIVE", comment: "Menu: iTunes is inactive")
        statusItem?.menu!.item(withTag: 2)!.isHidden = true
        statusItem?.image = NSImage(named: statusBarInactiveIcon)
    }

    internal func setLoggedOutState() {
        loggedIn = false
        statusItem?.menu!.item(withTag: 3)!.isHidden = true
    }

    internal func setLoggedInState(_ username: String) {
        loggedIn = true
        statusItem?.menu!.item(withTag: 3)!.isHidden = false
        statusItem?.menu!.item(withTag: 3)!.title = NSLocalizedString("LOGGED_IN", comment: "") + username
    }

    internal func showIfNeeded() {
        if statusItem == nil {
            createMenu()
        }
    }

    internal func updateScrobbleCacheCount(_ count: Int) {
        cachedScrobblings = count
        statusItem?.menu!.item(withTag: 5)!.title = NSLocalizedString("IN_CACHE", comment: "Menu: Scrobblings to be scrobbled") + String(count)
    }

}
