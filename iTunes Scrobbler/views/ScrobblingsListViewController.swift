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

        let vibrant = VibrantDarkView(frame: view.bounds)
        vibrant.autoresizingMask = NSView.AutoresizingMask.width.union(.height)
        vibrant.blendingMode = .behindWindow
        view.addSubview(vibrant, positioned: .below, relativeTo: nil)

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
        let view = tableView.makeView(withIdentifier: NSUserInterfaceItemIdentifier(rawValue: "MainCell"), owner: self) as? ScrobblingListItemView
        let item = list[row]
        view?.trackAndArtistLabel.stringValue = "\(item.value(forKey: "track")! as! String) - \(item.value(forKey: "artist")! as! String)"
        if let album = item.value(forKey: "album") as? String { view?.albumLabel.stringValue = album } else { view?.albumLabel.stringValue = "" }
        let date = item.value(forKey: "timestamp") as! Date
        view?.whenLabel.stringValue = DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
        return view
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        return false
    }

    func tableView(_ tableView: NSTableView, rowActionsForRow row: Int, edge: NSTableView.RowActionEdge) -> [NSTableViewRowAction] {
        return [ NSTableViewRowAction(style: .destructive, title: "Remove", handler: { (action, row) in
            self.table.removeRows(at: IndexSet(integer: row), withAnimation: .effectFade)
            try! DBFacade.shared.removeScrobbles([ self.list[row] ])
            self.list.remove(at: row)
            DistributedNotificationCenter.default().postNotificationName(
                ScrobblingsListViewController.deletedScrobbling,
                object: nil,
                userInfo: nil,
                options: .deliverImmediately
            )
        }) ]
    }

}

class ScrobblingListItemView: NSTableCellView {

    @IBOutlet weak var trackAndArtistLabel: NSTextField!
    @IBOutlet weak var albumLabel: NSTextField!
    @IBOutlet weak var whenLabel: NSTextField!
    @IBOutlet weak var nothingView: NothingView!

}

class NothingView: NSView {

    public override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let shape = NSBezierPath(rect: bounds)
        let gradient = NSGradient(colorsAndLocations:
            (NSColor(red: 1, green: 1, blue: 1, alpha: 0), 0),
            (NSColor(red: 1, green: 1, blue: 1, alpha: 1), 10 / bounds.size.width)
        )
        gradient?.draw(in: shape, angle: 0)
    }

}
