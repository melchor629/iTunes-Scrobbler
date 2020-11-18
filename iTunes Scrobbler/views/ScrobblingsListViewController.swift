//
//  ScrobblingsListViewController.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 10/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

class ScrobblingsListViewController: NSViewController, NSTableViewDelegate, NSTableViewDataSource {

    @IBOutlet weak var titleLabel: NSTextField!
    @IBOutlet weak var table: NSTableView!

    public static let deletedScrobbling = NSNotification.Name(rawValue: "me.melchor9000.iTunes-Scrobbler.ScrobblingsListViewController.deletedScrobbling")

    private var list: [NSManagedObject] = []

    override func viewDidLoad() {
        super.viewDidLoad()
        loadData()

        titleLabel.stringValue = NSLocalizedString("CACHED_SCROBBLINGS", comment: "ScrobblingListView: Title")

        if NSAppKitVersion.current <= NSAppKitVersion.macOS10_13_4 {
            let vibrant = VibrantDarkView(frame: view.bounds)
            vibrant.autoresizingMask = NSView.AutoresizingMask.width.union(.height)
            vibrant.blendingMode = .behindWindow
            view.addSubview(vibrant, positioned: .below, relativeTo: nil)
        }

        if #available(OSX 10.13, *) {
            table.usesAutomaticRowHeights = true
        }

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(ScrobblingsListViewController.addedScrobbling),
            name: AppDelegate.addedScrobbling,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(ScrobblingsListViewController.scrobbled),
            name: AppDelegate.sentScrobblings,
            object: nil
        )
    }

    override func viewWillDisappear() {
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: AppDelegate.addedScrobbling,
            object: nil
        )
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: AppDelegate.sentScrobblings,
            object: nil
        )
    }

    @IBAction func onMenuRemoveClicked(_ sender: Any) {
        remove(row: table.clickedRow)
    }

    @objc func addedScrobbling(_ notification: Notification) {
        self.list.append(DBFacade.shared.getLastScrobble()!)
        table.reloadData()
    }

    @objc func scrobbled(_ notification: Notification) {
        loadData()
    }

    private func loadData() {
        self.list = DBFacade.shared.getScrobbles()!
        table.reloadData()
    }

    public func numberOfRows(in tableView: NSTableView) -> Int {
        return list.count
    }

    public func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MainCell"), owner: self) as! ScrobblingListItemView
        let item = list[row]

        view.trackAndArtistLabel.stringValue = "\(item.value(forKey: "track")! as! String) - \(item.value(forKey: "artist")! as! String)"
        if let album = item.value(forKey: "album") as? String {
            view.albumLabel.stringValue = album
        } else {
            view.albumLabel.stringValue = ""
        }

        let date = item.value(forKey: "timestamp") as! Date
        view.whenLabel.stringValue = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)

        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return true
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        return [ NSTableViewRowAction(style: .destructive, title: "Remove", handler: { (action, row) in
            self.remove(row: row)
        }) ]
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 54
    }

    private func remove(row: Int) {
        table.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade)
        try! DBFacade.shared.removeScrobbles([list[row]])
        list.remove(at: row)
        DistributedNotificationCenter.default().postNotificationName(
            ScrobblingsListViewController.deletedScrobbling,
            object: nil,
            userInfo: nil,
            options: .deliverImmediately
        )
    }

}

class ScrobblingListItemView: NSTableCellView {

    @IBOutlet weak var trackAndArtistLabel: NSTextField!
    @IBOutlet weak var albumLabel: NSTextField!
    @IBOutlet weak var whenLabel: NSTextField!

}
