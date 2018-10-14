//
//  GithubUpdater.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 29/4/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Foundation

/// Version struct for "x.x.x" strings.
class Version {
    let major: Int
    let minor: Int
    let patch: Int?

    init(_ versionString: String) {
        let versionSub: String.SubSequence;
        if versionString.starts(with: "v") {
            versionSub = versionString[versionString.index(after: versionString.startIndex)...]
        } else {
            versionSub = versionString[versionString.startIndex...]
        }

        let versionSplit = versionSub.split(separator: ".")
        major = Int(versionSplit[0])!
        if versionSplit.count > 1 {
            minor = Int(versionSplit[1])!
        } else {
            minor = 0
        }
        if versionSplit.count > 2 {
            patch = Int(versionSplit[2])
        } else {
            patch = nil
        }
    }

    var debugDescription: String {
        get { return patch != nil ? "\(major).\(minor).\(patch!)" : "\(major).\(minor)" }
    }
}

func <(a: Version, b: Version) -> Bool {
    if(a.patch == nil || b.patch == nil) {
        return a.major < b.major || a.minor < b.minor
    } else {
        return a.major < b.major || a.minor < b.minor || a.patch! < b.patch!
    }
}

/// Model of a release.
class Release {
    let publishedAt: Date?
    let description: String
    let name: String
    let isDraft: Bool
    let isPrerelease: Bool
    let tag: Version?
    let assets: [ReleaseAsset]

    init(_ json: [String: Any]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        if let publishedAtString = json["publishedAt"]! as? String {
            publishedAt = formatter.date(from: publishedAtString)!
        } else {
            publishedAt = nil
        }
        description = json["description"]! as! String
        name = json["name"]! as! String
        isDraft = json["isDraft"]! as! Bool
        isPrerelease = json["isPrerelease"]! as! Bool
        if let tagDict = json["tag"]! as? [String: String] {
            tag = Version(tagDict["name"]!)
        } else {
            tag = nil
        }

        let releaseAssets = (json["releaseAssets"]! as! [String: [[String: [String: String]]]])["edges"]!
        assets = releaseAssets.map { ReleaseAsset($0["node"]!) }
    }
}

/// Model of a download asset for a release.
class ReleaseAsset {
    let name: String
    let url: URL

    init(_ json: [String: String]) {
        name = json["name"]!
        url = URL(string: json["downloadUrl"]!)!
    }
}

/// Updater that grabs the information from a GitHub repository and updates when needed.
class GithubUpdater {
    private static let GRAPHQL_URL = URL(string: "https://api.github.com/graphql")!
    private let token: String
    private let appVersion: Version
    private var backgroundTask: DispatchWorkItem?
    private var pendingToRestart = false
    private var pendingInfo: (URL, URL)? = nil

    init() {
        self.token = Tokens.githubToken
        self.appVersion = Version(Bundle.main.infoDictionary!["CFBundleShortVersionString"]! as! String)
    }

    /// Starts the background task of checking for updates (once per hour).
    func start() {
        backgroundTask = DispatchWorkItem {
            NSLog("Checking for updates...")
            self.getInfo()
            if self.backgroundTask != nil {
                DispatchQueue.main.asyncAfter(deadline: DispatchTime.now() + DispatchTimeInterval.seconds(3600),
                                              execute: self.backgroundTask!)
            }
        }
        DispatchQueue.main.async(execute: backgroundTask!)
    }

    /// Stops the background task from `start()`.
    func stop() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    /// If there's an update to apply, runs it in a wonderful shell script
    func applyUpdate() {
        if let (zip, appDir) = pendingInfo {
            NSLog("Extracting \(zip.path) to \(appDir.path) when the scrobbler has closed")
            let shellScript = [
                "sleep 1",
                "while pgrep 'iTunesScrobbler'",
                "do sleep 1",
                "done",
                "unzip -o '\(zip.path)' -d '\(appDir.path)'",
                "rm '\(zip.path)'"
            ].joined(separator: "; ")
            let task = Process()
            task.launchPath = "/usr/bin/env"
            task.arguments = ["bash", "-c", shellScript]
            task.launch()
        }
    }

    /// Gets the information from GitHub. Does some interesting parsing stuff.
    private func getInfo() {
        var request = URLRequest(url: GithubUpdater.GRAPHQL_URL)
        request.httpMethod = "POST"
        request.httpBody = """
        {
            "query": "query { repository(owner:\\"melchor629\\", name:\\"iTunes-Scrobbler\\") { releases(first:20, orderBy: { field: CREATED_AT, direction: DESC }) { edges { node { publishedAt description name isDraft isPrerelease tag { name } releaseAssets(first:10) { edges { node { downloadUrl name } } } } } } } }"
        }
        """.data(using: .utf8)
        request.addValue("bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if error == nil {
                if (response as! HTTPURLResponse).statusCode == 200 {
                    let json = try! JSONSerialization.jsonObject(with: data!, options: []) as! [String: Any]
                    let data = json["data"] as! [String: Any]
                    let repository = data["repository"] as! [String: Any]
                    let releases = repository["releases"] as! [String: Any]
                    let edge = releases["edges"] as! [[String: [String: Any]]]
                    let _releases = edge.map { Release($0["node"]!) }
                    self.doSomethingWithTheReleases(_releases)
                }
            }
        }.resume()
    }

    /// Does something with the result.
    private func doSomethingWithTheReleases(_ releases: [Release]) {
        if let release = releases.filter({ !$0.isDraft }).first {
            if !pendingToRestart && self.appVersion < release.tag! {
                NSLog("NEW VERSION \(release.tag!.debugDescription)")
                pendingToRestart = true
                let asset = release.assets.filter { $0.name.contains(".zip") }.first
                if let asset = asset {
                    let assetUrl = FileManager.default.urls(for: .applicationSupportDirectory,
                                                            in: .userDomainMask)[0]
                        .appendingPathComponent(asset.name)
                    NSLog("Downloading \(asset.url) to \(assetUrl.path)")
                    URLSession.shared.dataTask(with: asset.url) { (data, _, _) in
                        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
                        if FileManager.default.createFile(atPath: assetUrl.path, contents: data, attributes: nil) {
                            NSLog("App ready to be updated :)")
                            self.pendingInfo = (assetUrl, appDir)
                            let notif = NSUserNotification()
                            notif.title = NSLocalizedString("UPDATE_INSTALLED_TITLE",
                                                            comment: "Notification: Shows when an update has been applied")
                            notif.informativeText = NSLocalizedString("UPDATE_INSTALLED_BODY",
                                                                      comment: "Notification: Shows when an update has been applied")
                            NSUserNotificationCenter.default.deliver(notif)
                        }
                    }.resume()
                }
            } else if !pendingToRestart {
                NSLog("No update found")
            }
        }
    }

}
