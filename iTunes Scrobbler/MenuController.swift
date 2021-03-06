//
//  MenuController.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 7/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa
import ServiceManagement

fileprivate class MenuItemBuilder {
    private let item: NSMenuItem

    init(_ menu: NSMenu, _ key: String, comment: String) {
        self.item = menu.addItem(
            withTitle: NSLocalizedString(key, comment: comment),
            action: nil,
            keyEquivalent: ""
        )
    }

    @discardableResult
    func setTag(_ tag: Int) -> MenuItemBuilder {
        item.tag = tag
        return self
    }

    @discardableResult
    func setAction(_ selector: Selector, target: AnyObject) -> MenuItemBuilder {
        item.action = selector
        item.target = target
        return self
    }

    @discardableResult
    func setTooltip(_ key: String, comment: String) -> MenuItemBuilder {
        item.toolTip = NSLocalizedString(key, comment: comment)
        return self
    }
}

class MenuController: NSObject, NSMenuItemValidation {

    private let statusBarInactiveIcon = "StatusBarInactiveTemplate"
    private let statusBarActiveNotScrobbledIcon = "StatusBarActiveNotScrobbledTemplate"
    private let statusBarActiveScrobbledIcon = "StatusBarActiveScrobbledTemplate"
    private let inactiveTag = 1
    private let scrobbledTag = 2
    private let loggedInTag = 3
    private let cacheTag = 4

    private var statusItem: NSStatusItem?
    private var cachedScrobblings: Int = 0
    private var username: String?
    private let log = Logger(category: "MenuController")

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
        MenuItemBuilder(statusMenu, "STATE_INACTIVE", comment: "Menu: Status when iTunes is closed or stopped")
            .setTag(inactiveTag)
        MenuItemBuilder(statusMenu, "SCROBBLED", comment: "Menu: When the song is scrobbled, this text is visible")
            .setTag(scrobbledTag)
        statusMenu.addItem(NSMenuItem.separator())

