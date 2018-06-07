//
//  Lastfm.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 7/1/18.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Cocoa

enum LastfmError: Error {
    case CredentialsFileNotFound
    case CredentialsFileInvalid(String)
}

fileprivate extension String {
    fileprivate func urlEncode() -> String {
        return self.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)!.replacingOccurrences(of: "&", with: "%26")
    }
}

// https://www.last.fm/api/desktopauth
class Lastfm {

    private let apiKey: String
    private let secret: String
    private let baseUrl: String = "https://ws.audioscrobbler.com/2.0/"
    private var userToken: String?
    private var authToken: String?

    internal var token: String? {
        get { return self.userToken }
        set { self.userToken = newValue }
    }

    init() {
        self.apiKey = Tokens.lastfmApiKey
        self.secret = Tokens.lastfmSecret
    }

    internal func startAutentication() {
        makeRequest(["method":"auth.getToken"]) { (json, statusCode) in
            if statusCode == 200 {
                let res = json as! [String: Any]
                self.authToken = (res["token"] as! String)
                let url = "http://www.last.fm/api/auth/?api_key=\(self.apiKey)&token=\(self.authToken!)"
                NSWorkspace.shared.open(URL(string: url)!)
            }
        }
    }

    internal func endAuthentication(callback: @escaping (String?, String?) -> Void) {
        if let authToken = authToken {
            makeRequest(["method": "auth.getSession", "token": authToken]) { (json, statusCode) in
                if statusCode == 200 {
                    let session = (json as! [String: [String: Any]])["session"]!
                    self.userToken = (session["key"]! as! String)
                    DispatchQueue.main.async { callback(self.userToken, session["name"]! as? String) }
                } else {
                    DispatchQueue.main.async { callback(nil, nil) }
                }
            }
        } else {
            DispatchQueue.main.async { callback(nil, nil) }
        }
    }

    internal func updateNowPlaying(_ metadata: SongMetadata, callback: @escaping ([String: Any], Int) -> Void) {
        if metadata.trackTitle != nil && metadata.artistName != nil {
            var params: [String: String] = [:]
            params["track"] = metadata.trackTitle!
            params["artist"] = metadata.artistName!
            if let albumArtist = metadata.albumArtistName { params["albumArtist"] = albumArtist }
            if let album = metadata.albumName { params["album"] = album }
            params["duration"] = String(Int(metadata.duration.rounded()))
            params["method"] = "track.updateNowPlaying"
            makeRequest(post: params) { (json, statusCode) in
                callback(json as! [String: Any], statusCode)
            }
        }
    }

    func scrobble(_ m: [NSManagedObject], callback: @escaping ([NSManagedObject]) -> Void) {
        var params: [String: [String?]] = [
            "artist": [],
            "track": [],
            "timestamp": [],
            "album": [],
            "albumArtist": [],
            "duration": []
        ]

        for scrobble in m {
            params["track"]!.append(scrobble.value(forKeyPath: "track") as? String)
            params["artist"]!.append(scrobble.value(forKeyPath: "artist") as? String)
            params["album"]!.append(scrobble.value(forKeyPath: "album") as? String)
            params["albumArtist"]!.append(scrobble.value(forKeyPath: "albumArtist") as? String)
            if let duration = scrobble.value(forKeyPath: "duration") as? Double {
                params["duration"]!.append(String(Int(duration.rounded())))
            } else {
                params["duration"]!.append(nil)
            }
            if let timestamp = scrobble.value(forKeyPath: "timestamp") as? Date {
                params["timestamp"]!.append(String(Int(timestamp.timeIntervalSince1970)))
            }
        }

        var params2: [String: Any] = params
        params2["method"] = "track.scrobble"
        makeRequest(post: params2) { (json, statusCode) in
            if statusCode == 200 {
                var scrobbled: [NSManagedObject] = []
                let scr = ((json as! [String: Any])["scrobbles"]! as! [String: Any])["scrobble"]!
                var scrobbles = scr as? [[String: Any]]
                if scrobbles == nil {
                    scrobbles = [ scr as! [String: Any] ]
                }
                var pos = 0
                for scrobble in scrobbles! {
                    let info = (scrobble["ignoredMessage"] as! [String: Any])["code"]! as! NSString
                    if info == "0" {
                        scrobbled.append(m[pos])
                    }
                    pos += 1
                }
                DispatchQueue.main.async { callback(scrobbled) }
            } else {
                DispatchQueue.main.async { callback([]) }
            }
        }
    }

