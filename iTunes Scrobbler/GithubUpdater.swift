//
//  GithubUpdater.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 29/4/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Foundation

fileprivate enum GithubUpdaterError: Error {
    case InvalidJson(path: String)
    case InvalidRelease(path: String)
}

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
        return a.major < b.major
            || (a.major == b.major && a.minor < b.minor)
    } else {
        return a.major < b.major
            || (a.major == b.major && a.minor < b.minor)
            || (a.major == b.major && a.minor == b.minor && a.patch! < b.patch!)
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

    init(_ json: [String: Any]) throws {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = .withInternetDateTime
        if let publishedAtString = json["publishedAt"] as? String {
            guard let publishedAt = formatter.date(from: publishedAtString) else {
                throw GithubUpdaterError.InvalidRelease(path: "publishedAt")
            }

            self.publishedAt = publishedAt
        } else {
            publishedAt = nil
        }

        guard let description = json["description"] as? String else {
            throw GithubUpdaterError.InvalidRelease(path: "description")
        }
        guard let name = json["name"] as? String else {
            throw GithubUpdaterError.InvalidRelease(path: "name")
        }
        guard let isDraft = json["isDraft"] as? Bool else {
            throw GithubUpdaterError.InvalidRelease(path: "isDraft")
        }
        guard let isPrerelease = json["isPrerelease"] as? Bool else {
            throw GithubUpdaterError.InvalidRelease(path: "isPrerelease")
        }

        self.description = description
        self.name = name
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        if let tagDict = json["tag"] as? [String: String] {
            guard let name = tagDict["name"] else {
                throw GithubUpdaterError.InvalidRelease(path: "tag.name")
            }
            tag = Version(name)
        } else {
            tag = nil
        }

        guard let releaseAssets = json["releaseAssets"] as? [String: [[String: [String: String]]]] else {
            throw GithubUpdaterError.InvalidRelease(path: "releaseAssets")
        }
        guard let releaseAssetsEdges = releaseAssets["edges"] else {
            throw GithubUpdaterError.InvalidRelease(path: "releaseAssets.edges")
        }
        assets = try releaseAssetsEdges.map {
            let i = releaseAssetsEdges.firstIndex(of: $0)!.distance(to: releaseAssetsEdges.startIndex)
            guard let node = $0["node"] else {
                throw GithubUpdaterError.InvalidRelease(path: "releaseAssets.edges[\(i)].node")
            }
            return try ReleaseAsset(node, i)
        }
    }
}

/// Model of a download asset for a release.
class ReleaseAsset {
    let name: String
    let url: URL

    init(_ json: [String: String], _ index: Int) throws {
        guard let name = json["name"] else {
            throw GithubUpdaterError.InvalidRelease(path: "releaseAssets.edges[\(index)].node.name")
        }
        guard let downloadUrl = json["downloadUrl"] else {
            throw GithubUpdaterError.InvalidRelease(path: "releaseAssets.edges[\(index)].node.downloadUrl")
        }

        self.name = name
        url = URL(string: downloadUrl)!
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
    private let log = Logger(category: "GithubUpdater")

    init() {
        self.token = Tokens.githubToken
        self.appVersion = Version(Bundle.main.infoDictionary!["CFBundleShortVersionString"]! as! String)
        self.log.info("App is in version \(self.appVersion.debugDescription)")
    }

    /// Starts the background task of checking for updates (once per hour).
    func start() {
        backgroundTask = DispatchWorkItem {
            self.log.info("Checking for updates...")
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
            self.log.notice("Extracting \(zip.path) to \(appDir.path) when the scrobbler has closed")
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
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        URLSession.shared.dataTask(with: request) { (data, response, error) in
            if error != nil {
                self.log.error("Could not check for updates: \(error!)")
            }

            let res = response as? HTTPURLResponse
            let statusCode = (res?.statusCode ?? -1)
            if statusCode != 200 {
                self.log.warning("Check for updates response is not 200 OK: \(statusCode)")
                self.log.debug("Response body: \(String(data: data!, encoding: .utf8) ?? "<>")")
                return
            }

            do {
                guard let json = try JSONSerialization.jsonObject(with: data!, options: []) as? [String: Any] else {
                    throw GithubUpdaterError.InvalidJson(path: "")
                }
                guard let data = json["data"] as? [String: Any] else {
                    throw GithubUpdaterError.InvalidJson(path: "data")
                }
                guard let repository = data["repository"] as? [String: Any] else {
                    throw GithubUpdaterError.InvalidJson(path: "data.repository")
                }
                guard let releases = repository["releases"] as? [String: Any] else {
                    throw GithubUpdaterError.InvalidJson(path: "data.repository.releases")
                }
                guard let edge = releases["edges"] as? [[String: [String: Any]]] else {
                    throw GithubUpdaterError.InvalidJson(path: "data.repository.releases.edges")
                }

                let _releases = try edge.map { (e: [String: [String: Any]]) throws -> Release? in
                    do {
                        return try Release(e["node"]!)
                    } catch let GithubUpdaterError.InvalidRelease(path) {
                        self.log.warning("Invalid release ([data.repository.releases.edges[?].node.\(path)): \(e["node"]!)")
                    }
                    return nil
                }
                self.doSomethingWithTheReleases(_releases.filter { $0 != nil }.map { $0! })
            } catch let GithubUpdaterError.InvalidJson(path) {
                self.log.error("Invalid json structure in path \(path)")
                self.log.debug("Response body: \(String(data: data!, encoding: .utf8) ?? "<>")")
            } catch {
                self.log.error("Cannot parse check for update response: \(error)")
                self.log.debug("Response body: \(String(data: data!, encoding: .utf8) ?? "<>")")
                self.log.debug("Content Type: \(res?.allHeaderFields["Content-Type"] ?? "unknown")")
            }
        }.resume()
    }

    /// Does something with the result.
    private func doSomethingWithTheReleases(_ releases: [Release]) {
        if let release = releases.filter({ !$0.isDraft }).first {
            if !pendingToRestart && self.appVersion < release.tag! {
                self.log.notice("NEW VERSION \(release.tag!.debugDescription)")
                pendingToRestart = true
                let asset = release.assets.filter { $0.name.contains(".zip") }.first
                if let asset = asset {
                    let assetUrl = FileManager.default.urls(for: .applicationSupportDirectory,
                                                            in: .userDomainMask)[0]
                        .appendingPathComponent(asset.name)
                    self.log.info("Downloading \(asset.url) to \(assetUrl.path)")
                    URLSession.shared.dataTask(with: asset.url) { (data, _, _) in
                        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
                        if FileManager.default.createFile(atPath: assetUrl.path, contents: data, attributes: nil) {
                            self.log.info("App ready to be updated :)")
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
                self.log.info("No update found")
            }
        }
    }

}
