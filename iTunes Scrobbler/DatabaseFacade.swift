//
//  DatabaseFacade.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 11/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

/**
 Simplifies the accesses to the database through a shared instance.
 */
class DBFacade {

    /// Shared instance of the facade.
    internal static let shared = DBFacade(context: (NSApp.delegate! as! AppDelegate).persistentContainer.viewContext)

    private let context: NSManagedObjectContext

    private init(context: NSManagedObjectContext) {
        self.context = context
    }

    /// Gets the username, user token and the NSManagedObject if there's a user authenticated.
    internal func getAccount() -> (String, String, NSManagedObject)? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Account")
        let accountOrNot = try? context.fetch(fetchRequest)
        if accountOrNot != nil && accountOrNot!.count != 0 {
            let account = accountOrNot![0]
            return (account.value(forKeyPath: "username") as! String, account.value(forKeyPath: "token") as! String, account)
        } else {
            return nil
        }
    }

    /// Stores an account to the database.
    /// - Parameters:
    ///     - username: Username of the account.
    ///     - token: User token for his/her session.
    /// - Returns: The stored NSManagedObject.
    internal func addAccount(_ username: String, _ token: String) throws -> NSManagedObject {
        let entity = NSEntityDescription.entity(forEntityName: "Account", in: context)!
        let scrobbling = NSManagedObject(entity: entity, insertInto: context)
        scrobbling.setValue(token, forKey: "token")
        scrobbling.setValue(username, forKey: "username")
        try context.save()
        return scrobbling
    }

    /// Deletes the stored account (aka log out). Also removes cached scrobbles.
    /// - Parameter account: The NSManagedObject of the account.
    internal func deleteAccount(_ account: NSManagedObject) throws {
        context.delete(account)
        try context.save()
    }

    /// Gets the number of scrobbles in cache, if there's a user authenticated.
    /// - Returns: The number of scrobbles in cache, or nil if there's no user authenticated.
    internal func getScrobblesCount() -> Int? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Scrobble")
        return try? context.count(for: fetchRequest)
    }

    /// Gets a batch of scrobbles in cache, with an optional limit.
    /// - Parameters:
    ///     - limit: Number of items to fetch (all by default).
    ///     - ascendingOrder: Returns the list ordered from older to newer if true.
    /// - Returns: A list of items in cache, or nil if an error occurred.
    internal func getScrobbles(limit: Int? = nil, ascendingOrder: Bool = true) -> [NSManagedObject]? {
        let fetchRequest = NSFetchRequest<NSManagedObject>(entityName: "Scrobble")
        if let limit = limit { fetchRequest.fetchLimit = limit }
        fetchRequest.sortDescriptors = [ NSSortDescriptor(key: "timestamp", ascending: ascendingOrder) ]
        return try? context.fetch(fetchRequest)
    }

    /// Removes a batch of scrobbles.
    internal func removeScrobbles(_ objects: [NSManagedObject]) throws {
        objects.forEach { context.delete($0) }
        try context.save()
    }

    /// Saves the scrobble into the cache.
    /// - Parameters:
    ///     - metadata: Song metadata to store.
    ///     - time: Time when the song started to play.
    internal func saveScrobble(_ metadata: SongMetadata, time: Date) throws {
        let entity = NSEntityDescription.entity(forEntityName: "Scrobble", in: context)!
        let scrobbling = NSManagedObject(entity: entity, insertInto: context)
        scrobbling.setValue(metadata.albumName, forKey: "album")
        scrobbling.setValue(metadata.albumArtistName, forKey: "albumArtist")
        scrobbling.setValue(metadata.artistName, forKey: "artist")
        scrobbling.setValue(metadata.duration, forKey: "duration")
        scrobbling.setValue(time, forKey: "timestamp")
        scrobbling.setValue(metadata.trackTitle, forKey: "track")
        scrobbling.setValue(metadata.playedCount, forKey: "playedCount")
        try context.save()
    }

    /// Gets the last scrobble in cache, if there's one.
    internal func getLastScrobble() -> NSManagedObject? {
        if let last = getScrobbles(limit: 1, ascendingOrder: false) {
            return last.count != 0 ? last[0] : nil
        } else {
            return nil
        }
    }

    /// Easy getter for settings.
    private func getter(_ propertyName: String, _ defaultValue: String) -> String {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Setting")
        request.predicate = NSPredicate(fromMetadataQueryString: "key = \(propertyName)")
        let res = try! context.fetch(request)
        if res.count == 0 {
            let entity = NSEntityDescription.entity(forEntityName: "Setting", in: context)!
            let setting = NSManagedObject(entity: entity, insertInto: context)
            setting.setValue(defaultValue, forKey: "value")
            setting.setValue(propertyName, forKey: "key")
            try! context.save()
            return defaultValue
        } else {
            return res[0].value(forKey: "value")! as! String
        }
    }

    /// Easy setter for settings.
    private func setter(_ propertyName: String, _ newValue: String) {
        let request = NSFetchRequest<NSManagedObject>(entityName: "Setting")
        request.predicate = NSPredicate(fromMetadataQueryString: "key = \(propertyName)")
        let res = try! context.fetch(request)
        if res.count == 0 {
            let entity = NSEntityDescription.entity(forEntityName: "Setting", in: context)!
            let setting = NSManagedObject(entity: entity, insertInto: context)
            setting.setValue(newValue, forKey: "value")
            setting.setValue(propertyName, forKey: "key")
        } else {
            res[0].setValue(newValue, forKey: "value")
        }
        try! context.save()
    }

    /// Setting for send scrobbles at the moment (true) or store them in the cache (false).
    internal var sendScrobbles: Bool {
        get {
            return Bool(self.getter("SEND_SCROBBLES", "true"))!
        }
        set {
            self.setter("SEND_SCROBBLES", "\(newValue)")
        }
    }

    /// Setting for openning the scrobbler when login (true) or not (false).
    internal var openAtLogin: Bool {
        get {
            return Bool(getter("OPEN_AT_LOGIN", "false"))!
        }
        set {
            setter("OPEN_AT_LOGIN", "\(newValue)")
        }
    }

    /// Setting (is not in fact) to store when was the last scrobble and a hash of
    /// the metadata struct.
    internal var lastScrobble: (Date, Int) {
        get {
            let split = getter("LAST_SCROBBLE_TIME", "0;0").split(separator: ";")
            return (Date(timeIntervalSince1970: Double(split[0])!), Int(split[1])!)
        }
        set {
            setter("LAST_SCROBBLE_TIME", "\(newValue.0.timeIntervalSince1970);\(newValue.1)")
        }
    }

    /// Setting to enable autoupdate (true) or disable it (false).
    internal var autoUpdate: Bool {
        get {
            return Bool(getter("AUTO_UPDATE", "false"))!
        }
        set {
            setter("AUTO_UPDATE", "\(newValue)")
        }
    }

}
