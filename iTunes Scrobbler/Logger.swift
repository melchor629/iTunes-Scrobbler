//
//  Logger.swift
//  iTunes Scrobbler
//
//  Created by Melchor Garau Madrigal on 04/01/2019.
//  Copyright © 2019 Melchor Garau Madrigal. All rights reserved.
//

import Foundation
import os

class Logger {

    private static var syslogInit = false
    private static var fileHandle: FileHandle? = nil
    private static var dateFormatter: ISO8601DateFormatter! = nil
    private static let levelToString = [
        LOG_EMERG: "FATAL",
        LOG_ERR: "ERROR",
        LOG_WARNING: "WARNING",
        LOG_NOTICE: "NOTICE",
        LOG_INFO: "INFO",
        LOG_DEBUG: "DEBUG",
    ]
    private static var timer: DispatchSourceTimer? = nil

    private let category: String
    private let logger: Any?

    internal static func close() {
        if Logger.syslogInit {
            closelog()
            Logger.fileHandle?.closeFile()
            Logger.timer?.setEventHandler {}
            Logger.timer?.cancel()
        }
    }

    internal init(category: String) {
        if #available(OSX 11.0, *) {
            logger = os.Logger(subsystem: "me.melchor9000.iTunes-Scrobbler", category: category)
        } else {
            logger = nil
        }

        if !Logger.syslogInit {
            if logger == nil {
                openlog(Bundle.main.bundleIdentifier!, LOG_PERROR | LOG_PID, LOG_USER)
            }

            Logger.syslogInit = true
            Logger.fileHandle = Logger.openLogFileHandle()
            Logger.setUpLogRotating()

            Logger.dateFormatter = ISO8601DateFormatter()
            Logger.dateFormatter.timeZone = TimeZone(secondsFromGMT: 0)
            Logger.fileHandle?.write("\n".data(using: .utf8)!)
            if Logger.fileHandle == nil {
                NSLog("Log file cannot be created or opened for writting, no logs will be written :(")
            }
        }

        self.category = category
    }

    private static func openLogFileHandle() -> FileHandle? {
        let logPath = FileManager.default
            .homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Logs/iTunesScrobbler")
            .path
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: logPath, isDirectory: &isDir) {
            try? FileManager.default.createDirectory(atPath: logPath,
                                                     withIntermediateDirectories: true,
                                                     attributes: nil)
            isDir = true
        }
        if !isDir.boolValue {
            try? FileManager.default.removeItem(atPath: logPath)
            try? FileManager.default.createDirectory(atPath: logPath,
                                                     withIntermediateDirectories: false,
                                                     attributes: nil)
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy.MM.dd"
        dateFormatter.timeZone = TimeZone.current
        let logFilePath = "\(logPath)/iTunes Scrobbler.\(dateFormatter.string(from: Date())).log"
        if FileManager.default.fileExists(atPath: logFilePath) {
            let fileHandle = FileHandle(forUpdatingAtPath: logFilePath)
            fileHandle?.seekToEndOfFile()
            return fileHandle
        } else {
            FileManager.default.createFile(atPath: logFilePath,
                                           contents: nil,
                                           attributes: nil)
            return FileHandle(forWritingAtPath: logFilePath)
        }
    }

    private static func setUpLogRotating() {
        // get time until tomorrow
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone.current
        let startOfToday = calendar.startOfDay(for: Date())
        let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday)
        let diff = startOfTomorrow!.timeIntervalSince(Date())

        // create timer
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline: .now() + diff, repeating: .seconds(24 * 60 * 60))
        timer.setEventHandler {
            if let newLogFile = Logger.openLogFileHandle() {
                Logger.fileHandle?.closeFile()
                Logger.fileHandle = newLogFile
            }
        }

        // start timer
        timer.resume()
        Logger.timer = timer
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
        if #available(OSX 11.0, *) {
            let l = (logger! as! os.Logger)
            switch type {
            case LOG_EMERG:
                l.fault("\(message, privacy: .public)")
            case LOG_ERR:
                l.error("\(message, privacy: .public)")
            case LOG_WARNING:
                l.warning("\(message, privacy: .public)")
            case LOG_NOTICE:
                l.notice("\(message, privacy: .public)")
            case LOG_INFO:
                l.info("\(message, privacy: .public)")
            case LOG_DEBUG:
                l.debug("\(message, privacy: .public)")
            default:
                l.log("\(message, privacy: .public)")
            }
        } else {
            #if arch(x86_64)
            withVaList([]) { vsyslog(type, "[\(category)] \(message)", $0) }
            #else
            // this should never happen: ARM support for macOS is in 11.0 or higher
            #endif
        }

        if let fileHandle = Logger.fileHandle {
            let now = Logger.dateFormatter.string(from: Date())
            let line = "\(now)\t[\(Logger.levelToString[type]!)]\t(\(category)): \(message)\n"
            fileHandle.write(line.data(using: .utf8)!)
        }
    }

}
