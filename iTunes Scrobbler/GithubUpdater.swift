//
//  GithubUpdater.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 29/4/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Foundation
import Zip

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
}

func <(a: Version, b: Version) -> Bool {
    if(a.patch == nil || b.patch == nil) {
        return a.major < b.major || a.minor < b.minor
    } else {
        return a.major < b.major || a.minor < b.minor || a.patch! < b.patch!
    }
}

class Release {
    let publishedAt: Date
    let description: String
    let name: String
    let isDraft: Bool
    let isPrerelease: Bool
    let tag: Version
    let assets: [ReleaseAsset]

    init(_ json: [String: Any]) {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        publishedAt = formatter.date(from: json["publishedAt"]! as! String)!
        description = json["description"]! as! String
        name = json["name"]! as! String
        isDraft = json["isDraft"]! as! Bool
        isPrerelease = json["isPrerelease"]! as! Bool
        tag = Version((json["tag"]! as! [String: String])["name"]!)

        let releaseAssets = (json["releaseAssets"]! as! [String: [[String: [String: String]]]])["edges"]!
        assets = releaseAssets.map { ReleaseAsset($0["node"]!) }
    }
}

class ReleaseAsset {
    let name: String
    let url: URL

    init(_ json: [String: String]) {
        name = json["name"]!
        url = URL(string: json["downloadUrl"]!)!
    }
}

class GithubUpdater {
    private static let GRAPHQL_URL = URL(string: "https://api.github.com/graphql")!
    private let token: String
    private let appVersion: Version
    private var backgroundTask: DispatchWorkItem?
    private var pendingToRestart = false

    init() {
        self.token = Tokens.githubToken
        self.appVersion = Version(Bundle.main.infoDictionary!["CFBundleShortVersionString"]! as! String)
    }

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

    func stop() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

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

    private func doSomethingWithTheReleases(_ releases: [Release]) {
        if let release = releases.first {
            if !pendingToRestart && self.appVersion < release.tag {
                NSLog("NEW VERSION \(release.tag)")
                pendingToRestart = true
                let asset = release.assets.filter { $0.name.contains(".zip") }.first
                if let asset = asset {
                    URLSession.shared.dataTask(with: asset.url) { (data, _, _) in
                        let appDir = Bundle.main.bundleURL.deletingLastPathComponent()
                        if FileManager.default.createFile(atPath: "/tmp/\(asset.name)", contents: data, attributes: nil) {
                            try? Zip.unzipFile(URL(string: "/tmp/\(asset.name)")!,
                                               destination: appDir,
                                               overwrite: true,
                                               password: nil)
                        }
                    }.resume()
                }
            } else if !pendingToRestart {
                NSLog("No update found")
            }
        }
    }

}
