//
//  AppleScript.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 08/10/2018.
//  Copyright © 2018 Melchor Garau Madrigal. All rights reserved.
//

import Foundation

class AppleScript {

    private let script: NSAppleScript
    private let lineRegex = try! NSRegularExpression(pattern: "^(\\w[a-z0-9_\\-]+): +(.+)$", options: .caseInsensitive)
    private let numberRegex = try! NSRegularExpression(pattern: "^\\d+([.,]\\d+(E\\d+)?)?$", options: .caseInsensitive)

    init(_ code: String) {
        self.script = NSAppleScript(source: code)!
    }

    func run() -> [String: Any] {
        return script.executeAndReturnError(nil).stringValue!
            .split(separator: "\n")
            .map { splitLine(String($0)) }
            .reduce(into: [:] as [String: Any]) { (res, line) in
                if line[2] == "null" {
                    res[line[1]] = nil
                } else if numberRegex.firstMatch(in: line[2], range: NSMakeRange(0, line[2].utf16.count)) != nil {
                    if line[2].contains(",") {
                        res[line[1]] = Double(line[2].replacingOccurrences(of: ",", with: "."))!
                    } else {
                        res[line[1]] = Double(line[2])!
                    }
                } else {
                    res[line[1]] = line[2]
                }
            }
    }

    private func splitLine(_ string: String) -> [String] {
        let matches = lineRegex.matches(in: string, range: NSMakeRange(0, string.utf16.count))
        let nsstr = (string as NSString)
        var res: [String] = []
        for i in 0..<matches[0].numberOfRanges {
            res.append(nsstr.substring(with: matches[0].range(at: i)))
        }
        return res
    }

}