        MenuItemBuilder(statusMenu, "LOGGED_IN", comment: "Menu: When logged in")
            .setTag(loggedInTag)
            .setAction(#selector(MenuController.openUserProfile), target: self)
            .setTooltip("LOGGED_IN_TOOLTIP", comment: "Menu tooltip: Shows that when clicked, will open his Last.FM profile")
        MenuItemBuilder(statusMenu, "END_LOG_IN", comment: "Menu: To end the authentication process")
            .setAction(#selector(MenuController.endLogIn), target: self)
        MenuItemBuilder(statusMenu, "CANCEL_LOG_IN", comment: "Menu: To end the authentication process by cancelling")
            .setAction(#selector(MenuController.cancelLogIn), target: self)
        MenuItemBuilder(statusMenu, "NOT_LOGGED_IN", comment: "Menu: Log in")
            .setAction(#selector(MenuController.logIn), target: self)
        MenuItemBuilder(statusMenu, "LOG_OUT", comment: "Menu: Log out")
            .setAction(#selector(MenuController.logOut), target: self)
        statusMenu.addItem(NSMenuItem.separator())

        MenuItemBuilder(statusMenu, "IN_CACHE", comment: "Menu: Scrobblings to be scrobbled")
            .setTag(cacheTag)
        MenuItemBuilder(statusMenu, "SCROBBLE_NOW", comment: "Menu: Scrobble now button")
            .setAction(#selector(MenuController.scrobbleNow), target: self)
        MenuItemBuilder(statusMenu, "SEE_SCROBBLINGS", comment: "Menu: Show cached scrobblings")
            .setAction(#selector(MenuController.showCachedScrobblings), target: self)
        statusMenu.addItem(NSMenuItem.separator())

        MenuItemBuilder(statusMenu, "SEND_SCROBBLE_STATUS", comment: "Menu: Enables/Disables scrobblings sending (toggle)")
            .setAction(#selector(MenuController.changeSendScrobbleStatus), target: self)
        MenuItemBuilder(statusMenu, "RUN_AT_LOGIN", comment: "Menu: Run at login toggle")
            .setAction(#selector(MenuController.changeRunAtLogin), target: self)
        MenuItemBuilder(statusMenu, "AUTO_UPDATE", comment: "Menu: Auto update toggle")
            .setAction(#selector(MenuController.changeAutoUpdate), target: self)
        statusMenu.addItem(NSMenuItem.separator())

        MenuItemBuilder(statusMenu, "ABOUT", comment: "Menu: About window opener")
            .setAction(#selector(MenuController.openAboutWindow), target: self)
        MenuItemBuilder(statusMenu, "QUIT", comment: "Menu: Close the app")
            .setAction(#selector(MenuController.quit), target: self)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem!.image = NSImage(named: statusBarInactiveIcon)
        statusItem!.menu = statusMenu
        statusItem!.highlightMode = true

        statusItem!.menu!.item(withTag: scrobbledTag)!.isHidden = true;

        DispatchQueue.main.async {
            self.mustScrobble = DBFacade.shared.sendScrobbles
            self.openAtLogin = DBFacade.shared.openAtLogin
        }
    }

    public func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
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
        } else if menuItem.action == #selector(MenuController.openUserProfile) {
            menuItem.isHidden = !loggedIn || loggingIn
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
        log.debug("Start log in process")
    }

    @objc func endLogIn() {
        loggingIn = false
        let app = NSApp.delegate! as! AppDelegate
        log.debug("Received end of log in process, checking for user token...")
        app.lastfm.endAuthentication { (token, username) in
            if let token = token {
                do {
                    app.account = try DBFacade.shared.addAccount(username!, token)
                    self.setLoggedInState(username!)
                    self.log.debug("Token received, stored in DB")
                } catch let error as NSError {
                    self.setLoggedOutState()
                    self.log.error("Could not save user in DB \(error), \(error.userInfo)")
                }
            } else {
                self.log.debug("Token is nil, an error has occurred")
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
        log.debug("User has cancelled log in process")
    }

    @objc func logOut() {
        loggedIn = false
        let app = NSApp.delegate! as! AppDelegate
        app.lastfm.token = nil
        try! DBFacade.shared.deleteAccount(app.account!)
        app.account = nil
        log.debug("Account has been removed (log out)")
    }

    @objc func scrobbleNow() {
        let app = NSApp.delegate! as! AppDelegate
        app.scrobbleNow(true)
        log.debug("User has pressed 'scrobble now' button")
    }

    @objc func showCachedScrobblings() {
        (NSApp.delegate! as! AppDelegate).openScrobblingsCacheWindow()
    }

    @objc func changeSendScrobbleStatus() {
        mustScrobble = !mustScrobble
        DBFacade.shared.sendScrobbles = mustScrobble
        log.debug("User changed 'send scrobble' status to \(mustScrobble)")
    }

    @objc func changeRunAtLogin() {
        openAtLogin = !openAtLogin
        DBFacade.shared.openAtLogin = openAtLogin
        log.debug("Changed open at login to \(openAtLogin) " + (SMLoginItemSetEnabled("me.melchor9000.iTunes-Scrobbler-Launcher" as CFString, openAtLogin) ? "sucessfully" : "unsuccessfully"))
    }

    @objc func openAboutWindow() {
        (NSApp.delegate! as! AppDelegate).openAboutWindow()
    }

    @objc func quit() {
        log.warning("Quiting...")
        NSApplication.shared.terminate(self)
    }

    @objc func changeAutoUpdate() {
        autoUpdate! = !autoUpdate!
        DBFacade.shared.autoUpdate = autoUpdate!
        if autoUpdate! {
            log.debug("User changed auto update to on")
            (NSApp.delegate! as! AppDelegate).updater!.start()
        } else {
            log.debug("User changed auto update to off")
            (NSApp.delegate! as! AppDelegate).updater!.stop()
        }
    }

    @objc func openUserProfile() {
        if let username = self.username {
            NSWorkspace.shared.open(URL(string: "https://www.last.fm/user/\(username)")!)
            log.debug("User pressed in its username, profile page is opening...")
        }
    }

    internal func setSongState(_ metadata: SongMetadata, scrobbled: Bool, paused: Bool = false) {
        var text = metadata.trackTitle != nil ? metadata.trackTitle! : "?"
        if let artist = metadata.artistName {
            text += " - " + artist
        }

        if paused {
            text = "⏸ \(text)"
        } else {
            text = "▶️ \(text)"
        }

        if metadata.canBeScrobbled {
            statusItem?.image = NSImage(named: scrobbled ? statusBarActiveScrobbledIcon : statusBarActiveNotScrobbledIcon)
        } else {
            statusItem?.image = NSImage(named: statusBarInactiveIcon)
        }

        statusItem?.menu!.item(withTag: inactiveTag)!.title = text
        statusItem?.menu!.item(withTag: scrobbledTag)!.isHidden = !scrobbled
        log.debug("Changing song state to \"\(text)\" - Scrobbled? \(scrobbled)")
    }

    internal func setInactiveState() {
        statusItem?.menu!.item(withTag: inactiveTag)!.title = NSLocalizedString("STATE_INACTIVE", comment: "Menu: iTunes is inactive")
        statusItem?.menu!.item(withTag: scrobbledTag)!.isHidden = true
        statusItem?.image = NSImage(named: statusBarInactiveIcon)
        log.debug("Changing song state to inactive")
    }

    internal func setLoggedOutState() {
        loggedIn = false
        statusItem?.menu!.item(withTag: loggedInTag)!.isHidden = true
    }

    internal func setLoggedInState(_ username: String) {
        self.username = username
        loggedIn = true
        statusItem?.menu!.item(withTag: loggedInTag)!.isHidden = false
        statusItem?.menu!.item(withTag: loggedInTag)!.title = NSLocalizedString("LOGGED_IN", comment: "") + username
    }

    internal func showIfNeeded() {
        if statusItem == nil {
            createMenu()
        }
    }

    internal func updateScrobbleCacheCount(_ count: Int) {
        cachedScrobblings = count
        statusItem?.menu!.item(withTag: cacheTag)!.title = NSLocalizedString("IN_CACHE", comment: "Menu: Scrobblings to be scrobbled") + String(count)
        log.debug("Changing scrobble cache count to \(count)")
    }

}
