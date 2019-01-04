//
//  Logger.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 04/01/2019.
//  Copyright © 2019 Melchor Garau Madrigal. All rights reserved.
//

import Foundation

class Logger {

    private static var syslogInit = false
    private static var fileHandle: FileHandle? = nil
    private static var dateFormatter: DateFormatter! = nil
    private static let levelToString = [
        LOG_EMERG: "FATAL",
        LOG_ERR: "ERROR",
        LOG_WARNING: "WARNING",
        LOG_NOTICE: "NOTICE",
        LOG_INFO: "INFO",
        LOG_DEBUG: "DEBUG",
    ]

    private let category: String

    internal static func close() {
        if Logger.syslogInit {
            closelog()
            Logger.fileHandle?.closeFile()
        }
    }

    internal init(category: String) {
        if !Logger.syslogInit {
            openlog(Bundle.main.bundleIdentifier!, LOG_PERROR | LOG_PID, LOG_USER)
            Logger.syslogInit = true

            let logPath = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/iTunesScrobbler").path
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: logPath, isDirectory: &isDir) {
                try? FileManager.default.createDirectory(atPath: logPath, withIntermediateDirectories: true, attributes: nil)
                isDir = true
            }
            if !isDir.boolValue {
                try? FileManager.default.removeItem(atPath: logPath)
                try? FileManager.default.createDirectory(atPath: logPath, withIntermediateDirectories: false, attributes: nil)
            }

            Logger.dateFormatter = DateFormatter()
            Logger.dateFormatter.locale = Locale(identifier: "en_US_POSIX")
            Logger.dateFormatter.dateFormat = "yyyy.MM.dd"
            Logger.dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            //let startIndex = logPath.index(logPath.startIndex, offsetBy: 7)
            let logFilePath = "\(logPath)/iTunes Scrobbler.\(Logger.dateFormatter.string(from: Date())).log"
            if FileManager.default.fileExists(atPath: logFilePath) {
                Logger.fileHandle = FileHandle(forUpdatingAtPath: logFilePath)
                Logger.fileHandle?.seekToEndOfFile()
            } else {
                FileManager.default.createFile(atPath: logFilePath, contents: nil, attributes: nil)
                Logger.fileHandle = FileHandle(forWritingAtPath: logFilePath)
            }

            Logger.dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssZZZZ"
            Logger.fileHandle?.write("\n".data(using: .utf8)!)
            if Logger.fileHandle == nil {
                NSLog("Log file '\(logFilePath)' cannot be created or opened for writting, no logs will be written :(")
            }
        }

        self.category = category
    }

    internal func fatal(_ message: String) {
        doLog(LOG_EMERG, message)
    }

    internal func error(_ message: String) {
        doLog(LOG_ERR, message)
    }

    internal func warning(_ message: String) {
        doLog(LOG_WARNING, message)
    }

    internal func notice(_ message: String) {
        doLog(LOG_NOTICE, message)
    }

    internal func info(_ message: String) {
        doLog(LOG_INFO, message)
    }

    internal func debug(_ message: String) {
        doLog(LOG_DEBUG, message)
    }

    internal func doLog(_ type: Int32, _ message: String) {
        withVaList([]) { vsyslog(type, "[\(category)] \(message)", $0) }
        let now = Logger.dateFormatter.string(from: Date())
        let line = "\(now)\t[\(Logger.levelToString[type]!)]\t(\(category)): \(message)\n"
        Logger.fileHandle?.write(line.data(using: .utf8)!)
    }

}
