//
//  AppDelegate.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 7/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

internal func log(_ msg: String) {
    #if !NDEBUG
        NSLog("LOG: \(msg)")
    #endif
}

internal func log(_ obj: Any) {
    log(String(describing: obj))
}

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, iTunesServiceDelegate {

    internal static let addedScrobbling = NSNotification.Name(rawValue: "me.melchor9000.iTunes-Scrobbler.AppDelegate.addedScrobbling")
    internal static let sentScrobblings = NSNotification.Name(rawValue: "me.melchor9000.iTunes-Scrobbler.AppDelegate.sentScrobblings")

    internal let service = iTunesService()
    internal let menu = MenuController()
    internal var account: NSManagedObject?
    internal let lastfm: Lastfm
    internal let storyboard: NSStoryboard
    internal let updater: GithubUpdater?

    override init() {
        self.storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
        self.lastfm = Lastfm()
        self.updater = GithubUpdater()
        super.init()
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        service.delegate = self

        if let account = DBFacade.shared.getAccount() {
            self.account = account.2
            menu.setLoggedInState(account.0)
            lastfm.token = account.1
        } else {
            menu.setLoggedOutState()
        }
        updateScrobbleCacheCount()

        service.start()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(AppDelegate.deletedRowInTable),
            name: ScrobblingsListViewController.deletedScrobbling,
            object: nil
        )

        let launcherAppId = "me.melchor9000.iTunes-Scrobbler-Launcher"
        let runningApps = NSWorkspace.shared.runningApplications
        let isRunning = !runningApps.filter { $0.bundleIdentifier == launcherAppId }.isEmpty
        if isRunning {
            DistributedNotificationCenter.default().post(
                name: Notification.Name(rawValue: "me.melchor9000.iTunes-Scrobbler.killLauncher"),
                object: Bundle.main.bundleIdentifier!
            )
        }

        if updater != nil {
            menu.autoUpdate = DBFacade.shared.autoUpdate
            if menu.autoUpdate! {
                updater!.start()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        menu.showIfNeeded()
        return true
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

    @objc func deletedRowInTable(_ notification: NSNotification) {
        updateScrobbleCacheCount()
    }

    // MARK: - iTunes Service Delegate

    func iTunesStateChanged(_ state: iTunesState) {
        log(state)
        if state == .inactive {
            menu.setInactiveState()
        }
    }

    func iTunesSongChanged(_ metadata: SongMetadata) {
        log(metadata)
        menu.setSongState(metadata, scrobbled: false)
        if menu.loggedIn && DBFacade.shared.sendScrobbles {
            lastfm.updateNowPlaying(metadata) { (corrections, statusCode) in }
        }
    }

    func iTunesScrobbleTime(_ metadata: SongMetadata, _ time: Date) {
        menu.setSongState(metadata, scrobbled: true)

        //Save always the scrobblings, just in case
        if metadata.trackTitle != nil && metadata.artistName != nil {
            if let lastScrobbling = DBFacade.shared.getLastScrobble() {
                let m2 = SongMetadata(managedObject: lastScrobbling)
                let tm2 = lastScrobbling.value(forKey: "timestamp") as! Date
                let diff = time.timeIntervalSinceReferenceDate - tm2.timeIntervalSinceReferenceDate
                if m2 == metadata && diff < metadata.duration {
                    log("Same song scrobbling in less than duration time, not doing it")
                    return
                }
            } else {
                let last = DBFacade.shared.lastScrobble
                let diff = time.timeIntervalSince1970 - last.0.timeIntervalSince1970
                if metadata.hash == last.1 && diff < metadata.duration {
                    log("Same song scrobbling in less than duration time 2, not doing it")
                    return
                }
            }

            do {
                try DBFacade.shared.saveScrobble(metadata, time: time)
                DistributedNotificationCenter.default().postNotificationName(
                    AppDelegate.addedScrobbling,
                    object: nil,
                    userInfo: nil,
                    options: .deliverImmediately
                )
                DBFacade.shared.lastScrobble = (time, metadata.hash)
            } catch let error as NSError {
                log("Could not save scrobbling in cache \(error), \(error.userInfo)")
                NSApplication.shared.presentError(error)
            }
            updateScrobbleCacheCount()
            scrobbleNow()
        }
    }

    func scrobbleNow(_ force: Bool = false) {
        if account != nil && (DBFacade.shared.sendScrobbles || force) {
            if let scrobbles = DBFacade.shared.getScrobbles(limit: 50) {
                lastfm.scrobble(scrobbles) { (scrobbled) in
                    try! DBFacade.shared.removeScrobbles(scrobbles)
                    //TODO Do something about unscrobbled songs
                    DistributedNotificationCenter.default().postNotificationName(
                        AppDelegate.sentScrobblings,
                        object: nil,
                        userInfo: nil,
                        options: .deliverImmediately
                    )
                    self.updateScrobbleCacheCount()
                    if scrobbles.count == 50 {
                        self.scrobbleNow()
                    }
                }
            }
        }
    }

    private func updateScrobbleCacheCount() {
        if let count = DBFacade.shared.getScrobblesCount() {
            menu.updateScrobbleCacheCount(count)
        }
    }

    // MARK: - Core Data stack

    lazy var persistentContainer: NSPersistentContainer = {
        /*
         The persistent container for the application. This implementation
         creates and returns a container, having loaded the store for the
         application to it. This property is optional since there are legitimate
         error conditions that could cause the creation of the store to fail.
        */
        let container = NSPersistentContainer(name: "iTunes_Scrobbler")
        container.loadPersistentStores(completionHandler: { (storeDescription, error) in
            if let error = error {
                // Replace this implementation with code to handle the error appropriately.
                // fatalError() causes the application to generate a crash log and terminate. You should not use this function in a shipping application, although it may be useful during development.
                 
                /*
                 Typical reasons for an error here include:
                 * The parent directory does not exist, cannot be created, or disallows writing.
                 * The persistent store is not accessible, due to permissions or data protection when the device is locked.
                 * The device is out of space.
                 * The store could not be migrated to the current model version.
                 Check the error message to determine what the actual problem was.
                 */
                fatalError("Unresolved error \(error)")
            }
        })
        return container
    }()

    // MARK: - Core Data Saving and Undo support

    @IBAction func saveAction(_ sender: AnyObject?) {
        // Performs the save action for the application, which is to send the save: message to the application's managed object context. Any encountered errors are presented to the user.
        let context = persistentContainer.viewContext

        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing before saving")
        }
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                // Customize this code block to include application-specific recovery steps.
                let nserror = error as NSError
                NSApplication.shared.presentError(nserror)
            }
        }
    }

    func windowWillReturnUndoManager(window: NSWindow) -> UndoManager? {
        // Returns the NSUndoManager for the application. In this case, the manager returned is that of the managed object context for the application.
        return persistentContainer.viewContext.undoManager
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Save changes in the application's managed object context before the application terminates.
        let context = persistentContainer.viewContext
        
        if !context.commitEditing() {
            NSLog("\(NSStringFromClass(type(of: self))) unable to commit editing to terminate")
            return .terminateCancel
        }
        
        if !context.hasChanges {
            return .terminateNow
        }
        
        do {
            try context.save()
        } catch {
            let nserror = error as NSError

            // Customize this code block to include application-specific recovery steps.
            let result = sender.presentError(nserror)
            if (result) {
                return .terminateCancel
            }
            
            let question = NSLocalizedString("Could not save changes while quitting. Quit anyway?", comment: "Quit without saves error question message")
            let info = NSLocalizedString("Quitting now will lose any changes you have made since the last successful save", comment: "Quit without saves error question info");
            let quitButton = NSLocalizedString("Quit anyway", comment: "Quit anyway button title")
            let cancelButton = NSLocalizedString("Cancel", comment: "Cancel button title")
            let alert = NSAlert()
            alert.messageText = question
            alert.informativeText = info
            alert.addButton(withTitle: quitButton)
            alert.addButton(withTitle: cancelButton)
            
            let answer = alert.runModal()
            if answer == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }
        // If we got here, it is time to quit.
        return .terminateNow
    }

}