    private func makeRequest(_ params: [String: String], requiresSignature: Bool = true, callback: @escaping (Any?, Int) -> Void) {
        var mParams = params
        mParams["api_key"] = apiKey
        if let userToken = self.userToken {
            mParams["sk"] = userToken
        }
        if requiresSignature {
            mParams["api_sig"] = getSignature(mParams)
        }
        mParams["format"] = "json"

        let query = mParams.map { "\($0.key)=\($0.value.urlEncode())" }.joined(separator: "&")

        let task = URLSession.shared.dataTask(with: URL(string: "\(baseUrl)?\(query)")!) { (data, response, error) in
            if error != nil {
                log(error!.localizedDescription)
                //In case of error, won't do anything. The app will retry after to do the same request
            } else {
                let httpResponse = response! as! HTTPURLResponse
                callback(try! JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions(rawValue: 0)), httpResponse.statusCode)
            }
        }

        task.resume()
    }

    private func makeRequest(post body: [String: Any], callback: @escaping (Any?, Int) -> Void) {
        var mParams = body
        mParams["api_key"] = apiKey
        if let userToken = self.userToken {
            mParams["sk"] = userToken
        }
        var r = getSignature(mParams)
        r.1.append(("api_sig", r.0))
        r.1.append(("format", "json"))

        let urlEncoded = r.1.map { "\($0.0)=\($0.1.urlEncode())" }.joined(separator: "&")

        var request = URLRequest(url: URL(string: baseUrl)!)
        request.httpMethod = "POST"
        request.httpBody = urlEncoded.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded; charset=utf-8", forHTTPHeaderField: "Content-Type")

        let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
            if error != nil {
                log(error!.localizedDescription)
                //In case of error, won't do anything. The app will retry after to do the same request
            } else {
                let httpResponse = response! as! HTTPURLResponse
                callback(try! JSONSerialization.jsonObject(with: data!, options: JSONSerialization.ReadingOptions(rawValue: 0)), httpResponse.statusCode)
            }
        }

        task.resume()
    }

    private func getSignature(_ params: [String: String]) -> String {
        return md5Hex(params.sorted { (a, b) -> Bool in
            return a.key < b.key
        }.map { $0.key + $0.value }
        .reduce("") { (r, e) -> String in
            return r + e
        } + secret)
    }

    private func getSignature(_ params: [String: Any]) -> (String, [(String, String)]) {
        var sParams: [(String, String)] = []
        params.forEach {
            if $0.value is [Any] {
                let list = ($0.value as! [String?])
                var i = 0
                for v in list {
                    if let v = v { sParams.append(("\($0.key)[\(i)]", v)) }
                    i += 1
                }
            } else if $0.value is String {
                sParams.append(($0.key, ($0.value as! String)))
            } else {
                sParams.append(($0.key, String(describing: $0.value)))
            }
        }
        return (
            md5Hex(sParams.sorted { $0.0 < $1.0 }.map { $0.0 + $0.1 }.reduce("") { $0 + $1 } + secret),
            sParams
        )
    }

    //https://stackoverflow.com/questions/32163848/how-to-convert-string-to-md5-hash-using-ios-swift
    private func md5Hex(_ str: String) -> String {
        let data = str.data(using: .utf8)!
        var digestData = Data(count: Int(CC_MD5_DIGEST_LENGTH))
        _ = digestData.withUnsafeMutableBytes { digestBytes in
            return data.withUnsafeBytes({ (messageBytes) in
                return CC_MD5(messageBytes, CC_LONG(data.count), digestBytes)
            })
        }

        return digestData.map { String(format: "%02hhx", $0) }.joined()
    }

}
